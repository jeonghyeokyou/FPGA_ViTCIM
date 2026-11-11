/* vit_main.c - ViT-Base layer 0 attention block on the ZCU102 PL (blackbox outputs Golden).
 *
 * Scope : QKV proj -> PS MXFP4 -> QK^T -> softmax -> PS MXFP4 -> AV -> PS concat MXFP4
 *         -> out proj -> PS residual   (one attention block, 12 heads)
 * Order : sequential, one operation at a time, so that each operation's time is measured alone.
 *         (QKV / attention overlap is not used here.)
 *
 * build : make            (vit_hw.c vit_ops.c attn_ops.c mxfp4.c, -lm)
 * run   : sudo ./vit_main --data DIR [--heads N]
 *           DIR    : vit_golden_gen.py (MXFP4) output folder (x.bin, w.bin, y_golden.bin, q_fp4.bin ...)
 *           --heads: heads 0..N-1 (default 12). N < 12 stops before concat / out proj / residual.
 *
 * Final checks (outputs only; inputs of each blackbox call are checked by vit_dbg):
 *   BB outputs that went L2 -> CDMA -> DDR == Golden : Y(QKV), A, O, Y(out proj)
 *   PS results == Python files                      : Q,K,V^T, A, O concat MXFP4 (+ scales), R
 * L2 output regions and DDR readback buffers are poisoned first (time listed as "verify only").
 *
 * 원본: LHJ/ViT-Base_C_261110/vit_main.c (55d6f24) / JH 2026-11-10: MLP 블록 추가 (MLP_TASK.md 4.4, 8절)
 *   --mlp      : out_block() 뒤에 mlp_block() : LN2 -> FC1/GELU/G->H4 (48 tile) -> FC2 (48) -> Residual 2
 *   --tiles N  : FC1 tile 0..N-1 만 (빠른 확인). N < 48 이면 FC2 / Residual 2 는 건너뜀
 *   최종 검사 추가 : X2, G (L2 -> DDR), H4, P (L2 -> DDR), Y2, R2
 *   JH 2026-11-11 (VIT_FULL_TASK.md 6.1): 실행 순서 · 블록 · 최종 검사 · 시간 표를 layer_run.c 로 옮김.
 *   이 파일은 layer 0 파일을 읽고 layer_run(x.bin, h_in.bin) -> layer_check -> layer_report 만 한다
 *   (명령 순서 · 검사 · 출력은 그대로).
 */
#define _POSIX_C_SOURCE 200809L
#include "layer_run.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>

static void usage(const char *a0)
{
    fprintf(stderr, "usage: sudo %s --data DIR [--heads N(1..12)] [--mlp [--tiles N(1..48)]]\n"
                    "       --mlp needs --heads 12 (MLP starts from R)\n", a0);
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    const char *dir = NULL;
    int nh = VIT_HEADS, mlp = 0, ntiles = (int)FC1_TILES;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--data") && i + 1 < argc) dir = argv[++i];
        else if (!strcmp(argv[i], "--heads") && i + 1 < argc) nh = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--mlp")) mlp = 1;
        else if (!strcmp(argv[i], "--tiles") && i + 1 < argc) ntiles = atoi(argv[++i]);
        else { usage(argv[0]); return 1; }
    }
    if (!dir || nh < 1 || nh > VIT_HEADS || ntiles < 1 || ntiles > (int)FC1_TILES || (mlp && nh != VIT_HEADS)) {
        usage(argv[0]); return 1;
    }

    int rc = 1;
    hw_ctx hw;
    qkv_files qf;
    attn_files af;
    mlp_files mf;
    layer_ctx x;
    memset(&x, 0, sizeof x);
    memset(&af, 0, sizeof af);
    memset(&mf, 0, sizeof mf);
    x.wr.fd = x.rb.fd = x.pb.fd = -1;
    memset(&hw, 0, sizeof hw);
    hw.fd_mem = -1;

    if (qkv_files_load(dir, &qf)) return 1;
    if (attn_files_load(dir, &af)) { qkv_files_free(&qf); return 1; }
    if (mlp && mlp_files_load(dir, &mf)) { attn_files_free(&af); qkv_files_free(&qf); return 1; }

    if (hw_open(&hw)) goto out;
    if (layer_ctx_init(&x, &hw)) goto out;

    puts("==========================================================================");
    puts(mlp ? "  ZCU102 | ViT-Base layer 0 attention + MLP | MXFP4 | blackbox = Golden"
             : "  ZCU102 | ViT-Base layer 0 attention block | MXFP4 | blackbox = Golden");
    puts("==========================================================================");
    printf("  PL0 clock   : %" PRIu64 " Hz (Linux clk_summary)\n", hw.pl0_hz);
    printf("  Heads       : 0..%d   Mode: sequential (one operation at a time)\n", nh - 1);
    if (mlp) printf("  MLP         : FC1 tiles 0..%d%s, LN2 eps %.3g\n", ntiles - 1,
                    ntiles < (int)FC1_TILES ? " (FC2 / residual 2 skipped)" : "", mf.eps);
    printf("  Data        : %s\n", dir);

    double t_all = hw_now();
    if (layer_run(&x, &qf, &af, mlp ? &mf : NULL, qf.x, af.hin, nh, ntiles)) goto out;
    t_all = hw_now() - t_all;

    size_t bad = layer_check(&x, nh, ntiles, NULL);
    layer_report(&hw);
    puts("--------------------------------------------------------------------------");
    printf("  run %.3f ms | L2 commands %lu | blackbox calls %lu | CDMA transfers %lu\n",
           t_all * 1e3, hw.n_cmd, hw.n_bb, hw.n_dma);
    puts("  Scope: data movement + command sequence + PS MXFP4/residual; blackboxes output Golden (no compute).");
    rc = bad ? 2 : 0;

out:
    if (hw.cdma && (hw.dma_active || hw.q_count)) hw_cdma_drain(&hw);
    hw_close(&hw);
    if (mlp) printf("BOARD_RESULT=%s op=layer heads=%d tiles=%d mode=seq\n", rc ? "FAIL" : "PASS", nh, ntiles);
    else     printf("BOARD_RESULT=%s op=attn heads=%d mode=seq\n", rc ? "FAIL" : "PASS", nh);
    layer_ctx_free(&x);
    mlp_files_free(&mf);
    attn_files_free(&af);
    qkv_files_free(&qf);
    return rc;
}
