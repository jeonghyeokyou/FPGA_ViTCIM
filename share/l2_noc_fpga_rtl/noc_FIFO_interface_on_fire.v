`timescale 1ns / 1ps
// =====================================================================
//  RENAMED copy (original: rtl/NOC_260902/FIFO_interface_on_fire.v)
//  module FIFO_interface_on_fire -> noc_FIFO_interface_on_fire
//  (collides with L2_260901/FIFO_interface_on_fire.sv).
//  Internal `FIFO` instances -> `noc_FIFO` (see rename/noc_FIFO.v).
// =====================================================================

module noc_FIFO_interface_on_fire #(
   parameter ADDR_DEPTH = 1600,
   parameter DATA_WIDTH = 512,
   parameter FIFO_DEPTH = 8,
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
    // control signal
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
    output o_data_fifo_ready_S
);

wire w_input_ready_addr;
wire w_input_valid_addr;
wire [ADDR_BW-1:0] w_input_data_addr;
wire w_output_ready_addr;
wire w_output_valid_addr;
wire [ADDR_BW-1:0] w_output_data_addr;
wire w_input_ready_data;
wire w_input_valid_data;
wire [DATA_WIDTH-1:0] w_input_data_data;
wire w_output_ready_data;
wire w_output_valid_data;
wire [DATA_WIDTH-1:0] w_output_data_data;

reg r_write_ready;

reg r_read_signal, r_write_signal;

//===============================================================================================
// Read/Write Mux signal Latch Logic
always @(posedge clk or negedge rstb) begin
   if (!rstb) begin
       r_read_signal <= 1'b0;
   end
   else begin
       if (i_control_mode == 1'b0) begin
           if (i_read_valid_M == 1'b1) begin
               r_read_signal <= 1'b1;
           end
           else begin
               if (i_write_valid_M == 1'b1) begin
                   r_read_signal <= 1'b0;
               end
               else begin
                   r_read_signal <= r_read_signal;
               end
           end
       end
       else begin
           r_read_signal <= 1'b0;
       end
   end
end

always @(posedge clk or negedge rstb) begin
   if (!rstb) begin
       r_write_signal <= 1'b0;
   end
   else begin
       if (i_control_mode == 1'b0) begin
           if (i_write_valid_M == 1'b1) begin
               r_write_signal <= 1'b1;
           end
           else begin
               if (i_read_valid_M == 1'b1) begin
                   r_write_signal <= 1'b0;
               end
               else begin
                   r_write_signal <= r_write_signal;
               end
           end
       end
       else begin
           r_write_signal <= 1'b0;
       end
   end
end
//===============================================================================================

//===============================================================================================
// Mux Logic - Address FIFO
assign w_input_valid_addr = (i_control_mode == 1'b0) ? (i_read_valid_M || i_write_valid_M) : 1'b0;
assign w_input_data_addr = (i_read_valid_M) ? i_read_addr_M : ((i_write_valid_M) ? i_write_addr_M : {(ADDR_BW){1'b0}});
assign w_output_ready_addr = (r_read_signal) ? i_FIFO_read_ready_S : ((r_write_signal) ? (w_output_valid_addr && w_output_valid_data && i_FIFO_write_ready_S) : 1'b0);

// Mux Logic - Data FIFO
assign w_input_valid_data = (i_control_mode == 1'b0) ? (i_read_ready_S || i_write_valid_M) : 1'b0;
assign w_input_data_data = (r_read_signal) ? i_read_data_S : ((i_write_valid_M) ? i_write_data_M : {(DATA_WIDTH){1'b0}});
assign w_output_ready_data = (r_read_signal) ? i_data_fifo_ready_M : ((r_write_signal) ? (w_output_valid_addr && w_output_valid_data && i_FIFO_write_ready_S) : 1'b0);

// Mux Logic - FIFO Slave Intf
assign o_read_valid_S = (r_read_signal) ? w_output_valid_addr : 1'b0;
assign o_read_addr_S = w_output_data_addr;
assign o_write_valid_S = (r_write_signal) ? (w_output_valid_addr && w_output_valid_data) : 1'b0;
assign o_write_addr_S = w_output_data_addr;
assign o_write_data_S = w_output_data_data;
assign o_data_fifo_ready_S = w_input_ready_data;

// Mux Logic - FIFO Master Intf
assign o_read_ready_M = (r_read_signal) ? w_output_valid_data : 1'b0;
assign o_read_data_M = w_output_data_data;
assign o_write_ready_M = r_write_ready;
assign o_FIFO_read_ready_M = w_input_ready_addr;
assign o_FIFO_write_ready_M = w_input_ready_addr && w_input_ready_data;
//===============================================================================================

//===============================================================================================
// Registered write ready signal
always @(posedge clk or negedge rstb) begin
  if (!rstb) begin
      r_write_ready <= 1'b0;
  end
  else begin
      r_write_ready <= i_write_ready_S;
  end
end
//===============================================================================================

//===============================================================================================
// Module Instance
noc_FIFO #(
  .DATA_WIDTH(ADDR_BW),
  .FIFO_DEPTH(FIFO_DEPTH)
) UFIFO_ADDR (
  .i_clk(clk),
  .i_rstn(rstb),
  .o_input_ready(w_input_ready_addr),
  .i_input_valid(w_input_valid_addr),
  .i_input_data(w_input_data_addr),
  .i_output_ready(w_output_ready_addr),
  .o_output_valid(w_output_valid_addr),
  .o_output_data(w_output_data_addr)
);

noc_FIFO #(
  .DATA_WIDTH(DATA_WIDTH),
  .FIFO_DEPTH(FIFO_DEPTH)
) UFIFO_DATA (
  .i_clk(clk),
  .i_rstn(rstb),
  .o_input_ready(w_input_ready_data),
  .i_input_valid(w_input_valid_data),
  .i_input_data(w_input_data_data),
  .i_output_ready(w_output_ready_data),
  .o_output_valid(w_output_valid_data),
  .o_output_data(w_output_data_data)
);
//===============================================================================================

endmodule
