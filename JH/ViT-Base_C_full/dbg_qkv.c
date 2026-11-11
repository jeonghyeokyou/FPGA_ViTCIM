/* dbg_qkv.c - verification of the QKV projection flow.
 *
 * The blackbox only reads L1/WMEM (values unused) and writes Golden, so Y == Golden alone
 * does not show that the right X and W were in place. While the blackbox runs, pe_busy blocks
 * the NoC and CH1 commands cannot run, so L1/WMEM read back right after the call (before the
 * next LOAD) hold exactly what the blackbox saw. Each call is compared with the x.bin / w.bin
 * slice that belongs to its Golden (same head/P/token index as the Golden itself).
 *
 *  C1  DDR -> L2 by CDMA, read back by the PS
 *  C2  after each BB call: L1 input rows and WMEM rows == expected x.bin / w.bin slice
 *  C3  after each BB call: CYCLES == in_len + w_len + out_len + 9
 *  C4  L1 output rows (after BB), L2 Y (after STORE), DDR Y (after CDMA) == Golden,
 *      with L1 output rows, L2 Y and the DDR buffer poisoned beforehand
 *  C5  INJECT flips bit 0 of Golden beat 0: exactly that bit must be reported; then a
 *      clean run must match exactly
 * Readback uses ch1_in STORE / ch1_wgt STORE into L2 scratch (quads 15+), then the PS.
 */
#include "dbg_qkv.h"
#include "dbg_common.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char PN[3] = { 'Q', 'K', 'V' };

typedef struct {
    hw_ctx           *h;
    const qkv_layout *L;
    const qkv_files  *f;
    int               head;
    qkv_trace        *tr;       /* NULL : no trace */
} dbg_ctx;

/* ---- trace helpers (record only; nothing is sent to the hardware for the trace) ---------- */
static int tr_on(const dbg_ctx *d, int p, uint32_t tok0, uint32_t ntok)
{
    const qkv_trace *t = d->tr;
    return t && t->tok >= 0 && ((t->pmask >> p) & 1) &&
           (uint32_t)t->tok >= tok0 && (uint32_t)t->tok < tok0 + ntok;
}

static void tr_rec(trace_val *v, const uint8_t *got, const uint8_t *exp, uint32_t n)
{
    v->have = 1;
    memcpy(&v->got, got, 8);
    memcpy(&v->exp, exp, 8);
    v->n = n;
    v->ok = 0;
    for (uint32_t k = 0; k < n; k++)
        if (!memcmp(got + (size_t)k * LINE_BYTES, exp + (size_t)k * LINE_BYTES, LINE_BYTES)) v->ok++;
}

/* read n lines of L2 (main-flow location) and record them */
static void tr_rec_l2(dbg_ctx *d, trace_val *v, uint32_t c, const uint8_t *exp, uint32_t n)
{
    uint8_t *tmp = malloc((size_t)n * LINE_BYTES);
    if (!tmp) return;
    hw_l2_read(d->h, c, tmp, n);
    tr_rec(v, tmp, exp, n);
    free(tmp);
}

/* ---- hooks -------------------------------------------------------------------------- */
static int hk_before_bb(void *u, const bb_call *c)
{
    dbg_ctx *d = u;
    /* poison the L1 output rows: a call that writes nothing cannot look right */
    return hw_cmd_run(d->h, cmd_x_load(DBG_SCR_POISON, c->out_len, c->out_base));
}

