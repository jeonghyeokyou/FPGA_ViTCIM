`timescale 1ns / 1ps

module SRAM_group_merge #(
    parameter GROUPS = 16,
    parameter BLOCKS = 32,
    
    parameter BANDWIDTH_CHANNEL_0 = 64,                                                   
    parameter BANDWIDTH_CHANNEL_1_IN = 512,                                                  
    parameter BANDWIDTH_CHANNEL_2_IN = 256,   
    parameter BANDWIDTH_CHANNEL_1_WGT= 256,                                                  
    parameter BANDWIDTH_CHANNEL_2_WGT= 256,   

    parameter ADDRESS_ROW = 2048,

    localparam ADDR_BIT_IN_BLOCK = $clog2(ADDRESS_ROW),                                  
    localparam ADDR_BIT_PER_BLOCK = $clog2(BLOCKS),                                      
    localparam ADDR_BIT_TOTAL = $clog2(ADDRESS_ROW*BLOCKS), 

    localparam GROUP_CHANNEL_1_IN              = BANDWIDTH_CHANNEL_1_IN/BANDWIDTH_CHANNEL_0,                 
    localparam BLOCKS_CHANNEL_1_IN             = BLOCKS/GROUP_CHANNEL_1_IN,                                 
    localparam ADDR_BIT_PER_BLOCK_CHANNEL_1_IN = $clog2(BLOCKS_CHANNEL_1_IN),                    
    localparam ADDR_BIT_TOTAL_CHANNEL_1_IN     = $clog2(ADDRESS_ROW*BLOCKS_CHANNEL_1_IN),   

    localparam GROUP_CHANNEL_2_IN              = BANDWIDTH_CHANNEL_2_IN/BANDWIDTH_CHANNEL_0,                 
    localparam BLOCKS_CHANNEL_2_IN             = BLOCKS/GROUP_CHANNEL_2_IN,                                  
    localparam ADDR_BIT_PER_BLOCK_CHANNEL_2_IN = $clog2(BLOCKS_CHANNEL_2_IN),                   
    localparam ADDR_BIT_TOTAL_CHANNEL_2_IN     = $clog2(ADDRESS_ROW*BLOCKS_CHANNEL_2_IN),

    localparam GROUP_CHANNEL_1_WGT              = BANDWIDTH_CHANNEL_1_WGT/BANDWIDTH_CHANNEL_0,                 
    localparam BLOCKS_CHANNEL_1_WGT             = BLOCKS/GROUP_CHANNEL_1_WGT,                                 
    localparam ADDR_BIT_PER_BLOCK_CHANNEL_1_WGT = $clog2(BLOCKS_CHANNEL_1_WGT),                    
    localparam ADDR_BIT_TOTAL_CHANNEL_1_WGT     = $clog2(ADDRESS_ROW*BLOCKS_CHANNEL_1_WGT),   

    localparam GROUP_CHANNEL_2_WGT              = BANDWIDTH_CHANNEL_2_WGT/BANDWIDTH_CHANNEL_0,                 
    localparam BLOCKS_CHANNEL_2_WGT             = BLOCKS/GROUP_CHANNEL_2_WGT,                                  
    localparam ADDR_BIT_PER_BLOCK_CHANNEL_2_WGT = $clog2(BLOCKS_CHANNEL_2_WGT),                   
    localparam ADDR_BIT_TOTAL_CHANNEL_2_WGT     = $clog2(ADDRESS_ROW*BLOCKS_CHANNEL_2_WGT)  
)(
    // global clock, reset
    input i_clk,
    input i_rstn,
    //============================================================
    // Top controller (include Address generator) interface
    //============================================================
    ///////////////////////// channel 0 //////////////////////////
    // Read port
    input  wire  [GROUPS-1:0]                    i_read_valid_channel_0,
    output wire  [GROUPS-1:0]                    o_read_ready_channel_0,
    input  wire  [ADDR_BIT_TOTAL-1:0]            i_read_addr_channel_0          [GROUPS-1:0],
    output wire  [BANDWIDTH_CHANNEL_0-1:0]       o_read_data_channel_0          [GROUPS-1:0],
    // Write port
    input  wire  [GROUPS-1:0]                    i_write_valid_channel_0,
    output wire  [GROUPS-1:0]                    o_write_ready_channel_0,
    input  wire  [ADDR_BIT_TOTAL-1:0]            i_write_addr_channel_0         [GROUPS-1:0],
    input  wire  [BANDWIDTH_CHANNEL_0-1:0]       i_write_data_channel_0         [GROUPS-1:0],
    // Control signal
    input  wire                                  i_control_mode_channel_0,
    output wire  [GROUPS-1:0]                    o_FIFO_read_ready_channel_0,
    output wire  [GROUPS-1:0]                    o_FIFO_write_ready_channel_0,
    input  wire  [GROUPS-1:0]                    i_data_fifo_ready_channel_0,
    ///////////////////////// channel 1_in //////////////////////////
    // Read port
    input  wire  [GROUPS-1:0]                       i_read_valid_channel_1_in,
    output wire  [GROUPS-1:0]                       o_read_ready_channel_1_in,
    input  wire  [ADDR_BIT_TOTAL_CHANNEL_1_IN-1:0]  i_read_addr_channel_1_in          [GROUPS-1:0],
    output wire  [BANDWIDTH_CHANNEL_1_IN-1:0]       o_read_data_channel_1_in          [GROUPS-1:0],
    // Write port
    input  wire  [GROUPS-1:0]                       i_write_valid_channel_1_in,
    output wire  [GROUPS-1:0]                       o_write_ready_channel_1_in,
    input  wire  [ADDR_BIT_TOTAL_CHANNEL_1_IN-1:0]  i_write_addr_channel_1_in         [GROUPS-1:0],
    input  wire  [BANDWIDTH_CHANNEL_1_IN-1:0]       i_write_data_channel_1_in         [GROUPS-1:0],
    // Control signal
    input  wire                                     i_control_mode_channel_1_in,
    output wire  [GROUPS-1:0]                       o_FIFO_read_ready_channel_1_in,
    output wire  [GROUPS-1:0]                       o_FIFO_write_ready_channel_1_in,
    input  wire  [GROUPS-1:0]                       i_data_fifo_ready_channel_1_in,
    ///////////////////////// channel 2_in //////////////////////////
    // Read port
    input  wire  [GROUPS-1:0]                       i_read_valid_channel_2_in,
    output wire  [GROUPS-1:0]                       o_read_ready_channel_2_in,
    input  wire  [ADDR_BIT_TOTAL_CHANNEL_2_IN-1:0]  i_read_addr_channel_2_in          [GROUPS-1:0],
    output wire  [BANDWIDTH_CHANNEL_2_IN-1:0]       o_read_data_channel_2_in          [GROUPS-1:0],
    // Write port
    input  wire  [GROUPS-1:0]                       i_write_valid_channel_2_in,
    output wire  [GROUPS-1:0]                       o_write_ready_channel_2_in,
    input  wire  [ADDR_BIT_TOTAL_CHANNEL_2_IN-1:0]  i_write_addr_channel_2_in         [GROUPS-1:0],
    input  wire  [BANDWIDTH_CHANNEL_2_IN-1:0]       i_write_data_channel_2_in         [GROUPS-1:0],
    // Control signal
    input  wire                                     i_control_mode_channel_2_in,
    output wire  [GROUPS-1:0]                       o_FIFO_read_ready_channel_2_in,
    output wire  [GROUPS-1:0]                       o_FIFO_write_ready_channel_2_in,
    input  wire  [GROUPS-1:0]                       i_data_fifo_ready_channel_2_in,
    ///////////////////////// channel 1_wgt //////////////////////////
    // Read port
    input  wire  [GROUPS-1:0]                        i_read_valid_channel_1_wgt,
    output wire  [GROUPS-1:0]                        o_read_ready_channel_1_wgt,
    input  wire  [ADDR_BIT_TOTAL_CHANNEL_1_WGT-1:0]  i_read_addr_channel_1_wgt          [GROUPS-1:0],
    output wire  [BANDWIDTH_CHANNEL_1_WGT-1:0]       o_read_data_channel_1_wgt          [GROUPS-1:0],
    // Write port
    input  wire  [GROUPS-1:0]                        i_write_valid_channel_1_wgt,
    output wire  [GROUPS-1:0]                        o_write_ready_channel_1_wgt,
    input  wire  [ADDR_BIT_TOTAL_CHANNEL_1_WGT-1:0]  i_write_addr_channel_1_wgt         [GROUPS-1:0],
    input  wire  [BANDWIDTH_CHANNEL_1_WGT-1:0]       i_write_data_channel_1_wgt         [GROUPS-1:0],
    // Control signal
    input  wire                                      i_control_mode_channel_1_wgt,
    output wire  [GROUPS-1:0]                        o_FIFO_read_ready_channel_1_wgt,
    output wire  [GROUPS-1:0]                        o_FIFO_write_ready_channel_1_wgt,
    input  wire  [GROUPS-1:0]                        i_data_fifo_ready_channel_1_wgt,
    ///////////////////////// channel 2_wgt //////////////////////////
    // Read port
    input  wire  [GROUPS-1:0]                        i_read_valid_channel_2_wgt,
    output wire  [GROUPS-1:0]                        o_read_ready_channel_2_wgt,
    input  wire  [ADDR_BIT_TOTAL_CHANNEL_2_WGT-1:0]  i_read_addr_channel_2_wgt          [GROUPS-1:0],
    output wire  [BANDWIDTH_CHANNEL_2_WGT-1:0]       o_read_data_channel_2_wgt          [GROUPS-1:0],
    // Write port
    input  wire  [GROUPS-1:0]                        i_write_valid_channel_2_wgt,
    output wire  [GROUPS-1:0]                        o_write_ready_channel_2_wgt,
    input  wire  [ADDR_BIT_TOTAL_CHANNEL_2_WGT-1:0]  i_write_addr_channel_2_wgt         [GROUPS-1:0],
    input  wire  [BANDWIDTH_CHANNEL_2_WGT-1:0]       i_write_data_channel_2_wgt         [GROUPS-1:0],
    // Control signal
    input  wire                                      i_control_mode_channel_2_wgt,
    output wire  [GROUPS-1:0]                        o_FIFO_read_ready_channel_2_wgt,
    output wire  [GROUPS-1:0]                        o_FIFO_write_ready_channel_2_wgt,
    input  wire  [GROUPS-1:0]                        i_data_fifo_ready_channel_2_wgt
);
    
    genvar sram_grp;
    generate
        for (sram_grp = 0; sram_grp < GROUPS; sram_grp = sram_grp + 1) begin : SRAM_GRP
            L2_FIFO_interface_wrapper #(
                 .BLOCKS               ( BLOCKS ),
                 .BANDWIDTH_CHANNEL_0  ( BANDWIDTH_CHANNEL_0 ),
                 .BANDWIDTH_CHANNEL_1_IN  ( BANDWIDTH_CHANNEL_1_IN ),
                 .BANDWIDTH_CHANNEL_2_IN  ( BANDWIDTH_CHANNEL_2_IN ),
                 .BANDWIDTH_CHANNEL_1_WGT ( BANDWIDTH_CHANNEL_1_WGT),
                 .BANDWIDTH_CHANNEL_2_WGT ( BANDWIDTH_CHANNEL_2_WGT),
                 .ADDRESS_ROW          ( ADDRESS_ROW ),
                 .FIFO_DEPTH           ( 16 ),
                 .INPUT_DELAY          ( 5 )
            ) u_L2_FIFO_interface_wrapper ( 
                .i_clk                         ( i_clk ),
                .i_rstn                        ( i_rstn ),
                // Channel 0
                .i_read_valid_channel_0        ( i_read_valid_channel_0[sram_grp] ),
                .o_read_ready_channel_0        ( o_read_ready_channel_0[sram_grp] ),
                .i_read_addr_channel_0         ( i_read_addr_channel_0[sram_grp] ),
                .o_read_data_channel_0         ( o_read_data_channel_0[sram_grp] ),
                .i_write_valid_channel_0       ( i_write_valid_channel_0[sram_grp] ),
                .o_write_ready_channel_0       ( o_write_ready_channel_0[sram_grp] ),
                .i_write_addr_channel_0        ( i_write_addr_channel_0[sram_grp] ),
                .i_write_data_channel_0        ( i_write_data_channel_0[sram_grp] ),
                .i_control_mode_channel_0      ( i_control_mode_channel_0 ),
                .o_FIFO_read_ready_channel_0   ( o_FIFO_read_ready_channel_0[sram_grp] ),
                .o_FIFO_write_ready_channel_0  ( o_FIFO_write_ready_channel_0[sram_grp] ),
                .i_data_fifo_ready_channel_0   ( i_data_fifo_ready_channel_0[sram_grp] ),
                // Channel 1_IN
                .i_read_valid_channel_1_in        ( i_read_valid_channel_1_in[sram_grp] ),
                .o_read_ready_channel_1_in        ( o_read_ready_channel_1_in[sram_grp] ),
                .i_read_addr_channel_1_in         ( i_read_addr_channel_1_in[sram_grp] ),
                .o_read_data_channel_1_in         ( o_read_data_channel_1_in[sram_grp] ),
                .i_write_valid_channel_1_in       ( i_write_valid_channel_1_in[sram_grp] ),
                .o_write_ready_channel_1_in       ( o_write_ready_channel_1_in[sram_grp] ),
                .i_write_addr_channel_1_in        ( i_write_addr_channel_1_in[sram_grp] ),
                .i_write_data_channel_1_in        ( i_write_data_channel_1_in[sram_grp] ),
                .i_control_mode_channel_1_in      ( i_control_mode_channel_1_in ),
                .o_FIFO_read_ready_channel_1_in   ( o_FIFO_read_ready_channel_1_in[sram_grp] ),
                .o_FIFO_write_ready_channel_1_in  ( o_FIFO_write_ready_channel_1_in[sram_grp] ),
                .i_data_fifo_ready_channel_1_in   ( i_data_fifo_ready_channel_1_in[sram_grp] ),
                // Channel 2_IN
                .i_read_valid_channel_2_in        ( i_read_valid_channel_2_in[sram_grp] ),
                .o_read_ready_channel_2_in        ( o_read_ready_channel_2_in[sram_grp] ),
                .i_read_addr_channel_2_in         ( i_read_addr_channel_2_in[sram_grp] ),
                .o_read_data_channel_2_in         ( o_read_data_channel_2_in[sram_grp] ),
                .i_write_valid_channel_2_in       ( i_write_valid_channel_2_in[sram_grp] ),
                .o_write_ready_channel_2_in       ( o_write_ready_channel_2_in[sram_grp] ),
                .i_write_addr_channel_2_in        ( i_write_addr_channel_2_in[sram_grp] ),
                .i_write_data_channel_2_in        ( i_write_data_channel_2_in[sram_grp] ),
                .i_control_mode_channel_2_in      ( i_control_mode_channel_2_in ),
                .o_FIFO_read_ready_channel_2_in   ( o_FIFO_read_ready_channel_2_in[sram_grp] ),
                .o_FIFO_write_ready_channel_2_in  ( o_FIFO_write_ready_channel_2_in[sram_grp] ),
                .i_data_fifo_ready_channel_2_in   ( i_data_fifo_ready_channel_2_in[sram_grp] ),
                // Channel 1_WGT
                .i_read_valid_channel_1_wgt        ( i_read_valid_channel_1_wgt[sram_grp] ),
                .o_read_ready_channel_1_wgt        ( o_read_ready_channel_1_wgt[sram_grp] ),
                .i_read_addr_channel_1_wgt         ( i_read_addr_channel_1_wgt[sram_grp] ),
                .o_read_data_channel_1_wgt         ( o_read_data_channel_1_wgt[sram_grp] ),
                .i_write_valid_channel_1_wgt       ( i_write_valid_channel_1_wgt[sram_grp] ),
                .o_write_ready_channel_1_wgt       ( o_write_ready_channel_1_wgt[sram_grp] ),
                .i_write_addr_channel_1_wgt        ( i_write_addr_channel_1_wgt[sram_grp] ),
                .i_write_data_channel_1_wgt        ( i_write_data_channel_1_wgt[sram_grp] ),
                .i_control_mode_channel_1_wgt      ( i_control_mode_channel_1_wgt ),
                .o_FIFO_read_ready_channel_1_wgt   ( o_FIFO_read_ready_channel_1_wgt[sram_grp] ),
                .o_FIFO_write_ready_channel_1_wgt  ( o_FIFO_write_ready_channel_1_wgt[sram_grp] ),
                .i_data_fifo_ready_channel_1_wgt   ( i_data_fifo_ready_channel_1_wgt[sram_grp] ),
                // Channel 2_WGT
                .i_read_valid_channel_2_wgt        ( i_read_valid_channel_2_wgt[sram_grp] ),
                .o_read_ready_channel_2_wgt        ( o_read_ready_channel_2_wgt[sram_grp] ),
                .i_read_addr_channel_2_wgt         ( i_read_addr_channel_2_wgt[sram_grp] ),
                .o_read_data_channel_2_wgt         ( o_read_data_channel_2_wgt[sram_grp] ),
                .i_write_valid_channel_2_wgt       ( i_write_valid_channel_2_wgt[sram_grp] ),
                .o_write_ready_channel_2_wgt       ( o_write_ready_channel_2_wgt[sram_grp] ),
                .i_write_addr_channel_2_wgt        ( i_write_addr_channel_2_wgt[sram_grp] ),
                .i_write_data_channel_2_wgt        ( i_write_data_channel_2_wgt[sram_grp] ),
                .i_control_mode_channel_2_wgt      ( i_control_mode_channel_2_wgt ),
                .o_FIFO_read_ready_channel_2_wgt   ( o_FIFO_read_ready_channel_2_wgt[sram_grp] ),
                .o_FIFO_write_ready_channel_2_wgt  ( o_FIFO_write_ready_channel_2_wgt[sram_grp] ),
                .i_data_fifo_ready_channel_2_wgt   ( i_data_fifo_ready_channel_2_wgt[sram_grp] )
            );
        end
    endgenerate

endmodule 