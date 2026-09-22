`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Project: 2605TO - 5nm
// Version: 250731
// Version_log: 1. 250731
// Description: L2 FIFO Interface Top Module
// Designer : Yun HyunJun
//
//////////////////////////////////////////////////////////////////////////////////

module L2_FIFO_interface #(
    parameter ADDR_DEPTH = 2048,
    parameter DATA_WIDTH = 512,
    parameter FIFO_DEPTH = 4,
    parameter INPUT_DELAY = 3,
    localparam ADDR_BW = $clog2(ADDR_DEPTH)
)(
    // global clock, reset
    input clk,
    input rstb,
    //============================================================
    // Top controller (include Address generator) interface
    //============================================================
    // Read port
    input i_read_valid,
    output o_read_ready,
    input [ADDR_BW-1:0]i_read_addr,
    output [DATA_WIDTH-1:0] o_read_data,
    // Write port
    input i_write_valid,
    output o_write_ready,
    input [ADDR_BW-1:0] i_write_addr,
    input [DATA_WIDTH-1:0] i_write_data,
    // Control signal
    input i_control_mode,
    output o_FIFO_read_ready,
    output o_FIFO_write_ready,
    input i_data_fifo_ready,
    //============================================================
    // L2 Cache interface
    //============================================================
    // Read Interface
    output o_read_valid_L2,
    input i_read_ready_L2,
    output [ADDR_BW-1:0] o_read_addr_L2,
    input [DATA_WIDTH-1:0] i_read_data_L2,
    // Write Interface
    output o_write_valid_L2,
    input i_write_ready_L2,
    output [ADDR_BW-1:0] o_write_addr_L2,
    output [DATA_WIDTH-1:0] o_write_data_L2,
    // Control signal
    output o_control_mode
);

wire w_read_ready_hs;
wire [DATA_WIDTH-1:0] w_read_data_hs;
wire w_write_ready_hs;
wire w_read_valid_L2_hs;
wire [ADDR_BW-1:0] w_read_addr_L2_hs;
wire w_write_valid_L2_hs;
wire [ADDR_BW-1:0] w_write_addr_L2_hs;
wire [DATA_WIDTH-1:0] w_write_data_L2_hs;

wire w_read_ready_on_fire;
wire [DATA_WIDTH-1:0] w_read_data_on_fire;
wire w_write_ready_on_fire;
wire w_FIFO_read_ready_on_fire;
wire w_FIFO_write_ready_on_fire;
wire w_read_valid_L2_on_fire;
wire [ADDR_BW-1:0] w_read_addr_L2_on_fire;
wire w_write_valid_L2_on_fire;
wire [ADDR_BW-1:0] w_write_addr_L2_on_fire;
wire [DATA_WIDTH-1:0] w_write_data_L2_on_fire;

reg r_control_mode;

//===============================================================================================
// Data transfer Mode signal registering
always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        r_control_mode <= 1'b0;
    end
    else begin
        r_control_mode <= i_control_mode;
    end
end
//===============================================================================================

//===============================================================================================
// Output assignment, Mux by handshake mode (on fire vs. handshake)
assign o_read_ready = i_control_mode ? w_read_ready_hs : w_read_ready_on_fire;
assign o_read_data = i_control_mode ? w_read_data_hs : w_read_data_on_fire;
assign o_write_ready = i_control_mode ? w_write_ready_hs : w_write_ready_on_fire;
assign o_FIFO_read_ready = i_control_mode ? 1'b1 : w_FIFO_read_ready_on_fire;
assign o_FIFO_write_ready = i_control_mode ? 1'b1 : w_FIFO_write_ready_on_fire;
assign o_read_valid_L2 = i_control_mode ? w_read_valid_L2_hs : w_read_valid_L2_on_fire;
assign o_read_addr_L2 = i_control_mode ? w_read_addr_L2_hs : w_read_addr_L2_on_fire;
assign o_write_valid_L2 = i_control_mode ? w_write_valid_L2_hs : w_write_valid_L2_on_fire;
assign o_write_addr_L2 = i_control_mode ? w_write_addr_L2_hs : w_write_addr_L2_on_fire;
assign o_write_data_L2 = i_control_mode ? w_write_data_L2_hs : w_write_data_L2_on_fire;
assign o_control_mode = r_control_mode;
//===============================================================================================

//===============================================================================================
// Module Instance
L2_FIFO_interface_handshake #(
    .ADDR_DEPTH(ADDR_DEPTH),
    .DATA_WIDTH(DATA_WIDTH)
) UL2_FIFO_interface_handshake (
    .clk(clk),
    .rstb(rstb),
    .i_read_valid(i_read_valid),
    .o_read_ready(w_read_ready_hs),
    .i_read_addr(i_read_addr),
    .o_read_data(w_read_data_hs),
    .i_write_valid(i_write_valid),
    .o_write_ready(w_write_ready_hs),
    .i_write_addr(i_write_addr),
    .i_write_data(i_write_data),
    .i_control_mode(i_control_mode),
    .o_read_valid_L2(w_read_valid_L2_hs),
    .i_read_ready_L2(i_read_ready_L2),
    .o_read_addr_L2(w_read_addr_L2_hs),
    .i_read_data_L2(i_read_data_L2),
    .o_write_valid_L2(w_write_valid_L2_hs),
    .i_write_ready_L2(i_write_ready_L2),
    .o_write_addr_L2(w_write_addr_L2_hs),
    .o_write_data_L2(w_write_data_L2_hs)
);

L2_FIFO_interface_on_fire #(
    .ADDR_DEPTH(ADDR_DEPTH),
    .DATA_WIDTH(DATA_WIDTH),
    .FIFO_DEPTH(FIFO_DEPTH),
    .INPUT_DELAY(INPUT_DELAY)
) UL2_FIFO_interface_on_fire (
    .clk(clk),
    .rstb(rstb),
    .i_read_valid(i_read_valid),
    .o_read_ready(w_read_ready_on_fire),
    .i_read_addr(i_read_addr),
    .o_read_data(w_read_data_on_fire),
    .i_write_valid(i_write_valid),
    .o_write_ready(w_write_ready_on_fire),
    .i_write_addr(i_write_addr),
    .i_write_data(i_write_data),
    .o_FIFO_read_ready(w_FIFO_read_ready_on_fire),
    .o_FIFO_write_ready(w_FIFO_write_ready_on_fire),
    .i_data_fifo_ready(i_data_fifo_ready),
    .i_control_mode(i_control_mode),
    .o_read_valid_L2(w_read_valid_L2_on_fire),
    .i_read_ready_L2(i_read_ready_L2),
    .o_read_addr_L2(w_read_addr_L2_on_fire),
    .i_read_data_L2(i_read_data_L2),
    .o_write_valid_L2(w_write_valid_L2_on_fire),
    .i_write_ready_L2(i_write_ready_L2),
    .o_write_addr_L2(w_write_addr_L2_on_fire),
    .o_write_data_L2(w_write_data_L2_on_fire)
);
//===============================================================================================

endmodule
