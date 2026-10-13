`timescale 1ns/1ps
// =============================================================================
//  axi_lite_ctrl  -  PS(AXI4-Lite, 32b) -> L2 명령 / Blackbox 레지스터 / BRAM 쓰기 창
//  (BLACKBOX_TASK.md 10절 Phase 3 레지스터 맵)
//
//  off   name         R/W  내용
//  0x00  CMD_LO       RW   명령어 [31:0]
//  0x04  CMD_HI       RW   명령어 [63:32]
//  0x08  CMD_PUSH     W    bit0=1 -> o_command_valid 1클럭 펄스
//                          (그 클럭에 i_command_ready=0 이면 STATUS.cmd_overflow)
//  0x0C  STATUS       R    bit0 cmd_ready, bit1 busy_ch1_in, bit2 cmd_overflow (sticky)
//  0x20  BB_CTRL      RW   bit0 START (쓰기 펄스, 읽으면 0), bit2:1 inject
//  0x24  BB_IN        RW   [10:0] base, [24:16] len
//  0x28  BB_OUT       RW   [10:0] base, [24:16] len
//  0x2C  BB_LATENCY   RW   32b
//  0x30  BB_STATUS    R    bit0 busy, bit1 done, bit2 first_mm_valid, bit3 err_start_busy
//  0x34  BB_MISMATCH  R    [15:0] cnt, [31:16] first_idx
//  0x38  BB_MM_GOT    R    첫 불일치 beat 하위 32b (L1 에서 읽은 값)
//  0x3C  BB_MM_EXP    R    첫 불일치 beat 하위 32b (Expected)
//  0x40  BB_CYCLES    R    START~DONE 클럭 수
//  0x44  BRAM_ADDR    RW   [7:0] addr, bit8 sel (0=Expected, 1=Golden)
//  0x48  BRAM_COMMIT  W    bit0=1 -> WDATA 창(512b)을 BRAM[sel][addr] 에 기록, addr 자동 +1
//  0x80~0xBC BRAM_WDATA[0..15] RW  512b 쓰기 창, 0x80 = bit[31:0]
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
    localparam int LW    = BAW + 1
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

    // ---- Blackbox control -----------------------------------------------------
    output reg               o_bb_start,
    output wire [1:0]        o_bb_inject,
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
    input  wire [31:0]       i_bb_cycle_cnt
);

    localparam int NWIN = DW / 32;   // 16

    // ---- registers --------------------------------------------------------------
    reg [31:0] r_cmd_lo, r_cmd_hi;
    reg        r_cmd_overflow;
    reg [1:0]  r_inject;
    reg [31:0] r_bb_in, r_bb_out, r_bb_lat;
    reg [BAW-1:0] r_bram_addr;
    reg        r_bram_sel;
    reg [31:0] r_win [0:NWIN-1];

    assign o_command     = {r_cmd_hi, r_cmd_lo};
    assign o_bb_inject   = r_inject;
    assign o_bb_in_base  = r_bb_in[L1_AW-1:0];
    assign o_bb_in_len   = r_bb_in[16 +: LW];
    assign o_bb_out_base = r_bb_out[L1_AW-1:0];
    assign o_bb_out_len  = r_bb_out[16 +: LW];
    assign o_bb_latency  = r_bb_lat;

    genvar gi;
    generate
        for (gi = 0; gi < NWIN; gi = gi + 1) begin : g_win
            assign o_bram_wdata[gi*32 +: 32] = r_win[gi];
        end
    endgenerate

    // ---- AXI write channel --------------------------------------------------------
    reg              aw_full, w_full;
    reg [ADDR_W-1:0] aw_addr_q;
    reg [31:0]       w_data_q;
    reg [3:0]        w_strb_q;

    assign s_axil_awready = !aw_full && !s_axil_bvalid;
    assign s_axil_wready  = !w_full  && !s_axil_bvalid;
    assign s_axil_bresp   = 2'b00;

    wire       do_write = aw_full && w_full && !s_axil_bvalid;
    wire [7:0] w_off    = {aw_addr_q[7:2], 2'b00};
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
            r_inject <= '0; r_bb_in <= '0; r_bb_out <= '0; r_bb_lat <= '0;
            r_bram_addr <= '0; r_bram_sel <= 1'b0;
            for (i = 0; i < NWIN; i = i + 1) r_win[i] <= '0;
            o_command_valid <= 1'b0;
            o_bb_start <= 1'b0;
            o_bram_we <= 1'b0; o_bram_sel <= 1'b0; o_bram_addr <= '0;
        end else begin
            // one-clock pulses
            o_command_valid <= 1'b0;
            o_bb_start      <= 1'b0;
            o_bram_we       <= 1'b0;

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
                    8'h00: r_cmd_lo <= strb_merge(r_cmd_lo, w_data_q, w_strb_q);
                    8'h04: r_cmd_hi <= strb_merge(r_cmd_hi, w_data_q, w_strb_q);
                    8'h08: if (pulse_b0) o_command_valid <= 1'b1;
                    8'h20: begin
                        if (w_strb_q[0]) r_inject <= w_data_q[2:1];
                        if (pulse_b0)    o_bb_start <= 1'b1;
                    end
                    8'h24: r_bb_in  <= strb_merge(r_bb_in,  w_data_q, w_strb_q);
                    8'h28: r_bb_out <= strb_merge(r_bb_out, w_data_q, w_strb_q);
                    8'h2C: r_bb_lat <= strb_merge(r_bb_lat, w_data_q, w_strb_q);
                    8'h44: begin
                        if (w_strb_q[0]) r_bram_addr <= w_data_q[BAW-1:0];
                        if (w_strb_q[1]) r_bram_sel  <= w_data_q[8];
                    end
                    8'h48: if (pulse_b0) begin
                        o_bram_we   <= 1'b1;
                        o_bram_sel  <= r_bram_sel;
                        o_bram_addr <= r_bram_addr;
                        r_bram_addr <= r_bram_addr + 1'b1;
                    end
                    default: begin
                        if (w_off >= 8'h80 && w_off <= 8'hBC)
                            r_win[w_off[5:2]] <= strb_merge(r_win[w_off[5:2]], w_data_q, w_strb_q);
                    end
                endcase
            end
        end
    end

    // ---- AXI read channel ----------------------------------------------------------
    assign s_axil_arready = !s_axil_rvalid;
    assign s_axil_rresp   = 2'b00;

    wire [7:0] r_off = {s_axil_araddr[7:2], 2'b00};
    reg  [31:0] rmux;
    always @(*) begin
        rmux = 32'd0;
        case (r_off)
            8'h00: rmux = r_cmd_lo;
            8'h04: rmux = r_cmd_hi;
            8'h0C: rmux = {29'd0, r_cmd_overflow, i_busy_ch1_in, i_command_ready};
            8'h20: rmux = {29'd0, r_inject, 1'b0};
            8'h24: rmux = r_bb_in;
            8'h28: rmux = r_bb_out;
            8'h2C: rmux = r_bb_lat;
            8'h30: rmux = {28'd0, i_bb_err_start_busy, i_bb_first_mm_valid, i_bb_done, i_bb_busy};
            8'h34: rmux = {i_bb_first_mm_idx, i_bb_mismatch_cnt};
            8'h38: rmux = i_bb_first_mm_got;
            8'h3C: rmux = i_bb_first_mm_exp;
            8'h40: rmux = i_bb_cycle_cnt;
            8'h44: rmux = {23'd0, r_bram_sel, r_bram_addr};
            default: if (r_off >= 8'h80 && r_off <= 8'hBC) rmux = r_win[r_off[5:2]];
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
