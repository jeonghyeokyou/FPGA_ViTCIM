`timescale 1ns / 1ps
// =====================================================================
//  RENAMED copy for integration sim (original: rtl/NOC_260902/FIFO.v)
//  module FIFO -> noc_FIFO  :  L2_260901/FIFO.sv also declares `module FIFO`
//  with a DIFFERENT port list. Compiling both into one simulation without
//  renaming one of them causes a module redefinition / wrong-binding error.
//  Content otherwise identical to the original.
// =====================================================================

module noc_FIFO #(
    parameter DATA_WIDTH = 2048,
    parameter FIFO_DEPTH = 4
) (
    //Clock & Reset
    input  wire                     i_clk           ,
    input  wire                     i_rstn          ,

    //Push
    output wire                     o_input_ready   ,
    input  wire                     i_input_valid   ,
    input  wire [DATA_WIDTH   -1:0] i_input_data    ,

    //Pop
    input  wire                     i_output_ready  ,
    output wire                     o_output_valid  ,
    output wire [DATA_WIDTH   -1:0] o_output_data
);

localparam  FIFO_ADDR = $clog2(FIFO_DEPTH);

wire                  full;
wire                  empty;
wire                  input_ready_valid;
wire                  output_ready_valid;

reg [FIFO_ADDR  -1:0] wr_ptr, rd_ptr;
reg                   wr_ptr_phase, rd_ptr_phase;
reg [DATA_WIDTH -1:0] mem[FIFO_DEPTH-1:0];

assign full  = (wr_ptr_phase != rd_ptr_phase) && (wr_ptr == rd_ptr);
assign empty = (wr_ptr_phase == rd_ptr_phase) && (wr_ptr == rd_ptr);

assign o_input_ready  = ~full;
assign o_output_valid = ~empty;

assign input_ready_valid  = !full && i_input_valid;
assign output_ready_valid = !empty && i_output_ready;


//write pointer
always @ (posedge i_clk or negedge i_rstn) begin
    if(!i_rstn) begin
        wr_ptr        <= 'b0;
        wr_ptr_phase  <= 'b0;
    end
    else if(input_ready_valid) begin
        if((wr_ptr+1) == FIFO_DEPTH) begin
            wr_ptr        <= 'b0;
            wr_ptr_phase  <= ~wr_ptr_phase;
        end
        else begin
            wr_ptr        <= wr_ptr + 1;
            wr_ptr_phase  <= wr_ptr_phase;
        end
    end
end

//read pointer
always @ (posedge i_clk or negedge i_rstn) begin
    if(!i_rstn) begin
        rd_ptr        <= 'b0;
        rd_ptr_phase  <= 'b0;
    end
    else if(output_ready_valid) begin
        if((rd_ptr+1) == FIFO_DEPTH) begin
            rd_ptr        <= 'b0;
            rd_ptr_phase  <= ~rd_ptr_phase;
        end
        else begin
            rd_ptr        <= rd_ptr + 1;
            rd_ptr_phase  <= rd_ptr_phase;
        end
    end
end

// memory
always @(posedge i_clk) begin
    if (input_ready_valid) begin
        mem[wr_ptr] <= i_input_data;
    end
end

assign o_output_data = mem[rd_ptr];

endmodule
