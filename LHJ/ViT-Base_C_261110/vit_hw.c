/* vit_hw.c - hardware access layer for the ZCU102 L2/NoC/L1/blackbox PL.
 *
 * Board method carried over from l2_cdma_test3.c (board-tested 2026-10-14):
 *   - DMA buffers from /dev/dma_heap/reserved, physical address from /proc/self/pagemap
 *   - EL0 DC CIVAC cache maintenance, no CPU access to a buffer while the CDMA owns it
 *   - /dev/mem with O_SYNC -> Device-nGnRnE mapping: a register write followed by DSB has
 *     reached the PL slave before the next access (no early write acknowledgement)
 * Assumes exclusive use of the CDMA, L2 and blackbox by this process.
 */
#define _POSIX_C_SOURCE 200809L
#include "vit_hw.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>
#include <signal.h>
#include <inttypes.h>
#include <sys/mman.h>
#include <sys/ioctl.h>

#if !defined(__aarch64__)
#error "vit_hw.c targets the ZCU102 PS (aarch64) only"
#endif

/* CDMASR bits */
#define SR_IDLE   (1u << 1)
#define SR_IOC    (1u << 12)
#define SR_ERR    ((7u << 4) | (7u << 8) | (1u << 14))
#define SR_IRQ    (7u << 12)
#define CR_RESET  (1u << 2)

#define CMD_TIMEOUT_S   1.0
#define BB_TIMEOUT_S    1.0
#define DMA_TIMEOUT_S   2.0

static volatile sig_atomic_t g_stop;
static void stop_handler(int sig) { (void)sig; g_stop = 1; }
int hw_stop_requested(void) { return g_stop != 0; }

double hw_now(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec + (double)t.tv_nsec * 1e-9;
}

static inline void dsb(void) { __asm__ volatile("dsb sy" ::: "memory"); }

/* ---- register access ---------------------------------------------------------- */
static inline uint64_t cmd_rd(hw_ctx *h, unsigned off) { uint64_t v = h->cmd[off / 8]; dsb(); return v; }
static inline void     cmd_wr(hw_ctx *h, unsigned off, uint64_t v) { h->cmd[off / 8] = v; dsb(); }
static inline uint32_t bb_rd(hw_ctx *h, unsigned off) { uint32_t v = h->bb[off / 4]; dsb(); return v; }
static inline void     bb_wr(hw_ctx *h, unsigned off, uint32_t v) { h->bb[off / 4] = v; dsb(); }
static inline uint32_t dma_rd(hw_ctx *h, unsigned off) { uint32_t v = h->cdma[off / 4]; dsb(); return v; }
static inline void     dma_wr(hw_ctx *h, unsigned off, uint32_t v) { h->cdma[off / 4] = v; dsb(); }

/* ---- cache maintenance (from l2_cdma_test3.c) ------------------------------------ */
void hw_cache_sync(const void *p, size_t n)
{
    uint64_t ctr;
    __asm__ volatile("mrs %0, ctr_el0" : "=r"(ctr));
    size_t line = (size_t)4 << ((ctr >> 16) & 15);
    uintptr_t end = (uintptr_t)p + n;
    for (uintptr_t a = (uintptr_t)p & ~(uintptr_t)(line - 1); a < end; a += line)
        __asm__ volatile("dc civac, %0" :: "r"(a) : "memory");
    dsb();
}

/* ---- DMA buffers (from l2_cdma_test3.c) -------------------------------------------- */
struct heap_alloc { uint64_t len; uint32_t fd, fd_flags; uint64_t heap_flags; };
#define HEAP_ALLOC _IOWR('H', 0, struct heap_alloc)