static int hk_after_bb(void *u, const bb_call *c)
{
    dbg_ctx *d = u;
    char what[96];

    /* C3 */
    uint32_t exp_cyc = c->in_len + c->w_len + c->out_len + BB_CYCLE_OVERHEAD;
    snprintf(what, sizeof what, "%c g%d #%d CYCLES %u (expect %u)", PN[c->p], c->group, c->idx + 1, c->cycles, exp_cyc);
    dbg_result(C3, what, 1, c->cycles != exp_cyc);

    /* C2: L1 input rows == x.bin tokens tok0 .. tok0+ntok-1 */
    if (dbg_l1_to_l2(d->h, c->in_base, c->in_len, DBG_SCR_L1)) return -1;
    snprintf(what, sizeof what, "%c g%d #%d L1 %u+%u == x tok %u..%u", PN[c->p], c->group, c->idx + 1,
             c->in_base, c->in_len, c->tok0, c->tok0 + c->ntok - 1);
    dbg_result(C2, what, c->in_len, dbg_cmp_l2(d->h, "L1in", DBG_SCR_L1, d->f->x + x_off(c->tok0), c->in_len));

    /* C2: WMEM rows == w.bin head/P */
    if (dbg_wmem_to_l2(d->h, c->w_base, c->w_len, DBG_SCR_WMEM)) return -1;
    snprintf(what, sizeof what, "%c g%d #%d WMEM %u+%u == w h%d %c", PN[c->p], c->group, c->idx + 1,
             c->w_base, c->w_len, c->head, PN[c->p]);
    dbg_result(C2, what, c->w_len, dbg_cmp_l2(d->h, "WMEM", DBG_SCR_WMEM, d->f->w + w_off(c->head, c->p), c->w_len));

    /* C4: L1 output rows == Golden */
    if (dbg_l1_to_l2(d->h, c->out_base, c->out_len, DBG_SCR_OUT)) return -1;
    snprintf(what, sizeof what, "%c g%d #%d L1 out %u+%u == Golden", PN[c->p], c->group, c->idx + 1,
             c->out_base, c->out_len);
    dbg_result(C4, what, c->out_len, dbg_cmp_l2(d->h, "L1out", DBG_SCR_OUT, c->gold, c->out_len));

    /* trace: values at the main-flow locations L1 in / WMEM / L1 out (read from the copies above) */
    if (tr_on(d, c->p, c->tok0, c->ntok)) {
        trace_p *t = &d->tr->tp[c->p];
        uint32_t k = (uint32_t)d->tr->tok - c->tok0;
        t->bb = *c;
        tr_rec_l2(d, &t->v[TV_L1IN], DBG_SCR_L1 + X_LINES_PER_TOKEN * k,
                  d->f->x + x_off((uint32_t)d->tr->tok), X_LINES_PER_TOKEN);
        tr_rec_l2(d, &t->v[TV_WMEM], DBG_SCR_WMEM, d->f->w + w_off(c->head, c->p), c->w_len);
        tr_rec_l2(d, &t->v[TV_L1OUT], DBG_SCR_OUT + Y_LINES_PER_TOKEN * k,
                  c->gold + (size_t)Y_LINES_PER_TOKEN * k * LINE_BYTES, Y_LINES_PER_TOKEN);
    }
    return 0;
}

static int hk_after_store(void *u, const store_info *s)
{
    dbg_ctx *d = u;
    char what[96];
    snprintf(what, sizeof what, "%c g%d L2 Y 0x%04x+%u == Golden tok %u..%u", PN[s->p], s->group,
             s->l2_c, s->nlines, s->tok0, s->tok0 + s->ntok - 1);
    dbg_result(C4, what, s->nlines, dbg_cmp_l2(d->h, "L2Y", s->l2_c, s->gold, s->nlines));

    /* trace: L2 Y of the token, X LOAD group start */
    if (tr_on(d, s->p, s->tok0, s->ntok)) {
        trace_p *t = &d->tr->tp[s->p];
        uint32_t k = (uint32_t)d->tr->tok - s->tok0;
        t->g0 = s->tok0;
        t->y_c = s->l2_c + Y_LINES_PER_TOKEN * k;
        tr_rec_l2(d, &t->v[TV_L2Y], t->y_c, s->gold + (size_t)Y_LINES_PER_TOKEN * k * LINE_BYTES, Y_LINES_PER_TOKEN);
    }
    return 0;
}

