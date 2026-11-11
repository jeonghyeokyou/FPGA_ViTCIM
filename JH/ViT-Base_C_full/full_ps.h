/* full_ps.h - PS work before / after the 12 layers (VIT_FULL_TASK.md 4).  JH, 2026-11-11
 *
 *   embed : pixels [3][224][224] f32 -> h0 [197][768] BF16 (token 0 = CLS, 1 + t = patch t)
 *   LN1   : ps_ln2_mx (mlp_ops.h) with ln1_w / ln1_b -> x.bin layout MXFP4
 *   LN_f  : ps_ln_bf16 on the CLS token -> 768 BF16 (no quantization)
 *   head  : 768 BF16 -> logits [1000] f32 -> top-1
 * Sums go i = 0..767 in order in double; products of two floats are exact in double.
 * Build with -ffp-contract=off (as mlp_ps.c).
 */
#ifndef FULL_PS_H
#define FULL_PS_H

#include <stdint.h>
#include <stddef.h>

#define FULL_IMG      224
#define FULL_PATCH    16
#define FULL_GRID     (FULL_IMG / FULL_PATCH)                 /* 14            */
#define FULL_NPATCH   (FULL_GRID * FULL_GRID)                 /* 196           */
#define FULL_NCLASS   1000
#define PIXELS_FLOATS (3u * FULL_IMG * FULL_IMG)              /* pixels.bin    */

/* patch t = (t / 14, t % 14), element i = (ch, kh, kw) = conv weight [768][3][16][16] flattened.
 * h0[1+t][o] = BF16(f32(sum_i p[i] W[o][i] + b[o] + pos[1+t][o])), h0[0][o] = BF16(f32(cls[o] + pos[0][o])) */
void ps_embed(const float *px, const float *pw, const float *pb, const float *cls, const float *pos, uint8_t *h0);
/* one token (768 BF16, LE bytes) -> LN -> 768 BF16 (LE bytes); same formula as ps_ln2_mx */
void ps_ln_bf16(const uint8_t *x, const float *g, const float *b, double eps, uint8_t *y);
/* logits[o] = f32(sum_i lnc[i] W[o][i] + b[o]), o < ncls */
void ps_head(const uint8_t *lnc, const float *hw, const float *hb, int ncls, float *logits);
/* index of the first largest value */
int  ps_top1(const float *v, int n);

#endif
