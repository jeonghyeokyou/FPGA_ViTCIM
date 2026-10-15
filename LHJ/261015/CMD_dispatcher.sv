`timescale 1ns / 1ps

module CMD_dispatcher #(
   parameter DATA_WIDTH = 64,//command datawidth
   parameter FIFO_DEPTH = 64 //command queue
)(
    input  wire        i_clk,
    input  wire        i_rstn,
    ////////////////////// TOP ctrl interface ///////////// no read, write only w/o addr, w/ data ==> if normal handshake mode, o_FIFO_write_ready_M = 1'b0 
    /// write operation signal (i_write_data_M, i_write_valid_M, o_write_ready_M) ==> exclude o_FIFO_write_ready_M, i_write_addr_M

    input  wire [DATA_WIDTH-1:0] i_command      , //i_write_data_M
    input  wire                  i_command_valid, //i_write_data_M
    output wire                  o_command_ready, //o_write_ready_M  (acting like response signal)

    ////////////////////// channel 1_In //////////////////////
    output wire [63:0] o_ch1_in_rw_cmd,       
    output wire        o_ch1_in_rw_cmd_valid, 
    input  wire        i_ch1_in_rw_cmd_ready,

    ////////////////////// channel 2_In //////////////////////
    output wire [63:0] o_ch2_in_rw_cmd,       
    output wire        o_ch2_in_rw_cmd_valid, 
    input  wire        i_ch2_in_rw_cmd_ready,

    ////////////////////// channel 1_Wgt //////////////////////
    output wire [63:0] o_ch1_wgt_rw_cmd,       
    output wire        o_ch1_wgt_rw_cmd_valid, 
    input  wire        i_ch1_wgt_rw_cmd_ready,

    ////////////////////// channel 2_Wgt //////////////////////
    output wire [63:0] o_ch2_wgt_rw_cmd,       
    output wire        o_ch2_wgt_rw_cmd_valid, 
    input  wire        i_ch2_wgt_rw_cmd_ready
);

wire [DATA_WIDTH-1:0] w_command;
wire                  w_command_ready;
wire                  w_command_valid;
wire [2:0]            cmd_idx;

wire                  w_ch1_in_rw_cmd_valid;
wire                  w_ch1_in_rw_cmd_ready;
wire [DATA_WIDTH-1:0] w_ch1_in_rw_cmd;

wire                  w_ch2_in_rw_cmd_valid;
wire                  w_ch2_in_rw_cmd_ready;
wire [DATA_WIDTH-1:0] w_ch2_in_rw_cmd;

wire                  w_ch1_wgt_rw_cmd_valid;
wire                  w_ch1_wgt_rw_cmd_ready;
wire [DATA_WIDTH-1:0] w_ch1_wgt_rw_cmd;

wire                  w_ch2_wgt_rw_cmd_valid;
wire                  w_ch2_wgt_rw_cmd_ready;
wire [DATA_WIDTH-1:0] w_ch2_wgt_rw_cmd;

assign cmd_idx =         (w_command_valid) ? w_command[62:60] : 3'b0;
assign w_command_ready = (cmd_idx==3'b001 || cmd_idx==3'b010) ?  w_ch1_in_rw_cmd_ready  :
                         (cmd_idx==3'b011 || cmd_idx==3'b100) ?  w_ch2_in_rw_cmd_ready  :
                         (cmd_idx==3'b101 || cmd_idx==3'b110) ?  w_ch1_wgt_rw_cmd_ready :
                         (cmd_idx==3'b111)                    ?  w_ch2_wgt_rw_cmd_ready : 1'b0;

assign w_ch1_in_rw_cmd_valid  = (cmd_idx==3'b001 || cmd_idx==3'b010) ? w_command_valid : 1'b0;
assign w_ch2_in_rw_cmd_valid  = (cmd_idx==3'b011 || cmd_idx==3'b100) ? w_command_valid : 1'b0;
assign w_ch1_wgt_rw_cmd_valid = (cmd_idx==3'b101 || cmd_idx==3'b110) ? w_command_valid : 1'b0;
assign w_ch2_wgt_rw_cmd_valid = (cmd_idx==3'b111)                    ? w_command_valid : 1'b0;

assign w_ch1_in_rw_cmd  = (cmd_idx==3'b001 || cmd_idx==3'b010) ? w_command : 1'b0;
assign w_ch2_in_rw_cmd  = (cmd_idx==3'b011 || cmd_idx==3'b100) ? w_command : 1'b0;
assign w_ch1_wgt_rw_cmd = (cmd_idx==3'b101 || cmd_idx==3'b110) ? w_command : 1'b0;
assign w_ch2_wgt_rw_cmd = (cmd_idx==3'b111)                    ? w_command : 1'b0;

///// instance call /////
FIFO #(
        .DATA_WIDTH     ( DATA_WIDTH     ),
        .FIFO_DEPTH     ( FIFO_DEPTH     )
    ) u_command_queue (
        // Clock & Reset
        .i_clk          ( i_clk          ),
        .i_rstn         ( i_rstn         ),
        // Push Interface
        .o_input_ready  ( o_command_ready  ),
        .i_input_valid  ( i_command_valid  ),
        .i_input_data   ( i_command        ),
        // Pop Interface
        .i_output_ready ( w_command_ready ),
        .o_output_valid ( w_command_valid ),
        .o_output_data  ( w_command  )
    );

skid_buffer #(
        .DATA_WIDTH     ( DATA_WIDTH     )
    ) u_command_buffer_channel_1_in (    
        // System
        .i_clk          ( i_clk          ),
        .i_rstb         ( i_rstn         ),
        // Slave interface (input) //input
        .i_s_valid      ( w_ch1_in_rw_cmd_valid ),
        .o_s_ready      ( w_ch1_in_rw_cmd_ready ),
        .i_s_data       ( w_ch1_in_rw_cmd       ),
        // Master interface (output) //output
        .o_m_valid      ( o_ch1_in_rw_cmd_valid ),
        .i_m_ready      ( i_ch1_in_rw_cmd_ready ),
        .o_m_data       ( o_ch1_in_rw_cmd       )
    );

skid_buffer #(
        .DATA_WIDTH     ( DATA_WIDTH     )
    ) u_command_buffer_channel_2_in (    
        // System
        .i_clk          ( i_clk          ),
        .i_rstb         ( i_rstn         ),
        // Slave interface (input) //input
        .i_s_valid      ( w_ch2_in_rw_cmd_valid ),
        .o_s_ready      ( w_ch2_in_rw_cmd_ready ),
        .i_s_data       ( w_ch2_in_rw_cmd       ),
        // Master interface (output) //output
        .o_m_valid      ( o_ch2_in_rw_cmd_valid ),
        .i_m_ready      ( i_ch2_in_rw_cmd_ready ),
        .o_m_data       ( o_ch2_in_rw_cmd       )
    );

skid_buffer #(
        .DATA_WIDTH     ( DATA_WIDTH     )
    ) u_command_buffer_channel_1_wgt (    
        // System
        .i_clk          ( i_clk          ),
        .i_rstb         ( i_rstn         ),
        // Slave interface (input) //input
        .i_s_valid      ( w_ch1_wgt_rw_cmd_valid ),
        .o_s_ready      ( w_ch1_wgt_rw_cmd_ready ),
        .i_s_data       ( w_ch1_wgt_rw_cmd       ),
        // Master interface (output) //output
        .o_m_valid      ( o_ch1_wgt_rw_cmd_valid ),
        .i_m_ready      ( i_ch1_wgt_rw_cmd_ready ),
        .o_m_data       ( o_ch1_wgt_rw_cmd       )
    );

skid_buffer #(
        .DATA_WIDTH     ( DATA_WIDTH     )
    ) u_command_buffer_channel_2_wgt (    
        // System
        .i_clk          ( i_clk          ),
        .i_rstb         ( i_rstn         ),
        // Slave interface (input) //input
        .i_s_valid      ( w_ch2_wgt_rw_cmd_valid ),
        .o_s_ready      ( w_ch2_wgt_rw_cmd_ready ),
        .i_s_data       ( w_ch2_wgt_rw_cmd       ),
        // Master interface (output) //output
        .o_m_valid      ( o_ch2_wgt_rw_cmd_valid ),
        .i_m_ready      ( i_ch2_wgt_rw_cmd_ready ),
        .o_m_data       ( o_ch2_wgt_rw_cmd       )
    );

endmodule