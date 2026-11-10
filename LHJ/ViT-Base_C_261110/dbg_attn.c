/* dbg_attn.c - verification of the attention flow (same attn_ops code as vit_main).
 *
 * The blackboxes only read their inputs (values unused) and write Golden, so an output equal to
 * Golden does not show that the right inputs were in place. Inputs are read back right after
 * each call, while nothing else has run:
 *   MAC BB    : L1 input rows / WMEM rows -> ch1_in / ch1_wgt STORE to L2 scratch (g6) -> PS
 *   vector BB : input memory rows through DBG2, right after each ch2_in LOAD
 *
 *  C1  DDR -> L2 by CDMA, read back by the PS
 *  C2  blackbox inputs == the data the flow placed (Q/K, A/V^T, O concat/W_O; S for softmax)
 *  C3  CYCLES: MAC in + w + out + 9 ; vector in + 3*out + 6 (simulation; no ready stall)
 *  C4  L1 output rows, L2 output, DDR copy == Golden; regions poisoned first; guard lines kept;
 *      softmax: rows after the current call still hold S
 *  C5  INJECT flips bit 0 of Golden beat 0 (MAC and vector): exactly that bit is reported
 *  C6  PS results (MXFP4 codes + scales, residual) == the Python files
 */
#include "dbg_attn.h"
#include "dbg_common.h"
#include "mxfp4.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *const OPS[OP_N] = { [OP_QKT] = "QKT", [OP_SOFTMAX] = "SM", [OP_AV] = "AV", [OP_OPROJ] = "OP" };

typedef struct {
    hw_ctx           *h;
    const attn_files *f;
    int               head;
} da_ctx;

static int poison_l2_ps(hw_ctx *h, uint32_t c, uint32_t n, uint32_t seed)
{
    uint8_t *p = malloc(LB(n));
    if (!p) return -1;
    dbg_poison(p, n, seed);
    hw_l2_write(h, c, p, n);
    free(p);
    return 0;
}

/* ---- MAC hooks ------------------------------------------------------------------------------------ */
static int hk_before_mac(void *u, const mac_call *c)
{
    da_ctx *d = u;
    return hw_cmd_run(d->h, cmd_x_load(DA_SCR_POISON, c->out_len, c->out_base));
}

static int hk_after_mac(void *u, const mac_call *c)
{
    da_ctx *d = u;
    char what[112];
    const char *on = OPS[c->op];

    uint32_t exp_cyc = c->in_len + c->w_len + c->out_len + BB_CYCLE_OVERHEAD;
    snprintf(what, sizeof what, "%s #%d CYCLES %u (expect %u)", on, c->idx, c->cycles, exp_cyc);
    dbg_result(C3, what, 1, c->cycles != exp_cyc);

    if (dbg_l1_to_l2(d->h, c->in_base, c->in_len, DA_SCR_L1)) return -1;
    snprintf(what, sizeof what, "%s #%d L1 %u+%u == input rows %u..%u", on, c->idx, c->in_base, c->in_len,
             c->row0, c->row0 + c->nrow - 1);
    dbg_result(C2, what, c->in_len, dbg_cmp_l2(d->h, "L1in", DA_SCR_L1, c->in_exp, c->in_len));

    if (dbg_wmem_to_l2(d->h, c->w_base, c->w_len, DA_SCR_WMEM)) return -1;
    snprintf(what, sizeof what, "%s #%d WMEM %u+%u == weight rows", on, c->idx, c->w_base, c->w_len);
    dbg_result(C2, what, c->w_len, dbg_cmp_l2(d->h, "WMEM", DA_SCR_WMEM, c->w_exp, c->w_len));

    if (dbg_l1_to_l2(d->h, c->out_base, c->out_len, DA_SCR_OUT)) return -1;
    snprintf(what, sizeof what, "%s #%d L1 out %u+%u == Golden", on, c->idx, c->out_base, c->out_len);
    dbg_result(C4, what, c->out_len, dbg_cmp_l2(d->h, "L1out", DA_SCR_OUT, c->gold, c->out_len));
    return 0;
}

