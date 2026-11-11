/* layer_run.c - one encoder layer on the PL. See layer_run.h.  JH, 2026-11-11
 *
 * 원본: JH/ViT-Base_C_mlp/vit_main.c (c3db75b) 의 run_ctx, DMA helper, qkv_head / attn_head / out_block /
 *       mlp_block, final_checks*, report 를 옮김 (VIT_FULL_TASK.md 6.1). 블록 본문은 그대로이고
 *       run_ctx -> layer_ctx, residual 1 입력 af->hin -> x->hin (layer_run 인자) 만 바뀜.
 */
#define _POSIX_C_SOURCE 200809L
#include "layer_run.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#define RB_BYTES  LB(S_LINES)          /* largest readback : A of one head, 81,952 B   */
#define WR_BYTES  X_BYTES              /* largest DMA source : X / O concat, 75,648 B   */

/* ---- small DMA helpers ------------------------------------------------------------------------- */
static int to_l2(layer_ctx *x, const uint8_t *src, size_t n, uint32_t c)
{
    memcpy(x->wr.va, src, n);
    hw_cache_sync(x->wr.va, n);
    return hw_cdma_copy(x->h, x->wr.pa, hw_l2_pa(c), n);
}

static int from_l2(layer_ctx *x, uint32_t c, size_t n, uint8_t *dst)
{
    if (hw_cdma_copy(x->h, hw_l2_pa(c), x->rb.pa, n)) return -1;
    hw_cache_sync(x->rb.va, n);
    memcpy(dst, x->rb.va, n);
    return 0;
}

/* verification only: poison an L2 region and the DDR readback buffer */
static int poison_l2(layer_ctx *x, uint32_t c, uint32_t nlines)
{
    hw_op_begin(x->h, OP_VERIFY);
    int rc = hw_cdma_copy(x->h, x->pb.pa, hw_l2_pa(c), LB(nlines));
    hw_op_end(x->h);
    return rc;
}

static void arm_rb(layer_ctx *x)
{
    hw_op_begin(x->h, OP_VERIFY);
    memset(x->rb.va, 0x5A, RB_BYTES);
    hw_cache_sync(x->rb.va, RB_BYTES);
    hw_op_end(x->h);
}

#define PS_STEP(x, stmt) ({ double _t = hw_now(); int _r = (stmt); hw_prof_add((x)->h, PK_PS, hw_now() - _t); _r; })

/* ---- phase 1 : QKV of one head, then Q,K,V -> MXFP4 into g4-g5 ------------------------------------ */
static int qkv_head(layer_ctx *x, int head)
{
    hw_ctx *h = x->h;
    int b = head & 1;
    hw_op_begin(h, OP_QKV);
    int rc = to_l2(x, x->qf->w + w_off(head, 0), W_BYTES_PER_HEAD, x->L->w_c[b]);
    hw_op_end(h);
    if (rc) return -1;
    for (int p = 0; p < 3; p++)
        if (poison_l2(x, qkv_y_c(x->L, b, p), Y_LINES_PER_P)) return -1;

    hw_op_begin(h, OP_QKV);
    rc = qkv_proj_head(h, x->L, x->qf, head, b, NULL);
    hw_op_end(h);
    if (rc) { fprintf(stderr, "head %d QKV failed\n", head); return -1; }

    arm_rb(x);
    hw_op_begin(h, OP_QKV_MX);
    uint8_t *y = x->y + (size_t)head * Y_BYTES_PER_HEAD;
    for (int p = 0; p < 3 && !rc; p++)
        rc = from_l2(x, qkv_y_c(x->L, b, p), Y_BYTES_PER_P, y + (size_t)p * Y_BYTES_PER_P);
    uint8_t *q4 = x->q4 + q4_off(head), *k4 = x->k4 + q4_off(head), *vt4 = x->vt4 + vt4_off(head);
    if (!rc) rc = PS_STEP(x, ps_mx_qkv(y, q4, x->qs + QK_SCALES_PER_HEAD * head, k4, x->ks + QK_SCALES_PER_HEAD * head,
                                     vt4, x->vs + VT_SCALES_PER_HEAD * head));
    if (!rc) rc = to_l2(x, q4, LB(QK4_LINES), L2_Q4(head));
    if (!rc) rc = to_l2(x, k4, LB(QK4_LINES), L2_K4(head));
    if (!rc) rc = to_l2(x, vt4, LB(VT4_LINES), L2_VT4(head));
    hw_op_end(h);
    if (rc) fprintf(stderr, "head %d Q,K,V -> MXFP4 failed\n", head);
    return rc;
}

