/* vit_full.c - ViT-Base image -> patch embedding -> layers 0..N-1 -> final LN -> head (blackbox = Golden).
 * JH, 2026-11-11 (VIT_FULL_TASK.md 6.1)
 *
 * build : make OUT=.            (vit_full: full_ps.c + mlp_ps.c with -ffp-contract=off, layer_run.c)
 * run   : sudo ./vit_full --data DIR [--layers N(1..12)] [--inject r2:L] [--inject headw]
 *           DIR      : vit_golden_gen.py --full output (meta.json, embed/, l00..l11/, head/)
 *           --layers : layers 0..N-1 (default 12); the head runs only for N = 12
 *           --inject : fault test (verification only, not part of the flow)
 *                        r2:L  : sign bit of the largest |R2| of layer L flipped before its checks
 *                        headw : sign bit of the largest |W| in the Golden top-1 row of head_w.bin
 *
 * Flow (each layer: its files are read, used and freed before the next)
 *   PS  embed            h0 = ps_embed(pixels)                       check h0 == embed/h0_golden
 *   layer l              check h_l == lXX/h_in.bin
 *     PS  LN1            x_l = ps_ln2_mx(h_l, ln1_w, ln1_b)           check x_l == x.bin, x_scale.bin
 *     PL  layer_run      attention + MLP (same commands as vit_main --mlp)  layer_check (23 checks)
 *                        h_{l+1} = R2_l
 *   PS  final LN + head  lnc = ps_ln_bf16(h_12[CLS]), logits = ps_head    check lnc, logits (bit-exact), top-1
 * Last line : BOARD_RESULT=PASS|FAIL op=full layers=N top1=<idx>
 */
#define _POSIX_C_SOURCE 200809L
#include "layer_run.h"
#include "full_ps.h"
#include "mxfp4.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include <math.h>
#ifdef _WIN32
#define PSAPI_VERSION 2
#include <windows.h>
#include <psapi.h>
#else
#include <sys/resource.h>
#endif

#define N_LAYERS 12

/* ---- files ------------------------------------------------------------------------------------- */
static void *read_sub(const char *dir, const char *sub, const char *name, size_t expect)
{
    char path[1024];
    snprintf(path, sizeof path, "%s/%s/%s", dir, sub, name);
    FILE *fp = fopen(path, "rb");
    if (!fp) { fprintf(stderr, "open %s failed\n", path); return NULL; }
    uint8_t *p = malloc(expect + 1);
    size_t n = p ? fread(p, 1, expect + 1, fp) : 0;
    fclose(fp);
    if (!p || n != expect) { fprintf(stderr, "%s: %zu bytes, expected %zu\n", path, n, expect); free(p); return NULL; }
    return p;
}

/* class name : line idx of the "id2label" list in DIR/meta.json (json.dump indent=1 : one label per line) */
static void class_name(const char *dir, int idx, char *out, size_t n)
{
    char path[1024], buf[512];
    snprintf(out, n, "?");
    snprintf(path, sizeof path, "%s/meta.json", dir);
    FILE *fp = fopen(path, "rb");
    if (!fp) return;
    int in = 0, k = 0;
    while (fgets(buf, sizeof buf, fp)) {
        if (!in) { in = strstr(buf, "\"id2label\": [") != NULL; continue; }
        if (k++ == idx) {
            char *a = strchr(buf, '"'), *b = strrchr(buf, '"');
            if (a && b > a) { size_t m = (size_t)(b - a - 1) < n - 1 ? (size_t)(b - a - 1) : n - 1; memcpy(out, a + 1, m); out[m] = 0; }
            break;
        }
    }
    fclose(fp);
}

static double peak_mem_mb(void)
{
#ifdef _WIN32
    PROCESS_MEMORY_COUNTERS pmc;
    if (GetProcessMemoryInfo(GetCurrentProcess(), &pmc, sizeof pmc)) return (double)pmc.PeakWorkingSetSize / 1048576.0;
    return -1;
#else
    struct rusage ru;
    if (getrusage(RUSAGE_SELF, &ru) == 0) return (double)ru.ru_maxrss / 1024.0;   /* KiB on Linux */
    return -1;
#endif
}

