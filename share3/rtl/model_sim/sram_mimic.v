`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
//  sram_mimic  -  FIXED copy for simulation
//  (original: rtl/NOC_260902/sram_mimic.v)
//
//  Fix : line 29  `o_dout` was declared  `input`  ->  `output`.
//        It is assigned by `assign o_dout = r_dout;` and connected to a
//        submodule read-data output in L1_Cache_Mimic, so as an `input`
//        port it drove nothing and the L1 read path returned Z/X.
//
//  Polarity (i_ceb / i_web active-low) is already correct here.
//  Same module name; include THIS file instead of the original.
// -----------------------------------------------------------------------------

module sram_mimic#(
    parameter  BIT_WIDTH   = 128,
    parameter  ADDRESS_ROW = 2048,
    localparam ADDR_BIT =$clog2(ADDRESS_ROW)
)(
    input wire                       i_clk,
    input wire                       i_rstn,
    input wire                       i_web,
    input wire                       i_ceb,
    input wire   [ADDR_BIT -1 : 0]   i_addr,
    input wire   [BIT_WIDTH-1 : 0 ]  i_din,
    output wire  [BIT_WIDTH-1 : 0 ]  o_dout
);
    reg [BIT_WIDTH -1 : 0] mem [ADDRESS_ROW-1 : 0];
    reg [BIT_WIDTH-1 : 0] r_dout;
    integer i;

    assign o_dout = r_dout;

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
