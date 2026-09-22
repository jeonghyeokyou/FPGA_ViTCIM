`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Project: 2605TO - 5nm
// Version: 250805
// Version_log: 1. 250805
// Description: FIFO Interface Top Module with lower Interface and SRAM Cache (Merge)
// Designer : Yun HyunJun
//
//////////////////////////////////////////////////////////////////////////////////

module FIFO_intf #(
   parameter ADDR_DEPTH = 1600,
   parameter DATA_WIDTH = 512,
   parameter MEMORY_BITWIDTH = 128,
   parameter FIFO_DEPTH = 8,
   parameter INPUT_DELAY = 3,
   localparam ADDR_BW = $clog2(ADDR_DEPTH)
)(
   // global clock, reset
   input clk,
   input rstb,
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
   input i_data_fifo_ready
);

wire w_read_valid_prime;
wire w_read_ready_prime;
wire [ADDR_BW-1:0] w_read_addr_prime;
wire [DATA_WIDTH-1:0] w_read_data_prime;
wire w_write_valid_prime;
wire w_write_ready_prime;
wire [ADDR_BW-1:0] w_write_addr_prime;
wire [DATA_WIDTH-1:0] w_write_data_prime;
wire w_control_mode_prime;
wire w_FIFO_read_ready_prime;
wire w_FIFO_write_ready_prime;
wire w_data_fifo_ready_prime;

wire w_control_mode;
wire w_read_valid;
wire w_read_ready;
wire [ADDR_BW-1:0] w_read_addr;
wire [DATA_WIDTH-1:0] w_read_data;
wire w_write_valid;
wire w_write_ready;
wire [ADDR_BW-1:0] w_write_addr;
wire [DATA_WIDTH-1:0] w_write_data;

//===============================================================================================
// Module Instance
FIFO_interface #(
    .ADDR_DEPTH(ADDR_DEPTH),
    .DATA_WIDTH(DATA_WIDTH),
    .MEMORY_BITWIDTH(MEMORY_BITWIDTH),
    .FIFO_DEPTH(FIFO_DEPTH)
) UFIFO_interface (
    .clk(clk),
    .rstb(rstb),
    .i_read_valid_M(i_read_valid),
    .o_read_ready_M(o_read_ready),
    .i_read_addr_M(i_read_addr),
    .o_read_data_M(o_read_data),
    .i_write_valid_M(i_write_valid),
    .o_write_ready_M(o_write_ready),
    .i_write_addr_M(i_write_addr),
    .i_write_data_M(i_write_data),
    .o_FIFO_read_ready_M(o_FIFO_read_ready),
    .o_FIFO_write_ready_M(o_FIFO_write_ready),
    .i_data_fifo_ready_M(i_data_fifo_ready),
    .i_control_mode(i_control_mode),
    
    .o_read_valid_S(w_read_valid_prime),
    .i_read_ready_S(w_read_ready_prime),
    .o_read_addr_S(w_read_addr_prime),
    .i_read_data_S(w_read_data_prime),
    .o_write_valid_S(w_write_valid_prime),
    .i_write_ready_S(w_write_ready_prime),
    .o_write_addr_S(w_write_addr_prime),
    .o_write_data_S(w_write_data_prime),
    .i_FIFO_read_ready_S(w_FIFO_read_ready_prime),
    .i_FIFO_write_ready_S(w_FIFO_write_ready_prime),
    .o_data_fifo_ready_S(w_data_fifo_ready_prime),
    .o_control_mode(w_control_mode_prime)
);

L1_FIFO_interface #(
    .ADDR_DEPTH(ADDR_DEPTH),
    .DATA_WIDTH(DATA_WIDTH),
    .MEMORY_BITWIDTH(MEMORY_BITWIDTH),
    .FIFO_DEPTH(FIFO_DEPTH),
    .INPUT_DELAY(INPUT_DELAY)
)  UL1_FIFO_interface (
    .clk(clk),
    .rstb(rstb),
    .i_read_valid(w_read_valid_prime),
    .o_read_ready(w_read_ready_prime),
    .i_read_addr(w_read_addr_prime),
    .o_read_data(w_read_data_prime),
    .i_write_valid(w_write_valid_prime),
    .o_write_ready(w_write_ready_prime),
    .i_write_addr(w_write_addr_prime),
    .i_write_data(w_write_data_prime),
    .i_control_mode(w_control_mode_prime),
    .o_FIFO_read_ready(w_FIFO_read_ready_prime),
    .o_FIFO_write_ready(w_FIFO_write_ready_prime),
    .i_data_fifo_ready(w_data_fifo_ready_prime),
    
    .o_read_valid_L1(w_read_valid),
    .i_read_ready_L1(w_read_ready),
    .o_read_addr_L1(w_read_addr),
    .i_read_data_L1(w_read_data),
    .o_write_valid_L1(w_write_valid),
    .i_write_ready_L1(w_write_ready),
    .o_write_addr_L1(w_write_addr),
    .o_write_data_L1(w_write_data),
    .o_control_mode(w_control_mode)
);

L1_Cache_Mimic #(
    .ADDR_DEPTH(ADDR_DEPTH),
    .DATA_WIDTH(DATA_WIDTH),
    .MEMORY_BITWIDTH(MEMORY_BITWIDTH)
) UL1_Cache_Mimic (
    .i_clk(clk),
    .i_rstn(rstb),
    .i_control_mode(w_control_mode),
    .i_read_valid(w_read_valid),
    .o_read_ready(w_read_ready),
    .i_read_addr(w_read_addr),
    .o_read_data(w_read_data),
    .i_write_valid(w_write_valid),
    .o_write_ready(w_write_ready),
    .i_write_addr(w_write_addr),
    .i_write_data(w_write_data)
);
//===============================================================================================

endmodule