int hw_buf_alloc(hw_buf *b, size_t len)
{
    long pg = sysconf(_SC_PAGESIZE);
    size_t page = (size_t)pg;
    memset(b, 0, sizeof *b);
    b->fd = -1;
    len = (len + page - 1) / page * page;

    int hfd = open("/dev/dma_heap/reserved", O_RDWR | O_CLOEXEC);
    if (hfd < 0) { perror("open /dev/dma_heap/reserved"); return -1; }
    struct heap_alloc q = { .len = len, .fd_flags = O_RDWR | O_CLOEXEC };
    int rc = ioctl(hfd, HEAP_ALLOC, &q);
    close(hfd);
    if (rc < 0) { fprintf(stderr, "dma_heap allocate %zu B: %s\n", len, strerror(errno)); return -1; }
    b->fd = (int)q.fd;
    b->len = len;
    void *va = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_SHARED, b->fd, 0);
    if (va == MAP_FAILED) { perror("mmap dma buffer"); close(b->fd); b->fd = -1; return -1; }
    b->va = va;
    memset(b->va, 0, len);

    int pm = open("/proc/self/pagemap", O_RDONLY | O_CLOEXEC);
    if (pm < 0) { perror("open pagemap"); hw_buf_free(b); return -1; }
    uint64_t first = 0;
    for (size_t i = 0; i < len / page; i++) {
        uint64_t e = 0;
        off_t off = (off_t)(((uintptr_t)b->va / page + i) * 8);
        if (pread(pm, &e, 8, off) != 8 || !(e & (UINT64_C(1) << 63)) || (e & (UINT64_C(1) << 62))) {
            fprintf(stderr, "pagemap unavailable at page %zu\n", i);
            close(pm); hw_buf_free(b); return -1;
        }
        uint64_t pfn = e & ((UINT64_C(1) << 55) - 1);
        if (!pfn || (i && pfn != first + i)) {
            fprintf(stderr, "dma buffer: PFN hidden or non-contiguous at page %zu\n", i);
            close(pm); hw_buf_free(b); return -1;
        }
        if (!i) first = pfn;
    }
    close(pm);
    b->pa = first * page;
    if (b->pa >= DDR_LOW_END || len > DDR_LOW_END - b->pa) {
        fprintf(stderr, "dma buffer outside DDR LOW (pa 0x%" PRIx64 ")\n", b->pa);
        hw_buf_free(b); return -1;
    }
    hw_cache_sync(b->va, b->len);
    return 0;
}

void hw_buf_free(hw_buf *b)
{
    if (b->va) munmap(b->va, b->len);
    if (b->fd >= 0) close(b->fd);
    b->va = NULL; b->fd = -1; b->len = 0; b->pa = 0;
}

/* ---- PL0 clock as reported by Linux ------------------------------------------------- */
static uint64_t read_pl0_hz(void)
{
    FILE *f = fopen("/sys/kernel/debug/clk/clk_summary", "r");
    if (!f) return 0;
    char line[2048], name[128];
    unsigned a, b, c;
    unsigned long long hz;
    while (fgets(line, sizeof line, f))
        if (sscanf(line, " %127s %u %u %u %llu", name, &a, &b, &c, &hz) == 5 && !strcmp(name, "pl0_ref")) {
            fclose(f);
            return hz;
        }
    fclose(f);
    return 0;
}

/* ---- CDMA ------------------------------------------------------------------------------- */
static int cdma_reset(hw_ctx *h)
{
    dma_wr(h, CDMACR, CR_RESET);
    double t = hw_now();
    while (dma_rd(h, CDMACR) & CR_RESET)
        if (hw_now() - t > 0.2) return -1;
    uint32_t s = dma_rd(h, CDMASR);
    if (!(s & SR_IDLE) || (s & SR_ERR)) return -1;
    h->dma_active = 0;
    return 0;
}

uint64_t hw_l2_pa(uint32_t c) { return L2_DATA_BASE + (uint64_t)c * LINE_BYTES; }

static int in_l2(uint64_t a, size_t n)
{
    return a >= L2_DATA_BASE && n <= L2_DATA_SIZE && a - L2_DATA_BASE <= L2_DATA_SIZE - n;
}
static int in_ddr(uint64_t a, size_t n) { return a < DDR_LOW_END && n <= DDR_LOW_END - a; }

