# =====================================================================
#  Placeholder constraints for l2_noc_fpga_top.
#  Target: xczu9eg-ffvb1156-2-e (ZCU102 - confirmed real target 2026-09-15).
#  NOTE: ZU9EG has NO UltraRAM (only the "EV" UltraScale+ variants like the
#  ZU7EV on ZCU104 do) - ram_mimic.sv's `(* ram_style = "ultra" *)` cannot
#  be honored on this part. See build/util_synth.rpt after synthesis for
#  how Vivado actually resolved it (BRAM fallback or an error) - this may
#  need a ZCU102-specific ram_mimic copy with that attribute removed.
#  Board files are installed (xilinx.com:zcu102:part0) - switch to
#  `set_property board_part xilinx.com:zcu102:part0:3.4 [current_project]`
#  in build_synth.tcl and use the board's actual pin names once wiring a
#  real bitstream (LEDs/buttons/clock) instead of this placeholder XDC.
# =====================================================================

# 100 MHz system clock - matches the CLKP=10ns used throughout the
# simulation testbenches (verif/l2, verif/noc, verif/integ).
create_clock -period 10.000 -name sys_clk [get_ports i_clk]

# Async reset and LEDs are not timing-critical for a first synthesis/
# utilization check - mark them false-path so they don't skew the
# timing report, and leave I/O standard/LOC unconstrained (no board
# picked yet).
set_false_path -from [get_ports i_rst_n]
set_false_path -to   [get_ports o_led_done]
set_false_path -to   [get_ports o_led_pass]
set_false_path -to   [get_ports {o_mismatch_count[*]}]
