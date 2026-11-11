/* hw_sim.c - x86 software model of the vit_hw.h API (replaces vit_hw.c off the board).  JH, 2026-11-10
 *
 * Purpose: run vit_main / vit_dbg / the MLP flow on a PC with the same ops code, before the board.
 * Model (what the board does, as far as the PS can tell):
 *   L2 32768 lines, L1 2048, WMEM 1024, vector input memory 2048 / weight 512, Golden 256 per bank.
 *   L2 commands are decoded from the bit table in vit_hw.h (NOT with the cmd_* encoders), every bit
 *   outside the defined fields must be 0, ranges are checked (no wrap-around).
 *   MAC BB  : L1[out_base..] = Golden[0..out_len), CYCLES = in + w + out + 9
 *   vec BB  : beats (h, w) -> L2 start + w + h*W, CYCLES2 = in + w + 3*beats + 6
 *   INJECT  : bit 0 of beat 0 flipped.  CDMA : copied at submit (in order), DDR = hw_buf_alloc buffers.
 * Not modeled: timing, CDMA/command overlap hazards, cache effects.
 *
 * Environment (optional)
 *   HWSIM_LOG=path        : one line per L2 command (index, raw 64-bit word, decoded fields)
 *   HWSIM_FAULT_CMD=N     : L2 line address of command N (0-based) + 1 (fault injection)
 *   HWSIM_FAULT_LEN=N     : length of command N - 1 (fault injection)
 */
#define _POSIX_C_SOURCE 200809L
#include "vit_hw.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include <time.h>
#ifdef _WIN32
#include <windows.h>
#endif

static uint8_t s_l2[L2_LINES][LINE_BYTES], s_l1[L1_LINES][LINE_BYTES], s_wmem[WMEM_LINES][LINE_BYTES];
static uint8_t s_vin[VIN_LINES][LINE_BYTES], s_vw[VW_LINES][LINE_BYTES];
static uint8_t s_gold[2][GOLD_LINES][LINE_BYTES];
static uint32_t s_gold_n[2];

/* DDR buffers : fake physical addresses, page aligned, below DDR_LOW_END */
#define SIM_BUFS 64
static struct { uint64_t pa; uint8_t *va; size_t len; } s_buf[SIM_BUFS];
static uint64_t s_next_pa = UINT64_C(0x40000000);

static FILE *s_log;
static long s_fault_cmd = -1, s_fault_len = -1;
static unsigned long s_cmd_index;
unsigned long hwsim_count[8];             /* commands per op code (see hwsim_print_counts) */

double hw_now(void)
{
#ifdef _WIN32
    static LARGE_INTEGER f;
    LARGE_INTEGER c;
    if (!f.QuadPart) QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&c);
    return (double)c.QuadPart / (double)f.QuadPart;
#else
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec + (double)t.tv_nsec * 1e-9;
#endif
}

int  hw_stop_requested(void) { return 0; }
void hw_cache_sync(const void *p, size_t n) { (void)p; (void)n; }

/* ---- open / close ------------------------------------------------------------------------------ */
static long env_long(const char *name)
{
    const char *s = getenv(name);
    return s && *s ? strtol(s, NULL, 0) : -1;
}

