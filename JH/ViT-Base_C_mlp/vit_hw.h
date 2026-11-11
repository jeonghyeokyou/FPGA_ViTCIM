/* vit_hw.h - ZCU102 PL (L2 1MiB + NoC + L1 + blackbox) hardware access layer.
 *
 * 원본: LHJ/ViT-Base_C_261110/vit_hw.h (55d6f24) / JH 2026-11-10: PROF_OPS 16 -> 24
 *       (MLP 연산 7개 추가로 OP_N = 18, attn_ops.h 의 _Static_assert 를 넘지 않게)
 *
 * Shared by vit_main (ViT-Base flow) and vit_dbg (verification flow).
 * Address map: Vivado Address Editor, BD l2_bb_d, 2026-10-23.
 * RTL: share3 + ch0remap (TOP_L2_cache.sv md5 9d45fc4f974963a7f76d4f08320f9c36)
 *      + ch2lin (cmd_decoder_channel_2_in.sv sha256 a2c957c8..., bitstream 2026-10-30).
 *
 * L2 line address c (15 bit) = {grp[2:0], quad[1:0], row[9:0]}, one line = 256 bit = 32 B.
 * With ch0remap, PS/CDMA byte address = L2_DATA_BASE + 32*c (+ 8*lane): DDR order = line order.
 */
#ifndef VIT_HW_H
#define VIT_HW_H

#include <stdint.h>
#include <stddef.h>

/* ---- address map ------------------------------------------------------------ */
#define L2_DATA_BASE   UINT64_C(0xA0000000)   /* S_AXI_DATA, 1 MiB             */
#define L2_DATA_SIZE   0x100000UL
#define L2_CMD_BASE    UINT64_C(0xA0100000)   /* S_AXI_CMD (64-bit AXI4-Lite)  */
#define L2_CMD_SIZE    0x1000UL
#define BB_CTRL_BASE   UINT64_C(0xA0101000)   /* S_AXI_BB (32-bit AXI4-Lite)   */
#define BB_CTRL_SIZE   0x1000UL
#define CDMA_BASE      UINT64_C(0xA0110000)   /* axi_cdma_0/S_AXI_LITE         */
#define CDMA_SIZE      0x10000UL
#define DDR_LOW_END    UINT64_C(0x80000000)   /* CDMA sees DDR 0x0 .. 0x7FFF_FFFF */

/* PL0 clock as reported by Linux (clk_summary pl0_ref), set by the device-tree overlay
 * (assigned-clock-rates = <214264286>). Not the Vivado value (214264297). */
#define PL0_EXPECT_HZ  UINT64_C(214264286)

/* ---- geometry ----------------------------------------------------------------- */
#define LINE_BYTES     32u
#define L2_LINES       32768u
#define L1_LINES       2048u
#define WMEM_LINES     1024u
#define GOLD_LINES     256u

/* ---- L2 command adapter registers (axi_lite_l2_cmd_adapter.sv, 64-bit) -------- */
#define CMD_PUSH       0x000
#define CMD_STATUS     0x008
#define CMD_ACCEPTED   0x010
#define CMD_FORWARDED  0x018
#define CMD_BUSY       0x020   /* [3:0] ch1_in, ch2_in, ch1_wgt, ch2_wgt               */
#define CMD_ERRORS     0x028   /* sticky, W1C                                          */
#define CMD_VERSION    0x030   /* [31:0] = 0x00010001                                  */
#define CMD_DONE       0x038   /* [31:0] completed command count                       */
#define CMD_EXEC       0x040
#define CMD_VERSION_ID 0x00010001u

/* ---- CH1 blackbox registers (axi_lite_bb_ctrl.sv, 32-bit) ---------------------- */
#define BB_CTRL        0x20    /* W: bit0 START (pulse), bit1 INJECT                    */
#define BB_IN          0x24    /* {in_len[27:16], in_base[10:0]}                        */
#define BB_OUT         0x28    /* {out_len[24:16], out_base[10:0]}                      */
#define BB_LAT         0x2C
#define BB_STATUS      0x30    /* {err_start_busy[3], 0, done[1], busy[0]}              */
#define BB_CYCLES      0x40
#define BB_GADDR       0x44
#define BB_GCOMMIT     0x48
#define BB_WGT         0x4C    /* {w_len[26:16], w_base[9:0]}                           */
#define BB_WIN         0x80    /* 0x80..0x9C, word k = bits [32k+31:32k]                */

