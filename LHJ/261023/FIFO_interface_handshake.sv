`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Project: 2605TO - 5nm
// Version: 250805
// Version_log: 1. 250805
// Description: FIFO Interface Handshake Module
// Designer : Yun HyunJun
//
//////////////////////////////////////////////////////////////////////////////////

module FIFO_interface_handshake #(
   parameter ADDR_DEPTH = 1600,
   parameter DATA_WIDTH = 512,
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
   output [DATA_WIDTH-1:0] o_write_data_S
);

//===============================================================================================
// FSM State Parameter
localparam IDLE = 3'd1;
localparam READ_HS_MEM = 3'd2;
localparam READ_HS = 3'd3;
localparam WRITE_HS_MEM = 3'd4;
localparam WRITE_HS = 3'd5;
//===============================================================================================

reg [2:0] r_cur_state;
reg [2:0] r_next_state;

reg r_read_ready_M;
reg [DATA_WIDTH-1:0] r_read_data_M;
reg r_write_ready_M;
reg r_read_valid_S;
reg [ADDR_BW-1:0] r_read_addr_S;
reg r_write_valid_S;
reg [ADDR_BW-1:0] r_write_addr_S;
reg [DATA_WIDTH-1:0] r_write_data_S;

//===============================================================================================
// State Transition
always @(posedge clk or negedge rstb) begin
   if (!rstb) begin
       r_cur_state <= IDLE;
   end
   else begin
       r_cur_state <= r_next_state;
   end
end
//===============================================================================================

//===============================================================================================
// Next state assignment
always @(*) begin
   case (r_cur_state)
       IDLE: begin
           if (i_control_mode == 1'b1) begin
               if (i_read_valid_M == 1'b1) begin
                   r_next_state = READ_HS_MEM;
               end
               else if (i_write_valid_M == 1'b1) begin
                   r_next_state = WRITE_HS_MEM;
               end
               else begin
                   r_next_state = IDLE;
               end
           end
           else begin
               r_next_state = IDLE;
           end
       end
       READ_HS_MEM: begin
           if (i_read_ready_S == 1'b1) begin
               r_next_state = READ_HS;
           end
           else begin
               r_next_state = READ_HS_MEM;
           end
       end
       READ_HS: begin
           if (i_read_valid_M == 1'b0) begin
               r_next_state = IDLE;
           end
           else begin
               r_next_state = READ_HS;
           end
       end
       WRITE_HS_MEM: begin
           if (i_write_ready_S == 1'b1) begin
               r_next_state = WRITE_HS;
           end
           else begin
               r_next_state = WRITE_HS_MEM;
           end
       end
       WRITE_HS: begin
           r_next_state = IDLE;
       end
       default: begin
           r_next_state = IDLE;
       end
   endcase
end
//===============================================================================================

//===============================================================================================
// Valid, Ready signal assignment by FSM
always @(*) begin
   case (r_cur_state)
       IDLE: begin
           r_write_ready_M = 1'b0;
           r_write_valid_S = 1'b0;
           r_read_ready_M = 1'b0;
           r_read_valid_S = 1'b0;
       end
       READ_HS_MEM: begin
           r_write_ready_M = 1'b0;
           r_write_valid_S = 1'b0;
           r_read_ready_M = 1'b0;
           r_read_valid_S = 1'b1;
       end
       READ_HS: begin
           r_write_ready_M = 1'b0;
           r_write_valid_S = 1'b0;
           r_read_ready_M = 1'b1;
           r_read_valid_S = 1'b0;
       end
       WRITE_HS_MEM: begin
           r_write_ready_M = 1'b0;
           r_write_valid_S = 1'b1;
           r_read_ready_M = 1'b0;
           r_read_valid_S = 1'b0;
       end
       WRITE_HS: begin
           r_write_ready_M = 1'b1;
           r_write_valid_S = 1'b0;
           r_read_ready_M = 1'b0;
           r_read_valid_S = 1'b0;
       end
       default: begin
           r_write_ready_M = 1'b0;
           r_write_valid_S = 1'b0;
           r_read_ready_M = 1'b0;
           r_read_valid_S = 1'b0;
       end
   endcase
end
//===============================================================================================

//===============================================================================================
// Input data Latch
always @(posedge clk or negedge rstb) begin
   if (!rstb) begin
       r_write_addr_S <= {(ADDR_BW){1'b0}};
       r_write_data_S <= {(DATA_WIDTH){1'b0}};
   end
   else begin
       if (i_write_valid_M == 1'b1) begin
           r_write_addr_S <= i_write_addr_M;
           r_write_data_S <= i_write_data_M;
       end
       else begin
           r_write_addr_S <= r_write_addr_S;
           r_write_data_S <= r_write_data_S;
       end
   end
end

always @(posedge clk or negedge rstb) begin
   if (!rstb) begin
       r_read_addr_S <= {(ADDR_BW){1'b0}};
   end
   else begin
       if (i_read_valid_M == 1'b1) begin
           r_read_addr_S <= i_read_addr_M;
       end
       else begin
           r_read_addr_S <= r_read_addr_S;
       end
   end
end

always @(posedge clk or negedge rstb) begin
   if (!rstb) begin
       r_read_data_M <= {(DATA_WIDTH){1'b0}};
   end
   else begin
       if ((o_read_valid_S && i_read_ready_S) == 1'b1) begin
           r_read_data_M <= i_read_data_S;
       end
       else begin
           r_read_data_M <= r_read_data_M;
       end
   end
end
//===============================================================================================

//===============================================================================================
// Output assignment
assign o_read_ready_M = r_read_ready_M;
assign o_read_data_M = r_read_data_M;
assign o_write_ready_M = r_write_ready_M;
assign o_read_valid_S = r_read_valid_S;
assign o_read_addr_S = r_read_addr_S;
assign o_write_valid_S = r_write_valid_S;
assign o_write_addr_S = r_write_addr_S;
assign o_write_data_S = r_write_data_S;
//===============================================================================================

endmodule
