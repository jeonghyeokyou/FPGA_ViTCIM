`timescale 1ns/1ps
// =============================================================================
//  blackbox_nl  -  CH2 (nonlinear 쪽) 엔진 자리에 들어가는 "동작 모사" 모델 (256b)
//
//  하는 일 (연산은 하지 않는다)
//    1. weight 저장 : L2 ch2_wgt LOAD 가 NoC 로 보내는 weight 를 weight 메모리 (256b x 512) 에 저장
//    2. input 저장  : L2 ch2_in  LOAD 가 보내는 input 을 input 메모리 (256b x 2048) 에 저장
//                     (NoC 주소 15b = {PE/Accum, 14b} 중 하위 11b 만 사용)
//    3. input/weight 읽기 : 실행 중 두 메모리를 읽는다 (값은 쓰지 않음, 포트 점유만 모사)
//    4. output 생성 : PS 가 미리 넣어둔 Golden (256b x 256) 을 L2 ch2_in store 포트로 보낸다
//                     (BB 가 master : valid / addr {last,ch,h,w} / data 256b)
//    5. 디버그 읽기 : ch2 에는 weight / input 을 L2 로 되돌리는 STORE 가 없으므로,
//                     PS 가 AXI-Lite 로 두 메모리의 한 줄을 읽을 수 있게 한다.
//
//  실행 : IDLE -START-> GUARD_IN -> RD_IN -> RD_W -> WAIT -> (C2_RD -> C2_LAT -> C2_SEND)* -> GUARD_OUT -> DONE
//  디버그: IDLE -DBG->   GUARD_IN -> DBG_RD -> DBG_W1 -> DBG_CAP -> GUARD_OUT -> DONE
//  pe_busy 는 GUARD_IN ~ GUARD_OUT 동안 1 (두 메모리의 NoC 쓰기를 막는다).
//
//  ch2 출력 (rtl/fix/cmd_decoder_channel_2_in.sv BURST/HANDSHAKE_STORE 기준)
//  - Golden 1줄 = 1 beat (256b). beat 순서 : (jp, h, w) 마다 col 0, (있으면) col 1  ;  beat j = 2*jp+col
//  - 주소 : i_c2_prec=0 : {last, jp[4:0], col, 5'd0, h[9:0], w[9:0]}
//           i_c2_prec=1 : {last, jp[6:0], col, 3'd0, h[9:0], w[9:0]}
//    L2 는 (w + h*W + jp*H*W) 와 col 로 저장 위치를 정한다. last 는 마지막 beat 에서만 1.
//  - 전송 성립 : burst (i_c2_hs=0) 는 valid && i_c2_ready, handshake (i_c2_hs=1) 는 i_c2_resp 펄스.
//  - 이 모델은 1 beat 를 보내는 데 최소 3 클럭을 쓴다 (Golden 읽기 1클럭 지연 포함).
//
//  설계 메모
//  - 길이 0 이면 해당 단계를 건너뛴다. nb/h/w 중 하나라도 0 이면 출력 없음.
//  - START / DBG 는 IDLE/DONE 에서만 받는다. i_noc_busy=1 이면 무시 + o_err_start_busy (sticky).
//  - i_inject : 첫 출력 beat 의 bit0 을 뒤집는다 (PS 쪽 비교가 잡는지 확인용).
//  - 리셋은 상태/카운터만 초기화. 메모리 내용은 리셋하지 않음.
// =============================================================================
module blackbox_nl #(
    parameter int DW         = 256,
    parameter int I_DEPTH    = 2048,    // input memory rows
    parameter int W_DEPTH    = 512,     // weight memory rows
    parameter int G_DEPTH    = 256,     // Golden rows
    parameter int GUARD      = 2,
    localparam int I_AW      = $clog2(I_DEPTH),   // 11
    localparam int W_AW      = $clog2(W_DEPTH),   // 9
    localparam int BAW       = $clog2(G_DEPTH),   // 8
    localparam int IN_LW     = I_AW + 1,          // 12 (0..2048)
    localparam int W_LW      = W_AW + 1,          // 10 (0..512)
    localparam int CW        = IN_LW              // issue counter width
)(
    input  wire                 clk,
    input  wire                 rstn,

    // ---- control -------------------------------------------------------
    input  wire                 i_start,
    input  wire                 i_dbg_req,       // debug read of one row (pulse)
    input  wire                 i_dbg_sel,       // 0 = input memory, 1 = weight memory
    input  wire [I_AW-1:0]      i_dbg_row,
    input  wire                 i_noc_busy,
    input  wire [I_AW-1:0]      i_in_base,
    input  wire [IN_LW-1:0]     i_in_len,
    input  wire [W_AW-1:0]      i_w_base,
    input  wire [W_LW-1:0]      i_w_len,
    input  wire [31:0]          i_latency,
    input  wire                 i_inject,
    input  wire                 i_c2_prec,       // ch2 address channel-field layout (0 = 8b, 1 = 32b)
    input  wire                 i_c2_hs,         // ch2 handshake mode
    input  wire [9:0]           i_c2_h,          // height
    input  wire [9:0]           i_c2_w,          // width
    input  wire [6:0]           i_c2_nb,         // 256b beats (channel groups) per position

    // ---- Golden BRAM load port -----------------------------------------
    input  wire                 i_gold_we,
    input  wire [BAW-1:0]       i_gold_addr,
    input  wire [DW-1:0]        i_gold_wdata,

    // ---- input memory NoC write port (ch2_in LOAD) ---------------------
    input  wire                 i_i_write_valid,
    output wire                 o_i_write_ready,
    input  wire [I_AW-1:0]      i_i_write_addr,
    input  wire [DW-1:0]        i_i_write_data,
    input  wire                 i_i_control_mode,
    output wire                 o_i_FIFO_write_ready,
    output wire                 o_i_noc_write_commit,
    output wire                 o_i_port_conflict,

    // ---- weight memory NoC write port (ch2_wgt LOAD) -------------------
    input  wire                 i_w_write_valid,
    output wire                 o_w_write_ready,
    input  wire [W_AW-1:0]      i_w_write_addr,
    input  wire [DW-1:0]        i_w_write_data,
    input  wire                 i_w_control_mode,
    output wire                 o_w_FIFO_write_ready,
    output wire                 o_w_noc_write_commit,
    output wire                 o_w_port_conflict,

    // ---- L2 ch2_in store port (BB is the master) -----------------------
    output wire                 o_c2_valid,
    output wire [31:0]          o_c2_addr,
    output wire [DW-1:0]        o_c2_data,
    input  wire                 i_c2_ready,      // L2 o_noc_read_ready_channel_2_in
    input  wire                 i_c2_resp,       // L2 o_noc_read_response_channel_2_in

    // ---- status ---------------------------------------------------------
    output wire                 o_busy,
    output wire                 o_done,
    output reg                  o_err_start_busy,
    output reg  [31:0]          o_cycle_cnt,
    output reg  [DW-1:0]        o_dbg_data,
    output reg                  o_dbg_valid
);

    localparam [3:0] S_IDLE      = 4'd0,
                     S_GUARD_IN  = 4'd1,
                     S_RD_IN     = 4'd2,
                     S_RD_W      = 4'd3,
                     S_WAIT      = 4'd4,
                     S_C2_RD     = 4'd5,
                     S_C2_LAT    = 4'd6,
                     S_C2_SEND   = 4'd7,
                     S_GUARD_OUT = 4'd8,
                     S_DONE      = 4'd9,
                     S_DBG_RD    = 4'd10,
                     S_DBG_W1    = 4'd11,
                     S_DBG_CAP   = 4'd12;

    reg  [3:0]         st;

    // latched job parameters
    reg                r_dbg, r_dbg_sel;
    reg  [I_AW-1:0]    r_dbg_row;
    reg  [I_AW-1:0]    r_in_base;
    reg  [IN_LW-1:0]   r_in_len;
    reg  [W_AW-1:0]    r_w_base;
    reg  [W_LW-1:0]    r_w_len;
    reg  [31:0]        r_lat;
    reg                r_inj;
    reg                r_c2_prec, r_c2_hs;
    reg  [9:0]         r_c2_h, r_c2_w;
    reg  [6:0]         r_c2_nb;

    reg  [CW-1:0]      iss;          // issue counter (RD_IN / RD_W)
    reg  [31:0]        wcnt;         // guard / latency counter

    // memory PE port registers (read only)
    reg                r_pe_busy;
    reg                r_iceb, r_wceb;
    reg  [I_AW-1:0]    r_iaddr;
    reg  [W_AW-1:0]    r_waddr;

    // ch2 output counters : word order (jp, h, w), beat col inside the position
    reg  [BAW-1:0]     r_braddr;     // Golden row = beat index k
    reg  [5:0]         c2_jp;
    reg  [9:0]         c2_hh, c2_ww;
    reg                c2_col;
    reg                c2_first;

    // ---------------------------------------------------------------------
    //  Golden BRAM  (simple dual port: AXI-Lite write, FSM read)
    // ---------------------------------------------------------------------
    (* ram_style = "block" *) reg [DW-1:0] gold_mem [0:G_DEPTH-1];
    reg [DW-1:0] gold_q;

    always @(posedge clk) begin
        if (i_gold_we) gold_mem[i_gold_addr] <= i_gold_wdata;
        gold_q <= gold_mem[r_braddr];
    end

    // ---------------------------------------------------------------------
    //  input / weight memory : NoC writes (ch2_in / ch2_wgt LOAD), FSM reads
    //  (NoC read side unused : ch2 has no STORE from these memories)
    // ---------------------------------------------------------------------
    wire [DW-1:0] i_pe_dout, w_pe_dout;

    FIFO_intf_bb #(.ADDR_DEPTH(I_DEPTH), .DATA_WIDTH(DW), .MEMORY_BITWIDTH(DW/4),
                   .FIFO_DEPTH(8), .INPUT_DELAY(3)) u_imem (
        .clk(clk), .rstb(rstn),
        .i_read_valid(1'b0), .o_read_ready(), .i_read_addr({I_AW{1'b0}}), .o_read_data(),
        .i_write_valid(i_i_write_valid), .o_write_ready(o_i_write_ready),
        .i_write_addr(i_i_write_addr),   .i_write_data(i_i_write_data),
        .i_control_mode(i_i_control_mode),
        .o_FIFO_read_ready(), .o_FIFO_write_ready(o_i_FIFO_write_ready),
        .i_data_fifo_ready(1'b0),
        .i_pe_busy(r_pe_busy), .i_pe_ceb(r_iceb), .i_pe_web(1'b1), .i_pe_addr(r_iaddr),
        .i_pe_din({DW{1'b0}}), .o_pe_dout(i_pe_dout),
        .o_noc_write_commit(o_i_noc_write_commit), .o_port_conflict(o_i_port_conflict));

    FIFO_intf_bb #(.ADDR_DEPTH(W_DEPTH), .DATA_WIDTH(DW), .MEMORY_BITWIDTH(DW/4),
                   .FIFO_DEPTH(8), .INPUT_DELAY(3)) u_wmem (
        .clk(clk), .rstb(rstn),
        .i_read_valid(1'b0), .o_read_ready(), .i_read_addr({W_AW{1'b0}}), .o_read_data(),
        .i_write_valid(i_w_write_valid), .o_write_ready(o_w_write_ready),
        .i_write_addr(i_w_write_addr),   .i_write_data(i_w_write_data),
        .i_control_mode(i_w_control_mode),
        .o_FIFO_read_ready(), .o_FIFO_write_ready(o_w_FIFO_write_ready),
        .i_data_fifo_ready(1'b0),
        .i_pe_busy(r_pe_busy), .i_pe_ceb(r_wceb), .i_pe_web(1'b1), .i_pe_addr(r_waddr),
        .i_pe_din({DW{1'b0}}), .o_pe_dout(w_pe_dout),
        .o_noc_write_commit(o_w_noc_write_commit), .o_port_conflict(o_w_port_conflict));

    // ---------------------------------------------------------------------
    //  ch2 beat
    // ---------------------------------------------------------------------
    wire        c2_has_hi   = ({c2_jp, 1'b1} < r_c2_nb);             // beat 2*jp+1 exists
    wire        c2_last_pos = (c2_hh == r_c2_h - 10'd1) && (c2_ww == r_c2_w - 10'd1);
    wire        c2_last_jp  = ({1'b0, c2_jp, 1'b0} + 8'd2 >= {1'b0, r_c2_nb});   // last channel group
    wire        c2_last     = c2_last_pos && c2_last_jp && (c2_col || !c2_has_hi);
    wire [6:0]  c2_jfield   = {1'b0, c2_jp};
    wire [31:0] c2_addr_8b  = {c2_last, c2_jfield[4:0], c2_col, 5'd0, c2_hh, c2_ww};
    wire [31:0] c2_addr_32b = {c2_last, c2_jfield[6:0], c2_col, 3'd0, c2_hh, c2_ww};
    // valid / addr are registers (timing: they fan out to the whole L2 ch2_in input FIFO).
    // r_c2_valid == (st == S_C2_SEND) : set when entering C2_SEND, cleared when the beat is accepted.
    reg         r_c2_valid;
    reg  [31:0] r_c2_addr;
    wire        c2_acc      = r_c2_valid && (r_c2_hs ? i_c2_resp : i_c2_ready);

    // ---------------------------------------------------------------------
    //  outputs
    // ---------------------------------------------------------------------
    assign o_c2_valid = r_c2_valid;
    assign o_c2_addr  = r_c2_addr;
    assign o_c2_data  = gold_q ^ {{(DW-1){1'b0}}, (r_inj && c2_first)};
    assign o_busy     = (st != S_IDLE) && (st != S_DONE);
    assign o_done     = (st == S_DONE);

    // ---------------------------------------------------------------------
    //  FSM
    // ---------------------------------------------------------------------
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            st               <= S_IDLE;
            r_dbg            <= 1'b0; r_dbg_sel <= 1'b0; r_dbg_row <= '0;
            r_in_base        <= '0;  r_in_len   <= '0;
            r_w_base         <= '0;  r_w_len    <= '0;
            r_lat            <= '0;  r_inj      <= 1'b0;
            r_c2_prec        <= 1'b0; r_c2_hs   <= 1'b0;
            r_c2_h           <= '0;  r_c2_w     <= '0;  r_c2_nb <= '0;
            iss              <= '0;  wcnt       <= '0;
            r_pe_busy        <= 1'b0;
            r_iceb           <= 1'b1; r_iaddr   <= '0;
            r_wceb           <= 1'b1; r_waddr   <= '0;
            r_braddr         <= '0;
            c2_jp            <= '0;  c2_hh      <= '0;  c2_ww <= '0;
            c2_col           <= 1'b0; c2_first  <= 1'b0;
            r_c2_valid       <= 1'b0; r_c2_addr <= '0;
            o_err_start_busy <= 1'b0;
            o_cycle_cnt      <= '0;
            o_dbg_data       <= '0;
            o_dbg_valid      <= 1'b0;
        end else begin
            if (o_busy && !r_dbg) o_cycle_cnt <= o_cycle_cnt + 32'd1;

            case (st)
                // ---------------------------------------------------------
                S_IDLE, S_DONE: begin
                    if (i_start || i_dbg_req) begin
                        if (i_noc_busy) begin
                            o_err_start_busy <= 1'b1;          // ignore START / DBG
                        end else begin
                            r_dbg       <= i_dbg_req && !i_start;
                            r_dbg_sel   <= i_dbg_sel;
                            r_dbg_row   <= i_dbg_row;
                            if (i_start) begin
                                r_in_base   <= i_in_base;
                                r_in_len    <= i_in_len;
                                r_w_base    <= i_w_base;
                                r_w_len     <= i_w_len;
                                r_lat       <= i_latency;
                                r_inj       <= i_inject;
                                r_c2_prec   <= i_c2_prec;
                                r_c2_hs     <= i_c2_hs;
                                r_c2_h      <= i_c2_h;
                                r_c2_w      <= i_c2_w;
                                r_c2_nb     <= i_c2_nb;
                                o_cycle_cnt <= '0;
                                r_braddr    <= '0;
                                c2_jp       <= '0; c2_hh <= '0; c2_ww <= '0; c2_col <= 1'b0;
                                c2_first    <= 1'b1;
                            end else
                                o_dbg_valid <= 1'b0;
                            iss         <= '0;
                            wcnt        <= '0;
                            r_pe_busy   <= 1'b1;
                            st          <= S_GUARD_IN;
                        end
                    end
                end
                // ---------------------------------------------------------
                S_GUARD_IN: begin
                    if (wcnt >= GUARD - 1) begin
                        wcnt <= '0;
                        st   <= r_dbg ? S_DBG_RD : S_RD_IN;
                    end else
                        wcnt <= wcnt + 32'd1;
                end
                // ---------------------------------------------------------
                S_RD_IN: begin
                    if (iss != CW'(r_in_len)) begin
                        r_iceb  <= 1'b0;                           // read
                        r_iaddr <= r_in_base + I_AW'(iss);
                        iss     <= iss + 1'b1;
                    end else begin
                        r_iceb <= 1'b1;
                        iss    <= '0;
                        st     <= S_RD_W;
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
                        if (r_lat == 32'd0) st <= S_C2_RD;
                        else begin
                            wcnt <= r_lat;
                            st   <= S_WAIT;
                        end
                    end
                end
                // ---------------------------------------------------------
                S_WAIT: begin
                    if (wcnt <= 32'd1) st <= S_C2_RD;
                    else               wcnt <= wcnt - 32'd1;
                end
                // ---------------------------------------------------------
                //  ch2 output : one Golden row -> one beat
                // ---------------------------------------------------------
                S_C2_RD: begin                                     // r_braddr already points at beat k
                    if (r_c2_nb == 7'd0 || r_c2_h == 10'd0 || r_c2_w == 10'd0) begin
                        wcnt <= '0;
                        st   <= S_GUARD_OUT;
                    end else
                        st <= S_C2_LAT;
                end
                S_C2_LAT: begin                                    // gold_q <= Golden[k]
                    r_c2_valid <= 1'b1;
                    r_c2_addr  <= r_c2_prec ? c2_addr_32b : c2_addr_8b;   // counters are stable here
                    st         <= S_C2_SEND;
                end
                S_C2_SEND: begin
                    if (c2_acc) begin
                        r_c2_valid <= 1'b0;
                        c2_first <= 1'b0;
                        r_braddr <= r_braddr + 1'b1;
                        if (c2_last) begin
                            c2_jp <= '0; c2_hh <= '0; c2_ww <= '0; c2_col <= 1'b0;
                            r_braddr <= '0;
                            wcnt     <= '0;
                            st       <= S_GUARD_OUT;
                        end else begin
                            if (!c2_col && c2_has_hi)
                                c2_col <= 1'b1;                    // same position, beat j+1
                            else begin
                                c2_col <= 1'b0;
                                if (c2_ww == r_c2_w - 10'd1) begin
                                    c2_ww <= '0;
                                    if (c2_hh == r_c2_h - 10'd1) begin
                                        c2_hh <= '0;
                                        c2_jp <= c2_jp + 6'd1;
                                    end else
                                        c2_hh <= c2_hh + 10'd1;
                                end else
                                    c2_ww <= c2_ww + 10'd1;
                            end
                            st <= S_C2_RD;
                        end
                    end
                end
                // ---------------------------------------------------------
                //  debug read : one row of the input or weight memory
                // ---------------------------------------------------------
                S_DBG_RD: begin
                    if (r_dbg_sel) begin r_wceb <= 1'b0; r_waddr <= r_dbg_row[W_AW-1:0]; end
                    else           begin r_iceb <= 1'b0; r_iaddr <= r_dbg_row;             end
                    st <= S_DBG_W1;
                end
                S_DBG_W1: begin                                    // SRAM latches dout at this edge
                    r_iceb <= 1'b1;
                    r_wceb <= 1'b1;
                    st     <= S_DBG_CAP;
                end
                S_DBG_CAP: begin
                    o_dbg_data  <= r_dbg_sel ? w_pe_dout : i_pe_dout;
                    o_dbg_valid <= 1'b1;
                    wcnt        <= '0;
                    st          <= S_GUARD_OUT;
                end
                // ---------------------------------------------------------
                S_GUARD_OUT: begin
                    if (wcnt >= GUARD - 1) begin
                        r_pe_busy <= 1'b0;
                        r_dbg     <= 1'b0;
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