static int hk_after_store(void *u, const mac_store *s)
{
    da_ctx *d = u;
    char what[112];
    snprintf(what, sizeof what, "%s STORE L2 0x%04x+%u == Golden rows %u..%u", OPS[s->op], s->l2_c, s->nlines,
             s->row0, s->row0 + s->nrow - 1);
    dbg_result(C4, what, s->nlines, dbg_cmp_l2(d->h, "L2", s->l2_c, s->gold, s->nlines));
    return 0;
}

/* ---- vector hooks ------------------------------------------------------------------------------------ */
static int hk_after_vload(void *u, const vec_load *l)
{
    da_ctx *d = u;
    uint8_t line[LINE_BYTES];
    size_t bad = 0;
    for (uint32_t k = 0; k < l->nlines; k++) {
        if (hw_bb2_dbg_read(d->h, 0, l->v_row + k, line)) return -1;
        bad += dbg_cmp_lines("VIN", line, l->exp + LB(k), 1);
    }
    char what[112];
    snprintf(what, sizeof what, "SM LOAD %d: vec in %u+%u == S rows %u..%u", l->batch, l->v_row, l->nlines,
             l->row0, l->row0 + l->nrow - 1);
    dbg_result(C2, what, l->nlines, bad);
    return 0;
}

static int hk_after_vec(void *u, const vec_call *c)
{
    da_ctx *d = u;
    char what[112];
    uint32_t exp_cyc = c->in_len + 3u * c->nlines + BB2_CYCLE_OVERHEAD;
    snprintf(what, sizeof what, "SM #%d CYCLES2 %u (expect %u)", c->idx, c->cycles, exp_cyc);
    dbg_result(C3, what, 1, c->cycles != exp_cyc);

    snprintf(what, sizeof what, "SM #%d L2 0x%04x+%u == A rows %u..%u", c->idx, c->l2_c, c->nlines,
             c->row0, c->row0 + c->nrow - 1);
    dbg_result(C4, what, c->nlines, dbg_cmp_l2(d->h, "A", c->l2_c, c->gold, c->nlines));

    uint32_t next = c->row0 + c->nrow;
    if (next < VIT_TOKENS) {                       /* the row after this call is not processed yet */
        snprintf(what, sizeof what, "SM #%d L2 row %u still S (not overwritten)", c->idx, next);
        dbg_result(C4, what, S_LINES_PER_ROW, dbg_cmp_l2(d->h, "S", c->l2_c + c->nlines,
                   d->f->s + s_off(d->head, next), S_LINES_PER_ROW));
    }
    return 0;
}

/* ---- C5 ------------------------------------------------------------------------------------------------ */
static int check_inject_mac(hw_ctx *h, const uint8_t *g)
{
    uint8_t got[LINE_BYTES];
    uint32_t cyc;
    for (int inj = 1; inj >= 0; inj--) {
        if (hw_cmd_run(h, cmd_x_load(DA_SCR_POISON, 1, QKV_L1_OUT0))) return -1;
        if (hw_bb_gold_load(h, g, 1)) return -1;
        if (hw_bb_run(h, 0, 0, 0, 0, QKV_L1_OUT0, 1, inj, &cyc)) return -1;
        if (dbg_l1_to_l2(h, QKV_L1_OUT0, 1, DA_SCR_OUT)) return -1;
        hw_l2_read(h, DA_SCR_OUT, got, 1);
        int nbits = 0, bit0 = (got[0] ^ g[0]) & 1;
        for (unsigned i = 0; i < LINE_BYTES; i++) nbits += __builtin_popcount((unsigned)(got[i] ^ g[i]));
        if (inj) {
            printf("      MAC INJECT=1: %d bit(s) differ, bit0 %s\n", nbits, bit0 ? "flipped" : "same");
            dbg_result(C5, "MAC INJECT=1 -> exactly beat 0 bit 0 differs", 1, !(nbits == 1 && bit0));
        } else
            dbg_result(C5, "MAC INJECT=0 -> exact match", 1, nbits != 0);
    }
    return 0;
}

