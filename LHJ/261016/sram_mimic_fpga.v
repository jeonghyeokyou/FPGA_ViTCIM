`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
//  sram_mimic  -  SYNTHESIS copy (original: rtl/NOC_260902/sram_mimic.v)
//
//  Same functional fix as verif/noc/fix/sram_mimic.v (o_dout input->output),
//  PLUS two changes needed to make this an actual FPGA memory instead of a
//  simulation-only model:
//
//  1. Removed the `for (i=0;i<ADDRESS_ROW;i=i+1) mem[i]<=0` full-array reset.
//     A reset that touches every row is not a template Vivado's memory
//     inferencer recognizes as BRAM/URAM - it would synthesize as one flip-
//     flop per bit (for a 512b x 2048 instance that is ~1 Mb of FFs, likely
//     either failing synthesis or eating the whole device). Real BRAM/URAM
//     primitives don't have a full-array reset pin at all; the standard
//     Xilinx-recommended single-port RAM template only resets the *output*
//     register, if anything.
//  2. Added an `initial` preload of ADDR 0..4 with a known pattern
//     (0xDEAD_BEE0 + k). Vivado turns an `initial` on inferred-BRAM/URAM
//     content into the primitive's INIT_xx strings, so on FPGA configuration
//     the memory powers up already containing this pattern - this is what
//     lets the BIST sequencer in l2_noc_fpga_top.sv run a real store/load
//     round trip without any host-side write path (JTAG-AXI, VIO, ...).
//     Mirrors the exact backdoor-preload technique used in the simulation
//     testbenches (tb_l2_noc_ch1_in.sv / tb_l2_noc_ch1_wgt.sv), except here
//     it becomes real, synthesized initial memory content instead of a
//     hierarchical `force` only usable in a simulator.
//
//  Same module name (sram_mimic); swap in for verif/noc/fix/sram_mimic.v in
//  the synthesis fileset only - simulation keeps using the sim copy so nAB
//  regressions already run against it are unaffected.
// -----------------------------------------------------------------------------

module sram_mimic#(
    parameter  BIT_WIDTH   = 128,
    parameter  ADDRESS_ROW = 2048,
    localparam ADDR_BIT =$clog2(ADDRESS_ROW)
)(
    input wire                       i_clk,
    input wire                       i_rstn,   // kept for port compatibility; unused on purpose (see note 1)
    input wire                       i_web,
    input wire                       i_ceb,
    input wire   [ADDR_BIT -1 : 0]   i_addr,
    input wire   [BIT_WIDTH-1 : 0 ]  i_din,
    output wire  [BIT_WIDTH-1 : 0 ]  o_dout
);
    localparam [31:0] BIST_PATTERN_BASE = 32'hDEAD_BEE0;

    reg [BIT_WIDTH -1 : 0] mem [ADDRESS_ROW-1 : 0];
    reg [BIT_WIDTH-1 : 0] r_dout;
    integer p;

    assign o_dout = r_dout;

    initial begin
        for (p = 0; p < ADDRESS_ROW; p = p + 1)
            mem[p] = {BIT_WIDTH{1'b0}};
        if (ADDRESS_ROW > 4) begin
            mem[0] = {{(BIT_WIDTH-32){1'b0}}, BIST_PATTERN_BASE + 32'd0};
            mem[1] = {{(BIT_WIDTH-32){1'b0}}, BIST_PATTERN_BASE + 32'd1};
            mem[2] = {{(BIT_WIDTH-32){1'b0}}, BIST_PATTERN_BASE + 32'd2};
            mem[3] = {{(BIT_WIDTH-32){1'b0}}, BIST_PATTERN_BASE + 32'd3};
            mem[4] = {{(BIT_WIDTH-32){1'b0}}, BIST_PATTERN_BASE + 32'd4};
        end
    end

    // Write Operation (no reset - see note 1)
    always @(posedge i_clk) begin
        if (i_ceb == 1'b0 && i_web == 1'b0) begin
            mem[i_addr] <= i_din;
        end
    end
    // Read Operation (registered output, no reset - standard BRAM/URAM template)
    always @(posedge i_clk) begin
        if (i_ceb == 1'b0 && i_web == 1'b1) begin
            r_dout <= mem[i_addr];
        end
    end

endmodule
