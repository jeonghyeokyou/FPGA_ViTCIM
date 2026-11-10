/* vit_main.c - ViT-Base layer 0 attention block on the ZCU102 PL (blackbox outputs Golden).
 *
 * Scope : QKV proj -> PS MXFP4 -> QK^T -> softmax -> PS MXFP4 -> AV -> PS concat MXFP4
 *         -> out proj -> PS residual   (one attention block, 12 heads)
 * Order : sequential, one operation at a time, so that each operation's time is measured alone.
 *         (QKV / attention overlap is not used here.)
 *
 * build : make            (vit_hw.c vit_ops.c attn_ops.c mxfp4.c, -lm)
 * run   : sudo ./vit_main --data DIR [--heads N]
 *           DIR    : vit_golden_gen.py (MXFP4) output folder (x.bin, w.bin, y_golden.bin, q_fp4.bin ...)
 *           --heads: heads 0..N-1 (default 12). N < 12 stops before concat / out proj / residual.
 *
 * Final checks (outputs only; inputs of each blackbox call are checked by vit_dbg):
 *   BB outputs that went L2 -> CDMA -> DDR == Golden : Y(QKV), A, O, Y(out proj)
 *   PS results == Python files                      : Q,K,V^T, A, O concat MXFP4 (+ scales), R
 * L2 output regions and DDR readback buffers are poisoned first (time listed as "verify only").
 */
#define _POSIX_C_SOURCE 200809L
#include "vit_hw.h"
#include "vit_ops.h"
#include "attn_ops.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>

#define RB_BYTES  LB(S_LINES)          /* largest readback : A of one head, 81,952 B   */
#define WR_BYTES  X_BYTES              /* largest DMA source : X / O concat, 75,648 B   */

typedef struct {
    hw_ctx           *h;
    const qkv_layout *L;
    const qkv_files  *qf;
    const attn_files *af;
    hw_buf            wr, rb, pb;      /* DMA source staging, DMA readback, poison source */
    /* results kept on the host */
    uint8_t *y, *q4, *qs, *k4, *ks, *vt4, *vs, *a, *a4, *as, *o, *oc, *ocs, *yo, *r;
} run_ctx;

/* ---- small DMA helpers ------------------------------------------------------------------------- */
static int to_l2(run_ctx *x, const uint8_t *src, size_t n, uint32_t c)
{
    memcpy(x->wr.va, src, n);
    hw_cache_sync(x->wr.va, n);
    return hw_cdma_copy(x->h, x->wr.pa, hw_l2_pa(c), n);
}

static int from_l2(run_ctx *x, uint32_t c, size_t n, uint8_t *dst)
{
    if (hw_cdma_copy(x->h, hw_l2_pa(c), x->rb.pa, n)) return -1;
    hw_cache_sync(x->rb.va, n);
    memcpy(dst, x->rb.va, n);
    return 0;
}

/* verification only: poison an L2 region and the DDR readback buffer */
static int poison_l2(run_ctx *x, uint32_t c, uint32_t nlines)
{
    hw_op_begin(x->h, OP_VERIFY);
    int rc = hw_cdma_copy(x->h, x->pb.pa, hw_l2_pa(c), LB(nlines));
    hw_op_end(x->h);
    return rc;
}

static void arm_rb(run_ctx *x)
{
    hw_op_begin(x->h, OP_VERIFY);
    memset(x->rb.va, 0x5A, RB_BYTES);
    hw_cache_sync(x->rb.va, RB_BYTES);
    hw_op_end(x->h);
}

#define PS_STEP(x, stmt) ({ double _t = hw_now(); int _r = (stmt); hw_prof_add((x)->h, PK_PS, hw_now() - _t); _r; })

/* ---- phase 1 : QKV of one head, then Q,K,V -> MXFP4 into g4-g5 ------------------------------------ */
static int qkv_head(run_ctx *x, int head)
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
static int attn_head(run_ctx *x, int head)
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
static int out_block(run_ctx *x)
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
    ps_residual(x->af->hin, x->yo, x->r);
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
static void check(const char *what, const uint8_t *got, const uint8_t *exp, size_t n, size_t unit, const char *uname)
{
    size_t bad = cmp_bytes(got, exp, n, unit);
    printf("  [%s] %-44s %7zu %-5s | mismatch %zu\n", bad ? "FAIL" : "PASS", what, n / unit, uname, bad);
    g_bad_total += bad;
}

static void final_checks(run_ctx *x, int nh)
{
    const qkv_files *q = x->qf;
    const attn_files *f = x->af;
    puts("--------------------------------------------------------------------------");
    puts("  CHECK (outputs)                                 compared        result");
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
        puts("  (concat, out proj, residual skipped: --heads < 12)");
        return;
    }
    check("PS O concat MXFP4 == oc_fp4.bin", x->oc, f->oc, LB(OC_LINES), LINE_BYTES, "lines");
    check("PS O concat scale == oc_scale.bin", x->ocs, f->ocs, OC_SCALES, 1, "bytes");
    check("Y out proj (L2 -> DDR) == yo_golden.bin", x->yo, f->yo, LB(YO_LINES) * VIT_HEADS, LINE_BYTES, "lines");
    check("PS R = h_in + Y == r_golden.bin", x->r, f->r, RES_BYTES, 2, "BF16");
}

/* ---- profile report -------------------------------------------------------------------------------------- */
static void report(const hw_ctx *h)
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