/* blackbox_ip with LATENCY 0 and GUARD 2: CYCLES = in_len + w_len + out_len + 9
 * (simulation T18: 768+768+256 -> 1801, 60+768+20 -> 857). */
#define BB_CYCLE_OVERHEAD 9u

/* ---- CH2 (vector) blackbox registers (axi_lite_bb_ctrl.sv bank 2, 32-bit) ------- */
#define BB2_CTRL       0x120   /* W: bit0 START (pulse), bit1 INJECT, bit2 HS, bit3 PREC */
#define BB2_IN         0x124   /* {in_len[27:16], in_base[10:0]}  input memory          */
#define BB2_SHAPE      0x128   /* {nb[30:24], h[19:10], w[9:0]}   output beats nb*h*w   */
#define BB2_LAT        0x12C
#define BB2_STATUS     0x130   /* {err_start_busy[3], dbg_valid[2], done[1], busy[0]}   */
#define BB2_CYCLES     0x140
#define BB2_GADDR      0x144
#define BB2_GCOMMIT    0x148
#define BB2_WGT        0x14C   /* {w_len[25:16], w_base[8:0]}     weight memory         */
#define BB2_DBG        0x150   /* W: {sel[16], row[10:0]} -> read one row (0 input, 1 weight) */
#define BB2_DBG_DATA   0x160   /* 0x160..0x17C : the row read by DBG2                    */
#define VIN_LINES      2048u   /* vector blackbox input memory rows                      */
#define VW_LINES       512u    /* vector blackbox weight memory rows                     */

/* blackbox_nl, LATENCY 0, GUARD 2, no ready stall: CYCLES2 = in_len + w_len + 3*beats + 6
 * (simulation T20 0+0+3*32+6 = 102, T21 247+0+3*247+6 = 994, 91+0+3*91+6 = 370). */
#define BB2_CYCLE_OVERHEAD 6u

/* ---- CDMA registers ----------------------------------------------------------- */
#define CDMACR         0x00
#define CDMASR         0x04
#define CDMA_SA        0x18
#define CDMA_SA_MSB    0x1C
#define CDMA_DA        0x20
#define CDMA_DA_MSB    0x24
#define CDMA_BTT       0x28

/* ---- L2 command words (bb256_pkg.sv, simulation-verified) ---------------------- *
 *  ch1_in  LOAD  001 : L2 [54:40], len-1 [39:29], L1   [28:18], multicast [14:7] = 1
 *  ch1_in  STORE 010 : L2 [55:41], len-1 [40:27], cluster [26:24] = 0, L1 [23:13]
 *  ch1_wgt LOAD  101 : L2 [53:39], len-1 [38:29], WMEM [28:19], multicast [14:7] = 1
 *  ch1_wgt STORE 110 : L2 [54:40], len-1 [39:27], cluster [26:24] = 0, WMEM [23:14]
 *  [59:58] : LOAD 00 = burst, STORE 10 = burst (handshake LOAD is not used).          */
static inline uint64_t cmd_x_load(uint32_t l2_c, uint32_t n, uint32_t l1_row)
{
    return (UINT64_C(1) << 60) | ((uint64_t)(l2_c & 0x7FFF) << 40) |
           ((uint64_t)((n - 1) & 0x7FF) << 29) | ((uint64_t)(l1_row & 0x7FF) << 18) |
           (UINT64_C(1) << 7);
}
static inline uint64_t cmd_x_store(uint32_t l1_row, uint32_t n, uint32_t l2_c)
{
    return (UINT64_C(2) << 60) | (UINT64_C(2) << 58) | ((uint64_t)(l2_c & 0x7FFF) << 41) |
           ((uint64_t)((n - 1) & 0x3FFF) << 27) | ((uint64_t)(l1_row & 0x7FF) << 13);
}
static inline uint64_t cmd_w_load(uint32_t l2_c, uint32_t n, uint32_t w_row)
{
    return (UINT64_C(5) << 60) | ((uint64_t)(l2_c & 0x7FFF) << 39) |
           ((uint64_t)((n - 1) & 0x3FF) << 29) | ((uint64_t)(w_row & 0x3FF) << 19) |
           (UINT64_C(1) << 7);
}
static inline uint64_t cmd_w_store(uint32_t w_row, uint32_t n, uint32_t l2_c)
{
    return (UINT64_C(6) << 60) | (UINT64_C(2) << 58) | ((uint64_t)(l2_c & 0x7FFF) << 40) |
           ((uint64_t)((n - 1) & 0x1FFF) << 27) | ((uint64_t)(w_row & 0x3FF) << 14);
}

