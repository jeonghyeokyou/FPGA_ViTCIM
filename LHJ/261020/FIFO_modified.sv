`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/07/21 15:48:52
// Design Name: 
// Module Name: FIFO_modified - 'element_num' reset value bitwidth modify
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

module FIFO_modified #(
    parameter DATA_WIDTH = 512,
    parameter FIFO_DEPTH = 4,
    parameter INPUT_DELAY = 3,
    localparam EFFECTIVE_FIFO_DEPTH = (FIFO_DEPTH<=INPUT_DELAY) ? 1: FIFO_DEPTH -INPUT_DELAY
)
(
    //Clock & Reset
    input  wire                     i_clk           ,
    input  wire                     i_rstn          ,

    //Push
    output wire                     o_input_ready   ,
    output                           o_input_almost_ready,
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
  
  reg [FIFO_ADDR  :0] element_num;
  reg r_almost_ready;
  
  assign full  = (wr_ptr_phase != rd_ptr_phase) && (wr_ptr == rd_ptr);
  assign empty = (wr_ptr_phase == rd_ptr_phase) && (wr_ptr == rd_ptr);
  
  assign o_input_ready  = ~full;
  assign o_output_valid = ~empty;

  assign input_ready_valid  = !full & i_input_valid;
  assign output_ready_valid = !empty & i_output_ready;

  //number of element
  always @ (posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) begin
        element_num <= {(FIFO_ADDR+1){1'b0}};
    end
    else begin
        case ({input_ready_valid, output_ready_valid})
            2'b00: begin
                element_num <= element_num;
            end
            2'b01: begin
                element_num <= element_num - 1'b1;
            end
            2'b10: begin
                element_num <= element_num + 1'b1;
            end
            2'b11: begin
                element_num <= element_num;
            end
        endcase
    end
  end

always @(*) begin
    if (element_num >= (EFFECTIVE_FIFO_DEPTH)) begin
        r_almost_ready = 1'b1;
    end
    else begin
        r_almost_ready = 1'b0;
    end
end

assign o_input_almost_ready = r_almost_ready;

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