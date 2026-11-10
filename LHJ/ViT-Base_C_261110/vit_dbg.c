/* vit_dbg.c - step-by-step verification of the ViT-Base flow (same vit_ops code as vit_main).
 *
 * build : make
 * run   : sudo ./vit_dbg --data DIR [--op qkv|attn|oproj] [--layer 0] [--head H] [--tile J] [--map]
 *                        [--trace T [--p Q|K|V]]
 *           --op    : qkv   : QKV projection of one head (C1-C5 per call)
 *                     attn  : one head QKV -> MXFP4 -> QK^T -> softmax -> MXFP4 -> AV -> concat lines
 *                             (C1-C6; per-call checks on QK^T, softmax, AV)
 *                     oproj : one out-proj tile on oc_fp4.bin + residual of its 64 columns
 *           --tile  : out-proj tile 0..11 (default 0, --op oproj)
 *           --layer : layer (now: 0, the data files hold layer 0)
 *           --head  : head 0..11 (default 0)
 *           --map   : after the summary, print where each whole tensor (X, WQ/WK/WV, Q/K/V) sits
 *                     in L2 (line range, grp/quad/row, block, PS address) and L1/WMEM
 *           --trace : token 0..196 - after the summary, print where that token's data sits at
 *                     each main-flow stage and the value read there (no extra hardware commands;
 *                     verification copies are not shown)
 *           --p     : trace only Q, K or V (default: all three)
 * Sequential only. Writes L2 scratch quads 15+ (qkv) or group 6 (attn, oproj) in addition to the
 * normal layout. --trace is for --op qkv only.
 */
#define _POSIX_C_SOURCE 200809L
#include "vit_hw.h"
#include "vit_ops.h"
#include "dbg_common.h"
#include "dbg_qkv.h"
#include "attn_ops.h"
#include "dbg_attn.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>

static void usage(const char *a0)
{
    fprintf(stderr, "usage: sudo %s --data DIR [--op qkv|attn|oproj] [--layer 0] [--head 0..11] [--tile 0..11] [--map]"
                    " [--trace 0..196 [--p Q|K|V]]\n", a0);
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    const char *dir = NULL, *op = "qkv";
    int layer = 0, head = 0, map = 0, tile = 0;
    qkv_trace tr;
    memset(&tr, 0, sizeof tr);
    tr.tok = -1;
    tr.pmask = 7;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--data") && i + 1 < argc) dir = argv[++i];
        else if (!strcmp(argv[i], "--op") && i + 1 < argc) op = argv[++i];
        else if (!strcmp(argv[i], "--layer") && i + 1 < argc) layer = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--head") && i + 1 < argc) head = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--tile") && i + 1 < argc) tile = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--map")) map = 1;
        else if (!strcmp(argv[i], "--trace") && i + 1 < argc) tr.tok = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--p") && i + 1 < argc) {
            const char *s = argv[++i];
            tr.pmask = (!strcmp(s, "Q") || !strcmp(s, "q")) ? 1 : (!strcmp(s, "K") || !strcmp(s, "k")) ? 2 :
                       (!strcmp(s, "V") || !strcmp(s, "v")) ? 4 : 0;
            if (!tr.pmask) { usage(argv[0]); return 1; }
        }
        else { usage(argv[0]); return 1; }
    }
    if (!dir || head < 0 || head >= VIT_HEADS || tile < 0 || tile >= VIT_HEADS || tr.tok < -1 || tr.tok >= VIT_TOKENS) {
        usage(argv[0]); return 1;
    }
    int is_qkv = !strcmp(op, "qkv"), is_attn = !strcmp(op, "attn"), is_oproj = !strcmp(op, "oproj");
    if (!is_qkv && !is_attn && !is_oproj) { fprintf(stderr, "--op %s: qkv, attn or oproj\n", op); return 1; }
    if (!is_qkv && tr.tok >= 0) { fprintf(stderr, "--trace: --op qkv only\n"); return 1; }
    if (layer != 0) { fprintf(stderr, "--layer %d: data files hold layer 0 only\n", layer); return 1; }

    qkv_files f;
    attn_files af;
    hw_ctx hw;
    int rc = 1;
    memset(&hw, 0, sizeof hw);
    memset(&af, 0, sizeof af);
    hw.fd_mem = -1;
    if (qkv_files_load(dir, &f)) return 1;
    if (!is_qkv && attn_files_load(dir, &af)) { qkv_files_free(&f); return 1; }
    if (hw_open(&hw)) goto out;

    puts("==========================================================================");
    if (is_oproj) printf("  ZCU102 | vit_dbg | op %s | layer %d | tile %d\n", op, layer, tile);
    else          printf("  ZCU102 | vit_dbg | op %s | layer %d | head %d\n", op, layer, head);
    puts("==========================================================================");
    printf("  PL0 clock   : %" PRIu64 " Hz (Linux clk_summary)\n", hw.pl0_hz);
    printf("  Data        : %s\n", dir);

    double t = hw_now();
    int run = is_qkv  ? dbg_qkv_run(&hw, &f, head, &tr) :
              is_attn ? dbg_attn_run(&hw, &f, &af, head) : dbg_oproj_run(&hw, &af, tile);
    t = hw_now() - t;
    int fails = dbg_summary();
    printf("  run time %.1f ms | L2 commands %lu | blackbox calls %lu | CDMA transfers %lu\n",
           t * 1e3, hw.n_cmd, hw.n_bb, hw.n_dma);
    if (run) puts("  RUN ABORTED (see error above): counts cover the steps before the abort");
    if (map) { if (is_qkv) dbg_qkv_map_print(head); else dbg_attn_map_print(head); }
    if (is_qkv) dbg_qkv_trace_print(&tr);
    rc = (run || fails) ? 2 : 0;

out:
    hw_close(&hw);
    if (is_oproj) printf("BOARD_RESULT=%s op=%s layer=%d tile=%d\n", rc ? "FAIL" : "PASS", op, layer, tile);
    else          printf("BOARD_RESULT=%s op=%s layer=%d head=%d\n", rc ? "FAIL" : "PASS", op, layer, head);
    attn_files_free(&af);
    qkv_files_free(&f);
    return rc;
}
