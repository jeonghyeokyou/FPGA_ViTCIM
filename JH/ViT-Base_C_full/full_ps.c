/* full_ps.c - PS work before / after the 12 layers. See full_ps.h.  JH, 2026-11-11
 *
 * Build with -ffp-contract=off : acc += a * b must stay a multiply then an add (no FMA),
 * as in vit_golden_gen.py --full (embed_bf16, head_f32).
 */
#include "full_ps.h"
#include "mlp_ops.h"
#include "mxfp4.h"

void ps_embed(const float *px, const float *pw, const float *pb, const float *cls, const float *pos, uint8_t *h0)
{
    double p[VIT_DMODEL];
    for (int o = 0; o < VIT_DMODEL; o++)
        wr_bf16(h0 + 2 * o, f32_to_bf16((float)((double)cls[o] + (double)pos[o])));
    for (int t = 0; t < FULL_NPATCH; t++) {
        int r = t / FULL_GRID, c = t % FULL_GRID;
        for (int i = 0; i < VIT_DMODEL; i++) {                   /* i = (ch, kh, kw) */
            int ch = i / (FULL_PATCH * FULL_PATCH), kh = (i / FULL_PATCH) % FULL_PATCH, kw = i % FULL_PATCH;
            p[i] = (double)px[((size_t)ch * FULL_IMG + (size_t)(r * FULL_PATCH + kh)) * FULL_IMG + (size_t)(c * FULL_PATCH + kw)];
        }
        const float *pt = pos + (size_t)(1 + t) * VIT_DMODEL;
        uint8_t *ht = h0 + (size_t)(1 + t) * VIT_DMODEL * 2;
        for (int o = 0; o < VIT_DMODEL; o++) {
            const float *w = pw + (size_t)o * VIT_DMODEL;
            double acc = 0.0;
            for (int i = 0; i < VIT_DMODEL; i++) acc += p[i] * (double)w[i];
            double v = acc + (double)pb[o] + (double)pt[o];
            wr_bf16(ht + 2 * o, f32_to_bf16((float)v));
        }
    }
}

void ps_ln_bf16(const uint8_t *x, const float *g, const float *b, double eps, uint8_t *y)
{
    uint16_t v[VIT_DMODEL];
    ps_ln_row(x, g, b, eps, v);
    for (int i = 0; i < VIT_DMODEL; i++) wr_bf16(y + 2 * i, v[i]);
}

void ps_head(const uint8_t *lnc, const float *hw, const float *hb, int ncls, float *logits)
{
    double x[VIT_DMODEL];
    for (int i = 0; i < VIT_DMODEL; i++) x[i] = bf16_to_d(rd_bf16(lnc + 2 * i));
    for (int o = 0; o < ncls; o++) {
        const float *w = hw + (size_t)o * VIT_DMODEL;
        double acc = 0.0;
        for (int i = 0; i < VIT_DMODEL; i++) acc += x[i] * (double)w[i];
        logits[o] = (float)(acc + (double)hb[o]);
    }
}

int ps_top1(const float *v, int n)
{
    int best = 0;
    for (int i = 1; i < n; i++)
        if (v[i] > v[best]) best = i;
    return best;
}
