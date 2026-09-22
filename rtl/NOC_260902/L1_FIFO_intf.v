`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// Project      : L1 FIFO Interface with SRAM Controller
// Module       : L1_FIFO_intf
// Author       : Yun HyunJun
// Description  : L1 FIFO Interface Top Module with SRAM Controller
// Version      : Version_0 : 2025-10-09 (L1 FIFO Interface)
// Version      : Version_1 : 2025-10-13 (L1 FIFO Interface with SRAM Controller) -PSJ  
// -----------------------------------------------------------------------------

module L1_FIFO_intf #(
    parameter ADDR_DEPTH      = 2048,
    parameter DATA_WIDTH      = 512,
    parameter MEMORY_BITWIDTH = 128,
    parameter FIFO_DEPTH      = 8,
    parameter INPUT_DELAY     = 3,
    
    localparam ADDR_BW = $clog2(ADDR_DEPTH)
)(
    // Global Clock & Reset
    input                       clk,
    input                       rstb,
    
    // Control Signal 
    input                       i_pe_busy,
    // Read Port
    input                       i_read_valid,
    output                      o_read_ready,
    input  [ADDR_BW-1:0]        i_read_addr,
    output [DATA_WIDTH-1:0]     o_read_data,
    
    // Write Port
    input                       i_write_valid,
    output                      o_write_ready,
    input  [ADDR_BW-1:0]        i_write_addr,
    input  [DATA_WIDTH-1:0]     i_write_data,
    
    // Control Signal
    input                       i_control_mode,
    output                      o_FIFO_read_ready,
    output                      o_FIFO_write_ready,
    input                       i_data_fifo_ready,
    
    // SRAM Interface
    output                      o_sram_ceb,
    output                      o_sram_web,
    output [ADDR_BW-1:0]        o_sram_addr,
    output [DATA_WIDTH-1:0]     o_sram_din,
    input  [DATA_WIDTH-1:0]     i_sram_dout
);

// -----------------------------------------------------------------------------
// Declarations
// -----------------------------------------------------------------------------
wire                    w_control_mode;
wire                    w_read_valid;
wire                    w_read_ready;
wire [ADDR_BW-1:0]      w_read_addr;
wire [DATA_WIDTH-1:0]   w_read_data;
wire                    w_write_valid;
wire                    w_write_ready;
wire [ADDR_BW-1:0]      w_write_addr;
wire [DATA_WIDTH-1:0]   w_write_data;

wire                    w_sram_ceb;
wire                    w_sram_web;
wire [ADDR_BW-1:0]      w_sram_addr;
wire [DATA_WIDTH-1:0]   w_sram_din;

// -----------------------------------------------------------------------------
// Output Assignments
// -----------------------------------------------------------------------------
assign o_sram_ceb  = w_sram_ceb;
assign o_sram_web  = w_sram_web;
assign o_sram_addr = w_sram_addr;
assign o_sram_din  = w_sram_din;

// -----------------------------------------------------------------------------
// L1 FIFO Interface
// -----------------------------------------------------------------------------
L1_FIFO_interface #(
    .ADDR_DEPTH      (ADDR_DEPTH),
    .DATA_WIDTH      (DATA_WIDTH),
    .MEMORY_BITWIDTH (MEMORY_BITWIDTH),
    .FIFO_DEPTH      (FIFO_DEPTH),
    .INPUT_DELAY     (INPUT_DELAY)
) UL1_FIFO_interface (
    .clk                  (clk),
    .rstb                 (rstb),
    .i_pe_busy            (i_pe_busy),
    .i_read_valid         (i_read_valid),
    .o_read_ready         (o_read_ready),
    .i_read_addr          (i_read_addr),
    .o_read_data          (o_read_data),
    .i_write_valid        (i_write_valid),
    .o_write_ready        (o_write_ready),
    .i_write_addr         (i_write_addr),
    .i_write_data         (i_write_data),
    .i_control_mode       (i_control_mode),
    .o_FIFO_read_ready    (o_FIFO_read_ready),
    .o_FIFO_write_ready   (o_FIFO_write_ready),
    .i_data_fifo_ready    (i_data_fifo_ready),
    .o_read_valid_L1      (w_read_valid),
    .i_read_ready_L1      (w_read_ready),
    .o_read_addr_L1       (w_read_addr),
    .i_read_data_L1       (w_read_data),
    .o_write_valid_L1     (w_write_valid),
    .i_write_ready_L1     (w_write_ready),
    .o_write_addr_L1      (w_write_addr),
    .o_write_data_L1      (w_write_data),
    .o_control_mode       (w_control_mode)
);

// -----------------------------------------------------------------------------
// SRAM Controller
// -----------------------------------------------------------------------------
sram_controller #(
    .ADDR_DEPTH (ADDR_DEPTH),
    .DATA_WIDTH (DATA_WIDTH)
) Usram_controller (
    .i_clk         (clk),
    .i_rstn        (rstb),
    .i_control_mode(w_control_mode),
    .i_read_valid  (w_read_valid),
    .o_read_ready  (w_read_ready),
    .i_read_addr   (w_read_addr),
    .o_read_data   (w_read_data),
    .i_write_valid (w_write_valid),
    .o_write_ready (w_write_ready),
    .i_write_addr  (w_write_addr),
    .i_write_data  (w_write_data),
    .o_sram_ceb    (w_sram_ceb),
    .o_sram_web    (w_sram_web),
    .o_sram_addr   (w_sram_addr),
    .o_sram_din    (w_sram_din),
    .i_sram_dout   (i_sram_dout)
);

endmodule
