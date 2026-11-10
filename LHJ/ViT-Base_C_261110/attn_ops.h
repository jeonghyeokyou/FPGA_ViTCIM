/* attn_ops.h - ViT-Base layer 0 attention after the QKV projection (dataflow, no checking).
 *
 * Same structure as vit_ops: vit_main passes no hooks, vit_dbg attaches verification at the
 * hook points; the command sequence sent to the hardware is identical in both.
 *
 * Data format : MXFP4 (OCP MX v1.0, block 32, E8M0) for every MAC input, BF16 otherwise.
 *               Scales stay in DDR (decision (가), 2026-10-30): the BB model does not read them.
 * Data files  : vit_golden_gen.py (MXFP4) output folder, e.g. vit_l0_mx/.
 *
 * Flow of one head h (b = h % 2)
 *   PS      : Y_h (Q,K,V BF16) -> Q, K MXFP4 (token rows) + V^T MXFP4 (d rows, 256 tokens)
 *   MAC BB  : QK^T   L1 Q (197) x WMEM K (197)    -> S BF16  (row = 13 lines, 197 + 11 zeros)
 *   vec BB  : softmax(S/8) -> A BF16 written over S (ch2_in LOAD 152 + 45 rows, 11 x 19 rows)
 *   PS      : A -> MXFP4 (row = 256 elements = 4 lines, 197 + 59 zeros)
 *   MAC BB  : AV     L1 A (788) x WMEM V^T (256)  -> O BF16  (token = 4 lines)
 *   PS      : O_h -> MXFP4, placed at O concat line 12t + h
 * After 12 heads
 *   MAC BB  : out proj, 12 tiles of 64 output columns (same call pattern as QKV)
 *   PS      : R = BF16(f32(h_in) + f32(Y))
 */
#ifndef ATTN_OPS_H
#define ATTN_OPS_H

#include "vit_ops.h"

/* ---- operations of the profile report -------------------------------------------------- */
enum { OP_OTHER = 0, OP_QKV, OP_QKV_MX, OP_QKT, OP_SOFTMAX, OP_A_MX, OP_AV, OP_O_MX,
       OP_OPROJ, OP_RESID, OP_VERIFY, OP_N };
_Static_assert(OP_N <= PROF_OPS, "PROF_OPS too small");
extern const char *const OP_NAME[OP_N];

/* ---- sizes (32 B lines) ------------------------------------------------------------------ */
#define QK4_LINES          197u    /* Q or K of one head: 64 x FP4 = 1 line per token          */
#define VT4_LINES_PER_D    4u      /* 256 tokens x FP4 = 128 B                                  */
#define VT4_LINES          256u    /* 64 d                                                      */
#define S_LINES_PER_ROW    13u     /* 208 x BF16 = 416 B                                        */
#define S_LINES            (VIT_TOKENS * 13u)   /* 2561                                         */
#define A4_LINES_PER_ROW   4u      /* 256 x FP4                                                 */
#define A4_LINES           (VIT_TOKENS * 4u)    /* 788                                          */
#define O_LINES_PER_TOKEN  4u      /* 64 x BF16                                                 */
#define O_LINES            (VIT_TOKENS * 4u)    /* 788                                          */
#define OC_LINES           X_LINES              /* 2364, line 12t + h                           */
#define WO_LINES           768u    /* one tile: 64 output columns x 768 inputs                 */
#define YO_LINES           (VIT_TOKENS * 4u)    /* 788 per tile                                 */
#define RES_BYTES          ((size_t)VIT_TOKENS * VIT_DMODEL * 2)   /* h_in / R : 302,592 B      */

/* scale bytes (E8M0) */
#define QK_SCALES_PER_HEAD (VIT_TOKENS * 2u)    /* 394  */
#define VT_SCALES_PER_HEAD (VIT_DHEAD * 8u)     /* 512  */
#define A_SCALES_PER_HEAD  (VIT_TOKENS * 8u)    /* 1576 */
#define OC_SCALES          (VIT_TOKENS * 24u)   /* 4728 */

/* ---- L2 layout (v2, 2026-10-29) ------------------------------------------------------------
 *  QKV phase      : X / W A,B / Y A,B in 0x0000-0x3BFF (vit_ops), MXFP4 kept in g4-g5
 *  attention phase: g0-g3 reused, b = head % 2                                                 */