/* ---- C5: one Golden line through the blackbox with INJECT on, then off --------------------- */
static int check_inject(dbg_ctx *d)
{
    const uint8_t *g = d->f->y_golden + y_off(d->head, 0, 0);   /* Golden line 0 of this head, Q */
    uint8_t got[LINE_BYTES];
    uint32_t cyc;

    for (int inj = 1; inj >= 0; inj--) {
        if (hw_cmd_run(d->h, cmd_x_load(DBG_SCR_POISON, 1, QKV_L1_OUT0))) return -1;
        if (hw_bb_gold_load(d->h, g, 1)) return -1;
        if (hw_bb_run(d->h, 0, 0, 0, 0, QKV_L1_OUT0, 1, inj, &cyc)) return -1;
        if (dbg_l1_to_l2(d->h, QKV_L1_OUT0, 1, DBG_SCR_OUT)) return -1;
        hw_l2_read(d->h, DBG_SCR_OUT, got, 1);

        int nbits = 0, bit0 = (got[0] ^ g[0]) & 1;
        for (unsigned i = 0; i < LINE_BYTES; i++) nbits += __builtin_popcount((unsigned)(got[i] ^ g[i]));
        if (inj) {
            int ok = (nbits == 1 && bit0);
            printf("      INJECT=1: %d bit(s) differ, bit0 %s\n", nbits, bit0 ? "flipped" : "same");
            dbg_result(C5, "INJECT=1 -> exactly beat 0 bit 0 differs", 1, !ok);
        } else {
            dbg_result(C5, "INJECT=0 -> exact match", 1, nbits != 0);
        }
    }
    return 0;
}

