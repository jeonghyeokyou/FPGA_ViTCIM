/* mlp_ps.c - PS work of the MLP block. See mlp_ops.h.  JH, 2026-11-10
 *
 * Build with -ffp-contract=off : gcc (gnu modes) may otherwise fuse a*b + c into one FMA
 * (aarch64 does), which rounds differently from numpy and breaks bit-exact LN2.
 * No hardware access here (x86 test: test_mlp_ps.c).
 */
#include "mlp_ops.h"
#include "mxfp4.h"

#include <math.h>

int ps_ln2_mx(const uint8_t *r, const float *g, const float *b, double eps, uint8_t *x2, uint8_t *x2s)
{
    double x[VIT_DMODEL], v[VIT_DMODEL];
    for (uint32_t t = 0; t < VIT_TOKENS; t++) {
        const uint8_t *rt = r + (size_t)t * VIT_DMODEL * 2;
        double s = 0.0;
        for (int i = 0; i < VIT_DMODEL; i++) {                   /* in order, like the generator */
            x[i] = bf16_to_d(rd_bf16(rt + 2 * i));
            s += x[i];
        }
        double mean = s / VIT_DMODEL;
        double q = 0.0;
        for (int i = 0; i < VIT_DMODEL; i++) {
            double d = x[i] - mean;
            q += d * d;
        }
        double sd = sqrt(q / VIT_DMODEL + eps);
        for (int i = 0; i < VIT_DMODEL; i++) {
            double y = ((x[i] - mean) / sd) * (double)g[i] + (double)b[i];
            v[i] = bf16_to_d(f32_to_bf16((float)y));             /* f64 -> f32 -> BF16 RNE */
        }
        if (mx_quant(v, VIT_DMODEL, x2 + LB(X_LINES_PER_TOKEN * t), x2s + 24 * t)) return -1;
    }
    return 0;
}

int ps_mx_g(const uint8_t *g, int tile, uint8_t *h4, uint8_t *h4s)
{
    int k = tile / 12;
    return ps_mx_o(g, tile % 12, h4 + h4_off(k), h4s + (size_t)H4_SCALES * (size_t)k);
}

void ps_fc2_acc(float *acc, const uint8_t *p, int k, const float *b2n, uint8_t *y2n)
{
    for (uint32_t t = 0; t < VIT_TOKENS; t++)
        for (uint32_t c = 0; c < 64; c++) {
            size_t i = (size_t)t * 64 + c;
            float pv = bf16_to_f(rd_bf16(p + LB(4u * t) + 2 * c));
            acc[i] = (k == 0 ? b2n[c] : acc[i]) + pv;            /* float32 add */
            if (k == (int)FC2_K - 1) wr_bf16(y2n + LB(4u * t) + 2 * c, f32_to_bf16(acc[i]));
        }
}
