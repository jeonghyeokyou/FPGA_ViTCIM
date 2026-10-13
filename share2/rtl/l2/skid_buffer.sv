// -----------------------------------------------------------------------------
// Company      : Articron
// Author       : ParkJaehyun
// Create Date  : 2025-07-22
// License      : 
// Project      : 2605_Tapeout_NPU_TOP_CTRL
// Module       : skid_buffer
// Description  : Skid Buffer for Timing Closure
// Version      : 2025-07-22 <Initial Version>
// Features     : Pipeline stall handling, data buffering for timing closure
// Reference    : https://github.com/iammituraj/skid_buffer/blob/main/pipe_skid_buffer.sv
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module skid_buffer #(
    parameter DATA_WIDTH = 8
) (
    input  logic                   i_clk,
    input  logic                   i_rstb,

    // Slave interface (input)
    input  logic                   i_s_valid,
    output logic                   o_s_ready,
    input  logic [DATA_WIDTH-1:0]  i_s_data,

    // Master interface (output)
    output logic                   o_m_valid,
    input  logic                   i_m_ready,
    output logic [DATA_WIDTH-1:0]  o_m_data
);

    // State definitions
    localparam PIPE = 1'b0;  // Stage where data is piped out or stored to temp buffer
    localparam SKID = 1'b1;  // Stage to wait after data skid happened

    // State and data registers
    logic                    state_reg;           // State register
    logic [DATA_WIDTH-1:0]   m_data_reg;          // Data buffer
    logic [DATA_WIDTH-1:0]   m_data_temp_reg;     // Spare buffer
    logic                    m_valid_reg;         // Valid signal
    logic                    m_valid_temp_reg;    // Temporary valid signal
    logic                    s_ready_reg;         // Ready signal register
    
    // Pipeline ready signal
    logic ready;

    // Output assignments
    assign ready = i_m_ready || ~m_valid_reg;
    assign o_s_ready = s_ready_reg;
    assign o_m_data = m_data_reg;
    assign o_m_valid = m_valid_reg;

    // Main state machine
    always_ff @(posedge i_clk or negedge i_rstb) begin
        if (!i_rstb) begin
            state_reg <= PIPE;
            m_data_reg <= '0;
            m_data_temp_reg <= '0;
            m_valid_reg <= 1'b0;
            m_valid_temp_reg <= 1'b0;
            s_ready_reg <= 1'b0;
        end else begin
            case (state_reg)
                PIPE: begin
                    // Pipe data out
                    if (ready) begin
                        m_data_reg <= i_s_data;
                        m_valid_reg <= i_s_valid;
                        s_ready_reg <= 1'b1;
                        state_reg <= PIPE;
                    end
                    // Pipeline stall, store input data to temp buffer (skid happened)
                    else begin
                        m_data_temp_reg <= i_s_data;
                        m_valid_temp_reg <= i_s_valid;
                        s_ready_reg <= 1'b0;
                        state_reg <= SKID;
                    end
                end
                SKID: begin
                    // Copy data from temp buffer to data buffer, resume pipeline
                    if (ready) begin
                        m_data_reg <= m_data_temp_reg;
                        m_valid_reg <= m_valid_temp_reg;
                        s_ready_reg <= 1'b1;
                        state_reg <= PIPE;
                    end
                end
            endcase
        end
    end

endmodule 