/* mlp_ops.h - ViT-Base layer 0 MLP block after Residual 1 (dataflow, no checking).  JH, 2026-11-10
 *
 * Same structure as attn_ops: vit_main passes no hooks, vit_dbg attaches verification at the
 * hook points (attn_hooks / mac_call / mac_store / vec_load / vec_call are reused, op = OP_FC1 ...).
 *
 * Flow (MLP_TASK.md 4.1)
 *   PS      : R (BF16) -> LN2 -> BF16 -> MXFP4 = X2 (token = 12 lines, x.bin layout)
 *   MAC BB  : FC1 tile j (0..47) : X2 x W1 tile j (64 cols x 768) -> H tile j (BF16, 788 lines)
 *   vec BB  : GELU(H tile j) -> G tile j, written over H (ch2_in LOAD 788, 4 calls 64/64/64/5 tokens)
 *   PS      : G tile j -> MXFP4 into H4 plane k = j / 12, line 12t + (j % 12)  (ps_mx_o)
 *   MAC BB  : FC2 (n = 0..11, k = 0..3) : H4 plane k x W2 (n, k) -> partial (n, k) (BF16, no bias)
 *   PS      : Y2 tile n = BF16(f32 b2 + p(n,0) + .. + p(n,3))   (provisional, MLP_TASK.md 11 (3))
 *   PS      : R2 = BF16(f32(R) + f32(Y2))                       (ps_residual)
 */
#ifndef MLP_OPS_H
#define MLP_OPS_H

#include "attn_ops.h"

/* ---- sizes (32 B lines) --------------------------------------------------------------------- */
#define MLP_HIDDEN     3072u
#define FC1_TILES      48u     /* 64 output columns each                                     */
#define FC2_TILES      12u     /* n : 64 output columns each                                 */
#define FC2_K          4u      /* k : input columns 768k .. 768k+767                         */
#define FC2_CALLS      (FC2_TILES * FC2_K)     /* 48, i = 4n + k                             */
#define X2_LINES       X_LINES                 /* 2364, token = 12 lines                     */
#define W1_LINES       768u                    /* one tile : 64 cols x 768 x FP4             */
#define H_LINES        (VIT_TOKENS * 4u)       /* 788 per tile, token = 4 lines              */
#define H4_LINES       X_LINES                 /* 2364 per plane, line 12t + (j % 12)        */
#define W2_LINES       768u
#define P_LINES        (VIT_TOKENS * 4u)       /* 788 per partial                            */
#define Y2_LINES       (VIT_TOKENS * 4u)       /* 788 per tile                               */
#define X2_SCALES      OC_SCALES               /* 4728 : token*24 + block                    */
#define H4_SCALES      OC_SCALES               /* per plane                                  */
#define H_TILE_ELEMS   (VIT_TOKENS * 64u)      /* 12,608 BF16 / FP32 values of one tile      */

/* ---- L2 layout (MLP_TASK.md 4.3) ---------------------------------------------------------------
 *  FC1 phase : X2 g0, W1 A/B g1, H A/B g2 (b = j & 1)
 *  FC2 phase : W2 A/B over X2 (g0), P A/B over W1 (g1) (b = (4n + k) & 1)
 *  H4 planes : g3, g4, g5, g7 - kept until FC2 ends. g6 = vit_dbg scratch (DA_SCR_*), not used. */
#define L2_X2          0x0000u
#define L2_W1(b)       ((b) ? 0x1800u : 0x1000u)
#define L2_H(b)        ((b) ? 0x2800u : 0x2000u)
#define L2_H4(k)       ((k) == 3 ? 0x7000u : 0x3000u + 0x1000u * (uint32_t)(k))
#define L2_W2(b)       ((b) ? 0x0800u : 0x0000u)
#define L2_P(b)        ((b) ? 0x1800u : 0x1000u)

/* ---- vector BB (GELU) ------------------------------------------------------------------------- */
#define GELU_TOK_PER_CALL  64u     /* 64 x 4 = 256 Golden lines                                */
#define GELU_CALLS         4u      /* 64, 64, 64, 5 tokens                                     */