int hw_open(hw_ctx *h)
{
    memset(h, 0, sizeof *h);
    h->fd_mem = -1;
    h->pl0_hz = PL0_EXPECT_HZ;
    /* non-NULL so that callers' "mapped?" tests behave as on the board; never dereferenced */
    h->l2 = (volatile uint64_t *)(void *)s_l2;
    h->cmd = (volatile uint64_t *)(void *)s_l1;
    h->bb = (volatile uint32_t *)(void *)s_wmem;
    h->cdma = (volatile uint32_t *)(void *)s_vin;
    /* power-up contents are unknown on the board: fill with a pattern, not zeros */
    for (uint32_t c = 0; c < L2_LINES; c++) memset(s_l2[c], 0xC3 ^ (int)(c & 0xFF), LINE_BYTES);
    memset(s_l1, 0x3C, sizeof s_l1); memset(s_wmem, 0x5C, sizeof s_wmem);
    memset(s_vin, 0x6C, sizeof s_vin); memset(s_vw, 0x7C, sizeof s_vw);
    s_gold_n[0] = s_gold_n[1] = 0;
    const char *lp = getenv("HWSIM_LOG");
    if (lp && *lp && !(s_log = fopen(lp, "w"))) { perror(lp); return -1; }
    s_fault_cmd = env_long("HWSIM_FAULT_CMD");
    s_fault_len = env_long("HWSIM_FAULT_LEN");
    s_cmd_index = 0;
    memset(hwsim_count, 0, sizeof hwsim_count);
    fprintf(stderr, "[hw_sim] x86 software model of the PL (no board)%s\n", s_log ? ", command log on" : "");
    if (s_fault_cmd >= 0) fprintf(stderr, "[hw_sim] FAULT: L2 address + 1 on command %ld\n", s_fault_cmd);
    if (s_fault_len >= 0) fprintf(stderr, "[hw_sim] FAULT: length - 1 on command %ld\n", s_fault_len);
    return 0;
}

void hw_close(hw_ctx *h)
{
    if (s_log) { fclose(s_log); s_log = NULL; }
    h->l2 = NULL; h->cmd = NULL; h->bb = NULL; h->cdma = NULL;
}

/* ---- DDR buffers --------------------------------------------------------------------------------- */
int hw_buf_alloc(hw_buf *b, size_t len)
{
    memset(b, 0, sizeof *b);
    b->fd = -1;
    len = (len + 4095) / 4096 * 4096;
    for (int i = 0; i < SIM_BUFS; i++)
        if (!s_buf[i].va) {
            uint8_t *va = calloc(1, len);
            if (!va) return -1;
            s_buf[i].pa = s_next_pa; s_buf[i].va = va; s_buf[i].len = len;
            s_next_pa += len + 4096;
            b->va = va; b->len = len; b->pa = s_buf[i].pa;
            return 0;
        }
    fprintf(stderr, "[hw_sim] too many DMA buffers\n");
    return -1;
}

void hw_buf_free(hw_buf *b)
{
    for (int i = 0; i < SIM_BUFS; i++)
        if (b->va && s_buf[i].va == b->va) { free(s_buf[i].va); memset(&s_buf[i], 0, sizeof s_buf[i]); }
    b->va = NULL; b->fd = -1; b->len = 0; b->pa = 0;
}

static uint8_t *ddr_ptr(uint64_t pa, size_t n)
{
    for (int i = 0; i < SIM_BUFS; i++)
        if (s_buf[i].va && pa >= s_buf[i].pa && n <= s_buf[i].len && pa - s_buf[i].pa <= s_buf[i].len - n)
            return s_buf[i].va + (pa - s_buf[i].pa);
    return NULL;
}

/* ---- CDMA ------------------------------------------------------------------------------------------ */
uint64_t hw_l2_pa(uint32_t c) { return L2_DATA_BASE + (uint64_t)c * LINE_BYTES; }

static int in_l2(uint64_t a, size_t n)
{
    return a >= L2_DATA_BASE && n <= L2_DATA_SIZE && a - L2_DATA_BASE <= L2_DATA_SIZE - n;
}

int hw_cdma_submit(hw_ctx *h, uint64_t src, uint64_t dst, size_t n)
{
    uint8_t *d = NULL;
    const uint8_t *s = NULL;
    if (n && n <= L2_DATA_SIZE && !((src | dst | n) & 7)) {
        if (in_l2(src, n)) { s = &s_l2[0][0] + (src - L2_DATA_BASE); d = ddr_ptr(dst, n); }
        else if (in_l2(dst, n)) { d = &s_l2[0][0] + (dst - L2_DATA_BASE); s = ddr_ptr(src, n); }
    }
    if (!s || !d) {
        fprintf(stderr, "CDMA job rejected: src 0x%" PRIx64 " dst 0x%" PRIx64 " n %zu\n", src, dst, n);
        return -1;
    }
    memmove(d, s, n);
    h->prof[h->op].n[PK_DMA]++;
    h->prof[h->op].dma_bytes += n;
    h->n_dma++;
    return 0;
}

