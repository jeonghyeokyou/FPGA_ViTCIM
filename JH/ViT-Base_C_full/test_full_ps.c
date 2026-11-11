/* test_full_ps.c - x86 / aarch64 test of the PS work before / after the 12 layers (no board).  JH, 2026-11-11
 *
 * build : make test_full_ps      (full_ps.c, mlp_ps.c with -ffp-contract=off)
 * run   : ./test_full_ps --data DIR [--eps E]     DIR = vit_golden_gen.py --full output (embed/ l00..l11/ head/)
 *
 *  T1 embed  : embed/pixels, patch_w, patch_b, cls, pos -> ps_embed          == embed/h0_golden
 *  T2 LN1    : lXX/h_in + ln1_w / ln1_b -> ps_ln2_mx (12 layers)            == lXX/x.bin , x_scale.bin
 *  T3 LN_f   : l11/r2_golden token 0 (CLS) -> ps_ln_bf16                    == head/lnc_golden
 *  T4 head   : head/lnc_golden -> ps_head                                   == head/logits_golden (bit-exact), top-1
 *  T5 faults : one flipped input bit per test must make the result differ
 * eps : DIR/meta.json "layer_norm_eps" unless --eps is given.
 */
#include "full_ps.h"
#include "mlp_ops.h"
#include "mxfp4.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>

/* ---- the flow functions in attn_ops.c need these; the PS test never calls them ------------------ */
int hw_stop_requested(void) { return 1; }
int hw_cmd_run(hw_ctx *h, uint64_t cmd) { (void)h; (void)cmd; return -1; }
int hw_bb_gold_load(hw_ctx *h, const uint8_t *l, uint32_t n) { (void)h; (void)l; (void)n; return -1; }
int hw_bb_run(hw_ctx *h, uint32_t a, uint32_t b, uint32_t c, uint32_t d, uint32_t e, uint32_t f, int g, uint32_t *y)
{ (void)h; (void)a; (void)b; (void)c; (void)d; (void)e; (void)f; (void)g; (void)y; return -1; }
int hw_bb2_gold_load(hw_ctx *h, const uint8_t *l, uint32_t n) { (void)h; (void)l; (void)n; return -1; }
int hw_bb2_run_store(hw_ctx *h, uint32_t a, uint32_t b, uint32_t c, uint32_t d, uint32_t e, int f, uint32_t *y)
{ (void)h; (void)a; (void)b; (void)c; (void)d; (void)e; (void)f; (void)y; return -1; }

#define N_LAYERS 12

/* ---- helpers ------------------------------------------------------------------------------------ */
static double now_ms(void) { return 1e3 * (double)clock() / CLOCKS_PER_SEC; }

static void *load(const char *dir, const char *sub, const char *name, size_t expect)
{
    char path[1024];
    snprintf(path, sizeof path, "%s/%s/%s", dir, sub, name);
    FILE *fp = fopen(path, "rb");
    if (!fp) { fprintf(stderr, "open %s failed\n", path); exit(1); }
    uint8_t *p = malloc(expect + 1);
    size_t n = p ? fread(p, 1, expect + 1, fp) : 0;
    fclose(fp);
    if (!p || n != expect) { fprintf(stderr, "%s: %zu bytes, expected %zu\n", path, n, expect); exit(1); }
    return p;
}

static double meta_eps(const char *dir)
{
    char path[1024], buf[512];
    snprintf(path, sizeof path, "%s/meta.json", dir);
    FILE *fp = fopen(path, "rb");
    double eps = -1;
    if (!fp) return eps;
    while (fgets(buf, sizeof buf, fp)) {
        char *k = strstr(buf, "\"layer_norm_eps\"");
        if (k && (k = strchr(k, ':'))) { eps = strtod(k + 1, NULL); break; }
    }
    fclose(fp);
    return eps;
}

static size_t first_diff(const uint8_t *got, const uint8_t *exp, size_t n, size_t unit, size_t *first)
{
    size_t bad = 0;
    *first = (size_t)-1;
    for (size_t i = 0; i < n; i += unit)
        if (memcmp(got + i, exp + i, unit)) { if (!bad) *first = i; bad++; }
    return bad;
}

static int g_errors;
static void result(const char *name, size_t checked, const char *unit, size_t bad, double ms)
{
    printf("  [%s] %-44s %8zu %-6s mismatch %-6zu %8.2f ms\n", bad ? "FAIL" : "PASS", name, checked, unit, bad, ms);
    if (bad) g_errors++;
}

static void where_bf16(const char *tag, const uint8_t *got, const uint8_t *exp, size_t i)
{
    printf("        %s first: token %zu col %zu  got %.6g (0x%04X) exp %.6g (0x%04X)\n", tag, i / 1536, (i % 1536) / 2,
           bf16_to_d(rd_bf16(got + i)), rd_bf16(got + i), bf16_to_d(rd_bf16(exp + i)), rd_bf16(exp + i));
}

