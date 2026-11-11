/* dbg_mlp.c - verification of the MLP flow (same mlp_ops code as vit_main).  JH, 2026-11-10
 *
 * Same method as dbg_attn.c (whose hooks are static, so they are repeated here):
 *   MAC BB    : L1 input rows / WMEM rows -> ch1_in / ch1_wgt STORE to L2 scratch (g6) -> PS
 *   vector BB : input memory rows through DBG2, right after the ch2_in LOAD
 *
 *  C1  DDR -> L2 by CDMA, read back by the PS
 *  C2  blackbox inputs == the data the flow placed (X2 / W1 tile, H tile, H4 plane / W2 tile)
 *  C3  CYCLES: MAC in + w + out + 9 ; vector in + 3*out + 6
 *  C4  L1 output rows, L2 output, DDR copy == Golden; regions poisoned first; guard lines kept;
 *      GELU: tokens after the current call still hold H
 *  C5  INJECT flips bit 0 of Golden beat 0 (MAC and vector): exactly that bit is reported
 *  C6  PS results (LN2 MXFP4, G -> H4 MXFP4, FC2 accumulate, residual 2) == the Python files
 */
#include "dbg_mlp.h"
#include "dbg_attn.h"
#include "dbg_common.h"
#include "mxfp4.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *const OPS[OP_N] = { [OP_FC1] = "FC1", [OP_GELU] = "GELU", [OP_FC2] = "FC2" };

typedef struct {
    hw_ctx          *h;
    const mlp_files *f;
    int              tile;      /* FC1 / GELU tile */
} dm_ctx;

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
    dm_ctx *d = u;
    return hw_cmd_run(d->h, cmd_x_load(DA_SCR_POISON, c->out_len, c->out_base));
}

static int hk_after_mac(void *u, const mac_call *c)
{
    dm_ctx *d = u;
    char what[112];
    const char *on = OPS[c->op];

    uint32_t exp_cyc = c->in_len + c->w_len + c->out_len + BB_CYCLE_OVERHEAD;
    snprintf(what, sizeof what, "%s #%d CYCLES %u (expect %u)", on, c->idx, c->cycles, exp_cyc);
    dbg_result(C3, what, 1, c->cycles != exp_cyc);

    if (dbg_l1_to_l2(d->h, c->in_base, c->in_len, DA_SCR_L1)) return -1;
    snprintf(what, sizeof what, "%s #%d L1 %u+%u == input tokens %u..%u", on, c->idx, c->in_base, c->in_len,
             c->row0, c->row0 + c->nrow - 1);
    dbg_result(C2, what, c->in_len, dbg_cmp_l2(d->h, "L1in", DA_SCR_L1, c->in_exp, c->in_len));

    if (dbg_wmem_to_l2(d->h, c->w_base, c->w_len, DA_SCR_WMEM)) return -1;
    snprintf(what, sizeof what, "%s #%d WMEM %u+%u == weight tile", on, c->idx, c->w_base, c->w_len);
    dbg_result(C2, what, c->w_len, dbg_cmp_l2(d->h, "WMEM", DA_SCR_WMEM, c->w_exp, c->w_len));

    if (dbg_l1_to_l2(d->h, c->out_base, c->out_len, DA_SCR_OUT)) return -1;
    snprintf(what, sizeof what, "%s #%d L1 out %u+%u == Golden", on, c->idx, c->out_base, c->out_len);
    dbg_result(C4, what, c->out_len, dbg_cmp_l2(d->h, "L1out", DA_SCR_OUT, c->gold, c->out_len));
    return 0;
}

static int hk_after_store(void *u, const mac_store *s)
{
    dm_ctx *d = u;
    char what[112];
    snprintf(what, sizeof what, "%s STORE L2 0x%04x+%u == Golden tokens %u..%u", OPS[s->op], s->l2_c, s->nlines,
             s->row0, s->row0 + s->nrow - 1);
    dbg_result(C4, what, s->nlines, dbg_cmp_l2(d->h, "L2", s->l2_c, s->gold, s->nlines));
    return 0;
}

/* ---- vector hooks ------------------------------------------------------------------------------------ */
static int hk_after_vload(void *u, const vec_load *l)
{
    dm_ctx *d = u;
    uint8_t line[LINE_BYTES];
    size_t bad = 0;
    for (uint32_t k = 0; k < l->nlines; k++) {
        if (hw_bb2_dbg_read(d->h, 0, l->v_row + k, line)) return -1;
        bad += dbg_cmp_lines("VIN", line, l->exp + LB(k), 1);
    }
    char what[112];
    snprintf(what, sizeof what, "GELU LOAD: vec in %u+%u == H tile %d", l->v_row, l->nlines, l->head);
    dbg_result(C2, what, l->nlines, bad);
    return 0;
}