static void usage(const char *a0)
{
    fprintf(stderr, "usage: sudo %s --data DIR [--heads N(1..12)]\n", a0);
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    const char *dir = NULL;
    int nh = VIT_HEADS;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--data") && i + 1 < argc) dir = argv[++i];
        else if (!strcmp(argv[i], "--heads") && i + 1 < argc) nh = atoi(argv[++i]);
        else { usage(argv[0]); return 1; }
    }
    if (!dir || nh < 1 || nh > VIT_HEADS) { usage(argv[0]); return 1; }

    int rc = 1;
    hw_ctx hw;
    qkv_files qf;
    attn_files af;
    run_ctx x;
    memset(&x, 0, sizeof x);
    memset(&af, 0, sizeof af);
    x.wr.fd = x.rb.fd = x.pb.fd = -1;
    memset(&hw, 0, sizeof hw);
    hw.fd_mem = -1;

    if (qkv_files_load(dir, &qf)) return 1;
    if (attn_files_load(dir, &af)) { qkv_files_free(&qf); return 1; }
    struct { uint8_t **p; size_t n; } host[] = {
        { &x.y,   Y_FILE_BYTES },
        { &x.q4,  LB(QK4_LINES) * VIT_HEADS }, { &x.qs, (size_t)QK_SCALES_PER_HEAD * VIT_HEADS },
        { &x.k4,  LB(QK4_LINES) * VIT_HEADS }, { &x.ks, (size_t)QK_SCALES_PER_HEAD * VIT_HEADS },
        { &x.vt4, LB(VT4_LINES) * VIT_HEADS }, { &x.vs, (size_t)VT_SCALES_PER_HEAD * VIT_HEADS },
        { &x.a,   LB(S_LINES) * VIT_HEADS },
        { &x.a4,  LB(A4_LINES) * VIT_HEADS },  { &x.as, (size_t)A_SCALES_PER_HEAD * VIT_HEADS },
        { &x.o,   LB(O_LINES) * VIT_HEADS },
        { &x.oc,  LB(OC_LINES) },              { &x.ocs, OC_SCALES },
        { &x.yo,  LB(YO_LINES) * VIT_HEADS },
        { &x.r,   RES_BYTES },
    };
    for (size_t i = 0; i < sizeof host / sizeof host[0]; i++) {
        *host[i].p = malloc(host[i].n);
        if (!*host[i].p) goto out;
        memset(*host[i].p, 0xA5, host[i].n);
    }

    if (hw_open(&hw)) goto out;
    x.h = &hw; x.L = &QKV_LAYOUT_DEFAULT; x.qf = &qf; x.af = &af;
    if (hw_buf_alloc(&x.wr, WR_BYTES) || hw_buf_alloc(&x.rb, RB_BYTES) || hw_buf_alloc(&x.pb, RB_BYTES)) goto out;
    for (size_t i = 0; i < RB_BYTES / 8; i++) {                  /* poison: tag + byte offset */
        uint64_t v = UINT64_C(0xDEAD5EED00000000) ^ (uint64_t)(i * 8);
        memcpy(x.pb.va + 8 * i, &v, 8);
    }
    hw_cache_sync(x.pb.va, RB_BYTES);

    puts("==========================================================================");
    puts("  ZCU102 | ViT-Base layer 0 attention block | MXFP4 | blackbox = Golden");
    puts("==========================================================================");
    printf("  PL0 clock   : %" PRIu64 " Hz (Linux clk_summary)\n", hw.pl0_hz);
    printf("  Heads       : 0..%d   Mode: sequential (one operation at a time)\n", nh - 1);
    printf("  Data        : %s\n", dir);

    double t_all = hw_now();
    hw_op_begin(&hw, OP_QKV);
    int r0 = to_l2(&x, qf.x, X_BYTES, x.L->x_c);
    hw_op_end(&hw);
    if (r0) goto out;
    for (int h = 0; h < nh; h++) {
        double t = hw_now();
        if (qkv_head(&x, h)) goto out;
        printf("  QKV       head %2d done %8.3f ms\n", h, (hw_now() - t) * 1e3);
    }
    for (int h = 0; h < nh; h++) {
        double t = hw_now();
        if (attn_head(&x, h)) goto out;
        printf("  attention head %2d done %8.3f ms\n", h, (hw_now() - t) * 1e3);
    }
    if (nh == VIT_HEADS) {
        double t = hw_now();
        if (out_block(&x)) goto out;
        printf("  concat + out proj + residual %8.3f ms\n", (hw_now() - t) * 1e3);
    }
    t_all = hw_now() - t_all;

    final_checks(&x, nh);
    report(&hw);
    puts("--------------------------------------------------------------------------");
    printf("  run %.3f ms | L2 commands %lu | blackbox calls %lu | CDMA transfers %lu\n",
           t_all * 1e3, hw.n_cmd, hw.n_bb, hw.n_dma);
    puts("  Scope: data movement + command sequence + PS MXFP4/residual; blackboxes output Golden (no compute).");
    rc = g_bad_total ? 2 : 0;

out:
    if (hw.cdma && (hw.dma_active || hw.q_count)) hw_cdma_drain(&hw);
    hw_close(&hw);
    printf("BOARD_RESULT=%s op=attn heads=%d mode=seq\n", rc ? "FAIL" : "PASS", nh);
    hw_buf_free(&x.wr); hw_buf_free(&x.rb); hw_buf_free(&x.pb);
    for (size_t i = 0; i < sizeof host / sizeof host[0]; i++) free(*host[i].p);
    attn_files_free(&af);
    qkv_files_free(&qf);
    return rc;
}