/* ---- phase 2 : attention of one head ------------------------------------------------------------------ */
static int attn_head(layer_ctx *x, int head)
{
    hw_ctx *h = x->h;
    int b = head & 1, rc;
    if (poison_l2(x, L2_S(b), S_LINES) || poison_l2(x, L2_O(b), O_LINES)) return -1;

    hw_op_begin(h, OP_QKT);
    rc = at_qkt_head(h, x->af, head, x->q4 + q4_off(head), x->k4 + q4_off(head), NULL);
    hw_op_end(h);
    if (rc) return -1;

    hw_op_begin(h, OP_SOFTMAX);
    rc = at_softmax_head(h, x->af, head, NULL);
    hw_op_end(h);
    if (rc) return -1;

    arm_rb(x);
    hw_op_begin(h, OP_A_MX);
    uint8_t *a = x->a + LB(S_LINES) * head, *a4 = x->a4 + a4_off(head, 0);
    rc = from_l2(x, L2_S(b), LB(S_LINES), a);
    if (!rc) rc = PS_STEP(x, ps_mx_a(a, a4, x->as + A_SCALES_PER_HEAD * head));
    if (!rc) rc = to_l2(x, a4, LB(A4_LINES), L2_A4(b));
    hw_op_end(h);
    if (rc) { fprintf(stderr, "head %d A -> MXFP4 failed\n", head); return -1; }

    hw_op_begin(h, OP_AV);
    rc = at_av_head(h, x->af, head, a4, x->vt4 + vt4_off(head), NULL);
    hw_op_end(h);
    if (rc) return -1;

    arm_rb(x);
    hw_op_begin(h, OP_O_MX);
    uint8_t *o = x->o + o_off(head, 0);
    rc = from_l2(x, L2_O(b), LB(O_LINES), o);
    if (!rc) rc = PS_STEP(x, ps_mx_o(o, head, x->oc, x->ocs));
    hw_op_end(h);
    if (rc) fprintf(stderr, "head %d O -> MXFP4 failed\n", head);
    return rc;
}

/* ---- phase 3 : concat -> out proj -> residual ------------------------------------------------------------ */
static int out_block(layer_ctx *x)
{
    hw_ctx *h = x->h;
    int rc;
    hw_op_begin(h, OP_O_MX);
    rc = to_l2(x, x->oc, LB(OC_LINES), L2_OC);
    hw_op_end(h);
    if (rc) return -1;
    for (int j = 0; j < VIT_HEADS; j++)
        if (poison_l2(x, L2_YO(j), YO_LINES)) return -1;

    for (int j = 0; j < VIT_HEADS; j++) {
        hw_op_begin(h, OP_OPROJ);
        rc = to_l2(x, x->af->wo + wo_off(j), LB(WO_LINES), L2_WO(j & 1));
        if (!rc) rc = at_oproj_tile(h, x->af, j, x->oc, NULL);
        hw_op_end(h);
        if (rc) { fprintf(stderr, "out proj tile %d failed\n", j); return -1; }
    }
    for (int j = 0; j < VIT_HEADS; j++) {
        arm_rb(x);
        hw_op_begin(h, OP_RESID);
        rc = from_l2(x, L2_YO(j), LB(YO_LINES), x->yo + yo_off(j, 0));
        hw_op_end(h);
        if (rc) return -1;
    }
    hw_op_begin(h, OP_RESID);
    double t = hw_now();
    ps_residual(x->hin, x->yo, x->r);
    hw_prof_add(h, PK_PS, hw_now() - t);
    hw_op_end(h);
    return 0;
}