int dbg_qkv_run(hw_ctx *h, const qkv_files *f, int head, qkv_trace *tr)
{
    dbg_ctx d = { .h = h, .L = &QKV_LAYOUT_DEFAULT, .f = f, .head = head, .tr = tr };
    if (tr) { tr->head = head; memset(tr->tp, 0, sizeof tr->tp); }
    const qkv_layout *L = d.L;
    hw_buf xb, wb, yb;
    int rc = -1;
    uint8_t *poison = malloc((size_t)Y_LINES_PER_P * LINE_BYTES);
    xb.fd = wb.fd = yb.fd = -1; xb.va = wb.va = yb.va = NULL;
    if (!poison) return -1;

    if (hw_buf_alloc(&xb, X_BYTES) || hw_buf_alloc(&wb, W_BYTES_PER_HEAD) || hw_buf_alloc(&yb, Y_BYTES_PER_HEAD))
        goto out;

    /* ---- C1 --------------------------------------------------------------------------- */
    puts("\n-- C1  DDR -> L2 ----------------------------------------------------------");
    memcpy(xb.va, f->x, X_BYTES);
    hw_cache_sync(xb.va, X_BYTES);
    memcpy(wb.va, f->w + w_off(head, 0), W_BYTES_PER_HEAD);
    hw_cache_sync(wb.va, W_BYTES_PER_HEAD);
    if (hw_cdma_copy(h, xb.pa, hw_l2_pa(L->x_c), X_BYTES)) goto out;
    dbg_result(C1, "X  -> L2 0x0000", X_LINES, dbg_cmp_l2(h, "X", L->x_c, f->x, X_LINES));
    if (hw_cdma_copy(h, wb.pa, hw_l2_pa(L->w_c[0]), W_BYTES_PER_HEAD)) goto out;
    {
        char what[64];
        snprintf(what, sizeof what, "W h%d -> L2 0x%04x (Q,K,V)", head, L->w_c[0]);
        dbg_result(C1, what, W_LINES_PER_HEAD, dbg_cmp_l2(h, "W", L->w_c[0], f->w + w_off(head, 0), W_LINES_PER_HEAD));
    }
    /* trace: L2 X of the token, L2 W of each traced P */
    for (int p = 0; p < 3; p++)
        if (tr_on(&d, p, 0, VIT_TOKENS)) {
            uint32_t t = (uint32_t)tr->tok;
            tr_rec_l2(&d, &tr->tp[p].v[TV_L2X], L->x_c + X_LINES_PER_TOKEN * t, f->x + x_off(t), X_LINES_PER_TOKEN);
            tr_rec_l2(&d, &tr->tp[p].v[TV_L2W], qkv_w_c(L, 0, p), f->w + w_off(head, p), W_LINES_PER_P);
        }

    /* ---- poison: L2 Y regions (buffer 0) and the L1-output poison source ------------------ */
    for (int p = 0; p < 3; p++) {
        dbg_poison(poison, Y_LINES_PER_P, 100u + (uint32_t)p);
        hw_l2_write(h, qkv_y_c(L, 0, p), poison, Y_LINES_PER_P);
    }
    dbg_poison(poison, GOLD_LINES, 200u);
    hw_l2_write(h, DBG_SCR_POISON, poison, GOLD_LINES);

    /* ---- C5 ------------------------------------------------------------------------------ */
    puts("\n-- C5  injected error is caught -------------------------------------------");
    if (check_inject(&d)) goto out;

    /* ---- QKV with C2/C3/C4 hooks ---------------------------------------------------------- */
    printf("\n-- QKV head %d (C2, C3, C4 per call) --------------------------------------\n", head);
    qkv_hooks hk = { .user = &d, .before_bb = hk_before_bb, .after_bb = hk_after_bb, .after_store = hk_after_store };
    if (qkv_proj_head(h, L, f, head, 0, &hk)) goto out;

    /* ---- C4 through DDR ---------------------------------------------------------------------- */
    puts("\n-- C4  Y -> DDR (CDMA) ----------------------------------------------------");
    memset(yb.va, 0x5A, Y_BYTES_PER_HEAD);
    hw_cache_sync(yb.va, Y_BYTES_PER_HEAD);
    for (int p = 0; p < 3; p++)
        if (hw_cdma_submit(h, hw_l2_pa(qkv_y_c(L, 0, p)), yb.pa + (uint64_t)p * Y_BYTES_PER_P, Y_BYTES_PER_P)) goto out;
    if (hw_cdma_drain(h)) goto out;
    hw_cache_sync(yb.va, Y_BYTES_PER_HEAD);
    for (int p = 0; p < 3; p++) {
        char what[64];
        snprintf(what, sizeof what, "DDR Y%c h%d == y_golden.bin", PN[p], head);
        dbg_result(C4, what, Y_LINES_PER_P,
                   dbg_cmp_lines("DDRY", yb.va + (size_t)p * Y_BYTES_PER_P, f->y_golden + y_off(head, p, 0), Y_LINES_PER_P));
        if (tr_on(&d, p, 0, VIT_TOKENS)) {
            uint32_t t = (uint32_t)tr->tok;
            tr_rec(&tr->tp[p].v[TV_DDRY], yb.va + (size_t)p * Y_BYTES_PER_P + (size_t)t * Y_LINES_PER_TOKEN * LINE_BYTES,
                   f->y_golden + y_off(head, p, t), Y_LINES_PER_TOKEN);
            int all = 1;
            for (int v = 0; v < TV_N; v++) all &= tr->tp[p].v[v].have;
            tr->tp[p].done = all;
        }
    }
    rc = 0;

out:
    if (h->dma_active || h->q_count) hw_cdma_drain(h);
    hw_buf_free(&xb); hw_buf_free(&wb); hw_buf_free(&yb);
    free(poison);
    return rc;
}