#define L2_Q4(h)   (0x4000u + QK4_LINES * (uint32_t)(h))   /* Q all heads 0x4000-0x493B     */
#define L2_K4(h)   (0x493Cu + QK4_LINES * (uint32_t)(h))   /* K all heads 0x493C-0x5277     */
#define L2_VT4(h)  (0x5278u + VT4_LINES * (uint32_t)(h))   /* V^T all heads 0x5278-0x5E77   */
#define L2_S(b)    ((b) ? 0x1000u : 0x0000u)               /* S, then A in place (2561)      */
#define L2_A4(b)   ((b) ? 0x1C00u : 0x0C00u)               /* A MXFP4 (788)                  */
#define L2_O(b)    ((b) ? 0x2800u : 0x2000u)               /* O BF16 (788)                   */
#define L2_OC      0x0000u                                 /* O concat MXFP4 (2364)          */
#define L2_WO(b)   ((b) ? 0x4800u : 0x4000u)               /* W_O tile, b = tile % 2 (768)   */
#define L2_YO(j)   (0x1000u + 0x400u * (uint32_t)(j))      /* Y tile j (788)                 */

/* ---- L1 / WMEM / vector input memory use --------------------------------------------------- */
#define QKT_ROWS_PER_CALL  19u     /* 19 x 13 = 247 Golden lines                             */
#define QKT_CALLS          11u     /* 10 x 19 + 7                                            */
#define QKT_L1_OUT         1536u
#define SM_ROWS_PER_CALL   19u
#define SM_BATCHES         2       /* input memory 2048 rows: 152 rows (1976) + 45 rows (585) */
#define AV_TOK_PER_CALL    64u     /* 64 x 4 = 256 Golden lines                              */
#define AV_CALLS           4u      /* 64, 64, 64, 5 tokens                                   */
#define AV_L1_OUT          1024u   /* 788 lines, one STORE                                   */

/* ---- data files (vit_l0_mx/) ------------------------------------------------------------------ */
typedef struct {
    const uint8_t *q4, *qs, *k4, *ks, *vt4, *vs;   /* PS quantization of QKV (expected)     */
    const uint8_t *s, *a;                          /* QK^T / softmax Golden (row = 13 lines) */
    const uint8_t *a4, *as;                        /* PS quantization of A (expected)        */
    const uint8_t *o;                              /* AV Golden                              */
    const uint8_t *oc, *ocs;                       /* PS concat + quantization (expected)    */
    const uint8_t *wo;                             /* W_O MXFP4, 12 tiles                    */
    const uint8_t *yo;                             /* out proj Golden, 12 tiles              */
    const uint8_t *hin, *r;                        /* block input, R = h_in + Y (expected)   */
} attn_files;

int  attn_files_load(const char *dir, attn_files *f);
void attn_files_free(attn_files *f);

#define LB(n) ((size_t)(n) * LINE_BYTES)
static inline size_t q4_off(int h)            { return LB(QK4_LINES * (uint32_t)h); }
static inline size_t vt4_off(int h)           { return LB(VT4_LINES * (uint32_t)h); }
static inline size_t s_off(int h, uint32_t r) { return LB(S_LINES * (uint32_t)h + S_LINES_PER_ROW * r); }
static inline size_t a4_off(int h, uint32_t r){ return LB(A4_LINES * (uint32_t)h + A4_LINES_PER_ROW * r); }
static inline size_t o_off(int h, uint32_t t) { return LB(O_LINES * (uint32_t)h + O_LINES_PER_TOKEN * t); }
static inline size_t wo_off(int j)            { return LB(WO_LINES * (uint32_t)j); }
static inline size_t yo_off(int j, uint32_t t){ return LB(YO_LINES * (uint32_t)j + 4u * t); }

/* ---- PS work (host memory) ------------------------------------------------------------------- */
/* y : one head of y_golden layout (Q | K | V, 788 lines each)
 * -> q4, k4 (197 lines), qs, ks (394 B), vt4 (256 lines), vs (512 B) */
int  ps_mx_qkv(const uint8_t *y, uint8_t *q4, uint8_t *qs, uint8_t *k4, uint8_t *ks,
               uint8_t *vt4, uint8_t *vs);