int hw_cdma_service(hw_ctx *h) { (void)h; return 0; }
int hw_cdma_drain(hw_ctx *h)   { (void)h; return 0; }
int hw_cdma_copy(hw_ctx *h, uint64_t src, uint64_t dst, size_t n) { return hw_cdma_submit(h, src, dst, n); }

/* ---- L2 commands (decoded from the vit_hw.h bit table) ----------------------------------------------- */
static uint64_t field(uint64_t v, int hi, int lo) { return (v >> lo) & ((UINT64_C(1) << (hi - lo + 1)) - 1); }
static uint64_t fmask(int hi, int lo) { return ((UINT64_C(1) << (hi - lo + 1)) - 1) << lo; }

typedef struct { int op; uint32_t l2, n, row, hh, ww; } dcmd;

static int decode(uint64_t c, dcmd *d)
{
    uint64_t used = fmask(62, 60) | fmask(59, 58);
    int mode = (int)field(c, 59, 58);
    memset(d, 0, sizeof *d);
    d->op = (int)field(c, 62, 60);
    switch (d->op) {
    case 1:   /* ch1_in LOAD : L2 [54:40], len-1 [39:29], L1 [28:18], multicast [14:7] = 1, burst 00 */
        d->l2 = (uint32_t)field(c, 54, 40); d->n = (uint32_t)field(c, 39, 29) + 1; d->row = (uint32_t)field(c, 28, 18);
        used |= fmask(54, 18) | fmask(14, 7);
        if (mode != 0 || field(c, 14, 7) != 1) return -1;
        break;
    case 2:   /* ch1_in STORE : L2 [55:41], len-1 [40:27], cluster [26:24] = 0, L1 [23:13], burst 10 */
        d->l2 = (uint32_t)field(c, 55, 41); d->n = (uint32_t)field(c, 40, 27) + 1; d->row = (uint32_t)field(c, 23, 13);
        used |= fmask(55, 13);
        if (mode != 2 || field(c, 26, 24) != 0) return -1;
        break;
    case 5:   /* ch1_wgt LOAD : L2 [53:39], len-1 [38:29], WMEM [28:19], multicast [14:7] = 1 */
        d->l2 = (uint32_t)field(c, 53, 39); d->n = (uint32_t)field(c, 38, 29) + 1; d->row = (uint32_t)field(c, 28, 19);
        used |= fmask(53, 19) | fmask(14, 7);
        if (mode != 0 || field(c, 14, 7) != 1) return -1;
        break;
    case 6:   /* ch1_wgt STORE : L2 [54:40], len-1 [39:27], cluster [26:24] = 0, WMEM [23:14] */
        d->l2 = (uint32_t)field(c, 54, 40); d->n = (uint32_t)field(c, 39, 27) + 1; d->row = (uint32_t)field(c, 23, 14);
        used |= fmask(54, 14);
        if (mode != 2 || field(c, 26, 24) != 0) return -1;
        break;
    case 3:   /* ch2_in LOAD : L2 [53:39], len-1 [38:25], PE [24] = 0, row [23:10] */
        d->l2 = (uint32_t)field(c, 53, 39); d->n = (uint32_t)field(c, 38, 25) + 1; d->row = (uint32_t)field(c, 23, 10);
        used |= fmask(53, 10);
        if (mode != 0 || field(c, 24, 24) != 0) return -1;
        break;
    case 4:   /* ch2_in STORE : L2 [54:40], H [39:30], W [29:20], prec [57] = 0 */
        d->l2 = (uint32_t)field(c, 54, 40); d->hh = (uint32_t)field(c, 39, 30); d->ww = (uint32_t)field(c, 29, 20);
        d->n = d->hh * d->ww;
        used |= fmask(57, 57) | fmask(54, 20);
        if (mode != 2 || field(c, 57, 57) != 0) return -1;
        break;
    default:
        return -1;
    }
    return (c & ~used) ? -1 : 0;
}

static const char *const OPN[8] = { "?", "ch1_in LOAD", "ch1_in STORE", "ch2_in LOAD",
                                    "ch2_in STORE", "ch1_wgt LOAD", "ch1_wgt STORE", "?" };

