/* dbg_mlp.h - verification of the MLP flow (one FC1/GELU tile, one FC2 output tile).  JH, 2026-11-10 */
#ifndef DBG_MLP_H
#define DBG_MLP_H

#include "vit_hw.h"
#include "mlp_ops.h"

/* L2 scratch: the g6 lines of dbg_attn.h (DA_SCR_*), untouched by the main flow */

/* --op mlp --tile J : C6 LN2 (whole X2) -> C1 X2, W1 tile -> C5 -> FC1 tile J (C2 C3 C4 per call)
 * -> GELU tile J (C2 per LOAD, C3 C4 per call, guard lines) -> C4 DDR G -> C6 G -> H4 lines of tile J */
int dbg_mlp_run(hw_ctx *h, const attn_files *af, const mlp_files *mf, int tile);

/* --op fc2 --n N : C1 H4 planes 0..3 -> C5 -> FC2 (N, 0..3) (C1 W2, C2 C3 C4 per call, C4 DDR partial)
 * -> C6 accumulate == Y2 tile N -> C6 residual 2 of its 64 columns */
int dbg_fc2_run(hw_ctx *h, const attn_files *af, const mlp_files *mf, int n);

#endif