/* ---- trace print ---------------------------------------------------------------------------- */
/* L2 line range -> "c 0x....  | grp g quad q row a..b | block x-y | PS 0x..", split if it crosses a quad */
static void fmt_l2(char *s, size_t n, uint32_t c0, uint32_t nl)
{
    uint32_t c1 = c0 + nl - 1;
    unsigned g0 = c0 >> 12, q0 = (c0 >> 10) & 3, r0 = c0 & 1023;
    unsigned g1 = c1 >> 12, q1 = (c1 >> 10) & 3, r1 = c1 & 1023;
    uint64_t a0 = hw_l2_pa(c0), a1 = hw_l2_pa(c1) + LINE_BYTES - 1;
    if (g0 == g1 && q0 == q1)
        snprintf(s, n, "c 0x%04X..0x%04X | grp %u quad %u row %u..%u | block %u-%u | PS 0x%08llX..0x%08llX",
                 c0, c1, g0, q0, r0, r1, q0 * 4, q0 * 4 + 3, (unsigned long long)a0, (unsigned long long)a1);
    else
        snprintf(s, n, "c 0x%04X..0x%04X | grp %u quad %u row %u .. grp %u quad %u row %u | block %u-%u / %u-%u"
                 " | PS 0x%08llX..0x%08llX", c0, c1, g0, q0, r0, g1, q1, r1, q0 * 4, q0 * 4 + 3, q1 * 4, q1 * 4 + 3,
                 (unsigned long long)a0, (unsigned long long)a1);
}

static float bf16_to_f(uint16_t b)
{
    uint32_t u = (uint32_t)b << 16;
    float f;
    memcpy(&f, &u, 4);
    return f;
}

