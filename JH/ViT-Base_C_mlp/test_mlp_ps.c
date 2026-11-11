/* test_mlp_ps.c - x86 test of the MLP PS work (no board).  JH, 2026-11-10
 *
 * build : gcc -O2 -std=gnu11 -Wall -Wextra -ffp-contract=off -o test_mlp_ps \
 *             test_mlp_ps.c mlp_ps.c mlp_ops.c attn_ops.c mxfp4.c -lm
 * run   : ./test_mlp_ps --data DIR [--eps E]       DIR = vit_golden_gen.py output (40 files + meta.json)
 *
 *  T1 LN2      : r_golden -> ps_ln2_mx            == x2_fp4 / x2_scale
 *  T2 H quant  : g_golden 48 tiles -> ps_mx_g     == h4_fp4 / h4_scale
 *  T3 FC2 acc  : p_golden -> ps_fc2_acc           == y2_golden
 *  T4 Resid 2  : r_golden + y2_golden -> ps_residual == r2_golden
 *  T5 faults   : one flipped input bit per test must make the result differ
 * eps : meta.json "layer_norm_eps" (mlp_files_load) unless --eps is given.
 */
#include "mlp_ops.h"
#include "mxfp4.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>

/* ---- the flow functions in attn_ops.c / mlp_ops.c need these; the PS test never calls them ---- */
int hw_stop_requested(void) { return 1; }
int hw_cmd_run(hw_ctx *h, uint64_t cmd) { (void)h; (void)cmd; return -1; }
int hw_bb_gold_load(hw_ctx *h, const uint8_t *l, uint32_t n) { (void)h; (void)l; (void)n; return -1; }
int hw_bb_run(hw_ctx *h, uint32_t a, uint32_t b, uint32_t c, uint32_t d, uint32_t e, uint32_t f, int g, uint32_t *y)
{ (void)h; (void)a; (void)b; (void)c; (void)d; (void)e; (void)f; (void)g; (void)y; return -1; }
int hw_bb2_gold_load(hw_ctx *h, const uint8_t *l, uint32_t n) { (void)h; (void)l; (void)n; return -1; }
int hw_bb2_run_store(hw_ctx *h, uint32_t a, uint32_t b, uint32_t c, uint32_t d, uint32_t e, int f, uint32_t *y)
{ (void)h; (void)a; (void)b; (void)c; (void)d; (void)e; (void)f; (void)y; return -1; }

/* ---- helpers ------------------------------------------------------------------------------------ */
static double now_ms(void) { return 1e3 * (double)clock() / CLOCKS_PER_SEC; }

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

/* FP4 code bytes : token-major, 384 B per token (x.bin layout) */
static void where_fp4(const char *tag, const uint8_t *got, const uint8_t *exp, size_t i)
{
    size_t t = (i % LB(X_LINES)) / 384, e = (i % 384) * 2;
    printf("        %s first: plane %zu token %zu elements %zu,%zu  got 0x%02X exp 0x%02X (line %zu)\n",
           tag, i / LB(X_LINES), t, e, e + 1, got[i], exp[i], (i % LB(X_LINES)) / 32);
}
static void where_scale(const char *tag, const uint8_t *got, const uint8_t *exp, size_t i)
{
    printf("        %s first: plane %zu token %zu block %zu  got %u exp %u\n", tag, i / X2_SCALES,
           (i % X2_SCALES) / 24, i % 24, got[i], exp[i]);
}
/* BF16 tiles of 788 lines : tile, token, column */
static void where_tile(const char *tag, const uint8_t *got, const uint8_t *exp, size_t i)
{
    size_t tile = i / LB(Y2_LINES), r = i % LB(Y2_LINES);
    printf("        %s first: tile %zu token %zu col %zu  got %.6g (0x%04X) exp %.6g (0x%04X)\n", tag, tile,
           r / 128, 64 * tile + (r % 128) / 2, bf16_to_d(rd_bf16(got + i)), rd_bf16(got + i),
           bf16_to_d(rd_bf16(exp + i)), rd_bf16(exp + i));
}
static void where_res(const char *tag, const uint8_t *got, const uint8_t *exp, size_t i)
{
    printf("        %s first: token %zu col %zu  got %.6g (0x%04X) exp %.6g (0x%04X)\n", tag, i / 1536, (i % 1536) / 2,
           bf16_to_d(rd_bf16(got + i)), rd_bf16(got + i), bf16_to_d(rd_bf16(exp + i)), rd_bf16(exp + i));
}

