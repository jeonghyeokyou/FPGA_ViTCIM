// =====================================================================
//  zcu102_wrapper.sv
//
//  Board-specific glue for l2_noc_fpga_top on the real ZCU102
//  (xczu9eg-ffvb1156-2-e). l2_noc_fpga_top itself is NOT modified - this
//  wrapper only adapts two board realities:
//
//    1. Reset polarity: the ZCU102 push button "CPU_RESET" is
//       ACTIVE-HIGH, but l2_noc_fpga_top expects an ACTIVE-LOW i_rst_n.
//       -> inverted here, and also held low until the clock IP locks.
//
//    2. Clock type: the only PL-reachable clock on this board is a
//       300 MHz DIFFERENTIAL clock (USER_SI570_P/N), not a single-ended
//       100 MHz clock like i_clk expects.
//       -> converted via a Clocking Wizard IP ("clk_wiz_0", 300MHz diff
//          in -> 100MHz single-ended out), generated separately through
//          Vivado's IP Catalog (see GUIDE_synthesis_gui.md).
//
//  Port names below (CPU_RESET, GPIO_LED_0..4, USER_SI570_P/N) match the
//  real downloaded ZCU102 master XDC exactly:
//    C:/RTL_YJH/FPGA_ZCU102/zcu102-schematic-xtp454_cluster/
//      zcu102-xdc-rdf0405/zcu102_Rev1.0_U1_09152016.xdc
//  so constraints_zcu102.xdc's lines (copied from that master file) apply
//  with no renaming. (Cross-checked 2026-09-16 against Vivado's installed
//  board part `xilinx.com:zcu102:part0:3.4` - same pins/IOSTANDARD, just
//  that file used "..._LS"/"user_si570_sysclk_*" spellings instead.)
// =====================================================================

module zcu102_wrapper (
    input  wire USER_SI570_P,
    input  wire USER_SI570_N,
    input  wire CPU_RESET,
    output wire GPIO_LED_0,   // o_led_done
    output wire GPIO_LED_1,   // o_led_pass
    output wire GPIO_LED_2,   // o_mismatch_count[0]
    output wire GPIO_LED_3,   // o_mismatch_count[1]
    output wire GPIO_LED_4    // o_mismatch_count[2]
);

    wire       clk_100;
    wire       mmcm_locked;
    wire       rst_n;
    wire [2:0] mismatch_count;

    // Clocking Wizard IP: 300MHz differential in -> 100MHz single-ended
    // out. Generated via IP Catalog with the board part set to ZCU102,
    // which lets the wizard's own "Board Interface" picker wire the
    // clk_in1_p/n ports straight to user_si570_sysclk - no manual pin
    // entry needed for the IP's own input buffering.
    clk_wiz_0 u_clk_wiz (
        .clk_in1_p (USER_SI570_P),
        .clk_in1_n (USER_SI570_N),
        .clk_out1  (clk_100),
        .locked    (mmcm_locked)
    );

    assign rst_n = mmcm_locked & ~CPU_RESET;

    l2_noc_fpga_top u_dut (
        .i_clk            (clk_100),
        .i_rst_n          (rst_n),
        .o_led_done       (GPIO_LED_0),
        .o_led_pass       (GPIO_LED_1),
        .o_mismatch_count (mismatch_count)
    );

    assign GPIO_LED_2 = mismatch_count[0];
    assign GPIO_LED_3 = mismatch_count[1];
    assign GPIO_LED_4 = mismatch_count[2];

endmodule