static int check_inject_vec(hw_ctx *h, const uint8_t *g)
{
    uint8_t got[LINE_BYTES], guard[LINE_BYTES], gexp[LINE_BYTES];
    uint32_t cyc;
    dbg_poison(gexp, 1, 300);
    for (int inj = 1; inj >= 0; inj--) {
        if (poison_l2_ps(h, DA_SCR_INJ, 1, 301) || poison_l2_ps(h, DA_SCR_INJ + 1, 1, 300)) return -1;
        if (hw_bb2_gold_load(h, g, 1)) return -1;
        if (hw_bb2_run_store(h, 0, 0, DA_SCR_INJ, 1, 1, inj, &cyc)) return -1;
        hw_l2_read(h, DA_SCR_INJ, got, 1);
        hw_l2_read(h, DA_SCR_INJ + 1, guard, 1);
        int nbits = 0, bit0 = (got[0] ^ g[0]) & 1;
        for (unsigned i = 0; i < LINE_BYTES; i++) nbits += __builtin_popcount((unsigned)(got[i] ^ g[i]));
        int gok = !memcmp(guard, gexp, LINE_BYTES);
        if (inj) {
            printf("      vector INJECT=1: %d bit(s) differ, bit0 %s, next line %s\n", nbits,
                   bit0 ? "flipped" : "same", gok ? "kept" : "CHANGED");
            dbg_result(C5, "vector INJECT=1 -> exactly beat 0 bit 0 differs", 1, !(nbits == 1 && bit0 && gok));
        } else
            dbg_result(C5, "vector INJECT=0 -> exact match", 1, nbits != 0 || !gok);
    }
    return 0;
}

/* ---- helpers ---------------------------------------------------------------------------------------------- */
static size_t cmp_bytes(const uint8_t *got, const uint8_t *exp, size_t n)
{
    size_t bad = 0;
    for (size_t i = 0; i < n; i++) bad += got[i] != exp[i];
    return bad;
}

static int cdma_in(hw_ctx *h, hw_buf *wr, const uint8_t *src, size_t n, uint32_t c)
{
    memcpy(wr->va, src, n);
    hw_cache_sync(wr->va, n);
    return hw_cdma_copy(h, wr->pa, hw_l2_pa(c), n);
}

static int cdma_out(hw_ctx *h, hw_buf *rb, uint32_t c, size_t n, uint8_t *dst)
{
    memset(rb->va, 0x5A, n);
    hw_cache_sync(rb->va, n);
    if (hw_cdma_copy(h, hw_l2_pa(c), rb->pa, n)) return -1;
    hw_cache_sync(rb->va, n);
    memcpy(dst, rb->va, n);
    return 0;
}

/* C1 : CDMA a host block into L2 and read it back through the PS */
static int c1_put(hw_ctx *h, hw_buf *wr, const char *name, const uint8_t *src, uint32_t nlines, uint32_t c)
{
    if (cdma_in(h, wr, src, LB(nlines), c)) return -1;
    char what[96];
    snprintf(what, sizeof what, "%s -> L2 0x%04x", name, c);
    dbg_result(C1, what, nlines, dbg_cmp_l2(h, name, c, src, nlines));
    return 0;
}