static double g_job_t0;

static int cdma_start(hw_ctx *h, const cdma_job *j)
{
    uint32_t s = dma_rd(h, CDMASR);
    h->dma_last_sr = s;
    if (!(s & SR_IDLE) || (s & SR_ERR)) {
        fprintf(stderr, "CDMA not idle before start, SR=0x%08x\n", s);
        return -1;
    }
    dma_wr(h, CDMASR, SR_IRQ);                 /* W1C: discard previous completion */
    if (dma_rd(h, CDMASR) & SR_IOC) { fprintf(stderr, "CDMA IOC did not clear\n"); return -1; }
    dma_wr(h, CDMA_SA, (uint32_t)j->src);
    dma_wr(h, CDMA_SA_MSB, (uint32_t)(j->src >> 32));
    dma_wr(h, CDMA_DA, (uint32_t)j->dst);
    dma_wr(h, CDMA_DA_MSB, (uint32_t)(j->dst >> 32));
    h->dma_active = 1;
    g_job_t0 = hw_now();
    dma_wr(h, CDMA_BTT, (uint32_t)j->n);       /* starts the transfer */
    return 0;
}

int hw_cdma_submit(hw_ctx *h, uint64_t src, uint64_t dst, size_t n)
{
    if (h->dma_error) return -1;
    if (!n || n > L2_DATA_SIZE || ((src | dst | n) & 7) ||
        !((in_l2(src, n) && in_ddr(dst, n)) || (in_ddr(src, n) && in_l2(dst, n)))) {
        fprintf(stderr, "CDMA job rejected: src 0x%" PRIx64 " dst 0x%" PRIx64 " n %zu\n", src, dst, n);
        return -1;
    }
    if (h->q_count == CDMA_QLEN) { fprintf(stderr, "CDMA queue full\n"); return -1; }
    h->q[h->q_tail] = (cdma_job){ src, dst, n };
    h->q_tail = (h->q_tail + 1) % CDMA_QLEN;
    h->q_count++;
    h->prof[h->op].n[PK_DMA]++;
    h->prof[h->op].dma_bytes += n;
    return hw_cdma_service(h);
}

int hw_cdma_service(hw_ctx *h)
{
    if (h->dma_error) return -1;
    if (h->dma_active) {
        uint32_t s = dma_rd(h, CDMASR);
        h->dma_last_sr = s;
        if (s & SR_ERR) {
            fprintf(stderr, "CDMA error SR=0x%08x\n", s);
            h->dma_error = 1;
            return -1;
        }
        if ((s & (SR_IDLE | SR_IOC)) == (SR_IDLE | SR_IOC)) {
            h->dma_active = 0;
            h->n_dma++;
        } else if (hw_now() - g_job_t0 > DMA_TIMEOUT_S) {
            fprintf(stderr, "CDMA timeout SR=0x%08x\n", s);
            h->dma_error = 1;
            return -1;
        }
    }
    if (!h->dma_active && h->q_count) {
        cdma_job j = h->q[h->q_head];
        h->q_head = (h->q_head + 1) % CDMA_QLEN;
        h->q_count--;
        if (cdma_start(h, &j)) { h->dma_error = 1; return -1; }
    }
    return 0;
}

int hw_cdma_drain(hw_ctx *h)
{
    double t0 = hw_now();
    while (h->dma_active || h->q_count)
        if (hw_cdma_service(h)) return -1;
    h->prof[h->op].t[PK_DMA] += hw_now() - t0;
    return 0;
}

int hw_cdma_copy(hw_ctx *h, uint64_t src, uint64_t dst, size_t n)
{
    if (hw_cdma_submit(h, src, dst, n)) return -1;
    return hw_cdma_drain(h);
}

