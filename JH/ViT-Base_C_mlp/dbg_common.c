/* dbg_common.c - shared verification tools for vit_dbg. */
#include "dbg_common.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>

const char *const DBG_CHK_NAME[NCHK] = {
    "C1 DDR -> L2 (CDMA, read back by PS)",
    "C2 BB inputs (L1 in, WMEM, vector in) per call",
    "C3 BB CYCLES (MAC in+w+out+9, vec in+3out+6)",
    "C4 output (L1 out, L2, DDR) vs Golden",
    "C5 compare catches injected 1-bit error",
    "C6 PS result (MXFP4, residual) vs Python file",
};
int dbg_pass[NCHK], dbg_fail[NCHK];

void dbg_result(int chk, const char *what, size_t checked, size_t bad)
{
    printf("  [%s] C%d %-46s %6zu lines | mismatch %zu\n", bad ? "FAIL" : "PASS", chk + 1, what, checked, bad);
    if (bad) dbg_fail[chk]++;
    else dbg_pass[chk]++;
}

size_t dbg_cmp_lines(const char *tag, const uint8_t *got, const uint8_t *exp, uint32_t nlines)
{
    size_t bad = 0;
    for (uint32_t k = 0; k < nlines; k++) {
        const uint8_t *g = got + (size_t)k * LINE_BYTES, *e = exp + (size_t)k * LINE_BYTES;
        if (!memcmp(g, e, LINE_BYTES)) continue;
        if (bad < 3) {
            for (int lane = 0; lane < 4; lane++) {
                uint64_t gv, ev;
                memcpy(&gv, g + 8 * lane, 8);
                memcpy(&ev, e + 8 * lane, 8);
                if (gv != ev) {
                    printf("      %s line %u lane %d: got %016" PRIx64 " exp %016" PRIx64 "\n", tag, k, lane, gv, ev);
                    break;
                }
            }
        }
        bad++;
    }
    return bad;
}

size_t dbg_cmp_l2(hw_ctx *h, const char *tag, uint32_t c, const uint8_t *exp, uint32_t nlines)
{
    uint8_t *tmp = malloc((size_t)nlines * LINE_BYTES);
    if (!tmp) return nlines;
    hw_l2_read(h, c, tmp, nlines);
    size_t bad = dbg_cmp_lines(tag, tmp, exp, nlines);
    free(tmp);
    return bad;
}

void dbg_poison(uint8_t *dst, uint32_t nlines, uint32_t seed)
{
    for (size_t i = 0; i < (size_t)nlines * 4; i++) {
        uint64_t v = (UINT64_C(0xBAD0C0DE) << 32) ^ ((uint64_t)seed << 20) ^ (uint64_t)i;
        memcpy(dst + 8 * i, &v, 8);
    }
}

int dbg_l1_to_l2(hw_ctx *h, uint32_t l1_row, uint32_t n, uint32_t c)
{
    return hw_cmd_run(h, cmd_x_store(l1_row, n, c));
}

int dbg_wmem_to_l2(hw_ctx *h, uint32_t w_row, uint32_t n, uint32_t c)
{
    return hw_cmd_run(h, cmd_w_store(w_row, n, c));
}

int dbg_summary(void)
{
    int total = 0;
    puts("--------------------------------------------------------------------------");
    puts("  CHECK                                              PASS   FAIL");
    for (int i = 0; i < NCHK; i++) {
        printf("  %-50s %4d   %4d\n", DBG_CHK_NAME[i], dbg_pass[i], dbg_fail[i]);
        total += dbg_fail[i];
    }
    return total;
}