/* ---- phase 4 : MLP (LN2 -> FC1 -> GELU -> G->H4 -> FC2 -> accumulate -> residual 2) --------------------- */
static int mlp_block(layer_ctx *x, int ntiles)
{
    hw_ctx *h = x->h;
    const mlp_files *mf = x->mf;
    int rc;
    hw_op_begin(h, OP_LN2);
    rc = PS_STEP(x, ps_ln2_mx(x->r, mf->ln2_w, mf->ln2_b, mf->eps, x->x2, x->x2s));
    if (!rc) rc = to_l2(x, x->x2, LB(X2_LINES), L2_X2);
    hw_op_end(h);
    if (rc) { fprintf(stderr, "LN2 -> MXFP4 failed\n"); return -1; }

    for (int j = 0; j < ntiles; j++) {
        int b = j & 1, k = j / 12;
        if (poison_l2(x, L2_H(b), H_LINES)) return -1;
        hw_op_begin(h, OP_FC1);
        rc = to_l2(x, mf->w1 + w1_off(j), LB(W1_LINES), L2_W1(b));
        if (!rc) rc = mlp_fc1_tile(h, mf, j, x->x2, NULL);
        hw_op_end(h);
        if (rc) { fprintf(stderr, "FC1 tile %d failed\n", j); return -1; }

        hw_op_begin(h, OP_GELU);
        rc = mlp_gelu_tile(h, mf, j, NULL);
        hw_op_end(h);
        if (rc) return -1;

        arm_rb(x);
        hw_op_begin(h, OP_H_MX);
        uint8_t *g = x->g + h_off(j, 0);
        rc = from_l2(x, L2_H(b), LB(H_LINES), g);
        if (!rc) rc = PS_STEP(x, ps_mx_g(g, j, x->h4, x->h4s));
        if (!rc && j % 12 == 11) rc = to_l2(x, x->h4 + h4_off(k), LB(H4_LINES), L2_H4(k));
        hw_op_end(h);
        if (rc) { fprintf(stderr, "tile %d G -> H4 failed\n", j); return -1; }
    }
    if (ntiles < (int)FC1_TILES) return 0;

    for (int n = 0; n < (int)FC2_TILES; n++)
        for (int k = 0; k < (int)FC2_K; k++) {
            int b = (4 * n + k) & 1;
            if (poison_l2(x, L2_P(b), P_LINES)) return -1;
            hw_op_begin(h, OP_FC2);
            rc = to_l2(x, mf->w2 + w2_off(n, k), LB(W2_LINES), L2_W2(b));
            if (!rc) rc = mlp_fc2_call(h, mf, n, k, x->h4, NULL);
            hw_op_end(h);
            if (rc) { fprintf(stderr, "FC2 (%d,%d) failed\n", n, k); return -1; }

            arm_rb(x);
            hw_op_begin(h, OP_FC2_ACC);
            uint8_t *p = x->p + p_off(n, k, 0);
            rc = from_l2(x, L2_P(b), LB(P_LINES), p);
            if (!rc) {
                double t = hw_now();
                ps_fc2_acc(x->acc, p, k, mf->b2 + 64 * n, x->y2 + y2_off(n, 0));
                hw_prof_add(h, PK_PS, hw_now() - t);
            }
            hw_op_end(h);
            if (rc) return -1;
        }

    hw_op_begin(h, OP_RESID2);
    double t = hw_now();
    ps_residual(x->r, x->y2, x->r2);
    hw_prof_add(h, PK_PS, hw_now() - t);
    hw_op_end(h);
    return 0;
}

/* ---- final checks ---------------------------------------------------------------------------------------- */
static size_t cmp_bytes(const uint8_t *got, const uint8_t *exp, size_t n, size_t unit)
{
    size_t bad = 0;
    for (size_t i = 0; i < n; i += unit)
        if (memcmp(got + i, exp + i, unit)) bad++;
    return bad;
}

static size_t g_bad_total;
static int g_nchecks, g_quiet;
static void check(const char *what, const uint8_t *got, const uint8_t *exp, size_t n, size_t unit, const char *uname)
{
    size_t bad = cmp_bytes(got, exp, n, unit);
    if (!g_quiet || bad)
        printf("  [%s] %-44s %7zu %-5s | mismatch %zu\n", bad ? "FAIL" : "PASS", what, n / unit, uname, bad);
    g_bad_total += bad;
    g_nchecks++;
}