/* ---- one head ------------------------------------------------------------------------------------------- */
int dbg_attn_run(hw_ctx *h, const qkv_files *qf, const attn_files *af, int head)
{
    const qkv_layout *L = &QKV_LAYOUT_DEFAULT;
    da_ctx d = { .h = h, .f = af, .head = head };
    attn_hooks hk = { .user = &d, .before_mac = hk_before_mac, .after_mac = hk_after_mac,
                      .after_store = hk_after_store, .after_vload = hk_after_vload, .after_vec = hk_after_vec };
    int b = head & 1, rc = -1;
    char what[112];
    hw_buf wr, rb;
    wr.fd = rb.fd = -1; wr.va = rb.va = NULL;
    uint8_t *y = malloc(Y_BYTES_PER_HEAD), *q4 = malloc(LB(QK4_LINES)), *k4 = malloc(LB(QK4_LINES)),
            *vt4 = malloc(LB(VT4_LINES)), *qs = malloc(QK_SCALES_PER_HEAD), *ks = malloc(QK_SCALES_PER_HEAD),
            *vs = malloc(VT_SCALES_PER_HEAD), *a = malloc(LB(S_LINES)), *a4 = malloc(LB(A4_LINES)),
            *as = malloc(A_SCALES_PER_HEAD), *o = malloc(LB(O_LINES)), *oc = malloc(LB(OC_LINES)), *ocs = malloc(OC_SCALES);
    if (!y || !q4 || !k4 || !vt4 || !qs || !ks || !vs || !a || !a4 || !as || !o || !oc || !ocs) goto out;
    memset(oc, 0xA5, LB(OC_LINES));
    memset(ocs, 0xA5, OC_SCALES);
    if (hw_buf_alloc(&wr, X_BYTES) || hw_buf_alloc(&rb, LB(S_LINES))) goto out;

    /* ---- QKV of this head (its own checks: --op qkv) ---------------------------------------------- */
    printf("\n-- QKV head %d (no per-call checks here; see --op qkv) -------------------\n", head);
    if (c1_put(h, &wr, "X", qf->x, X_LINES, L->x_c)) goto out;
    if (c1_put(h, &wr, "W", qf->w + w_off(head, 0), W_LINES_PER_HEAD, L->w_c[0])) goto out;
    for (int p = 0; p < 3; p++) if (poison_l2_ps(h, qkv_y_c(L, 0, p), Y_LINES_PER_P, 100u + (uint32_t)p)) goto out;
    if (qkv_proj_head(h, L, qf, head, 0, NULL)) goto out;
    for (int p = 0; p < 3; p++)
        if (cdma_out(h, &rb, qkv_y_c(L, 0, p), Y_BYTES_PER_P, y + (size_t)p * Y_BYTES_PER_P)) goto out;
    snprintf(what, sizeof what, "DDR Y h%d (Q,K,V) == y_golden.bin", head);
    dbg_result(C4, what, Y_LINES_PER_HEAD, dbg_cmp_lines("DDRY", y, qf->y_golden + y_off(head, 0, 0), Y_LINES_PER_HEAD));

    /* ---- C6 PS MXFP4 of Q, K, V^T ------------------------------------------------------------------- */
    puts("\n-- C6  PS Q, K, V^T -> MXFP4 -------------------------------------------------");
    if (ps_mx_qkv(y, q4, qs, k4, ks, vt4, vs)) { fprintf(stderr, "ps_mx_qkv failed\n"); goto out; }
    dbg_result(C6, "Q MXFP4 == q_fp4.bin (head)", QK4_LINES, dbg_cmp_lines("Q4", q4, af->q4 + q4_off(head), QK4_LINES));
    dbg_result(C6, "Q scale == q_scale.bin (bytes)", QK_SCALES_PER_HEAD, cmp_bytes(qs, af->qs + QK_SCALES_PER_HEAD * head, QK_SCALES_PER_HEAD));
    dbg_result(C6, "K MXFP4 == k_fp4.bin (head)", QK4_LINES, dbg_cmp_lines("K4", k4, af->k4 + q4_off(head), QK4_LINES));
    dbg_result(C6, "K scale == k_scale.bin (bytes)", QK_SCALES_PER_HEAD, cmp_bytes(ks, af->ks + QK_SCALES_PER_HEAD * head, QK_SCALES_PER_HEAD));
    dbg_result(C6, "V^T MXFP4 == vt_fp4.bin (head)", VT4_LINES, dbg_cmp_lines("VT4", vt4, af->vt4 + vt4_off(head), VT4_LINES));
    dbg_result(C6, "V^T scale == vt_scale.bin (bytes)", VT_SCALES_PER_HEAD, cmp_bytes(vs, af->vs + VT_SCALES_PER_HEAD * head, VT_SCALES_PER_HEAD));

    puts("\n-- C1  MXFP4 -> L2 (g4-g5) ---------------------------------------------------");
    if (c1_put(h, &wr, "Q4", q4, QK4_LINES, L2_Q4(head)) || c1_put(h, &wr, "K4", k4, QK4_LINES, L2_K4(head)) ||
        c1_put(h, &wr, "VT4", vt4, VT4_LINES, L2_VT4(head))) goto out;

    /* ---- C5 ---------------------------------------------------------------------------------------------- */
    puts("\n-- C5  injected error is caught (MAC, vector) --------------------------------");
    {
        uint8_t *pz = malloc(LB(GOLD_LINES));
        if (!pz) goto out;
        dbg_poison(pz, GOLD_LINES, 200u);
        hw_l2_write(h, DA_SCR_POISON, pz, GOLD_LINES);
        free(pz);
    }
    if (check_inject_mac(h, af->s + s_off(head, 0)) || check_inject_vec(h, af->a + s_off(head, 0))) goto out;

    /* ---- QK^T ----------------------------------------------------------------------------------------------- */
    uint32_t sb = L2_S(b), below = (sb - 1u) & (L2_LINES - 1u), above = sb + S_LINES;
    uint8_t gb[LINE_BYTES], ga[LINE_BYTES];
    printf("\n-- QK^T head %d -> S buffer %d (L2 0x%04x) : C2 C3 C4 per call -----------\n", head, b, sb);
    if (poison_l2_ps(h, sb, S_LINES, 400) || poison_l2_ps(h, below, 1, 401) || poison_l2_ps(h, above, 1, 402)) goto out;
    dbg_poison(gb, 1, 401);
    dbg_poison(ga, 1, 402);
    if (at_qkt_head(h, af, head, q4, k4, &hk)) goto out;
    snprintf(what, sizeof what, "L2 S 0x%04x+%u == s_golden.bin (head)", sb, S_LINES);
    dbg_result(C4, what, S_LINES, dbg_cmp_l2(h, "S", sb, af->s + s_off(head, 0), S_LINES));

    /* ---- softmax -------------------------------------------------------------------------------------------- */
    printf("\n-- softmax head %d (vector BB, A over S) : C2 per LOAD, C3 C4 per call ----\n", head);
    if (at_softmax_head(h, af, head, &hk)) goto out;
    snprintf(what, sizeof what, "L2 A 0x%04x+%u == a_golden.bin (head)", sb, S_LINES);
    dbg_result(C4, what, S_LINES, dbg_cmp_l2(h, "A", sb, af->a + s_off(head, 0), S_LINES));
    snprintf(what, sizeof what, "guard L2 0x%04x / 0x%04x kept", below, above);
    dbg_result(C4, what, 2, dbg_cmp_l2(h, "below", below, gb, 1) + dbg_cmp_l2(h, "above", above, ga, 1));

    /* ---- A -> MXFP4 ------------------------------------------------------------------------------------------ */
    puts("\n-- A -> DDR, C6 PS A -> MXFP4, C1 -> L2 ----------------------------------------");
    if (cdma_out(h, &rb, sb, LB(S_LINES), a)) goto out;
    dbg_result(C4, "DDR A == a_golden.bin (head)", S_LINES, dbg_cmp_lines("DDRA", a, af->a + s_off(head, 0), S_LINES));
    if (ps_mx_a(a, a4, as)) { fprintf(stderr, "ps_mx_a failed\n"); goto out; }
    dbg_result(C6, "A MXFP4 == a_fp4.bin (head)", A4_LINES, dbg_cmp_lines("A4", a4, af->a4 + a4_off(head, 0), A4_LINES));
    dbg_result(C6, "A scale == a_scale.bin (bytes)", A_SCALES_PER_HEAD, cmp_bytes(as, af->as + A_SCALES_PER_HEAD * head, A_SCALES_PER_HEAD));
    if (c1_put(h, &wr, "A4", a4, A4_LINES, L2_A4(b))) goto out;

    /* ---- AV ------------------------------------------------------------------------------------------------- */
    printf("\n-- AV head %d -> O buffer %d (L2 0x%04x) : C2 C3 C4 per call --------------\n", head, b, L2_O(b));
    if (poison_l2_ps(h, L2_O(b), O_LINES, 500)) goto out;
    if (at_av_head(h, af, head, a4, vt4, &hk)) goto out;

    /* ---- O -> concat MXFP4 ------------------------------------------------------------------------------------ */
    puts("\n-- O -> DDR, C6 PS O -> concat MXFP4 (lines 12t + head) -----------------------");
    if (cdma_out(h, &rb, L2_O(b), LB(O_LINES), o)) goto out;
    dbg_result(C4, "DDR O == o_golden.bin (head)", O_LINES, dbg_cmp_lines("DDRO", o, af->o + o_off(head, 0), O_LINES));
    if (ps_mx_o(o, head, oc, ocs)) { fprintf(stderr, "ps_mx_o failed\n"); goto out; }
    {
        size_t bad_l = 0, bad_s = 0;
        for (uint32_t t = 0; t < VIT_TOKENS; t++) {
            size_t li = LB(X_LINES_PER_TOKEN * t + (uint32_t)head);
            bad_l += memcmp(oc + li, af->oc + li, LINE_BYTES) != 0;
            bad_s += cmp_bytes(ocs + 24 * t + 2 * head, af->ocs + 24 * t + 2 * head, 2);
        }
        dbg_result(C6, "O concat lines 12t+head == oc_fp4.bin", VIT_TOKENS, bad_l);
        dbg_result(C6, "O concat scale (2 per token) == oc_scale", 2 * VIT_TOKENS, bad_s);
    }
    rc = 0;

out:
    if (h->dma_active || h->q_count) hw_cdma_drain(h);
    hw_buf_free(&wr); hw_buf_free(&rb);
    free(y); free(q4); free(k4); free(vt4); free(qs); free(ks); free(vs);
    free(a); free(a4); free(as); free(o); free(oc); free(ocs);
    return rc;
}

