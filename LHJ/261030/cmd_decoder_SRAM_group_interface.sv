`timescale 1ns / 1ps

module cmd_decoder_SRAM_group_interface #(
    parameter  ADDR_BIT_TOTAL = 18,                                     // total address bit
    parameter  BANDWIDTH      = 256,
    parameter  GROUPS         = 4,
    parameter  FIFO_DEPTH     = 4,
    localparam ADDR_DEPTH      = 2 **ADDR_BIT_TOTAL,
    localparam ADDR_BIT_PER_GROUP = $clog2(GROUPS),                     // grp address bit
    localparam ADDR_BIT_IN_GROUP  = ADDR_BIT_TOTAL - ADDR_BIT_PER_GROUP // address bit to SRAM
)(
    /// Global signal
    input  wire        i_clk,
    input  wire        i_rstn,

    /// SRAM read port
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

    /// SRAM write port
    /// interface w/ cmd_decoder
    input  wire [ADDR_BIT_TOTAL-1:0] i_sram_write_addr,
    input  wire                      i_sram_write_valid,
    input  wire [BANDWIDTH-1:0]      i_sram_write_data,
    output wire                      o_sram_write_ready,
    output wire                      o_sram_write_response,
    /// interface w/ SRAM_group_merge
    output wire [GROUPS-1:0]            o_write_valid,
    input  wire [GROUPS-1:0]            i_write_ready,
    output wire [ADDR_BIT_IN_GROUP-1:0] o_write_addr          [GROUPS-1:0],
    output wire [BANDWIDTH-1:0]         o_write_data          [GROUPS-1:0],
    input  wire [GROUPS-1:0]            i_FIFO_write_ready,

    // handshake control signal
    input  wire                     i_control_mode
);

    // FIFO Master Port (Upstream interface)
    // Read
    wire                      w_read_valid_M;
    wire                      w_read_ready_M;
    wire [ADDR_BIT_TOTAL-1:0] w_read_addr_M;
    wire [BANDWIDTH     -1:0] w_read_data_M;
    // Write
    wire                      w_write_valid_M;
    wire                      w_write_ready_M;
    wire [ADDR_BIT_TOTAL-1:0] w_write_addr_M;
    wire [BANDWIDTH     -1:0] w_write_data_M;
    // FIFO & Control
    wire                      w_FIFO_read_ready_M;
    wire                      w_FIFO_write_ready_M;
    wire                      w_data_fifo_ready_M;
    wire                      w_control_mode_M;
    //
    assign w_read_addr_M        = i_sram_read_addr;
    assign w_read_valid_M       = i_sram_read_valid;
    assign o_sram_read_ready    = w_FIFO_read_ready_M;
    assign w_data_fifo_ready_M  = i_sram_read_data_ready;
    assign o_sram_read_response = w_read_ready_M;
    assign o_sram_read_data     = w_read_data_M;
    assign w_control_mode_M     = i_control_mode; 
    //
    assign w_write_addr_M      = i_sram_write_addr;
    assign w_write_valid_M     = i_sram_write_valid;
    assign w_write_data_M      = i_sram_write_data;
    assign o_sram_write_ready  = w_FIFO_write_ready_M;
    assign o_sram_write_response = w_write_ready_M;

    // FIFO Slave Port (Downstream interface)
    // Read
    wire                      w_read_valid_S;
    wire                      w_read_ready_S;
    wire [ADDR_BIT_TOTAL-1:0] w_read_addr_S;
    wire [BANDWIDTH     -1:0] w_read_data_S;
    // Write
    wire                      w_write_valid_S;
    wire                      w_write_ready_S;
    wire [ADDR_BIT_TOTAL-1:0] w_write_addr_S;
    wire [BANDWIDTH     -1:0] w_write_data_S;
    // FIFO & Control
    wire                      w_FIFO_read_ready_S;
    wire                      w_FIFO_write_ready_S;
    wire                      w_data_fifo_ready_S;
    wire                      w_control_mode_S;

    /// interface w/ SRAM_group_merge
    wire [GROUPS-1:0]              w_o_read_valid; 
    wire [GROUPS-1:0]              w_i_read_ready;
    wire [ADDR_BIT_IN_GROUP-1:0]   w_o_read_addr         [GROUPS-1:0];
    wire [BANDWIDTH-1:0]           w_i_read_data         [GROUPS-1:0]; 
    wire [GROUPS-1:0]              w_i_FIFO_read_ready;
    wire [GROUPS-1:0]              w_o_data_fifo_ready;
    /// interface w/ SRAM_group_merge
    wire [GROUPS-1:0]              w_o_write_valid;
    wire [GROUPS-1:0]              w_i_write_ready;
    wire [ADDR_BIT_IN_GROUP-1:0]   w_o_write_addr        [GROUPS-1:0];
    wire [BANDWIDTH-1:0]           w_o_write_data        [GROUPS-1:0];
    wire [GROUPS-1:0]              w_i_FIFO_write_ready;

    assign o_read_valid         = w_o_read_valid;
    assign w_i_read_ready       = i_read_ready;
    assign o_read_addr          = w_o_read_addr;
    assign w_i_read_data        = i_read_data;
    assign w_i_FIFO_read_ready  = i_FIFO_read_ready;
    assign o_data_fifo_ready    = w_o_data_fifo_ready;
    assign o_write_valid        = w_o_write_valid;
    assign w_i_write_ready      = i_write_ready;
    assign o_write_addr         = w_o_write_addr;
    assign o_write_data         = w_o_write_data;
    assign w_i_FIFO_write_ready = i_FIFO_write_ready;

/// Module instantiation (FIFO, cmd_dec_read_intf, cmd_dec_write_intf)
cmd_decoder_SRAM_group_read_interface #(
        .ADDR_BIT_TOTAL ( ADDR_BIT_TOTAL ),
        .BANDWIDTH      ( BANDWIDTH      ),
        .GROUPS         ( GROUPS         )
    ) u_cmd_decoder_SRAM_group_read_interface (
        /// Global signal
        .i_clk                  ( i_clk                  ),
        .i_rstn                 ( i_rstn                 ),
        /// Interface w/ cmd_decoder
        .i_sram_read_addr       ( w_read_addr_S       ),
        .i_sram_read_valid      ( w_read_valid_S      ),
        .o_sram_read_ready      ( w_FIFO_read_ready_S ),
        .i_sram_read_data_ready ( w_data_fifo_ready_S ),
        .o_sram_read_response   ( w_read_ready_S      ),
        .o_sram_read_data       ( w_read_data_S       ),
        /// Interface w/ SRAM_group_merge
        .o_read_valid           ( w_o_read_valid           ),
        .i_read_ready           ( w_i_read_ready           ),
        .o_read_addr            ( w_o_read_addr            ),
        .i_read_data            ( w_i_read_data            ),
        .i_FIFO_read_ready      ( w_i_FIFO_read_ready      ),
        .o_data_fifo_ready      ( w_o_data_fifo_ready      ),
        // Handshake control signal
        .i_control_mode         ( w_control_mode_S         ) 
    );

cmd_decoder_SRAM_group_write_interface #(
        .ADDR_BIT_TOTAL ( ADDR_BIT_TOTAL ),
        .BANDWIDTH      ( BANDWIDTH      ),
        .GROUPS         ( GROUPS         )
    ) u_cmd_decoder_SRAM_group_write_interface (
        /// Global signal
        .i_clk                  ( i_clk                  ), // input
        .i_rstn                 ( i_rstn                 ), // input
        /// Interface w/ cmd_decoder
        .i_sram_write_addr      ( w_write_addr_S      ), // input 
        .i_sram_write_valid     ( w_write_valid_S     ), // input
        .i_sram_write_data      ( w_write_data_S      ), // input  
        .o_sram_write_ready     ( w_FIFO_write_ready_S), // output
        .o_sram_write_response  ( w_write_ready_S     ), // output
        /// Interface w/ SRAM_group_merge
        .o_write_valid          ( w_o_write_valid          ), // output 
        .i_write_ready          ( w_i_write_ready          ), // input  
        // Unpacked Array Ports
        .o_write_addr           ( w_o_write_addr           ), // output 
        .o_write_data           ( w_o_write_data           ), // output 
        .i_FIFO_write_ready     ( w_i_FIFO_write_ready     ), // input  
        // Handshake control signal
        .i_control_mode         ( w_control_mode_S         )  // input
    );

FIFO_interface #(
        .ADDR_DEPTH     ( ADDR_DEPTH ),
        .DATA_WIDTH     ( BANDWIDTH ),
        .FIFO_DEPTH     ( FIFO_DEPTH )
) u_FIFO_interface (
        // Global
        .clk                    ( i_clk                ), // input
        .rstb                   ( i_rstn               ), // input
        //============================================================
        // FIFO Master Port (Upstream)
        //============================================================
        // Read port
        .i_read_valid_M         ( w_read_valid_M       ), // input
        .o_read_ready_M         ( w_read_ready_M       ), // output
        .i_read_addr_M          ( w_read_addr_M        ), // input  [ADDR_BW-1:0]
        .o_read_data_M          ( w_read_data_M        ), // output [DATA_WIDTH-1:0]
        // Write port
        .i_write_valid_M        ( w_write_valid_M      ), // input
        .o_write_ready_M        ( w_write_ready_M      ), // output
        .i_write_addr_M         ( w_write_addr_M       ), // input  [ADDR_BW-1:0]
        .i_write_data_M         ( w_write_data_M       ), // input  [DATA_WIDTH-1:0]
        // FIFO signal
        .o_FIFO_read_ready_M    ( w_FIFO_read_ready_M  ), // output
        .o_FIFO_write_ready_M   ( w_FIFO_write_ready_M ), // output
        .i_data_fifo_ready_M    ( w_data_fifo_ready_M  ), // input
        // Control signal
        .i_control_mode         ( w_control_mode_M     ), // input
        //============================================================
        // FIFO Slave Port (Downstream)
        //============================================================
        // Read Interface
        .o_read_valid_S         ( w_read_valid_S       ), // output
        .i_read_ready_S         ( w_read_ready_S       ), // input
        .o_read_addr_S          ( w_read_addr_S        ), // output [ADDR_BW-1:0]
        .i_read_data_S          ( w_read_data_S        ), // input  [DATA_WIDTH-1:0]
        // Write Interface
        .o_write_valid_S        ( w_write_valid_S      ), // output
        .i_write_ready_S        ( w_write_ready_S      ), // input
        .o_write_addr_S         ( w_write_addr_S       ), // output [ADDR_BW-1:0]
        .o_write_data_S         ( w_write_data_S       ), // output [DATA_WIDTH-1:0]
        // FIFO signal
        .i_FIFO_read_ready_S    ( w_FIFO_read_ready_S  ), // input
        .i_FIFO_write_ready_S   ( w_FIFO_write_ready_S ), // input
        .o_data_fifo_ready_S    ( w_data_fifo_ready_S  ), // output
        // Control signal
        .o_control_mode         ( w_control_mode_S     )  // output
    );
   
endmodule