/* dbg_qkv.h - verification of the QKV projection flow (one head, sequential). */
#ifndef DBG_QKV_H
#define DBG_QKV_H

#include "vit_hw.h"
#include "vit_ops.h"

/* ---- --trace : where one token travels in the main flow (verification moves excluded) ---- */
enum { TV_L2X, TV_L1IN, TV_L2W, TV_WMEM, TV_L1OUT, TV_L2Y, TV_DDRY, TV_N };

typedef struct {
    int      have;
    uint64_t got, exp;          /* first 8 B (lane 0) of the first line             */
    uint32_t n, ok;             /* lines compared / lines equal                    */
} trace_val;

typedef struct {
    int       done;             /* every stage of this P was recorded               */
    uint32_t  g0;               /* first token of the X LOAD group                  */
    bb_call   bb;               /* blackbox call that holds the token's output      */
    uint32_t  y_c;              /* L2 Y line of the token (STORE destination)        */
    trace_val v[TV_N];
} trace_p;

typedef struct {
    int     tok;                /* -1 : no trace                                    */
    int     pmask;              /* bit p : trace Q(1) K(2) V(4)                     */
    int     head;
    trace_p tp[3];
} qkv_trace;

/* C1 -> C5 -> qkv_proj_head() with C2/C3/C4 hooks -> C4 through DDR.
 * tr may be NULL (no trace). Returns 0 when the run completed
 * (pass/fail counts are in dbg_common). */
int  dbg_qkv_run(hw_ctx *h, const qkv_files *f, int head, qkv_trace *tr);

/* print where each whole tensor of the main flow sits in L2 / L1 / WMEM (no hardware access) */
void dbg_qkv_map_print(int head);

/* print the trace collected by dbg_qkv_run (main-flow locations and values only) */
void dbg_qkv_trace_print(const qkv_trace *tr);

#endif