/* ---- L2 commands ------------------------------------------------------------------------ */
int hw_cmd_run(hw_ctx *h, uint64_t cmd)
{
    double t0 = hw_now();
    uint32_t d0 = (uint32_t)cmd_rd(h, CMD_DONE);
    cmd_wr(h, CMD_PUSH, cmd);
    uint64_t e = cmd_rd(h, CMD_ERRORS);
    if (e & 0x1F) {
        fprintf(stderr, "L2 command 0x%016" PRIx64 " rejected, ERRORS=0x%" PRIx64 "\n", cmd, e);
        return -1;
    }
    double t = hw_now();
    while ((uint32_t)cmd_rd(h, CMD_DONE) == d0) {
        if (hw_cdma_service(h)) return -1;
        if (hw_now() - t > CMD_TIMEOUT_S) {
            fprintf(stderr, "L2 command 0x%016" PRIx64 " timeout: BUSY=0x%" PRIx64 " EXEC=0x%" PRIx64
                    " STATUS=0x%" PRIx64 "\n", cmd, cmd_rd(h, CMD_BUSY), cmd_rd(h, CMD_EXEC), cmd_rd(h, CMD_STATUS));
            return -1;
        }
    }
    h->n_cmd++;
    hw_prof_add(h, PK_CMD, hw_now() - t0);
    return 0;
}

/* ---- blackbox ------------------------------------------------------------------------------ */
/* Golden BRAM of either blackbox: the 256b window (0x80..0x9C) is shared, commit per bank.
 * The window may only be written while neither blackbox runs (axi_lite_bb_ctrl.sv). */
static int gold_load(hw_ctx *h, unsigned r_gaddr, unsigned r_gcommit, const uint8_t *lines, uint32_t n)
{
    double t0 = hw_now();
    if (n == 0 || n > GOLD_LINES) { fprintf(stderr, "Golden length %u out of range\n", n); return -1; }
    if ((bb_rd(h, BB_STATUS) & 1u) || (bb_rd(h, BB2_STATUS) & 1u)) {
        fprintf(stderr, "Golden load while a blackbox is busy\n");
        return -1;
    }
    bb_wr(h, r_gaddr, 0);
    for (uint32_t k = 0; k < n; k++) {
        const uint8_t *p = lines + (size_t)k * LINE_BYTES;
        for (unsigned w = 0; w < 8; w++) {
            uint32_t v;
            memcpy(&v, p + 4 * w, 4);          /* word w = bits [32w+31:32w], little-endian */
            bb_wr(h, BB_WIN + 4 * w, v);
        }
        bb_wr(h, r_gcommit, 1);
    }
    uint32_t ga = bb_rd(h, r_gaddr) & 0xFF;
    if (ga != (n & 0xFF)) { fprintf(stderr, "GOLD_ADDR 0x%x = %u after %u commits\n", r_gaddr, ga, n); return -1; }
    hw_prof_add(h, PK_GOLD, hw_now() - t0);
    return 0;
}

int hw_bb_gold_load(hw_ctx *h, const uint8_t *lines, uint32_t n)
{
    return gold_load(h, BB_GADDR, BB_GCOMMIT, lines, n);
}

int hw_bb2_gold_load(hw_ctx *h, const uint8_t *lines, uint32_t n)
{
    return gold_load(h, BB2_GADDR, BB2_GCOMMIT, lines, n);
}

