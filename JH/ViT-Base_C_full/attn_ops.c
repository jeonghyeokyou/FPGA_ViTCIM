/* attn_ops.c - attention dataflow after QKV. See attn_ops.h.
 *
 * 원본: LHJ/ViT-Base_C_261110/attn_ops.c (55d6f24) / JH 2026-11-10: OP_NAME[] 에 MLP 연산 7개 이름
 *       추가 (attn_ops.h enum 과 같은 순서). 그 밖에는 그대로.
 */
#include "attn_ops.h"
#include "mxfp4.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

const char *const OP_NAME[OP_N] = {
    "other",
    "QKV proj (MAC)",
    "Q,K,V -> MXFP4 (PS)",
    "QK^T (MAC)",
    "softmax (vector)",
    "A -> MXFP4 (PS)",
    "AV (MAC)",
    "O -> concat MXFP4 (PS)",
    "out proj (MAC)",
    "residual (PS)",
    "LN2 -> MXFP4 (PS)",
    "FC1 (MAC)",
    "GELU (vector)",
    "G -> H4 MXFP4 (PS)",
    "FC2 partial (MAC)",
    "FC2 accumulate (PS)",
    "residual 2 (PS)",
    "verify only (poison)",
};

/* ---- files ------------------------------------------------------------------------------------ */
static uint8_t *read_file(const char *dir, const char *name, size_t expect)
{
    char path[1024];
    snprintf(path, sizeof path, "%s/%s", dir, name);
    FILE *fp = fopen(path, "rb");
    if (!fp) { fprintf(stderr, "open %s: %s\n", path, strerror(errno)); return NULL; }
    uint8_t *p = malloc(expect + 1);
    size_t got = p ? fread(p, 1, expect + 1, fp) : 0;
    fclose(fp);
    if (!p || got != expect) {
        fprintf(stderr, "%s: %zu bytes, expected %zu\n", path, got, expect);
        free(p);
        return NULL;
    }
    return p;
}

int attn_files_load(const char *dir, attn_files *f)
{
    memset(f, 0, sizeof *f);
    struct { const uint8_t **p; const char *name; size_t n; } t[] = {
        { &f->q4,  "q_fp4.bin",     LB(QK4_LINES) * VIT_HEADS },
        { &f->qs,  "q_scale.bin",   (size_t)QK_SCALES_PER_HEAD * VIT_HEADS },
        { &f->k4,  "k_fp4.bin",     LB(QK4_LINES) * VIT_HEADS },
        { &f->ks,  "k_scale.bin",   (size_t)QK_SCALES_PER_HEAD * VIT_HEADS },
        { &f->vt4, "vt_fp4.bin",    LB(VT4_LINES) * VIT_HEADS },
        { &f->vs,  "vt_scale.bin",  (size_t)VT_SCALES_PER_HEAD * VIT_HEADS },
        { &f->s,   "s_golden.bin",  LB(S_LINES) * VIT_HEADS },
        { &f->a,   "a_golden.bin",  LB(S_LINES) * VIT_HEADS },
        { &f->a4,  "a_fp4.bin",     LB(A4_LINES) * VIT_HEADS },
        { &f->as,  "a_scale.bin",   (size_t)A_SCALES_PER_HEAD * VIT_HEADS },
        { &f->o,   "o_golden.bin",  LB(O_LINES) * VIT_HEADS },
        { &f->oc,  "oc_fp4.bin",    LB(OC_LINES) },
        { &f->ocs, "oc_scale.bin",  OC_SCALES },
        { &f->wo,  "wo.bin",        LB(WO_LINES) * VIT_HEADS },
        { &f->yo,  "yo_golden.bin", LB(YO_LINES) * VIT_HEADS },
        { &f->hin, "h_in.bin",      RES_BYTES },
        { &f->r,   "r_golden.bin",  RES_BYTES },
    };
    for (size_t i = 0; i < sizeof t / sizeof t[0]; i++)
        if (!(*t[i].p = read_file(dir, t[i].name, t[i].n))) { attn_files_free(f); return -1; }
    return 0;
}

void attn_files_free(attn_files *f)
{
    const uint8_t *all[] = { f->q4, f->qs, f->k4, f->ks, f->vt4, f->vs, f->s, f->a, f->a4, f->as,
                             f->o, f->oc, f->ocs, f->wo, f->yo, f->hin, f->r };
    for (size_t i = 0; i < sizeof all / sizeof all[0]; i++) free((void *)all[i]);
    memset(f, 0, sizeof *f);
}

