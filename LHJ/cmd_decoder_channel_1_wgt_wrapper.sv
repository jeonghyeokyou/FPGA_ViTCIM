`timescale 1ns / 1ps

module cmd_decoder_channel_1_wgt_wrapper #(
    parameter GROUPS   = 16,
    parameter GROUPS_1 = 4,
    parameter GROUPS_2 = 4,
    parameter BLOCKS = 32,
    localparam BLOCKS_TOTAL = GROUPS*BLOCKS,

    parameter BANDWIDTH_CHANNEL_0 = 64,                                                   
    parameter BANDWIDTH_CHANNEL_1_WGT = 256,                                              
    parameter ADDRESS_ROW = 2048,
    parameter DESTINATION_ADDR_BIT_CHANNEL_1_WGT = 18, 

    localparam ADDR_BIT_PER_GROUP   = $clog2(GROUPS),
    localparam ADDR_BIT_PER_GROUP_1 = $clog2(GROUPS_1),
    localparam ADDR_BIT_PER_GROUP_2 = $clog2(GROUPS_2),
    localparam ADDR_BIT_PER_BLOCK   = $clog2(BLOCKS),

    localparam GROUP_CHANNEL_1_WGT = BANDWIDTH_CHANNEL_1_WGT/BANDWIDTH_CHANNEL_0,                 
    localparam BLOCKS_CHANNEL_1_WGT = BLOCKS/GROUP_CHANNEL_1_WGT,                                 
    localparam ADDR_BIT_PER_BLOCK_CHANNEL_1_WGT = $clog2(BLOCKS_CHANNEL_1_WGT),                    
    localparam ADDR_BIT_TOTAL_CHANNEL_1_WGT = $clog2(ADDRESS_ROW*BLOCKS_CHANNEL_1_WGT),   
    localparam ADDR_BIT_TOTAL_CHANNEL_1_WGT_GRP = ADDR_BIT_PER_GROUP + ADDR_BIT_TOTAL_CHANNEL_1_WGT,
    
    localparam ADDR_BIT_IN_GROUP_1  = ADDR_BIT_TOTAL_CHANNEL_1_WGT_GRP - ADDR_BIT_PER_GROUP_1
)(
    input  wire        i_clk,
    input  wire        i_rstn,

    ////////////////////// channel 1_Wgt //////////////////////
    // ========== Interface with command_decoder ==========
    input  wire [63:0] i_ch1_wgt_rw_cmd,       
    input  wire        i_ch1_wgt_rw_cmd_valid, 
    output wire        o_ch1_wgt_rw_cmd_ready,

    // ========== Interface with top_ctrl ==========
    output wire        o_load_busy_channel_1_wgt,
    output wire        o_store_busy_channel_1_wgt,        

    // ========== Interface with FIFO_interface (NOC Write Path) ========== 
    input  wire                                            i_noc_write_ready_channel_1_wgt,  
    output wire                                            o_noc_write_valid_channel_1_wgt,
    output wire [DESTINATION_ADDR_BIT_CHANNEL_1_WGT-1:0]   o_noc_write_addr_channel_1_wgt,
    output wire [BANDWIDTH_CHANNEL_1_WGT-1:0]              o_noc_write_data_channel_1_wgt,
    input  wire                                            i_noc_write_response_channel_1_wgt,

    // ========== Interface with FIFO_interface (NOC Read Path) ========== 
    output wire [DESTINATION_ADDR_BIT_CHANNEL_1_WGT-1:0]   o_noc_read_addr_channel_1_wgt,
    output wire                                            o_noc_read_valid_channel_1_wgt, 
    output wire                                            o_noc_read_data_ready_channel_1_wgt,
    input  wire                                            i_noc_read_ready_channel_1_wgt,     
    input  wire                                            i_noc_read_response_channel_1_wgt,        
    input  wire [BANDWIDTH_CHANNEL_1_WGT-1:0]              i_noc_read_data_channel_1_wgt,

    output wire                                            o_noc_control_mode_channel_1_wgt,
    output wire                                            o_sram_control_mode_channel_1_wgt,

    /// interface w/ SRAM_group_merge
    output wire [GROUPS-1:0]                         o_read_valid, 
    input  wire [GROUPS-1:0]                         i_read_ready,
    output wire [ADDR_BIT_TOTAL_CHANNEL_1_WGT-1:0]   o_read_addr         [GROUPS-1:0], 
    input  wire [BANDWIDTH_CHANNEL_1_WGT-1:0]        i_read_data         [GROUPS-1:0], 
    input  wire [GROUPS-1:0]                         i_FIFO_read_ready,
    output wire [GROUPS-1:0]                         o_data_fifo_ready,
    /// interface w/ SRAM_group_merge
    output wire [GROUPS-1:0]                         o_write_valid,
    input  wire [GROUPS-1:0]                         i_write_ready,
    output wire [ADDR_BIT_TOTAL_CHANNEL_1_WGT-1:0]   o_write_addr          [GROUPS-1:0],
    output wire [BANDWIDTH_CHANNEL_1_WGT-1:0]        o_write_data          [GROUPS-1:0],
    input  wire [GROUPS-1:0]                         i_FIFO_write_ready
);
/// sram read port : cmd_decoder_channel_wgt <===> cmd_decoder_SRAM_group_interface 1st stage
/// SRAM read port
/// interface w/ cmd_decoder
wire [ADDR_BIT_TOTAL_CHANNEL_1_WGT_GRP-1:0]   w_sram_read_addr_stage_1;       
wire                                          w_sram_read_valid_stage_1;      
wire                                          w_sram_read_ready_stage_1;      
wire                                          w_sram_read_data_ready_stage_1;
wire                                          w_sram_read_response_stage_1;  
wire [BANDWIDTH_CHANNEL_1_WGT-1:0]            w_sram_read_data_stage_1;       
/// interface w/ SRAM_group_merge
wire [GROUPS_1-1:0]                             w_read_valid_stage_1; 
wire [GROUPS_1-1:0]                             w_read_ready_stage_1;
wire [ADDR_BIT_IN_GROUP_1-1:0]                  w_read_addr_stage_1         [GROUPS_1-1:0];
wire [BANDWIDTH_CHANNEL_1_WGT-1:0]              w_read_data_stage_1         [GROUPS_1-1:0]; 
wire [GROUPS_1-1:0]                             w_FIFO_read_ready_stage_1;
wire [GROUPS_1-1:0]                             w_data_fifo_ready_stage_1;

/// sram write port : cmd_decoder_channel_wgt <===> cmd_decoder_SRAM_group_interface 1st stage
/// SRAM write port
/// interface w/ cmd_decoder
wire [ADDR_BIT_TOTAL_CHANNEL_1_WGT_GRP-1:0]   w_sram_write_addr_stage_1;
wire                                          w_sram_write_valid_stage_1;
wire [BANDWIDTH_CHANNEL_1_WGT-1:0]            w_sram_write_data_stage_1;
wire                                          w_sram_write_ready_stage_1;
wire                                          w_sram_write_response_stage_1;
/// interface w/ SRAM_group_merge
wire [GROUPS_1-1:0]                             w_write_valid_stage_1;
wire [GROUPS_1-1:0]                             w_write_ready_stage_1;
wire [ADDR_BIT_IN_GROUP_1-1:0]                  w_write_addr_stage_1          [GROUPS_1-1:0];
wire [BANDWIDTH_CHANNEL_1_WGT-1:0]              w_write_data_stage_1          [GROUPS_1-1:0];
wire [GROUPS_1-1:0]                             w_FIFO_write_ready_stage_1;

/// cmd_decoder_SRAM_group_interface 1st stage <===> cmd_decoder_SRAM_group_interface 2nd stage
/// interface w/ SRAM_group_merge
wire [GROUPS-1:0]                             w_read_valid_stage_2; 
wire [GROUPS-1:0]                             w_read_ready_stage_2;
wire [ADDR_BIT_TOTAL_CHANNEL_1_WGT-1:0]       w_read_addr_stage_2         [GROUPS-1:0];
wire [BANDWIDTH_CHANNEL_1_WGT-1:0]            w_read_data_stage_2         [GROUPS-1:0]; 
wire [GROUPS-1:0]                             w_FIFO_read_ready_stage_2;
wire [GROUPS-1:0]                             w_data_fifo_ready_stage_2;
/// interface w/ SRAM_group_merge
wire [GROUPS-1:0]                             w_write_valid_stage_2;
wire [GROUPS-1:0]                             w_write_ready_stage_2;
wire [ADDR_BIT_TOTAL_CHANNEL_1_WGT-1:0]       w_write_addr_stage_2          [GROUPS-1:0];
wire [BANDWIDTH_CHANNEL_1_WGT-1:0]            w_write_data_stage_2          [GROUPS-1:0];
wire [GROUPS-1:0]                             w_FIFO_write_ready_stage_2;

wire                                          w_sram_control_mode_channel_1_wgt;
wire                                          w_noc_control_mode_channel_1_wgt;

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
assign w_FIFO_write_ready_stage_2 = i_FIFO_write_ready; //gpt한테 문법 검토 맡기기

assign o_noc_control_mode_channel_1_wgt  = w_noc_control_mode_channel_1_wgt;
assign o_sram_control_mode_channel_1_wgt = w_sram_control_mode_channel_1_wgt;

// module instance
// module instance : channel 1 weight load/store command module
cmd_decoder_channel_1_wgt #(
    .SOURCE_ADDR_BIT        ( ADDR_BIT_TOTAL_CHANNEL_1_WGT_GRP ),
    .DESTINATION_ADDR_BIT   ( DESTINATION_ADDR_BIT_CHANNEL_1_WGT ),
    .BANDWIDTH_CHANNEL_1    ( BANDWIDTH_CHANNEL_1_WGT)
) u_cmd_decoder_channel_1_wgt (
    .i_clk                  ( i_clk ),
    .i_rstn                 ( i_rstn ),

    .i_ch1_rw_cmd           ( i_ch1_wgt_rw_cmd),
    .i_ch1_rw_cmd_valid     ( i_ch1_wgt_rw_cmd_valid),
    .o_ch1_rw_cmd_ready     ( o_ch1_wgt_rw_cmd_ready),

    .o_load_busy            ( o_load_busy_channel_1_wgt ),
    .o_store_busy           ( o_store_busy_channel_1_wgt),

    .o_sram_read_addr       ( w_sram_read_addr_stage_1 ),
    .o_sram_read_valid      ( w_sram_read_valid_stage_1),
    .o_sram_read_data_ready ( w_sram_read_data_ready_stage_1 ),
    .i_sram_read_ready      ( w_sram_read_ready_stage_1 ),
    .i_sram_read_response   ( w_sram_read_response_stage_1 ),
    .i_sram_read_data       ( w_sram_read_data_stage_1 ),

    .i_noc_write_ready      ( i_noc_write_ready_channel_1_wgt ),
    .o_noc_write_valid      ( o_noc_write_valid_channel_1_wgt ),
    .o_noc_write_addr       ( o_noc_write_addr_channel_1_wgt ),
    .o_noc_write_data       ( o_noc_write_data_channel_1_wgt),
    .i_noc_write_response   ( i_noc_write_response_channel_1_wgt),

    .o_sram_write_addr      ( w_sram_write_addr_stage_1 ),
    .o_sram_write_valid     ( w_sram_write_valid_stage_1 ),
    .o_sram_write_data      ( w_sram_write_data_stage_1 ),
    .i_sram_write_ready     ( w_sram_write_ready_stage_1 ),
    .i_sram_write_response  ( w_sram_write_response_stage_1 ),

    .o_noc_read_addr        ( o_noc_read_addr_channel_1_wgt ),
    .o_noc_read_valid       ( o_noc_read_valid_channel_1_wgt ), 
    .o_noc_read_data_ready  ( o_noc_read_data_ready_channel_1_wgt ),
    .i_noc_read_ready       ( i_noc_read_ready_channel_1_wgt ),     
    .i_noc_read_response    ( i_noc_read_response_channel_1_wgt ),        
    .i_noc_read_data        ( i_noc_read_data_channel_1_wgt ),
    
    .o_sram_control_mode    ( w_sram_control_mode_channel_1_wgt ),
    .o_noc_control_mode     ( w_noc_control_mode_channel_1_wgt)
);

cmd_decoder_SRAM_group_interface #(
        .ADDR_BIT_TOTAL ( ADDR_BIT_TOTAL_CHANNEL_1_WGT_GRP ),
        .BANDWIDTH      ( BANDWIDTH_CHANNEL_1_WGT          ),
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
        .i_control_mode         ( w_sram_control_mode_channel_1_wgt)  
    );

    genvar b;
    generate
        for (b = 0; b < GROUPS_1; b = b + 1) begin : BLOCK
            cmd_decoder_SRAM_group_interface #(
                    .ADDR_BIT_TOTAL ( ADDR_BIT_IN_GROUP_1     ),
                    .BANDWIDTH      ( BANDWIDTH_CHANNEL_1_WGT ),
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
                    .i_control_mode         ( w_sram_control_mode_channel_1_wgt )  
                );
        end
    endgenerate

endmodule


