`timescale 1ns/1ps
// =============================================================================
//  axi_lite_ctrl  -  PS(AXI4-Lite, 32b) -> L2 명령 / Blackbox 레지스터 / BRAM 쓰기 창
//
//  off   name         R/W  내용
//  0x00  CMD_LO       RW   명령어 [31:0]
//  0x04  CMD_HI       RW   명령어 [63:32]
//  0x08  CMD_PUSH     W    bit0=1 -> o_command_valid 1클럭 펄스
//                          (그 클럭에 i_command_ready=0 이면 STATUS.cmd_overflow)
//  0x0C  STATUS       R    bit0 cmd_ready, bit1 busy_ch1_in, bit2 cmd_overflow (sticky),
//                          bit3 busy_ch2_in, bit4 busy_ch1_wgt
//  --- 입력 / 출력 Blackbox (512b) ---
//  0x20  BB_CTRL      RW   bit0 START (쓰기 펄스, 읽으면 0), bit2:1 inject,
//                          bit3 OUT_SEL (0 = L1 OUT 영역 -> ch1_in STORE, 1 = L2 ch2_in store 로 직접),
//                          bit4 C2_HS (ch2 handshake)
//  0x24  BB_IN        RW   [10:0] base, [24:16] len
//  0x28  BB_OUT       RW   [10:0] base, [24:16] len           (OUT_SEL=0 일 때)
//  0x2C  BB_LATENCY   RW   32b
//  0x30  BB_STATUS    R    bit0 busy, bit1 done, bit2 first_mm_valid, bit3 err_start_busy
//  0x34  BB_MISMATCH  R    [15:0] cnt, [31:16] first_idx
//  0x38  BB_MM_GOT    R    첫 불일치 beat 하위 32b (L1 에서 읽은 값)
//  0x3C  BB_MM_EXP    R    첫 불일치 beat 하위 32b (Expected)
//  0x40  BB_CYCLES    R    START~DONE 클럭 수
//  0x44  BRAM_ADDR    RW   [7:0] addr, bit8 sel (0=Expected, 1=Golden)
//  0x48  BRAM_COMMIT  W    bit0=1 -> WDATA 창(512b)을 BRAM[sel][addr] 에 기록, addr 자동 +1
//  0x4C  BB_C2_CFG    RW   [9:0] W, [19:10] H, [26:20] NB (256b beat / 위치), bit31 PREC 필드 (0 8b, 1 32b)
//  0x80~0xBC BRAM_WDATA[0..15] RW  512b 쓰기 창, 0x80 = bit[31:0]
//  --- weight Blackbox (256b, ch1_wgt 쪽 cluster array 검사) ---
//  0x120 WBB_CTRL     RW   bit0 START (펄스), bit2:1 inject
//  0x124 WBB_IN       RW   [9:0] base, [26:16] len (1..1024)
//  0x130 WBB_STATUS   R    BB_STATUS 와 같은 형식
//  0x134 WBB_MISMATCH R    [15:0] cnt, [31:16] first_idx
//  0x138 WBB_MM_GOT / 0x13C WBB_MM_EXP / 0x140 WBB_CYCLES   R
//  0x144 WBRAM_ADDR   RW   [9:0] Expected 주소
//  0x148 WBRAM_COMMIT W    bit0=1 -> 쓰기 창 아래 256b (0x80~0x9C) 를 weight Expected[addr] 에 기록, addr +1
//
//  - 정의 안 된 주소: 읽으면 0, 쓰기 무시, 응답은 항상 OKAY
//  - WSTRB 는 일반 레지스터에 바이트 단위로 적용. 펄스 레지스터는 wstrb[0] & wdata[0]
//  - cmd_overflow / err_start_busy 는 리셋으로만 해제 (TODO(JH): W1C 로 할지)
//  - 한 번에 쓰기 1개, 읽기 1개 (outstanding 1). 합성 가능 RTL.
// =============================================================================
module axi_lite_ctrl #(
    parameter int ADDR_W = 12,
    parameter int DW     = 512,      // Blackbox BRAM width
    parameter int L1_AW  = 11,
    parameter int BAW    = 8,
    localparam int LW    = BAW + 1,
    localparam int WDW   = 256,      // weight Blackbox width
    localparam int WAW   = 10        // weight L1 / Expected address width
)(
    input  wire              clk,
    input  wire              rstn,

    // ---- AXI4-Lite slave --------------------------------------------------
    input  wire [ADDR_W-1:0] s_axil_awaddr,
    input  wire [2:0]        s_axil_awprot,
    input  wire              s_axil_awvalid,
    output wire              s_axil_awready,
    input  wire [31:0]       s_axil_wdata,
    input  wire [3:0]        s_axil_wstrb,
    input  wire              s_axil_wvalid,
    output wire              s_axil_wready,
    output wire [1:0]        s_axil_bresp,
    output reg               s_axil_bvalid,
    input  wire              s_axil_bready,
    input  wire [ADDR_W-1:0] s_axil_araddr,
    input  wire [2:0]        s_axil_arprot,
    input  wire              s_axil_arvalid,
    output wire              s_axil_arready,
    output reg  [31:0]       s_axil_rdata,
    output wire [1:0]        s_axil_rresp,
    output reg               s_axil_rvalid,
    input  wire              s_axil_rready,

    // ---- L2 command ---------------------------------------------------------
    output wire [63:0]       o_command,
    output reg               o_command_valid,
    input  wire              i_command_ready,
    input  wire              i_busy_ch1_in,
    input  wire              i_busy_ch2_in,
    input  wire              i_busy_ch1_wgt,

    // ---- Blackbox control -----------------------------------------------------
    output reg               o_bb_start,
    output wire [1:0]        o_bb_inject,
    output wire              o_bb_out_sel,
    output wire              o_bb_c2_hs,
    output wire              o_bb_c2_prec,
    output wire [9:0]        o_bb_c2_h,
    output wire [9:0]        o_bb_c2_w,
    output wire [6:0]        o_bb_c2_nb,
    output wire [L1_AW-1:0]  o_bb_in_base,
    output wire [LW-1:0]     o_bb_in_len,
    output wire [L1_AW-1:0]  o_bb_out_base,
    output wire [LW-1:0]     o_bb_out_len,
    output wire [31:0]       o_bb_latency,
    output reg               o_bram_we,
    output reg               o_bram_sel,
    output reg  [BAW-1:0]    o_bram_addr,
    output wire [DW-1:0]     o_bram_wdata,

    // ---- Blackbox status ------------------------------------------------------
    input  wire              i_bb_busy,
    input  wire              i_bb_done,
    input  wire              i_bb_first_mm_valid,
    input  wire              i_bb_err_start_busy,
    input  wire [15:0]       i_bb_mismatch_cnt,
    input  wire [15:0]       i_bb_first_mm_idx,
    input  wire [31:0]       i_bb_first_mm_got,
    input  wire [31:0]       i_bb_first_mm_exp,
    input  wire [31:0]       i_bb_cycle_cnt,

    // ---- weight Blackbox control / status ---------------------------------------
    output reg               o_wbb_start,
    output wire [1:0]        o_wbb_inject,
    output wire [WAW-1:0]    o_wbb_in_base,
    output wire [WAW:0]      o_wbb_in_len,
    output reg               o_wbram_we,
    output reg  [WAW-1:0]    o_wbram_addr,
    output wire [WDW-1:0]    o_wbram_wdata,
    input  wire              i_wbb_busy,
    input  wire              i_wbb_done,
    input  wire              i_wbb_first_mm_valid,
    input  wire              i_wbb_err_start_busy,
    input  wire [15:0]       i_wbb_mismatch_cnt,
    input  wire [15:0]       i_wbb_first_mm_idx,
    input  wire [31:0]       i_wbb_first_mm_got,
    input  wire [31:0]       i_wbb_first_mm_exp,
    input  wire [31:0]       i_wbb_cycle_cnt
);

    localparam int NWIN = DW / 32;   // 16

    // ---- registers --------------------------------------------------------------
    reg [31:0] r_cmd_lo, r_cmd_hi;
    reg        r_cmd_overflow;
    reg [1:0]  r_inject;
    reg        r_out_sel, r_c2_hs;
    reg [31:0] r_bb_in, r_bb_out, r_bb_lat, r_c2_cfg;
    reg [BAW-1:0] r_bram_addr;
    reg        r_bram_sel;
    reg [31:0] r_win [0:NWIN-1];
    reg [1:0]  r_winject;
    reg [31:0] r_wbb_in;
    reg [WAW-1:0] r_wbram_addr;

    assign o_command     = {r_cmd_hi, r_cmd_lo};
    assign o_bb_inject   = r_inject;
    assign o_bb_out_sel  = r_out_sel;
    assign o_bb_c2_hs    = r_c2_hs;
    assign o_bb_c2_w     = r_c2_cfg[9:0];
    assign o_bb_c2_h     = r_c2_cfg[19:10];
    assign o_bb_c2_nb    = r_c2_cfg[26:20];
    assign o_bb_c2_prec  = r_c2_cfg[31];
    assign o_bb_in_base  = r_bb_in[L1_AW-1:0];
    assign o_bb_in_len   = r_bb_in[16 +: LW];
    assign o_bb_out_base = r_bb_out[L1_AW-1:0];
    assign o_bb_out_len  = r_bb_out[16 +: LW];
    assign o_bb_latency  = r_bb_lat;
    assign o_wbb_inject  = r_winject;
    assign o_wbb_in_base = r_wbb_in[WAW-1:0];
    assign o_wbb_in_len  = r_wbb_in[16 +: WAW+1];

    genvar gi;
    generate
        for (gi = 0; gi < NWIN; gi = gi + 1) begin : g_win
            assign o_bram_wdata[gi*32 +: 32] = r_win[gi];
        end
    endgenerate
    assign o_wbram_wdata = o_bram_wdata[WDW-1:0];   // weight window = lower 256b of the same window

    // ---- AXI write channel --------------------------------------------------------
    reg              aw_full, w_full;
    reg [ADDR_W-1:0] aw_addr_q;
    reg [31:0]       w_data_q;
    reg [3:0]        w_strb_q;

    assign s_axil_awready = !aw_full && !s_axil_bvalid;
    assign s_axil_wready  = !w_full  && !s_axil_bvalid;
    assign s_axil_bresp   = 2'b00;

    wire       do_write = aw_full && w_full && !s_axil_bvalid;
    wire [8:0] w_off    = {aw_addr_q[8:2], 2'b00};
    wire       pulse_b0 = w_strb_q[0] && w_data_q[0];

    function automatic [31:0] strb_merge(input [31:0] old_v, input [31:0] new_v, input [3:0] s);
        strb_merge = { s[3] ? new_v[31:24] : old_v[31:24],
                       s[2] ? new_v[23:16] : old_v[23:16],
                       s[1] ? new_v[15:8]  : old_v[15:8],
                       s[0] ? new_v[7:0]   : old_v[7:0] };
    endfunction

    integer i;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            aw_full <= 1'b0; w_full <= 1'b0; s_axil_bvalid <= 1'b0;
            aw_addr_q <= '0; w_data_q <= '0; w_strb_q <= '0;
            r_cmd_lo <= '0; r_cmd_hi <= '0; r_cmd_overflow <= 1'b0;
            r_inject <= '0; r_out_sel <= 1'b0; r_c2_hs <= 1'b0;
            r_bb_in <= '0; r_bb_out <= '0; r_bb_lat <= '0; r_c2_cfg <= '0;
            r_bram_addr <= '0; r_bram_sel <= 1'b0;
            for (i = 0; i < NWIN; i = i + 1) r_win[i] <= '0;
            r_winject <= '0; r_wbb_in <= '0; r_wbram_addr <= '0;
            o_command_valid <= 1'b0;
            o_bb_start <= 1'b0; o_wbb_start <= 1'b0;
            o_bram_we <= 1'b0; o_bram_sel <= 1'b0; o_bram_addr <= '0;
            o_wbram_we <= 1'b0; o_wbram_addr <= '0;
        end else begin
            // one-clock pulses
            o_command_valid <= 1'b0;
            o_bb_start      <= 1'b0;
            o_wbb_start     <= 1'b0;
            o_bram_we       <= 1'b0;
            o_wbram_we      <= 1'b0;

            // L2 handshake check : valid is up for exactly this clock
            if (o_command_valid && !i_command_ready) r_cmd_overflow <= 1'b1;

            if (s_axil_awvalid && s_axil_awready) begin aw_full <= 1'b1; aw_addr_q <= s_axil_awaddr; end
            if (s_axil_wvalid  && s_axil_wready)  begin w_full  <= 1'b1; w_data_q <= s_axil_wdata; w_strb_q <= s_axil_wstrb; end
            if (s_axil_bvalid  && s_axil_bready)  s_axil_bvalid <= 1'b0;

            if (do_write) begin
                aw_full <= 1'b0;
                w_full  <= 1'b0;
                s_axil_bvalid <= 1'b1;
                case (w_off)
                    9'h000: r_cmd_lo <= strb_merge(r_cmd_lo, w_data_q, w_strb_q);
                    9'h004: r_cmd_hi <= strb_merge(r_cmd_hi, w_data_q, w_strb_q);
                    9'h008: if (pulse_b0) o_command_valid <= 1'b1;
                    9'h020: begin
                        if (w_strb_q[0]) begin
                            r_inject  <= w_data_q[2:1];
                            r_out_sel <= w_data_q[3];
                            r_c2_hs   <= w_data_q[4];
                        end
                        if (pulse_b0) o_bb_start <= 1'b1;
                    end
                    9'h024: r_bb_in  <= strb_merge(r_bb_in,  w_data_q, w_strb_q);
                    9'h028: r_bb_out <= strb_merge(r_bb_out, w_data_q, w_strb_q);
                    9'h02C: r_bb_lat <= strb_merge(r_bb_lat, w_data_q, w_strb_q);
                    9'h044: begin
                        if (w_strb_q[0]) r_bram_addr <= w_data_q[BAW-1:0];
                        if (w_strb_q[1]) r_bram_sel  <= w_data_q[8];
                    end
                    9'h048: if (pulse_b0) begin
                        o_bram_we   <= 1'b1;
                        o_bram_sel  <= r_bram_sel;
                        o_bram_addr <= r_bram_addr;
                        r_bram_addr <= r_bram_addr + 1'b1;
                    end
                    9'h04C: r_c2_cfg <= strb_merge(r_c2_cfg, w_data_q, w_strb_q);
                    9'h120: begin
                        if (w_strb_q[0]) r_winject <= w_data_q[2:1];
                        if (pulse_b0)    o_wbb_start <= 1'b1;
                    end
                    9'h124: r_wbb_in <= strb_merge(r_wbb_in, w_data_q, w_strb_q);
                    9'h144: r_wbram_addr <= strb_merge({22'd0, r_wbram_addr}, w_data_q, w_strb_q) & 32'h3FF;
                    9'h148: if (pulse_b0) begin
                        o_wbram_we   <= 1'b1;
                        o_wbram_addr <= r_wbram_addr;
                        r_wbram_addr <= r_wbram_addr + 1'b1;
                    end
                    default: begin
                        if (w_off >= 9'h080 && w_off <= 9'h0BC)
                            r_win[w_off[5:2]] <= strb_merge(r_win[w_off[5:2]], w_data_q, w_strb_q);
                    end
                endcase
            end
        end
    end

    // ---- AXI read channel ----------------------------------------------------------
    assign s_axil_arready = !s_axil_rvalid;
    assign s_axil_rresp   = 2'b00;

    wire [8:0] r_off = {s_axil_araddr[8:2], 2'b00};
    reg  [31:0] rmux;
    always @(*) begin
        rmux = 32'd0;
        case (r_off)
            9'h000: rmux = r_cmd_lo;
            9'h004: rmux = r_cmd_hi;
            9'h00C: rmux = {27'd0, i_busy_ch1_wgt, i_busy_ch2_in, r_cmd_overflow, i_busy_ch1_in, i_command_ready};
            9'h020: rmux = {27'd0, r_c2_hs, r_out_sel, r_inject, 1'b0};
            9'h024: rmux = r_bb_in;
            9'h028: rmux = r_bb_out;
            9'h02C: rmux = r_bb_lat;
            9'h030: rmux = {28'd0, i_bb_err_start_busy, i_bb_first_mm_valid, i_bb_done, i_bb_busy};
            9'h034: rmux = {i_bb_first_mm_idx, i_bb_mismatch_cnt};
            9'h038: rmux = i_bb_first_mm_got;
            9'h03C: rmux = i_bb_first_mm_exp;
            9'h040: rmux = i_bb_cycle_cnt;
            9'h044: rmux = {23'd0, r_bram_sel, r_bram_addr};
            9'h04C: rmux = r_c2_cfg;
            9'h120: rmux = {29'd0, r_winject, 1'b0};
            9'h124: rmux = r_wbb_in;
            9'h130: rmux = {28'd0, i_wbb_err_start_busy, i_wbb_first_mm_valid, i_wbb_done, i_wbb_busy};
            9'h134: rmux = {i_wbb_first_mm_idx, i_wbb_mismatch_cnt};
            9'h138: rmux = i_wbb_first_mm_got;
            9'h13C: rmux = i_wbb_first_mm_exp;
            9'h140: rmux = i_wbb_cycle_cnt;
            9'h144: rmux = {22'd0, r_wbram_addr};
            default: if (r_off >= 9'h080 && r_off <= 9'h0BC) rmux = r_win[r_off[5:2]];
        endcase
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            s_axil_rvalid <= 1'b0;
            s_axil_rdata  <= '0;
        end else begin
            if (s_axil_arvalid && s_axil_arready) begin
                s_axil_rvalid <= 1'b1;
                s_axil_rdata  <= rmux;
            end else if (s_axil_rvalid && s_axil_rready)
                s_axil_rvalid <= 1'b0;
        end
    end

endmodule
