`timescale 1ns/1ps
// =============================================================================
//  blackbox_ip  -  실제 MAC IP 자리에 들어가는 "동작 모사" 모델 (256b 버전)
//
//  하는 일 (연산은 하지 않는다)
//    1. weight 저장  : L2 ch1_wgt 가 NoC 로 보내는 weight 를 내부 weight 메모리
//                      (256b x 1024) 에 저장한다. ch1_wgt STORE 로 다시 읽어낼 수 있다.
//    2. input 인가   : L1 (256b x 2048) 의 입력 영역을 읽는다 (값은 쓰지 않음).
//    3. output 생성  : PS 가 미리 넣어둔 Golden (256b x 256) 을 L1 OUT 영역에 쓴다.
//                      -> ch1_in STORE 로 L2 에 회수, PS 가 Golden 과 비교.
//
//  IDLE -START&!noc_busy-> GUARD_IN -> RD_IN -> RD_W -> WAIT -> WR_OUT -> GUARD_OUT -> DONE
//  pe_busy :  0                1          1       1       1        1          1          0
//
//  RD_IN  : L1[in_base+k]      k = 0..in_len-1  읽기 (값 사용 안 함, 포트 점유만 모사)
//  RD_W   : WMEM[w_base+k]     k = 0..w_len-1   읽기 (값 사용 안 함)
//  WAIT   : i_latency 클럭 대기 (0 이면 건너뜀)
//  WR_OUT : Golden[k] -> L1[out_base+k]
//
//  weight 메모리 = FIFO_intf_bb (NoC 브리지 + L1_FIFO_intf + mux + SRAM) 를 그대로 쓴다.
//  NoC 쪽 포트는 FIFO_intf 와 같으므로 noc_ch1_wgt_adapter 를 그대로 붙인다.
//  pe_busy 는 L1 과 weight 메모리에 같이 걸린다 (둘 다 NoC 접근을 막는다).
//
//  WR_OUT 1클럭 지연 맞추기: Golden 을 먼저 읽고(E_k) 다음 엣지(E_k+1)에 ceb/web/addr 를
//  올려서, o_din = gold_q 가 그 사이클에 SRAM 입력으로 나간다 -> E_k+2 에 L1 에 기록.
//
//  설계 메모
//  - 길이 0 이면 해당 단계를 건너뛴다.
//  - START 는 IDLE/DONE 에서만 받는다. i_noc_busy=1 이면 무시 + o_err_start_busy (sticky).
//  - i_inject : Golden 0번 beat 의 bit0 을 뒤집어 내보낸다 (PS 쪽 비교가 잡는지 확인용).
//  - 리셋은 상태/카운터만 초기화. Golden BRAM / weight 메모리 내용은 리셋하지 않음.
// =============================================================================
module blackbox_ip #(
    parameter int DW         = 256,
    parameter int L1_AW      = 11,      // L1 2048 rows
    parameter int W_DEPTH    = 1024,    // weight memory rows
    parameter int G_DEPTH    = 256,     // Golden rows
    parameter int GUARD      = 2,
    localparam int W_AW      = $clog2(W_DEPTH),   // 10
    localparam int BAW       = $clog2(G_DEPTH),   // 8
    localparam int IN_LW     = L1_AW + 1,         // 12 (0..2048)
    localparam int W_LW      = W_AW + 1,          // 11 (0..1024)
    localparam int OUT_LW    = BAW + 1,           // 9  (0..256)
    localparam int CW        = IN_LW              // issue counter width
)(
    input  wire                 clk,
    input  wire                 rstn,

    // ---- control -------------------------------------------------------
    input  wire                 i_start,
    input  wire                 i_noc_busy,
    input  wire [L1_AW-1:0]     i_in_base,
    input  wire [IN_LW-1:0]     i_in_len,
    input  wire [W_AW-1:0]      i_w_base,
    input  wire [W_LW-1:0]      i_w_len,
    input  wire [L1_AW-1:0]     i_out_base,
    input  wire [OUT_LW-1:0]    i_out_len,
    input  wire [31:0]          i_latency,
    input  wire                 i_inject,

    // ---- Golden BRAM load port -----------------------------------------
    input  wire                 i_gold_we,
    input  wire [BAW-1:0]       i_gold_addr,
    input  wire [DW-1:0]        i_gold_wdata,

    // ---- L1 SRAM port (active-low) -------------------------------------
    output wire                 o_pe_busy,
    output wire                 o_ceb,
    output wire                 o_web,
    output wire [L1_AW-1:0]     o_addr,
    output wire [DW-1:0]        o_din,
    input  wire [DW-1:0]        i_dout,

    // ---- weight memory NoC port (same as FIFO_intf) --------------------
    input  wire                 i_w_read_valid,
    output wire                 o_w_read_ready,
    input  wire [W_AW-1:0]      i_w_read_addr,
    output wire [DW-1:0]        o_w_read_data,
    input  wire                 i_w_write_valid,
    output wire                 o_w_write_ready,
    input  wire [W_AW-1:0]      i_w_write_addr,
    input  wire [DW-1:0]        i_w_write_data,
    input  wire                 i_w_control_mode,
    output wire                 o_w_FIFO_read_ready,
    output wire                 o_w_FIFO_write_ready,
    input  wire                 i_w_data_fifo_ready,
    output wire                 o_w_noc_write_commit,
    output wire                 o_w_port_conflict,

    // ---- status ---------------------------------------------------------
    output wire                 o_busy,
    output wire                 o_done,
    output reg                  o_err_start_busy,
    output reg  [31:0]          o_cycle_cnt
);

    localparam [2:0] S_IDLE      = 3'd0,
                     S_GUARD_IN  = 3'd1,
                     S_RD_IN     = 3'd2,
                     S_RD_W      = 3'd3,
                     S_WAIT      = 3'd4,
                     S_WR_OUT    = 3'd5,
                     S_GUARD_OUT = 3'd6,
                     S_DONE      = 3'd7;

    reg  [2:0]         st;

    // latched job parameters
    reg  [L1_AW-1:0]   r_in_base, r_out_base;
    reg  [IN_LW-1:0]   r_in_len;
    reg  [W_AW-1:0]    r_w_base;
    reg  [W_LW-1:0]    r_w_len;
    reg  [OUT_LW-1:0]  r_out_len;
    reg  [31:0]        r_lat;
    reg                r_inj;

    reg  [CW-1:0]      iss;          // issue counter (RD_IN / RD_W / WR_OUT)
    reg  [31:0]        wcnt;         // guard / latency counter

    // L1 port registers
    reg                r_pe_busy;
    reg                r_ceb, r_web;
    reg  [L1_AW-1:0]   r_addr;
    reg  [OUT_LW-1:0]  r_wr_idx;

    // weight memory PE port registers (read only)
    reg                r_wceb;
    reg  [W_AW-1:0]    r_waddr;

    // Golden read pipeline
    reg  [BAW-1:0]     r_braddr;
    reg                p1_v;
    reg  [OUT_LW-1:0]  p1_idx;

    // ---------------------------------------------------------------------
    //  Golden BRAM  (simple dual port: AXI-Lite write, FSM read)
    // ---------------------------------------------------------------------
    (* ram_style = "block" *) reg [DW-1:0] gold_mem [0:G_DEPTH-1];
    reg [DW-1:0] gold_q;

    always @(posedge clk) begin
        if (i_gold_we) gold_mem[i_gold_addr] <= i_gold_wdata;
        gold_q <= gold_mem[r_braddr];
    end

    wire inj_gold = r_inj && (r_wr_idx == {OUT_LW{1'b0}});

    // ---------------------------------------------------------------------
    //  weight memory : NoC writes (ch1_wgt LOAD) / reads (ch1_wgt STORE),
    //                  FSM reads during RD_W
    // ---------------------------------------------------------------------
    wire [DW-1:0] w_pe_dout;

    FIFO_intf_bb #(.ADDR_DEPTH(W_DEPTH), .DATA_WIDTH(DW), .MEMORY_BITWIDTH(DW/4),
                   .FIFO_DEPTH(8), .INPUT_DELAY(3)) u_wmem (
        .clk(clk), .rstb(rstn),
        .i_read_valid(i_w_read_valid),   .o_read_ready(o_w_read_ready),
        .i_read_addr(i_w_read_addr),     .o_read_data(o_w_read_data),
        .i_write_valid(i_w_write_valid), .o_write_ready(o_w_write_ready),
        .i_write_addr(i_w_write_addr),   .i_write_data(i_w_write_data),
        .i_control_mode(i_w_control_mode),
        .o_FIFO_read_ready(o_w_FIFO_read_ready), .o_FIFO_write_ready(o_w_FIFO_write_ready),
        .i_data_fifo_ready(i_w_data_fifo_ready),
        .i_pe_busy(r_pe_busy), .i_pe_ceb(r_wceb), .i_pe_web(1'b1), .i_pe_addr(r_waddr),
        .i_pe_din({DW{1'b0}}), .o_pe_dout(w_pe_dout),
        .o_noc_write_commit(o_w_noc_write_commit), .o_port_conflict(o_w_port_conflict));

    // read data of L1 / weight memory is not used (no computation)
    wire unused_dout = &{1'b0, i_dout, w_pe_dout};

    // ---------------------------------------------------------------------
    //  outputs
    // ---------------------------------------------------------------------
    assign o_pe_busy = r_pe_busy;
    assign o_ceb     = r_ceb;
    assign o_web     = r_web;
    assign o_addr    = r_addr;
    assign o_din     = gold_q ^ {{(DW-1){1'b0}}, inj_gold};
    assign o_busy    = (st != S_IDLE) && (st != S_DONE);
    assign o_done    = (st == S_DONE);

    // ---------------------------------------------------------------------
    //  FSM
    // ---------------------------------------------------------------------
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            st               <= S_IDLE;
            r_in_base        <= '0;  r_out_base <= '0;
            r_in_len         <= '0;  r_out_len  <= '0;
            r_w_base         <= '0;  r_w_len    <= '0;
            r_lat            <= '0;  r_inj      <= 1'b0;
            iss              <= '0;  wcnt       <= '0;
            r_pe_busy        <= 1'b0;
            r_ceb            <= 1'b1; r_web     <= 1'b1;
            r_addr           <= '0;  r_wr_idx   <= '0;
            r_wceb           <= 1'b1; r_waddr   <= '0;
            r_braddr         <= '0;
            p1_v             <= 1'b0; p1_idx    <= '0;
            o_err_start_busy <= 1'b0;
            o_cycle_cnt      <= '0;
        end else begin
            if (o_busy) o_cycle_cnt <= o_cycle_cnt + 32'd1;

            case (st)
                // ---------------------------------------------------------
                S_IDLE, S_DONE: begin
                    if (i_start) begin
                        if (i_noc_busy) begin
                            o_err_start_busy <= 1'b1;          // ignore START
                        end else begin
                            r_in_base   <= i_in_base;
                            r_in_len    <= i_in_len;
                            r_w_base    <= i_w_base;
                            r_w_len     <= i_w_len;
                            r_out_base  <= i_out_base;
                            r_out_len   <= i_out_len;
                            r_lat       <= i_latency;
                            r_inj       <= i_inject;
                            o_cycle_cnt <= '0;
                            iss         <= '0;
                            wcnt        <= '0;
                            r_pe_busy   <= 1'b1;
                            st          <= (GUARD == 0) ? S_RD_IN : S_GUARD_IN;
                        end
                    end
                end
                // ---------------------------------------------------------
                S_GUARD_IN: begin
                    if (wcnt >= GUARD - 1) begin
                        wcnt <= '0;
                        st   <= S_RD_IN;
                    end else
                        wcnt <= wcnt + 32'd1;
                end
                // ---------------------------------------------------------
                S_RD_IN: begin
                    if (iss != CW'(r_in_len)) begin
                        r_ceb  <= 1'b0;
                        r_web  <= 1'b1;                            // read
                        r_addr <= r_in_base + L1_AW'(iss);
                        iss    <= iss + 1'b1;
                    end else begin
                        r_ceb <= 1'b1;
                        iss   <= '0;
                        st    <= S_RD_W;
                    end
                end
                // ---------------------------------------------------------
                S_RD_W: begin
                    if (iss != CW'(r_w_len)) begin
                        r_wceb  <= 1'b0;                           // read
                        r_waddr <= r_w_base + W_AW'(iss);
                        iss     <= iss + 1'b1;
                    end else begin
                        r_wceb <= 1'b1;
                        iss    <= '0;
                        if (r_lat == 32'd0) st <= S_WR_OUT;
                        else begin
                            wcnt <= r_lat;
                            st   <= S_WAIT;
                        end
                    end
                end
                // ---------------------------------------------------------
                S_WAIT: begin
                    if (wcnt <= 32'd1) st <= S_WR_OUT;
                    else               wcnt <= wcnt - 32'd1;
                end
                // ---------------------------------------------------------
                S_WR_OUT: begin
                    // stage 1 : Golden BRAM read issue
                    if (iss != CW'(r_out_len)) begin
                        r_braddr <= iss[BAW-1:0];
                        p1_v     <= 1'b1;
                        p1_idx   <= OUT_LW'(iss);
                        iss      <= iss + 1'b1;
                    end else
                        p1_v <= 1'b0;
                    // stage 2 : gold_q is valid next cycle -> drive the L1 write now
                    r_ceb    <= ~p1_v;
                    r_web    <= ~p1_v;                             // write
                    r_addr   <= r_out_base + L1_AW'(p1_idx);
                    r_wr_idx <= p1_idx;
                    if (iss == CW'(r_out_len) && !p1_v && r_ceb) begin  // last write done
                        r_web <= 1'b1;
                        wcnt  <= '0;
                        if (GUARD == 0) begin
                            r_pe_busy <= 1'b0;
                            st        <= S_DONE;
                        end else
                            st <= S_GUARD_OUT;
                    end
                end
                // ---------------------------------------------------------
                S_GUARD_OUT: begin
                    if (wcnt >= GUARD - 1) begin
                        r_pe_busy <= 1'b0;
                        st        <= S_DONE;
                    end else
                        wcnt <= wcnt + 32'd1;
                end
                // ---------------------------------------------------------
                default: st <= S_IDLE;
            endcase
        end
    end

endmodule
