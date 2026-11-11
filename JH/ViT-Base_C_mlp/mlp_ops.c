/* mlp_ops.c - MLP dataflow after Residual 1. See mlp_ops.h.  JH, 2026-11-10 */
#include "mlp_ops.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

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

/* float32 little-endian file -> host float array */
static float *read_f32(const char *dir, const char *name, size_t n)
{
    uint8_t *raw = read_file(dir, name, 4 * n);
    float *v = raw ? malloc(4 * n) : NULL;
    if (v)
        for (size_t i = 0; i < n; i++) {
            uint32_t u = (uint32_t)raw[4 * i] | (uint32_t)raw[4 * i + 1] << 8 |
                         (uint32_t)raw[4 * i + 2] << 16 | (uint32_t)raw[4 * i + 3] << 24;
            memcpy(&v[i], &u, 4);
        }
    free(raw);
    return v;
}

/* "layer_norm_eps" of meta.json (written by vit_golden_gen.py); -1 if absent */
static double meta_eps(const char *dir)
{
    char path[1024];
    snprintf(path, sizeof path, "%s/meta.json", dir);
    FILE *fp = fopen(path, "rb");
    if (!fp) return -1;
    static char buf[1 << 20];
    size_t n = fread(buf, 1, sizeof buf - 1, fp);
    fclose(fp);
    buf[n] = 0;
    const char *s = strstr(buf, "\"layer_norm_eps\"");
    if (!s || !(s = strchr(s, ':'))) return -1;
    return strtod(s + 1, NULL);
}

int mlp_files_load(const char *dir, mlp_files *f)
{
    memset(f, 0, sizeof *f);
    struct { const uint8_t **p; const char *name; size_t n; } t[] = {
        { &f->x2,  "x2_fp4.bin",    LB(X2_LINES) },
        { &f->x2s, "x2_scale.bin",  X2_SCALES },
        { &f->w1,  "w1.bin",        LB(W1_LINES) * FC1_TILES },
        { &f->h,   "h_golden.bin",  LB(H_LINES) * FC1_TILES },
        { &f->g,   "g_golden.bin",  LB(H_LINES) * FC1_TILES },
        { &f->h4,  "h4_fp4.bin",    LB(H4_LINES) * FC2_K },
        { &f->h4s, "h4_scale.bin",  (size_t)H4_SCALES * FC2_K },
        { &f->w2,  "w2.bin",        LB(W2_LINES) * FC2_CALLS },
        { &f->p,   "p_golden.bin",  LB(P_LINES) * FC2_CALLS },
        { &f->y2,  "y2_golden.bin", LB(Y2_LINES) * FC2_TILES },
        { &f->r2,  "r2_golden.bin", RES_BYTES },
    };
    for (size_t i = 0; i < sizeof t / sizeof t[0]; i++)
        if (!(*t[i].p = read_file(dir, t[i].name, t[i].n))) { mlp_files_free(f); return -1; }
    if (!(f->ln2_w = read_f32(dir, "ln2_w.bin", VIT_DMODEL)) || !(f->ln2_b = read_f32(dir, "ln2_b.bin", VIT_DMODEL)) ||
        !(f->b2 = read_f32(dir, "b2.bin", VIT_DMODEL))) { mlp_files_free(f); return -1; }
    if ((f->eps = meta_eps(dir)) < 0) {
        fprintf(stderr, "%s/meta.json: \"layer_norm_eps\" not found (generator without the MLP extension?)\n", dir);
        mlp_files_free(f);
        return -1;
    }
    return 0;
}

void mlp_files_free(mlp_files *f)
{
    const void *all[] = { f->ln2_w, f->ln2_b, f->b2, f->x2, f->x2s, f->w1, f->h, f->g, f->h4, f->h4s,
                          f->w2, f->p, f->y2, f->r2 };
    for (size_t i = 0; i < sizeof all / sizeof all[0]; i++) free((void *)all[i]);
    memset(f, 0, sizeof *f);
}

/* ---- blackbox call helpers (same as attn_ops.c, which keeps them static) ----------------------- */
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

/* One 64-column output tile with its W already in WMEM 0 (QKV / out proj call pattern):
 *   group 0 (tokens 0-127) / 1 (128-196): LOAD in_c + 12*g0, 12*nt -> L1 0, BB #1 (64 tokens),
 *   BB #2 (n2 tokens), STORE L1 1536, 4*nt -> out_c + 4*g0
 * gold / in_exp / w_exp : Golden tile (token = 4 lines), input (token = 12 lines), W tile      */