static int log_and_fault(uint64_t cmd, dcmd *d)
{
    unsigned long idx = s_cmd_index++;
    if (decode(cmd, d)) {
        fprintf(stderr, "L2 command 0x%016" PRIx64 " rejected (hw_sim decode: bad op/mode/fixed field/stray bits)\n", cmd);
        return -1;
    }
    hwsim_count[d->op]++;
    if (s_log) {
        if (d->op == 4)
            fprintf(s_log, "%6lu 0x%016" PRIx64 " %-13s L2 0x%04X H %u W %u (%u beats)\n", idx, cmd, OPN[d->op],
                    d->l2, d->hh, d->ww, d->n);
        else
            fprintf(s_log, "%6lu 0x%016" PRIx64 " %-13s L2 0x%04X n %4u %s %u\n", idx, cmd, OPN[d->op], d->l2, d->n,
                    d->op == 5 || d->op == 6 ? "WMEM" : d->op == 3 ? "v_row" : "L1", d->row);
    }
    if ((long)idx == s_fault_cmd) d->l2 = (d->l2 + 1) & 0x7FFF;
    if ((long)idx == s_fault_len && d->op != 4 && d->n > 1) d->n--;
    return 0;
}

static int exec_cmd(const dcmd *d)
{
    uint32_t mem_lines = d->op == 1 || d->op == 2 ? L1_LINES : d->op == 3 ? VIN_LINES : WMEM_LINES;
    if (d->l2 + d->n > L2_LINES || d->row + d->n > mem_lines) {
        fprintf(stderr, "[hw_sim] %s out of range: L2 0x%04X n %u row %u\n", OPN[d->op], d->l2, d->n, d->row);
        return -1;
    }
    for (uint32_t i = 0; i < d->n; i++)
        switch (d->op) {
        case 1: memcpy(s_l1[d->row + i], s_l2[d->l2 + i], LINE_BYTES); break;
        case 2: memcpy(s_l2[d->l2 + i], s_l1[d->row + i], LINE_BYTES); break;
        case 3: memcpy(s_vin[d->row + i], s_l2[d->l2 + i], LINE_BYTES); break;
        case 5: memcpy(s_wmem[d->row + i], s_l2[d->l2 + i], LINE_BYTES); break;
        case 6: memcpy(s_l2[d->l2 + i], s_wmem[d->row + i], LINE_BYTES); break;
        default: return -1;
        }
    return 0;
}

int hw_cmd_run(hw_ctx *h, uint64_t cmd)
{
    double t0 = hw_now();
    dcmd d;
    if (log_and_fault(cmd, &d)) return -1;
    if (d.op == 4) {   /* a ch2_in STORE alone would wait for beats that never come */
        fprintf(stderr, "L2 command 0x%016" PRIx64 " (ch2_in STORE) outside hw_bb2_run_store: timeout\n", cmd);
        return -1;
    }
    if (exec_cmd(&d)) return -1;
    h->n_cmd++;
    hw_prof_add(h, PK_CMD, hw_now() - t0);
    return 0;
}

/* ---- blackboxes ------------------------------------------------------------------------------------------ */
static int gold_load(hw_ctx *h, int bank, const uint8_t *lines, uint32_t n)
{
    double t0 = hw_now();
    if (n == 0 || n > GOLD_LINES) { fprintf(stderr, "Golden length %u out of range\n", n); return -1; }
    memcpy(s_gold[bank], lines, (size_t)n * LINE_BYTES);
    s_gold_n[bank] = n;
    hw_prof_add(h, PK_GOLD, hw_now() - t0);
    return 0;
}

int hw_bb_gold_load(hw_ctx *h, const uint8_t *lines, uint32_t n)  { return gold_load(h, 0, lines, n); }
int hw_bb2_gold_load(hw_ctx *h, const uint8_t *lines, uint32_t n) { return gold_load(h, 1, lines, n); }

