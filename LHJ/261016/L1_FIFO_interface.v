`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// Project      : L1 FIFO Interface Top Module
// Module       : L1_FIFO_interface
// Author       : Yun HyunJun
// Description  : L1 FIFO Interface Top Module with PE busy gating
// Version      : Version_0 : 2025-10-09 (L1 FIFO Interface)
//              : Version_1 : 2025-10-13 (L1 FIFO Interface with PE busy gating) -PSJ
// -----------------------------------------------------------------------------

module L1_FIFO_interface #(
    parameter ADDR_DEPTH      = 2048,
    parameter DATA_WIDTH      = 512,
    parameter FIFO_DEPTH      = 4,
    parameter INPUT_DELAY     = 3,
    
    localparam ADDR_BW = $clog2(ADDR_DEPTH)
)(
    // Global Clock & Reset
    input                       clk,
    input                       rstb,
    
    // PE Busy Signal
    input                       i_pe_busy,
    
    // Top Controller Interface
    input                       i_read_valid,
    output                      o_read_ready,
    input  [ADDR_BW-1:0]        i_read_addr,
    output [DATA_WIDTH-1:0]     o_read_data,
    
    input                       i_write_valid,
    output                      o_write_ready,
    input  [ADDR_BW-1:0]        i_write_addr,
    input  [DATA_WIDTH-1:0]     i_write_data,
    
    input                       i_control_mode,
    output                      o_FIFO_read_ready,
    output                      o_FIFO_write_ready,
    input                       i_data_fifo_ready,
    
    // L1 Cache Interface
    output                      o_read_valid_L1,
    input                       i_read_ready_L1,
    output [ADDR_BW-1:0]        o_read_addr_L1,
    input  [DATA_WIDTH-1:0]     i_read_data_L1,
    
    output                      o_write_valid_L1,
    input                       i_write_ready_L1,
    output [ADDR_BW-1:0]        o_write_addr_L1,
    output [DATA_WIDTH-1:0]     o_write_data_L1,
    
    output                      o_control_mode
);

// -----------------------------------------------------------------------------
// Declarations
// -----------------------------------------------------------------------------
reg r_control_mode;

// Handshake mode wires
wire                    w_read_ready_hs;
wire [DATA_WIDTH-1:0]   w_read_data_hs;
wire                    w_write_ready_hs;
wire                    w_read_valid_L1_hs;
wire [ADDR_BW-1:0]      w_read_addr_L1_hs;
wire                    w_write_valid_L1_hs;
wire [ADDR_BW-1:0]      w_write_addr_L1_hs;
wire [DATA_WIDTH-1:0]   w_write_data_L1_hs;

// On-fire mode wires
wire                    w_read_ready_on_fire;
wire [DATA_WIDTH-1:0]   w_read_data_on_fire;
wire                    w_write_ready_on_fire;
wire                    w_FIFO_read_ready_on_fire;
wire                    w_FIFO_write_ready_on_fire;
wire                    w_read_valid_L1_on_fire;
wire [ADDR_BW-1:0]      w_read_addr_L1_on_fire;
wire                    w_write_valid_L1_on_fire;
wire [ADDR_BW-1:0]      w_write_addr_L1_on_fire;
wire [DATA_WIDTH-1:0]   w_write_data_L1_on_fire;

// Gated input signals to sub-modules
wire                    w_read_valid_gated;
wire [ADDR_BW-1:0]      w_read_addr_gated;
wire                    w_write_valid_gated;
wire [ADDR_BW-1:0]      w_write_addr_gated;
wire [DATA_WIDTH-1:0]   w_write_data_gated;
wire                    w_control_mode_gated;
wire                    w_data_fifo_ready_gated;

// Gated L1 Cache input signals to sub-modules
wire                    w_read_ready_L1_gated;
wire [DATA_WIDTH-1:0]   w_read_data_L1_gated;
wire                    w_write_ready_L1_gated;

// -----------------------------------------------------------------------------
// PE Busy Gating Logic - Top Controller Inputs
// -----------------------------------------------------------------------------
assign w_read_valid_gated      = i_pe_busy ? 1'b0                : i_read_valid;
assign w_read_addr_gated       = i_pe_busy ? {ADDR_BW{1'b0}}     : i_read_addr;
assign w_write_valid_gated     = i_pe_busy ? 1'b0                : i_write_valid;
assign w_write_addr_gated      = i_pe_busy ? {ADDR_BW{1'b0}}     : i_write_addr;
assign w_write_data_gated      = i_pe_busy ? {DATA_WIDTH{1'b0}}  : i_write_data;
assign w_control_mode_gated    = i_pe_busy ? 1'b0                : i_control_mode;
assign w_data_fifo_ready_gated = i_pe_busy ? 1'b0                : i_data_fifo_ready;

// -----------------------------------------------------------------------------
// PE Busy Gating Logic - L1 Cache Inputs
// -----------------------------------------------------------------------------
assign w_read_ready_L1_gated  = i_pe_busy ? 1'b0                : i_read_ready_L1;
assign w_read_data_L1_gated   = i_pe_busy ? {DATA_WIDTH{1'b0}}  : i_read_data_L1;
assign w_write_ready_L1_gated = i_pe_busy ? 1'b0                : i_write_ready_L1;

// -----------------------------------------------------------------------------
// Control Mode Register
// -----------------------------------------------------------------------------
always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        r_control_mode <= 1'b0;
    end
    else begin
        r_control_mode <= w_control_mode_gated;
    end
end

// -----------------------------------------------------------------------------
// Output Assignments (Mode Mux with PE Busy Gating)
// -----------------------------------------------------------------------------
assign o_read_ready       = i_pe_busy ? 1'b0                : (w_control_mode_gated ? w_read_ready_hs : w_read_ready_on_fire);
assign o_read_data        = i_pe_busy ? {DATA_WIDTH{1'b0}}  : (w_control_mode_gated ? w_read_data_hs : w_read_data_on_fire);
assign o_write_ready      = i_pe_busy ? 1'b0                : (w_control_mode_gated ? w_write_ready_hs : w_write_ready_on_fire);
assign o_FIFO_read_ready  = i_pe_busy ? 1'b0                : (w_control_mode_gated ? 1'b1 : w_FIFO_read_ready_on_fire);
assign o_FIFO_write_ready = i_pe_busy ? 1'b0                : (w_control_mode_gated ? 1'b1 : w_FIFO_write_ready_on_fire);
assign o_read_valid_L1    = i_pe_busy ? 1'b0                : (w_control_mode_gated ? w_read_valid_L1_hs : w_read_valid_L1_on_fire);
assign o_read_addr_L1     = i_pe_busy ? {ADDR_BW{1'b0}}     : (w_control_mode_gated ? w_read_addr_L1_hs : w_read_addr_L1_on_fire);
assign o_write_valid_L1   = i_pe_busy ? 1'b0                : (w_control_mode_gated ? w_write_valid_L1_hs : w_write_valid_L1_on_fire);
assign o_write_addr_L1    = i_pe_busy ? {ADDR_BW{1'b0}}     : (w_control_mode_gated ? w_write_addr_L1_hs : w_write_addr_L1_on_fire);
assign o_write_data_L1    = i_pe_busy ? {DATA_WIDTH{1'b0}}  : (w_control_mode_gated ? w_write_data_L1_hs : w_write_data_L1_on_fire);
assign o_control_mode     = i_pe_busy ? 1'b0                : r_control_mode;

// -----------------------------------------------------------------------------
// L1 FIFO Interface Handshake Mode
// -----------------------------------------------------------------------------
L1_FIFO_interface_handshake #(
    .ADDR_DEPTH (ADDR_DEPTH),
    .DATA_WIDTH (DATA_WIDTH)
) UL1_FIFO_interface_handshake (
    .clk              (clk),
    .rstb             (rstb),
    .i_read_valid     (w_read_valid_gated),
    .o_read_ready     (w_read_ready_hs),
    .i_read_addr      (w_read_addr_gated),
    .o_read_data      (w_read_data_hs),
    .i_write_valid    (w_write_valid_gated),
    .o_write_ready    (w_write_ready_hs),
    .i_write_addr     (w_write_addr_gated),
    .i_write_data     (w_write_data_gated),
    .i_control_mode   (w_control_mode_gated),
    .o_read_valid_L1  (w_read_valid_L1_hs),
    .i_read_ready_L1  (w_read_ready_L1_gated),
    .o_read_addr_L1   (w_read_addr_L1_hs),
    .i_read_data_L1   (w_read_data_L1_gated),
    .o_write_valid_L1 (w_write_valid_L1_hs),
    .i_write_ready_L1 (w_write_ready_L1_gated),
    .o_write_addr_L1  (w_write_addr_L1_hs),
    .o_write_data_L1  (w_write_data_L1_hs)
);

// -----------------------------------------------------------------------------
// L1 FIFO Interface On-Fire Mode
// -----------------------------------------------------------------------------
L1_FIFO_interface_on_fire #(
    .ADDR_DEPTH  (ADDR_DEPTH),
    .DATA_WIDTH  (DATA_WIDTH),
    .FIFO_DEPTH  (FIFO_DEPTH),
    .INPUT_DELAY (INPUT_DELAY)
) UL1_FIFO_interface_on_fire (
    .clk                  (clk),
    .rstb                 (rstb),
    .i_read_valid         (w_read_valid_gated),
    .o_read_ready         (w_read_ready_on_fire),
    .i_read_addr          (w_read_addr_gated),
    .o_read_data          (w_read_data_on_fire),
    .i_write_valid        (w_write_valid_gated),
    .o_write_ready        (w_write_ready_on_fire),
    .i_write_addr         (w_write_addr_gated),
    .i_write_data         (w_write_data_gated),
    .o_FIFO_read_ready    (w_FIFO_read_ready_on_fire),
    .o_FIFO_write_ready   (w_FIFO_write_ready_on_fire),
    .i_data_fifo_ready    (w_data_fifo_ready_gated),
    .i_control_mode       (w_control_mode_gated),
    .o_read_valid_L1      (w_read_valid_L1_on_fire),
    .i_read_ready_L1      (w_read_ready_L1_gated),
    .o_read_addr_L1       (w_read_addr_L1_on_fire),
    .i_read_data_L1       (w_read_data_L1_gated),
    .o_write_valid_L1     (w_write_valid_L1_on_fire),
    .i_write_ready_L1     (w_write_ready_L1_gated),
    .o_write_addr_L1      (w_write_addr_L1_on_fire),
    .o_write_data_L1      (w_write_data_L1_on_fire)
);

endmodule