/* ---- one out-proj tile ------------------------------------------------------------------------------------ */
int dbg_oproj_run(hw_ctx *h, const attn_files *af, int tile)
{
    da_ctx d = { .h = h, .f = af, .head = tile };
    attn_hooks hk = { .user = &d, .before_mac = hk_before_mac, .after_mac = hk_after_mac, .after_store = hk_after_store };
    int rc = -1;
    char what[112];
    hw_buf wr, rb;
    wr.fd = rb.fd = -1; wr.va = rb.va = NULL;
    uint8_t *yt = malloc(LB(YO_LINES)), *pz = malloc(LB(GOLD_LINES));
    if (!yt || !pz) goto out;
    if (hw_buf_alloc(&wr, X_BYTES) || hw_buf_alloc(&rb, LB(YO_LINES))) goto out;

    puts("\n-- C1  O concat (oc_fp4.bin) and W_O tile -> L2 ------------------------------");
    if (c1_put(h, &wr, "OC", af->oc, OC_LINES, L2_OC)) goto out;
    if (c1_put(h, &wr, "WO", af->wo + wo_off(tile), WO_LINES, L2_WO(tile & 1))) goto out;
    dbg_poison(pz, GOLD_LINES, 200u);
    hw_l2_write(h, DA_SCR_POISON, pz, GOLD_LINES);
    if (poison_l2_ps(h, L2_YO(tile), YO_LINES, 600)) goto out;

    printf("\n-- out proj tile %d -> Y tile (L2 0x%04x) : C2 C3 C4 per call ------------\n", tile, L2_YO(tile));
    if (at_oproj_tile(h, af, tile, af->oc, &hk)) goto out;
    if (cdma_out(h, &rb, L2_YO(tile), LB(YO_LINES), yt)) goto out;
    snprintf(what, sizeof what, "DDR Y tile %d == yo_golden.bin", tile);
    dbg_result(C4, what, YO_LINES, dbg_cmp_lines("DDRY", yt, af->yo + yo_off(tile, 0), YO_LINES));

    /* C6 : residual of this tile's 64 columns */
    {
        size_t bad = 0;
        for (uint32_t t = 0; t < VIT_TOKENS; t++)
            for (uint32_t c = 0; c < 64; c++) {
                size_t i = ((size_t)t * VIT_DMODEL + 64u * (uint32_t)tile + c) * 2;
                float s = bf16_to_f(rd_bf16(af->hin + i)) + bf16_to_f(rd_bf16(yt + LB(4u * t) + 2 * c));
                bad += f32_to_bf16(s) != rd_bf16(af->r + i);
            }
        snprintf(what, sizeof what, "R cols %d..%d = h_in + Y == r_golden (BF16)", 64 * tile, 64 * tile + 63);
        dbg_result(C6, what, (size_t)VIT_TOKENS * 64, bad);
    }
    rc = 0;

out:
    if (h->dma_active || h->q_count) hw_cdma_drain(h);
    hw_buf_free(&wr); hw_buf_free(&rb);
    free(yt); free(pz);
    return rc;
}

