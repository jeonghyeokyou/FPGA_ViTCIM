# =====================================================================
#  build_synth.tcl  -  bb256 시스템 (CH1 blackbox_ip + CH2 blackbox_nl) 합성
#  verif/fpga/build_synth_size.tcl 방식 (non-project, in-memory)
#
#  Usage (bb256/scripts 에서):
#    "C:\Xilinx\Vivado\2024.2\bin\vivado.bat" -mode batch -source build_synth.tcl -log build/vivado.log -journal build/vivado.jou
#    other clock: ... -source build_synth.tcl -log ... -tclargs 5.0   (period ns; results in build_<MHz>MHz/)
#    + board margin: -tclargs 5.0 0.15   (extra set_clock_uncertainty ns; results in build_<MHz>MHz_u<ps>/)
#
#  top  = l2_system_bd_wrapper, OOC (out_of_context) 모드 -> I/O 핀 배치 없이 합성/배치/배선
#  part = xczu9eg-ffvb1156-2-e (ZCU102), aclk 100 MHz
#  L2   = 8 x 16 x 1024 x 64b = 1 MiB  (rtl/base/ram_mimic_fpga_bram.sv, ram_style=block)
#  L1 / blackbox 메모리 = sram_mimic_fpga.v (BRAM 추론용)
#  결과 = bb256/scripts/build/*.rpt , *.dcp
# =====================================================================
set PART  "xczu9eg-ffvb1156-2-e"
set ROOT  [file normalize [file dirname [info script]]]
set PERIOD 10.0
set UNC 0.0
if {$argc >= 1} { set PERIOD [lindex $argv 0] }
if {$argc >= 2 && [string is double -strict [lindex $argv 1]]} { set UNC [lindex $argv 1] }
if {$PERIOD == 10.0 && $UNC == 0.0} {
    set BUILD "$ROOT/build"
} else {
    set BUILD "$ROOT/build_[expr {int(round(1000.0 / $PERIOD))}]MHz"
    if {$UNC != 0.0} { append BUILD "_u[expr {int(round($UNC * 1000.0))}]" }
}
file mkdir $BUILD
puts "===== aclk period $PERIOD ns -> $BUILD ====="

create_project -in_memory -part $PART

set fh [open "$ROOT/files_synth.f" r]
while {[gets $fh line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string index $line 0] eq "#"} { continue }
    set line [file normalize [file join $ROOT work_synth $line]]   ;# list is relative to scripts/work_*/
    if {[string match "*.sv" $line]} { read_verilog -sv $line } else { read_verilog $line }
}
close $fh
if {$PERIOD == 10.0 && $UNC == 0.0} {
    read_xdc -mode out_of_context "$ROOT/constraints.xdc"
} else {
    set xf [open "$BUILD/constraints_period.xdc" w]
    puts $xf "create_clock -period $PERIOD -name aclk \[get_ports aclk\]"
    if {$UNC != 0.0} { puts $xf "set_clock_uncertainty -setup $UNC \[get_clocks aclk\]" }
    close $xf
    read_xdc -mode out_of_context "$BUILD/constraints_period.xdc"
}

puts "===== synth_design (OOC) ====="
synth_design -top l2_system_bd_wrapper -part $PART -mode out_of_context
write_checkpoint -force "$BUILD/post_synth.dcp"
report_utilization -file "$BUILD/util_synth.rpt"
report_utilization -hierarchical -hierarchical_depth 3 -file "$BUILD/util_synth_hier.rpt"
report_timing_summary -file "$BUILD/timing_synth.rpt"

puts "===== opt / place / route ====="
opt_design
place_design
phys_opt_design
route_design
phys_opt_design
write_checkpoint -force "$BUILD/post_route.dcp"

report_utilization -file "$BUILD/util_route.rpt"
report_utilization -hierarchical -hierarchical_depth 3 -file "$BUILD/util_route_hier.rpt"
report_ram_utilization -file "$BUILD/ram_route.rpt"
report_timing_summary -max_paths 10 -file "$BUILD/timing_route.rpt"
report_timing -max_paths 3 -nworst 1 -unique_pins -path_type full -file "$BUILD/top3_paths.rpt"
report_timing -max_paths 3 -nworst 1 -unique_pins -hold -path_type summary -file "$BUILD/top3_hold.rpt"
report_drc -file "$BUILD/drc.rpt"
# top-level hierarchy of start/end point for the worst setup paths
set fh [open "$BUILD/path_hier.rpt" w]
foreach p [get_timing_paths -max_paths 2000 -nworst 1 -setup] {
    set s [get_property STARTPOINT_PIN $p]; set e [get_property ENDPOINT_PIN $p]
    puts $fh "[get_property SLACK $p] [get_property LOGIC_LEVELS $p] $s -> $e"
}
close $fh

puts "===== DONE - reports in $BUILD ====="