static void final_checks_mlp(layer_ctx *x, int ntiles)
{
    const mlp_files *m = x->mf;
    check("PS LN2 X2 MXFP4 == x2_fp4.bin", x->x2, m->x2, LB(X2_LINES), LINE_BYTES, "lines");
    check("PS LN2 X2 scale == x2_scale.bin", x->x2s, m->x2s, X2_SCALES, 1, "bytes");
    check("G GELU (L2 -> DDR) == g_golden.bin", x->g, m->g, LB(H_LINES) * (size_t)ntiles, LINE_BYTES, "lines");
    if (ntiles < (int)FC1_TILES) {
        if (!g_quiet) puts("  (H4, FC2, accumulate, residual 2 skipped: --tiles < 48)");
        return;
    }
    check("PS H4 MXFP4 == h4_fp4.bin", x->h4, m->h4, LB(H4_LINES) * FC2_K, LINE_BYTES, "lines");
    check("PS H4 scale == h4_scale.bin", x->h4s, m->h4s, (size_t)H4_SCALES * FC2_K, 1, "bytes");
    check("P FC2 partial (L2 -> DDR) == p_golden.bin", x->p, m->p, LB(P_LINES) * FC2_CALLS, LINE_BYTES, "lines");
    check("PS Y2 accumulate == y2_golden.bin", x->y2, m->y2, LB(Y2_LINES) * FC2_TILES, 2, "BF16");
    check("PS R2 = R + Y2 == r2_golden.bin", x->r2, m->r2, RES_BYTES, 2, "BF16");
}

static void final_checks(layer_ctx *x, int nh)
{
    const qkv_files *q = x->qf;
    const attn_files *f = x->af;
    if (!g_quiet) {
        puts("--------------------------------------------------------------------------");
        puts("  CHECK (outputs)                                 compared        result");
    }
    check("Y QKV (L2 -> DDR) == y_golden.bin", x->y, q->y_golden, (size_t)nh * Y_BYTES_PER_HEAD, LINE_BYTES, "lines");
    check("PS Q MXFP4 == q_fp4.bin", x->q4, f->q4, LB(QK4_LINES) * nh, LINE_BYTES, "lines");
    check("PS Q scale == q_scale.bin", x->qs, f->qs, (size_t)QK_SCALES_PER_HEAD * nh, 1, "bytes");
    check("PS K MXFP4 == k_fp4.bin", x->k4, f->k4, LB(QK4_LINES) * nh, LINE_BYTES, "lines");
    check("PS K scale == k_scale.bin", x->ks, f->ks, (size_t)QK_SCALES_PER_HEAD * nh, 1, "bytes");
    check("PS V^T MXFP4 == vt_fp4.bin", x->vt4, f->vt4, LB(VT4_LINES) * nh, LINE_BYTES, "lines");
    check("PS V^T scale == vt_scale.bin", x->vs, f->vs, (size_t)VT_SCALES_PER_HEAD * nh, 1, "bytes");
    check("A softmax (L2 -> DDR) == a_golden.bin", x->a, f->a, LB(S_LINES) * nh, LINE_BYTES, "lines");
    check("PS A MXFP4 == a_fp4.bin", x->a4, f->a4, LB(A4_LINES) * nh, LINE_BYTES, "lines");
    check("PS A scale == a_scale.bin", x->as, f->as, (size_t)A_SCALES_PER_HEAD * nh, 1, "bytes");
    check("O AV (L2 -> DDR) == o_golden.bin", x->o, f->o, LB(O_LINES) * nh, LINE_BYTES, "lines");
    if (nh < VIT_HEADS) {
        if (!g_quiet) puts("  (concat, out proj, residual skipped: --heads < 12)");
        return;
    }
    check("PS O concat MXFP4 == oc_fp4.bin", x->oc, f->oc, LB(OC_LINES), LINE_BYTES, "lines");
    check("PS O concat scale == oc_scale.bin", x->ocs, f->ocs, OC_SCALES, 1, "bytes");
    check("Y out proj (L2 -> DDR) == yo_golden.bin", x->yo, f->yo, LB(YO_LINES) * VIT_HEADS, LINE_BYTES, "lines");
    check("PS R = h_in + Y == r_golden.bin", x->r, f->r, RES_BYTES, 2, "BF16");
}

