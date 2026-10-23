`timescale 1ns / 1ps

module SRAM_group_interface_channel_0 #(
    parameter GROUPS   = 16,
    parameter GROUPS_1 = 4,
    parameter GROUPS_2 = 4,
    parameter BLOCKS = 16,
    localparam BLOCKS_TOTAL = GROUPS*BLOCKS,

    parameter BANDWIDTH_CHANNEL_0 = 64,                                                                                         
    parameter ADDRESS_ROW = 2048,
    parameter DESTINATION_ADDR_BIT_CHANNEL_0 = 20, 

    localparam ADDR_BIT_PER_GROUP   = $clog2(GROUPS),
    localparam ADDR_BIT_PER_GROUP_1 = $clog2(GROUPS_1),
    localparam ADDR_BIT_PER_GROUP_2 = $clog2(GROUPS_2),
    localparam ADDR_BIT_PER_BLOCK   = $clog2(BLOCKS),

    localparam ADDR_BIT_IN_BLOCK = $clog2(ADDRESS_ROW),                                  
    localparam ADDR_BIT_PER_BLOCK_CHANNEL_0 = $clog2(BLOCKS), // same as ADDR_BIT_PER_BLOCK                                  
    localparam ADDR_BIT_TOTAL_CHANNEL_0 = $clog2(ADDRESS_ROW*BLOCKS), 
    localparam ADDR_BIT_TOTAL_CHANNEL_0_GRP = ADDR_BIT_PER_GROUP + ADDR_BIT_TOTAL_CHANNEL_0,    
    localparam ADDR_BIT_IN_GROUP_1  = ADDR_BIT_TOTAL_CHANNEL_0_GRP - ADDR_BIT_PER_GROUP_1
)(
    input  wire        i_clk,
    input  wire        i_rstn,

    ////////////////////// channel 0 //////////////////////
    // read addr
    input  wire [ADDR_BIT_TOTAL_CHANNEL_0_GRP-1:0]        i_sram_read_addr_channel_0,
    input  wire                                           i_sram_read_valid_channel_0,
    output wire                                           o_sram_read_ready_channel_0,
    // read data
    output wire [BANDWIDTH_CHANNEL_0-1:0]                 o_sram_read_data_channel_0,
    output wire                                           o_sram_read_response_channel_0,
    input  wire                                           i_sram_read_data_ready_channel_0,
    // write data & addr
    input  wire [ADDR_BIT_TOTAL_CHANNEL_0_GRP-1:0]        i_sram_write_addr_channel_0,
    input  wire [BANDWIDTH_CHANNEL_0-1:0]                 i_sram_write_data_channel_0,
    input  wire                                           i_sram_write_valid_channel_0,
    output wire                                           o_sram_write_ready_channel_0,
    output wire                                           o_sram_write_response_channel_0,

    /// interface w/ SRAM_group_merge
    output wire [GROUPS-1:0]                         o_read_valid, 
    input  wire [GROUPS-1:0]                         i_read_ready,
    output wire [ADDR_BIT_TOTAL_CHANNEL_0-1:0]       o_read_addr         [GROUPS-1:0], 
    input  wire [BANDWIDTH_CHANNEL_0-1:0]            i_read_data         [GROUPS-1:0], 
    input  wire [GROUPS-1:0]                         i_FIFO_read_ready,
    output wire [GROUPS-1:0]                         o_data_fifo_ready,
    /// interface w/ SRAM_group_merge
    output wire [GROUPS-1:0]                         o_write_valid,
    input  wire [GROUPS-1:0]                         i_write_ready,
    output wire [ADDR_BIT_TOTAL_CHANNEL_0-1:0]       o_write_addr          [GROUPS-1:0],
    output wire [BANDWIDTH_CHANNEL_0-1:0]            o_write_data          [GROUPS-1:0],
    input  wire [GROUPS-1:0]                         i_FIFO_write_ready
);
/// sram read port : cmd_decoder_channel_in <===> cmd_decoder_SRAM_group_interface 1st stage
/// SRAM read port
/// interface w/ cmd_decoder
wire [ADDR_BIT_TOTAL_CHANNEL_0_GRP-1:0]       w_sram_read_addr_stage_1;       
wire                                          w_sram_read_valid_stage_1;      
wire                                          w_sram_read_ready_stage_1;      
wire                                          w_sram_read_data_ready_stage_1;
wire                                          w_sram_read_response_stage_1;  
wire [BANDWIDTH_CHANNEL_0-1:0]                w_sram_read_data_stage_1;       
/// interface w/ SRAM_group_merge
wire [GROUPS_1-1:0]                             w_read_valid_stage_1; 
wire [GROUPS_1-1:0]                             w_read_ready_stage_1;
wire [ADDR_BIT_IN_GROUP_1-1:0]                  w_read_addr_stage_1         [GROUPS_1-1:0];
wire [BANDWIDTH_CHANNEL_0-1:0]                  w_read_data_stage_1         [GROUPS_1-1:0]; 
wire [GROUPS_1-1:0]                             w_FIFO_read_ready_stage_1;
wire [GROUPS_1-1:0]                             w_data_fifo_ready_stage_1;

assign w_sram_read_addr_stage_1       = i_sram_read_addr_channel_0;
assign w_sram_read_valid_stage_1      = i_sram_read_valid_channel_0;
assign o_sram_read_ready_channel_0    = w_sram_read_ready_stage_1;
assign o_sram_read_data_channel_0     = w_sram_read_data_stage_1;
assign o_sram_read_response_channel_0 = w_sram_read_response_stage_1;
assign w_sram_read_data_ready_stage_1 = i_sram_read_data_ready_channel_0;

/// sram write port : cmd_decoder_channel_in <===> cmd_decoder_SRAM_group_interface 1st stage
/// SRAM write port
/// interface w/ cmd_decoder
wire [ADDR_BIT_TOTAL_CHANNEL_0_GRP-1:0]       w_sram_write_addr_stage_1;
wire                                          w_sram_write_valid_stage_1;
wire [BANDWIDTH_CHANNEL_0-1:0]                w_sram_write_data_stage_1;
wire                                          w_sram_write_ready_stage_1;
wire                                          w_sram_write_response_stage_1;
/// interface w/ SRAM_group_merge
wire [GROUPS_1-1:0]                             w_write_valid_stage_1;
wire [GROUPS_1-1:0]                             w_write_ready_stage_1;
wire [ADDR_BIT_IN_GROUP_1-1:0]                  w_write_addr_stage_1          [GROUPS_1-1:0];
wire [BANDWIDTH_CHANNEL_0-1:0]                  w_write_data_stage_1          [GROUPS_1-1:0];
wire [GROUPS_1-1:0]                             w_FIFO_write_ready_stage_1;

assign w_sram_write_addr_stage_1  = i_sram_write_addr_channel_0;
assign w_sram_write_data_stage_1  = i_sram_write_data_channel_0;
assign w_sram_write_valid_stage_1 = i_sram_write_valid_channel_0;

assign o_sram_write_ready_channel_0    = w_sram_write_ready_stage_1;
assign o_sram_write_response_channel_0 = w_sram_write_response_stage_1;

/// cmd_decoder_SRAM_group_interface 1st stage <===> cmd_decoder_SRAM_group_interface 2nd stage
/// interface w/ SRAM_group_merge
wire [GROUPS-1:0]                             w_read_valid_stage_2; 
wire [GROUPS-1:0]                             w_read_ready_stage_2;
wire [ADDR_BIT_TOTAL_CHANNEL_0-1:0]           w_read_addr_stage_2         [GROUPS-1:0];
wire [BANDWIDTH_CHANNEL_0-1:0]                w_read_data_stage_2         [GROUPS-1:0]; 
wire [GROUPS-1:0]                             w_FIFO_read_ready_stage_2;
wire [GROUPS-1:0]                             w_data_fifo_ready_stage_2;
/// interface w/ SRAM_group_merge
wire [GROUPS-1:0]                             w_write_valid_stage_2;
wire [GROUPS-1:0]                             w_write_ready_stage_2;
wire [ADDR_BIT_TOTAL_CHANNEL_0-1:0]           w_write_addr_stage_2          [GROUPS-1:0];
wire [BANDWIDTH_CHANNEL_0-1:0]                w_write_data_stage_2          [GROUPS-1:0];
wire [GROUPS-1:0]                             w_FIFO_write_ready_stage_2;

assign o_read_valid               = w_read_valid_stage_2;
assign w_read_ready_stage_2       = i_read_ready;
assign o_read_addr                = w_read_addr_stage_2;
assign w_read_data_stage_2        = i_read_data;
assign w_FIFO_read_ready_stage_2  = i_FIFO_read_ready;
assign o_data_fifo_ready          = w_data_fifo_ready_stage_2;

assign o_write_valid              = w_write_valid_stage_2;
assign w_write_ready_stage_2      = i_write_ready;
assign o_write_addr               = w_write_addr_stage_2;                 
assign o_write_data               = w_write_data_stage_2;
assign w_FIFO_write_ready_stage_2 = i_FIFO_write_ready; 

// module instance

cmd_decoder_SRAM_group_interface #(
        .ADDR_BIT_TOTAL ( ADDR_BIT_TOTAL_CHANNEL_0_GRP ),
        .BANDWIDTH      ( BANDWIDTH_CHANNEL_0          ),
        .GROUPS         ( GROUPS_1                         ),
        .FIFO_DEPTH     ( 4                                )
) u_cmd_decoder_SRAM_group_interface_stage_1 (
        /// Global signal
        .i_clk                  ( i_clk                  ), 
        .i_rstn                 ( i_rstn                 ),
        /// SRAM read port (cmd_decoder side)
        .i_sram_read_addr       ( w_sram_read_addr_stage_1       ), 
        .i_sram_read_valid      ( w_sram_read_valid_stage_1      ), 
        .o_sram_read_ready      ( w_sram_read_ready_stage_1      ), 
        .i_sram_read_data_ready ( w_sram_read_data_ready_stage_1 ), 
        .o_sram_read_response   ( w_sram_read_response_stage_1   ), 
        .o_sram_read_data       ( w_sram_read_data_stage_1       ), 
        /// SRAM read port (SRAM_group_merge side)
        .o_read_valid           ( w_read_valid_stage_1           ), 
        .i_read_ready           ( w_read_ready_stage_1           ), 
        .o_read_addr            ( w_read_addr_stage_1            ), 
        .i_read_data            ( w_read_data_stage_1            ), 
        .i_FIFO_read_ready      ( w_FIFO_read_ready_stage_1      ),
        .o_data_fifo_ready      ( w_data_fifo_ready_stage_1      ), 
        /// SRAM write port (cmd_decoder side)
        .i_sram_write_addr      ( w_sram_write_addr_stage_1      ), 
        .i_sram_write_valid     ( w_sram_write_valid_stage_1     ), 
        .i_sram_write_data      ( w_sram_write_data_stage_1      ), 
        .o_sram_write_ready     ( w_sram_write_ready_stage_1     ),
        .o_sram_write_response  ( w_sram_write_response_stage_1  ), 
        /// SRAM write port (SRAM_group_merge side)
        .o_write_valid          ( w_write_valid_stage_1          ), 
        .i_write_ready          ( w_write_ready_stage_1          ), 
        .o_write_addr           ( w_write_addr_stage_1           ), 
        .o_write_data           ( w_write_data_stage_1           ), 
        .i_FIFO_write_ready     ( w_FIFO_write_ready_stage_1     ),
        // Handshake control signal
        .i_control_mode         ( '0)  
    );

    genvar b;
    generate
        for (b = 0; b < GROUPS_1; b = b + 1) begin : BLOCK
            cmd_decoder_SRAM_group_interface #(
                    .ADDR_BIT_TOTAL ( ADDR_BIT_IN_GROUP_1     ),
                    .BANDWIDTH      ( BANDWIDTH_CHANNEL_0 ),
                    .GROUPS         ( GROUPS_2                ),
                    .FIFO_DEPTH     ( 4                       )
            ) u_cmd_decoder_SRAM_group_interface_stage_2 (
                    /// Global signal
                    .i_clk                  ( i_clk                  ), 
                    .i_rstn                 ( i_rstn                 ),
                    /// SRAM read port (cmd_decoder side)
                    .i_sram_read_addr       ( w_read_addr_stage_1[b]       ), 
                    .i_sram_read_valid      ( w_read_valid_stage_1[b]      ), 
                    .o_sram_read_ready      ( w_FIFO_read_ready_stage_1[b] ), 
                    .i_sram_read_data_ready ( w_data_fifo_ready_stage_1[b] ), 
                    .o_sram_read_response   ( w_read_ready_stage_1[b]      ), 
                    .o_sram_read_data       ( w_read_data_stage_1[b]       ), 
                    /// SRAM read port (SRAM_group_merge side)
                    .o_read_valid           ( w_read_valid_stage_2[GROUPS_2*(b+1)-1:GROUPS_2*b]           ), // same as [GROUPS_2*b+:GROUPS_2]
                    .i_read_ready           ( w_read_ready_stage_2[GROUPS_2*(b+1)-1:GROUPS_2*b]           ), 
                    .o_read_addr            ( w_read_addr_stage_2[GROUPS_2*(b+1)-1:GROUPS_2*b]            ), 
                    .i_read_data            ( w_read_data_stage_2[GROUPS_2*(b+1)-1:GROUPS_2*b]            ), 
                    .i_FIFO_read_ready      ( w_FIFO_read_ready_stage_2[GROUPS_2*(b+1)-1:GROUPS_2*b]      ),
                    .o_data_fifo_ready      ( w_data_fifo_ready_stage_2[GROUPS_2*(b+1)-1:GROUPS_2*b]      ), 
                    /// SRAM write port (cmd_decoder side)
                    .i_sram_write_addr      ( w_write_addr_stage_1[b]      ), 
                    .i_sram_write_valid     ( w_write_valid_stage_1[b]     ), 
                    .i_sram_write_data      ( w_write_data_stage_1[b]      ), 
                    .o_sram_write_ready     ( w_FIFO_write_ready_stage_1[b]),
                    .o_sram_write_response  ( w_write_ready_stage_1[b]     ), 
                    /// SRAM write port (SRAM_group_merge side)
                    .o_write_valid          ( w_write_valid_stage_2[GROUPS_2*(b+1)-1:GROUPS_2*b]          ), 
                    .i_write_ready          ( w_write_ready_stage_2[GROUPS_2*(b+1)-1:GROUPS_2*b]          ), 
                    .o_write_addr           ( w_write_addr_stage_2[GROUPS_2*(b+1)-1:GROUPS_2*b]           ), 
                    .o_write_data           ( w_write_data_stage_2[GROUPS_2*(b+1)-1:GROUPS_2*b]           ), 
                    .i_FIFO_write_ready     ( w_FIFO_write_ready_stage_2[GROUPS_2*(b+1)-1:GROUPS_2*b]     ),
                    // Handshake control signal
                    .i_control_mode         ( '0)  
                );
        end
    endgenerate

endmodule