void dbg_qkv_trace_print(const qkv_trace *tr)
{
    if (!tr || tr->tok < 0) return;
    const qkv_layout *L = &QKV_LAYOUT_DEFAULT;
    uint32_t tok = (uint32_t)tr->tok;
    char loc[200];

    puts("\n==========================================================================");
    printf("  TRACE  head %d | token %u | main flow only (verification copies not shown)\n", tr->head, tok);
    puts("==========================================================================");
    for (int p = 0; p < 3; p++) {
        if (!((tr->pmask >> p) & 1)) continue;
        const trace_p *t = &tr->tp[p];
        printf("\n-- %c ---------------------------------------------------------------------\n", PN[p]);
        if (!t->done) { puts("  (incomplete: the run stopped before every stage was reached)"); }
        const bb_call *b = &t->bb;
        uint32_t kb = tok - b->tok0;                      /* index inside the blackbox call */
        uint32_t kg = tok - t->g0;                        /* index inside the X LOAD group  */
        size_t   xb = x_off(tok), wb = w_off(tr->head, p), yb = y_off(tr->head, p, tok);

        puts("  [location]");
        printf("  %-14s byte %zu..%zu (%u lines)\n", "DDR x.bin", xb, xb + X_LINES_PER_TOKEN * LINE_BYTES - 1, X_LINES_PER_TOKEN);
        fmt_l2(loc, sizeof loc, L->x_c + X_LINES_PER_TOKEN * tok, X_LINES_PER_TOKEN);
        printf("  %-14s %s\n", "L2 X   CDMA", loc);
        printf("  %-14s L1 row %u..%u   (X LOAD tokens %u..: L2 c 0x%04X -> L1 0)\n", "L1 in  LOAD",
               QKV_L1_IN0 + X_LINES_PER_TOKEN * kg, QKV_L1_IN0 + X_LINES_PER_TOKEN * kg + X_LINES_PER_TOKEN - 1,
               t->g0, L->x_c + X_LINES_PER_TOKEN * t->g0);
        printf("  %-14s byte %zu..%zu (%u lines, head %d %c)\n", "DDR w.bin", wb, wb + W_LINES_PER_P * LINE_BYTES - 1,
               W_LINES_PER_P, tr->head, PN[p]);
        fmt_l2(loc, sizeof loc, qkv_w_c(L, 0, p), W_LINES_PER_P);
        printf("  %-14s %s\n", "L2 W   CDMA", loc);
        printf("  %-14s WMEM row %u..%u\n", "WMEM   WLOAD", b->w_base, b->w_base + b->w_len - 1);
        printf("  %-14s Golden#%d tokens %u..%u : in L1 %u+%u, w WMEM %u+%u, out L1 %u+%u\n", "BB     call",
               b->idx + 1, b->tok0, b->tok0 + b->ntok - 1, b->in_base, b->in_len, b->w_base, b->w_len, b->out_base, b->out_len);
        printf("  %-14s L1 row %u..%u   (Golden line %u..%u)\n", "L1 out BB",
               b->out_base + Y_LINES_PER_TOKEN * kb, b->out_base + Y_LINES_PER_TOKEN * kb + Y_LINES_PER_TOKEN - 1,
               Y_LINES_PER_TOKEN * kb, Y_LINES_PER_TOKEN * kb + Y_LINES_PER_TOKEN - 1);
        fmt_l2(loc, sizeof loc, t->y_c, Y_LINES_PER_TOKEN);
        printf("  %-14s %s\n", "L2 Y   STORE", loc);
        printf("  %-14s byte %zu..%zu (same offset as y_golden.bin)\n", "DDR Y  CDMA", yb, yb + Y_LINES_PER_TOKEN * LINE_BYTES - 1);

        static const char *const NAME[TV_N] = { "L2 X", "L1 in", "L2 W", "WMEM", "L1 out", "L2 Y", "DDR Y" };
        char src[TV_N][48];
        snprintf(src[TV_L2X],   48, "x.bin byte %zu", xb);
        snprintf(src[TV_L1IN],  48, "x.bin byte %zu", xb);
        snprintf(src[TV_L2W],   48, "w.bin byte %zu", wb);
        snprintf(src[TV_WMEM],  48, "w.bin byte %zu", wb);
        snprintf(src[TV_L1OUT], 48, "Golden line %u", Y_LINES_PER_TOKEN * kb);
        snprintf(src[TV_L2Y],   48, "y_golden byte %zu", yb);
        snprintf(src[TV_DDRY],  48, "y_golden byte %zu", yb);
        static const int ORDER[TV_N] = { TV_L2X, TV_L1IN, TV_L2W, TV_WMEM, TV_L1OUT, TV_L2Y, TV_DDRY };

        puts("  [value]  first line, lane 0 (8 B, little-endian)");
        printf("  %-8s %-17s %-17s %-22s %s\n", "stage", "read", "expected", "expected from", "lines");
        for (int i = 0; i < TV_N; i++) {
            const trace_val *v = &t->v[ORDER[i]];
            if (!v->have) { printf("  %-8s (not reached)\n", NAME[ORDER[i]]); continue; }
            printf("  %-8s %016llx  %016llx  %-22s %u/%u %s\n", NAME[ORDER[i]], (unsigned long long)v->got,
                   (unsigned long long)v->exp, src[ORDER[i]], v->ok, v->n, v->ok == v->n ? "OK" : "MISMATCH");
        }
        if (t->v[TV_DDRY].have) {
            uint64_t g = t->v[TV_DDRY].got;
            uint16_t c[4];
            for (int i = 0; i < 4; i++) c[i] = (uint16_t)(g >> (16 * i));
            printf("  [read as]  %c[token %u][col 0..3] = %.4f %.4f %.4f %.4f   (BF16 0x%04x 0x%04x 0x%04x 0x%04x)\n",
                   PN[p], tok, bf16_to_f(c[0]), bf16_to_f(c[1]), bf16_to_f(c[2]), bf16_to_f(c[3]), c[0], c[1], c[2], c[3]);
        }
    }
}