int hw_bb_run(hw_ctx *h, uint32_t in_base, uint32_t in_len, uint32_t w_base, uint32_t w_len,
              uint32_t out_base, uint32_t out_len, int inject, uint32_t *cycles)
{
    /* the register block answers SLVERR for an out-of-range START: check here first */
    if (in_len > L1_LINES || in_base + in_len > L1_LINES || out_len > GOLD_LINES ||
        out_base + out_len > L1_LINES || w_len > WMEM_LINES || w_base + w_len > WMEM_LINES) {
        fprintf(stderr, "blackbox range error in %u+%u w %u+%u out %u+%u\n",
                in_base, in_len, w_base, w_len, out_base, out_len);
        return -1;
    }
    double t0 = hw_now();
    uint32_t s = bb_rd(h, BB_STATUS);
    if (s & 0x9u) { fprintf(stderr, "blackbox not ready, STATUS=0x%x\n", s); return -1; }
    bb_wr(h, BB_IN,  (in_len << 16) | in_base);
    bb_wr(h, BB_WGT, (w_len << 16) | w_base);
    bb_wr(h, BB_OUT, (out_len << 16) | out_base);
    bb_wr(h, BB_LAT, 0);
    bb_wr(h, BB_CTRL, (inject ? 2u : 0u) | 1u);
    double t = hw_now();
    for (;;) {
        s = bb_rd(h, BB_STATUS);
        if ((s & 2u) && !(s & 1u)) break;
        if (hw_cdma_service(h)) return -1;
        if (hw_now() - t > BB_TIMEOUT_S) { fprintf(stderr, "blackbox timeout STATUS=0x%x\n", s); return -1; }
    }
    if (s & 8u) { fprintf(stderr, "blackbox START refused (err_start_busy), STATUS=0x%x\n", s); return -1; }
    if (inject) bb_wr(h, BB_CTRL, 0);          /* clear INJECT, no START */
    uint32_t cyc = bb_rd(h, BB_CYCLES);
    if (cycles) *cycles = cyc;
    h->n_bb++;
    hw_prof_add(h, PK_BB, hw_now() - t0);
    h->prof[h->op].bb_cycles += cyc;
    return 0;
}

/* ---- vector blackbox (CH2) ---------------------------------------------------------------- */
int hw_bb2_run_store(hw_ctx *h, uint32_t in_base, uint32_t in_len, uint32_t l2_c,
                     uint32_t hh, uint32_t ww, int inject, uint32_t *cycles)
{
    uint32_t n = hh * ww;
    if (in_len > VIN_LINES || in_base + in_len > VIN_LINES || hh == 0 || ww == 0 ||
        hh > 1023 || ww > 1023 || n > GOLD_LINES || l2_c >= L2_LINES) {
        fprintf(stderr, "vector blackbox range error in %u+%u shape 1x%ux%u L2 0x%04x\n", in_base, in_len, hh, ww, l2_c);
        return -1;
    }
    double t0 = hw_now();
    uint32_t s = bb_rd(h, BB2_STATUS);
    if (s & 0x9u) { fprintf(stderr, "vector blackbox not ready, STATUS2=0x%x\n", s); return -1; }
    bb_wr(h, BB2_IN,    (in_len << 16) | in_base);
    bb_wr(h, BB2_WGT,   0);
    bb_wr(h, BB2_SHAPE, (1u << 24) | (hh << 10) | ww);
    bb_wr(h, BB2_LAT,   0);

    /* the STORE goes first (T21 order); it completes when the blackbox has sent all beats */
    uint64_t cmd = cmd_v_store(l2_c, hh, ww);
    uint32_t d0 = (uint32_t)cmd_rd(h, CMD_DONE);
    cmd_wr(h, CMD_PUSH, cmd);
    uint64_t e = cmd_rd(h, CMD_ERRORS);
    if (e & 0x1F) {
        fprintf(stderr, "L2 command 0x%016" PRIx64 " rejected, ERRORS=0x%" PRIx64 "\n", cmd, e);
        return -1;
    }
    bb_wr(h, BB2_CTRL, (inject ? 2u : 0u) | 1u);   /* HS 0 (burst), PREC 0 */
    double t = hw_now();
    for (;;) {
        s = bb_rd(h, BB2_STATUS);
        if ((s & 2u) && !(s & 1u)) break;
        if (hw_cdma_service(h)) return -1;
        if (hw_now() - t > BB_TIMEOUT_S) {
            fprintf(stderr, "vector blackbox timeout STATUS2=0x%x BUSY=0x%" PRIx64 "\n", s, cmd_rd(h, CMD_BUSY));
            return -1;
        }
    }
    if (s & 8u) { fprintf(stderr, "vector blackbox START refused (err_start_busy), STATUS2=0x%x\n", s); return -1; }
    t = hw_now();
    while ((uint32_t)cmd_rd(h, CMD_DONE) == d0) {
        if (hw_cdma_service(h)) return -1;
        if (hw_now() - t > CMD_TIMEOUT_S) {
            fprintf(stderr, "ch2_in STORE 0x%016" PRIx64 " timeout: BUSY=0x%" PRIx64 " EXEC=0x%" PRIx64 "\n",
                    cmd, cmd_rd(h, CMD_BUSY), cmd_rd(h, CMD_EXEC));
            return -1;
        }
    }
    if (inject) bb_wr(h, BB2_CTRL, 0);         /* clear INJECT, no START */
    uint32_t cyc = bb_rd(h, BB2_CYCLES);
    if (cycles) *cycles = cyc;
    h->n_bb++;
    h->n_cmd++;
    hw_prof_add(h, PK_BB, hw_now() - t0);
    h->prof[h->op].bb_cycles += cyc;
    return 0;
}

