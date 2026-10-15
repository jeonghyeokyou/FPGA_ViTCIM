`timescale 1ns / 1ps

module cmd_decoder_SRAM_group_merge #(
    parameter GROUPS = 8,
    parameter BLOCKS = 32,
    localparam BLOCKS_TOTAL = GROUPS*BLOCKS,
    
    parameter BANDWIDTH_CHANNEL_0 = 64,
    parameter BANDWIDTH_CHANNEL_1_IN  = 512,                                                  
    parameter BANDWIDTH_CHANNEL_2_IN  = 256,                                                     
    parameter BANDWIDTH_CHANNEL_1_WGT = 256,                                                  
    parameter BANDWIDTH_CHANNEL_2_WGT = 256,   

    parameter ADDRESS_ROW = 2048,

    parameter DESTINATION_ADDR_BIT_CHANNEL_0     = 20,
    parameter DESTINATION_ADDR_BIT_CHANNEL_1_IN  = 19,
    parameter DESTINATION_ADDR_BIT_CHANNEL_2_IN  = 15,
    parameter DESTINATION_ADDR_BIT_CHANNEL_1_WGT = 18,
    parameter DESTINATION_ADDR_BIT_CHANNEL_2_WGT  = 8,

    localparam ADDR_BIT_PER_GROUP = $clog2(GROUPS),
    localparam ADDR_BIT_PER_BLOCK = $clog2(BLOCKS),

    localparam ADDR_BIT_IN_BLOCK = $clog2(ADDRESS_ROW),                                  
    localparam ADDR_BIT_PER_BLOCK_CHANNEL_0 = $clog2(BLOCKS),                                      
    localparam ADDR_BIT_TOTAL_CHANNEL_0 = $clog2(ADDRESS_ROW*BLOCKS), 
    localparam ADDR_BIT_TOTAL_CHANNEL_0_GRP = ADDR_BIT_PER_GROUP + ADDR_BIT_TOTAL_CHANNEL_0,

    localparam GROUP_CHANNEL_1_IN = BANDWIDTH_CHANNEL_1_IN/BANDWIDTH_CHANNEL_0,                 
    localparam BLOCKS_CHANNEL_1_IN = BLOCKS/GROUP_CHANNEL_1_IN,                                 
    localparam ADDR_BIT_PER_BLOCK_CHANNEL_1_IN = $clog2(BLOCKS_CHANNEL_1_IN),                    
    localparam ADDR_BIT_TOTAL_CHANNEL_1_IN = $clog2(ADDRESS_ROW*BLOCKS_CHANNEL_1_IN),   
    localparam ADDR_BIT_TOTAL_CHANNEL_1_IN_GRP = ADDR_BIT_PER_GROUP + ADDR_BIT_TOTAL_CHANNEL_1_IN,

    localparam GROUP_CHANNEL_2_IN = BANDWIDTH_CHANNEL_2_IN/BANDWIDTH_CHANNEL_0,                 
    localparam BLOCKS_CHANNEL_2_IN = BLOCKS/GROUP_CHANNEL_2_IN,                                  
    localparam ADDR_BIT_PER_BLOCK_CHANNEL_2_IN = $clog2(BLOCKS_CHANNEL_2_IN),                   
    localparam ADDR_BIT_TOTAL_CHANNEL_2_IN = $clog2(ADDRESS_ROW*BLOCKS_CHANNEL_2_IN),
    localparam ADDR_BIT_TOTAL_CHANNEL_2_IN_GRP = ADDR_BIT_PER_GROUP + ADDR_BIT_TOTAL_CHANNEL_2_IN,

    localparam GROUP_CHANNEL_1_WGT = BANDWIDTH_CHANNEL_1_WGT/BANDWIDTH_CHANNEL_0,                 
    localparam BLOCKS_CHANNEL_1_WGT = BLOCKS/GROUP_CHANNEL_1_WGT,                                 
    localparam ADDR_BIT_PER_BLOCK_CHANNEL_1_WGT = $clog2(BLOCKS_CHANNEL_1_WGT),                    
    localparam ADDR_BIT_TOTAL_CHANNEL_1_WGT = $clog2(ADDRESS_ROW*BLOCKS_CHANNEL_1_WGT),   
    localparam ADDR_BIT_TOTAL_CHANNEL_1_WGT_GRP = ADDR_BIT_PER_GROUP + ADDR_BIT_TOTAL_CHANNEL_1_WGT,

    localparam GROUP_CHANNEL_2_WGT = BANDWIDTH_CHANNEL_2_WGT/BANDWIDTH_CHANNEL_0,                 
    localparam BLOCKS_CHANNEL_2_WGT = BLOCKS/GROUP_CHANNEL_2_WGT,                                  
    localparam ADDR_BIT_PER_BLOCK_CHANNEL_2_WGT = $clog2(BLOCKS_CHANNEL_2_WGT),                   
    localparam ADDR_BIT_TOTAL_CHANNEL_2_WGT = $clog2(ADDRESS_ROW*BLOCKS_CHANNEL_2_WGT),
    localparam ADDR_BIT_TOTAL_CHANNEL_2_WGT_GRP = ADDR_BIT_PER_GROUP + ADDR_BIT_TOTAL_CHANNEL_2_WGT,

    localparam GROUPS_1 = 2,
    localparam GROUPS_2 = 4
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

    ////////////////////// channel 1_In //////////////////////
    // ========== Interface with command_decoder ==========
    input  wire [63:0] i_ch1_in_rw_cmd,       
    input  wire        i_ch1_in_rw_cmd_valid, 
    output wire        o_ch1_in_rw_cmd_ready,
    // ========== Interface with top_ctrl ==========
    output wire        o_load_busy_channel_1_in,
    output wire        o_store_busy_channel_1_in,        
    // ========== Interface with FIFO_interface (NOC Write Path) ========== 
    input  wire                                           i_noc_write_ready_channel_1_in,   
    output wire                                           o_noc_write_valid_channel_1_in,
    output wire [DESTINATION_ADDR_BIT_CHANNEL_1_IN-1:0]   o_noc_write_addr_channel_1_in,
    output wire [BANDWIDTH_CHANNEL_1_IN-1:0]              o_noc_write_data_channel_1_in,
    input  wire                                           i_noc_write_response_channel_1_in,
    // ========== Interface with FIFO_interface (NOC Read Path) ========== 
    output wire [DESTINATION_ADDR_BIT_CHANNEL_1_IN-1:0]   o_noc_read_addr_channel_1_in,
    output wire                                           o_noc_read_valid_channel_1_in, 
    output wire                                           o_noc_read_data_ready_channel_1_in,
    input  wire                                           i_noc_read_ready_channel_1_in,     
    input  wire                                           i_noc_read_response_channel_1_in,        
    input  wire [BANDWIDTH_CHANNEL_1_IN-1:0]              i_noc_read_data_channel_1_in,
    output wire                                           o_noc_control_mode_channel_1_in,

    ////////////////////// channel 2_In //////////////////////
    // ========== Interface with command_decoder ==========
    input  wire [63:0] i_ch2_in_rw_cmd,       
    input  wire        i_ch2_in_rw_cmd_valid, 
    output wire        o_ch2_in_rw_cmd_ready,
    // ========== Interface with top_ctrl ==========
    output wire        o_load_busy_channel_2_in,
    output wire        o_store_busy_channel_2_in,        
    // ========== Interface with FIFO_interface (NOC Write Path) ========== 
    input  wire                                           i_noc_write_ready_channel_2_in,   
    output wire                                           o_noc_write_valid_channel_2_in,
    output wire [DESTINATION_ADDR_BIT_CHANNEL_2_IN-1:0]   o_noc_write_addr_channel_2_in,
    output wire [BANDWIDTH_CHANNEL_2_IN-1:0]              o_noc_write_data_channel_2_in,
    input  wire                                           i_noc_write_response_channel_2_in,
    // ========== Interface with FIFO_interface (NOC Read Path) ========== 
    output wire                                           o_noc_read_ready_channel_2_in,    
    input  wire                                           i_noc_read_valid_channel_2_in,
    input  wire [31:0]                                    i_noc_read_addr_channel_2_in,
    input  wire [BANDWIDTH_CHANNEL_2_IN-1:0]              i_noc_read_data_channel_2_in, 
    output wire                                           o_noc_read_response_channel_2_in,
    output wire                                           o_noc_control_mode_channel_2_in,

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

    ////////////////////// channel 2_Wgt //////////////////////
    // ========== Interface with command_decoder ==========
    input  wire [63:0] i_ch2_wgt_rw_cmd,       
    input  wire        i_ch2_wgt_rw_cmd_valid, 
    output wire        o_ch2_wgt_rw_cmd_ready,
    // ========== Interface with top_ctrl ==========
    output wire        o_load_busy_channel_2_wgt,        
    // ========== Interface with FIFO_interface (NOC Write Path) ========== 
    input  wire                                            i_noc_write_ready_channel_2_wgt,  
    output wire                                            o_noc_write_valid_channel_2_wgt,
    output wire [DESTINATION_ADDR_BIT_CHANNEL_2_WGT-1:0]   o_noc_write_addr_channel_2_wgt,
    output wire [BANDWIDTH_CHANNEL_2_WGT-1:0]              o_noc_write_data_channel_2_wgt,
    input  wire                                            i_noc_write_response_channel_2_wgt,
    output wire                                            o_noc_control_mode_channel_2_wgt
);

////// channel_0
wire [GROUPS-1:0]                       w_read_valid_channel_0             ;
wire [GROUPS-1:0]                       w_read_ready_channel_0             ;
wire [ADDR_BIT_TOTAL_CHANNEL_0-1:0]     w_read_addr_channel_0  [GROUPS-1:0]; // no ADDR_BIT_TOTAL_CHANNEL_1_IN_GRP!
wire [BANDWIDTH_CHANNEL_0-1:0]          w_read_data_channel_0  [GROUPS-1:0];
wire [GROUPS-1:0]                       w_FIFO_read_ready_channel_0        ;
wire [GROUPS-1:0]                       w_data_fifo_ready_channel_0        ;

wire [GROUPS-1:0]                       w_write_valid_channel_0            ;
wire [GROUPS-1:0]                       w_write_ready_channel_0            ;
wire [ADDR_BIT_TOTAL_CHANNEL_0-1:0]     w_write_addr_channel_0 [GROUPS-1:0];
wire [BANDWIDTH_CHANNEL_0-1:0]          w_write_data_channel_0 [GROUPS-1:0];
wire [GROUPS-1:0]                       w_FIFO_write_ready_channel_0       ;

////// channel_1_input
wire [GROUPS-1:0]                       w_read_valid_channel_1_in             ;
wire [GROUPS-1:0]                       w_read_ready_channel_1_in             ;
wire [ADDR_BIT_TOTAL_CHANNEL_1_IN-1:0]  w_read_addr_channel_1_in  [GROUPS-1:0]; // no ADDR_BIT_TOTAL_CHANNEL_1_IN_GRP!
wire [BANDWIDTH_CHANNEL_1_IN-1:0]       w_read_data_channel_1_in  [GROUPS-1:0];
wire [GROUPS-1:0]                       w_FIFO_read_ready_channel_1_in        ;
wire [GROUPS-1:0]                       w_data_fifo_ready_channel_1_in        ;

wire [GROUPS-1:0]                       w_write_valid_channel_1_in            ;
wire [GROUPS-1:0]                       w_write_ready_channel_1_in            ;
wire [ADDR_BIT_TOTAL_CHANNEL_1_IN-1:0]  w_write_addr_channel_1_in [GROUPS-1:0];
wire [BANDWIDTH_CHANNEL_1_IN-1:0]       w_write_data_channel_1_in [GROUPS-1:0];
wire [GROUPS-1:0]                       w_FIFO_write_ready_channel_1_in       ;
wire                                    w_sram_control_mode_channel_1_in      ;

////// channel_2_input
wire [GROUPS-1:0]                       w_read_valid_channel_2_in             ;
wire [GROUPS-1:0]                       w_read_ready_channel_2_in             ;
wire [ADDR_BIT_TOTAL_CHANNEL_2_IN-1:0]  w_read_addr_channel_2_in  [GROUPS-1:0]; // no ADDR_BIT_TOTAL_CHANNEL_1_IN_GRP!
wire [BANDWIDTH_CHANNEL_2_IN-1:0]       w_read_data_channel_2_in  [GROUPS-1:0];
wire [GROUPS-1:0]                       w_FIFO_read_ready_channel_2_in        ;
wire [GROUPS-1:0]                       w_data_fifo_ready_channel_2_in        ;

wire [GROUPS-1:0]                       w_write_valid_channel_2_in            ;
wire [GROUPS-1:0]                       w_write_ready_channel_2_in            ;
wire [ADDR_BIT_TOTAL_CHANNEL_2_IN-1:0]  w_write_addr_channel_2_in [GROUPS-1:0];
wire [BANDWIDTH_CHANNEL_2_IN-1:0]       w_write_data_channel_2_in [GROUPS-1:0];
wire [GROUPS-1:0]                       w_FIFO_write_ready_channel_2_in       ;
wire                                    w_sram_control_mode_channel_2_in      ;

////// channel_1_weight
wire [GROUPS-1:0]                       w_read_valid_channel_1_wgt             ;
wire [GROUPS-1:0]                       w_read_ready_channel_1_wgt             ;
wire [ADDR_BIT_TOTAL_CHANNEL_1_WGT-1:0] w_read_addr_channel_1_wgt  [GROUPS-1:0]; // no ADDR_BIT_TOTAL_CHANNEL_1_WGT_GRP!
wire [BANDWIDTH_CHANNEL_1_WGT-1:0]      w_read_data_channel_1_wgt  [GROUPS-1:0];
wire [GROUPS-1:0]                       w_FIFO_read_ready_channel_1_wgt        ;
wire [GROUPS-1:0]                       w_data_fifo_ready_channel_1_wgt        ;

wire [GROUPS-1:0]                       w_write_valid_channel_1_wgt            ;
wire [GROUPS-1:0]                       w_write_ready_channel_1_wgt            ;
wire [ADDR_BIT_TOTAL_CHANNEL_1_WGT-1:0] w_write_addr_channel_1_wgt [GROUPS-1:0];
wire [BANDWIDTH_CHANNEL_1_WGT-1:0]      w_write_data_channel_1_wgt [GROUPS-1:0];
wire [GROUPS-1:0]                       w_FIFO_write_ready_channel_1_wgt       ;
wire                                    w_sram_control_mode_channel_1_wgt      ;

////// channel_2_weight
wire [GROUPS-1:0]                       w_read_valid_channel_2_wgt             ;
wire [GROUPS-1:0]                       w_read_ready_channel_2_wgt             ;
wire [ADDR_BIT_TOTAL_CHANNEL_2_WGT-1:0] w_read_addr_channel_2_wgt  [GROUPS-1:0]; // no ADDR_BIT_TOTAL_CHANNEL_2_WGT_GRP!
wire [BANDWIDTH_CHANNEL_2_WGT-1:0]      w_read_data_channel_2_wgt  [GROUPS-1:0];
wire [GROUPS-1:0]                       w_FIFO_read_ready_channel_2_wgt        ;
wire [GROUPS-1:0]                       w_data_fifo_ready_channel_2_wgt        ;
wire                                    w_sram_control_mode_channel_2_wgt      ;

//=================================================================================================================================================================//
//======================================================== Module instance call ===================================================================================//
//=================================================================================================================================================================//

SRAM_group_interface_channel_0 #(
        .GROUPS                               ( GROUPS                               ),
        .GROUPS_1                             ( GROUPS_1                             ),
        .GROUPS_2                             ( GROUPS_2                             ),
        .BLOCKS                               ( BLOCKS                               ),
        .BANDWIDTH_CHANNEL_0                  ( BANDWIDTH_CHANNEL_0                  ),
        .ADDRESS_ROW                          ( ADDRESS_ROW                          ),
        .DESTINATION_ADDR_BIT_CHANNEL_0       ( DESTINATION_ADDR_BIT_CHANNEL_0       )
    ) u_SRAM_group_interface_channel_0 (
        .i_clk                                ( i_clk                                ),
        .i_rstn                               ( i_rstn                               ),
        // Channel 0 Read Interface
        .i_sram_read_addr_channel_0           ( i_sram_read_addr_channel_0           ),
        .i_sram_read_valid_channel_0          ( i_sram_read_valid_channel_0          ),
        .o_sram_read_ready_channel_0          ( o_sram_read_ready_channel_0          ),
        .o_sram_read_data_channel_0           ( o_sram_read_data_channel_0           ),
        .o_sram_read_response_channel_0       ( o_sram_read_response_channel_0       ),
        .i_sram_read_data_ready_channel_0     ( i_sram_read_data_ready_channel_0     ),
        // Channel 0 Write Interface
        .i_sram_write_addr_channel_0          ( i_sram_write_addr_channel_0          ),
        .i_sram_write_data_channel_0          ( i_sram_write_data_channel_0          ),
        .i_sram_write_valid_channel_0         ( i_sram_write_valid_channel_0         ),
        .o_sram_write_ready_channel_0         ( o_sram_write_ready_channel_0         ),
        .o_sram_write_response_channel_0      (      ),
        // SRAM Group Merge (Read)
        .o_read_valid                         ( w_read_valid_channel_0           ),
        .i_read_ready                         ( w_read_ready_channel_0           ),
        .o_read_addr                          ( w_read_addr_channel_0            ),
        .i_read_data                          ( w_read_data_channel_0            ),
        .i_FIFO_read_ready                    ( w_FIFO_read_ready_channel_0      ),
        .o_data_fifo_ready                    ( w_data_fifo_ready_channel_0      ),
        // SRAM Group Merge (Write)
        .o_write_valid                        ( w_write_valid_channel_0          ),
        .i_write_ready                        ( w_write_ready_channel_0          ),
        .o_write_addr                         ( w_write_addr_channel_0           ),
        .o_write_data                         ( w_write_data_channel_0           ),
        .i_FIFO_write_ready                   ( w_FIFO_write_ready_channel_0     )
    );

cmd_decoder_channel_1_in_wrapper #(
        .GROUPS                               ( GROUPS                               ),
        .GROUPS_1                             ( GROUPS_1                             ),
        .GROUPS_2                             ( GROUPS_2                             ),
        .BLOCKS                               ( BLOCKS                               ),
        .BANDWIDTH_CHANNEL_0                  ( BANDWIDTH_CHANNEL_0                  ),
        .BANDWIDTH_CHANNEL_1_IN               ( BANDWIDTH_CHANNEL_1_IN               ),
        .ADDRESS_ROW                          ( ADDRESS_ROW                          ),
        .DESTINATION_ADDR_BIT_CHANNEL_1_IN    ( DESTINATION_ADDR_BIT_CHANNEL_1_IN    )
    ) u_cmd_decoder_channel_1_in_wrapper (
        .i_clk                                ( i_clk                                ),
        .i_rstn                               ( i_rstn                               ),
        // Channel 1_In - Command Decoder
        .i_ch1_in_rw_cmd                     ( i_ch1_in_rw_cmd                     ),
        .i_ch1_in_rw_cmd_valid               ( i_ch1_in_rw_cmd_valid               ),
        .o_ch1_in_rw_cmd_ready               ( o_ch1_in_rw_cmd_ready               ),
        // Top Ctrl
        .o_load_busy_channel_1_in            ( o_load_busy_channel_1_in            ),
        .o_store_busy_channel_1_in           ( o_store_busy_channel_1_in           ),
        // NOC Write Path
        .i_noc_write_ready_channel_1_in      ( i_noc_write_ready_channel_1_in      ),
        .o_noc_write_valid_channel_1_in      ( o_noc_write_valid_channel_1_in      ),
        .o_noc_write_addr_channel_1_in       ( o_noc_write_addr_channel_1_in       ),
        .o_noc_write_data_channel_1_in       ( o_noc_write_data_channel_1_in       ),
        .i_noc_write_response_channel_1_in   ( i_noc_write_response_channel_1_in   ),
        // NOC Read Path
        .o_noc_read_addr_channel_1_in        ( o_noc_read_addr_channel_1_in        ),
        .o_noc_read_valid_channel_1_in       ( o_noc_read_valid_channel_1_in       ),
        .o_noc_read_data_ready_channel_1_in  ( o_noc_read_data_ready_channel_1_in  ),
        .i_noc_read_ready_channel_1_in       ( i_noc_read_ready_channel_1_in       ),
        .i_noc_read_response_channel_1_in    ( i_noc_read_response_channel_1_in    ),
        .i_noc_read_data_channel_1_in        ( i_noc_read_data_channel_1_in        ),
        // Control Modes
        .o_noc_control_mode_channel_1_in     ( o_noc_control_mode_channel_1_in     ),
        .o_sram_control_mode_channel_1_in    ( w_sram_control_mode_channel_1_in    ),
        // SRAM Group Merge (Read)
        .o_read_valid                         ( w_read_valid_channel_1_in           ),
        .i_read_ready                         ( w_read_ready_channel_1_in           ),
        .o_read_addr                          ( w_read_addr_channel_1_in            ),
        .i_read_data                          ( w_read_data_channel_1_in            ),
        .i_FIFO_read_ready                    ( w_FIFO_read_ready_channel_1_in      ),
        .o_data_fifo_ready                    ( w_data_fifo_ready_channel_1_in      ),
        // SRAM Group Merge (Write)
        .o_write_valid                        ( w_write_valid_channel_1_in          ),
        .i_write_ready                        ( w_write_ready_channel_1_in          ),
        .o_write_addr                         ( w_write_addr_channel_1_in           ),
        .o_write_data                         ( w_write_data_channel_1_in           ),
        .i_FIFO_write_ready                   ( w_FIFO_write_ready_channel_1_in     )
    );
    
cmd_decoder_channel_2_in_wrapper #(
        .GROUPS                               ( GROUPS                               ),
        .GROUPS_1                             ( GROUPS_1                             ),
        .GROUPS_2                             ( GROUPS_2                             ),
        .BLOCKS                               ( BLOCKS                               ),
        .BANDWIDTH_CHANNEL_0                  ( BANDWIDTH_CHANNEL_0                  ),
        .BANDWIDTH_CHANNEL_2_IN               ( BANDWIDTH_CHANNEL_2_IN               ),
        .ADDRESS_ROW                          ( ADDRESS_ROW                          ),
        .DESTINATION_ADDR_BIT_CHANNEL_2_IN    ( DESTINATION_ADDR_BIT_CHANNEL_2_IN    )
    ) u_cmd_decoder_channel_2_in_wrapper (
        .i_clk                                ( i_clk                                ),
        .i_rstn                               ( i_rstn                               ),
        // Channel 1_In - Command Decoder
        .i_ch2_in_rw_cmd                     ( i_ch2_in_rw_cmd                     ),
        .i_ch2_in_rw_cmd_valid               ( i_ch2_in_rw_cmd_valid               ),
        .o_ch2_in_rw_cmd_ready               ( o_ch2_in_rw_cmd_ready               ),
        // Top Ctrl
        .o_load_busy_channel_2_in            ( o_load_busy_channel_2_in            ),
        .o_store_busy_channel_2_in           ( o_store_busy_channel_2_in           ),
        // NOC Write Path
        .i_noc_write_ready_channel_2_in      ( i_noc_write_ready_channel_2_in      ),
        .o_noc_write_valid_channel_2_in      ( o_noc_write_valid_channel_2_in      ),
        .o_noc_write_addr_channel_2_in       ( o_noc_write_addr_channel_2_in       ),
        .o_noc_write_data_channel_2_in       ( o_noc_write_data_channel_2_in       ),
        .i_noc_write_response_channel_2_in   ( i_noc_write_response_channel_2_in   ),
        // NOC Read Path
        .o_noc_read_ready_channel_2_in       (o_noc_read_ready_channel_2_in),    
        .i_noc_read_valid_channel_2_in       (i_noc_read_valid_channel_2_in),
        .i_noc_read_addr_channel_2_in        (i_noc_read_addr_channel_2_in),
        .i_noc_read_data_channel_2_in        (i_noc_read_data_channel_2_in),   
        .o_noc_read_response_channel_2_in    (o_noc_read_response_channel_2_in),
        // Control Modes
        .o_noc_control_mode_channel_2_in     ( o_noc_control_mode_channel_2_in     ),
        .o_sram_control_mode_channel_2_in    ( w_sram_control_mode_channel_2_in     ),
        // SRAM Group Merge (Read)
        .o_read_valid                         ( w_read_valid_channel_2_in           ),
        .i_read_ready                         ( w_read_ready_channel_2_in           ),
        .o_read_addr                          ( w_read_addr_channel_2_in            ),
        .i_read_data                          ( w_read_data_channel_2_in            ),
        .i_FIFO_read_ready                    ( w_FIFO_read_ready_channel_2_in      ),
        .o_data_fifo_ready                    ( w_data_fifo_ready_channel_2_in      ),
        // SRAM Group Merge (Write)
        .o_write_valid                        ( w_write_valid_channel_2_in          ),
        .i_write_ready                        ( w_write_ready_channel_2_in          ),
        .o_write_addr                         ( w_write_addr_channel_2_in           ),
        .o_write_data                         ( w_write_data_channel_2_in           ),
        .i_FIFO_write_ready                   ( w_FIFO_write_ready_channel_2_in     )
    );

cmd_decoder_channel_1_wgt_wrapper #(
        .GROUPS                               ( GROUPS                               ),
        .GROUPS_1                             ( GROUPS_1                             ),
        .GROUPS_2                             ( GROUPS_2                             ),
        .BLOCKS                               ( BLOCKS                               ),
        .BANDWIDTH_CHANNEL_0                  ( BANDWIDTH_CHANNEL_0                  ),
        .BANDWIDTH_CHANNEL_1_WGT              ( BANDWIDTH_CHANNEL_1_WGT              ),
        .ADDRESS_ROW                          ( ADDRESS_ROW                          ),
        .DESTINATION_ADDR_BIT_CHANNEL_1_WGT   ( DESTINATION_ADDR_BIT_CHANNEL_1_WGT   )
    ) u_cmd_decoder_channel_1_wgt_wrapper (
        .i_clk                                ( i_clk                                ),
        .i_rstn                               ( i_rstn                               ),
        // Channel 1_Wgt - Command Decoder
        .i_ch1_wgt_rw_cmd                     ( i_ch1_wgt_rw_cmd                     ),
        .i_ch1_wgt_rw_cmd_valid               ( i_ch1_wgt_rw_cmd_valid               ),
        .o_ch1_wgt_rw_cmd_ready               ( o_ch1_wgt_rw_cmd_ready               ),
        // Top Ctrl
        .o_load_busy_channel_1_wgt            ( o_load_busy_channel_1_wgt            ),
        .o_store_busy_channel_1_wgt           ( o_store_busy_channel_1_wgt           ),
        // NOC Write Path
        .i_noc_write_ready_channel_1_wgt      ( i_noc_write_ready_channel_1_wgt      ),
        .o_noc_write_valid_channel_1_wgt      ( o_noc_write_valid_channel_1_wgt      ),
        .o_noc_write_addr_channel_1_wgt       ( o_noc_write_addr_channel_1_wgt       ),
        .o_noc_write_data_channel_1_wgt       ( o_noc_write_data_channel_1_wgt       ),
        .i_noc_write_response_channel_1_wgt   ( i_noc_write_response_channel_1_wgt   ),
        // NOC Read Path
        .o_noc_read_addr_channel_1_wgt        ( o_noc_read_addr_channel_1_wgt        ),
        .o_noc_read_valid_channel_1_wgt       ( o_noc_read_valid_channel_1_wgt       ),
        .o_noc_read_data_ready_channel_1_wgt  ( o_noc_read_data_ready_channel_1_wgt  ),
        .i_noc_read_ready_channel_1_wgt       ( i_noc_read_ready_channel_1_wgt       ),
        .i_noc_read_response_channel_1_wgt    ( i_noc_read_response_channel_1_wgt    ),
        .i_noc_read_data_channel_1_wgt        ( i_noc_read_data_channel_1_wgt        ),
        // Control Modes
        .o_noc_control_mode_channel_1_wgt     ( o_noc_control_mode_channel_1_wgt     ),
        .o_sram_control_mode_channel_1_wgt    ( w_sram_control_mode_channel_1_wgt         ),
        // SRAM Group Merge (Read)
        .o_read_valid                         ( w_read_valid_channel_1_wgt           ),
        .i_read_ready                         ( w_read_ready_channel_1_wgt           ),
        .o_read_addr                          ( w_read_addr_channel_1_wgt            ),
        .i_read_data                          ( w_read_data_channel_1_wgt            ),
        .i_FIFO_read_ready                    ( w_FIFO_read_ready_channel_1_wgt      ),
        .o_data_fifo_ready                    ( w_data_fifo_ready_channel_1_wgt      ),
        // SRAM Group Merge (Write)
        .o_write_valid                        ( w_write_valid_channel_1_wgt          ),
        .i_write_ready                        ( w_write_ready_channel_1_wgt          ),
        .o_write_addr                         ( w_write_addr_channel_1_wgt           ),
        .o_write_data                         ( w_write_data_channel_1_wgt           ),
        .i_FIFO_write_ready                   ( w_FIFO_write_ready_channel_1_wgt     )
    );

cmd_decoder_channel_2_wgt_wrapper #(
        .GROUPS                               ( GROUPS                               ),
        .GROUPS_1                             ( GROUPS_1                             ),
        .GROUPS_2                             ( GROUPS_2                             ),
        .BLOCKS                               ( BLOCKS                               ),
        .BANDWIDTH_CHANNEL_0                  ( BANDWIDTH_CHANNEL_0                  ),
        .BANDWIDTH_CHANNEL_2_WGT              ( BANDWIDTH_CHANNEL_2_WGT              ),
        .ADDRESS_ROW                          ( ADDRESS_ROW                          ),
        .DESTINATION_ADDR_BIT_CHANNEL_2_WGT   ( DESTINATION_ADDR_BIT_CHANNEL_2_WGT   )
    ) u_cmd_decoder_channel_2_wgt_wrapper (
        .i_clk                                ( i_clk                                ),
        .i_rstn                               ( i_rstn                               ),
        // Channel 2_Wgt - Command Decoder
        .i_ch2_wgt_rw_cmd                     ( i_ch2_wgt_rw_cmd                     ),
        .i_ch2_wgt_rw_cmd_valid               ( i_ch2_wgt_rw_cmd_valid               ),
        .o_ch2_wgt_rw_cmd_ready               ( o_ch2_wgt_rw_cmd_ready               ),
        // Top Ctrl
        .o_load_busy_channel_2_wgt            ( o_load_busy_channel_2_wgt            ),

        // NOC Write Path
        .i_noc_write_ready_channel_2_wgt      ( i_noc_write_ready_channel_2_wgt      ),
        .o_noc_write_valid_channel_2_wgt      ( o_noc_write_valid_channel_2_wgt      ),
        .o_noc_write_addr_channel_2_wgt       ( o_noc_write_addr_channel_2_wgt       ),
        .o_noc_write_data_channel_2_wgt       ( o_noc_write_data_channel_2_wgt       ),
        .i_noc_write_response_channel_2_wgt   ( i_noc_write_response_channel_2_wgt   ),
        // Control Modes
        .o_noc_control_mode_channel_2_wgt     ( o_noc_control_mode_channel_2_wgt     ),
        .o_sram_control_mode_channel_2_wgt    ( w_sram_control_mode_channel_2_wgt    ),
        // SRAM Group Merge (Read)
        .o_read_valid                         ( w_read_valid_channel_2_wgt           ),
        .i_read_ready                         ( w_read_ready_channel_2_wgt           ),
        .o_read_addr                          ( w_read_addr_channel_2_wgt            ),
        .i_read_data                          ( w_read_data_channel_2_wgt            ),
        .i_FIFO_read_ready                    ( w_FIFO_read_ready_channel_2_wgt      ),
        .o_data_fifo_ready                    ( w_data_fifo_ready_channel_2_wgt      )
    );

wire [ADDR_BIT_TOTAL_CHANNEL_2_WGT-1:0] w_write_addr_channel_2_wgt [GROUPS-1:0];
wire [BANDWIDTH_CHANNEL_2_WGT-1:0]      w_write_data_channel_2_wgt [GROUPS-1:0];

genvar g;
generate
  for (g=0; g<GROUPS; g=g+1) begin : ZERO_INIT
    assign w_write_addr_channel_2_wgt[g] = '0;
    assign w_write_data_channel_2_wgt[g] = '0;
  end
endgenerate

SRAM_group_merge #( // SRAM_group_merge also correct ctrl together
    .GROUPS                     ( GROUPS ),
    .BLOCKS                     ( BLOCKS ),
    .BANDWIDTH_CHANNEL_0        ( BANDWIDTH_CHANNEL_0 ),
    .BANDWIDTH_CHANNEL_1_IN     ( BANDWIDTH_CHANNEL_1_IN ),
    .BANDWIDTH_CHANNEL_2_IN     ( BANDWIDTH_CHANNEL_2_IN ),
    .BANDWIDTH_CHANNEL_1_WGT    ( BANDWIDTH_CHANNEL_1_WGT ),
    .BANDWIDTH_CHANNEL_2_WGT    ( BANDWIDTH_CHANNEL_2_WGT ),
    .ADDRESS_ROW                ( ADDRESS_ROW )
) u_SRAM_group_merge (
    .i_clk                          ( i_clk ),
    .i_rstn                         ( i_rstn ),
    // channel 0
    .i_read_valid_channel_0        ( w_read_valid_channel_0 ),
    .o_read_ready_channel_0        ( w_read_ready_channel_0 ),
    .i_read_addr_channel_0         ( w_read_addr_channel_0 ),
    .o_read_data_channel_0         ( w_read_data_channel_0 ),
    .i_write_valid_channel_0       ( w_write_valid_channel_0 ),
    .o_write_ready_channel_0       ( w_write_ready_channel_0 ),
    .i_write_addr_channel_0        ( w_write_addr_channel_0 ),
    .i_write_data_channel_0        ( w_write_data_channel_0 ),
    .i_control_mode_channel_0      ( 1'b0 ),
    .o_FIFO_read_ready_channel_0   ( w_FIFO_read_ready_channel_0 ),
    .o_FIFO_write_ready_channel_0  ( w_FIFO_write_ready_channel_0 ),
    .i_data_fifo_ready_channel_0   ( w_data_fifo_ready_channel_0 ),
    // channel 1_in
    .i_read_valid_channel_1_in        ( w_read_valid_channel_1_in ),
    .o_read_ready_channel_1_in        ( w_read_ready_channel_1_in ),
    .i_read_addr_channel_1_in         ( w_read_addr_channel_1_in ),
    .o_read_data_channel_1_in         ( w_read_data_channel_1_in ),
    .i_write_valid_channel_1_in       ( w_write_valid_channel_1_in ),
    .o_write_ready_channel_1_in       ( w_write_ready_channel_1_in ),
    .i_write_addr_channel_1_in        ( w_write_addr_channel_1_in ),
    .i_write_data_channel_1_in        ( w_write_data_channel_1_in ),
    .i_control_mode_channel_1_in      ( w_sram_control_mode_channel_1_in ),
    .o_FIFO_read_ready_channel_1_in   ( w_FIFO_read_ready_channel_1_in ),
    .o_FIFO_write_ready_channel_1_in  ( w_FIFO_write_ready_channel_1_in ),
    .i_data_fifo_ready_channel_1_in   ( w_data_fifo_ready_channel_1_in ),
    // channel 2_in
    .i_read_valid_channel_2_in        ( w_read_valid_channel_2_in ),
    .o_read_ready_channel_2_in        ( w_read_ready_channel_2_in ),
    .i_read_addr_channel_2_in         ( w_read_addr_channel_2_in ),
    .o_read_data_channel_2_in         ( w_read_data_channel_2_in ),
    .i_write_valid_channel_2_in       ( w_write_valid_channel_2_in ),
    .o_write_ready_channel_2_in       ( w_write_ready_channel_2_in ),
    .i_write_addr_channel_2_in        ( w_write_addr_channel_2_in ),
    .i_write_data_channel_2_in        ( w_write_data_channel_2_in ),
    .i_control_mode_channel_2_in      ( w_sram_control_mode_channel_2_in ),
    .o_FIFO_read_ready_channel_2_in   ( w_FIFO_read_ready_channel_2_in ),
    .o_FIFO_write_ready_channel_2_in  ( w_FIFO_write_ready_channel_2_in ),
    .i_data_fifo_ready_channel_2_in   ( w_data_fifo_ready_channel_2_in ),
    // channel 1_wgt
    .i_read_valid_channel_1_wgt        ( w_read_valid_channel_1_wgt),
    .o_read_ready_channel_1_wgt        ( w_read_ready_channel_1_wgt ),
    .i_read_addr_channel_1_wgt         ( w_read_addr_channel_1_wgt ),
    .o_read_data_channel_1_wgt         ( w_read_data_channel_1_wgt ),
    .i_write_valid_channel_1_wgt       ( w_write_valid_channel_1_wgt ),
    .o_write_ready_channel_1_wgt       ( w_write_ready_channel_1_wgt ),
    .i_write_addr_channel_1_wgt        ( w_write_addr_channel_1_wgt ),
    .i_write_data_channel_1_wgt        ( w_write_data_channel_1_wgt ),
    .i_control_mode_channel_1_wgt      ( w_sram_control_mode_channel_1_wgt ),
    .o_FIFO_read_ready_channel_1_wgt   ( w_FIFO_read_ready_channel_1_wgt ),
    .o_FIFO_write_ready_channel_1_wgt  ( w_FIFO_write_ready_channel_1_wgt ),
    .i_data_fifo_ready_channel_1_wgt   ( w_data_fifo_ready_channel_1_wgt ),
    // channel 2_wgt
    .i_read_valid_channel_2_wgt        ( w_read_valid_channel_2_wgt ),
    .o_read_ready_channel_2_wgt        ( w_read_ready_channel_2_wgt ),
    .i_read_addr_channel_2_wgt         ( w_read_addr_channel_2_wgt ),
    .o_read_data_channel_2_wgt         ( w_read_data_channel_2_wgt ),
    .i_write_valid_channel_2_wgt       ( '0  ),
    .o_write_ready_channel_2_wgt       ( ),
    .i_write_addr_channel_2_wgt        ( w_write_addr_channel_2_wgt  ), // '0 (only use for 1D vector), '{default: '0} (not supported depending on compiler type)
    .i_write_data_channel_2_wgt        ( w_write_data_channel_2_wgt  ), 
    .i_control_mode_channel_2_wgt      ( w_sram_control_mode_channel_2_wgt ),
    .o_FIFO_read_ready_channel_2_wgt   ( w_FIFO_read_ready_channel_2_wgt ),
    .o_FIFO_write_ready_channel_2_wgt  ( ),
    .i_data_fifo_ready_channel_2_wgt   ( w_data_fifo_ready_channel_2_wgt )
);

endmodule