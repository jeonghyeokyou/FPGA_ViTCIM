/* vit_ops.h - ViT-Base operations built on vit_hw (dataflow only, no checking).
 *
 * Each operation exposes hook points. vit_main passes no hooks; vit_dbg attaches
 * verification there. The command sequence sent to the hardware is identical in both.
 *
 * Implemented: QKV projection (layer 0, all 12 heads; B structure, token split (a)).
 * Next: K layout for QK^T, QK^T, softmax, AV, ... (added one at a time).
 */
#ifndef VIT_OPS_H
#define VIT_OPS_H

#include "vit_hw.h"

/* ---- ViT-Base dimensions --------------------------------------------------------- */
#define VIT_TOKENS   197
#define VIT_DMODEL   768
#define VIT_HEADS    12
#define VIT_DHEAD    64

/* ---- QKV data sizes in 32 B lines (x.bin / w.bin / y_golden.bin) ------------------ */
#define X_LINES_PER_TOKEN  12u                     /* 768 x INT4 = 384 B                 */
#define X_LINES            (VIT_TOKENS * 12u)      /* 2364 lines = 75,648 B              */
#define W_LINES_PER_P      768u                    /* 64 cols x 768 x INT4 = 24,576 B    */
#define W_LINES_PER_HEAD   (3u * W_LINES_PER_P)    /* 2304 lines = 73,728 B              */
#define Y_LINES_PER_TOKEN  4u                      /* 64 x BF16 = 128 B                  */
#define Y_LINES_PER_P      (VIT_TOKENS * 4u)       /* 788 lines = 25,216 B               */
#define Y_LINES_PER_HEAD   (3u * Y_LINES_PER_P)    /* 2364 lines = 75,648 B              */
#define X_BYTES            ((size_t)X_LINES * LINE_BYTES)
#define W_BYTES_PER_HEAD   ((size_t)W_LINES_PER_HEAD * LINE_BYTES)
#define Y_BYTES_PER_P      ((size_t)Y_LINES_PER_P * LINE_BYTES)
#define Y_BYTES_PER_HEAD   ((size_t)Y_LINES_PER_HEAD * LINE_BYTES)
#define W_FILE_BYTES       (W_BYTES_PER_HEAD * VIT_HEADS)   /* 884,736 */
#define Y_FILE_BYTES       (Y_BYTES_PER_HEAD * VIT_HEADS)   /* 907,776 */

/* ---- L2 layout for QKV (line address c) ---------------------------------------------
 *  X        0x0000  2364 lines (quads 0-2)
 *  buffer A W 0x0C00 (Q +0, K +768, V +1536)   Y 0x1800 (Q +0, K +1024, V +2048)
 *  buffer B W 0x2400                            Y 0x3000
 *  quads 15-31 (c >= 0x3C00) free                                                        */
typedef struct {
    uint32_t x_c;
    uint32_t w_c[2];
    uint32_t y_c[2];
} qkv_layout;

extern const qkv_layout QKV_LAYOUT_DEFAULT;

static inline uint32_t qkv_w_c(const qkv_layout *L, int buf, int p) { return L->w_c[buf] + W_LINES_PER_P * (uint32_t)p; }
static inline uint32_t qkv_y_c(const qkv_layout *L, int buf, int p) { return L->y_c[buf] + 1024u * (uint32_t)p; }

/* ---- L1 / WMEM layout used by one BB call ------------------------------------------- */
#define QKV_L1_IN0    0u      /* tokens g0 .. g0+63       : L1 0 .. 767           */
#define QKV_L1_IN1    768u    /* tokens g0+64 .. g0+nt-1  : L1 768 ..             */
#define QKV_L1_OUT0   1536u   /* Golden#1 output (256 lines)                      */
#define QKV_L1_OUT1   1792u   /* Golden#2 output (4 x n2 lines)                   */

/* ---- host copies of the three files (golden is injected from here) ---------------------- */
typedef struct {
    const uint8_t *x;         /* x.bin        75,648 B  */
    const uint8_t *w;         /* w.bin       884,736 B  */
    const uint8_t *y_golden;  /* y_golden.bin 907,776 B */
} qkv_files;

/* read x.bin, w.bin, y_golden.bin from `dir` (sizes checked); free with qkv_files_free */
int  qkv_files_load(const char *dir, qkv_files *f);
void qkv_files_free(qkv_files *f);

static inline size_t x_off(uint32_t token)             { return (size_t)token * X_LINES_PER_TOKEN * LINE_BYTES; }
static inline size_t w_off(int head, int p)             { return ((size_t)head * W_LINES_PER_HEAD + (size_t)p * W_LINES_PER_P) * LINE_BYTES; }
static inline size_t y_off(int head, int p, uint32_t t) { return (size_t)head * Y_BYTES_PER_HEAD + (size_t)p * Y_BYTES_PER_P + (size_t)t * Y_LINES_PER_TOKEN * LINE_BYTES; }

/* ---- one blackbox call, as seen by the hooks ------------------------------------------ */
typedef struct {
    int      head, p, group, idx;   /* idx 0 = Golden#1, 1 = Golden#2                 */
    uint32_t tok0, ntok;            /* tokens whose outputs this Golden holds         */
    uint32_t in_base, in_len;       /* L1 input rows read by the blackbox             */
    uint32_t w_base, w_len;         /* WMEM rows read by the blackbox                 */
    uint32_t out_base, out_len;     /* L1 rows written with Golden                    */
    const uint8_t *gold;            /* Golden lines injected (host copy)              */
    uint32_t cycles;                /* CYCLES register after the call                 */
} bb_call;

typedef struct {
    int      head, p, group;
    uint32_t l1_row, nlines;        /* STORE source in L1                             */
    uint32_t l2_c;                  /* STORE destination in L2                        */
    uint32_t tok0, ntok;
    const uint8_t *gold;            /* expected bytes of the stored lines             */
} store_info;

typedef struct {
    void *user;
    int (*before_bb)(void *user, const bb_call *c);
    int (*after_bb)(void *user, const bb_call *c);
    int (*after_store)(void *user, const store_info *s);
} qkv_hooks;

/* Q, K, V projection of one head with its W already in L2 buffer `buf`.
 * Sequence per P (Q, K, V):
 *   W LOAD 768 -> WMEM 0
 *   group 0 (tokens 0-127) and group 1 (tokens 128-196):
 *     X LOAD 12*nt -> L1 0
 *     Golden#1 (tokens g0..g0+63)  -> BB(in 0,768  w 0,768 out 1536,256)
 *     Golden#2 (remaining n2)      -> BB(in 768,12*n2 w 0,768 out 1792,4*n2)
 *     STORE 256+4*n2 L1 1536 -> Y_P + 4*g0
 * hooks may be NULL. Returns 0 on success. */
int qkv_proj_head(hw_ctx *h, const qkv_layout *L, const qkv_files *f, int head, int buf,
                  const qkv_hooks *hooks);

#endif
