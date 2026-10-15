`timescale 1ns / 1ps

module SRAM_group #(
    parameter BLOCKS = 4096,
    parameter BIT_WIDTH = 64,
    parameter ADDRESS_ROW = 256,
    localparam ADDR_BIT_IN_BLOCK = $clog2(ADDRESS_ROW),
    localparam ADDR_BIT_PER_BLOCK = $clog2(BLOCKS),
    localparam ADDR_BIT_TOTAL = ADDR_BIT_IN_BLOCK + ADDR_BIT_PER_BLOCK
)(
    input wire           i_clk,
    input wire           i_rstn,

    // ========== ceb, web, addr,d_in, q_out for each block ==========
    input   wire [BLOCKS-1:0]            i_ceb,           // active-low
    input   wire [BLOCKS-1:0]            i_web,           // active-low
    input   wire [ADDR_BIT_IN_BLOCK-1:0] i_addr [BLOCKS-1:0],
    input   wire [BIT_WIDTH-1:0]         i_din  [BLOCKS-1:0],
    output  wire [BIT_WIDTH-1:0]         o_qout [BLOCKS-1:0]
);
    
    genvar b;
    generate
        for (b = 0; b < BLOCKS; b = b + 1) begin : BLOCK
            ram_mimic #(
                .BIT_WIDTH(BIT_WIDTH),
                .ADDRESS_ROW(ADDRESS_ROW)
            ) u_sram_mimic (
                .clka (i_clk),
                .ena (i_ceb[b]),
                .wea (i_web[b]),
                .addra (i_addr[b]),
                .dia (i_din[b]),
                .doa (o_qout[b])
            );
        end
    endgenerate

endmodule 