/* layer_run.h - one ViT-Base encoder layer (attention + MLP) on the PL, blackbox = Golden.  JH, 2026-11-11
 *
 * Moved out of vit_main.c (VIT_FULL_TASK.md 6.1) so that vit_main (layer 0) and vit_full (12 layers)
 * run the same command sequence. Bodies of qkv_head / attn_head / out_block / mlp_block are unchanged;
 * the only differences: the layer input x4 (MXFP4, x.bin layout) and h_in (BF16, residual 1 input) are
 * arguments (vit_main passes qf->x / af->hin), and check failures are returned instead of kept in a global.
 *
 *   layer_ctx_init  : DDR DMA buffers + host result buffers (~6 MB), once (after hw_open)
 *   layer_run       : X -> L2, QKV 12 heads -> attention 12 heads -> out proj + residual 1 [-> MLP]
 *   layer_check     : final output checks (15 attention, + 8 MLP) -> number of mismatching units
 *   layer_report    : time / breakdown table of hw->prof
 */
#ifndef LAYER_RUN_H
#define LAYER_RUN_H

#include "vit_hw.h"
#include "vit_ops.h"
#include "attn_ops.h"
#include "mlp_ops.h"

typedef struct {
    hw_ctx           *h;
    const qkv_layout *L;
    const qkv_files  *qf;
    const attn_files *af;
    const mlp_files  *mf;              /* NULL : attention only */
    const uint8_t    *hin;             /* residual 1 input of this run */
    hw_buf            wr, rb, pb;      /* DMA source staging, DMA readback, poison source */
    /* results kept on the host */
    uint8_t *y, *q4, *qs, *k4, *ks, *vt4, *vs, *a, *a4, *as, *o, *oc, *ocs, *yo, *r;
    uint8_t *x2, *x2s, *g, *h4, *h4s, *p, *y2, *r2;   /* MLP */
    float   *acc;                                     /* FC2 accumulator of one tile n */
    size_t   host_bytes;                              /* malloc'ed by layer_ctx_init */
    int      quiet;                                   /* layer_run / layer_check: print failures only */
} layer_ctx;

int    layer_ctx_init(layer_ctx *x, hw_ctx *h);
void   layer_ctx_free(layer_ctx *x);
/* nh heads (1..12); mf != NULL (needs nh == 12) adds the MLP with FC1 tiles 0..ntiles-1 (FC2 only if 48) */
int    layer_run(layer_ctx *x, const qkv_files *qf, const attn_files *af, const mlp_files *mf,
                 const uint8_t *x4, const uint8_t *h_in, int nh, int ntiles);
size_t layer_check(layer_ctx *x, int nh, int ntiles, int *nchecks);
void   layer_report(const hw_ctx *h);

#endif
