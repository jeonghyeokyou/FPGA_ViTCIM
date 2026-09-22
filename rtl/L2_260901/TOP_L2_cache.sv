`timescale 1ns / 1ps

module TOP_L2_cache #(
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
    parameter DESTINATION_ADDR_BIT_CHANNEL_2_WGT  = 9,

    localparam ADDR_BIT_PER_GROUP = $clog2(GROUPS),                                 
    localparam ADDR_BIT_PER_BLOCK = $clog2(BLOCKS),

    localparam ADDR_BIT_IN_BLOCK = $clog2(ADDRESS_ROW),                                
    localparam ADDR_BIT_PER_BLOCK_channel_0 = $clog2(BLOCKS), // same as ADDR_BIT_PER_BLOCK                                     
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
    localparam ADDR_BIT_TOTAL_CHANNEL_2_WGT_GRP = ADDR_BIT_PER_GROUP + ADDR_BIT_TOTAL_CHANNEL_2_WGT
)(
    input  wire        i_clk,
    input  wire        i_rstb,

    ////////////////////// channel 0 //////////////////////
    // AXI interface w/ sram_read_ctrl_axi
    // Read Address Channel (AR)
    input  wire [ADDR_BIT_TOTAL_CHANNEL_0_GRP-1:0]    i_araddr_channel_0,
    input  wire                                       i_arvalid_channel_0,
    output wire                                       o_arready_channel_0,
    input  wire [7:0]                                 i_arlen_channel_0,
    // Read Data Channel (R)
    output wire [BANDWIDTH_CHANNEL_0-1:0]             o_rdata_channel_0, //64
    output wire                                       o_rvalid_channel_0,
    input  wire                                       i_rready_channel_0,
    output wire                                       o_rlast_channel_0,

    // AXI interface w/ sram_write_ctrl_axi
    // Write Address Channel (AW)
    input  wire [ADDR_BIT_TOTAL_CHANNEL_0_GRP-1:0]    i_awaddr_channel_0, //20
    input  wire                                       i_awvalid_channel_0,
    output wire                                       o_awready_channel_0,
    input  wire [7:0]                                 i_awlen_channel_0,
    // Write Data Channel (W)
    input  wire [BANDWIDTH_CHANNEL_0-1:0]             i_wdata_channel_0, //64
    input  wire                                       i_wvalid_channel_0,
    input  wire                                       i_wlast_channel_0,
    output wire                                       o_wready_channel_0,
    // Write Response Channel (B)
    output wire                                       o_bvalid_channel_0,
    input  wire                                       i_bready_channel_0,

    ////////////////////// TOP ctrl interface ////////////////

    input  wire [63:0] i_command,
    input  wire        i_command_valid,
    output wire        o_command_ready,

    ////////////////////// channel 1_In //////////////////////

    // ========== Interface with top_ctrl ==========
    output wire        o_busy_channel_1_in,      
    // ========== Interface with FIFO_interface (NOC Write Path) ========== 
    input  wire                                           i_noc_write_ready_channel_1_in,   
    output wire                                           o_noc_write_valid_channel_1_in,
    output wire [DESTINATION_ADDR_BIT_CHANNEL_1_IN-1:0]   o_noc_write_addr_channel_1_in, //19
    output wire [BANDWIDTH_CHANNEL_1_IN-1:0]              o_noc_write_data_channel_1_in, //512
    input  wire                                           i_noc_write_response_channel_1_in,
    // ========== Interface with FIFO_interface (NOC Read Path) ========== 
    output wire [DESTINATION_ADDR_BIT_CHANNEL_1_IN-1:0]   o_noc_read_addr_channel_1_in, //19
    output wire                                           o_noc_read_valid_channel_1_in, 
    output wire                                           o_noc_read_data_ready_channel_1_in,
    input  wire                                           i_noc_read_ready_channel_1_in,     
    input  wire                                           i_noc_read_response_channel_1_in,        
    input  wire [BANDWIDTH_CHANNEL_1_IN-1:0]              i_noc_read_data_channel_1_in,
    output wire                                           o_noc_control_mode_channel_1_in,

    ////////////////////// channel 2_In //////////////////////

    // ========== Interface with top_ctrl ==========
    output wire        o_busy_channel_2_in,
    // ========== Interface with FIFO_interface (NOC Write Path) ========== 
    input  wire                                           i_noc_write_ready_channel_2_in,   
    output wire                                           o_noc_write_valid_channel_2_in,
    output wire [DESTINATION_ADDR_BIT_CHANNEL_2_IN-1:0]   o_noc_write_addr_channel_2_in, //15
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

    // ========== Interface with top_ctrl ==========
    output wire        o_busy_channel_1_wgt,   
    // ========== Interface with FIFO_interface (NOC Write Path) ========== 
    input  wire                                            i_noc_write_ready_channel_1_wgt,   
    output wire                                            o_noc_write_valid_channel_1_wgt,
    output wire [DESTINATION_ADDR_BIT_CHANNEL_1_WGT-1:0]   o_noc_write_addr_channel_1_wgt, //18
    output wire [BANDWIDTH_CHANNEL_1_WGT-1:0]              o_noc_write_data_channel_1_wgt,
    input  wire                                            i_noc_write_response_channel_1_wgt,
    // ========== Interface with FIFO_interface (NOC Read Path) ========== 
    output wire [DESTINATION_ADDR_BIT_CHANNEL_1_WGT-1:0]   o_noc_read_addr_channel_1_wgt, //18
    output wire                                            o_noc_read_valid_channel_1_wgt, 
    output wire                                            o_noc_read_data_ready_channel_1_wgt,
    input  wire                                            i_noc_read_ready_channel_1_wgt,     
    input  wire                                            i_noc_read_response_channel_1_wgt,        
    input  wire [BANDWIDTH_CHANNEL_1_WGT-1:0]              i_noc_read_data_channel_1_wgt,
    output wire                                            o_noc_control_mode_channel_1_wgt,

    ////////////////////// channel 2_Wgt //////////////////////

    // ========== Interface with top_ctrl ==========
    output wire        o_busy_channel_2_wgt,        
    // ========== Interface with FIFO_interface (NOC Write Path) ========== 
    input  wire                                            i_noc_write_ready_channel_2_wgt,  
    output wire                                            o_noc_write_valid_channel_2_wgt,
    output wire [DESTINATION_ADDR_BIT_CHANNEL_2_WGT-1:0]   o_noc_write_addr_channel_2_wgt, //9
    output wire [BANDWIDTH_CHANNEL_2_WGT-1:0]              o_noc_write_data_channel_2_wgt,
    input  wire                                            i_noc_write_response_channel_2_wgt,
    output wire                                            o_noc_control_mode_channel_2_wgt
);

    ///////////////////// cmd dispatcher intf /////////////

    // ========== Interface with command_decoder ==========
    wire [63:0] i_ch1_in_rw_cmd;       
    wire        i_ch1_in_rw_cmd_valid;
    wire        o_ch1_in_rw_cmd_ready;

    // ========== Interface with command_decoder ==========
    wire [63:0] i_ch2_in_rw_cmd;       
    wire        i_ch2_in_rw_cmd_valid;
    wire        o_ch2_in_rw_cmd_ready;

    // ========== Interface with command_decoder ==========
    wire [63:0] i_ch1_wgt_rw_cmd;       
    wire        i_ch1_wgt_rw_cmd_valid;
    wire        o_ch1_wgt_rw_cmd_ready;

    // ========== Interface with command_decoder ==========
    wire [63:0] i_ch2_wgt_rw_cmd;       
    wire        i_ch2_wgt_rw_cmd_valid;
    wire        o_ch2_wgt_rw_cmd_ready;

    ////////////////////// channel 0 //////////////////////
    // AXI interface w/ sram_read_ctrl_axi
    // Read Address Channel (AR)
    wire [ADDR_BIT_TOTAL_CHANNEL_0_GRP-1:0]    w_araddr_channel_0;
    wire                                       w_arvalid_channel_0;
    wire                                       w_arready_channel_0;
    wire [7:0]                                 w_arlen_channel_0;
    // Read Data Channel (R)
    wire [BANDWIDTH_CHANNEL_0-1:0]             w_rdata_channel_0;
    wire                                       w_rvalid_channel_0;
    wire                                       w_rready_channel_0;
    wire                                       w_rlast_channel_0;

    // AXI interface w/ sram_write_ctrl_axi
    // Write Address Channel (AW)
    wire [ADDR_BIT_TOTAL_CHANNEL_0_GRP-1:0]    w_awaddr_channel_0;
    wire                                       w_awvalid_channel_0;
    wire                                       w_awready_channel_0;
    wire [7:0]                                 w_awlen_channel_0;
    // Write Data Channel (W)
    wire [BANDWIDTH_CHANNEL_0-1:0]             w_wdata_channel_0;
    wire                                       w_wvalid_channel_0;
    wire                                       w_wlast_channel_0;
    wire                                       w_wready_channel_0;
    // Write Response Channel (B)
    wire                                       w_bvalid_channel_0;
    wire                                       w_bready_channel_0;

    assign w_araddr_channel_0  = i_araddr_channel_0;
    assign w_arvalid_channel_0 = i_arvalid_channel_0;
    assign o_arready_channel_0 = w_arready_channel_0;
    assign w_arlen_channel_0   = i_arlen_channel_0;

    assign o_rdata_channel_0   = w_rdata_channel_0;
    assign o_rvalid_channel_0  = w_rvalid_channel_0;
    assign w_rready_channel_0  = i_rready_channel_0;
    assign o_rlast_channel_0   = w_rlast_channel_0;

    assign w_awaddr_channel_0  = i_awaddr_channel_0;
    assign w_awvalid_channel_0 = i_awvalid_channel_0;
    assign o_awready_channel_0 = w_awready_channel_0;
    assign w_awlen_channel_0   = i_awlen_channel_0;

    assign w_wdata_channel_0   = i_wdata_channel_0;
    assign w_wvalid_channel_0  = i_wvalid_channel_0;
    assign w_wlast_channel_0   = i_wlast_channel_0;
    assign o_wready_channel_0  = w_wready_channel_0;
    
    assign o_bvalid_channel_0 = w_bvalid_channel_0;
    assign w_bready_channel_0 = i_bready_channel_0;


    ////////////////////// channel 0 //////////////////////
    // read addr
    wire [ADDR_BIT_TOTAL_CHANNEL_0_GRP-1:0]        w_sram_read_addr_channel_0;
    wire                                           w_sram_read_valid_channel_0;
    wire                                           w_sram_read_ready_channel_0;
    // read data
    wire [BANDWIDTH_CHANNEL_0-1:0]                 w_sram_read_data_channel_0;
    wire                                           w_sram_read_response_channel_0;
    wire                                           w_sram_read_data_ready_channel_0;
    // write operation
    // write data & addr
    wire [ADDR_BIT_TOTAL_CHANNEL_0_GRP-1:0]        w_sram_write_addr_channel_0;
    wire [BANDWIDTH_CHANNEL_0-1:0]                 w_sram_write_data_channel_0;
    wire                                           w_sram_write_valid_channel_0;
    wire                                           w_sram_write_ready_channel_0;


    wire o_load_busy_channel_1_in;
    wire o_store_busy_channel_1_in;
    wire o_load_busy_channel_2_in;
    wire o_store_busy_channel_2_in;
    wire o_load_busy_channel_1_wgt;
    wire o_store_busy_channel_1_wgt;
    wire o_load_busy_channel_2_wgt;

    // top ctrl busy signal
    assign o_busy_channel_1_in  = o_load_busy_channel_1_in || o_store_busy_channel_1_in;
    assign o_busy_channel_2_in  = o_load_busy_channel_2_in || o_store_busy_channel_2_in;
    assign o_busy_channel_1_wgt = o_load_busy_channel_1_wgt|| o_store_busy_channel_1_wgt;
    assign o_busy_channel_2_wgt = o_load_busy_channel_2_wgt;
    
    // -------------------------------------------------------------------------
    //  instance definition
    // -------------------------------------------------------------------------
    sramctrl_channel_0 #(
        .AXI_DATA_WIDTH  ( BANDWIDTH_CHANNEL_0  ),
        .SRAM_DATA_WIDTH ( BANDWIDTH_CHANNEL_0  ),
        .SRAM_ADDR_WIDTH ( ADDR_BIT_TOTAL_CHANNEL_0_GRP ),
        .MOR_DEPTH       ( 4 )
    ) u_sramctrl_channel_0 (
        // Clock & Reset
        .i_clk              ( i_clk              ), 
        .i_rstb             ( i_rstb             ),

        // AXI Read Address Channel (AR)
        .i_araddr           ( w_araddr_channel_0       ),
        .i_arvalid          ( w_arvalid_channel_0      ),
        .o_arready          ( w_arready_channel_0      ),
        .i_arlen            ( w_arlen_channel_0        ),

        // AXI Read Data Channel (R)
        .o_rdata            ( w_rdata_channel_0        ),
        .o_rvalid           ( w_rvalid_channel_0       ),
        .i_rready           ( w_rready_channel_0       ),
        .o_rlast            ( w_rlast_channel_0        ),

        // AXI Write Address Channel (AW)
        .i_awaddr           ( w_awaddr_channel_0       ),
        .i_awvalid          ( w_awvalid_channel_0      ),
        .o_awready          ( w_awready_channel_0      ),
        .i_awlen            ( w_awlen_channel_0        ),

        // AXI Write Data Channel (W)
        .i_wdata            ( w_wdata_channel_0        ),
        .i_wvalid           ( w_wvalid_channel_0       ),
        .i_wlast            ( w_wlast_channel_0        ),
        .o_wready           ( w_wready_channel_0       ),

        // AXI Write Response Channel (B)
        .o_bvalid           ( w_bvalid_channel_0       ),
        .i_bready           ( w_bready_channel_0       ),

        // SRAM Interface - Read Operation
        .o_read_addr        ( w_sram_read_addr_channel_0       ),
        .o_read_addr_valid  ( w_sram_read_valid_channel_0 ),
        .i_read_addr_ready  ( w_sram_read_ready_channel_0 ),
        .i_read_data        ( w_sram_read_data_channel_0       ),
        .i_read_data_valid  ( w_sram_read_response_channel_0 ),
        .o_read_data_ready  ( w_sram_read_data_ready_channel_0 ),

        // SRAM Interface - Write Operation
        .o_write_addr       ( w_sram_write_addr_channel_0      ),
        .o_write_data       ( w_sram_write_data_channel_0      ),
        .o_write_valid      ( w_sram_write_valid_channel_0     ),
        .i_write_ready      ( w_sram_write_ready_channel_0     )
    );

cmd_decoder_SRAM_group_merge #(
        .GROUPS                               ( GROUPS                               ),
        .BLOCKS                               ( BLOCKS                               ),
        .BANDWIDTH_CHANNEL_0                  ( BANDWIDTH_CHANNEL_0                  ),
        .BANDWIDTH_CHANNEL_1_IN               ( BANDWIDTH_CHANNEL_1_IN               ),
        .BANDWIDTH_CHANNEL_2_IN               ( BANDWIDTH_CHANNEL_2_IN               ),
        .BANDWIDTH_CHANNEL_1_WGT              ( BANDWIDTH_CHANNEL_1_WGT              ),
        .BANDWIDTH_CHANNEL_2_WGT              ( BANDWIDTH_CHANNEL_2_WGT              ),
        .ADDRESS_ROW                          ( ADDRESS_ROW                          ),
        .DESTINATION_ADDR_BIT_CHANNEL_0       ( DESTINATION_ADDR_BIT_CHANNEL_0       ),
        .DESTINATION_ADDR_BIT_CHANNEL_1_IN    ( DESTINATION_ADDR_BIT_CHANNEL_1_IN    ),
        .DESTINATION_ADDR_BIT_CHANNEL_2_IN    ( DESTINATION_ADDR_BIT_CHANNEL_2_IN    ),
        .DESTINATION_ADDR_BIT_CHANNEL_1_WGT   ( DESTINATION_ADDR_BIT_CHANNEL_1_WGT   ),
        .DESTINATION_ADDR_BIT_CHANNEL_2_WGT   ( DESTINATION_ADDR_BIT_CHANNEL_2_WGT   )
    ) u_cmd_decoder_SRAM_group_merge (
        .i_clk                                ( i_clk                                ),
        .i_rstn                               ( i_rstb                               ),

        // Channel 0
        .i_sram_read_addr_channel_0         (w_sram_read_addr_channel_0),
        .i_sram_read_valid_channel_0        (w_sram_read_valid_channel_0),
        .o_sram_read_ready_channel_0        (w_sram_read_ready_channel_0),
        .o_sram_read_data_channel_0         (w_sram_read_data_channel_0),
        .o_sram_read_response_channel_0     (w_sram_read_response_channel_0),
        .i_sram_read_data_ready_channel_0   (w_sram_read_data_ready_channel_0),
        .i_sram_write_addr_channel_0        (w_sram_write_addr_channel_0),
        .i_sram_write_data_channel_0        (w_sram_write_data_channel_0),
        .i_sram_write_valid_channel_0       (w_sram_write_valid_channel_0),
        .o_sram_write_ready_channel_0       (w_sram_write_ready_channel_0),

        // Channel 1_In
        .i_ch1_in_rw_cmd                      ( i_ch1_in_rw_cmd                      ),
        .i_ch1_in_rw_cmd_valid                ( i_ch1_in_rw_cmd_valid                ),
        .o_ch1_in_rw_cmd_ready                ( o_ch1_in_rw_cmd_ready                ),
        .o_load_busy_channel_1_in             ( o_load_busy_channel_1_in             ),
        .o_store_busy_channel_1_in            ( o_store_busy_channel_1_in            ),
        .i_noc_write_ready_channel_1_in       ( i_noc_write_ready_channel_1_in       ),
        .o_noc_write_valid_channel_1_in       ( o_noc_write_valid_channel_1_in       ),
        .o_noc_write_addr_channel_1_in        ( o_noc_write_addr_channel_1_in        ),
        .o_noc_write_data_channel_1_in        ( o_noc_write_data_channel_1_in        ),
        .i_noc_write_response_channel_1_in    ( i_noc_write_response_channel_1_in    ),
        .o_noc_read_addr_channel_1_in         ( o_noc_read_addr_channel_1_in         ),
        .o_noc_read_valid_channel_1_in        ( o_noc_read_valid_channel_1_in        ),
        .o_noc_read_data_ready_channel_1_in   ( o_noc_read_data_ready_channel_1_in   ),
        .i_noc_read_ready_channel_1_in        ( i_noc_read_ready_channel_1_in        ),
        .i_noc_read_response_channel_1_in     ( i_noc_read_response_channel_1_in     ),
        .i_noc_read_data_channel_1_in         ( i_noc_read_data_channel_1_in         ),
        .o_noc_control_mode_channel_1_in      ( o_noc_control_mode_channel_1_in      ),

        // Channel 2_In
        .i_ch2_in_rw_cmd                      ( i_ch2_in_rw_cmd                      ),
        .i_ch2_in_rw_cmd_valid                ( i_ch2_in_rw_cmd_valid                ),
        .o_ch2_in_rw_cmd_ready                ( o_ch2_in_rw_cmd_ready                ),
        .o_load_busy_channel_2_in             ( o_load_busy_channel_2_in             ),
        .o_store_busy_channel_2_in            ( o_store_busy_channel_2_in            ),
        .i_noc_write_ready_channel_2_in       ( i_noc_write_ready_channel_2_in       ),
        .o_noc_write_valid_channel_2_in       ( o_noc_write_valid_channel_2_in       ),
        .o_noc_write_addr_channel_2_in        ( o_noc_write_addr_channel_2_in        ),
        .o_noc_write_data_channel_2_in        ( o_noc_write_data_channel_2_in        ),
        .i_noc_write_response_channel_2_in    ( i_noc_write_response_channel_2_in    ),
        .o_noc_read_ready_channel_2_in        ( o_noc_read_ready_channel_2_in        ),
        .i_noc_read_valid_channel_2_in        ( i_noc_read_valid_channel_2_in        ),
        .i_noc_read_addr_channel_2_in         ( i_noc_read_addr_channel_2_in         ),
        .i_noc_read_data_channel_2_in         ( i_noc_read_data_channel_2_in         ),
        .o_noc_read_response_channel_2_in     ( o_noc_read_response_channel_2_in     ),
        .o_noc_control_mode_channel_2_in      ( o_noc_control_mode_channel_2_in      ),

        // Channel 1_Wgt
        .i_ch1_wgt_rw_cmd                     ( i_ch1_wgt_rw_cmd                     ),
        .i_ch1_wgt_rw_cmd_valid               ( i_ch1_wgt_rw_cmd_valid               ),
        .o_ch1_wgt_rw_cmd_ready               ( o_ch1_wgt_rw_cmd_ready               ),
        .o_load_busy_channel_1_wgt            ( o_load_busy_channel_1_wgt            ),
        .o_store_busy_channel_1_wgt           ( o_store_busy_channel_1_wgt           ),
        .i_noc_write_ready_channel_1_wgt      ( i_noc_write_ready_channel_1_wgt      ),
        .o_noc_write_valid_channel_1_wgt      ( o_noc_write_valid_channel_1_wgt      ),
        .o_noc_write_addr_channel_1_wgt       ( o_noc_write_addr_channel_1_wgt       ),
        .o_noc_write_data_channel_1_wgt       ( o_noc_write_data_channel_1_wgt       ),
        .i_noc_write_response_channel_1_wgt   ( i_noc_write_response_channel_1_wgt   ),
        .o_noc_read_addr_channel_1_wgt        ( o_noc_read_addr_channel_1_wgt        ),
        .o_noc_read_valid_channel_1_wgt       ( o_noc_read_valid_channel_1_wgt       ),
        .o_noc_read_data_ready_channel_1_wgt  ( o_noc_read_data_ready_channel_1_wgt  ),
        .i_noc_read_ready_channel_1_wgt       ( i_noc_read_ready_channel_1_wgt       ),
        .i_noc_read_response_channel_1_wgt    ( i_noc_read_response_channel_1_wgt    ),
        .i_noc_read_data_channel_1_wgt        ( i_noc_read_data_channel_1_wgt        ),
        .o_noc_control_mode_channel_1_wgt     ( o_noc_control_mode_channel_1_wgt     ),

        // Channel 2_Wgt
        .i_ch2_wgt_rw_cmd                     ( i_ch2_wgt_rw_cmd                     ),
        .i_ch2_wgt_rw_cmd_valid               ( i_ch2_wgt_rw_cmd_valid               ),
        .o_ch2_wgt_rw_cmd_ready               ( o_ch2_wgt_rw_cmd_ready               ),
        .o_load_busy_channel_2_wgt            ( o_load_busy_channel_2_wgt            ),
        .i_noc_write_ready_channel_2_wgt      ( i_noc_write_ready_channel_2_wgt      ),
        .o_noc_write_valid_channel_2_wgt      ( o_noc_write_valid_channel_2_wgt      ),
        .o_noc_write_addr_channel_2_wgt       ( o_noc_write_addr_channel_2_wgt       ),
        .o_noc_write_data_channel_2_wgt       ( o_noc_write_data_channel_2_wgt       ),
        .i_noc_write_response_channel_2_wgt   ( i_noc_write_response_channel_2_wgt   ),
        .o_noc_control_mode_channel_2_wgt     ( o_noc_control_mode_channel_2_wgt     )
    );

CMD_dispatcher #(
        .DATA_WIDTH             ( 64             ),
        .FIFO_DEPTH             ( 64             )
    ) u_CMD_dispatcher (
        // System
        .i_clk                  ( i_clk                  ),
        .i_rstn                 ( i_rstb                 ),

        // TOP Ctrl Interface
        .i_command              ( i_command              ),
        .i_command_valid        ( i_command_valid        ),
        .o_command_ready        ( o_command_ready        ),

        // Channel 1_In
        .o_ch1_in_rw_cmd        ( i_ch1_in_rw_cmd        ),
        .o_ch1_in_rw_cmd_valid  ( i_ch1_in_rw_cmd_valid  ),
        .i_ch1_in_rw_cmd_ready  ( o_ch1_in_rw_cmd_ready  ),

        // Channel 2_In
        .o_ch2_in_rw_cmd        ( i_ch2_in_rw_cmd        ),
        .o_ch2_in_rw_cmd_valid  ( i_ch2_in_rw_cmd_valid  ),
        .i_ch2_in_rw_cmd_ready  ( o_ch2_in_rw_cmd_ready  ),

        // Channel 1_Wgt
        .o_ch1_wgt_rw_cmd       ( i_ch1_wgt_rw_cmd       ),
        .o_ch1_wgt_rw_cmd_valid ( i_ch1_wgt_rw_cmd_valid ),
        .i_ch1_wgt_rw_cmd_ready ( o_ch1_wgt_rw_cmd_ready ),

        // Channel 2_Wgt
        .o_ch2_wgt_rw_cmd       ( i_ch2_wgt_rw_cmd       ),
        .o_ch2_wgt_rw_cmd_valid ( i_ch2_wgt_rw_cmd_valid ),
        .i_ch2_wgt_rw_cmd_ready ( o_ch2_wgt_rw_cmd_ready )
    );

endmodule