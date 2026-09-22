`timescale 1ns / 1ps

module cmd_decoder_SRAM_group_write_interface #(
    parameter  ADDR_BIT_TOTAL = 18,                                     // total address bit
    parameter  BANDWIDTH = 256,
    parameter  GROUPS = 4,
    localparam ADDR_BIT_PER_GROUP = $clog2(GROUPS),                     // grp address bit
    localparam ADDR_BIT_IN_GROUP  = ADDR_BIT_TOTAL - ADDR_BIT_PER_GROUP // address bit to SRAM
)(
    /// Global signal
    input  wire        i_clk,
    input  wire        i_rstn,
    /// interface w/ cmd_decoder
    input  wire [ADDR_BIT_TOTAL-1:0] i_sram_write_addr,
    input  wire                      i_sram_write_valid,
    input  wire [BANDWIDTH-1:0]      i_sram_write_data,
    output wire                      o_sram_write_ready,
    output wire                      o_sram_write_response,
    /// interface w/ SRAM_group_merge
    output wire [GROUPS-1:0]            o_write_valid,
    input  wire [GROUPS-1:0]            i_write_ready,
    output wire [ADDR_BIT_IN_GROUP-1:0] o_write_addr[GROUPS-1:0],
    output wire [BANDWIDTH-1:0]         o_write_data[GROUPS-1:0],
    input  wire [GROUPS-1:0]            i_FIFO_write_ready,
    // handshake control signal
    input  wire                     i_control_mode
);
   
wire   w_sram_control_mode;
assign w_sram_control_mode = i_control_mode;

// channel 1 : cmd_decoder ==> sram_group_merge
wire [ADDR_BIT_TOTAL-1:0]         w_sram_write_addr;
wire [BANDWIDTH-1:0]              w_sram_write_data;
wire                              w_sram_write_valid;
wire                              w_sram_write_ready;
wire                              w_sram_write_response; // no coding yet
assign                            w_sram_write_response = 1'b0; // no coding yet
wire [ADDR_BIT_PER_GROUP-1:0]     w_sel_sram_group_store  = w_sram_write_addr[ADDR_BIT_TOTAL-1:ADDR_BIT_IN_GROUP];
wire [ADDR_BIT_IN_GROUP -1:0]     w_sram_write_addr_group = w_sram_write_addr[ADDR_BIT_IN_GROUP-1:0];

assign w_sram_write_addr     = i_sram_write_addr;
assign w_sram_write_valid    = i_sram_write_valid;
assign w_sram_write_data     = i_sram_write_data;
assign o_sram_write_ready    = w_sram_write_ready;
assign o_sram_write_response = w_sram_write_response; // no coding yet

// channel 1 : cmd group muxing logic : cmd_decoder ==> sram_group_merge
wire [ADDR_BIT_IN_GROUP-1:0]        w_write_addr [GROUPS-1:0];
wire [BANDWIDTH-1:0]                w_write_data [GROUPS-1:0];
wire [GROUPS-1:0]                   w_write_valid;
wire [GROUPS-1:0]                   w_FIFO_write_ready;
wire [GROUPS-1:0]                   w_write_ready;

// channel 1 store
genvar sel_grp_idx_store;
generate
    for (sel_grp_idx_store=0; sel_grp_idx_store<GROUPS; sel_grp_idx_store=sel_grp_idx_store+1) begin : SEL_GRP_CH_1_STORE
        wire   sel_grp_store                   = (w_sel_sram_group_store == sel_grp_idx_store);

        assign w_write_addr      [sel_grp_idx_store]  = sel_grp_store ? w_sram_write_addr_group : {ADDR_BIT_IN_GROUP{1'b0}};
        assign w_write_data      [sel_grp_idx_store]  = sel_grp_store ? w_sram_write_data       : {BANDWIDTH{1'b0}};
        assign w_write_valid     [sel_grp_idx_store]  = sel_grp_store & w_sram_write_valid;
    end
endgenerate

assign w_sram_write_ready = (w_sram_write_valid) ? w_FIFO_write_ready[w_sel_sram_group_store] : 1'b0;

assign o_write_valid      = w_write_valid;
assign w_write_ready      = i_write_ready;
assign o_write_addr       = w_write_addr;
assign o_write_data       = w_write_data;
assign w_FIFO_write_ready = i_FIFO_write_ready;

endmodule