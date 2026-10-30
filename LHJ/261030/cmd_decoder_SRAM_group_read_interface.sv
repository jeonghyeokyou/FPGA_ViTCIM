`timescale 1ns / 1ps

module cmd_decoder_SRAM_group_read_interface #(
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
    input  wire [ADDR_BIT_TOTAL-1:0]   i_sram_read_addr,       //o_read_addr
    input  wire                        i_sram_read_valid,      //o_read_valid
    output wire                        o_sram_read_ready,      //i_FIFO_read_ready

    input  wire                        i_sram_read_data_ready, //o_data_fifo_ready
    output wire                        o_sram_read_response,   //i_read_ready
    output wire [BANDWIDTH-1:0]        o_sram_read_data,       //i_read_data

    /// interface w/ SRAM_group_merge
    output wire [GROUPS-1:0]              o_read_valid, 
    input  wire [GROUPS-1:0]              i_read_ready,
    output wire [ADDR_BIT_IN_GROUP-1:0]   o_read_addr         [GROUPS-1:0], 
    input  wire [BANDWIDTH-1:0]           i_read_data         [GROUPS-1:0], 
    input  wire [GROUPS-1:0]              i_FIFO_read_ready,
    output wire [GROUPS-1:0]              o_data_fifo_ready,

    // handshake control signal
    input  wire                     i_control_mode
);
   
wire   w_sram_control_mode;
assign w_sram_control_mode = i_control_mode;
// channel 1 : cmd_decoder ==> sram_group_merge
wire [ADDR_BIT_TOTAL-1:0]               w_sram_read_addr;
wire                                    w_sram_read_valid;
wire                                    w_sram_read_ready;
wire [ADDR_BIT_PER_GROUP-1:0]           w_sel_sram_group       = w_sram_read_addr[ADDR_BIT_TOTAL-1:ADDR_BIT_IN_GROUP];
wire [ADDR_BIT_IN_GROUP -1:0]           w_sram_read_addr_group = w_sram_read_addr[ADDR_BIT_IN_GROUP-1:0];

assign w_sram_read_addr  = i_sram_read_addr;
assign w_sram_read_valid = i_sram_read_valid;
assign o_sram_read_ready = w_sram_read_ready;

// channel 1 : cmd group muxing logic : cmd_decoder ==> sram_group_merge
wire [ADDR_BIT_IN_GROUP-1:0]        w_read_addr      [GROUPS-1:0];
wire [GROUPS-1:0]                   w_read_valid                 ;
wire [GROUPS-1:0]                   w_FIFO_read_ready            ;

// channel 1 : sram_group_merge ==> cmd_decoder
wire                                    w_sram_read_data_ready;
wire                                    w_sram_read_response;
wire [BANDWIDTH-1:0]                    w_sram_read_data;

assign o_sram_read_data       = w_sram_read_data;
assign o_sram_read_response   = w_sram_read_response;
assign w_sram_read_data_ready = i_sram_read_data_ready;

// channel 1 : cmd group muxing logic : sram_group_merge ==> cmd_decoder
wire [GROUPS-1:0]                       w_read_ready                  ;
wire [BANDWIDTH-1:0]                    w_read_data       [GROUPS-1:0];
wire [GROUPS-1:0]                       w_data_fifo_ready             ;

wire                                    w_fifo_addr_ready;
wire                                    w_fifo_addr_valid;
wire                                    w_fifo_data_ready;
wire                                    w_fifo_data_valid;
wire [ADDR_BIT_PER_GROUP-1:0]           w_sel_read_data;

genvar sel_grp_idx;
generate
    for (sel_grp_idx=0; sel_grp_idx<GROUPS; sel_grp_idx=sel_grp_idx+1) begin : SEL_GRP
        wire   sel_grp                         = (w_sel_sram_group == sel_grp_idx);
        wire   sel_grp_read_data               = (w_sel_read_data  == sel_grp_idx);
        assign w_read_addr      [sel_grp_idx]  = sel_grp ? w_sram_read_addr_group : {ADDR_BIT_IN_GROUP{1'b0}};
        assign w_read_valid     [sel_grp_idx]  = sel_grp & w_sram_read_valid;
        assign w_data_fifo_ready[sel_grp_idx]  = sel_grp_read_data & w_sram_read_data_ready;
    end
endgenerate

assign w_sram_read_ready = (w_sram_read_valid) ? w_FIFO_read_ready[w_sel_sram_group] : 1'b0;
assign w_fifo_addr_valid =  w_sram_read_valid && w_sram_read_ready;

FIFO #(
    .DATA_WIDTH ( ADDR_BIT_PER_GROUP ),
    .FIFO_DEPTH ( 8 )
) u_FIFO_read_addr (
    .i_clk          ( i_clk ),
    .i_rstn         ( i_rstn ),
    .o_input_ready  ( w_fifo_addr_ready ),
    .i_input_valid  ( w_fifo_addr_valid ),
    .i_input_data   ( w_sel_sram_group  ),
    .i_output_ready ( w_fifo_data_ready ),
    .o_output_valid ( w_fifo_data_valid ),
    .o_output_data  ( w_sel_read_data   )
);

assign w_sram_read_data     = w_read_data [w_sel_read_data];
assign w_sram_read_response = w_read_ready[w_sel_read_data];
assign w_fifo_data_ready    = w_sram_read_response && w_sram_read_data_ready;

assign o_read_valid = w_read_valid;
assign w_read_ready = i_read_ready;
assign o_read_addr  = w_read_addr;
assign w_read_data  = i_read_data;
assign w_FIFO_read_ready = i_FIFO_read_ready;
assign o_data_fifo_ready = w_data_fifo_ready;

endmodule