/* ---- map -------------------------------------------------------------------------------------------------- */
static void map_row(const char *name, uint32_t c0, uint32_t nl, const char *note)
{
    uint32_t c1 = c0 + nl - 1;
    int first = 1;
    for (uint32_t c = c0; c <= c1;) {
        uint32_t e = (c | 1023u) < c1 ? (c | 1023u) : c1;
        unsigned g = c >> 12, q = (c >> 10) & 3;
        char seg[64];
        snprintf(seg, sizeof seg, "g%u q%u r%u-%u (block %u-%u)", g, q, c & 1023u, e & 1023u, q * 4, q * 4 + 3);
        if (first)
            printf("  %-10s 0x%04X-0x%04X %5u  %-30s 0x%08llX  %s\n", name, c0, c1, nl, seg,
                   (unsigned long long)hw_l2_pa(c0), note);
        else
            printf("  %-10s %-13s %5s  %-30s\n", "", "", "", seg);
        first = 0;
        c = e + 1;
    }
}

void dbg_attn_map_print(int head)
{
    int b = head & 1;
    char n[64];
    puts("\n==========================================================================");
    printf("  L2 MAP  op attn | head %d (buffer %d) | computed from attn_ops.h\n", head, b);
    puts("==========================================================================");
    printf("  %-10s %-13s %5s  %-30s %-10s  %s\n", "tensor", "L2 c", "lines", "grp/quad/row", "PS addr", "content");
    map_row("Q4 h", L2_Q4(head), QK4_LINES, "Q MXFP4, token t = line t");
    map_row("K4 h", L2_K4(head), QK4_LINES, "K MXFP4, token t = line t (no transpose)");
    map_row("VT4 h", L2_VT4(head), VT4_LINES, "V^T MXFP4, d = 4 lines (197 tokens + 59 zeros)");
    map_row("S/A", L2_S(b), S_LINES, "S BF16, then A in place; row = 13 lines");
    map_row("A4", L2_A4(b), A4_LINES, "A MXFP4, row = 4 lines (197 + 59 zeros)");
    map_row("O", L2_O(b), O_LINES, "O BF16, token = 4 lines");
    puts("  -- after 12 heads (out proj)");
    map_row("OC", L2_OC, OC_LINES, "O concat MXFP4, line 12t + h");
    map_row("WO even", L2_WO(0), WO_LINES, "W_O tile j (j even)");
    map_row("WO odd", L2_WO(1), WO_LINES, "W_O tile j (j odd)");
    for (int j = 0; j < VIT_HEADS; j++) {
        snprintf(n, sizeof n, "Y tile %d", j);
        map_row(n, L2_YO(j), YO_LINES, "out proj output BF16, token = 4 lines");
    }
    puts("  -- L1 / WMEM / vector input memory");
    printf("  QK^T     L1 0..196 Q, WMEM 0..196 K, out L1 %u+247 (19 rows) x 10, +91 x 1 -> STORE each\n", QKT_L1_OUT);
    printf("  softmax  ch2 LOAD rows 0-151 (1976 lines), 152-196 (585) -> input memory 0; 11 x 19 rows\n");
    printf("  AV       L1 0..787 A, WMEM 0..255 V^T, out L1 %u..%u (4 calls) -> one STORE\n", AV_L1_OUT, AV_L1_OUT + O_LINES - 1);
    printf("  out proj WMEM 0..767 W_O tile, L1 as QKV (O concat in place of X)\n");
}
