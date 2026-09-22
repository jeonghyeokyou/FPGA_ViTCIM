`timescale 1ns / 1ps
// =====================================================================
//  RENAMED copy (original: rtl/NOC_260902/FIFO_interface.v)
//  module FIFO_interface -> noc_FIFO_interface
//  (collides with L2_260901/FIFO_interface.sv - different ports).
//  Internal instances -> noc_FIFO_interface_on_fire / noc_FIFO_interface_handshake.
// =====================================================================

module noc_FIFO_interface #(
   parameter ADDR_DEPTH = 1600,
   parameter DATA_WIDTH = 512,
   parameter FIFO_DEPTH = 4,
   localparam ADDR_BW = $clog2(ADDR_DEPTH)
)(
    // global clock, reset
    input clk,
    input rstb,
    //============================================================
    // FIFO Master Port
    //============================================================
    // Read port
    input i_read_valid_M,
    output o_read_ready_M,
    input [ADDR_BW-1:0]i_read_addr_M,
    output [DATA_WIDTH-1:0] o_read_data_M,
    // Write port
    input i_write_valid_M,
    output o_write_ready_M,
    input [ADDR_BW-1:0] i_write_addr_M,
    input [DATA_WIDTH-1:0] i_write_data_M,
    // FIFO signal
    output o_FIFO_read_ready_M,
    output o_FIFO_write_ready_M,
    input i_data_fifo_ready_M,
    // Control signal
    input i_control_mode,
    //============================================================
    // FIFO Slave Port
    //============================================================
    // Read Interface
    output o_read_valid_S,
    input i_read_ready_S,
    output [ADDR_BW-1:0] o_read_addr_S,
    input [DATA_WIDTH-1:0] i_read_data_S,
    // Write Interface
    output o_write_valid_S,
    input i_write_ready_S,
    output [ADDR_BW-1:0] o_write_addr_S,
    output [DATA_WIDTH-1:0] o_write_data_S,
    // FIFO signal
    input i_FIFO_read_ready_S,
    input i_FIFO_write_ready_S,
    output o_data_fifo_ready_S,
    // Control signal
    output o_control_mode
);

wire w_read_ready_hs;
wire [DATA_WIDTH-1:0] w_read_data_hs;
wire w_write_ready_hs;
wire w_read_valid_hs;
wire [ADDR_BW-1:0] w_read_addr_hs;
wire w_write_valid_hs;
wire [ADDR_BW-1:0] w_write_addr_hs;
wire [DATA_WIDTH-1:0] w_write_data_hs;

wire w_read_ready_on_fire;
wire [DATA_WIDTH-1:0] w_read_data_on_fire;
wire w_write_ready_on_fire;
wire w_FIFO_read_ready_on_fire;
wire w_FIFO_write_ready_on_fire;
wire w_read_valid_on_fire;
wire [ADDR_BW-1:0] w_read_addr_on_fire;
wire w_write_valid_on_fire;
wire [ADDR_BW-1:0] w_write_addr_on_fire;
wire [DATA_WIDTH-1:0] w_write_data_on_fire;
wire w_data_fifo_ready_on_fire;

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
assign o_read_ready_M = i_control_mode ? w_read_ready_hs : w_read_ready_on_fire;
assign o_read_data_M = i_control_mode ? w_read_data_hs : w_read_data_on_fire;
assign o_write_ready_M = i_control_mode ? w_write_ready_hs : w_write_ready_on_fire;
assign o_FIFO_read_ready_M = i_control_mode ? 1'b0 : w_FIFO_read_ready_on_fire;
assign o_FIFO_write_ready_M = i_control_mode ? 1'b0 : w_FIFO_write_ready_on_fire;
assign o_read_valid_S = i_control_mode ? w_read_valid_hs : w_read_valid_on_fire;
assign o_read_addr_S = i_control_mode ? w_read_addr_hs : w_read_addr_on_fire;
assign o_write_valid_S = i_control_mode ? w_write_valid_hs : w_write_valid_on_fire;
assign o_write_addr_S = i_control_mode ? w_write_addr_hs : w_write_addr_on_fire;
assign o_write_data_S = i_control_mode ? w_write_data_hs : w_write_data_on_fire;
assign o_data_fifo_ready_S = i_control_mode ? 1'b0 : w_data_fifo_ready_on_fire;
assign o_control_mode = r_control_mode;
//===============================================================================================

//===============================================================================================
// Module Instance
noc_FIFO_interface_on_fire #(
    .ADDR_DEPTH(ADDR_DEPTH),
    .DATA_WIDTH(DATA_WIDTH),
    .FIFO_DEPTH(FIFO_DEPTH)
) UFIFO_interface_on_fire (
    .clk(clk),
    .rstb(rstb),
    .i_read_valid_M(i_read_valid_M),
    .o_read_ready_M(w_read_ready_on_fire),
    .i_read_addr_M(i_read_addr_M),
    .o_read_data_M(w_read_data_on_fire),
    .i_write_valid_M(i_write_valid_M),
    .o_write_ready_M(w_write_ready_on_fire),
    .i_write_addr_M(i_write_addr_M),
    .i_write_data_M(i_write_data_M),
    .o_FIFO_read_ready_M(w_FIFO_read_ready_on_fire),
    .o_FIFO_write_ready_M(w_FIFO_write_ready_on_fire),
    .i_data_fifo_ready_M(i_data_fifo_ready_M),
    .i_control_mode(i_control_mode),
    .o_read_valid_S(w_read_valid_on_fire),
    .i_read_ready_S(i_read_ready_S),
    .o_read_addr_S(w_read_addr_on_fire),
    .i_read_data_S(i_read_data_S),
    .o_write_valid_S(w_write_valid_on_fire),
    .i_write_ready_S(i_write_ready_S),
    .o_write_addr_S(w_write_addr_on_fire),
    .o_write_data_S(w_write_data_on_fire),
    .i_FIFO_read_ready_S(i_FIFO_read_ready_S),
    .i_FIFO_write_ready_S(i_FIFO_write_ready_S),
    .o_data_fifo_ready_S(w_data_fifo_ready_on_fire)
);

noc_FIFO_interface_handshake #(
    .ADDR_DEPTH(ADDR_DEPTH),
    .DATA_WIDTH(DATA_WIDTH)
) UFIFO_interface_handshake (
    .clk(clk),
    .rstb(rstb),
    .i_read_valid_M(i_read_valid_M),
    .o_read_ready_M(w_read_ready_hs),
    .i_read_addr_M(i_read_addr_M),
    .o_read_data_M(w_read_data_hs),
    .i_write_valid_M(i_write_valid_M),
    .o_write_ready_M(w_write_ready_hs),
    .i_write_addr_M(i_write_addr_M),
    .i_write_data_M(i_write_data_M),
    .i_control_mode(i_control_mode),
    .o_read_valid_S(w_read_valid_hs),
    .i_read_ready_S(i_read_ready_S),
    .o_read_addr_S(w_read_addr_hs),
    .i_read_data_S(i_read_data_S),
    .o_write_valid_S(w_write_valid_hs),
    .i_write_ready_S(i_write_ready_S),
    .o_write_addr_S(w_write_addr_hs),
    .o_write_data_S(w_write_data_hs)
);
//===============================================================================================

endmodule