/* ---- data files (vit_golden_gen.py MLP extension) --------------------------------------------- */
typedef struct {
    float         *ln2_w, *ln2_b, *b2;    /* float32 (host-endian copies)                       */
    const uint8_t *x2, *x2s;              /* LN2 -> MXFP4 (expected)                            */
    const uint8_t *w1;                    /* W1 MXFP4, 48 tiles                                 */
    const uint8_t *h, *g;                 /* FC1 Golden / GELU Golden, 48 tiles of 788 lines    */
    const uint8_t *h4, *h4s;              /* G -> MXFP4 planes (expected)                       */
    const uint8_t *w2;                    /* W2 MXFP4, 48 tiles (i = 4n + k)                    */
    const uint8_t *p;                     /* FC2 partial Golden, 48 x 788 lines                 */
    const uint8_t *y2, *r2;               /* Y2 tiles / R2 (expected)                           */
    double         eps;                   /* LN2 eps : meta.json "layer_norm_eps"               */
} mlp_files;

int  mlp_files_load(const char *dir, mlp_files *f);
void mlp_files_free(mlp_files *f);

static inline size_t w1_off(int j)              { return LB(W1_LINES * (uint32_t)j); }
static inline size_t h_off(int j, uint32_t t)   { return LB(H_LINES * (uint32_t)j + 4u * t); }
static inline size_t h4_off(int k)              { return LB(H4_LINES * (uint32_t)k); }
static inline size_t w2_off(int n, int k)       { return LB(W2_LINES * (4u * (uint32_t)n + (uint32_t)k)); }
static inline size_t p_off(int n, int k, uint32_t t) { return LB(P_LINES * (4u * (uint32_t)n + (uint32_t)k) + 4u * t); }
static inline size_t y2_off(int n, uint32_t t)  { return LB(Y2_LINES * (uint32_t)n + 4u * t); }

/* ---- PS work (mlp_ps.c, host memory; build with -ffp-contract=off) ----------------------------- */
/* r : [197][768] BF16 -> x2 (2364 lines, token*12), x2s (4728 B, token*24 + block)
 * per token, double : mean / var summed i = 0..767 in order, y = ((x - mean) / sqrt(var + eps)) * g + b
 * -> float -> BF16 RNE -> MXFP4                                                                   */
int  ps_ln2_mx(const uint8_t *r, const float *g, const float *b, double eps, uint8_t *x2, uint8_t *x2s);
/* the LN of one token used above (no quantization) : in 768 BF16 (LE bytes) -> out 768 BF16 values (JH 2026-11-11) */
void ps_ln_row(const uint8_t *in, const float *g, const float *b, double eps, uint16_t *out);
/* g : GELU tile j (788 lines) -> lines 12t + (j % 12) of H4 plane j / 12 (h4 = all 4 planes) */
int  ps_mx_g(const uint8_t *g, int tile, uint8_t *h4, uint8_t *h4s);
/* partial (n, k) into acc (12,608 floats of tile n) : k = 0 starts from b2n (64 floats of tile n);
 * k = FC2_K - 1 also writes Y2 tile n (788 lines) to y2n                                           */
void ps_fc2_acc(float *acc, const uint8_t *p, int k, const float *b2n, uint8_t *y2n);

/* ---- operations (hooks may be NULL) ------------------------------------------------------------
 * mlp_fc1_tile : WLOAD L2_W1(j&1) 768 -> WMEM 0, then the QKV call pattern on X2 -> STORE -> L2_H(j&1)
 * mlp_gelu_tile: ch2_in LOAD L2_H(j&1) 788 -> input memory 0, 4 x [Golden G -> vector BB -> STORE over H]
 * mlp_fc2_call : WLOAD L2_W2(i&1) 768 -> WMEM 0, QKV call pattern on H4 plane k -> STORE -> L2_P(i&1)
 * x2 / h4 : the data the flow placed in L2 (for the hooks' input checks)                          */
int mlp_fc1_tile(hw_ctx *h, const mlp_files *f, int tile, const uint8_t *x2, const attn_hooks *k);
int mlp_gelu_tile(hw_ctx *h, const mlp_files *f, int tile, const attn_hooks *k);
int mlp_fc2_call(hw_ctx *h, const mlp_files *f, int n, int kk, const uint8_t *h4, const attn_hooks *k);

#endif
