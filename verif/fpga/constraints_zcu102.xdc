# =====================================================================
#  constraints_zcu102.xdc
#
#  Real ZCU102 (xczu9eg-ffvb1156-2-e) pin constraints for zcu102_wrapper
#  (the board-facing top; l2_noc_fpga_top sits underneath it unchanged).
#
#  The set_property lines below are copied verbatim (pin/IOSTANDARD +
#  original bank comment) from the user's own downloaded master XDC:
#    C:/RTL_YJH/FPGA_ZCU102/zcu102-schematic-xtp454_cluster/
#      zcu102-xdc-rdf0405/zcu102_Rev1.0_U1_09152016.xdc
#    (lines 216-225 for the LEDs, 238-239 for CPU_RESET, 621-624 for the
#    USER_SI570 differential clock)
#  Cross-checked 2026-09-16 against Vivado's own installed board part
#  `xilinx.com:zcu102:part0:3.4` (part0_pins.xml) - identical values.
#
#  This replaces the earlier placeholder constraints.xdc (which only had
#  a clock period + false paths, no real pins) once targeting actual
#  hardware instead of just a resource/timing check.
# =====================================================================

## ---- 300 MHz differential system clock (Si5341, "USER_SI570_P/N") -
##      feeds the Clocking Wizard IP inside zcu102_wrapper, which derives
##      the 100 MHz clock l2_noc_fpga_top actually runs on. ----
set_property PACKAGE_PIN AL8         [get_ports "USER_SI570_P"] ;# Bank  64 VCCO - VCC1V2   - IO_L12P_T1U_N10_GC_64
set_property IOSTANDARD  DIFF_SSTL12 [get_ports "USER_SI570_P"] ;# Bank  64 VCCO - VCC1V2   - IO_L12P_T1U_N10_GC_64
set_property PACKAGE_PIN AL7         [get_ports "USER_SI570_N"] ;# Bank  64 VCCO - VCC1V2   - IO_L12N_T1U_N11_GC_64
set_property IOSTANDARD  DIFF_SSTL12 [get_ports "USER_SI570_N"] ;# Bank  64 VCCO - VCC1V2   - IO_L12N_T1U_N11_GC_64
create_clock -period 3.333 -name sys_clk_300 [get_ports "USER_SI570_P"]

## ---- CPU_RESET push button - ACTIVE HIGH. zcu102_wrapper inverts this
##      before driving l2_noc_fpga_top's active-low i_rst_n. Not timing-
##      critical -> false path. ----
set_property PACKAGE_PIN AM13     [get_ports "CPU_RESET"] ;# Bank  44 VCCO - VCC3V3   - IO_L4N_AD8N_44
set_property IOSTANDARD  LVCMOS33 [get_ports "CPU_RESET"] ;# Bank  44 VCCO - VCC3V3   - IO_L4N_AD8N_44
set_false_path -from [get_ports "CPU_RESET"]

## ---- 5 of the board's 8 user LEDs, active-high. Not timing-critical ->
##      false path. ----
set_property PACKAGE_PIN AG14     [get_ports "GPIO_LED_0"] ;# Bank  44 VCCO - VCC3V3   - IO_L10P_AD2P_44
set_property IOSTANDARD  LVCMOS33 [get_ports "GPIO_LED_0"] ;# Bank  44 VCCO - VCC3V3   - IO_L10P_AD2P_44
set_property PACKAGE_PIN AF13     [get_ports "GPIO_LED_1"] ;# Bank  44 VCCO - VCC3V3   - IO_L9N_AD3N_44
set_property IOSTANDARD  LVCMOS33 [get_ports "GPIO_LED_1"] ;# Bank  44 VCCO - VCC3V3   - IO_L9N_AD3N_44
set_property PACKAGE_PIN AE13     [get_ports "GPIO_LED_2"] ;# Bank  44 VCCO - VCC3V3   - IO_L9P_AD3P_44
set_property IOSTANDARD  LVCMOS33 [get_ports "GPIO_LED_2"] ;# Bank  44 VCCO - VCC3V3   - IO_L9P_AD3P_44
set_property PACKAGE_PIN AJ14     [get_ports "GPIO_LED_3"] ;# Bank  44 VCCO - VCC3V3   - IO_L8N_HDGC_AD4N_44
set_property IOSTANDARD  LVCMOS33 [get_ports "GPIO_LED_3"] ;# Bank  44 VCCO - VCC3V3   - IO_L8N_HDGC_AD4N_44
set_property PACKAGE_PIN AJ15     [get_ports "GPIO_LED_4"] ;# Bank  44 VCCO - VCC3V3   - IO_L8P_HDGC_AD4P_44
set_property IOSTANDARD  LVCMOS33 [get_ports "GPIO_LED_4"] ;# Bank  44 VCCO - VCC3V3   - IO_L8P_HDGC_AD4P_44
set_false_path -to [get_ports {GPIO_LED_0 GPIO_LED_1 GPIO_LED_2 GPIO_LED_3 GPIO_LED_4}]
