`timescale 1ns/1ps
// =============================================================================
//  FIFO_intf_bb  -  FIFO_intf 의 Blackbox 버전
//
//    noc_FIFO_interface  ->  noc_L1_FIFO_intf  --(SRAM port, NoC)-->  l1_port_mux  ->  l1_sram
//    (NoC 브리지,              (L1 FIFO + sram ctrl,                     ^ (SRAM port, PE)
//     버그#6 수정본)            i_pe_busy 게이팅)                         | blackbox_pe / MAC IP
//
//  NoC 쪽 포트(이름/폭/동작)는 verif/noc/rename/FIFO_intf.v 와 같다
//  -> noc_ch1_in_adapter 를 그대로 붙일 수 있다.
//  기존 FIFO_intf 의 L1_Cache_Mimic = (noc_sram_controller + sram_mimic x4) 와
//  여기의 (noc_L1_FIFO_intf 안의 noc_sram_controller + l1_sram) 은 같은 구성이다.
//  차이는 i_pe_busy 가 실제로 연결되고, SRAM 포트가 PE 와 공유된다는 것뿐.
//
//  추가 포트 : i_pe_busy, i_pe_ceb, i_pe_web (active-low), i_pe_addr, i_pe_din, o_pe_dout
// =============================================================================
module FIFO_intf_bb #(
    parameter ADDR_DEPTH      = 2048,
    parameter DATA_WIDTH      = 512,
    parameter MEMORY_BITWIDTH = 128,
    parameter FIFO_DEPTH      = 8,
    parameter INPUT_DELAY     = 3,
    localparam ADDR_BW        = $clog2(ADDR_DEPTH)
)(
    input                    clk,
    input                    rstb,
    // ---- NoC side (same as FIFO_intf) ----
    input                    i_read_valid,
    output                   o_read_ready,
    input  [ADDR_BW-1:0]     i_read_addr,
    output [DATA_WIDTH-1:0]  o_read_data,
    input                    i_write_valid,
    output                   o_write_ready,
    input  [ADDR_BW-1:0]     i_write_addr,
    input  [DATA_WIDTH-1:0]  i_write_data,
    input                    i_control_mode,
    output                   o_FIFO_read_ready,
    output                   o_FIFO_write_ready,
    input                    i_data_fifo_ready,
    // ---- PE side ----
    input                    i_pe_busy,
    input                    i_pe_ceb,
    input                    i_pe_web,
    input  [ADDR_BW-1:0]     i_pe_addr,
    input  [DATA_WIDTH-1:0]  i_pe_din,
    output [DATA_WIDTH-1:0]  o_pe_dout
);

    // noc_FIFO_interface slave <-> noc_L1_FIFO_intf
    wire                  w_read_valid_prime,  w_read_ready_prime;
    wire [ADDR_BW-1:0]    w_read_addr_prime;
    wire [DATA_WIDTH-1:0] w_read_data_prime;
    wire                  w_write_valid_prime, w_write_ready_prime;
    wire [ADDR_BW-1:0]    w_write_addr_prime;
    wire [DATA_WIDTH-1:0] w_write_data_prime;
    wire                  w_control_mode_prime;
    wire                  w_FIFO_read_ready_prime, w_FIFO_write_ready_prime, w_data_fifo_ready_prime;

    // SRAM ports
    wire                  noc_ceb, noc_web;
    wire [ADDR_BW-1:0]    noc_addr;
    wire [DATA_WIDTH-1:0] noc_din, noc_dout;
    wire                  sram_ceb, sram_web;
    wire [ADDR_BW-1:0]    sram_addr;
    wire [DATA_WIDTH-1:0] sram_din, sram_dout;
    wire                  pe_conflict;     // debug only (always 0 when the PE honors GUARD)

    noc_FIFO_interface #(
        .ADDR_DEPTH(ADDR_DEPTH), .DATA_WIDTH(DATA_WIDTH), .FIFO_DEPTH(FIFO_DEPTH)
    ) UFIFO_interface (
        .clk(clk), .rstb(rstb),
        .i_read_valid_M(i_read_valid),   .o_read_ready_M(o_read_ready),
        .i_read_addr_M(i_read_addr),     .o_read_data_M(o_read_data),
        .i_write_valid_M(i_write_valid), .o_write_ready_M(o_write_ready),
        .i_write_addr_M(i_write_addr),   .i_write_data_M(i_write_data),
        .o_FIFO_read_ready_M(o_FIFO_read_ready),
        .o_FIFO_write_ready_M(o_FIFO_write_ready),
        .i_data_fifo_ready_M(i_data_fifo_ready),
        .i_control_mode(i_control_mode),
        .o_read_valid_S(w_read_valid_prime),   .i_read_ready_S(w_read_ready_prime),
        .o_read_addr_S(w_read_addr_prime),     .i_read_data_S(w_read_data_prime),
        .o_write_valid_S(w_write_valid_prime), .i_write_ready_S(w_write_ready_prime),
        .o_write_addr_S(w_write_addr_prime),   .o_write_data_S(w_write_data_prime),
        .i_FIFO_read_ready_S(w_FIFO_read_ready_prime),
        .i_FIFO_write_ready_S(w_FIFO_write_ready_prime),
        .o_data_fifo_ready_S(w_data_fifo_ready_prime),
        .o_control_mode(w_control_mode_prime)
    );

    noc_L1_FIFO_intf #(
        .ADDR_DEPTH(ADDR_DEPTH), .DATA_WIDTH(DATA_WIDTH), .MEMORY_BITWIDTH(MEMORY_BITWIDTH),
        .FIFO_DEPTH(FIFO_DEPTH), .INPUT_DELAY(INPUT_DELAY)
    ) UL1_FIFO_intf (
        .clk(clk), .rstb(rstb),
        .i_pe_busy(i_pe_busy),
        .i_read_valid(w_read_valid_prime),   .o_read_ready(w_read_ready_prime),
        .i_read_addr(w_read_addr_prime),     .o_read_data(w_read_data_prime),
        .i_write_valid(w_write_valid_prime), .o_write_ready(w_write_ready_prime),
        .i_write_addr(w_write_addr_prime),   .i_write_data(w_write_data_prime),
        .i_control_mode(w_control_mode_prime),
        .o_FIFO_read_ready(w_FIFO_read_ready_prime),
        .o_FIFO_write_ready(w_FIFO_write_ready_prime),
        .i_data_fifo_ready(w_data_fifo_ready_prime),
        .o_sram_ceb(noc_ceb), .o_sram_web(noc_web), .o_sram_addr(noc_addr),
        .o_sram_din(noc_din), .i_sram_dout(noc_dout)
    );

    l1_port_mux #(.ADDR_BW(ADDR_BW), .DATA_WIDTH(DATA_WIDTH)) u_l1_port_mux (
        .i_pe_busy(i_pe_busy),
        .i_noc_ceb(noc_ceb), .i_noc_web(noc_web), .i_noc_addr(noc_addr), .i_noc_din(noc_din), .o_noc_dout(noc_dout),
        .i_pe_ceb(i_pe_ceb), .i_pe_web(i_pe_web), .i_pe_addr(i_pe_addr), .i_pe_din(i_pe_din), .o_pe_dout(o_pe_dout),
        .o_sram_ceb(sram_ceb), .o_sram_web(sram_web), .o_sram_addr(sram_addr), .o_sram_din(sram_din),
        .i_sram_dout(sram_dout),
        .o_pe_conflict(pe_conflict)
    );

    l1_sram #(
        .ADDR_DEPTH(ADDR_DEPTH), .DATA_WIDTH(DATA_WIDTH), .MEMORY_BITWIDTH(MEMORY_BITWIDTH)
    ) u_l1_sram (
        .i_clk(clk), .i_rstn(rstb),
        .i_ceb(sram_ceb), .i_web(sram_web), .i_addr(sram_addr), .i_din(sram_din), .o_dout(sram_dout)
    );

endmodule
