# Makefile - ViT-Base layer 0 (attention + MLP).  JH, 2026-11-10
#
#   board (ZCU102, own folder)          : make OUT=.      -> ./vit_main ./vit_dbg ./vit_full  (plain make writes ../ = Hyunjun's binaries)
#   x86 model (no board)                : make sim        -> ./vit_main_sim ./vit_dbg_sim ./vit_full_sim ./test_mlp_ps ./test_full_ps
#   cross from a PC                     : make CC=aarch64-linux-gnu-gcc
#
# mlp_ps.c is always compiled with -ffp-contract=off: gcc in gnu modes may fuse a*b + c into an FMA
# (aarch64 does: 2 fmadd in ps_ln2_mx without the flag), which breaks bit-exact LN2.

CC      ?= gcc
CFLAGS  ?= -O2 -std=gnu11 -Wall -Wextra
OUT     ?= ..
LDLIBS   = -lm
EXE     ?=

OPS      = vit_ops.c attn_ops.c mlp_ops.c mxfp4.c
DBG      = dbg_common.c dbg_qkv.c dbg_attn.c dbg_mlp.c
HDRS     = $(wildcard *.h)

.PHONY: all sim clean
all: $(OUT)/vit_main $(OUT)/vit_dbg $(OUT)/vit_full

mlp_ps.o: mlp_ps.c $(HDRS)
	$(CC) $(CFLAGS) -ffp-contract=off -c -o $@ mlp_ps.c

full_ps.o: full_ps.c $(HDRS)
	$(CC) $(CFLAGS) -ffp-contract=off -c -o $@ full_ps.c

# PS test of embed / LN1 / final LN / head (VIT_FULL_TASK.md Phase 2); x86 or cross (CC=aarch64-linux-gnu-gcc)
test_full_ps$(EXE): test_full_ps.c full_ps.o mlp_ps.o attn_ops.c mxfp4.c $(HDRS)
	$(CC) $(CFLAGS) -ffp-contract=off -o $@ test_full_ps.c full_ps.o mlp_ps.o attn_ops.c mxfp4.c $(LDLIBS)

$(OUT)/vit_main: vit_main.c layer_run.c vit_hw.c $(OPS) mlp_ps.o $(HDRS)
	$(CC) $(CFLAGS) -o $@ vit_main.c layer_run.c vit_hw.c $(OPS) mlp_ps.o $(LDLIBS)

$(OUT)/vit_full: vit_full.c layer_run.c vit_hw.c $(OPS) mlp_ps.o full_ps.o $(HDRS)
	$(CC) $(CFLAGS) -o $@ vit_full.c layer_run.c vit_hw.c $(OPS) mlp_ps.o full_ps.o $(LDLIBS)

$(OUT)/vit_dbg: vit_dbg.c vit_hw.c $(OPS) $(DBG) mlp_ps.o $(HDRS)
	$(CC) $(CFLAGS) -o $@ vit_dbg.c vit_hw.c $(OPS) $(DBG) mlp_ps.o $(LDLIBS)

sim: vit_main_sim$(EXE) vit_dbg_sim$(EXE) vit_full_sim$(EXE) test_mlp_ps$(EXE) test_full_ps$(EXE)

vit_main_sim$(EXE): vit_main.c layer_run.c hw_sim.c $(OPS) mlp_ps.o $(HDRS)
	$(CC) $(CFLAGS) -o $@ vit_main.c layer_run.c hw_sim.c $(OPS) mlp_ps.o $(LDLIBS)

vit_full_sim$(EXE): vit_full.c layer_run.c hw_sim.c $(OPS) mlp_ps.o full_ps.o $(HDRS)
	$(CC) $(CFLAGS) -o $@ vit_full.c layer_run.c hw_sim.c $(OPS) mlp_ps.o full_ps.o $(LDLIBS)

vit_dbg_sim$(EXE): vit_dbg.c hw_sim.c $(OPS) $(DBG) mlp_ps.o $(HDRS)
	$(CC) $(CFLAGS) -o $@ vit_dbg.c hw_sim.c $(OPS) $(DBG) mlp_ps.o $(LDLIBS)

test_mlp_ps$(EXE): test_mlp_ps.c mlp_ops.c attn_ops.c mxfp4.c mlp_ps.o $(HDRS)
	$(CC) $(CFLAGS) -ffp-contract=off -o $@ test_mlp_ps.c mlp_ops.c attn_ops.c mxfp4.c mlp_ps.o $(LDLIBS)

clean:
	rm -f mlp_ps.o full_ps.o vit_main_sim$(EXE) vit_full_sim$(EXE) vit_dbg_sim$(EXE) test_mlp_ps$(EXE) test_full_ps$(EXE)
