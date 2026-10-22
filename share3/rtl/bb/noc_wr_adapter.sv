`timescale 1ns/1ps
// =====================================================================
//  noc_wr_adapter  -  L2 NoC write master (LOAD only) -> FIFO_intf write port
//
//  ch2_in LOAD 와 ch2_wgt LOAD 용. L2 가 NoC 로 쓰기만 하고 읽기는 없다
//  (ch2_in 의 store 쪽은 엔진이 master 라 이 adapter 를 거치지 않는다).
//  쓰기 쪽 연결은 noc_ch1_in_adapter / noc_ch1_wgt_adapter 와 같다:
//    L2 write_ready    <- FIFO_intf o_FIFO_write_ready (FIFO 에 자리 있음)
//    L2 write_response <- FIFO_intf o_write_ready      (handshake 응답)
//  주소는 하위 ADDR_BW 비트만 쓴다:
//    ch2_in  : NoC 15b = {PE/Accum, 14b} -> 하위 11b (input 메모리 2048줄)
//    ch2_wgt : NoC 9b                   -> 9b       (weight 메모리 512줄)
// =====================================================================

module noc_wr_adapter #(
    parameter DA_L2   = 15,     // L2 NoC write address width
    parameter ADDR_BW = 11,     // FIFO_intf local address width
    parameter DW      = 256
)(
    // ---------------- L2 side : TOP_L2_cache NoC write master -----------
    input  wire               l2_noc_write_valid,
    input  wire [DA_L2-1:0]   l2_noc_write_addr,
    input  wire [DW-1:0]      l2_noc_write_data,
    output wire               l2_noc_write_ready,
    output wire               l2_noc_write_response,
    input  wire               l2_noc_control_mode,

    // ---------------- NoC side : FIFO_intf write port -------------------
    output wire                m_write_valid,
    output wire [ADDR_BW-1:0]  m_write_addr,
    output wire [DW-1:0]       m_write_data,
    input  wire                m_write_ready,
    input  wire                m_fifo_write_ready,
    output wire                m_control_mode
);

    assign m_write_valid         = l2_noc_write_valid;
    assign m_write_addr          = l2_noc_write_addr[ADDR_BW-1:0];
    assign m_write_data          = l2_noc_write_data;
    assign l2_noc_write_ready    = m_fifo_write_ready;
    assign l2_noc_write_response = m_write_ready;
    assign m_control_mode        = l2_noc_control_mode;

endmodule
