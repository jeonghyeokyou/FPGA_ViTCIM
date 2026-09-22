# =====================================================================
#  build_synth.tcl  -  non-project batch-mode synthesis of l2_noc_fpga_top
#
#  Usage:
#    "C:\Xilinx\Vivado\2024.2\bin\vivado.bat" -mode batch -source build_synth.tcl
#
#  What it does:
#    1. Reads the synthesis fileset (L2 fix + NOC renamed/fpga-fixed +
#       adapter + top), same sources verified with xvlog/xelab already.
#    2. synth_design against xczu7ev-ffvc1156-2-e (see constraints.xdc for
#       why - swap PART below once you have a real target board).
#    3. Reports utilization (LUT/FF/BRAM/URAM/DSP) and timing (WNS/TNS).
#    4. If synthesis succeeds, also runs opt/place/route so the timing
#       report reflects real routing, not just a synthesis estimate, and
#       writes a checkpoint - no bitstream (no real board/pinout yet).
#  Everything lands in verif/fpga/build/.
# =====================================================================

set PART "xczu9eg-ffvb1156-2-e"    ;# ZCU102 (corrected 2026-09-15 - was xczu7ev/ZCU104, wrong board)
set ROOT [file normalize [file dirname [info script]]]
set BUILD "$ROOT/build"
file mkdir $BUILD

create_project -in_memory -part $PART

proc read_filelist {path type} {
    set fh [open $path r]
    while {[gets $fh line] >= 0} {
        set line [string trim $line]
        if {$line eq "" || [string index $line 0] eq "#"} { continue }
        if {$type eq "sv"} { read_verilog -sv $line } else { read_verilog $line }
    }
    close $fh
}

puts "===== reading L2 (.sv) ====="
read_filelist "$ROOT/../l2/l2_files_ramfix.f" sv

puts "===== reading NOC (.v, fpga sram_mimic) ====="
read_filelist "$ROOT/fpga_files_noc.f" v

puts "===== reading adapter + top (.sv) ====="
read_verilog -sv "$ROOT/../integ/noc_ch1_in_adapter.sv"
read_verilog -sv "$ROOT/l2_noc_fpga_top.sv"

read_xdc "$ROOT/constraints.xdc"

puts "===== synth_design ====="
synth_design -top l2_noc_fpga_top -part $PART

write_checkpoint -force "$BUILD/post_synth.dcp"
report_utilization -file "$BUILD/util_synth.rpt"
report_timing_summary -file "$BUILD/timing_synth.rpt"

puts "===== opt/place/route ====="
opt_design
place_design
route_design

write_checkpoint -force "$BUILD/post_route.dcp"
report_utilization -file "$BUILD/util_route.rpt"
report_timing_summary -file "$BUILD/timing_route.rpt"
report_drc -file "$BUILD/drc.rpt"

puts "===== DONE - reports in $BUILD ====="