/* ---- PS work ------------------------------------------------------------------------------------ */
int ps_mx_qkv(const uint8_t *y, uint8_t *q4, uint8_t *qs, uint8_t *k4, uint8_t *ks, uint8_t *vt4, uint8_t *vs)
{
    double v[256];
    const uint8_t *yq = y, *yk = y + Y_BYTES_PER_P, *yv = y + 2 * Y_BYTES_PER_P;
    for (uint32_t t = 0; t < VIT_TOKENS; t++) {                  /* token rows, 64 = 2 blocks */
        for (int d = 0; d < VIT_DHEAD; d++) v[d] = bf16_to_d(rd_bf16(yq + LB(4u * t) + 2 * d));
        if (mx_quant(v, VIT_DHEAD, q4 + LB(t), qs + 2 * t)) return -1;
        for (int d = 0; d < VIT_DHEAD; d++) v[d] = bf16_to_d(rd_bf16(yk + LB(4u * t) + 2 * d));
        if (mx_quant(v, VIT_DHEAD, k4 + LB(t), ks + 2 * t)) return -1;
    }
    for (int d = 0; d < VIT_DHEAD; d++) {                        /* V^T: d rows, 256 tokens = 8 blocks */
        for (uint32_t t = 0; t < 256; t++)
            v[t] = t < VIT_TOKENS ? bf16_to_d(rd_bf16(yv + LB(4u * t) + 2 * d)) : 0.0;
        if (mx_quant(v, 256, vt4 + LB(VT4_LINES_PER_D * (uint32_t)d), vs + 8 * d)) return -1;
    }
    return 0;
}

int ps_mx_a(const uint8_t *a, uint8_t *a4, uint8_t *as)
{
    double v[256];
    for (uint32_t r = 0; r < VIT_TOKENS; r++) {
        for (uint32_t s = 0; s < 256; s++)
            v[s] = s < VIT_TOKENS ? bf16_to_d(rd_bf16(a + LB(S_LINES_PER_ROW * r) + 2 * s)) : 0.0;
        if (mx_quant(v, 256, a4 + LB(A4_LINES_PER_ROW * r), as + 8 * r)) return -1;
    }
    return 0;
}

int ps_mx_o(const uint8_t *o, int head, uint8_t *oc, uint8_t *ocs)
{
    double v[VIT_DHEAD];
    for (uint32_t t = 0; t < VIT_TOKENS; t++) {
        for (int d = 0; d < VIT_DHEAD; d++) v[d] = bf16_to_d(rd_bf16(o + LB(O_LINES_PER_TOKEN * t) + 2 * d));
        if (mx_quant(v, VIT_DHEAD, oc + LB(X_LINES_PER_TOKEN * t + (uint32_t)head), ocs + 24 * t + 2 * head))
            return -1;
    }
    return 0;
}

void ps_residual(const uint8_t *hin, const uint8_t *yo, uint8_t *r)
{
    for (uint32_t t = 0; t < VIT_TOKENS; t++)
        for (uint32_t c = 0; c < VIT_DMODEL; c++) {
            size_t i = ((size_t)t * VIT_DMODEL + c) * 2;
            float x = bf16_to_f(rd_bf16(hin + i));
            float y = bf16_to_f(rd_bf16(yo + yo_off((int)(c / 64), t) + 2 * (c % 64)));
            float s = x + y;                                     /* float32 add, then RNE */
            wr_bf16(r + i, f32_to_bf16(s));
        }
}

/* ---- blackbox call helpers ---------------------------------------------------------------------- */
static int run_mac(hw_ctx *h, const attn_hooks *k, mac_call *c)
{
    if (k && k->before_mac && k->before_mac(k->user, c)) return -1;
    if (hw_bb_gold_load(h, c->gold, c->out_len)) return -1;
    if (hw_bb_run(h, c->in_base, c->in_len, c->w_base, c->w_len, c->out_base, c->out_len, 0, &c->cycles))
        return -1;
    if (k && k->after_mac && k->after_mac(k->user, c)) return -1;
    return 0;
}

static int run_store(hw_ctx *h, const attn_hooks *k, const mac_store *s)
{
    if (hw_cmd_run(h, cmd_x_store(s->l1_row, s->nlines, s->l2_c))) return -1;
    if (k && k->after_store && k->after_store(k->user, s)) return -1;
    return 0;
}

#define FAIL(...) do { fprintf(stderr, __VA_ARGS__); return -1; } while (0)

