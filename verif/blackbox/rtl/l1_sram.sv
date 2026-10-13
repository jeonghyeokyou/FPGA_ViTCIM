`timescale 1ns/1ps
// =============================================================================
//  l1_sram  -  L1 SRAM 512b x 2048 (= 128 KiB) = sram_mimic 128b x 2048 4개
//
//  L1_Cache_Mimic 안의 SRAM 배열 부분만 떼어낸 것 (컨트롤러는 noc_L1_FIFO_intf 쪽).
//  bank k = data bit [128k+127 : 128k].  ceb/web active-low, 읽기 1클럭 지연.
//  sram_mimic 모델은 파일 목록에서 고른다:
//    sim   : verif/noc/fix/sram_mimic.v        (리셋 시 전체 0)
//    synth : verif/fpga/fpga_fix/sram_mimic_fpga.v (BRAM 추론용, 리셋 없음)
//  TB backdoor 경로 : <inst>.Usram_mimic_<k>.mem[addr]
// =============================================================================
module l1_sram #(
    parameter ADDR_DEPTH      = 2048,
    parameter DATA_WIDTH      = 512,
    parameter MEMORY_BITWIDTH = 128,
    localparam ADDR_BW        = $clog2(ADDR_DEPTH)
)(
    input  wire                  i_clk,
    input  wire                  i_rstn,
    input  wire                  i_ceb,
    input  wire                  i_web,
    input  wire [ADDR_BW-1:0]    i_addr,
    input  wire [DATA_WIDTH-1:0] i_din,
    output wire [DATA_WIDTH-1:0] o_dout
);
    generate
        if (DATA_WIDTH != 4*MEMORY_BITWIDTH) begin : g_bad_width
            initial $fatal(1, "l1_sram: DATA_WIDTH must be 4*MEMORY_BITWIDTH");
        end
    endgenerate

    sram_mimic #(.BIT_WIDTH(MEMORY_BITWIDTH), .ADDRESS_ROW(ADDR_DEPTH)) Usram_mimic_0 (
        .i_clk(i_clk), .i_rstn(i_rstn), .i_web(i_web), .i_ceb(i_ceb), .i_addr(i_addr),
        .i_din(i_din[0*MEMORY_BITWIDTH +: MEMORY_BITWIDTH]), .o_dout(o_dout[0*MEMORY_BITWIDTH +: MEMORY_BITWIDTH]));
    sram_mimic #(.BIT_WIDTH(MEMORY_BITWIDTH), .ADDRESS_ROW(ADDR_DEPTH)) Usram_mimic_1 (
        .i_clk(i_clk), .i_rstn(i_rstn), .i_web(i_web), .i_ceb(i_ceb), .i_addr(i_addr),
        .i_din(i_din[1*MEMORY_BITWIDTH +: MEMORY_BITWIDTH]), .o_dout(o_dout[1*MEMORY_BITWIDTH +: MEMORY_BITWIDTH]));
    sram_mimic #(.BIT_WIDTH(MEMORY_BITWIDTH), .ADDRESS_ROW(ADDR_DEPTH)) Usram_mimic_2 (
        .i_clk(i_clk), .i_rstn(i_rstn), .i_web(i_web), .i_ceb(i_ceb), .i_addr(i_addr),
        .i_din(i_din[2*MEMORY_BITWIDTH +: MEMORY_BITWIDTH]), .o_dout(o_dout[2*MEMORY_BITWIDTH +: MEMORY_BITWIDTH]));
    sram_mimic #(.BIT_WIDTH(MEMORY_BITWIDTH), .ADDRESS_ROW(ADDR_DEPTH)) Usram_mimic_3 (
        .i_clk(i_clk), .i_rstn(i_rstn), .i_web(i_web), .i_ceb(i_ceb), .i_addr(i_addr),
        .i_din(i_din[3*MEMORY_BITWIDTH +: MEMORY_BITWIDTH]), .o_dout(o_dout[3*MEMORY_BITWIDTH +: MEMORY_BITWIDTH]));

endmodule
