/* vit_ops.c - ViT-Base operations (dataflow). See vit_ops.h. */
#include "vit_ops.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

static uint8_t *read_file(const char *dir, const char *name, size_t expect)
{
    char path[1024];
    snprintf(path, sizeof path, "%s/%s", dir, name);
    FILE *fp = fopen(path, "rb");
    if (!fp) { fprintf(stderr, "open %s: %s\n", path, strerror(errno)); return NULL; }
    uint8_t *p = malloc(expect + 1);
    size_t got = p ? fread(p, 1, expect + 1, fp) : 0;
    fclose(fp);
    if (!p || got != expect) {
        fprintf(stderr, "%s: %zu bytes, expected %zu\n", path, got, expect);
        free(p);
        return NULL;
    }
    return p;
}

int qkv_files_load(const char *dir, qkv_files *f)
{
    memset(f, 0, sizeof *f);
    f->x = read_file(dir, "x.bin", X_BYTES);
    f->w = read_file(dir, "w.bin", W_FILE_BYTES);
    f->y_golden = read_file(dir, "y_golden.bin", Y_FILE_BYTES);
    if (!f->x || !f->w || !f->y_golden) { qkv_files_free(f); return -1; }
    return 0;
}

void qkv_files_free(qkv_files *f)
{
    free((void *)f->x); free((void *)f->w); free((void *)f->y_golden);
    f->x = f->w = f->y_golden = NULL;
}

const qkv_layout QKV_LAYOUT_DEFAULT = {
    .x_c = 0x0000,
    .w_c = { 0x0C00, 0x2400 },
    .y_c = { 0x1800, 0x3000 },
};

static const char PNAME[3] = { 'Q', 'K', 'V' };

static int run_bb(hw_ctx *h, const qkv_hooks *k, bb_call *c)
{
    if (k && k->before_bb && k->before_bb(k->user, c)) return -1;
    if (hw_bb_gold_load(h, c->gold, c->out_len)) return -1;
    if (hw_bb_run(h, c->in_base, c->in_len, c->w_base, c->w_len, c->out_base, c->out_len, 0, &c->cycles))
        return -1;
    if (k && k->after_bb && k->after_bb(k->user, c)) return -1;
    return 0;
}

int qkv_proj_head(hw_ctx *h, const qkv_layout *L, const qkv_files *f, int head, int buf,
                  const qkv_hooks *hooks)
{
    if (head < 0 || head >= VIT_HEADS || (buf != 0 && buf != 1)) return -1;

    for (int p = 0; p < 3; p++) {
        if (hw_stop_requested()) return -1;
        if (hw_cmd_run(h, cmd_w_load(qkv_w_c(L, buf, p), W_LINES_PER_P, 0))) {
            fprintf(stderr, "head %d W%c LOAD failed\n", head, PNAME[p]);
            return -1;
        }
        for (int g = 0; g < 2; g++) {
            uint32_t g0 = 128u * (uint32_t)g;
            uint32_t nt = g ? (VIT_TOKENS - 128u) : 128u;     /* 128 / 69 */
            uint32_t n2 = nt - 64u;                            /* 64 / 5   */

            if (hw_cmd_run(h, cmd_x_load(L->x_c + X_LINES_PER_TOKEN * g0, X_LINES_PER_TOKEN * nt, QKV_L1_IN0))) {
                fprintf(stderr, "head %d %c group %d X LOAD failed\n", head, PNAME[p], g);
                return -1;
            }

            bb_call c1 = {
                .head = head, .p = p, .group = g, .idx = 0, .tok0 = g0, .ntok = 64,
                .in_base = QKV_L1_IN0, .in_len = X_LINES_PER_TOKEN * 64u,
                .w_base = 0, .w_len = W_LINES_PER_P,
                .out_base = QKV_L1_OUT0, .out_len = Y_LINES_PER_TOKEN * 64u,
                .gold = f->y_golden + y_off(head, p, g0),
            };
            bb_call c2 = {
                .head = head, .p = p, .group = g, .idx = 1, .tok0 = g0 + 64u, .ntok = n2,
                .in_base = QKV_L1_IN1, .in_len = X_LINES_PER_TOKEN * n2,
                .w_base = 0, .w_len = W_LINES_PER_P,
                .out_base = QKV_L1_OUT1, .out_len = Y_LINES_PER_TOKEN * n2,
                .gold = f->y_golden + y_off(head, p, g0 + 64u),
            };
            if (run_bb(h, hooks, &c1) || run_bb(h, hooks, &c2)) {
                fprintf(stderr, "head %d %c group %d blackbox failed\n", head, PNAME[p], g);
                return -1;
            }

            store_info s = {
                .head = head, .p = p, .group = g,
                .l1_row = QKV_L1_OUT0, .nlines = Y_LINES_PER_TOKEN * nt,
                .l2_c = qkv_y_c(L, buf, p) + Y_LINES_PER_TOKEN * g0,
                .tok0 = g0, .ntok = nt,
                .gold = f->y_golden + y_off(head, p, g0),
            };
            if (hw_cmd_run(h, cmd_x_store(s.l1_row, s.nlines, s.l2_c))) {
                fprintf(stderr, "head %d Y%c STORE group %d failed\n", head, PNAME[p], g);
                return -1;
            }
            if (hooks && hooks->after_store && hooks->after_store(hooks->user, &s)) return -1;
        }
    }
    return 0;
}
