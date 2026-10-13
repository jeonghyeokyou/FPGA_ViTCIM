// -----------------------------------------------------------------------------
// Company      : Articron
// Author       : ParkJaehyun
// Create Date  : 2025-07-22
// License      : 
// Project      : 2605_Tapeout_NPU_TOP_CTRL
// Module       : sram_write_ctrl_axi
// Description  : SRAM Write Controller with AXI4 Interface Protocol
// Version      : 2025-07-22 <Revised Version>
// Features     : AXI4 Write Channel (AW, W, B), Multiple Outstanding Requests (MOR), Burst Support
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
module sram_write_ctrl_axi #(
    parameter AXI_DATA_WIDTH  = 32,
    parameter SRAM_DATA_WIDTH = 32,
    parameter SRAM_ADDR_WIDTH = 10,
    parameter MOR_DEPTH       = 4
) (
    input  logic                          i_clk,
    input  logic                          i_rstb,

    // Write Address Channel (AW)
    input  logic [SRAM_ADDR_WIDTH-1:0]    i_awaddr,
    input  logic                          i_awvalid,
    output logic                          o_awready,
    input  logic [7:0]                    i_awlen,

    // Write Data Channel (W)
    input  logic [AXI_DATA_WIDTH-1:0]     i_wdata,
    input  logic                          i_wvalid,
    input  logic                          i_wlast,
    output logic                          o_wready,

    // Write Response Channel (B)
    output logic                          o_bvalid,
    input  logic                          i_bready,

    // SRAM interface (FIFO_sram interface)
    // write data & addr
    output logic [SRAM_ADDR_WIDTH-1:0]    o_a,
    output logic [SRAM_DATA_WIDTH-1:0]    o_q,
    output logic                          o_q_valid,
    input  logic                          i_q_ready,
    //output logic [SRAM_ADDR_WIDTH-1:0]    o_a,
    //output logic                          o_ceb,
    //output logic                          o_web,
    //output logic [SRAM_DATA_WIDTH-1:0]    o_d,

    // TOP Read/Write Ctrl interface
    output logic                          o_write_busy
);

    localparam int MOR_LOG2_DEPTH = $clog2(MOR_DEPTH);
    localparam int AWPK_WIDTH     = SRAM_ADDR_WIDTH + 8;

    typedef enum logic [1:0] {
        S_IDLE  = 2'd0,
        S_WRITE = 2'd1,
        S_RESP  = 2'd2
    } state_e;

    state_e current_state, next_state;

    // -----------------------------
    // FIFO ����
    // -----------------------------
    // W data FIFO {wdata, wlast}
    logic                      w_fifo_s_valid,  w_fifo_s_ready;
    logic [AXI_DATA_WIDTH:0]   w_fifo_s_data;
    logic                      w_fifo_m_valid,  w_fifo_m_ready;
    logic [AXI_DATA_WIDTH:0]   w_fifo_m_data;
    logic [AXI_DATA_WIDTH-1:0] w_fifo_wdata;
    logic                      w_fifo_wlast;

    // AW��W FIFO {addr, awlen}
    logic                      aw_to_w_fifo_s_valid, aw_to_w_fifo_s_ready;
    logic [AWPK_WIDTH-1:0]     aw_to_w_fifo_s_data;
    logic                      aw_to_w_fifo_m_valid, aw_to_w_fifo_m_ready;
    logic [AWPK_WIDTH-1:0]     aw_to_w_fifo_m_data;
    logic [SRAM_ADDR_WIDTH-1:0]aw_to_w_fifo_addr;
    logic [7:0]                aw_to_w_fifo_awlen;

    // W��B FIFO {burst_len}
    logic                      w_to_b_fifo_s_valid, w_to_b_fifo_s_ready;
    logic [8:0]                w_to_b_fifo_s_data;
    logic                      w_to_b_fifo_m_valid, w_to_b_fifo_m_ready;
    logic [8:0]                w_to_b_fifo_m_data;

    logic [7:0]                r_awlen_latch;

    // -----------------------------
    // AW ä�� ����
    // -----------------------------
    assign o_awready            = aw_to_w_fifo_s_ready;
    assign aw_to_w_fifo_s_valid = i_awvalid;
    assign aw_to_w_fifo_s_data  = {i_awaddr, i_awlen};

    assign aw_to_w_fifo_addr    = aw_to_w_fifo_m_data[AWPK_WIDTH-1:8];
    assign aw_to_w_fifo_awlen   = aw_to_w_fifo_m_data[7:0];

    // -----------------------------
    // W ä�� ����
    // -----------------------------
    assign o_wready      = w_fifo_s_ready;
    assign w_fifo_s_valid= i_wvalid;
    assign w_fifo_s_data = {i_wdata, i_wlast};

    assign w_fifo_wdata  = w_fifo_m_data[AXI_DATA_WIDTH:1];
    assign w_fifo_wlast  = w_fifo_m_data[0];

    // -----------------------------
    // W ä�� last beat / handshake
    // -----------------------------
    logic last_beat, last_beat_hs, can_accept_last;

    assign last_beat      = w_fifo_m_valid && w_fifo_wlast;
    assign can_accept_last= last_beat ? w_to_b_fifo_s_ready : 1'b1;  // ������ beat�� ���� B FIFO ���� Ȯ��

    // �� ��ȣ�� �Ʒ����� �� �� �� gating �� ����
    // assign w_fifo_m_ready = (current_state == S_WRITE) && can_accept_last;

    assign last_beat_hs        = w_fifo_m_valid && w_fifo_m_ready && w_fifo_wlast;
    assign w_to_b_fifo_s_valid = (current_state == S_WRITE) && last_beat_hs;
    assign w_to_b_fifo_s_data  = r_awlen_latch + 1; // (awlen + 1) = burst length

    // -----------------------------
    // AW �� Ʈ����� ���� ���� (AW FIFO pop ����)
    //  - IDLE   : ù Ʈ�����
    //  - WRITE  : ���� burst ������ beat HS + ���� AW ����
    //  - RESP   : B ���� �� + ���� AW ����
    // -----------------------------
    logic start_new_tr;

    always_comb begin
        start_new_tr = 1'b0;

        unique case (current_state)
            S_IDLE: begin
                if (aw_to_w_fifo_m_valid)
                    start_new_tr = 1'b1;
            end

            S_WRITE: begin
                if (last_beat_hs && aw_to_w_fifo_m_valid)
                    start_new_tr = 1'b1;
            end

            S_RESP: begin
                if (o_bvalid && i_bready && aw_to_w_fifo_m_valid)
                    start_new_tr = 1'b1;
            end

            default: start_new_tr = 1'b0;
        endcase
    end

    // AW FIFO pop �� �׻� start_new_tr ����Ŭ������
    assign aw_to_w_fifo_m_ready = start_new_tr;

    // -----------------------------
    // FSM state
    // -----------------------------
    always_ff @(posedge i_clk or negedge i_rstb) begin
        if (!i_rstb)
            current_state <= S_IDLE;
        else
            current_state <= next_state;
    end

    always_comb begin
        next_state = current_state;

        unique case (current_state)
            S_IDLE: begin
                if (aw_to_w_fifo_m_valid)
                    next_state = S_WRITE;
            end

            S_WRITE: begin
                if (last_beat_hs) begin
                    if (aw_to_w_fifo_m_valid)
                        next_state = S_WRITE; // ���� Ʈ����� �ٷ� ���� (back-to-back)
                    else
                        next_state = S_RESP;
                end
            end

            S_RESP: begin
                if (o_bvalid && i_bready) begin
                    if (aw_to_w_fifo_m_valid)
                        next_state = S_WRITE;
                    else
                        next_state = S_IDLE;
                end
            end

            default: next_state = S_IDLE;
        endcase
    end

    always @ (posedge i_clk or negedge i_rstb)begin
        if(!i_rstb) begin
            o_write_busy <= 1'b0;
        end
        else begin
            //if ((current_state==S_IDLE)&&(next_state==S_WRITE)) begin
            if ((current_state==S_IDLE)&&(i_awvalid)) begin
                o_write_busy <= 1'b1;
            end
            if ((current_state==S_RESP)&&(next_state==S_IDLE)) begin
                o_write_busy <= 1'b0;
            end
        end
    end

    // -----------------------------
    // �� Ʈ������� ù S_WRITE ����Ŭ����
    // W FIFO pop�� 1����Ŭ ���� ���� �÷���
    //  - start_new_tr�� 1�� ����Ŭ �� ���� ����Ŭ S_WRITE���� block
    // -----------------------------
    logic block_first_data;

    always_ff @(posedge i_clk or negedge i_rstb) begin
        if (!i_rstb) begin
            block_first_data <= 1'b0;
        end else begin
            if (start_new_tr) begin
                // ���� ����Ŭ S_WRITE ���� �� �� �� block
                block_first_data <= 1'b1;
            end else if (current_state == S_WRITE) begin
                // ù S_WRITE ����Ŭ �� �� �������� ����
                block_first_data <= 1'b0;
            end
        end
    end

    // ���� W FIFO pop ����:
    //  - WRITE ����
    //  - last beat�� B FIFO ���� �ʼ�
    //  - �� Ʈ����� ���� ���� ù S_WRITE ����Ŭ(block_first_data) ������ pop ����
    assign w_fifo_m_ready =  // ���� �κ��� ���� ���� �Ҿ��ϱ��մϴ�... �׷��� valid�� ���� ���� state���� ����ߵ��� �������?
        (current_state == S_WRITE) &&
        can_accept_last &&
        i_q_ready &&
        !block_first_data;

    // -----------------------------
    // AW len latch
    // -----------------------------
    always_ff @(posedge i_clk or negedge i_rstb) begin
        if (!i_rstb) begin
            r_awlen_latch <= '0;
        end else if (start_new_tr) begin
            r_awlen_latch <= aw_to_w_fifo_awlen;
        end
    end

    // -----------------------------
    // SRAM Address ���
    //  - start_new_tr : �� Ʈ����� base addr �ε�
    //  - WRITE �� handshake �� ������ +1
    // -----------------------------
    always_ff @(posedge i_clk or negedge i_rstb) begin
        if (!i_rstb) begin
            o_a <= '0;
        end else if (start_new_tr) begin
            o_a <= aw_to_w_fifo_addr;
        end else if ( current_state == S_WRITE &&
                      w_fifo_m_valid && w_fifo_m_ready &&
                      r_awlen_latch != 0 ) begin
            o_a <= o_a + 1'b1;
        end
    end

    // ----------------------------- // w ready �� i_ready �� �ձ�, �ϴ� �̾ Ȯ�� check 
    // SRAM control / data
    // -----------------------------
    
    //assign o_q_valid =  w_fifo_m_valid; // (current_state ==S_WRITE) && can_accept_last && !block_first_data
    //assign o_q       = (w_fifo_m_valid)? w_fifo_wdata : '0;

    assign o_q_valid =  w_fifo_m_valid && (current_state ==S_WRITE) && can_accept_last && !block_first_data;
    assign o_q       = (o_q_valid)? w_fifo_wdata : '0;

    //assign o_ceb = (w_fifo_m_valid && w_fifo_m_ready) ? 1'b0 : 1'b1;
    //assign o_web = 1'b0; // write-only
    //assign o_d   = (w_fifo_m_valid && w_fifo_m_ready) ? w_fifo_wdata : '0;

    // -----------------------------
    // B ä�� ó�� (W��B FIFO)
    // -----------------------------
    always_ff @(posedge i_clk or negedge i_rstb) begin
        if (!i_rstb) begin
            o_bvalid <= 1'b0;
        end else begin
            if (!o_bvalid && w_to_b_fifo_m_valid) begin
                // ������ ��� �ְ� FIFO�� ���� ��ū�� ������ BVALID �ø�
                o_bvalid <= 1'b1;
            end else if (o_bvalid && i_bready) begin
                // handshake �Ϸ� �� BVALID ����
                o_bvalid <= 1'b0;
            end
        end
    end

    // ������ handshake�� �Ͼ ���� W��B FIFO pop
    assign w_to_b_fifo_m_ready = o_bvalid && i_bready;

    // -----------------------------
    // FIFO �ν��Ͻ�
    // -----------------------------
    // W FIFO
    sync_fifo_L2 #(
        .FIFO_IN_REG    (0),
        .FIFO_OUT_REG   (0),
        .FIFO_CMD_LENGTH(AXI_DATA_WIDTH + 1),
        .FIFO_DEPTH     (MOR_DEPTH),
        .FIFO_LOG2_DEPTH(MOR_LOG2_DEPTH)
    ) w_fifo_inst (
        .i_clk        (i_clk),
        .i_rstb       (i_rstb),
        .i_s_valid    (w_fifo_s_valid),
        .o_s_ready    (w_fifo_s_ready),
        .i_s_data     (w_fifo_s_data),
        .o_m_valid    (w_fifo_m_valid),
        .i_m_ready    (w_fifo_m_ready),
        .o_m_data     (w_fifo_m_data),
        .o_almost_full(),
        .o_almost_empty()
    );

    // AW��W FIFO
    sync_fifo_L2 #(
        .FIFO_IN_REG    (0),
        .FIFO_OUT_REG   (0),
        .FIFO_CMD_LENGTH(AWPK_WIDTH),
        .FIFO_DEPTH     (MOR_DEPTH),
        .FIFO_LOG2_DEPTH(MOR_LOG2_DEPTH)
    ) aw_to_w_fifo_inst (
        .i_clk        (i_clk),
        .i_rstb       (i_rstb),
        .i_s_valid    (aw_to_w_fifo_s_valid),
        .o_s_ready    (aw_to_w_fifo_s_ready),
        .i_s_data     (aw_to_w_fifo_s_data),
        .o_m_valid    (aw_to_w_fifo_m_valid),
        .i_m_ready    (aw_to_w_fifo_m_ready),
        .o_m_data     (aw_to_w_fifo_m_data),
        .o_almost_full(),
        .o_almost_empty()
    );

    // W��B FIFO
    sync_fifo_L2 #(
        .FIFO_IN_REG    (0),
        .FIFO_OUT_REG   (0),
        .FIFO_CMD_LENGTH(8 + 1),
        .FIFO_DEPTH     (MOR_DEPTH),
        .FIFO_LOG2_DEPTH(MOR_LOG2_DEPTH)
    ) w_to_b_fifo_inst (
        .i_clk        (i_clk),
        .i_rstb       (i_rstb),
        .i_s_valid    (w_to_b_fifo_s_valid),
        .o_s_ready    (w_to_b_fifo_s_ready),
        .i_s_data     (w_to_b_fifo_s_data),
        .o_m_valid    (w_to_b_fifo_m_valid),
        .i_m_ready    (w_to_b_fifo_m_ready),
        .o_m_data     (w_to_b_fifo_m_data),
        .o_almost_full(),
        .o_almost_empty()
    );

endmodule
