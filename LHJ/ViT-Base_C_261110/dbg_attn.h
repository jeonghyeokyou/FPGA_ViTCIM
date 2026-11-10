/* dbg_attn.h - verification of the attention flow (one head / one out-proj tile, sequential). */
#ifndef DBG_ATTN_H
#define DBG_ATTN_H

#include "vit_hw.h"
#include "vit_ops.h"
#include "attn_ops.h"

/* L2 scratch used only by vit_dbg --op attn / oproj (group 6, untouched by the main flow) */
#define DA_SCR_L1      0x6000u   /* L1 input readback, up to 1024 lines        */
#define DA_SCR_WMEM    0x6400u   /* WMEM readback, up to 1024 lines            */
#define DA_SCR_OUT     0x6800u   /* L1 output readback, up to 256 lines        */
#define DA_SCR_POISON  0x6900u   /* poison source for L1 output rows, 256      */
#define DA_SCR_INJ     0x6A00u   /* vector blackbox INJECT target (+1 guard)   */

/* one head: QKV (no hooks) -> C6 PS MXFP4 -> C5 -> QK^T, softmax, AV with C2/C3/C4 hooks
 * -> C6 A MXFP4, O concat lines of this head. Returns 0 when the run completed. */
int  dbg_attn_run(hw_ctx *h, const qkv_files *qf, const attn_files *af, int head);

/* one out-proj tile on oc_fp4.bin (file) with hooks -> C4 Y tile -> C6 residual of its 64 columns */
int  dbg_oproj_run(hw_ctx *h, const attn_files *af, int tile);

/* where each tensor of the attention flow sits (computed from attn_ops.h, no hardware access) */
void dbg_attn_map_print(int head);

#endif
