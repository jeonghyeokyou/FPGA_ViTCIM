`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/17 10:06:33
// Design Name: 
// Module Name: ram_mimic
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

(* DONT_TOUCH = "TRUE" *) module ram_mimic #(
    parameter BIT_WIDTH = 64,
    parameter ADDRESS_ROW = 2048,
    localparam ADDR_BIT = $clog2(ADDRESS_ROW)
) (
    input wire clka,
    input wire ena,
    input wire wea,
    input wire [ADDR_BIT-1:0] addra,
    input wire [BIT_WIDTH-1:0] dia,
    output reg [BIT_WIDTH-1:0] doa
);

(*ram_style = "ultra"*) reg [BIT_WIDTH-1:0] ram [ADDRESS_ROW-1:0];

always @(posedge clka) begin
    if (ena) begin
        if (wea) begin
            ram[addra] <= dia;
        end
        else begin
            doa <= ram[addra];
        end
    end
end

endmodule