static int hk_after_vec(void *u, const vec_call *c)
{
    dm_ctx *d = u;
    char what[112];
    uint32_t exp_cyc = c->in_len + 3u * c->nlines + BB2_CYCLE_OVERHEAD;
    snprintf(what, sizeof what, "GELU #%d CYCLES2 %u (expect %u)", c->idx, c->cycles, exp_cyc);
    dbg_result(C3, what, 1, c->cycles != exp_cyc);

    snprintf(what, sizeof what, "GELU #%d L2 0x%04x+%u == G tokens %u..%u", c->idx, c->l2_c, c->nlines,
             c->row0, c->row0 + c->nrow - 1);
    dbg_result(C4, what, c->nlines, dbg_cmp_l2(d->h, "G", c->l2_c, c->gold, c->nlines));

    uint32_t next = c->row0 + c->nrow;
    if (next < VIT_TOKENS) {                       /* the token after this call is not processed yet */
        snprintf(what, sizeof what, "GELU #%d L2 token %u still H (not overwritten)", c->idx, next);
        dbg_result(C4, what, 4, dbg_cmp_l2(d->h, "H", c->l2_c + c->nlines, d->f->h + h_off(d->tile, next), 4));
    }
    return 0;
}

/* ---- C5 (same as dbg_attn.c) --------------------------------------------------------------------------- */
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

static int c1_put(hw_ctx *h, hw_buf *wr, const char *name, const uint8_t *src, uint32_t nlines, uint32_t c)
{
    if (cdma_in(h, wr, src, LB(nlines), c)) return -1;
    char what[96];
    snprintf(what, sizeof what, "%s -> L2 0x%04x", name, c);
    dbg_result(C1, what, nlines, dbg_cmp_l2(h, name, c, src, nlines));
    return 0;
}

/* poison a region and its two neighbour lines (guards), remember the guard contents */
static int poison_guarded(hw_ctx *h, uint32_t c, uint32_t n, uint32_t seed, uint8_t *gb, uint8_t *ga)
{
    uint32_t below = (c - 1u) & (L2_LINES - 1u), above = c + n;
    if (poison_l2_ps(h, c, n, seed) || poison_l2_ps(h, below, 1, seed + 1) || poison_l2_ps(h, above, 1, seed + 2))
        return -1;
    dbg_poison(gb, 1, seed + 1);
    dbg_poison(ga, 1, seed + 2);
    return 0;
}

static void check_guards(hw_ctx *h, uint32_t c, uint32_t n, const uint8_t *gb, const uint8_t *ga)
{
    char what[112];
    uint32_t below = (c - 1u) & (L2_LINES - 1u), above = c + n;
    snprintf(what, sizeof what, "guard L2 0x%04x / 0x%04x kept", below, above);
    dbg_result(C4, what, 2, dbg_cmp_l2(h, "below", below, gb, 1) + dbg_cmp_l2(h, "above", above, ga, 1));
}

static int load_poison_src(hw_ctx *h)
{
    uint8_t *pz = malloc(LB(GOLD_LINES));
    if (!pz) return -1;
    dbg_poison(pz, GOLD_LINES, 200u);
    hw_l2_write(h, DA_SCR_POISON, pz, GOLD_LINES);
    free(pz);
    return 0;
}

