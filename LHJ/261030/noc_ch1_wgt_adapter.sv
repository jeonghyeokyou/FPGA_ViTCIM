`timescale 1ns/1ps
// =====================================================================
//  noc_ch1_wgt_adapter  (ch1_wgt integration, same pattern as STEP 2's
//  noc_ch1_in_adapter.sv — ch1_wgt has the identical port SHAPE as
//  ch1_in in TOP_L2_cache: L2 is always master on both write and read,
//  see cmd_decoder_channel_1_wgt.sv. Only the widths differ:
//    ch1_in  : NOC addr 19b = {multicast[7:0], local[10:0]}, data 512b
//    ch1_wgt : NOC addr 18b = {multicast[7:0], local[9:0]},  data 256b
//  (o_noc_write_addr = {r_multicast, r_destination_start_addr[9:0]},
//   o_noc_read_addr  = {w_multicast_store, r_source_start_addr_store[9:0]})
//
//  Real-world target: ch1_in talks to the CIM Cluster's L1 cache,
//  ch1_wgt talks to the CIM Cluster Array's weight memory - a different
//  physical block, but NOC_260902 only models "a cache behind FIFO_intf",
//  so the same FIFO_intf instance (re-parameterized: DATA_WIDTH=256,
//  ADDR_DEPTH=1024 -> 10b) stands in for it here, same as ch1_in.
// =====================================================================

module noc_ch1_wgt_adapter #(
    parameter DA_L2   = 18,     // L2 ch1_wgt NOC address width (multicast+local)
    parameter ADDR_BW = 10,     // FIFO_intf local address width
    parameter DW      = 256     // data width (channel 1 wgt = 256b)
)(
    // ---------------- L2 side : TOP_L2_cache ch1_wgt NOC master port -----
    input  wire               l2_noc_write_valid,
    input  wire [DA_L2-1:0]   l2_noc_write_addr,
    input  wire [DW-1:0]      l2_noc_write_data,
    output wire               l2_noc_write_ready,
    output wire               l2_noc_write_response,

    input  wire               l2_noc_read_valid,
    input  wire [DA_L2-1:0]   l2_noc_read_addr,
    input  wire               l2_noc_read_data_ready,
    output wire               l2_noc_read_ready,
    output wire               l2_noc_read_response,
    output wire [DW-1:0]      l2_noc_read_data,

    input  wire               l2_noc_control_mode,

    // ---------------- NOC side : FIFO_intf master port ------------------
    output wire                m_write_valid,
    output wire [ADDR_BW-1:0]  m_write_addr,
    output wire [DW-1:0]       m_write_data,
    input  wire                m_write_ready,
    input  wire                m_fifo_write_ready,

    output wire                m_read_valid,
    output wire [ADDR_BW-1:0]  m_read_addr,
    input  wire                m_read_ready,
    input  wire [DW-1:0]       m_read_data,
    input  wire                m_fifo_read_ready,
    output wire                m_data_fifo_ready,

    output wire                m_control_mode
);

    assign m_write_valid         = l2_noc_write_valid;
    assign m_write_addr          = l2_noc_write_addr[ADDR_BW-1:0];
    assign m_write_data          = l2_noc_write_data;
    assign l2_noc_write_ready    = m_fifo_write_ready;
    assign l2_noc_write_response = m_write_ready;

    assign m_read_valid          = l2_noc_read_valid;
    assign m_read_addr           = l2_noc_read_addr[ADDR_BW-1:0];
    assign m_data_fifo_ready     = l2_noc_read_data_ready;
    assign l2_noc_read_ready     = m_fifo_read_ready;
    assign l2_noc_read_response  = m_read_ready;
    assign l2_noc_read_data      = m_read_data;

    assign m_control_mode = l2_noc_control_mode;

endmodule