static int mac_tile(hw_ctx *h, const attn_hooks *k, int op, int head, uint32_t in_c, uint32_t out_c,
                    const uint8_t *gold, const uint8_t *in_exp, const uint8_t *w_exp)
{
    for (uint32_t g = 0; g < 2; g++) {
        if (hw_stop_requested()) return -1;
        uint32_t g0 = 128u * g;
        uint32_t nt = g ? (VIT_TOKENS - 128u) : 128u;          /* 128 / 69 */
        uint32_t n2 = nt - 64u;                                 /* 64 / 5   */
        if (hw_cmd_run(h, cmd_x_load(in_c + X_LINES_PER_TOKEN * g0, X_LINES_PER_TOKEN * nt, QKV_L1_IN0)))
            FAIL("op %d %d group %u LOAD failed\n", op, head, g);
        mac_call c1 = {
            .op = op, .head = head, .idx = (int)(2 * g), .row0 = g0, .nrow = 64,
            .in_base = QKV_L1_IN0, .in_len = X_LINES_PER_TOKEN * 64u, .w_base = 0, .w_len = W1_LINES,
            .out_base = QKV_L1_OUT0, .out_len = 4u * 64u,
            .gold = gold + LB(4u * g0), .in_exp = in_exp + LB(X_LINES_PER_TOKEN * g0), .w_exp = w_exp,
        };
        mac_call c2 = {
            .op = op, .head = head, .idx = (int)(2 * g + 1), .row0 = g0 + 64u, .nrow = n2,
            .in_base = QKV_L1_IN1, .in_len = X_LINES_PER_TOKEN * n2, .w_base = 0, .w_len = W1_LINES,
            .out_base = QKV_L1_OUT1, .out_len = 4u * n2,
            .gold = gold + LB(4u * (g0 + 64u)), .in_exp = in_exp + LB(X_LINES_PER_TOKEN * (g0 + 64u)),
            .w_exp = w_exp,
        };
        if (run_mac(h, k, &c1) || run_mac(h, k, &c2)) FAIL("op %d %d group %u blackbox failed\n", op, head, g);
        mac_store s = {
            .op = op, .head = head, .idx = (int)g, .l1_row = QKV_L1_OUT0, .nlines = 4u * nt,
            .l2_c = out_c + 4u * g0, .row0 = g0, .nrow = nt, .gold = gold + LB(4u * g0),
        };
        if (run_store(h, k, &s)) FAIL("op %d %d STORE group %u failed\n", op, head, g);
    }
    return 0;
}

/* ---- FC1 tile j ---------------------------------------------------------------------------------- */
int mlp_fc1_tile(hw_ctx *h, const mlp_files *f, int tile, const uint8_t *x2, const attn_hooks *k)
{
    int b = tile & 1;
    if (hw_cmd_run(h, cmd_w_load(L2_W1(b), W1_LINES, 0))) FAIL("FC1 tile %d W1 WLOAD failed\n", tile);
    if (mac_tile(h, k, OP_FC1, tile, L2_X2, L2_H(b), f->h + h_off(tile, 0), x2, f->w1 + w1_off(tile)))
        FAIL("FC1 tile %d failed\n", tile);
    return 0;
}

/* ---- GELU tile j (vector blackbox, output over H) ------------------------------------------------ */
int mlp_gelu_tile(hw_ctx *h, const mlp_files *f, int tile, const attn_hooks *k)
{
    uint32_t hb = L2_H(tile & 1);
    vec_load l = {
        .op = OP_GELU, .head = tile, .batch = 0, .l2_c = hb, .nlines = H_LINES, .v_row = 0,
        .row0 = 0, .nrow = VIT_TOKENS, .exp = f->h + h_off(tile, 0),
    };
    if (hw_cmd_run(h, cmd_v_load(l.l2_c, l.nlines, l.v_row))) FAIL("GELU tile %d: ch2_in LOAD failed\n", tile);
    if (k && k->after_vload && k->after_vload(k->user, &l)) return -1;
    for (uint32_t i = 0; i < GELU_CALLS; i++) {
        if (hw_stop_requested()) return -1;
        uint32_t t0 = GELU_TOK_PER_CALL * i;
        uint32_t nt = VIT_TOKENS - t0 < GELU_TOK_PER_CALL ? VIT_TOKENS - t0 : GELU_TOK_PER_CALL;
        vec_call c = {
            .op = OP_GELU, .head = tile, .idx = (int)i, .row0 = t0, .nrow = nt,
            .in_base = 4u * t0, .in_len = 4u * nt, .l2_c = hb + 4u * t0, .nlines = 4u * nt,
            .gold = f->g + h_off(tile, t0),
        };
        if (k && k->before_vec && k->before_vec(k->user, &c)) return -1;
        if (hw_bb2_gold_load(h, c.gold, c.nlines)) FAIL("GELU tile %d call %u: Golden load failed\n", tile, i);
        if (hw_bb2_run_store(h, c.in_base, c.in_len, c.l2_c, 1, c.nlines, 0, &c.cycles))
            FAIL("GELU tile %d call %u failed\n", tile, i);
        if (k && k->after_vec && k->after_vec(k->user, &c)) return -1;
    }
    return 0;
}

/* ---- FC2 (n, k) : hook head = i = 4n + k ------------------------------------------------------------ */
int mlp_fc2_call(hw_ctx *h, const mlp_files *f, int n, int kk, const uint8_t *h4, const attn_hooks *k)
{
    int i = 4 * n + kk, b = i & 1;
    if (hw_cmd_run(h, cmd_w_load(L2_W2(b), W2_LINES, 0))) FAIL("FC2 (%d,%d) W2 WLOAD failed\n", n, kk);
    if (mac_tile(h, k, OP_FC2, i, L2_H4(kk), L2_P(b), f->p + p_off(n, kk, 0), h4 + h4_off(kk), f->w2 + w2_off(n, kk)))
        FAIL("FC2 (%d,%d) failed\n", n, kk);
    return 0;
}
