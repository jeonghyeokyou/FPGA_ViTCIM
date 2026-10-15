// -----------------------------------------------------------------------------
// Company      : Articron
// Author       : ParkJaehyun
// Create Date  : 2025-07-22
// License      : 
// Project      : 2605_Tapeout_NPU_TOP_CTRL
// Module       : sync_fifo
// Description  : Synchronous FIFO with Backpressure Signals
// Version      : 2025-07-22 <Initial Version>
// Features     : Configurable depth, input/output registers, almost_full/almost_empty signals
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps
module sync_fifo_L2 #(
    parameter unsigned FIFO_IN_REG      = 1,
    parameter unsigned FIFO_OUT_REG     = 1,
    parameter unsigned FIFO_CMD_LENGTH  = 32,
    parameter unsigned FIFO_DEPTH       = 4,
    parameter unsigned FIFO_LOG2_DEPTH  = 2,
    parameter unsigned INPUT_DELAY      = 2
) (
    input  logic                           i_clk,
    input  logic                           i_rstb,

    // Slave interface (input)
    input  logic                           i_s_valid,
    output logic                           o_s_ready,
    input  logic [FIFO_CMD_LENGTH-1:0]     i_s_data,

    // Master interface (output)
    output logic                           o_m_valid,
    input  logic                           i_m_ready,
    output logic [FIFO_CMD_LENGTH-1:0]     o_m_data,
    
    // Backpressure signals for pipeline latency consideration
    output logic                           o_almost_full,   // 2개 공간만 남았을 때 1
    output logic                           o_almost_empty   // 2개 데이터만 남았을 때 1
);

    // Internal signals for skid buffer
    logic                           w_s_valid;
    logic                           w_s_ready;
    logic [FIFO_CMD_LENGTH-1:0]     w_s_data;

    logic                           w_m_valid;
    logic                           w_m_ready;
    logic [FIFO_CMD_LENGTH-1:0]     w_m_data;

    // FIFO status signals
    logic                           o_empty;
    logic                           o_full;

    // Handshake signals
    wire i_hs = w_s_valid & w_s_ready;
    wire o_hs = w_m_valid & w_m_ready;

    // FIFO pointers and memory
    logic [FIFO_LOG2_DEPTH-1:0]     wptr, wptr_nxt;
    logic                           wptr_round, wptr_round_nxt;
    logic [FIFO_LOG2_DEPTH-1:0]     rptr, rptr_nxt;
    logic                           rptr_round, rptr_round_nxt;
    logic [FIFO_CMD_LENGTH-1:0]     cmd_fifo[FIFO_DEPTH-1:0];

    // FIFO write logic
    always_ff @(posedge i_clk or negedge i_rstb) begin
        if (!i_rstb) begin
            wptr <= '0;
            wptr_round <= 1'b0;
            for (int i = 0; i < FIFO_DEPTH; i++) begin
                cmd_fifo[i] <= '0;
            end
        end else if (i_hs) begin
            cmd_fifo[wptr] <= w_s_data;
            {wptr_round, wptr} <= {wptr_round_nxt, wptr_nxt};
        end
    end

    // Write pointer next logic
    always_comb begin
        if (wptr == (FIFO_DEPTH-1)) begin
            wptr_nxt = '0;
            wptr_round_nxt = ~wptr_round;
        end else begin
            wptr_nxt = wptr + 'd1;
            wptr_round_nxt = wptr_round;
        end
    end

    // FIFO read logic
    always_ff @(posedge i_clk or negedge i_rstb) begin
        if (!i_rstb) begin
            rptr <= '0;
            rptr_round <= 1'b0;
        end else if (o_hs) begin
            {rptr_round, rptr} <= {rptr_round_nxt, rptr_nxt};
        end
    end

    // Read pointer next logic
    always_comb begin
        if (rptr == (FIFO_DEPTH-1)) begin
            rptr_nxt = '0;
            rptr_round_nxt = ~rptr_round;
        end else begin
            rptr_nxt = rptr + 'd1;
            rptr_round_nxt = rptr_round;
        end
    end

    // FIFO data output
    assign w_m_data = cmd_fifo[rptr];

    // FIFO status signals
    assign o_empty = (wptr_round == rptr_round) && (wptr == rptr);
    assign o_full = (wptr_round != rptr_round) && (wptr == rptr);

    // FIFO usage calculation for backpressure signals
    logic [FIFO_LOG2_DEPTH:0] fifo_usage;
    always_comb begin
        if (wptr_round == rptr_round) begin
            fifo_usage = (wptr >= rptr) ? (wptr - rptr) : (FIFO_DEPTH - rptr + wptr);
        end else begin
            fifo_usage = (FIFO_DEPTH - rptr + wptr);
        end
    end

    // Backpressure signals
    assign o_almost_full = (fifo_usage >= FIFO_DEPTH - INPUT_DELAY);  // 2개 공간만 남았을 때
    assign o_almost_empty = (fifo_usage <= INPUT_DELAY);              // 2개 데이터만 남았을 때

    // FIFO control signals
    assign w_s_ready = ~o_full;
    assign w_m_valid = ~o_empty;

    // Input register (skid buffer)
    generate
        if (FIFO_IN_REG) begin
            skid_buffer #(
                .DATA_WIDTH(FIFO_CMD_LENGTH)
            ) u_skid_buffer_in (
                .i_clk        (i_clk),
                .i_rstb       (i_rstb),
                .i_s_valid    (i_s_valid),
                .o_s_ready    (o_s_ready),
                .i_s_data     (i_s_data),
                .o_m_valid    (w_s_valid),
                .i_m_ready    (w_s_ready),
                .o_m_data     (w_s_data)
            );
        end else begin
            assign w_s_valid = i_s_valid;
            assign o_s_ready = w_s_ready;
            assign w_s_data = i_s_data;
        end
    endgenerate

    // Output register (skid buffer)
    generate
        if (FIFO_OUT_REG) begin
            skid_buffer #(
                .DATA_WIDTH(FIFO_CMD_LENGTH)
            ) u_skid_buffer_out (
                .i_clk        (i_clk),
                .i_rstb       (i_rstb),
                .i_s_valid    (w_m_valid),
                .o_s_ready    (w_m_ready),
                .i_s_data     (w_m_data),
                .o_m_valid    (o_m_valid),
                .i_m_ready    (i_m_ready),
                .o_m_data     (o_m_data)
            );
        end else begin
            assign o_m_valid = w_m_valid;
            assign w_m_ready = i_m_ready;
            assign o_m_data = w_m_data;
        end
    endgenerate

endmodule