int hw_bb2_dbg_read(hw_ctx *h, int sel, uint32_t row, uint8_t *line)
{
    if (row >= (sel ? VW_LINES : VIN_LINES)) { fprintf(stderr, "DBG2 row %u out of range\n", row); return -1; }
    uint32_t s = bb_rd(h, BB2_STATUS);
    if (s & 0x9u) { fprintf(stderr, "DBG2 while vector blackbox busy, STATUS2=0x%x\n", s); return -1; }
    bb_wr(h, BB2_DBG, (sel ? (1u << 16) : 0u) | row);
    double t = hw_now();
    for (;;) {
        s = bb_rd(h, BB2_STATUS);
        if ((s & 4u) && !(s & 1u)) break;
        if (hw_now() - t > BB_TIMEOUT_S) { fprintf(stderr, "DBG2 timeout STATUS2=0x%x\n", s); return -1; }
    }
    for (unsigned w = 0; w < 8; w++) {
        uint32_t v = bb_rd(h, BB2_DBG_DATA + 4 * w);
        memcpy(line + 4 * w, &v, 4);
    }
    return 0;
}

/* ---- L2 through the PS (ch0) ----------------------------------------------------------------- */
void hw_l2_write(hw_ctx *h, uint32_t c, const uint8_t *src, uint32_t nlines)
{
    volatile uint64_t *d = h->l2 + (size_t)c * 4;
    for (size_t i = 0; i < (size_t)nlines * 4; i++) {
        uint64_t v;
        memcpy(&v, src + 8 * i, 8);
        d[i] = v;
    }
    dsb();
}

void hw_l2_read(hw_ctx *h, uint32_t c, uint8_t *dst, uint32_t nlines)
{
    volatile uint64_t *s = h->l2 + (size_t)c * 4;
    for (size_t i = 0; i < (size_t)nlines * 4; i++) {
        uint64_t v = s[i];
        memcpy(dst + 8 * i, &v, 8);
    }
}

/* ---- open / close ------------------------------------------------------------------------------ */
static void *map_region(int fd, uint64_t base, size_t size, const char *name)
{
    void *p = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, (off_t)base);
    if (p == MAP_FAILED) { fprintf(stderr, "mmap %s: %s\n", name, strerror(errno)); return NULL; }
    return p;
}