/* ---- L2 map : where each whole tensor of the main flow sits (computed from qkv_layout) ------- */
static void map_row(const char *name, uint32_t c0, uint32_t nl, const char *ddr)
{
    uint32_t c1 = c0 + nl - 1;
    int first = 1;
    for (uint32_t c = c0; c <= c1;) {
        uint32_t e = (c | 1023u) < c1 ? (c | 1023u) : c1;          /* end of this quad segment */
        unsigned g = c >> 12, q = (c >> 10) & 3;
        char seg[64];
        snprintf(seg, sizeof seg, "g%u q%u r%u-%u (block %u-%u)", g, q, c & 1023u, e & 1023u, q * 4, q * 4 + 3);
        if (first)
            printf("  %-7s 0x%04X-0x%04X %5u  %-30s 0x%08llX-0x%08llX  %s\n", name, c0, c1, nl, seg,
                   (unsigned long long)hw_l2_pa(c0), (unsigned long long)(hw_l2_pa(c1) + LINE_BYTES - 1), ddr);
        else
            printf("  %-7s %-13s %5s  %-30s\n", "", "", "", seg);
        first = 0;
        c = e + 1;
    }
}

void dbg_qkv_map_print(int head)
{
    const qkv_layout *L = &QKV_LAYOUT_DEFAULT;
    char ddr[64];
    puts("\n==========================================================================");
    printf("  L2 MAP  op qkv | head %d | main flow only (computed from qkv_layout)\n", head);
    puts("==========================================================================");
    printf("  %-7s %-13s %5s  %-30s %-23s  %s\n", "tensor", "L2 c", "lines", "grp/quad/row", "PS address", "DDR source");
    for (int buf = 0; buf < 2; buf++) {
        printf("  -- buffer %c%s\n", buf ? 'B' : 'A', buf ? " (odd heads in vit_main; vit_dbg uses A)" : "");
        if (!buf) {
            snprintf(ddr, sizeof ddr, "x.bin %zu..%zu", (size_t)0, X_BYTES - 1);
            map_row("X", L->x_c, X_LINES, ddr);
        }
        for (int p = 0; p < 3; p++) {
            char nm[8];
            snprintf(nm, sizeof nm, "W%c", PN[p]);
            snprintf(ddr, sizeof ddr, "w.bin %zu..%zu", w_off(head, p), w_off(head, p) + (size_t)W_LINES_PER_P * LINE_BYTES - 1);
            map_row(nm, qkv_w_c(L, buf, p), W_LINES_PER_P, ddr);
        }
        for (int p = 0; p < 3; p++) {
            char nm[8];
            snprintf(nm, sizeof nm, "%c", PN[p]);
            snprintf(ddr, sizeof ddr, "y_golden %zu..%zu", y_off(head, p, 0), y_off(head, p, 0) + Y_BYTES_PER_P - 1);
            map_row(nm, qkv_y_c(L, buf, p), Y_LINES_PER_P, ddr);
        }
    }
    puts("  -- L1 / WMEM (per P: W LOAD once, then token groups 0-127 and 128-196)");
    printf("  X LOAD   L1 %u..%u (tokens 0-127, 1536 lines) / L1 %u..%u (tokens 128-196, 828 lines)\n",
           QKV_L1_IN0, QKV_L1_IN0 + 1535u, QKV_L1_IN0, QKV_L1_IN0 + 827u);
    printf("  W LOAD   WMEM 0..%u (WQ, then WK, then WV)\n", W_LINES_PER_P - 1);
    printf("  BB in    Golden#1: L1 %u+768 | Golden#2: L1 %u+768 (g0) / %u+60 (g1)\n", QKV_L1_IN0, QKV_L1_IN1, QKV_L1_IN1);
    printf("  BB out   Golden#1: L1 %u+256 | Golden#2: L1 %u+256 (g0) / %u+20 (g1)\n", QKV_L1_OUT0, QKV_L1_OUT1, QKV_L1_OUT1);
    printf("  STORE    L1 %u+512 (g0) / %u+276 (g1) -> Y + 4 x first token\n", QKV_L1_OUT0, QKV_L1_OUT0);
}
