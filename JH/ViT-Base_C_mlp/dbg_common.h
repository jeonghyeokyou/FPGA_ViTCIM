/* dbg_common.h - shared verification tools for vit_dbg. */
#ifndef DBG_COMMON_H
#define DBG_COMMON_H

#include "vit_hw.h"

/* L2 scratch lines used only by vit_dbg (quads 15+, untouched by the ViT flow) */
#define DBG_SCR_L1      0x3C00u   /* L1 readback, up to 1536 lines              */
#define DBG_SCR_WMEM    0x4400u   /* WMEM readback, up to 1024 lines            */
#define DBG_SCR_OUT     0x4800u   /* L1 output readback, up to 256 lines        */
#define DBG_SCR_POISON  0x4C00u   /* poison source for L1 output rows, 256 lines */

/* per-check counters */
enum { C1 = 0, C2, C3, C4, C5, C6, NCHK };   /* C6 : PS results (attention) */
extern const char *const DBG_CHK_NAME[NCHK];
extern int dbg_pass[NCHK], dbg_fail[NCHK];

/* print one result line and count it */
void dbg_result(int chk, const char *what, size_t checked, size_t bad);

/* compare n lines, print up to 3 differing lines (first differing 64-bit lane) */
size_t dbg_cmp_lines(const char *tag, const uint8_t *got, const uint8_t *exp, uint32_t nlines);

/* read n lines of L2 through the PS and compare */
size_t dbg_cmp_l2(hw_ctx *h, const char *tag, uint32_t c, const uint8_t *exp, uint32_t nlines);

/* deterministic poison lines (0xBAD0C0DE tag + seed + word index) */
void dbg_poison(uint8_t *dst, uint32_t nlines, uint32_t seed);

/* copy L1 rows / WMEM rows to L2 scratch (ch1_in STORE / ch1_wgt STORE) */
int dbg_l1_to_l2(hw_ctx *h, uint32_t l1_row, uint32_t n, uint32_t c);
int dbg_wmem_to_l2(hw_ctx *h, uint32_t w_row, uint32_t n, uint32_t c);

/* print the summary table; returns total failures */
int dbg_summary(void);

#endif