int hw_open(hw_ctx *h)
{
    memset(h, 0, sizeof *h);
    h->fd_mem = -1;

    struct sigaction act;
    memset(&act, 0, sizeof act);
    act.sa_handler = stop_handler;
    sigemptyset(&act.sa_mask);
    sigaction(SIGINT, &act, NULL);
    sigaction(SIGTERM, &act, NULL);

    /* 1. PL0 clock before any PL access */
    h->pl0_hz = read_pl0_hz();
    if (h->pl0_hz != PL0_EXPECT_HZ) {
        if (!h->pl0_hz) fprintf(stderr, "PL0 clock: cannot read pl0_ref from clk_summary (run with sudo)\n");
        else fprintf(stderr, "PL0 clock %" PRIu64 " Hz (Linux) != expected %" PRIu64 " Hz: load the "
                     "bitstream with the 214 MHz overlay first\n", h->pl0_hz, PL0_EXPECT_HZ);
        return -1;
    }

    /* 2. mappings */
    h->fd_mem = open("/dev/mem", O_RDWR | O_SYNC | O_CLOEXEC);
    if (h->fd_mem < 0) { perror("open /dev/mem"); return -1; }
    h->l2   = map_region(h->fd_mem, L2_DATA_BASE, L2_DATA_SIZE, "L2");
    h->cmd  = map_region(h->fd_mem, L2_CMD_BASE, L2_CMD_SIZE, "CMD");
    h->bb   = map_region(h->fd_mem, BB_CTRL_BASE, BB_CTRL_SIZE, "BB");
    h->cdma = map_region(h->fd_mem, CDMA_BASE, CDMA_SIZE, "CDMA");
    if (!h->l2 || !h->cmd || !h->bb || !h->cdma) return -1;

    /* 3. CDMA idle -> reset */
    uint32_t s = dma_rd(h, CDMASR);
    if (!(s & SR_IDLE)) { fprintf(stderr, "CDMA busy (SR=0x%08x): refusing to reset another transfer\n", s); return -1; }
    if (cdma_reset(h)) { fprintf(stderr, "CDMA reset failed\n"); return -1; }

    /* 4. command adapter identity, no sticky errors, channels idle */
    uint64_t ver = cmd_rd(h, CMD_VERSION);
    if ((uint32_t)ver != CMD_VERSION_ID) {
        fprintf(stderr, "command adapter VERSION 0x%" PRIx64 " (expected 0x%08x): wrong bitstream?\n", ver, CMD_VERSION_ID);
        return -1;
    }
    uint64_t err = cmd_rd(h, CMD_ERRORS);
    if (err & 0x1F) {
        fprintf(stderr, "command adapter ERRORS=0x%" PRIx64 " from an earlier run, clearing\n", err);
        cmd_wr(h, CMD_ERRORS, 0x1F);
    }
    if (cmd_rd(h, CMD_BUSY) & 0xF) { fprintf(stderr, "L2 channels busy at start\n"); return -1; }

    /* 5. blackbox idle, no sticky START refusal */
    uint32_t bs = bb_rd(h, BB_STATUS);
    if (bs & 0x9u) {
        fprintf(stderr, "blackbox STATUS=0x%x at start (busy or err_start_busy): reload the bitstream\n", bs);
        return -1;
    }
    bs = bb_rd(h, BB2_STATUS);
    if (bs & 0x9u) {
        fprintf(stderr, "vector blackbox STATUS2=0x%x at start (busy or err_start_busy): reload the bitstream\n", bs);
        return -1;
    }
    return 0;
}

void hw_close(hw_ctx *h)
{
    if (h->cdma && h->dma_active) {
        fprintf(stderr, "resetting CDMA before exit...\n");
        if (cdma_reset(h)) {
            fprintf(stderr, "BOARD_RESULT=FAIL reason=DMA_NOT_QUIESCENT\n"
                            "Buffers retained. Do NOT kill; reset/reboot the board to stop the DMA.\n");
            for (;;) pause();   /* never return active DMA buffers to the allocator */
        }
    }
    if (h->l2)   munmap((void *)h->l2, L2_DATA_SIZE);
    if (h->cmd)  munmap((void *)h->cmd, L2_CMD_SIZE);
    if (h->bb)   munmap((void *)h->bb, BB_CTRL_SIZE);
    if (h->cdma) munmap((void *)h->cdma, CDMA_SIZE);
    if (h->fd_mem >= 0) close(h->fd_mem);
    h->l2 = NULL; h->cmd = NULL; h->bb = NULL; h->cdma = NULL; h->fd_mem = -1;
}