/* ---- CH2 command words (bb256_pkg.sv, ch2lin, simulation T19-T21) -----------------------
 *  ch2_in  LOAD  011 : L2 [53:39] (15b line, +1 per line), len-1 [38:25], PE [24] = 0, row [23:10]
 *  ch2_in  STORE 100 : L2 start [54:40] (15b), H [39:30], W [29:20], prec [57] = 0
 *                      beat (cg, h, w) -> c = start + w + h*W + cg*H*W (nb = 1 : cg = 0)
 *  [59:58] : LOAD 00 = burst, STORE 10 = burst.                                              */
static inline uint64_t cmd_v_load(uint32_t l2_c, uint32_t n, uint32_t v_row)
{
    return (UINT64_C(3) << 60) | ((uint64_t)(l2_c & 0x7FFF) << 39) |
           ((uint64_t)((n - 1) & 0x3FFF) << 25) | ((uint64_t)(v_row & 0x3FFF) << 10);
}
static inline uint64_t cmd_v_store(uint32_t l2_c, uint32_t hh, uint32_t ww)
{
    return (UINT64_C(4) << 60) | (UINT64_C(2) << 58) | ((uint64_t)(l2_c & 0x7FFF) << 40) |
           ((uint64_t)(hh & 0x3FF) << 30) | ((uint64_t)(ww & 0x3FF) << 20);
}

/* ---- DMA-capable DDR buffer ----------------------------------------------------- */
typedef struct {
    uint8_t *va;      /* CPU address (cached mapping)        */
    size_t   len;
    uint64_t pa;      /* physical address seen by the CDMA   */
    int      fd;
} hw_buf;

/* ---- CDMA job queue: lets the CPU issue L2/BB work while the CDMA runs ---------- */
#define CDMA_QLEN 32
typedef struct { uint64_t src, dst; size_t n; } cdma_job;

/* ---- time per operation and per kind of work (vit_main report) ------------------------
 * The caller sets the current operation (hw_op_begin / hw_op_end); the functions below add
 * their own time to it. Times are PS wall clock (CLOCK_MONOTONIC), including MMIO polling.  */
enum { PK_CMD = 0,   /* L2 LOAD / STORE commands (hw_cmd_run)                   */
       PK_GOLD,      /* Golden injection into a blackbox (BB model only)        */
       PK_BB,        /* blackbox START .. done (ch2: .. its L2 STORE done)      */
       PK_DMA,       /* CDMA wait (drain)                                       */
       PK_PS,        /* PS computation (quantization, residual)                */
       PK_N };
#define PROF_OPS 24
typedef struct {
    double        wall;           /* sum of hw_op_begin .. hw_op_end                  */
    double        t[PK_N];
    unsigned long n[PK_N];        /* commands / Golden loads / BB calls / CDMA jobs / PS steps */
    uint64_t      bb_cycles;      /* sum of CYCLES / CYCLES2 registers (PL0 clocks)    */
    uint64_t      dma_bytes;
} hw_prof;