/* index (bytes) of the largest |BF16| among n values at p, stride 2 */
static size_t argmax_bf16(const uint8_t *p, size_t nbytes)
{
    size_t best = 0;
    double m = -1;
    for (size_t i = 0; i < nbytes; i += 2) {
        double v = fabs(bf16_to_d(rd_bf16(p + i)));
        if (v > m) { m = v; best = i; }
    }
    return best;
}

/* ---- the four computations (also used by T5) -------------------------------------------------- */
static int run_t1(const uint8_t *r, const mlp_files *f, double eps, uint8_t *x2, uint8_t *x2s)
{ return ps_ln2_mx(r, f->ln2_w, f->ln2_b, eps, x2, x2s); }

static int run_t2(const uint8_t *g, uint8_t *h4, uint8_t *h4s)
{
    for (int j = 0; j < (int)FC1_TILES; j++)
        if (ps_mx_g(g + h_off(j, 0), j, h4, h4s)) return -1;
    return 0;
}

static void run_t3(const uint8_t *p, const float *b2, float *acc, uint8_t *y2)
{
    for (int n = 0; n < (int)FC2_TILES; n++)
        for (int k = 0; k < (int)FC2_K; k++)
            ps_fc2_acc(acc, p + p_off(n, k, 0), k, b2 + 64 * n, y2 + y2_off(n, 0));
}

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

    attn_files af;
    mlp_files mf;
    if (attn_files_load(dir, &af)) return 1;
    if (mlp_files_load(dir, &mf)) { attn_files_free(&af); return 1; }
    if (eps < 0) eps = mf.eps;

    size_t n_x2 = LB(X2_LINES), n_h4 = LB(H4_LINES) * FC2_K, n_h4s = (size_t)H4_SCALES * FC2_K;
    size_t n_y2 = LB(Y2_LINES) * FC2_TILES, n_g = LB(H_LINES) * FC1_TILES, n_p = LB(P_LINES) * FC2_CALLS;
    uint8_t *x2 = malloc(n_x2), *x2s = malloc(X2_SCALES), *h4 = malloc(n_h4), *h4s = malloc(n_h4s);
    uint8_t *y2 = malloc(n_y2), *r2 = malloc(RES_BYTES), *rr = malloc(RES_BYTES), *gg = malloc(n_g), *pp = malloc(n_p);
    float *acc = malloc(sizeof(float) * H_TILE_ELEMS);
    if (!x2 || !x2s || !h4 || !h4s || !y2 || !r2 || !rr || !gg || !pp || !acc) { fprintf(stderr, "malloc\n"); return 1; }

    puts("==========================================================================");
    puts("  test_mlp_ps | MLP PS work vs vit_golden_gen.py (x86, no board)");
    puts("==========================================================================");
    printf("  Data : %s   eps = %.17g\n", dir, eps);
    size_t bad, at;
    double t;

    /* T1 */
    memset(x2, 0xA5, n_x2); memset(x2s, 0xA5, X2_SCALES);
    t = now_ms();
    int rc = run_t1(af.r, &mf, eps, x2, x2s);
    t = now_ms() - t;
    bad = rc ? n_x2 : first_diff(x2, mf.x2, n_x2, 1, &at);
    result("T1 LN2 MXFP4 == x2_fp4.bin", n_x2, "bytes", bad, t);
    if (bad && !rc) where_fp4("x2", x2, mf.x2, at);
    bad = rc ? X2_SCALES : first_diff(x2s, mf.x2s, X2_SCALES, 1, &at);
    result("T1 LN2 scale == x2_scale.bin", X2_SCALES, "bytes", bad, 0);
    if (bad && !rc) where_scale("x2s", x2s, mf.x2s, at);

    /* T2 */
    memset(h4, 0xA5, n_h4); memset(h4s, 0xA5, n_h4s);
    t = now_ms();
    rc = run_t2(mf.g, h4, h4s);
    t = now_ms() - t;
    bad = rc ? n_h4 : first_diff(h4, mf.h4, n_h4, 1, &at);
    result("T2 G -> H4 MXFP4 == h4_fp4.bin (48 tiles)", n_h4, "bytes", bad, t);
    if (bad && !rc) where_fp4("h4", h4, mf.h4, at);
    bad = rc ? n_h4s : first_diff(h4s, mf.h4s, n_h4s, 1, &at);
    result("T2 H4 scale == h4_scale.bin", n_h4s, "bytes", bad, 0);
    if (bad && !rc) where_scale("h4s", h4s, mf.h4s, at);

    /* T3 */
    memset(y2, 0xA5, n_y2);
    t = now_ms();
    run_t3(mf.p, mf.b2, acc, y2);
    t = now_ms() - t;
    bad = first_diff(y2, mf.y2, n_y2, 2, &at);
    result("T3 FC2 accumulate == y2_golden.bin", n_y2 / 2, "BF16", bad, t);
    if (bad) where_tile("y2", y2, mf.y2, at);

    /* T4 */
    memset(r2, 0xA5, RES_BYTES);
    t = now_ms();
    ps_residual(af.r, mf.y2, r2);
    t = now_ms() - t;
    bad = first_diff(r2, mf.r2, RES_BYTES, 2, &at);
    result("T4 R2 = R + Y2 == r2_golden.bin", RES_BYTES / 2, "BF16", bad, t);
    if (bad) where_res("r2", r2, mf.r2, at);

    /* T5 : flip the sign bit of the largest |value| in one place; the result must change */
    puts("  T5 fault detection (one input bit flipped -> mismatch expected)");
    size_t i5;
    memcpy(rr, af.r, RES_BYTES);
    i5 = 5 * 1536 + argmax_bf16(rr + 5 * 1536, 1536);
    rr[i5 + 1] ^= 0x80;
    run_t1(rr, &mf, eps, x2, x2s);
    bad = first_diff(x2, mf.x2, n_x2, 1, &at) + first_diff(x2s, mf.x2s, X2_SCALES, 1, &at);
    result("T5a R token 5 sign bit -> X2 differs", 1, "flip", bad ? 0 : 1, 0);

    memcpy(gg, mf.g, n_g);
    i5 = h_off(3, 0) + argmax_bf16(gg + h_off(3, 0), LB(H_LINES));
    gg[i5 + 1] ^= 0x80;
    run_t2(gg, h4, h4s);
    bad = first_diff(h4, mf.h4, n_h4, 1, &at) + first_diff(h4s, mf.h4s, n_h4s, 1, &at);
    result("T5b G tile 3 sign bit -> H4 differs", 1, "flip", bad ? 0 : 1, 0);

    memcpy(pp, mf.p, n_p);
    i5 = p_off(2, 1, 0) + argmax_bf16(pp + p_off(2, 1, 0), LB(P_LINES));
    pp[i5 + 1] ^= 0x80;
    run_t3(pp, mf.b2, acc, y2);
    bad = first_diff(y2, mf.y2, n_y2, 2, &at);
    result("T5c partial (2,1) sign bit -> Y2 differs", 1, "flip", bad ? 0 : 1, 0);

    memcpy(y2, mf.y2, n_y2);
    i5 = y2_off(7, 0) + argmax_bf16(y2 + y2_off(7, 0), LB(Y2_LINES));
    y2[i5 + 1] ^= 0x80;
    ps_residual(af.r, y2, r2);
    bad = first_diff(r2, mf.r2, RES_BYTES, 2, &at);
    result("T5d Y2 tile 7 sign bit -> R2 differs", 1, "flip", bad ? 0 : 1, 0);

    float g0 = mf.ln2_w[100];
    mf.ln2_w[100] = -g0;
    run_t1(af.r, &mf, eps, x2, x2s);
    mf.ln2_w[100] = g0;
    bad = first_diff(x2, mf.x2, n_x2, 1, &at) + first_diff(x2s, mf.x2s, X2_SCALES, 1, &at);
    result("T5e LN2 gamma[100] sign bit -> X2 differs", 1, "flip", bad ? 0 : 1, 0);

    puts("--------------------------------------------------------------------------");
    free(x2); free(x2s); free(h4); free(h4s); free(y2); free(r2); free(rr); free(gg); free(pp); free(acc);
    mlp_files_free(&mf);
    attn_files_free(&af);
    printf("%s (errors=%d)\n", g_errors ? "FAIL" : "PASS", g_errors);
    return g_errors ? 1 : 0;
}
