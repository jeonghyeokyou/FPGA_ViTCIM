// -----------------------------------------------------------------------------
// Company      : Articron
// Author       : ParkJaehyun
// Create Date  : 2025-07-22
// License      : 
// Project      : 2605_Tapeout_NPU_TOP_CTRL
// Module       : sram_read_ctrl_axi
// Description  : SRAM Read Controller with AXI4 Interface Protocol
// Version      : 2025-07-22 <Initial Version>
// Features     : AXI4 Read Channel (AR, R), Multiple Outstanding Requests (MOR), Burst Support
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
module sram_read_ctrl_axi #(
    parameter AXI_DATA_WIDTH = 32,
    parameter SRAM_DATA_WIDTH = 32,
    parameter SRAM_ADDR_WIDTH = 10,
    parameter FIFO_DEPTH = 8,
    parameter MOR_DEPTH = 4
) (
    input  logic                  i_clk,
    input  logic                  i_rstb,
    // Address Read Channel (AR)
    input  logic [SRAM_ADDR_WIDTH-1:0]        i_araddr,
    input  logic                  i_arvalid,
    output logic                  o_arready,
    input  logic [7:0]  i_arlen,
    // Data Read Channel (R)
    output logic [AXI_DATA_WIDTH-1:0]    o_rdata,
    output logic                  o_rvalid,
    input  logic                  i_rready,
    output logic                  o_rlast,
    // SRAM interface (FIFO_sram interface)
    // read addr
    output logic [SRAM_ADDR_WIDTH-1:0]        o_a,
    output logic                              o_a_valid,
    input  logic                              i_a_ready,
    // read data
    input  logic [SRAM_DATA_WIDTH-1:0]        i_q,
    input  logic                              i_q_valid,
    output logic                              o_q_ready,
    // TOP Read/Write Ctrl interface
    output logic                          o_read_busy
);

    localparam increment_addr_size = 1;
    localparam FIFO_LOG2_DEPTH = $clog2(FIFO_DEPTH);
    localparam MOR_LOG2_DEPTH = $clog2(MOR_DEPTH);
    localparam ARPK_WIDTH = SRAM_ADDR_WIDTH + 8;

    typedef enum logic [1:0] {
        S_IDLE      = 2'd0,
        S_READ      = 2'd1,
        S_WAIT      = 2'd2
    } state_e;
    state_e current_state, next_state;

    // AR request FIFO for MOR support
    logic ar_fifo_s_valid, ar_fifo_s_ready;
    logic [ARPK_WIDTH-1:0] ar_fifo_s_data; // {addr, arlen}
    logic ar_fifo_m_valid, ar_fifo_m_ready;
    logic [ARPK_WIDTH-1:0] ar_fifo_m_data;
    logic [SRAM_ADDR_WIDTH-1:0] ar_fifo_addr;
    logic [7:0] ar_fifo_arlen;
    logic ar_fifo_almost_full, ar_fifo_almost_empty;
    
    // FIFO signals for sync_fifo
    logic fifo_s_valid, fifo_s_ready;
    logic fifo_s_ready_r_delay;
    logic [AXI_DATA_WIDTH-1:0] fifo_s_data;
    logic fifo_m_valid, fifo_m_ready;
    logic [AXI_DATA_WIDTH-1:0] fifo_m_data;
    logic fifo_almost_full, fifo_almost_empty;
    
    // Control signals
    logic [7:0]   r_arlen_latch;
    logic [8:0]     burst_cnt;
    logic [8:0]     addr_cnt;
    logic                           addr_last;
    logic [7:0]   w_arlen;
    
    // SRAM read control
    logic sram_read_en;
    
    assign o_rlast = (burst_cnt == r_arlen_latch && o_rvalid);
    assign o_rdata = fifo_m_data;
    assign o_rvalid = fifo_m_valid;
    assign fifo_m_ready = o_rvalid && i_rready;
    assign w_arlen = i_arlen;

    // AR FIFO data packing/unpacking
    assign ar_fifo_s_data = {i_araddr, i_arlen};
    assign ar_fifo_addr = ar_fifo_m_data[ARPK_WIDTH-1:8];
    assign ar_fifo_arlen = ar_fifo_m_data[7:0];

    // arready: AR FIFO�� ������ ���� ���� accept
    assign o_arready = ar_fifo_s_ready;
    assign ar_fifo_s_valid = i_arvalid;
    


    // AR FIFO instance for MOR
    sync_fifo_L2 #(
        .FIFO_IN_REG(0),
        .FIFO_OUT_REG(0),
        .FIFO_CMD_LENGTH(ARPK_WIDTH),
        .FIFO_DEPTH(MOR_DEPTH),
        .FIFO_LOG2_DEPTH(MOR_LOG2_DEPTH),
        .INPUT_DELAY(2)
    ) ar_fifo_inst (
        .i_clk(i_clk),
        .i_rstb(i_rstb),
        .i_s_valid(ar_fifo_s_valid),
        .o_s_ready(ar_fifo_s_ready),
        .i_s_data(ar_fifo_s_data),
        .o_m_valid(ar_fifo_m_valid),
        .i_m_ready(ar_fifo_m_ready),
        .o_m_data(ar_fifo_m_data),
        .o_almost_full(ar_fifo_almost_full),
        .o_almost_empty(ar_fifo_almost_empty)
    );
    
    // FSM state
    always_ff @(posedge i_clk or negedge i_rstb) begin
        if (!i_rstb)
            current_state <= S_IDLE;
        else
            current_state <= next_state;
    end

    // FSM next state logic
    always_comb begin
        next_state = current_state;
        case (current_state)
            S_IDLE: begin
                if (ar_fifo_m_valid)
                    next_state = S_READ;
            end
            S_READ: begin
                if (addr_last && fifo_s_ready_r_delay)
                    next_state = S_WAIT;
            end
            S_WAIT: begin
                if (!fifo_m_valid && burst_cnt == r_arlen_latch + 1)
                    next_state = S_IDLE;
            end
        endcase
    end

    always @ (posedge i_clk or negedge i_rstb)begin
        if(!i_rstb) begin
            o_read_busy <= 1'b0;
        end
        else begin
            if ((current_state==S_IDLE)&&(next_state==S_READ)) begin
                o_read_busy <= 1'b1;
            end
            if ((current_state==S_WAIT)&&(next_state==S_IDLE)&&!ar_fifo_m_valid) begin
                o_read_busy <= 1'b0;
            end
        end
    end

    // Latch address and burst info from AR FIFO
    always_ff @(posedge i_clk or negedge i_rstb) begin
        if (!i_rstb) begin
            r_arlen_latch <= '0;
        end else if (current_state == S_IDLE && ar_fifo_m_valid) begin
            r_arlen_latch <= ar_fifo_arlen;
        end
    end

    // Burst counter - increment when data is actually transferred
    always_ff @(posedge i_clk or negedge i_rstb) begin
        if (!i_rstb) begin
            burst_cnt <= '0;
        end else if (current_state == S_IDLE && ar_fifo_m_valid) begin
            burst_cnt <= 0;
        end else if (fifo_m_ready && fifo_m_valid) begin
            burst_cnt <= burst_cnt + 1;
        end
    end

    // Address counter for SRAM reads
    always_ff @(posedge i_clk or negedge i_rstb) begin
        if (!i_rstb) begin
            addr_cnt <= '0;
        end else if (current_state == S_IDLE && ar_fifo_m_valid) begin
            addr_cnt <= 0;
        end else if (sram_read_en&&i_a_ready) begin
            addr_cnt <= addr_cnt + 1;
        end
    end

    // addr_last: AXI4 arlen�� ���� ������ ������ ���� - 1
    // single mode (arlen=0): 1�� ������ ����, addr_cnt�� 0�� ���� �б�
    // burst mode (arlen>0): arlen+1�� ������ ����, addr_cnt�� arlen�� ������ �б�
    assign addr_last = (addr_cnt == r_arlen_latch);

    // SRAM read control
    // 1. S_READ �����̰� FIFO�� ������� ���� �б�
    assign sram_read_en = (current_state == S_READ) && fifo_s_ready_r_delay;

    // SRAM 2-cycle latency ����: FIFO�� full�� �� read�� �ߴ��ϴ� ���� �ƴ϶�, 
    // 2�� �����Ͱ� �� ���� �� ������ �����Ͽ� almost_full���� read�� �ߴ� 
    assign fifo_s_ready_r_delay = ~fifo_almost_full;


    // SRAM read delay pipeline (2 cycles) // �̰� �����ϰ� ����ϸ� ��������
    logic sram_read_en_d1, sram_read_en_d2;
    always_ff @(posedge i_clk or negedge i_rstb) begin
        if (!i_rstb) begin
            sram_read_en_d1 <= 1'b0;
            sram_read_en_d2 <= 1'b0;
        end else begin
            sram_read_en_d1 <= sram_read_en;
            sram_read_en_d2 <= sram_read_en_d1;
        end
    end

    // Address output to SRAM
    always_ff @(posedge i_clk or negedge i_rstb) begin
        if (!i_rstb) begin
            o_a <= '0;
        end else if (current_state == S_IDLE && ar_fifo_m_valid) begin
            o_a <= ar_fifo_addr;
        end else if (sram_read_en&&i_a_ready) begin
            o_a <= o_a + increment_addr_size;
        end
    end

    // // SRAM control
    // always_ff @(posedge i_clk or negedge i_rstb) begin
    //     if (!i_rstb) begin
    //         o_ceb <= 1'b1; // SRAM disable on reset
    //     end else if (current_state == S_IDLE && ar_fifo_m_valid) begin
    //         o_ceb <= 1'b0; // Enable SRAM when starting read
    //     end else if (addr_last && (current_state == S_READ || current_state == S_WAIT)) begin
    //         o_ceb <= 1'b1; // Disable SRAM when read complete (S_READ or S_WAIT)
    //     end
    // end
    
    assign o_a_valid = sram_read_en;
    //assign o_ceb = ~sram_read_en;
    //assign o_web = 1'b1; // read only

    // FIFO data input for sync_fifo
    assign fifo_s_data = i_q;
    //assign fifo_s_valid = sram_read_en_d1;
    assign fifo_s_valid = i_q_valid;
    assign o_q_ready    = fifo_s_ready;

    // AR FIFO read control
    assign ar_fifo_m_ready = (current_state == S_IDLE);

    // FIFO instance for buffering rdata
    sync_fifo_L2 #(
        .FIFO_IN_REG(0),
        .FIFO_OUT_REG(0),
        .FIFO_CMD_LENGTH(AXI_DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH),
        .FIFO_LOG2_DEPTH(FIFO_LOG2_DEPTH),
        .INPUT_DELAY(2)
    ) fifo_inst (
        .i_clk(i_clk),
        .i_rstb(i_rstb),
        .i_s_valid(fifo_s_valid),
        .o_s_ready(fifo_s_ready),
        .i_s_data(fifo_s_data),
        .o_m_valid(fifo_m_valid),
        .i_m_ready(fifo_m_ready),
        .o_m_data(fifo_m_data),
        .o_almost_full(fifo_almost_full),
        .o_almost_empty(fifo_almost_empty)
    );

endmodule 