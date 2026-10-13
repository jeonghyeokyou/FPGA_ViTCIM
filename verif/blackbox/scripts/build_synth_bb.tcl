# =====================================================================
#  build_synth_bb.tcl  -  Blackbox 시스템 top 합성 (Phase 4)
#  verif/fpga/build_synth_size.tcl 방식 (non-project, in-memory)
#
#  Usage (verif/blackbox/scripts 에서):
#    "C:\Xilinx\Vivado\2024.2\bin\vivado.bat" -mode batch -source build_synth_bb.tcl -log build_bb/vivado.log -journal build_bb/vivado.jou
#
#  top  = l2_noc_bb_bd_wrapper, OOC (out_of_context) 모드 -> I/O 핀 배치 없이 합성/배치/배선
#  part = xczu9eg-ffvb1156-2-e (ZCU102), aclk 100 MHz
#  L2   = 8 x 16 x 1024 x 64b = 1 MiB  (LHJ/ram_mimic_fpga_bram.sv, ram_style=block)
#  L1   = sram_mimic_fpga.v (BRAM 추론용)
#  결과 = verif/blackbox/scripts/build_bb/*.rpt , *.dcp
# =====================================================================
set PART  "xczu9eg-ffvb1156-2-e"
set ROOT  [file normalize [file dirname [info script]]]
set BUILD "$ROOT/build_bb"
file mkdir $BUILD

create_project -in_memory -part $PART

set fh [open "$ROOT/files_bb_synth.f" r]
while {[gets $fh line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string index $line 0] eq "#"} { continue }
    if {[string match "*.sv" $line]} { read_verilog -sv $line } else { read_verilog $line }
}
close $fh
read_xdc -mode out_of_context "$ROOT/constraints_bb.xdc"

puts "===== synth_design (OOC) ====="
synth_design -top l2_noc_bb_bd_wrapper -part $PART -mode out_of_context
write_checkpoint -force "$BUILD/post_synth.dcp"
report_utilization -file "$BUILD/util_synth.rpt"
report_utilization -hierarchical -hierarchical_depth 3 -file "$BUILD/util_synth_hier.rpt"
report_timing_summary -file "$BUILD/timing_synth.rpt"

puts "===== opt / place / route ====="
opt_design
place_design
route_design
write_checkpoint -force "$BUILD/post_route.dcp"

report_utilization -file "$BUILD/util_route.rpt"
report_utilization -hierarchical -hierarchical_depth 3 -file "$BUILD/util_route_hier.rpt"
report_ram_utilization -file "$BUILD/ram_route.rpt"
report_timing_summary -max_paths 10 -file "$BUILD/timing_route.rpt"
report_timing -max_paths 3 -nworst 1 -unique_pins -path_type full -file "$BUILD/top3_paths.rpt"
report_timing -max_paths 3 -nworst 1 -unique_pins -hold -path_type summary -file "$BUILD/top3_hold.rpt"
report_drc -file "$BUILD/drc.rpt"

puts "===== DONE - reports in $BUILD ====="