/* ---- QK^T ------------------------------------------------------------------------------------------ */
int at_qkt_head(hw_ctx *h, const attn_files *f, int head, const uint8_t *q4, const uint8_t *k4,
                const attn_hooks *k)
{
    uint32_t sb = L2_S(head & 1);
    if (hw_cmd_run(h, cmd_x_load(L2_Q4(head), QK4_LINES, 0))) FAIL("head %d QK^T: Q LOAD failed\n", head);
    if (hw_cmd_run(h, cmd_w_load(L2_K4(head), QK4_LINES, 0))) FAIL("head %d QK^T: K WLOAD failed\n", head);
    for (uint32_t i = 0; i < QKT_CALLS; i++) {
        if (hw_stop_requested()) return -1;
        uint32_t r0 = QKT_ROWS_PER_CALL * i;
        uint32_t m = VIT_TOKENS - r0 < QKT_ROWS_PER_CALL ? VIT_TOKENS - r0 : QKT_ROWS_PER_CALL;
        mac_call c = {
            .op = OP_QKT, .head = head, .idx = (int)i, .row0 = r0, .nrow = m,
            .in_base = r0, .in_len = m, .w_base = 0, .w_len = QK4_LINES,
            .out_base = QKT_L1_OUT, .out_len = S_LINES_PER_ROW * m,
            .gold = f->s + s_off(head, r0), .in_exp = q4 + LB(r0), .w_exp = k4,
        };
        if (run_mac(h, k, &c)) FAIL("head %d QK^T call %u failed\n", head, i);
        mac_store s = {
            .op = OP_QKT, .head = head, .idx = (int)i, .l1_row = QKT_L1_OUT, .nlines = c.out_len,
            .l2_c = sb + S_LINES_PER_ROW * r0, .row0 = r0, .nrow = m, .gold = c.gold,
        };
        if (run_store(h, k, &s)) FAIL("head %d QK^T STORE %u failed\n", head, i);
    }
    return 0;
}

/* ---- softmax (vector blackbox) ------------------------------------------------------------------------ */
static const uint32_t SM_ROW0[SM_BATCHES] = { 0, 152 };
static const uint32_t SM_NROW[SM_BATCHES] = { 152, 45 };

int at_softmax_head(hw_ctx *h, const attn_files *f, int head, const attn_hooks *k)
{
    uint32_t sb = L2_S(head & 1);
    int idx = 0;
    for (int bt = 0; bt < SM_BATCHES; bt++) {
        vec_load l = {
            .op = OP_SOFTMAX, .head = head, .batch = bt,
            .l2_c = sb + S_LINES_PER_ROW * SM_ROW0[bt], .nlines = S_LINES_PER_ROW * SM_NROW[bt], .v_row = 0,
            .row0 = SM_ROW0[bt], .nrow = SM_NROW[bt], .exp = f->s + s_off(head, SM_ROW0[bt]),
        };
        if (hw_cmd_run(h, cmd_v_load(l.l2_c, l.nlines, l.v_row))) FAIL("head %d softmax: ch2_in LOAD %d failed\n", head, bt);
        if (k && k->after_vload && k->after_vload(k->user, &l)) return -1;
        for (uint32_t r = 0; r < SM_NROW[bt]; r += SM_ROWS_PER_CALL, idx++) {
            if (hw_stop_requested()) return -1;
            uint32_t m = SM_NROW[bt] - r < SM_ROWS_PER_CALL ? SM_NROW[bt] - r : SM_ROWS_PER_CALL;
            uint32_t row = SM_ROW0[bt] + r;
            vec_call c = {
                .op = OP_SOFTMAX, .head = head, .idx = idx, .row0 = row, .nrow = m,
                .in_base = S_LINES_PER_ROW * r, .in_len = S_LINES_PER_ROW * m,
                .l2_c = sb + S_LINES_PER_ROW * row, .nlines = S_LINES_PER_ROW * m,
                .gold = f->a + s_off(head, row),
            };
            if (k && k->before_vec && k->before_vec(k->user, &c)) return -1;
            if (hw_bb2_gold_load(h, c.gold, c.nlines)) FAIL("head %d softmax call %d: Golden load failed\n", head, idx);
            if (hw_bb2_run_store(h, c.in_base, c.in_len, c.l2_c, 1, c.nlines, 0, &c.cycles))
                FAIL("head %d softmax call %d failed\n", head, idx);
            if (k && k->after_vec && k->after_vec(k->user, &c)) return -1;
        }
    }
    return 0;
}

