`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// Project      : SRAM Mimic 
// Module       : SRAM Mimic 
// Author       : ParkSunJong
// Description  : ---
// Version      : 2025-06-18 <Basic Version>
//              : 2025-06-20 <MEMORY ROW : Debugging>
// -----------------------------------------------------------------------------


module sram_mimic#(
    parameter  BIT_WIDTH   = 128,
    parameter  ADDRESS_ROW = 2048,
    localparam ADDR_BIT =$clog2(ADDRESS_ROW)  
)(
    // -------------------------------------------------------------------------
    // Global Signals
    input wire                       i_clk, 
    input wire                       i_rstn,
    // -------------------------------------------------------------------------
    //  Input List
    input wire                       i_web,
    input wire                       i_ceb,
    input wire   [ADDR_BIT -1 : 0]   i_addr,
    input wire   [BIT_WIDTH-1 : 0 ]  i_din,
    // -------------------------------------------------------------------------
    // Output
    input wire   [BIT_WIDTH-1 : 0 ]  o_dout 
);
    // -------------------------------------------------------------------------
    // Internal Registers
    // -------------------------------------------------------------------------
    reg [BIT_WIDTH -1 : 0] mem [ADDRESS_ROW-1 : 0]; 
    reg [BIT_WIDTH-1 : 0] r_dout;
    // -------------------------------------------------------------------------
    // For- Loop Integer
    // -------------------------------------------------------------------------
    integer i;
    // -------------------------------------------------------------------------
    // Output Assignments
    // -------------------------------------------------------------------------
    assign o_dout = r_dout;
    // -------------------------------------------------------------------------
    // Logic
    // -------------------------------------------------------------------------
    // Write Operation 
    always @(posedge i_clk or negedge i_rstn) begin
        if(i_rstn == 1'b0) begin 
            for(i =0; i<ADDRESS_ROW; i=i+1) begin 
                mem[i] <= {BIT_WIDTH{1'b0}};
            end 
        end 
        else begin
             if(i_ceb == 1'b0 && i_web == 1'b0) begin
                mem[i_addr] <= i_din;
             end
        end 
    end 
    // -------------------------------------------------------------------------
    // Read Operation
    always @(posedge i_clk or negedge i_rstn)begin
        if(i_rstn == 1'b0)begin 
            r_dout <= {BIT_WIDTH{1'b0}};
        end 
        else begin 
            if(i_ceb == 1'b0 && i_web == 1'b1) begin 
                r_dout <= mem[i_addr];
            end
        end 
    end 

endmodule
