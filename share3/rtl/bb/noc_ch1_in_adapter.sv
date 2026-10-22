`timescale 1ns/1ps
// =====================================================================
//  noc_ch1_in_adapter  (Phase 2 STEP 2)
//
//  Glue between TOP_L2_cache's channel-1-input NOC master port
//  (L2_260901/cmd_decoder_channel_1_in.sv) and NOC_260902's FIFO_intf
//  master port (rename/FIFO_intf.v -> noc_FIFO_interface -> ... ->
//  L1_Cache_Mimic).
//
//  Direction on the L2 side:
//    ch1_in LOAD  (cmd_idx=1) : L2 internal SRAM -> NOC   -> uses the
//                                write path below (l2_noc_write_*)
//    ch1_in STORE (cmd_idx=2) : NOC -> L2 internal SRAM   -> uses the
//                                read path below (l2_noc_read_*)
//  Only one direction is active at a time, so both can share the one
//  FIFO_intf master port (its own on-fire mux picks read vs write from
//  whichever valid arrives first - see noc_FIFO_interface_on_fire.v).
//
//  What this adapter actually does:
//   1. Renames signals 1:1 (L2 o_noc_* / i_noc_* <-> FIFO_intf *_M)
//      per the mapping in cmd_decoder_SRAM_group_read_interface.sv's
//      port comments (`i_sram_read_addr //o_read_addr` etc.):
//        o_noc_write_valid      -> i_write_valid_M
//        i_noc_write_ready      <- o_FIFO_write_ready_M
//        i_noc_write_response   <- o_write_ready_M
//        o_noc_read_valid       -> i_read_valid_M
//        i_noc_read_ready       <- o_FIFO_read_ready_M
//        i_noc_read_response    <- o_read_ready_M
//        i_noc_read_data        <- o_read_data_M
//        o_noc_read_data_ready  -> i_data_fifo_ready_M
//   2. Drops the multicast field: L2's channel-1-input NOC address is
//      19b = {multicast[7:0], local_addr[10:0]}; FIFO_intf only has an
//      11b local address space (ADDR_DEPTH=2048 -> clog2=11), so only
//      the low ADDR_BW bits are wired through. (Multicast fan-out to
//      several L1 caches is outside what this single FIFO_intf models.)
//   3. Passes control_mode straight through - both sides agree that
//      0 = fire-on-valid (used by burst mode, the case exercised here).
// =====================================================================

module noc_ch1_in_adapter #(
    parameter DA_L2   = 19,     // L2 ch1_in NOC address width (multicast+local)
    parameter ADDR_BW = 11,     // FIFO_intf local address width
    parameter DW      = 512     // data width (channel 1 = 512b on both sides)
)(
    // ---------------- L2 side : TOP_L2_cache ch1_in NOC master port -----
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
    input  wire                m_write_ready,       // FIFO_intf.o_write_ready
    input  wire                m_fifo_write_ready,  // FIFO_intf.o_FIFO_write_ready

    output wire                m_read_valid,
    output wire [ADDR_BW-1:0]  m_read_addr,
    input  wire                m_read_ready,        // FIFO_intf.o_read_ready
    input  wire [DW-1:0]       m_read_data,          // FIFO_intf.o_read_data
    input  wire                m_fifo_read_ready,    // FIFO_intf.o_FIFO_read_ready
    output wire                m_data_fifo_ready,

    output wire                m_control_mode
);

    // ---- write path : ch1_in LOAD (L2 SRAM -> NOC/L1) ----
    assign m_write_valid         = l2_noc_write_valid;
    assign m_write_addr          = l2_noc_write_addr[ADDR_BW-1:0];
    assign m_write_data          = l2_noc_write_data;
    assign l2_noc_write_ready    = m_fifo_write_ready;
    assign l2_noc_write_response = m_write_ready;

    // ---- read path : ch1_in STORE (NOC/L1 -> L2 SRAM) ----
    assign m_read_valid          = l2_noc_read_valid;
    assign m_read_addr           = l2_noc_read_addr[ADDR_BW-1:0];
    assign m_data_fifo_ready     = l2_noc_read_data_ready;
    assign l2_noc_read_ready     = m_fifo_read_ready;
    assign l2_noc_read_response  = m_read_ready;
    assign l2_noc_read_data      = m_read_data;

    // ---- control ----
    assign m_control_mode = l2_noc_control_mode;

endmodule