/* ---- AV ---------------------------------------------------------------------------------------------------- */
int at_av_head(hw_ctx *h, const attn_files *f, int head, const uint8_t *a4, const uint8_t *vt4,
               const attn_hooks *k)
{
    int b = head & 1;
    if (hw_cmd_run(h, cmd_x_load(L2_A4(b), A4_LINES, 0))) FAIL("head %d AV: A LOAD failed\n", head);
    if (hw_cmd_run(h, cmd_w_load(L2_VT4(head), VT4_LINES, 0))) FAIL("head %d AV: V^T WLOAD failed\n", head);
    for (uint32_t i = 0; i < AV_CALLS; i++) {
        if (hw_stop_requested()) return -1;
        uint32_t t0 = AV_TOK_PER_CALL * i;
        uint32_t nt = VIT_TOKENS - t0 < AV_TOK_PER_CALL ? VIT_TOKENS - t0 : AV_TOK_PER_CALL;
        mac_call c = {
            .op = OP_AV, .head = head, .idx = (int)i, .row0 = t0, .nrow = nt,
            .in_base = A4_LINES_PER_ROW * t0, .in_len = A4_LINES_PER_ROW * nt, .w_base = 0, .w_len = VT4_LINES,
            .out_base = AV_L1_OUT + O_LINES_PER_TOKEN * t0, .out_len = O_LINES_PER_TOKEN * nt,
            .gold = f->o + o_off(head, t0), .in_exp = a4 + LB(A4_LINES_PER_ROW * t0), .w_exp = vt4,
        };
        if (run_mac(h, k, &c)) FAIL("head %d AV call %u failed\n", head, i);
    }
    mac_store s = {
        .op = OP_AV, .head = head, .idx = 0, .l1_row = AV_L1_OUT, .nlines = O_LINES, .l2_c = L2_O(b),
        .row0 = 0, .nrow = VIT_TOKENS, .gold = f->o + o_off(head, 0),
    };
    if (run_store(h, k, &s)) FAIL("head %d AV STORE failed\n", head);
    return 0;
}

/* ---- output projection (one tile of 64 output columns; QKV call pattern) ---------------------------------- */
int at_oproj_tile(hw_ctx *h, const attn_files *f, int tile, const uint8_t *oc, const attn_hooks *k)
{
    if (hw_cmd_run(h, cmd_w_load(L2_WO(tile & 1), WO_LINES, 0))) FAIL("tile %d W_O WLOAD failed\n", tile);
    for (uint32_t g = 0; g < 2; g++) {
        if (hw_stop_requested()) return -1;
        uint32_t g0 = 128u * g;
        uint32_t nt = g ? (VIT_TOKENS - 128u) : 128u;          /* 128 / 69 */
        uint32_t n2 = nt - 64u;                                 /* 64 / 5   */
        if (hw_cmd_run(h, cmd_x_load(L2_OC + X_LINES_PER_TOKEN * g0, X_LINES_PER_TOKEN * nt, QKV_L1_IN0)))
            FAIL("tile %d group %u O concat LOAD failed\n", tile, g);
        mac_call c1 = {
            .op = OP_OPROJ, .head = tile, .idx = (int)(2 * g), .row0 = g0, .nrow = 64,
            .in_base = QKV_L1_IN0, .in_len = X_LINES_PER_TOKEN * 64u, .w_base = 0, .w_len = WO_LINES,
            .out_base = QKV_L1_OUT0, .out_len = 4u * 64u,
            .gold = f->yo + yo_off(tile, g0), .in_exp = oc + LB(X_LINES_PER_TOKEN * g0), .w_exp = f->wo + wo_off(tile),
        };
        mac_call c2 = {
            .op = OP_OPROJ, .head = tile, .idx = (int)(2 * g + 1), .row0 = g0 + 64u, .nrow = n2,
            .in_base = QKV_L1_IN1, .in_len = X_LINES_PER_TOKEN * n2, .w_base = 0, .w_len = WO_LINES,
            .out_base = QKV_L1_OUT1, .out_len = 4u * n2,
            .gold = f->yo + yo_off(tile, g0 + 64u), .in_exp = oc + LB(X_LINES_PER_TOKEN * (g0 + 64u)),
            .w_exp = f->wo + wo_off(tile),
        };
        if (run_mac(h, k, &c1) || run_mac(h, k, &c2)) FAIL("tile %d group %u blackbox failed\n", tile, g);
        mac_store s = {
            .op = OP_OPROJ, .head = tile, .idx = (int)g, .l1_row = QKV_L1_OUT0, .nlines = 4u * nt,
            .l2_c = L2_YO(tile) + 4u * g0, .row0 = g0, .nrow = nt, .gold = f->yo + yo_off(tile, g0),
        };
        if (run_store(h, k, &s)) FAIL("tile %d Y STORE group %u failed\n", tile, g);
    }
    return 0;
}
