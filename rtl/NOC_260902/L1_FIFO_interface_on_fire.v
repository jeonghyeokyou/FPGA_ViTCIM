`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Project: 2605TO - 5nm
// Version: 250731
// Version_log: 1. 250731
// Description: L1 FIFO Interface On Fire Module
// Designer : Yun HyunJun
//
//////////////////////////////////////////////////////////////////////////////////

module L1_FIFO_interface_on_fire #(
    parameter ADDR_DEPTH = 1600,
    parameter DATA_WIDTH = 512,
    parameter FIFO_DEPTH = 8,
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
    output o_FIFO_read_ready,
    output o_FIFO_write_ready,
    input i_data_fifo_ready,
    input i_control_mode,
    //============================================================
    // L1 Cache interface
    //============================================================
    // Read Interface
    output o_read_valid_L1,
    input i_read_ready_L1,
    output [ADDR_BW-1:0] o_read_addr_L1,
    input [DATA_WIDTH-1:0] i_read_data_L1,
    // Write Interface
    output o_write_valid_L1,
    input i_write_ready_L1,
    output [ADDR_BW-1:0] o_write_addr_L1,
    output [DATA_WIDTH-1:0] o_write_data_L1
);

wire w_input_ready_addr;
wire w_input_valid_addr;
wire [ADDR_BW-1:0] w_input_data_addr;
wire w_output_ready_addr;
wire w_output_valid_addr;
wire [ADDR_BW-1:0] w_output_data_addr;
wire w_input_ready_data;
wire w_input_almost_ready_data;
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
            if (i_read_valid == 1'b1) begin
                r_read_signal <= 1'b1;
            end
            else begin
                if (i_write_valid == 1'b1) begin
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
            if (i_write_valid == 1'b1) begin
                r_write_signal <= 1'b1;
            end
            else begin
                if (i_read_valid == 1'b1) begin
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
assign w_input_valid_addr = (i_control_mode == 1'b0) ? (i_read_valid || i_write_valid) : 1'b0;
assign w_input_data_addr = (i_read_valid) ? i_read_addr : ((i_write_valid) ? i_write_addr : {(ADDR_BW){1'b0}});
assign w_output_ready_addr = (r_read_signal) ? (!w_input_almost_ready_data) : ((r_write_signal) ? (w_output_valid_addr && w_output_valid_data) : 1'b0);

// Mux Logic - Data FIFO
assign w_input_valid_data = (i_control_mode == 1'b0) ? (i_read_ready_L1 || i_write_valid) : 1'b0;
assign w_input_data_data = (r_read_signal) ? i_read_data_L1 : ((i_write_valid) ? i_write_data : {(DATA_WIDTH){1'b0}});
assign w_output_ready_data = (r_read_signal) ? i_data_fifo_ready : ((r_write_signal) ? (w_output_valid_addr && w_output_valid_data) : 1'b0);

// Mux Logic - Memory Intf
assign o_read_valid_L1 = (r_read_signal) ? ((w_input_almost_ready_data == 1'b0) ? w_output_valid_addr : 1'b0) : 1'b0;
assign o_read_addr_L1 = w_output_data_addr;
assign o_write_valid_L1 = (r_write_signal) ? w_output_valid_addr && w_output_valid_data : 1'b0;
assign o_write_addr_L1 = w_output_data_addr;
assign o_write_data_L1 = w_output_data_data;

// Mux Logic - FIFO Intf
assign o_read_ready = (r_read_signal) ? w_output_valid_data : 1'b0;
assign o_read_data = w_output_data_data;
assign o_write_ready = r_write_ready;
assign o_FIFO_read_ready = w_input_ready_addr;
assign o_FIFO_write_ready = w_input_ready_addr && w_input_ready_data;
//===============================================================================================

//===============================================================================================
// Registered write ready signal
always @(posedge clk or negedge rstb) begin
   if (!rstb) begin
       r_write_ready <= 1'b0;
   end
   else begin
       r_write_ready <= i_write_ready_L1;
   end
end
//===============================================================================================

//===============================================================================================
// Module Instance
FIFO #(
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

FIFO_modified #(
   .DATA_WIDTH(DATA_WIDTH),
   .FIFO_DEPTH(FIFO_DEPTH),
   .INPUT_DELAY(INPUT_DELAY)
) UFIFO_DATA (
   .i_clk(clk),
   .i_rstn(rstb),
   .o_input_ready(w_input_ready_data),
   .o_input_almost_ready(w_input_almost_ready_data),
   .i_input_valid(w_input_valid_data),
   .i_input_data(w_input_data_data),
   .i_output_ready(w_output_ready_data),
   .o_output_valid(w_output_valid_data),
   .o_output_data(w_output_data_data)
);
//===============================================================================================

endmodule
