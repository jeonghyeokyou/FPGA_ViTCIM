`timescale 1ns / 1ps

module L2_FIFO_interface_wrapper #(
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
    localparam ADDR_BIT_TOTAL_CHANNEL_2_WGT     = $clog2(ADDRESS_ROW*BLOCKS_CHANNEL_2_WGT),  

    parameter FIFO_DEPTH = 16,
    parameter INPUT_DELAY = 5
)(
    // global clock, reset
    input i_clk,
    input i_rstn,
    //============================================================
    // Top controller (include Address generator) interface
    //============================================================
    ///////////////////////// channel 0 //////////////////////////
    // Read port
    input                                 i_read_valid_channel_0,
    output                                o_read_ready_channel_0,
    input  [ADDR_BIT_TOTAL-1:0]           i_read_addr_channel_0,
    output [BANDWIDTH_CHANNEL_0-1:0]      o_read_data_channel_0,
    // Write port
    input                                 i_write_valid_channel_0,
    output                                o_write_ready_channel_0,
    input [ADDR_BIT_TOTAL-1:0]            i_write_addr_channel_0,
    input [BANDWIDTH_CHANNEL_0-1:0]       i_write_data_channel_0,
    // Control signal
    input                                 i_control_mode_channel_0,
    output                                o_FIFO_read_ready_channel_0,
    output                                o_FIFO_write_ready_channel_0,
    input                                 i_data_fifo_ready_channel_0,
    ///////////////////////// channel 1_in //////////////////////////
    // Read port
    input                                    i_read_valid_channel_1_in,
    output                                   o_read_ready_channel_1_in,
    input  [ADDR_BIT_TOTAL_CHANNEL_1_IN-1:0] i_read_addr_channel_1_in,
    output [BANDWIDTH_CHANNEL_1_IN-1:0]      o_read_data_channel_1_in,
    // Write port
    input                                    i_write_valid_channel_1_in,
    output                                   o_write_ready_channel_1_in,
    input [ADDR_BIT_TOTAL_CHANNEL_1_IN-1:0]  i_write_addr_channel_1_in,
    input [BANDWIDTH_CHANNEL_1_IN-1:0]       i_write_data_channel_1_in,
    // Control signal
    input                                    i_control_mode_channel_1_in,
    output                                   o_FIFO_read_ready_channel_1_in,
    output                                   o_FIFO_write_ready_channel_1_in,
    input                                    i_data_fifo_ready_channel_1_in,
    ///////////////////////// channel 2_in //////////////////////////
    // Read port
    input                                    i_read_valid_channel_2_in,
    output                                   o_read_ready_channel_2_in,
    input  [ADDR_BIT_TOTAL_CHANNEL_2_IN-1:0] i_read_addr_channel_2_in,
    output [BANDWIDTH_CHANNEL_2_IN-1:0]      o_read_data_channel_2_in,
    // Write port
    input                                    i_write_valid_channel_2_in,
    output                                   o_write_ready_channel_2_in,
    input [ADDR_BIT_TOTAL_CHANNEL_2_IN-1:0]  i_write_addr_channel_2_in,
    input [BANDWIDTH_CHANNEL_2_IN-1:0]       i_write_data_channel_2_in,
    // Control signal
    input                                    i_control_mode_channel_2_in,
    output                                   o_FIFO_read_ready_channel_2_in,
    output                                   o_FIFO_write_ready_channel_2_in,
    input                                    i_data_fifo_ready_channel_2_in,
    ///////////////////////// channel 1_wgt //////////////////////////
    // Read port
    input                                    i_read_valid_channel_1_wgt,
    output                                   o_read_ready_channel_1_wgt,
    input  [ADDR_BIT_TOTAL_CHANNEL_1_WGT-1:0] i_read_addr_channel_1_wgt,
    output [BANDWIDTH_CHANNEL_1_WGT-1:0]      o_read_data_channel_1_wgt,
    // Write port
    input                                    i_write_valid_channel_1_wgt,
    output                                   o_write_ready_channel_1_wgt,
    input [ADDR_BIT_TOTAL_CHANNEL_1_WGT-1:0]  i_write_addr_channel_1_wgt,
    input [BANDWIDTH_CHANNEL_1_WGT-1:0]       i_write_data_channel_1_wgt,
    // Control signal
    input                                    i_control_mode_channel_1_wgt,
    output                                   o_FIFO_read_ready_channel_1_wgt,
    output                                   o_FIFO_write_ready_channel_1_wgt,
    input                                    i_data_fifo_ready_channel_1_wgt,
    ///////////////////////// channel 2_wgt //////////////////////////
    // Read port
    input                                    i_read_valid_channel_2_wgt,
    output                                   o_read_ready_channel_2_wgt,
    input  [ADDR_BIT_TOTAL_CHANNEL_2_WGT-1:0] i_read_addr_channel_2_wgt,
    output [BANDWIDTH_CHANNEL_2_WGT-1:0]      o_read_data_channel_2_wgt,
    // Write port
    input                                    i_write_valid_channel_2_wgt,
    output                                   o_write_ready_channel_2_wgt,
    input [ADDR_BIT_TOTAL_CHANNEL_2_WGT-1:0]  i_write_addr_channel_2_wgt,
    input [BANDWIDTH_CHANNEL_2_WGT-1:0]       i_write_data_channel_2_wgt,
    // Control signal
    input                                    i_control_mode_channel_2_wgt,
    output                                   o_FIFO_read_ready_channel_2_wgt,
    output                                   o_FIFO_write_ready_channel_2_wgt,
    input                                    i_data_fifo_ready_channel_2_wgt
);

//===============================================================================================

//===============================================================================================
// Module Instance

///// channel 0 : interface (L2_FIFO_interface <==> sram_ctrl)
// read interface
wire                                       w_read_valid_L2_channel_0;
wire                                       w_read_ready_L2_channel_0;
wire [ADDR_BIT_TOTAL-1:0]                  w_read_addr_L2_channel_0;
wire [BANDWIDTH_CHANNEL_0-1:0]             w_read_data_L2_channel_0;
// Write Interface
wire                                       w_write_valid_L2_channel_0;
wire                                       w_write_ready_L2_channel_0;
wire [ADDR_BIT_TOTAL-1:0]                  w_write_addr_L2_channel_0;
wire [BANDWIDTH_CHANNEL_0-1:0]             w_write_data_L2_channel_0;
// Control signal
wire                                       w_control_mode_channel_0;

///// channel 1 in : interface (L2_FIFO_interface <==> sram_ctrl)
// read interface
wire                                          w_read_valid_L2_channel_1_in;
wire                                          w_read_ready_L2_channel_1_in;
wire [ADDR_BIT_TOTAL_CHANNEL_1_IN-1:0]        w_read_addr_L2_channel_1_in;
wire [BANDWIDTH_CHANNEL_1_IN-1:0]             w_read_data_L2_channel_1_in;
// Write Interface
wire                                          w_write_valid_L2_channel_1_in;
wire                                          w_write_ready_L2_channel_1_in;
wire [ADDR_BIT_TOTAL_CHANNEL_1_IN-1:0]        w_write_addr_L2_channel_1_in;
wire [BANDWIDTH_CHANNEL_1_IN-1:0]             w_write_data_L2_channel_1_in;
// Control signal
wire                                          w_control_mode_channel_1_in;

///// channel 2 in : interface (L2_FIFO_interface <==> sram_ctrl)
// read interface
wire                                          w_read_valid_L2_channel_2_in;
wire                                          w_read_ready_L2_channel_2_in;
wire [ADDR_BIT_TOTAL_CHANNEL_2_IN-1:0]        w_read_addr_L2_channel_2_in;
wire [BANDWIDTH_CHANNEL_2_IN-1:0]             w_read_data_L2_channel_2_in;
// Write Interface
wire                                          w_write_valid_L2_channel_2_in;
wire                                          w_write_ready_L2_channel_2_in;
wire [ADDR_BIT_TOTAL_CHANNEL_2_IN-1:0]        w_write_addr_L2_channel_2_in;
wire [BANDWIDTH_CHANNEL_2_IN-1:0]             w_write_data_L2_channel_2_in;
// Control signal
wire                                          w_control_mode_channel_2_in;

///// channel 1 wgt : interface (L2_FIFO_interface <==> sram_ctrl)
// read interface
wire                                           w_read_valid_L2_channel_1_wgt;
wire                                           w_read_ready_L2_channel_1_wgt;
wire [ADDR_BIT_TOTAL_CHANNEL_1_WGT-1:0]        w_read_addr_L2_channel_1_wgt;
wire [BANDWIDTH_CHANNEL_1_WGT-1:0]             w_read_data_L2_channel_1_wgt;
// Write Interface
wire                                           w_write_valid_L2_channel_1_wgt;
wire                                           w_write_ready_L2_channel_1_wgt;
wire [ADDR_BIT_TOTAL_CHANNEL_1_WGT-1:0]        w_write_addr_L2_channel_1_wgt;
wire [BANDWIDTH_CHANNEL_1_WGT-1:0]             w_write_data_L2_channel_1_wgt;
// Control signal
wire                                           w_control_mode_channel_1_wgt;

///// channel 2 wgt : interface (L2_FIFO_interface <==> sram_ctrl)
// read interface
wire                                           w_read_valid_L2_channel_2_wgt;
wire                                           w_read_ready_L2_channel_2_wgt;
wire [ADDR_BIT_TOTAL_CHANNEL_2_WGT-1:0]        w_read_addr_L2_channel_2_wgt;
wire [BANDWIDTH_CHANNEL_2_WGT-1:0]             w_read_data_L2_channel_2_wgt;
// Write Interface
wire                                           w_write_valid_L2_channel_2_wgt;
wire                                           w_write_ready_L2_channel_2_wgt;
wire [ADDR_BIT_TOTAL_CHANNEL_2_WGT-1:0]        w_write_addr_L2_channel_2_wgt;
wire [BANDWIDTH_CHANNEL_2_WGT-1:0]             w_write_data_L2_channel_2_wgt;
// Control signal
wire                                           w_control_mode_channel_2_wgt;

L2_FIFO_interface #(
    .ADDR_DEPTH(ADDRESS_ROW*BLOCKS),
    .DATA_WIDTH(BANDWIDTH_CHANNEL_0),
    .FIFO_DEPTH(FIFO_DEPTH),
    .INPUT_DELAY(INPUT_DELAY)
) u_L2_FIFO_interface_channel_0 (
    .clk                ( i_clk ),
    .rstb               ( i_rstn ),

    .i_read_valid       ( i_read_valid_channel_0 ),
    .o_read_ready       ( o_read_ready_channel_0 ),
    .i_read_addr        ( i_read_addr_channel_0 ),
    .o_read_data        ( o_read_data_channel_0 ),
    
    .i_write_valid      ( i_write_valid_channel_0 ),
    .o_write_ready      ( o_write_ready_channel_0 ),
    .i_write_addr       ( i_write_addr_channel_0 ),
    .i_write_data       ( i_write_data_channel_0 ),
    
    .i_control_mode     ( i_control_mode_channel_0 ),
    .o_FIFO_read_ready  ( o_FIFO_read_ready_channel_0 ),
    .o_FIFO_write_ready ( o_FIFO_write_ready_channel_0 ),
    .i_data_fifo_ready  ( i_data_fifo_ready_channel_0 ),

    .o_read_valid_L2    ( w_read_valid_L2_channel_0 ),
    .i_read_ready_L2    ( w_read_ready_L2_channel_0 ),
    .o_read_addr_L2     ( w_read_addr_L2_channel_0 ),
    .i_read_data_L2     ( w_read_data_L2_channel_0 ),
    
    .o_write_valid_L2   ( w_write_valid_L2_channel_0 ),
    .i_write_ready_L2   ( w_write_ready_L2_channel_0 ),
    .o_write_addr_L2    ( w_write_addr_L2_channel_0 ),
    .o_write_data_L2    ( w_write_data_L2_channel_0 ),
    
    .o_control_mode     ( w_control_mode_channel_0 )
);

L2_FIFO_interface #(
    .ADDR_DEPTH(ADDRESS_ROW*BLOCKS_CHANNEL_1_IN),
    .DATA_WIDTH(BANDWIDTH_CHANNEL_1_IN),
    .FIFO_DEPTH(FIFO_DEPTH),
    .INPUT_DELAY(INPUT_DELAY)
) u_L2_FIFO_interface_channel_1_in (
    .clk                ( i_clk ),
    .rstb               ( i_rstn ),

    .i_read_valid       ( i_read_valid_channel_1_in ),
    .o_read_ready       ( o_read_ready_channel_1_in ),
    .i_read_addr        ( i_read_addr_channel_1_in ),
    .o_read_data        ( o_read_data_channel_1_in ),
    
    .i_write_valid      ( i_write_valid_channel_1_in ),
    .o_write_ready      ( o_write_ready_channel_1_in ),
    .i_write_addr       ( i_write_addr_channel_1_in ),
    .i_write_data       ( i_write_data_channel_1_in ),
    
    .i_control_mode     ( i_control_mode_channel_1_in ),
    .o_FIFO_read_ready  ( o_FIFO_read_ready_channel_1_in ),
    .o_FIFO_write_ready ( o_FIFO_write_ready_channel_1_in ),
    .i_data_fifo_ready  ( i_data_fifo_ready_channel_1_in ),

    .o_read_valid_L2    ( w_read_valid_L2_channel_1_in ),
    .i_read_ready_L2    ( w_read_ready_L2_channel_1_in ),
    .o_read_addr_L2     ( w_read_addr_L2_channel_1_in ),
    .i_read_data_L2     ( w_read_data_L2_channel_1_in ),
    
    .o_write_valid_L2   ( w_write_valid_L2_channel_1_in ),
    .i_write_ready_L2   ( w_write_ready_L2_channel_1_in ),
    .o_write_addr_L2    ( w_write_addr_L2_channel_1_in ),
    .o_write_data_L2    ( w_write_data_L2_channel_1_in ),
    
    .o_control_mode     ( w_control_mode_channel_1_in )
);

L2_FIFO_interface #(
    .ADDR_DEPTH(ADDRESS_ROW*BLOCKS_CHANNEL_2_IN),
    .DATA_WIDTH(BANDWIDTH_CHANNEL_2_IN),
    .FIFO_DEPTH(FIFO_DEPTH),
    .INPUT_DELAY(INPUT_DELAY)
) u_L2_FIFO_interface_channel_2_in (
    .clk                ( i_clk ),
    .rstb               ( i_rstn ),

    .i_read_valid       ( i_read_valid_channel_2_in ),
    .o_read_ready       ( o_read_ready_channel_2_in ),
    .i_read_addr        ( i_read_addr_channel_2_in ),
    .o_read_data        ( o_read_data_channel_2_in ),
    
    .i_write_valid      ( i_write_valid_channel_2_in ),
    .o_write_ready      ( o_write_ready_channel_2_in ),
    .i_write_addr       ( i_write_addr_channel_2_in ),
    .i_write_data       ( i_write_data_channel_2_in ),
    
    .i_control_mode     ( i_control_mode_channel_2_in ),
    .o_FIFO_read_ready  ( o_FIFO_read_ready_channel_2_in ),
    .o_FIFO_write_ready ( o_FIFO_write_ready_channel_2_in ),
    .i_data_fifo_ready  ( i_data_fifo_ready_channel_2_in ),

    .o_read_valid_L2    ( w_read_valid_L2_channel_2_in ),
    .i_read_ready_L2    ( w_read_ready_L2_channel_2_in ),
    .o_read_addr_L2     ( w_read_addr_L2_channel_2_in ),
    .i_read_data_L2     ( w_read_data_L2_channel_2_in ),
    
    .o_write_valid_L2   ( w_write_valid_L2_channel_2_in ),
    .i_write_ready_L2   ( w_write_ready_L2_channel_2_in ),
    .o_write_addr_L2    ( w_write_addr_L2_channel_2_in ),
    .o_write_data_L2    ( w_write_data_L2_channel_2_in ),
    
    .o_control_mode     ( w_control_mode_channel_2_in )
);

L2_FIFO_interface #(
    .ADDR_DEPTH(ADDRESS_ROW*BLOCKS_CHANNEL_1_WGT),
    .DATA_WIDTH(BANDWIDTH_CHANNEL_1_WGT),
    .FIFO_DEPTH(FIFO_DEPTH),
    .INPUT_DELAY(INPUT_DELAY)
) u_L2_FIFO_interface_channel_1_wgt (
    .clk                ( i_clk ),
    .rstb               ( i_rstn ),

    .i_read_valid       ( i_read_valid_channel_1_wgt ),
    .o_read_ready       ( o_read_ready_channel_1_wgt ),
    .i_read_addr        ( i_read_addr_channel_1_wgt ),
    .o_read_data        ( o_read_data_channel_1_wgt ),
    
    .i_write_valid      ( i_write_valid_channel_1_wgt ),
    .o_write_ready      ( o_write_ready_channel_1_wgt ),
    .i_write_addr       ( i_write_addr_channel_1_wgt ),
    .i_write_data       ( i_write_data_channel_1_wgt ),
    
    .i_control_mode     ( i_control_mode_channel_1_wgt ),
    .o_FIFO_read_ready  ( o_FIFO_read_ready_channel_1_wgt ),
    .o_FIFO_write_ready ( o_FIFO_write_ready_channel_1_wgt ),
    .i_data_fifo_ready  ( i_data_fifo_ready_channel_1_wgt ),

    .o_read_valid_L2    ( w_read_valid_L2_channel_1_wgt ),
    .i_read_ready_L2    ( w_read_ready_L2_channel_1_wgt ),
    .o_read_addr_L2     ( w_read_addr_L2_channel_1_wgt ),
    .i_read_data_L2     ( w_read_data_L2_channel_1_wgt ),
    
    .o_write_valid_L2   ( w_write_valid_L2_channel_1_wgt ),
    .i_write_ready_L2   ( w_write_ready_L2_channel_1_wgt ),
    .o_write_addr_L2    ( w_write_addr_L2_channel_1_wgt ),
    .o_write_data_L2    ( w_write_data_L2_channel_1_wgt ),
    
    .o_control_mode     ( w_control_mode_channel_1_wgt )
);

L2_FIFO_interface #(
    .ADDR_DEPTH(ADDRESS_ROW*BLOCKS_CHANNEL_2_WGT),
    .DATA_WIDTH(BANDWIDTH_CHANNEL_2_WGT),
    .FIFO_DEPTH(FIFO_DEPTH),
    .INPUT_DELAY(INPUT_DELAY)
) u_L2_FIFO_interface_channel_2_wgt (
    .clk                ( i_clk ),
    .rstb               ( i_rstn ),

    .i_read_valid       ( i_read_valid_channel_2_wgt ),
    .o_read_ready       ( o_read_ready_channel_2_wgt ),
    .i_read_addr        ( i_read_addr_channel_2_wgt ),
    .o_read_data        ( o_read_data_channel_2_wgt ),
    
    .i_write_valid      ( i_write_valid_channel_2_wgt ),
    .o_write_ready      ( o_write_ready_channel_2_wgt ),
    .i_write_addr       ( i_write_addr_channel_2_wgt ),
    .i_write_data       ( i_write_data_channel_2_wgt ),
    
    .i_control_mode     ( i_control_mode_channel_2_wgt ),
    .o_FIFO_read_ready  ( o_FIFO_read_ready_channel_2_wgt ),
    .o_FIFO_write_ready ( o_FIFO_write_ready_channel_2_wgt ),
    .i_data_fifo_ready  ( i_data_fifo_ready_channel_2_wgt ),

    .o_read_valid_L2    ( w_read_valid_L2_channel_2_wgt ),
    .i_read_ready_L2    ( w_read_ready_L2_channel_2_wgt ),
    .o_read_addr_L2     ( w_read_addr_L2_channel_2_wgt ),
    .i_read_data_L2     ( w_read_data_L2_channel_2_wgt ),
    
    .o_write_valid_L2   ( w_write_valid_L2_channel_2_wgt ),
    .i_write_ready_L2   ( w_write_ready_L2_channel_2_wgt ),
    .o_write_addr_L2    ( w_write_addr_L2_channel_2_wgt ),
    .o_write_data_L2    ( w_write_data_L2_channel_2_wgt ),
    
    .o_control_mode     ( w_control_mode_channel_2_wgt )
);

///// channel 0 : interface (sram_controller <==> sram_group_decoder)
wire                                w_sram_ceb_channel_0;
wire                                w_sram_web_channel_0;          
wire [ADDR_BIT_TOTAL-1:0]           w_sram_addr_channel_0;    
wire [BANDWIDTH_CHANNEL_0-1:0]      w_sram_din_channel_0;
wire [BANDWIDTH_CHANNEL_0-1:0]      w_sram_qout_channel_0;
///// channel 1 in : interface (sram_controller <==> sram_group_decoder)
wire                                   w_sram_ceb_channel_1_in;
wire                                   w_sram_web_channel_1_in;          
wire [ADDR_BIT_TOTAL_CHANNEL_1_IN-1:0] w_sram_addr_channel_1_in;    
wire [BANDWIDTH_CHANNEL_1_IN-1:0]      w_sram_din_channel_1_in;
wire [BANDWIDTH_CHANNEL_1_IN-1:0]      w_sram_qout_channel_1_in;
///// channel 2 in : interface (sram_controller <==> sram_group_decoder)
wire                                   w_sram_ceb_channel_2_in;
wire                                   w_sram_web_channel_2_in;          
wire [ADDR_BIT_TOTAL_CHANNEL_2_IN-1:0] w_sram_addr_channel_2_in;    
wire [BANDWIDTH_CHANNEL_2_IN-1:0]      w_sram_din_channel_2_in;
wire [BANDWIDTH_CHANNEL_2_IN-1:0]      w_sram_qout_channel_2_in;
///// channel 1 wgt : interface (sram_controller <==> sram_group_decoder)
wire                                    w_sram_ceb_channel_1_wgt;
wire                                    w_sram_web_channel_1_wgt;          
wire [ADDR_BIT_TOTAL_CHANNEL_1_WGT-1:0] w_sram_addr_channel_1_wgt;    
wire [BANDWIDTH_CHANNEL_1_WGT-1:0]      w_sram_din_channel_1_wgt;
wire [BANDWIDTH_CHANNEL_1_WGT-1:0]      w_sram_qout_channel_1_wgt;
///// channel 2 wgt : interface (sram_controller <==> sram_group_decoder)
wire                                    w_sram_ceb_channel_2_wgt;
wire                                    w_sram_web_channel_2_wgt;          
wire [ADDR_BIT_TOTAL_CHANNEL_2_WGT-1:0] w_sram_addr_channel_2_wgt;    
wire [BANDWIDTH_CHANNEL_2_WGT-1:0]      w_sram_din_channel_2_wgt;
wire [BANDWIDTH_CHANNEL_2_WGT-1:0]      w_sram_qout_channel_2_wgt;

sram_controller #(
    .ADDR_DEPTH ( ADDRESS_ROW*BLOCKS ),
    .DATA_WIDTH ( BANDWIDTH_CHANNEL_0 )
) u_sram_controller_channel_0 (
    .i_clk          ( i_clk ),
    .i_rstn         ( i_rstn ),

    .i_control_mode ( w_control_mode_channel_0 ),

    .i_read_valid   ( w_read_valid_L2_channel_0 ),
    .o_read_ready   ( w_read_ready_L2_channel_0 ),
    .i_read_addr    ( w_read_addr_L2_channel_0 ),
    .o_read_data    ( w_read_data_L2_channel_0 ),

    .i_write_valid  ( w_write_valid_L2_channel_0 ),
    .o_write_ready  ( w_write_ready_L2_channel_0 ),
    .i_write_addr   ( w_write_addr_L2_channel_0 ),
    .i_write_data   ( w_write_data_L2_channel_0 ),

    .o_sram_ceb     ( w_sram_ceb_channel_0 ),
    .o_sram_web     ( w_sram_web_channel_0 ),
    .o_sram_addr    ( w_sram_addr_channel_0 ),
    .o_sram_din     ( w_sram_din_channel_0 ),
    .i_sram_dout    ( w_sram_qout_channel_0 )
);

sram_controller #(
    .ADDR_DEPTH ( ADDRESS_ROW*BLOCKS_CHANNEL_1_IN ),
    .DATA_WIDTH ( BANDWIDTH_CHANNEL_1_IN )
) u_sram_controller_channel_1_in (
    .i_clk          ( i_clk ),
    .i_rstn         ( i_rstn ),

    .i_control_mode ( w_control_mode_channel_1_in ),

    .i_read_valid   ( w_read_valid_L2_channel_1_in ),
    .o_read_ready   ( w_read_ready_L2_channel_1_in ),
    .i_read_addr    ( w_read_addr_L2_channel_1_in ),
    .o_read_data    ( w_read_data_L2_channel_1_in ),

    .i_write_valid  ( w_write_valid_L2_channel_1_in ),
    .o_write_ready  ( w_write_ready_L2_channel_1_in ),
    .i_write_addr   ( w_write_addr_L2_channel_1_in ),
    .i_write_data   ( w_write_data_L2_channel_1_in ),

    .o_sram_ceb     ( w_sram_ceb_channel_1_in ),
    .o_sram_web     ( w_sram_web_channel_1_in ),
    .o_sram_addr    ( w_sram_addr_channel_1_in ),
    .o_sram_din     ( w_sram_din_channel_1_in ),
    .i_sram_dout    ( w_sram_qout_channel_1_in )
);

sram_controller #(
    .ADDR_DEPTH ( ADDRESS_ROW*BLOCKS_CHANNEL_2_IN ),
    .DATA_WIDTH ( BANDWIDTH_CHANNEL_2_IN )
) u_sram_controller_channel_2_in (
    .i_clk          ( i_clk ),
    .i_rstn         ( i_rstn ),

    .i_control_mode ( w_control_mode_channel_2_in ),

    .i_read_valid   ( w_read_valid_L2_channel_2_in ),
    .o_read_ready   ( w_read_ready_L2_channel_2_in ),
    .i_read_addr    ( w_read_addr_L2_channel_2_in ),
    .o_read_data    ( w_read_data_L2_channel_2_in ),

    .i_write_valid  ( w_write_valid_L2_channel_2_in ),
    .o_write_ready  ( w_write_ready_L2_channel_2_in ),
    .i_write_addr   ( w_write_addr_L2_channel_2_in ),
    .i_write_data   ( w_write_data_L2_channel_2_in ),

    .o_sram_ceb     ( w_sram_ceb_channel_2_in ),
    .o_sram_web     ( w_sram_web_channel_2_in ),
    .o_sram_addr    ( w_sram_addr_channel_2_in ),
    .o_sram_din     ( w_sram_din_channel_2_in ),
    .i_sram_dout    ( w_sram_qout_channel_2_in )
);

sram_controller #(
    .ADDR_DEPTH ( ADDRESS_ROW*BLOCKS_CHANNEL_1_WGT ),
    .DATA_WIDTH ( BANDWIDTH_CHANNEL_1_WGT )
) u_sram_controller_channel_1_wgt (
    .i_clk          ( i_clk ),
    .i_rstn         ( i_rstn ),

    .i_control_mode ( w_control_mode_channel_1_wgt ),

    .i_read_valid   ( w_read_valid_L2_channel_1_wgt ),
    .o_read_ready   ( w_read_ready_L2_channel_1_wgt ),
    .i_read_addr    ( w_read_addr_L2_channel_1_wgt ),
    .o_read_data    ( w_read_data_L2_channel_1_wgt ),

    .i_write_valid  ( w_write_valid_L2_channel_1_wgt ),
    .o_write_ready  ( w_write_ready_L2_channel_1_wgt ),
    .i_write_addr   ( w_write_addr_L2_channel_1_wgt ),
    .i_write_data   ( w_write_data_L2_channel_1_wgt ),

    .o_sram_ceb     ( w_sram_ceb_channel_1_wgt ),
    .o_sram_web     ( w_sram_web_channel_1_wgt ),
    .o_sram_addr    ( w_sram_addr_channel_1_wgt ),
    .o_sram_din     ( w_sram_din_channel_1_wgt ),
    .i_sram_dout    ( w_sram_qout_channel_1_wgt )
);

sram_controller #(
    .ADDR_DEPTH ( ADDRESS_ROW*BLOCKS_CHANNEL_2_WGT ),
    .DATA_WIDTH ( BANDWIDTH_CHANNEL_2_WGT )
) u_sram_controller_channel_2_wgt (
    .i_clk          ( i_clk ),
    .i_rstn         ( i_rstn ),

    .i_control_mode ( w_control_mode_channel_2_wgt ),

    .i_read_valid   ( w_read_valid_L2_channel_2_wgt ),
    .o_read_ready   ( w_read_ready_L2_channel_2_wgt ),
    .i_read_addr    ( w_read_addr_L2_channel_2_wgt ),
    .o_read_data    ( w_read_data_L2_channel_2_wgt ),

    .i_write_valid  ( w_write_valid_L2_channel_2_wgt ),
    .o_write_ready  ( w_write_ready_L2_channel_2_wgt ),
    .i_write_addr   ( w_write_addr_L2_channel_2_wgt ),
    .i_write_data   ( w_write_data_L2_channel_2_wgt ),

    .o_sram_ceb     ( w_sram_ceb_channel_2_wgt ),
    .o_sram_web     ( w_sram_web_channel_2_wgt ),
    .o_sram_addr    ( w_sram_addr_channel_2_wgt ),
    .o_sram_din     ( w_sram_din_channel_2_wgt ),
    .i_sram_dout    ( w_sram_qout_channel_2_wgt )
);

SRAM_group_decoder #(
     .BLOCKS               ( BLOCKS ), 
     .BANDWIDTH_CHANNEL_0     ( BANDWIDTH_CHANNEL_0     ), 
     .BANDWIDTH_CHANNEL_1_IN  ( BANDWIDTH_CHANNEL_1_IN  ), 
     .BANDWIDTH_CHANNEL_2_IN  ( BANDWIDTH_CHANNEL_2_IN  ), 
     .BANDWIDTH_CHANNEL_1_WGT ( BANDWIDTH_CHANNEL_1_WGT ), 
     .BANDWIDTH_CHANNEL_2_WGT ( BANDWIDTH_CHANNEL_2_WGT ), 
     .ADDRESS_ROW          ( ADDRESS_ROW )  
) u_SRAM_group_decoder ( 
    .i_clk                ( i_clk ),
    .i_rstn               ( i_rstn ),

    .i_ceb_channel_0      ( w_sram_ceb_channel_0 ),
    .i_web_channel_0      ( w_sram_web_channel_0 ),
    .i_addr_channel_0     ( w_sram_addr_channel_0 ),
    .i_din_channel_0      ( w_sram_din_channel_0 ),
    .o_qout_channel_0     ( w_sram_qout_channel_0 ),

    .i_ceb_channel_1_in      ( w_sram_ceb_channel_1_in ),
    .i_web_channel_1_in      ( w_sram_web_channel_1_in ),
    .i_addr_channel_1_in     ( w_sram_addr_channel_1_in ),
    .i_din_channel_1_in      ( w_sram_din_channel_1_in ),
    .o_qout_channel_1_in     ( w_sram_qout_channel_1_in ),

    .i_ceb_channel_2_in      ( w_sram_ceb_channel_2_in ),
    .i_web_channel_2_in      ( w_sram_web_channel_2_in ),
    .i_addr_channel_2_in     ( w_sram_addr_channel_2_in ),
    .i_din_channel_2_in      ( w_sram_din_channel_2_in ),
    .o_qout_channel_2_in     ( w_sram_qout_channel_2_in ),

    .i_ceb_channel_1_wgt      ( w_sram_ceb_channel_1_wgt ),
    .i_web_channel_1_wgt      ( w_sram_web_channel_1_wgt ),
    .i_addr_channel_1_wgt     ( w_sram_addr_channel_1_wgt ),
    .i_din_channel_1_wgt      ( w_sram_din_channel_1_wgt ),
    .o_qout_channel_1_wgt     ( w_sram_qout_channel_1_wgt ),

    .i_ceb_channel_2_wgt      ( w_sram_ceb_channel_2_wgt ),
    .i_web_channel_2_wgt      ( w_sram_web_channel_2_wgt ),
    .i_addr_channel_2_wgt     ( w_sram_addr_channel_2_wgt ),
    .i_din_channel_2_wgt      ( w_sram_din_channel_2_wgt ),
    .o_qout_channel_2_wgt     ( w_sram_qout_channel_2_wgt )
);

endmodule