/* ---- checks ------------------------------------------------------------------------------------ */
static size_t g_bad;
static int g_n;
static size_t check(int quiet, const char *what, const void *got, const void *exp, size_t n, size_t unit, const char *uname)
{
    size_t bad = 0;
    for (size_t i = 0; i < n; i += unit)
        if (memcmp((const uint8_t *)got + i, (const uint8_t *)exp + i, unit)) bad++;
    if (!quiet || bad)
        printf("  [%s] %-44s %7zu %-5s | mismatch %zu\n", bad ? "FAIL" : "PASS", what, n / unit, uname, bad);
    g_bad += bad;
    g_n++;
    return bad;
}

static void flip_sign_bf16(uint8_t *p, size_t nvals)
{
    size_t best = 0;
    for (size_t i = 1; i < nvals; i++)
        if (fabs(bf16_to_d(rd_bf16(p + 2 * i))) > fabs(bf16_to_d(rd_bf16(p + 2 * best)))) best = i;
    p[2 * best + 1] ^= 0x80;
}

static void usage(const char *a0)
{
    fprintf(stderr, "usage: sudo %s --data DIR [--layers N(1..12)] [--inject r2:L] [--inject headw]\n", a0);
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    const char *dir = NULL;
    int nl = N_LAYERS, inj_r2 = -1, inj_headw = 0;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--data") && i + 1 < argc) dir = argv[++i];
        else if (!strcmp(argv[i], "--layers") && i + 1 < argc) nl = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--inject") && i + 1 < argc) {
            const char *s = argv[++i];
            if (!strncmp(s, "r2:", 3)) inj_r2 = atoi(s + 3);
            else if (!strcmp(s, "headw")) inj_headw = 1;
            else { usage(argv[0]); return 1; }
        }
        else { usage(argv[0]); return 1; }
    }
    if (!dir || nl < 1 || nl > N_LAYERS || inj_r2 >= nl) { usage(argv[0]); return 1; }

    int rc = 1, top1 = -1, run_failed = 0;
    hw_ctx hw;
    layer_ctx x;
    memset(&hw, 0, sizeof hw);
    memset(&x, 0, sizeof x);
    hw.fd_mem = -1;
    x.wr.fd = x.rb.fd = x.pb.fd = -1;
    const size_t D = VIT_DMODEL;
    uint8_t *h = malloc(RES_BYTES), *x4 = malloc(X_BYTES), *x4s = malloc(X2_SCALES), *lnc = malloc(2 * D);
    float *lg = malloc(4 * (size_t)FULL_NCLASS);
    struct { double load, ln1, run, check, wall; unsigned long cmd, bb, dma; size_t bad; int n; } per[N_LAYERS];
    memset(per, 0, sizeof per);
    if (!h || !x4 || !x4s || !lnc || !lg) { fprintf(stderr, "malloc\n"); goto out; }

    if (hw_open(&hw)) goto out;
    if (layer_ctx_init(&x, &hw)) goto out;
    x.quiet = 1;

    puts("==========================================================================");
    puts("  ZCU102 | ViT-Base image -> embed -> layers -> head | MXFP4 | blackbox = Golden");
    puts("==========================================================================");
    printf("  PL0 clock   : %" PRIu64 " Hz (Linux clk_summary)\n", hw.pl0_hz);
    printf("  Layers      : 0..%d%s   Mode: sequential (one operation at a time)\n", nl - 1, nl < N_LAYERS ? " (head skipped)" : "");
    printf("  Data        : %s\n", dir);
    if (inj_r2 >= 0) printf("  INJECT      : layer %d R2, sign bit of the largest |value|\n", inj_r2);
    if (inj_headw) puts("  INJECT      : head_w, sign bit of the largest |W| in the Golden top-1 row");
    double t_all = hw_now();

    /* ---- embed (PS) ---- */
    {
        float *px = read_sub(dir, "embed", "pixels.bin", 4 * PIXELS_FLOATS);
        float *pw = read_sub(dir, "embed", "patch_w.bin", 4 * D * D);
        float *pb = read_sub(dir, "embed", "patch_b.bin", 4 * D);
        float *cls = read_sub(dir, "embed", "cls.bin", 4 * D);
        float *pos = read_sub(dir, "embed", "pos.bin", 4 * (size_t)VIT_TOKENS * D);
        uint8_t *h0g = read_sub(dir, "embed", "h0_golden.bin", RES_BYTES);
        int ok = px && pw && pb && cls && pos && h0g;
        if (ok) {
            hw_op_begin(&hw, OP_EMBED);
            double t = hw_now();
            ps_embed(px, pw, pb, cls, pos, h);
            hw_prof_add(&hw, PK_PS, hw_now() - t);
            hw_op_end(&hw);
            puts("--------------------------------------------------------------------------");
            check(0, "PS embed h0 == embed/h0_golden.bin", h, h0g, RES_BYTES, 2, "BF16");
        }
        free(px); free(pw); free(pb); free(cls); free(pos); free(h0g);
        if (!ok) goto out;
    }

    /* ---- layers ---- */
    puts("  layer  checks      L2 cmd     BB   CDMA   load ms   LN1 ms   run ms  check ms");
    for (int l = 0; l < nl; l++) {
        char sub[8], ldir[1024];
        snprintf(sub, sizeof sub, "l%02d", l);
        snprintf(ldir, sizeof ldir, "%s/%s", dir, sub);
        qkv_files qf;
        attn_files af;
        mlp_files mf;
        memset(&af, 0, sizeof af);
        memset(&mf, 0, sizeof mf);
        double t0 = hw_now(), t;
        unsigned long c0 = hw.n_cmd, b0 = hw.n_bb, d0 = hw.n_dma;
        size_t bad0 = g_bad;
        int n0 = g_n;
        if (qkv_files_load(ldir, &qf)) goto out;
        if (attn_files_load(ldir, &af)) { qkv_files_free(&qf); goto out; }
        if (mlp_files_load(ldir, &mf)) { attn_files_free(&af); qkv_files_free(&qf); goto out; }
        float *w1 = read_sub(dir, sub, "ln1_w.bin", 4 * D), *b1 = read_sub(dir, sub, "ln1_b.bin", 4 * D);
        uint8_t *xsg = read_sub(dir, sub, "x_scale.bin", X2_SCALES);
        per[l].load = hw_now() - t0;
        int ok = w1 && b1 && xsg;

        if (ok) {
            char what[64];
            snprintf(what, sizeof what, "l%02d input h == h_in.bin", l);
            check(1, what, h, af.hin, RES_BYTES, 2, "BF16");
            t = hw_now();
            hw_op_begin(&hw, OP_LN1);
            ok = !ps_ln2_mx(h, w1, b1, mf.eps, x4, x4s);
            hw_prof_add(&hw, PK_PS, hw_now() - t);
            hw_op_end(&hw);
            per[l].ln1 = hw_now() - t;
            snprintf(what, sizeof what, "l%02d PS LN1 x MXFP4 == x.bin", l);
            check(1, what, x4, qf.x, X_BYTES, LINE_BYTES, "lines");
            snprintf(what, sizeof what, "l%02d PS LN1 x scale == x_scale.bin", l);
            check(1, what, x4s, xsg, X2_SCALES, 1, "bytes");
        }
        if (ok) {
            t = hw_now();
            if (layer_run(&x, &qf, &af, &mf, x4, h, VIT_HEADS, (int)FC1_TILES)) { ok = 0; run_failed = 1; }
            per[l].run = hw_now() - t;
        }
        if (ok) {
            if (l == inj_r2) flip_sign_bf16(x.r2, RES_BYTES / 2);
            t = hw_now();
            int n;
            size_t lb = layer_check(&x, VIT_HEADS, (int)FC1_TILES, &n);
            if (lb) printf("  (layer %d: output check failed, see above)\n", l);
            g_bad += lb;
            g_n += n;
            per[l].check = hw_now() - t;
            memcpy(h, x.r2, RES_BYTES);                          /* h_{l+1} = R2_l */
        }
        free(w1); free(b1); free(xsg);
        mlp_files_free(&mf);
        attn_files_free(&af);
        qkv_files_free(&qf);
        if (!ok) { fprintf(stderr, "layer %d failed\n", l); goto out; }
        per[l].bad = g_bad - bad0;
        per[l].n = g_n - n0;
        per[l].cmd = hw.n_cmd - c0; per[l].bb = hw.n_bb - b0; per[l].dma = hw.n_dma - d0;
        per[l].wall = hw_now() - t0;
        printf("  %5d  %3d %-4s  %6lu %6lu %6lu %9.1f %8.1f %8.1f %9.1f\n", l, per[l].n, per[l].bad ? "FAIL" : "PASS",
               per[l].cmd, per[l].bb, per[l].dma, per[l].load * 1e3, per[l].ln1 * 1e3, per[l].run * 1e3, per[l].check * 1e3);
    }

    /* ---- final LN + head (PS) ---- */
    if (nl == N_LAYERS) {
        float *lw = read_sub(dir, "head", "lnf_w.bin", 4 * D), *lb = read_sub(dir, "head", "lnf_b.bin", 4 * D);
        float *hwt = read_sub(dir, "head", "head_w.bin", 4 * (size_t)FULL_NCLASS * D);
        float *hb = read_sub(dir, "head", "head_b.bin", 4 * (size_t)FULL_NCLASS);
        uint8_t *lncg = read_sub(dir, "head", "lnc_golden.bin", 2 * D);
        float *lgg = read_sub(dir, "head", "logits_golden.bin", 4 * (size_t)FULL_NCLASS);
        int ok = lw && lb && hwt && hb && lncg && lgg;
        if (ok) {
            int tg = ps_top1(lgg, FULL_NCLASS);
            if (inj_headw) {
                float *row = hwt + (size_t)tg * D;
                size_t best = 0;
                for (size_t i = 1; i < D; i++) if (fabsf(row[i]) > fabsf(row[best])) best = i;
                row[best] = -row[best];
            }
            double eps = 1e-12;
            {   /* eps of the last layer's meta.json (all layers and the final LN share config.layer_norm_eps) */
                mlp_files mf;
                char ldir[1024];
                memset(&mf, 0, sizeof mf);
                snprintf(ldir, sizeof ldir, "%s/l%02d", dir, N_LAYERS - 1);
                if (!mlp_files_load(ldir, &mf)) eps = mf.eps;
                mlp_files_free(&mf);
            }
            hw_op_begin(&hw, OP_HEAD);
            double t = hw_now();
            ps_ln_bf16(h, lw, lb, eps, lnc);                    /* token 0 = CLS */
            ps_head(lnc, hwt, hb, FULL_NCLASS, lg);
            hw_prof_add(&hw, PK_PS, hw_now() - t);
            hw_op_end(&hw);
            puts("--------------------------------------------------------------------------");
            check(0, "PS final LN (CLS) == head/lnc_golden.bin", lnc, lncg, 2 * D, 2, "BF16");
            check(0, "PS head logits == logits_golden.bin", lg, lgg, 4 * (size_t)FULL_NCLASS, 4, "f32");
            top1 = ps_top1(lg, FULL_NCLASS);
            check(0, "top-1 == argmax(logits_golden)", &top1, &tg, sizeof top1, sizeof top1, "index");
            char name[128], gname[128];
            class_name(dir, top1, name, sizeof name);
            class_name(dir, tg, gname, sizeof gname);
            printf("  top-1 = %d '%s' (logit %.6g)   Golden top-1 = %d '%s'\n", top1, name, lg[top1], tg, gname);
        }
        free(lw); free(lb); free(hwt); free(hb); free(lncg); free(lgg);
        if (!ok) goto out;
    }
    t_all = hw_now() - t_all;

    layer_report(&hw);
    puts("--------------------------------------------------------------------------");
    unsigned long sc = 0, sb = 0, sd = 0;
    double sw = 0;
    for (int l = 0; l < nl; l++) { sc += per[l].cmd; sb += per[l].bb; sd += per[l].dma; sw += per[l].wall; }
    printf("  layers %d : L2 commands %lu (%lu / layer) | blackbox calls %lu | CDMA %lu | %.1f ms (%.1f ms / layer)\n",
           nl, sc, sc / (unsigned long)nl, sb, sd, sw * 1e3, sw * 1e3 / nl);
    printf("  run %.3f ms | L2 commands %lu | blackbox calls %lu | CDMA transfers %lu | checks %d, mismatch %zu\n",
           t_all * 1e3, hw.n_cmd, hw.n_bb, hw.n_dma, g_n, g_bad);
    printf("  memory : host layer buffers %.1f MB, peak resident %.1f MB\n", (double)x.host_bytes / 1048576.0, peak_mem_mb());
    puts("  Scope: data movement + command sequence + PS (embed, LN, MXFP4, residual, head); blackboxes output Golden.");
    rc = g_bad ? 2 : 0;

out:
    if (hw.cdma && (hw.dma_active || hw.q_count)) hw_cdma_drain(&hw);
    hw_close(&hw);
    if (run_failed) rc = rc ? rc : 1;
    printf("BOARD_RESULT=%s op=full layers=%d top1=%d\n", rc ? "FAIL" : "PASS", nl, top1);
    layer_ctx_free(&x);
    free(h); free(x4); free(x4s); free(lnc); free(lg);
    return rc;
}