/* ---- --op mlp --tile J ----------------------------------------------------------------------------------- */
int dbg_mlp_run(hw_ctx *h, const attn_files *af, const mlp_files *mf, int tile)
{
    dm_ctx d = { .h = h, .f = mf, .tile = tile };
    attn_hooks hk = { .user = &d, .before_mac = hk_before_mac, .after_mac = hk_after_mac,
                      .after_store = hk_after_store, .after_vload = hk_after_vload, .after_vec = hk_after_vec };
    int b = tile & 1, k = tile / 12, slot = tile % 12, rc = -1;
    uint32_t hb = L2_H(b);
    char what[112];
    hw_buf wr, rb;
    wr.fd = rb.fd = -1; wr.va = rb.va = NULL;
    uint8_t gb[LINE_BYTES], ga[LINE_BYTES];
    uint8_t *x2 = malloc(LB(X2_LINES)), *x2s = malloc(X2_SCALES), *g = malloc(LB(H_LINES)),
            *h4 = malloc(LB(H4_LINES) * FC2_K), *h4s = malloc((size_t)H4_SCALES * FC2_K);
    if (!x2 || !x2s || !g || !h4 || !h4s) goto out;
    memset(h4, 0xA5, LB(H4_LINES) * FC2_K);
    memset(h4s, 0xA5, (size_t)H4_SCALES * FC2_K);
    if (hw_buf_alloc(&wr, X_BYTES) || hw_buf_alloc(&rb, LB(H_LINES))) goto out;

    /* ---- C6 LN2 (PS) ---------------------------------------------------------------------------------- */
    printf("\n-- C6  PS LN2 (R = r_golden.bin) -> MXFP4, eps %.3g ------------------------\n", mf->eps);
    if (ps_ln2_mx(af->r, mf->ln2_w, mf->ln2_b, mf->eps, x2, x2s)) { fprintf(stderr, "ps_ln2_mx failed\n"); goto out; }
    dbg_result(C6, "X2 MXFP4 == x2_fp4.bin", X2_LINES, dbg_cmp_lines("X2", x2, mf->x2, X2_LINES));
    dbg_result(C6, "X2 scale == x2_scale.bin (bytes)", X2_SCALES, cmp_bytes(x2s, mf->x2s, X2_SCALES));

    puts("\n-- C1  X2 and W1 tile -> L2 --------------------------------------------------------");
    if (c1_put(h, &wr, "X2", x2, X2_LINES, L2_X2)) goto out;
    if (c1_put(h, &wr, "W1", mf->w1 + w1_off(tile), W1_LINES, L2_W1(b))) goto out;

    puts("\n-- C5  injected error is caught (MAC, vector) --------------------------------");
    if (load_poison_src(h)) goto out;
    if (check_inject_mac(h, mf->h + h_off(tile, 0)) || check_inject_vec(h, mf->g + h_off(tile, 0))) goto out;

    /* ---- FC1 -------------------------------------------------------------------------------------------- */
    printf("\n-- FC1 tile %d -> H buffer %d (L2 0x%04x) : C2 C3 C4 per call -----------\n", tile, b, hb);
    if (poison_guarded(h, hb, H_LINES, 700, gb, ga)) goto out;
    if (mlp_fc1_tile(h, mf, tile, x2, &hk)) goto out;
    snprintf(what, sizeof what, "L2 H 0x%04x+%u == h_golden.bin (tile)", hb, H_LINES);
    dbg_result(C4, what, H_LINES, dbg_cmp_l2(h, "H", hb, mf->h + h_off(tile, 0), H_LINES));

    /* ---- GELU ------------------------------------------------------------------------------------------- */
    printf("\n-- GELU tile %d (vector BB, G over H) : C2 per LOAD, C3 C4 per call -------\n", tile);
    if (mlp_gelu_tile(h, mf, tile, &hk)) goto out;
    snprintf(what, sizeof what, "L2 G 0x%04x+%u == g_golden.bin (tile)", hb, H_LINES);
    dbg_result(C4, what, H_LINES, dbg_cmp_l2(h, "G", hb, mf->g + h_off(tile, 0), H_LINES));
    check_guards(h, hb, H_LINES, gb, ga);

    /* ---- G -> H4 ---------------------------------------------------------------------------------------- */
    printf("\n-- G -> DDR, C6 PS G -> H4 plane %d lines 12t + %d -------------------------\n", k, slot);
    if (cdma_out(h, &rb, hb, LB(H_LINES), g)) goto out;
    dbg_result(C4, "DDR G == g_golden.bin (tile)", H_LINES, dbg_cmp_lines("DDRG", g, mf->g + h_off(tile, 0), H_LINES));
    if (ps_mx_g(g, tile, h4, h4s)) { fprintf(stderr, "ps_mx_g failed\n"); goto out; }
    {
        size_t bad_l = 0, bad_s = 0;
        for (uint32_t t = 0; t < VIT_TOKENS; t++) {
            size_t li = h4_off(k) + LB(X_LINES_PER_TOKEN * t + (uint32_t)slot);
            size_t si = (size_t)H4_SCALES * (size_t)k + 24 * t + 2 * (size_t)slot;
            bad_l += memcmp(h4 + li, mf->h4 + li, LINE_BYTES) != 0;
            bad_s += cmp_bytes(h4s + si, mf->h4s + si, 2);
        }
        snprintf(what, sizeof what, "H4 plane %d lines 12t+%d == h4_fp4.bin", k, slot);
        dbg_result(C6, what, VIT_TOKENS, bad_l);
        snprintf(what, sizeof what, "H4 plane %d scale (2 per token) == h4_scale", k);
        dbg_result(C6, what, 2 * VIT_TOKENS, bad_s);
    }
    rc = 0;

out:
    if (h->dma_active || h->q_count) hw_cdma_drain(h);
    hw_buf_free(&wr); hw_buf_free(&rb);
    free(x2); free(x2s); free(g); free(h4); free(h4s);
    return rc;
}