int hw_bb_run(hw_ctx *h, uint32_t in_base, uint32_t in_len, uint32_t w_base, uint32_t w_len,
              uint32_t out_base, uint32_t out_len, int inject, uint32_t *cycles)
{
    if (in_len > L1_LINES || in_base + in_len > L1_LINES || out_len > GOLD_LINES ||
        out_base + out_len > L1_LINES || w_len > WMEM_LINES || w_base + w_len > WMEM_LINES) {
        fprintf(stderr, "blackbox range error in %u+%u w %u+%u out %u+%u\n",
                in_base, in_len, w_base, w_len, out_base, out_len);
        return -1;
    }
    if (out_len > s_gold_n[0]) {
        fprintf(stderr, "[hw_sim] blackbox out_len %u > Golden lines loaded %u\n", out_len, s_gold_n[0]);
        return -1;
    }
    double t0 = hw_now();
    memcpy(s_l1[out_base], s_gold[0], (size_t)out_len * LINE_BYTES);
    if (inject && out_len) s_l1[out_base][0] ^= 1u;
    uint32_t cyc = in_len + w_len + out_len + BB_CYCLE_OVERHEAD;
    if (cycles) *cycles = cyc;
    h->n_bb++;
    hw_prof_add(h, PK_BB, hw_now() - t0);
    h->prof[h->op].bb_cycles += cyc;
    return 0;
}

int hw_bb2_run_store(hw_ctx *h, uint32_t in_base, uint32_t in_len, uint32_t l2_c,
                     uint32_t hh, uint32_t ww, int inject, uint32_t *cycles)
{
    uint32_t n = hh * ww;
    if (in_len > VIN_LINES || in_base + in_len > VIN_LINES || hh == 0 || ww == 0 ||
        hh > 1023 || ww > 1023 || n > GOLD_LINES || l2_c >= L2_LINES) {
        fprintf(stderr, "vector blackbox range error in %u+%u shape 1x%ux%u L2 0x%04x\n", in_base, in_len, hh, ww, l2_c);
        return -1;
    }
    if (n > s_gold_n[1]) {
        fprintf(stderr, "[hw_sim] vector blackbox %u beats > Golden lines loaded %u\n", n, s_gold_n[1]);
        return -1;
    }
    double t0 = hw_now();
    dcmd d;
    if (log_and_fault(cmd_v_store(l2_c, hh, ww), &d)) return -1;
    if (d.op != 4 || d.hh == 0 || d.ww == 0) return -1;
    for (uint32_t r = 0; r < d.hh; r++)
        for (uint32_t w = 0; w < d.ww; w++) {
            uint32_t beat = r * d.ww + w, c = d.l2 + w + r * d.ww;
            if (c >= L2_LINES) { fprintf(stderr, "[hw_sim] ch2_in STORE beat past L2 end\n"); return -1; }
            memcpy(s_l2[c], s_gold[1][beat], LINE_BYTES);
            if (inject && beat == 0) s_l2[c][0] ^= 1u;
        }
    uint32_t cyc = in_len + 0 + 3 * n + BB2_CYCLE_OVERHEAD;
    if (cycles) *cycles = cyc;
    h->n_bb++;
    h->n_cmd++;
    hw_prof_add(h, PK_BB, hw_now() - t0);
    h->prof[h->op].bb_cycles += cyc;
    return 0;
}

int hw_bb2_dbg_read(hw_ctx *h, int sel, uint32_t row, uint8_t *line)
{
    (void)h;
    if (row >= (sel ? VW_LINES : VIN_LINES)) { fprintf(stderr, "DBG2 row %u out of range\n", row); return -1; }
    memcpy(line, sel ? s_vw[row] : s_vin[row], LINE_BYTES);
    return 0;
}

/* ---- L2 through the PS ------------------------------------------------------------------------------------- */
void hw_l2_write(hw_ctx *h, uint32_t c, const uint8_t *src, uint32_t nlines)
{
    (void)h;
    if (c + nlines > L2_LINES) { fprintf(stderr, "[hw_sim] hw_l2_write past L2 end\n"); abort(); }
    memcpy(s_l2[c], src, (size_t)nlines * LINE_BYTES);
}

void hw_l2_read(hw_ctx *h, uint32_t c, uint8_t *dst, uint32_t nlines)
{
    (void)h;
    if (c + nlines > L2_LINES) { fprintf(stderr, "[hw_sim] hw_l2_read past L2 end\n"); abort(); }
    memcpy(dst, s_l2[c], (size_t)nlines * LINE_BYTES);
}