/* a : 2561 lines (row stride 13) -> a4 (788 lines), as (1576 B) */
int  ps_mx_a(const uint8_t *a, uint8_t *a4, uint8_t *as);
/* o : 788 lines of head h -> lines 12t + h of oc, scale bytes t*24 + 2h, +1 of ocs */
int  ps_mx_o(const uint8_t *o, int head, uint8_t *oc, uint8_t *ocs);
/* hin, r : [197][768] BF16 ; yo : 12 tiles of 788 lines */
void ps_residual(const uint8_t *hin, const uint8_t *yo, uint8_t *r);

/* ---- hook points ----------------------------------------------------------------------------- */
typedef struct {
    int      op, head, idx;          /* head = tile for OP_OPROJ                               */
    uint32_t row0, nrow;             /* rows (tokens) whose outputs this Golden holds          */
    uint32_t in_base, in_len;        /* L1 rows read by the blackbox                           */
    uint32_t w_base, w_len;          /* WMEM rows read by the blackbox                         */
    uint32_t out_base, out_len;      /* L1 rows written with Golden                            */
    const uint8_t *gold;             /* Golden lines injected                                   */
    const uint8_t *in_exp, *w_exp;   /* what the L1 / WMEM rows above should hold              */
    uint32_t cycles;
} mac_call;

typedef struct {
    int      op, head, idx;
    uint32_t l1_row, nlines, l2_c;   /* ch1_in STORE                                            */
    uint32_t row0, nrow;
    const uint8_t *gold;             /* expected bytes of the stored lines                      */
} mac_store;

typedef struct {
    int      op, head, batch;
    uint32_t l2_c, nlines, v_row;    /* ch2_in LOAD : L2 -> vector input memory                 */
    uint32_t row0, nrow;             /* S rows                                                 */
    const uint8_t *exp;              /* expected input memory contents                         */
} vec_load;

typedef struct {
    int      op, head, idx;
    uint32_t row0, nrow;             /* S rows of this call                                    */
    uint32_t in_base, in_len;        /* vector input memory rows read                          */
    uint32_t l2_c, nlines;           /* ch2_in STORE target (A over S)                          */
    const uint8_t *gold;
    uint32_t cycles;
} vec_call;

typedef struct {
    void *user;
    int (*before_mac)(void *user, const mac_call *c);
    int (*after_mac)(void *user, const mac_call *c);
    int (*after_store)(void *user, const mac_store *s);
    int (*after_vload)(void *user, const vec_load *l);
    int (*before_vec)(void *user, const vec_call *c);
    int (*after_vec)(void *user, const vec_call *c);
} attn_hooks;

/* ---- operations (hooks may be NULL) ------------------------------------------------------------
 * at_qkt_head    : LOAD Q_h 197 -> L1 0, WLOAD K_h 197 -> WMEM 0,
 *                  11 x [BB(in L1 19r+19, w 0+197, out 1536+247) -> STORE -> S_b + 13*19r]
 * at_softmax_head: 2 x [ch2_in LOAD S rows -> input memory 0], then per 19 rows
 *                  [Golden A -> vector BB(in 13r+13m) -> ch2_in STORE over the same S rows]
 * at_av_head     : LOAD A4_b 788 -> L1 0, WLOAD V^T_h 256 -> WMEM 0,
 *                  4 x BB(in L1 4t0+4nt, w 0+256, out 1024+4t0) -> STORE 788 -> O_b
 * at_oproj_tile  : WLOAD W_O tile (L2_WO(j%2)) 768 -> WMEM 0, then the QKV call pattern on the
 *                  O concat (L2_OC) -> STORE -> Y tile j
 * q4 / k4 / a4 / vt4 / oc : the data the flow placed in L2 (for the hooks' input checks)       */
int at_qkt_head(hw_ctx *h, const attn_files *f, int head, const uint8_t *q4, const uint8_t *k4,
                const attn_hooks *k);
int at_softmax_head(hw_ctx *h, const attn_files *f, int head, const attn_hooks *k);
int at_av_head(hw_ctx *h, const attn_files *f, int head, const uint8_t *a4, const uint8_t *vt4,
               const attn_hooks *k);
int at_oproj_tile(hw_ctx *h, const attn_files *f, int tile, const uint8_t *oc, const attn_hooks *k);

#endif