/* index of the largest |value| */
static size_t argmax_abs_bf16(const uint8_t *p, size_t n)
{
    size_t best = 0;
    for (size_t i = 1; i < n; i++)
        if (fabs(bf16_to_d(rd_bf16(p + 2 * i))) > fabs(bf16_to_d(rd_bf16(p + 2 * best)))) best = i;
    return best;
}
static size_t argmax_abs_f32(const float *p, size_t n)
{
    size_t best = 0;
    for (size_t i = 1; i < n; i++)
        if (fabsf(p[i]) > fabsf(p[best])) best = i;
    return best;
}
static void flip_sign_f32(float *p) { uint32_t u; memcpy(&u, p, 4); u ^= 0x80000000u; memcpy(p, &u, 4); }

typedef struct { uint8_t *h_in, *x, *xs; float *w, *b; } layer_in;

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    const char *dir = NULL;
    double eps = -1;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--data") && i + 1 < argc) dir = argv[++i];
        else if (!strcmp(argv[i], "--eps") && i + 1 < argc) eps = strtod(argv[++i], NULL);
        else { fprintf(stderr, "usage: %s --data DIR [--eps E]\n", argv[0]); return 1; }
    }
    if (!dir) { fprintf(stderr, "usage: %s --data DIR [--eps E]\n", argv[0]); return 1; }
    if (eps < 0) eps = meta_eps(dir);
    if (eps < 0) { fprintf(stderr, "%s/meta.json: no layer_norm_eps (use --eps)\n", dir); return 1; }

    const size_t D = VIT_DMODEL, HB = RES_BYTES;                 /* h0 / h_in / r2 : [197][768] BF16 */
    float *px  = load(dir, "embed", "pixels.bin", 4 * PIXELS_FLOATS);
    float *pw  = load(dir, "embed", "patch_w.bin", 4 * D * D);
    float *pb  = load(dir, "embed", "patch_b.bin", 4 * D);
    float *cls = load(dir, "embed", "cls.bin", 4 * D);
    float *pos = load(dir, "embed", "pos.bin", 4 * VIT_TOKENS * D);
    uint8_t *h0g = load(dir, "embed", "h0_golden.bin", HB);
    layer_in L[N_LAYERS];
    for (int l = 0; l < N_LAYERS; l++) {
        char sub[8];
        snprintf(sub, sizeof sub, "l%02d", l);
        L[l].h_in = load(dir, sub, "h_in.bin", HB);
        L[l].x = load(dir, sub, "x.bin", LB(X_LINES));
        L[l].xs = load(dir, sub, "x_scale.bin", X2_SCALES);
        L[l].w = load(dir, sub, "ln1_w.bin", 4 * D);
        L[l].b = load(dir, sub, "ln1_b.bin", 4 * D);
    }
    uint8_t *r2_last = load(dir, "l11", "r2_golden.bin", HB);
    float *lnf_w = load(dir, "head", "lnf_w.bin", 4 * D);
    float *lnf_b = load(dir, "head", "lnf_b.bin", 4 * D);
    float *hw    = load(dir, "head", "head_w.bin", 4 * (size_t)FULL_NCLASS * D);
    float *hb    = load(dir, "head", "head_b.bin", 4 * (size_t)FULL_NCLASS);
    uint8_t *lncg = load(dir, "head", "lnc_golden.bin", 2 * D);
    float *lgg   = load(dir, "head", "logits_golden.bin", 4 * (size_t)FULL_NCLASS);

    uint8_t *h0 = malloc(HB), *x = malloc(LB(X_LINES)), *xs = malloc(X2_SCALES), *hh = malloc(HB), *lnc = malloc(2 * D);
    float *lg = malloc(4 * (size_t)FULL_NCLASS);
    if (!h0 || !x || !xs || !hh || !lnc || !lg) { fprintf(stderr, "malloc\n"); return 1; }

    puts("==========================================================================");
    puts("  test_full_ps | embed / LN1 x12 / final LN / head vs vit_golden_gen.py --full (no board)");
    puts("==========================================================================");
    printf("  Data : %s   eps = %.17g\n", dir, eps);
    size_t bad, at;
    double t;

    /* T1 */
    memset(h0, 0xA5, HB);
    t = now_ms();
    ps_embed(px, pw, pb, cls, pos, h0);
    t = now_ms() - t;
    bad = first_diff(h0, h0g, HB, 2, &at);
    result("T1 embed == h0_golden.bin", HB / 2, "BF16", bad, t);
    if (bad) where_bf16("h0", h0, h0g, at);

    /* T2 */
    for (int l = 0; l < N_LAYERS; l++) {
        char name[64];
        memset(x, 0xA5, LB(X_LINES)); memset(xs, 0xA5, X2_SCALES);
        t = now_ms();
        int rc = ps_ln2_mx(L[l].h_in, L[l].w, L[l].b, eps, x, xs);
        t = now_ms() - t;
        bad = rc ? 1 : first_diff(x, L[l].x, LB(X_LINES), 1, &at) + first_diff(xs, L[l].xs, X2_SCALES, 1, &at);
        snprintf(name, sizeof name, "T2 LN1 l%02d == x.bin + x_scale.bin", l);
        result(name, LB(X_LINES) + X2_SCALES, "bytes", bad, t);
    }

    /* T3 */
    memset(lnc, 0xA5, 2 * D);
    t = now_ms();
    ps_ln_bf16(r2_last, lnf_w, lnf_b, eps, lnc);
    t = now_ms() - t;
    bad = first_diff(lnc, lncg, 2 * D, 2, &at);
    result("T3 final LN (l11 R2 CLS) == lnc_golden.bin", D, "BF16", bad, t);
    if (bad) where_bf16("lnc", lnc, lncg, at);

    /* T4 */
    memset(lg, 0xA5, 4 * (size_t)FULL_NCLASS);
    t = now_ms();
    ps_head(lncg, hw, hb, FULL_NCLASS, lg);
    t = now_ms() - t;
    bad = first_diff((const uint8_t *)lg, (const uint8_t *)lgg, 4 * (size_t)FULL_NCLASS, 4, &at);
    result("T4 head == logits_golden.bin (bit-exact)", FULL_NCLASS, "f32", bad, t);
    if (bad) printf("        logits first: class %zu  got %.9g exp %.9g\n", at / 4, lg[at / 4], lgg[at / 4]);
    int top = ps_top1(lg, FULL_NCLASS), topg = ps_top1(lgg, FULL_NCLASS);
    result("T4 top-1 == argmax(logits_golden)", 1, "index", top != topg, 0);
    printf("        top-1 = %d (logit %.6g)\n", top, lg[top]);

    /* T5 : flip one sign bit (of the largest |value|) per input; the result must change */
    puts("  T5 fault detection (one input bit flipped -> mismatch expected)");
    size_t i5 = argmax_abs_f32(px, PIXELS_FLOATS);
    flip_sign_f32(&px[i5]);
    ps_embed(px, pw, pb, cls, pos, h0);
    flip_sign_f32(&px[i5]);
    bad = first_diff(h0, h0g, HB, 2, &at);
    result("T5a pixel sign bit -> h0 differs", 1, "flip", bad ? 0 : 1, 0);

    memcpy(hh, L[5].h_in, HB);
    i5 = 5 * D + argmax_abs_bf16(hh + 5 * D * 2, D);
    hh[2 * i5 + 1] ^= 0x80;
    ps_ln2_mx(hh, L[5].w, L[5].b, eps, x, xs);
    bad = first_diff(x, L[5].x, LB(X_LINES), 1, &at) + first_diff(xs, L[5].xs, X2_SCALES, 1, &at);
    result("T5b l05 h_in token 5 sign bit -> x differs", 1, "flip", bad ? 0 : 1, 0);

    flip_sign_f32(&lnf_w[100]);
    ps_ln_bf16(r2_last, lnf_w, lnf_b, eps, lnc);
    flip_sign_f32(&lnf_w[100]);
    bad = first_diff(lnc, lncg, 2 * D, 2, &at);
    result("T5c final LN gamma[100] sign bit -> lnc differs", 1, "flip", bad ? 0 : 1, 0);

    i5 = (size_t)topg * D + argmax_abs_f32(hw + (size_t)topg * D, D);
    flip_sign_f32(&hw[i5]);
    ps_head(lncg, hw, hb, FULL_NCLASS, lg);
    flip_sign_f32(&hw[i5]);
    bad = first_diff((const uint8_t *)lg, (const uint8_t *)lgg, 4 * (size_t)FULL_NCLASS, 4, &at);
    result("T5d head W[top-1] sign bit -> logits differ", 1, "flip", bad ? 0 : 1, 0);

    puts("--------------------------------------------------------------------------");
    for (int l = 0; l < N_LAYERS; l++) { free(L[l].h_in); free(L[l].x); free(L[l].xs); free(L[l].w); free(L[l].b); }
    free(px); free(pw); free(pb); free(cls); free(pos); free(h0g); free(r2_last);
    free(lnf_w); free(lnf_b); free(hw); free(hb); free(lncg); free(lgg);
    free(h0); free(x); free(xs); free(hh); free(lnc); free(lg);
    printf("%s (errors=%d)\n", g_errors ? "FAIL" : "PASS", g_errors);
    return g_errors ? 1 : 0;
}