typedef struct {
    int                fd_mem;
    volatile uint64_t *l2;        /* L2 data window (MMIO, 64-bit access)  */
    volatile uint64_t *cmd;       /* command adapter                       */
    volatile uint32_t *bb;        /* blackbox control                      */
    volatile uint32_t *cdma;      /* CDMA registers                        */
    uint64_t           pl0_hz;
    /* CDMA queue */
    cdma_job           q[CDMA_QLEN];
    int                q_head, q_tail, q_count;
    int                dma_active;
    int                dma_error;
    uint32_t           dma_last_sr;
    /* counters */
    unsigned long      n_cmd, n_bb, n_dma;
    /* profile (index 0 = work outside any operation) */
    int                op;
    double             op_t0;
    hw_prof            prof[PROF_OPS];
} hw_ctx;

/* ---- open / close ------------------------------------------------------------- */
int  hw_open(hw_ctx *h);                  /* maps registers, checks PL0, CDMA, adapter */
void hw_close(hw_ctx *h);                 /* resets a pending CDMA before unmapping    */
int  hw_stop_requested(void);             /* Ctrl-C seen                               */

/* ---- DDR buffers ---------------------------------------------------------------- */
int  hw_buf_alloc(hw_buf *b, size_t len);
void hw_buf_free(hw_buf *b);
void hw_cache_sync(const void *p, size_t n);   /* DC CIVAC over the range + DSB */

/* ---- CDMA (DDR <-> L2) ------------------------------------------------------------ */
uint64_t hw_l2_pa(uint32_t c);                        /* byte address of L2 line c     */
int  hw_cdma_submit(hw_ctx *h, uint64_t src, uint64_t dst, size_t n);
int  hw_cdma_service(hw_ctx *h);                      /* progress queue, never blocks  */
int  hw_cdma_drain(hw_ctx *h);                        /* wait until queue is empty     */
int  hw_cdma_copy(hw_ctx *h, uint64_t src, uint64_t dst, size_t n); /* submit + drain */

/* ---- L2 commands ------------------------------------------------------------------ */
int  hw_cmd_run(hw_ctx *h, uint64_t cmd);   /* push one command, wait for completion */

/* ---- CH1 blackbox ------------------------------------------------------------------ */
int  hw_bb_gold_load(hw_ctx *h, const uint8_t *lines, uint32_t n);
int  hw_bb_run(hw_ctx *h, uint32_t in_base, uint32_t in_len, uint32_t w_base, uint32_t w_len,
               uint32_t out_base, uint32_t out_len, int inject, uint32_t *cycles);

/* ---- CH2 (vector) blackbox --------------------------------------------------------- */
int  hw_bb2_gold_load(hw_ctx *h, const uint8_t *lines, uint32_t n);
/* one vector job whose output goes straight to L2 :
 *   pushes ch2_in STORE (start l2_c, H = hh, W = ww), START (input rows in_base..+in_len,
 *   shape nb 1 x hh x ww), waits for the blackbox and then for the STORE to complete.        */
int  hw_bb2_run_store(hw_ctx *h, uint32_t in_base, uint32_t in_len, uint32_t l2_c,
                      uint32_t hh, uint32_t ww, int inject, uint32_t *cycles);
/* one row of the input (sel 0) or weight (sel 1) memory through DBG2 (debug only) */
int  hw_bb2_dbg_read(hw_ctx *h, int sel, uint32_t row, uint8_t *line);

/* ---- L2 window through the PS (ch0, MMIO) ------------------------------------------ */
void hw_l2_write(hw_ctx *h, uint32_t c, const uint8_t *src, uint32_t nlines);
void hw_l2_read(hw_ctx *h, uint32_t c, uint8_t *dst, uint32_t nlines);

/* ---- misc --------------------------------------------------------------------------- */
double hw_now(void);   /* monotonic seconds */

/* ---- profile helpers ------------------------------------------------------------------ */
static inline void hw_op_begin(hw_ctx *h, int op)
{
    h->op = (op >= 0 && op < PROF_OPS) ? op : 0;
    h->op_t0 = hw_now();
}
static inline void hw_op_end(hw_ctx *h)
{
    h->prof[h->op].wall += hw_now() - h->op_t0;
    h->op = 0;
}
static inline void hw_prof_add(hw_ctx *h, int kind, double dt)
{
    h->prof[h->op].t[kind] += dt;
    h->prof[h->op].n[kind]++;
}

#endif
