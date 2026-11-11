/* mxfp4.c - see mxfp4.h */
#include "mxfp4.h"

#include <math.h>
#include <string.h>

_Static_assert(sizeof(float) == 4 && sizeof(double) == 8, "IEEE float / double required");

/* |v| thresholds of vit_golden_gen.py fp4_encode (ties go to the even mantissa) */
static unsigned fp4_code(double v)
{
    double m = fabs(v);
    unsigned c;
    if      (m <= 0.25) c = 0;
    else if (m <  0.75) c = 1;
    else if (m <= 1.25) c = 2;
    else if (m <  1.75) c = 3;
    else if (m <= 2.5)  c = 4;
    else if (m <  3.5)  c = 5;
    else if (m <= 5.0)  c = 6;
    else                c = 7;
    if (v < 0 && c) c |= 8;
    return c;
}

int mx_quant(const double *v, size_t n, uint8_t *packed, uint8_t *scale)
{
    if (n % MX_BLOCK) return -1;
    for (size_t b = 0; b < n / MX_BLOCK; b++) {
        const double *x = v + b * MX_BLOCK;
        double amax = 0;
        for (int i = 0; i < MX_BLOCK; i++) {
            if (!isfinite(x[i])) return -1;
            double a = fabs(x[i]);
            if (a > amax) amax = a;
        }
        int X = -127;
        if (amax > 0) {
            int e;
            frexp(amax, &e);                 /* amax = f * 2^e, f in [0.5, 1) -> floor(log2) = e - 1 */
            X = e - 1 - 2;
            if (X < -127) X = -127;
            if (X > 127) X = 127;
        }
        scale[b] = (uint8_t)(X + 127);
        for (int i = 0; i < MX_BLOCK; i += 2) {
            unsigned lo = fp4_code(ldexp(x[i], -X));
            unsigned hi = fp4_code(ldexp(x[i + 1], -X));
            packed[(b * MX_BLOCK + (size_t)i) / 2] = (uint8_t)(lo | (hi << 4));
        }
    }
    return 0;
}

float bf16_to_f(uint16_t b)
{
    uint32_t u = (uint32_t)b << 16;
    float f;
    memcpy(&f, &u, 4);
    return f;
}

double bf16_to_d(uint16_t b) { return (double)bf16_to_f(b); }

uint16_t f32_to_bf16(float f)
{
    uint32_t u;
    memcpy(&u, &f, 4);
    uint64_t w = u;
    return (uint16_t)((w + 0x7FFF + ((w >> 16) & 1)) >> 16);
}

uint16_t rd_bf16(const uint8_t *p) { return (uint16_t)(p[0] | (p[1] << 8)); }
void     wr_bf16(uint8_t *p, uint16_t v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); }
