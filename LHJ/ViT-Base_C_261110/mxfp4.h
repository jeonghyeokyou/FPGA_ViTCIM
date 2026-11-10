/* mxfp4.h - OCP MX v1.0 MXFP4 on the PS, bit-identical to vit_golden_gen.py (MXFP4 version).
 *
 *  block   : 32 consecutive values along the reduction axis, one E8M0 scale byte = X + 127
 *  X       : floor(log2(max |v|)) - 2, clipped to [-127, 127]; all-zero block -> -127
 *  element : v / 2^X -> E2M1 round-to-nearest, ties to mantissa 0, |.| > 6 -> 6
 *  code    : [3] sign, [2:0] magnitude index (0:0 1:0.5 2:1 3:1.5 4:2 5:3 6:4 7:6), no -0
 *  packing : element 2i -> byte[3:0], element 2i+1 -> byte[7:4]
 * Inputs here are BF16 (8-bit mantissa), so floor(log2) is exact with frexp.
 */
#ifndef MXFP4_H
#define MXFP4_H

#include <stdint.h>
#include <stddef.h>

#define MX_BLOCK 32

/* n values (n % 32 == 0) -> n/2 packed bytes + n/32 scale bytes; -1 on a non-finite value */
int mx_quant(const double *v, size_t n, uint8_t *packed, uint8_t *scale);

/* BF16 <-> float */
double   bf16_to_d(uint16_t b);
float    bf16_to_f(uint16_t b);
uint16_t f32_to_bf16(float f);          /* round to nearest even (finite input) */
uint16_t rd_bf16(const uint8_t *p);     /* little-endian */
void     wr_bf16(uint8_t *p, uint16_t v);

#endif
