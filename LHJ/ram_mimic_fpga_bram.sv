// FPGA build override: only RAM_STYLE changes from the supplied vendor file.
`timescale 1ns / 1ps
// =====================================================================
//  ram_mimic  -  FIXED simulation model
//
//  The rest of L2_260901 drives the SRAM interface ACTIVE-LOW:
//    sram_controller.o_sram_ceb / o_sram_web  == 0 means "access"
//    SRAM_group_decoder.ceb_merge / web_merge == 0 means "access / write"
//  The original rtl/L2_260901/ram_mimic.sv used `if (ena)` / `if (wea)`
//  (Xilinx BRAM active-HIGH convention), so in simulation the memory
//  never captured a write and never returned a read  -> every read = X.
//
//  This copy flips the polarity to active-LOW to match the design.
//  (Same module name; include THIS file instead of the original.)
// =====================================================================
(* DONT_TOUCH = "TRUE" *) module ram_mimic #(
    parameter BIT_WIDTH = 64,
    parameter ADDRESS_ROW = 2048,
    localparam ADDR_BIT = $clog2(ADDRESS_ROW)
) (
    input wire clka,
    input wire ena,                     // active-low chip enable  (0 = access)
    input wire wea,                     // active-low write enable  (0 = write)
    input wire [ADDR_BIT-1:0] addra,
    input wire [BIT_WIDTH-1:0] dia,
    output reg [BIT_WIDTH-1:0] doa
);

(*ram_style = "block"*) reg [BIT_WIDTH-1:0] ram [ADDRESS_ROW-1:0];

always @(posedge clka) begin
    if (!ena) begin                     // selected
        if (!wea) ram[addra] <= dia;    // write
        else      doa        <= ram[addra];   // read
    end
end

endmodule
