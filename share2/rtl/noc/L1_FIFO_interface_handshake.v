`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Project: 2605TO - 5nm
// Version: 250731
// Version_log: 1. 250731
// Description: L1 FIFO Interface Handshake Module
// Designer : Yun HyunJun
//
//////////////////////////////////////////////////////////////////////////////////

module L1_FIFO_interface_handshake #(
    parameter ADDR_DEPTH = 1600,
    parameter DATA_WIDTH = 512,
    localparam ADDR_BW = $clog2(ADDR_DEPTH)
)(
    // global clock, reset
    input clk,
    input rstb,
    //============================================================
    // Top controller interface
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

reg r_read_ready;
reg [DATA_WIDTH-1:0] r_read_data;
reg r_write_ready;
reg r_read_valid_L1;
reg [ADDR_BW-1:0] r_read_addr_L1;
reg r_write_valid_L1;
reg [ADDR_BW-1:0] r_write_addr_L1;
reg [DATA_WIDTH-1:0] r_write_data_L1;

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
                if (i_read_valid == 1'b1) begin
                    r_next_state = READ_HS_MEM;
                end
                else if (i_write_valid == 1'b1) begin
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
            if (i_read_ready_L1 == 1'b1) begin
                r_next_state = READ_HS;
            end
            else begin
                r_next_state = READ_HS_MEM;
            end
        end
        READ_HS: begin
            if (i_read_valid == 1'b0) begin
                r_next_state = IDLE;
            end
            else begin
                r_next_state = READ_HS;
            end
        end
        WRITE_HS_MEM: begin
            if (i_write_ready_L1 == 1'b1) begin
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
            r_write_ready = 1'b0;
            r_write_valid_L1 = 1'b0;
            r_read_ready = 1'b0;
            r_read_valid_L1 = 1'b0;
        end
        READ_HS_MEM: begin
            r_write_ready = 1'b0;
            r_write_valid_L1 = 1'b0;
            r_read_ready = 1'b0;
            r_read_valid_L1 = 1'b1;
        end
        READ_HS: begin
            r_write_ready = 1'b0;
            r_write_valid_L1 = 1'b0;
            r_read_ready = 1'b1;
            r_read_valid_L1 = 1'b0;
        end
        WRITE_HS_MEM: begin
            r_write_ready = 1'b0;
            r_write_valid_L1 = 1'b1;
            r_read_ready = 1'b0;
            r_read_valid_L1 = 1'b0;
        end
        WRITE_HS: begin
            r_write_ready = 1'b1;
            r_write_valid_L1 = 1'b0;
            r_read_ready = 1'b0;
            r_read_valid_L1 = 1'b0;
        end
        default: begin
            r_write_ready = 1'b0;
            r_write_valid_L1 = 1'b0;
            r_read_ready = 1'b0;
            r_read_valid_L1 = 1'b0;
        end
    endcase
end
//===============================================================================================

//===============================================================================================
// Input data Latch
always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        r_write_addr_L1 <= {(ADDR_BW){1'b0}};
        r_write_data_L1 <= {(DATA_WIDTH){1'b0}};
    end
    else begin
        if (i_write_valid == 1'b1) begin
            r_write_addr_L1 <= i_write_addr;
            r_write_data_L1 <= i_write_data;
        end
        else begin
            r_write_addr_L1 <= r_write_addr_L1;
            r_write_data_L1 <= r_write_data_L1;
        end
    end
end

always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        r_read_addr_L1 <= {(ADDR_BW){1'b0}};
    end
    else begin
        if (i_read_valid == 1'b1) begin
            r_read_addr_L1 <= i_read_addr;
        end
        else begin
            r_read_addr_L1 <= r_read_addr_L1;
        end
    end
end

always @(posedge clk or negedge rstb) begin
    if (!rstb) begin
        r_read_data <= {(DATA_WIDTH){1'b0}};
    end
    else begin
        if ((o_read_valid_L1 && i_read_ready_L1) == 1'b1) begin
            r_read_data <= i_read_data_L1;
        end
        else begin
            r_read_data <= r_read_data;
        end
    end
end
//===============================================================================================

//===============================================================================================
// Output assignment
assign o_read_ready = r_read_ready;
assign o_read_data = r_read_data;
assign o_write_ready = r_write_ready;
assign o_read_valid_L1 = r_read_valid_L1;
assign o_read_addr_L1 = r_read_addr_L1;
assign o_write_valid_L1 = r_write_valid_L1;
assign o_write_addr_L1 = r_write_addr_L1;
assign o_write_data_L1 = r_write_data_L1;
//===============================================================================================

endmodule