/* ---- profile report -------------------------------------------------------------------------------------- */
void layer_report(const hw_ctx *h)
{
    double mhz = (double)h->pl0_hz * 1e-6;
    hw_prof tot;
    memset(&tot, 0, sizeof tot);
    puts("--------------------------------------------------------------------------");
    printf("  TIME PER OPERATION   (PL0 clk = PS wall time x %.6f MHz; BB clk = CYCLES registers)\n", mhz);
    printf("  %-24s %9s %12s %10s %12s\n", "operation", "wall ms", "PL0 clk", "BB clk", "no-Golden ms");
    for (int op = 0; op < OP_N; op++) {
        const hw_prof *p = &h->prof[op];
        if (p->wall == 0 && p->n[PK_CMD] == 0 && p->n[PK_DMA] == 0) continue;
        printf("  %-24s %9.3f %12.0f %10" PRIu64 " %12.3f\n", OP_NAME[op], p->wall * 1e3,
               p->wall * (double)h->pl0_hz, p->bb_cycles, (p->wall - p->t[PK_GOLD]) * 1e3);
        if (op == OP_VERIFY || op == OP_OTHER) continue;
        tot.wall += p->wall; tot.bb_cycles += p->bb_cycles; tot.t[PK_GOLD] += p->t[PK_GOLD];
    }
    printf("  %-24s %9.3f %12.0f %10" PRIu64 " %12.3f\n", "total (w/o verify)", tot.wall * 1e3,
           tot.wall * (double)h->pl0_hz, tot.bb_cycles, (tot.wall - tot.t[PK_GOLD]) * 1e3);

    puts("");
    puts("  BREAKDOWN ms (count)   L2 cmd = LOAD/STORE, BB = START..done (ch2: ..STORE done),");
    puts("                         Golden = Golden injection (BB model only), rest = memcpy/cache/loop");
    printf("  %-24s %13s %13s %13s %18s %13s %8s\n", "operation", "L2 cmd", "BB", "Golden", "CDMA (KiB)", "PS", "rest");
    for (int op = 0; op < OP_N; op++) {
        const hw_prof *p = &h->prof[op];
        if (p->wall == 0 && p->n[PK_CMD] == 0 && p->n[PK_DMA] == 0) continue;
        double rest = p->wall;
        for (int k = 0; k < PK_N; k++) rest -= p->t[k];
        char c[PK_N][24];
        for (int k = 0; k < PK_N; k++) snprintf(c[k], sizeof c[k], "%7.3f (%lu)", p->t[k] * 1e3, p->n[k]);
        char d[32];
        snprintf(d, sizeof d, "%7.3f (%lu,%" PRIu64 ")", p->t[PK_DMA] * 1e3, p->n[PK_DMA], p->dma_bytes / 1024);
        printf("  %-24s %13s %13s %13s %18s %13s %8.3f\n", OP_NAME[op], c[PK_CMD], c[PK_BB], c[PK_GOLD], d, c[PK_PS], rest * 1e3);
    }
}

size_t layer_check(layer_ctx *x, int nh, int ntiles, int *nchecks)
{
    g_bad_total = 0;
    g_nchecks = 0;
    g_quiet = x->quiet;
    final_checks(x, nh);
    if (x->mf) final_checks_mlp(x, ntiles);
    if (nchecks) *nchecks = g_nchecks;
    return g_bad_total;
}

