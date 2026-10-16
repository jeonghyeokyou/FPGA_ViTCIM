`timescale 1ns/1ps
// =============================================================================
//  blackbox_pe  -  실제 MAC IP 자리에 들어가는 "PE 흉내" (BLACKBOX_TASK.md 7절)
//
//  IDLE -START&!noc_busy-> GUARD_IN -> RD_IN -> WAIT -> WR_OUT -> GUARD_OUT -> DONE
//  pe_busy :  0                1          1       1        1          1          0
//
//  RD_IN  : L1[in_base+k] 를 읽어 Expected[k] 와 비교 (CP-A)
//  WAIT   : i_latency 클럭 대기 (0 이면 건너뜀). 정확히 latency 클럭 머문다.
//  WR_OUT : Golden[k] 를 L1[out_base+k] 에 씀
//
//  1클럭 지연 맞추기 (가장 흔한 실수 지점)
//  ---------------------------------------------------------------------------
//  L1 SRAM(sram_mimic)도, Expected/Golden BRAM 도 "주소를 클럭 엣지에서 받고, 그 다음
//  사이클에 데이터가 나오는" 1클럭 지연 메모리다. 그래서 둘 다 **같은 엣지에 같은 레지스터에서
//  나온 주소**를 받게 만들었다:
//     엣지 E_k   : r_addr <= in_base+k ,  r_braddr <= k ,  p1_v/p1_idx <= 1/k   (발행)
//     엣지 E_k+1 : SRAM r_dout <= L1[in_base+k],  exp_q <= Expected[k],  p2_v/p2_idx <= 1/k
//     E_k+1~E_k+2 사이 : i_dout 과 exp_q 가 같은 k 의 값 -> 비교, E_k+2 에 결과 기록
//  WR_OUT 은 반대 방향: Golden 을 먼저 읽고(E_k) 다음 엣지(E_k+1)에 ceb/web/addr 를
//  올려서, o_din = gold_q 가 그 사이클에 SRAM 입력으로 나간다 -> E_k+2 에 L1 에 기록.
//
//  설계 메모
//  - 길이 0 이면 해당 단계를 건너뛴다. 길이가 BRAM_DEPTH 보다 크면 BRAM 주소가 wrap 된다
//    (사양 범위 1~256 밖이므로 동작 보장 안 함).
//  - START 는 IDLE/DONE 에서만 받는다. 동작 중 START 는 무시.
//  - i_noc_busy=1 일 때 START -> 무시 + o_err_start_busy (sticky, 리셋으로만 해제)
//  - 리셋은 상태/카운터만 초기화. Expected/Golden BRAM 내용은 리셋 안 함 (BRAM 추론).
//  - TODO(JH) 12절-②: NoC 전송 도중 pe_busy 를 올리면 L1_FIFO_interface 가 출력을
//    조합논리로 0 으로 만든다. 여기서는 START 시점의 i_noc_busy 만 검사한다.
//  - 합성 가능 RTL (initial / #delay / $display 없음)
// =============================================================================
module blackbox_pe #(
    parameter int DW         = 512,
    parameter int L1_AW      = 11,
    parameter int BRAM_DEPTH = 256,
    parameter int GUARD      = 2,
    localparam int BAW       = $clog2(BRAM_DEPTH),   // 8
    localparam int LW        = BAW + 1                // 9  (1..256)
)(
    input  wire                 clk,
    input  wire                 rstn,

    // ---- control -------------------------------------------------------
    input  wire                 i_start,
    input  wire                 i_noc_busy,
    input  wire [L1_AW-1:0]     i_in_base,
    input  wire [LW-1:0]        i_in_len,
    input  wire [L1_AW-1:0]     i_out_base,
    input  wire [LW-1:0]        i_out_len,
    input  wire [31:0]          i_latency,
    input  wire [1:0]           i_inject,

    // ---- Expected / Golden BRAM load port ------------------------------
    input  wire                 i_bram_we,
    input  wire                 i_bram_sel,      // 0 = Expected, 1 = Golden
    input  wire [BAW-1:0]       i_bram_addr,
    input  wire [DW-1:0]        i_bram_wdata,

    // ---- L1 SRAM port (active-low) -------------------------------------
    output wire                 o_pe_busy,
    output wire                 o_ceb,
    output wire                 o_web,
    output wire [L1_AW-1:0]     o_addr,
    output wire [DW-1:0]        o_din,
    input  wire [DW-1:0]        i_dout,

    // ---- status ---------------------------------------------------------
    output wire                 o_busy,
    output wire                 o_done,
    output reg  [15:0]          o_mismatch_cnt,
    output reg  [15:0]          o_first_mm_idx,
    output reg                  o_first_mm_valid,
    output reg  [31:0]          o_first_mm_got,
    output reg  [31:0]          o_first_mm_exp,
    output reg                  o_err_start_busy,
    output reg  [31:0]          o_cycle_cnt
);

    localparam [2:0] S_IDLE      = 3'd0,
                     S_GUARD_IN  = 3'd1,
                     S_RD_IN     = 3'd2,
                     S_WAIT      = 3'd3,
                     S_WR_OUT    = 3'd4,
                     S_GUARD_OUT = 3'd5,
                     S_DONE      = 3'd6;

    reg  [2:0]        st;

    // latched job parameters
    reg  [L1_AW-1:0]  r_in_base, r_out_base;
    reg  [LW-1:0]     r_in_len,  r_out_len;
    reg  [31:0]       r_lat;
    reg  [1:0]        r_inj;

    reg  [LW-1:0]     iss;          // issue counter (RD / WR)
    reg  [31:0]       wcnt;         // guard / latency counter

    // L1 port registers
    reg               r_pe_busy;
    reg               r_ceb, r_web;
    reg  [L1_AW-1:0]  r_addr;
    reg  [LW-1:0]     r_wr_idx;

    // read pipeline
    reg  [BAW-1:0]    r_braddr;
    reg               p1_v, p2_v;
    reg  [LW-1:0]     p1_idx, p2_idx;

    // ---------------------------------------------------------------------
    //  Expected / Golden BRAM  (simple dual port: TB/AXI write, FSM read)
    // ---------------------------------------------------------------------
    (* ram_style = "block" *) reg [DW-1:0] exp_mem  [0:BRAM_DEPTH-1];
    (* ram_style = "block" *) reg [DW-1:0] gold_mem [0:BRAM_DEPTH-1];
    reg [DW-1:0] exp_q, gold_q;

    always @(posedge clk) begin
        if (i_bram_we && !i_bram_sel) exp_mem[i_bram_addr] <= i_bram_wdata;
        exp_q <= exp_mem[r_braddr];
    end

    always @(posedge clk) begin
        if (i_bram_we && i_bram_sel) gold_mem[i_bram_addr] <= i_bram_wdata;
        gold_q <= gold_mem[r_braddr];
    end

    // ---------------------------------------------------------------------
    //  compare (CP-A) : i_dout and exp_q belong to the same beat p2_idx
    // ---------------------------------------------------------------------
    wire          inj_exp  = r_inj[1] && (p2_idx == {LW{1'b0}});
    wire [DW-1:0] exp_cmp  = exp_q ^ {{(DW-1){1'b0}}, inj_exp};
    wire          mismatch = p2_v && (i_dout != exp_cmp);

    wire          inj_gold = r_inj[0] && (r_wr_idx == {LW{1'b0}});

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
            r_lat            <= '0;  r_inj      <= '0;
            iss              <= '0;  wcnt       <= '0;
            r_pe_busy        <= 1'b0;
            r_ceb            <= 1'b1; r_web     <= 1'b1;
            r_addr           <= '0;  r_wr_idx   <= '0;
            r_braddr         <= '0;
            p1_v             <= 1'b0; p2_v      <= 1'b0;
            p1_idx           <= '0;  p2_idx     <= '0;
            o_mismatch_cnt   <= '0;
            o_first_mm_idx   <= '0;
            o_first_mm_valid <= 1'b0;
            o_first_mm_got   <= '0;
            o_first_mm_exp   <= '0;
            o_err_start_busy <= 1'b0;
            o_cycle_cnt      <= '0;
        end else begin
            // read-compare pipeline stage 2 (only meaningful in RD_IN)
            p2_v   <= p1_v && (st == S_RD_IN);
            p2_idx <= p1_idx;

            if (o_busy) o_cycle_cnt <= o_cycle_cnt + 32'd1;

            if (mismatch) begin
                if (o_mismatch_cnt != 16'hFFFF) o_mismatch_cnt <= o_mismatch_cnt + 16'd1;
                if (!o_first_mm_valid) begin
                    o_first_mm_valid <= 1'b1;
                    o_first_mm_idx   <= 16'(p2_idx);
                    o_first_mm_got   <= i_dout[31:0];
                    o_first_mm_exp   <= exp_cmp[31:0];
                end
            end

            case (st)
                // ---------------------------------------------------------
                S_IDLE, S_DONE: begin
                    if (i_start) begin
                        if (i_noc_busy) begin
                            o_err_start_busy <= 1'b1;          // ignore START
                        end else begin
                            r_in_base        <= i_in_base;
                            r_in_len         <= i_in_len;
                            r_out_base       <= i_out_base;
                            r_out_len        <= i_out_len;
                            r_lat            <= i_latency;
                            r_inj            <= i_inject;
                            o_mismatch_cnt   <= '0;
                            o_first_mm_valid <= 1'b0;
                            o_first_mm_idx   <= '0;
                            o_first_mm_got   <= '0;
                            o_first_mm_exp   <= '0;
                            o_cycle_cnt      <= '0;
                            iss              <= '0;
                            wcnt             <= '0;
                            r_pe_busy        <= 1'b1;
                            st               <= (GUARD == 0) ? S_RD_IN : S_GUARD_IN;
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
                    if (iss != r_in_len) begin
                        r_ceb    <= 1'b0;
                        r_web    <= 1'b1;                          // read
                        r_addr   <= r_in_base + L1_AW'(iss);
                        r_braddr <= iss[BAW-1:0];
                        p1_v     <= 1'b1;
                        p1_idx   <= iss;
                        iss      <= iss + 1'b1;
                    end else begin
                        r_ceb <= 1'b1;
                        p1_v  <= 1'b0;
                        if (!p1_v && !p2_v) begin                  // pipeline drained
                            iss <= '0;
                            if (r_lat == 32'd0) st <= S_WR_OUT;
                            else begin
                                wcnt <= r_lat;
                                st   <= S_WAIT;
                            end
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
                    if (iss != r_out_len) begin
                        r_braddr <= iss[BAW-1:0];
                        p1_v     <= 1'b1;
                        p1_idx   <= iss;
                        iss      <= iss + 1'b1;
                    end else
                        p1_v <= 1'b0;
                    // stage 2 : gold_q is valid next cycle -> drive the L1 write now
                    r_ceb    <= ~p1_v;
                    r_web    <= ~p1_v;                             // write
                    r_addr   <= r_out_base + L1_AW'(p1_idx);
                    r_wr_idx <= p1_idx;
                    if (iss == r_out_len && !p1_v && r_ceb) begin  // last write done
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
