# Phase 1 : blackbox_pe unit (sim)
# paths are relative to share2/scripts/work_*/ (the directory the .bat files run in)
# rtl/fix = our fixed copies (see docs/FIX_SUMMARY.md), rtl/model_* = sim / FPGA memory models
../../rtl/model_sim/sram_mimic.v
../../rtl/bb/l1_sram.sv
../../rtl/bb/l1_port_mux.sv
../../rtl/bb/blackbox_pe.sv
../../tb/bb_pkg.sv
../../tb/tb_blackbox_pe.sv