/* ---- context ------------------------------------------------------------------------------------------- */
int layer_ctx_init(layer_ctx *x, hw_ctx *h)
{
    memset(x, 0, sizeof *x);
    x->wr.fd = x->rb.fd = x->pb.fd = -1;
    x->h = h;
    x->L = &QKV_LAYOUT_DEFAULT;
    struct { uint8_t **p; size_t n; } host[] = {
        { &x->y,   Y_FILE_BYTES },
        { &x->q4,  LB(QK4_LINES) * VIT_HEADS }, { &x->qs, (size_t)QK_SCALES_PER_HEAD * VIT_HEADS },
        { &x->k4,  LB(QK4_LINES) * VIT_HEADS }, { &x->ks, (size_t)QK_SCALES_PER_HEAD * VIT_HEADS },
        { &x->vt4, LB(VT4_LINES) * VIT_HEADS }, { &x->vs, (size_t)VT_SCALES_PER_HEAD * VIT_HEADS },
        { &x->a,   LB(S_LINES) * VIT_HEADS },
        { &x->a4,  LB(A4_LINES) * VIT_HEADS },  { &x->as, (size_t)A_SCALES_PER_HEAD * VIT_HEADS },
        { &x->o,   LB(O_LINES) * VIT_HEADS },
        { &x->oc,  LB(OC_LINES) },              { &x->ocs, OC_SCALES },
        { &x->yo,  LB(YO_LINES) * VIT_HEADS },
        { &x->r,   RES_BYTES },
        { &x->x2,  LB(X2_LINES) },              { &x->x2s, X2_SCALES },
        { &x->g,   LB(H_LINES) * FC1_TILES },
        { &x->h4,  LB(H4_LINES) * FC2_K },      { &x->h4s, (size_t)H4_SCALES * FC2_K },
        { &x->p,   LB(P_LINES) * FC2_CALLS },
        { &x->y2,  LB(Y2_LINES) * FC2_TILES },
        { &x->r2,  RES_BYTES },
    };
    x->acc = malloc(sizeof(float) * H_TILE_ELEMS);
    if (!x->acc) return -1;
    x->host_bytes = sizeof(float) * H_TILE_ELEMS;
    for (size_t i = 0; i < sizeof host / sizeof host[0]; i++) {
        *host[i].p = malloc(host[i].n);
        if (!*host[i].p) return -1;
        memset(*host[i].p, 0xA5, host[i].n);
        x->host_bytes += host[i].n;
    }
    if (hw_buf_alloc(&x->wr, WR_BYTES) || hw_buf_alloc(&x->rb, RB_BYTES) || hw_buf_alloc(&x->pb, RB_BYTES)) return -1;
    for (size_t i = 0; i < RB_BYTES / 8; i++) {                  /* poison: tag + byte offset */
        uint64_t v = UINT64_C(0xDEAD5EED00000000) ^ (uint64_t)(i * 8);
        memcpy(x->pb.va + 8 * i, &v, 8);
    }
    hw_cache_sync(x->pb.va, RB_BYTES);
    return 0;
}

void layer_ctx_free(layer_ctx *x)
{
    hw_buf_free(&x->wr); hw_buf_free(&x->rb); hw_buf_free(&x->pb);
    uint8_t **p[] = { &x->y, &x->q4, &x->qs, &x->k4, &x->ks, &x->vt4, &x->vs, &x->a, &x->a4, &x->as, &x->o,
                      &x->oc, &x->ocs, &x->yo, &x->r, &x->x2, &x->x2s, &x->g, &x->h4, &x->h4s, &x->p, &x->y2, &x->r2 };
    for (size_t i = 0; i < sizeof p / sizeof p[0]; i++) { free(*p[i]); *p[i] = NULL; }
    free(x->acc);
    x->acc = NULL;
}

/* ---- one layer : the order vit_main.c main() had ------------------------------------------------------- */
int layer_run(layer_ctx *x, const qkv_files *qf, const attn_files *af, const mlp_files *mf,
              const uint8_t *x4, const uint8_t *h_in, int nh, int ntiles)
{
    hw_ctx *h = x->h;
    x->qf = qf; x->af = af; x->mf = mf; x->hin = h_in;
    hw_op_begin(h, OP_QKV);
    int r0 = to_l2(x, x4, X_BYTES, x->L->x_c);
    hw_op_end(h);
    if (r0) return -1;
    for (int hd = 0; hd < nh; hd++) {
        double t = hw_now();
        if (qkv_head(x, hd)) return -1;
        if (!x->quiet) printf("  QKV       head %2d done %8.3f ms\n", hd, (hw_now() - t) * 1e3);
    }
    for (int hd = 0; hd < nh; hd++) {
        double t = hw_now();
        if (attn_head(x, hd)) return -1;
        if (!x->quiet) printf("  attention head %2d done %8.3f ms\n", hd, (hw_now() - t) * 1e3);
    }
    if (nh == VIT_HEADS) {
        double t = hw_now();
        if (out_block(x)) return -1;
        if (!x->quiet) printf("  concat + out proj + residual %8.3f ms\n", (hw_now() - t) * 1e3);
    }
    if (mf) {
        double t = hw_now();
        if (mlp_block(x, ntiles)) return -1;
        if (!x->quiet) printf("  MLP (LN2 .. residual 2)      %8.3f ms\n", (hw_now() - t) * 1e3);
    }
    return 0;
}