/* ---- --op fc2 --n N ------------------------------------------------------------------------------------- */
int dbg_fc2_run(hw_ctx *h, const attn_files *af, const mlp_files *mf, int n)
{
    dm_ctx d = { .h = h, .f = mf, .tile = -1 };
    attn_hooks hk = { .user = &d, .before_mac = hk_before_mac, .after_mac = hk_after_mac, .after_store = hk_after_store };
    int rc = -1;
    char what[112];
    hw_buf wr, rb;
    wr.fd = rb.fd = -1; wr.va = rb.va = NULL;
    uint8_t gb[LINE_BYTES], ga[LINE_BYTES];
    uint8_t *p = malloc(LB(P_LINES)), *y2 = malloc(LB(Y2_LINES));
    float *acc = malloc(sizeof(float) * H_TILE_ELEMS);
    if (!p || !y2 || !acc) goto out;
    memset(y2, 0xA5, LB(Y2_LINES));
    if (hw_buf_alloc(&wr, X_BYTES) || hw_buf_alloc(&rb, LB(P_LINES))) goto out;

    puts("\n-- C1  H4 planes 0..3 (h4_fp4.bin) -> L2 g3, g4, g5, g7 -------------------------");
    for (int k = 0; k < (int)FC2_K; k++) {
        snprintf(what, sizeof what, "H4[%d]", k);
        if (c1_put(h, &wr, what, mf->h4 + h4_off(k), H4_LINES, L2_H4(k))) goto out;
    }

    puts("\n-- C5  injected error is caught (MAC) ----------------------------------------");
    if (load_poison_src(h) || check_inject_mac(h, mf->p + p_off(n, 0, 0))) goto out;

    for (int k = 0; k < (int)FC2_K; k++) {
        int i = 4 * n + k, b = i & 1;
        printf("\n-- FC2 (%d,%d) i %d : W2 -> L2 0x%04x, partial -> L2 0x%04x : C2 C3 C4 per call --\n",
               n, k, i, L2_W2(b), L2_P(b));
        if (c1_put(h, &wr, "W2", mf->w2 + w2_off(n, k), W2_LINES, L2_W2(b))) goto out;
        if (poison_guarded(h, L2_P(b), P_LINES, 800u + 4u * (uint32_t)k, gb, ga)) goto out;
        if (mlp_fc2_call(h, mf, n, k, mf->h4, &hk)) goto out;
        check_guards(h, L2_P(b), P_LINES, gb, ga);
        if (cdma_out(h, &rb, L2_P(b), LB(P_LINES), p)) goto out;
        snprintf(what, sizeof what, "DDR partial (%d,%d) == p_golden.bin", n, k);
        dbg_result(C4, what, P_LINES, dbg_cmp_lines("DDRP", p, mf->p + p_off(n, k, 0), P_LINES));
        ps_fc2_acc(acc, p, k, mf->b2 + 64 * n, y2);
    }

    puts("\n-- C6  PS accumulate (f32 b2 + p0..p3) and residual 2 of this tile ----------");
    snprintf(what, sizeof what, "Y2 tile %d == y2_golden.bin", n);
    dbg_result(C6, what, Y2_LINES, dbg_cmp_lines("Y2", y2, mf->y2 + y2_off(n, 0), Y2_LINES));
    {
        size_t bad = 0;
        for (uint32_t t = 0; t < VIT_TOKENS; t++)
            for (uint32_t c = 0; c < 64; c++) {
                size_t ri = ((size_t)t * VIT_DMODEL + 64u * (uint32_t)n + c) * 2;
                float s = bf16_to_f(rd_bf16(af->r + ri)) + bf16_to_f(rd_bf16(y2 + LB(4u * t) + 2 * c));
                bad += f32_to_bf16(s) != rd_bf16(mf->r2 + ri);
            }
        snprintf(what, sizeof what, "R2 cols %d..%d = R + Y2 == r2_golden (BF16)", 64 * n, 64 * n + 63);
        dbg_result(C6, what, (size_t)VIT_TOKENS * 64, bad);
    }
    rc = 0;

out:
    if (h->dma_active || h->q_count) hw_cdma_drain(h);
    hw_buf_free(&wr); hw_buf_free(&rb);
    free(p); free(y2); free(acc);
    return rc;
}
