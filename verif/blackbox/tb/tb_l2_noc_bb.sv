`timescale 1ns/1ps
// =============================================================================
//  tb_l2_noc_bb  -  Phase 2 : L2 + NoC + Blackbox 통합 (BLACKBOX_TASK.md 10절)
//
//   TB(ch0 task) ─► TOP_L2_cache(1 MiB) ─ch1_in─► noc_ch1_in_adapter ─► FIFO_intf_bb ─► l1_sram
//   TB(i_command) ─┘                                                       ▲ l1_port_mux
//                                                                  blackbox_pe (pe_busy)
//
//  ch0 는 TOP_L2_cache 의 간소화 AXI 포트를 TB task 로 직접 구동 (bridge 없음).
//  !! ch1_in 512b beat 하나는 L2 안에서 ch0 64b 워드 8개(lane)로 흩어져 있다 !!
//     -> ch0 쓰기/읽기는 lane 별 burst 로 한다 (bb_pkg::ch1_to_ch0, FINDING_l2_ch0_ch1_layout.md)
//
//  R0  : 회귀 (BB idle) - 기존 tb_l2_noc_ch1_in 과 같은 STORE->LOAD 왕복 5 beat
//  S1  : seed 1 ①~⑥                 S2 : seed 2,3,4
//  S3  : inject[0] -> CP-B 가 beat 0 만 잡아내는지
//  S4  : LOAD->START->STORE 간격 0   S5 : latency 0 / 10000
//  S6  : handshake 모드 (LOAD 01, STORE 11)
// =============================================================================
module tb_l2_noc_bb;
    import bb_pkg::*;

    localparam int CLKP = 10;
    localparam int DW   = 512;
    localparam string VEC_ROOT = "../../vectors";

    // TOP_L2_cache default NOC address widths (same as verif/integ TB)
    localparam DA_CH0 = 20, DA_CH1_IN = 19, DA_CH2_IN = 15, DA_CH1_WGT = 18, DA_CH2_WGT = 9;
    localparam BW_CH2_IN = 256, BW_CH1_WGT = 256, BW_CH2_WGT = 256;
    localparam NOC_ADDR_DEPTH = 2048, NOC_ADDR_BW = 11;

    logic i_clk = 0, i_rstb = 0;
    always #(CLKP/2) i_clk = ~i_clk;

    // ---- command ---------------------------------------------------------
    logic [63:0] i_command = '0;
    logic        i_command_valid = 0;
    wire         o_command_ready;

    // ---- ch0 ---------------------------------------------------------------
    logic [CH0_AW-1:0] araddr = '0, awaddr = '0;
    logic              arvalid = 0, awvalid = 0;
    logic [7:0]        arlen = 0, awlen = 0;
    wire               arready, awready;
    wire  [63:0]       rdata;
    wire               rvalid, rlast;
    logic              rready = 1;
    logic [63:0]       wdata = '0;
    logic              wvalid = 0, wlast = 0;
    wire               wready, bvalid;
    logic              bready = 1;

    // ---- ch1_in <-> adapter --------------------------------------------------
    wire                 busy_ch1_in;
    wire                 l2_w_ready, l2_w_valid, l2_w_resp;
    wire [DA_CH1_IN-1:0] l2_w_addr, l2_r_addr;
    wire [DW-1:0]        l2_w_data, l2_r_data;
    wire                 l2_r_valid, l2_r_data_ready, l2_r_ready, l2_r_resp, l2_ctrl_mode;

    // ---- unused channels -------------------------------------------------------
    wire unused_busy2w;
    wire busy_ch2_in, busy_ch1_wgt;

    // ---- ch2_in store port <-> Blackbox (BB is the master) -----------------------
    wire                 c2_valid, c2_ready, c2_resp;
    wire [31:0]          c2_addr;
    wire [255:0]         c2_data;

    // ---- ch1_wgt <-> adapter -------------------------------------------------------
    wire                  w_l2_w_ready, w_l2_w_valid, w_l2_w_resp;
    wire [DA_CH1_WGT-1:0] w_l2_w_addr, w_l2_r_addr;
    wire [255:0]          w_l2_w_data, w_l2_r_data;
    wire                  w_l2_r_valid, w_l2_r_data_ready, w_l2_r_ready, w_l2_r_resp, w_l2_ctrl_mode;

    TOP_L2_cache #(
        .GROUPS(GROUPS), .BLOCKS(BLOCKS), .ADDRESS_ROW(ADDRESS_ROW),
        .BANDWIDTH_CHANNEL_0(BW_CH0), .BANDWIDTH_CHANNEL_1_IN(DW),
        .BANDWIDTH_CHANNEL_2_IN(BW_CH2_IN), .BANDWIDTH_CHANNEL_1_WGT(BW_CH1_WGT), .BANDWIDTH_CHANNEL_2_WGT(BW_CH2_WGT),
        .DESTINATION_ADDR_BIT_CHANNEL_0(DA_CH0), .DESTINATION_ADDR_BIT_CHANNEL_1_IN(DA_CH1_IN),
        .DESTINATION_ADDR_BIT_CHANNEL_2_IN(DA_CH2_IN), .DESTINATION_ADDR_BIT_CHANNEL_1_WGT(DA_CH1_WGT),
        .DESTINATION_ADDR_BIT_CHANNEL_2_WGT(DA_CH2_WGT)
    ) dut_l2 (
        .i_clk(i_clk), .i_rstb(i_rstb),
        .i_araddr_channel_0(araddr), .i_arvalid_channel_0(arvalid), .o_arready_channel_0(arready),
        .i_arlen_channel_0(arlen), .o_rdata_channel_0(rdata), .o_rvalid_channel_0(rvalid),
        .i_rready_channel_0(rready), .o_rlast_channel_0(rlast),
        .i_awaddr_channel_0(awaddr), .i_awvalid_channel_0(awvalid), .o_awready_channel_0(awready),
        .i_awlen_channel_0(awlen), .i_wdata_channel_0(wdata), .i_wvalid_channel_0(wvalid),
        .i_wlast_channel_0(wlast), .o_wready_channel_0(wready), .o_bvalid_channel_0(bvalid),
        .i_bready_channel_0(bready),
        .i_command(i_command), .i_command_valid(i_command_valid), .o_command_ready(o_command_ready),
        .o_busy_channel_1_in(busy_ch1_in),
        .i_noc_write_ready_channel_1_in(l2_w_ready), .o_noc_write_valid_channel_1_in(l2_w_valid),
        .o_noc_write_addr_channel_1_in(l2_w_addr), .o_noc_write_data_channel_1_in(l2_w_data),
        .i_noc_write_response_channel_1_in(l2_w_resp),
        .o_noc_read_addr_channel_1_in(l2_r_addr), .o_noc_read_valid_channel_1_in(l2_r_valid),
        .o_noc_read_data_ready_channel_1_in(l2_r_data_ready), .i_noc_read_ready_channel_1_in(l2_r_ready),
        .i_noc_read_response_channel_1_in(l2_r_resp), .i_noc_read_data_channel_1_in(l2_r_data),
        .o_noc_control_mode_channel_1_in(l2_ctrl_mode),
        // ch2_in : load side (L2 -> PE/Accum) not used ; store side driven by the Blackbox
        .o_busy_channel_2_in(busy_ch2_in),
        .i_noc_write_ready_channel_2_in(1'b1), .o_noc_write_valid_channel_2_in(),
        .o_noc_write_addr_channel_2_in(), .o_noc_write_data_channel_2_in(),
        .i_noc_write_response_channel_2_in(1'b0), .o_noc_read_ready_channel_2_in(c2_ready),
        .i_noc_read_valid_channel_2_in(c2_valid), .i_noc_read_addr_channel_2_in(c2_addr),
        .i_noc_read_data_channel_2_in(c2_data), .o_noc_read_response_channel_2_in(c2_resp),
        .o_noc_control_mode_channel_2_in(),
        // ch1_wgt : -> adapter -> FIFO_intf_bb (256b) <- weight Blackbox
        .o_busy_channel_1_wgt(busy_ch1_wgt),
        .i_noc_write_ready_channel_1_wgt(w_l2_w_ready), .o_noc_write_valid_channel_1_wgt(w_l2_w_valid),
        .o_noc_write_addr_channel_1_wgt(w_l2_w_addr), .o_noc_write_data_channel_1_wgt(w_l2_w_data),
        .i_noc_write_response_channel_1_wgt(w_l2_w_resp), .o_noc_read_addr_channel_1_wgt(w_l2_r_addr),
        .o_noc_read_valid_channel_1_wgt(w_l2_r_valid), .o_noc_read_data_ready_channel_1_wgt(w_l2_r_data_ready),
        .i_noc_read_ready_channel_1_wgt(w_l2_r_ready), .i_noc_read_response_channel_1_wgt(w_l2_r_resp),
        .i_noc_read_data_channel_1_wgt(w_l2_r_data), .o_noc_control_mode_channel_1_wgt(w_l2_ctrl_mode),
        .o_busy_channel_2_wgt(unused_busy2w),
        .i_noc_write_ready_channel_2_wgt(1'b1), .o_noc_write_valid_channel_2_wgt(),
        .o_noc_write_addr_channel_2_wgt(), .o_noc_write_data_channel_2_wgt(),
        .i_noc_write_response_channel_2_wgt(1'b0), .o_noc_control_mode_channel_2_wgt()
    );

    // ---- adapter -----------------------------------------------------------
    wire                   m_write_valid, m_write_ready, m_fifo_write_ready;
    wire [NOC_ADDR_BW-1:0] m_write_addr, m_read_addr;
    wire [DW-1:0]          m_write_data, m_read_data;
    wire                   m_read_valid, m_read_ready, m_fifo_read_ready, m_data_fifo_ready, m_control_mode;

    noc_ch1_in_adapter #(.DA_L2(DA_CH1_IN), .ADDR_BW(NOC_ADDR_BW), .DW(DW)) u_adapter (
        .l2_noc_write_valid(l2_w_valid), .l2_noc_write_addr(l2_w_addr), .l2_noc_write_data(l2_w_data),
        .l2_noc_write_ready(l2_w_ready), .l2_noc_write_response(l2_w_resp),
        .l2_noc_read_valid(l2_r_valid), .l2_noc_read_addr(l2_r_addr),
        .l2_noc_read_data_ready(l2_r_data_ready), .l2_noc_read_ready(l2_r_ready),
        .l2_noc_read_response(l2_r_resp), .l2_noc_read_data(l2_r_data),
        .l2_noc_control_mode(l2_ctrl_mode),
        .m_write_valid(m_write_valid), .m_write_addr(m_write_addr), .m_write_data(m_write_data),
        .m_write_ready(m_write_ready), .m_fifo_write_ready(m_fifo_write_ready),
        .m_read_valid(m_read_valid), .m_read_addr(m_read_addr), .m_read_ready(m_read_ready),
        .m_read_data(m_read_data), .m_fifo_read_ready(m_fifo_read_ready),
        .m_data_fifo_ready(m_data_fifo_ready), .m_control_mode(m_control_mode));

    // ---- FIFO_intf_bb + blackbox ---------------------------------------------
    wire              pe_busy, pe_ceb, pe_web;
    wire [10:0]       pe_addr;
    wire [DW-1:0]     pe_din, pe_dout;

    FIFO_intf_bb #(.ADDR_DEPTH(NOC_ADDR_DEPTH), .DATA_WIDTH(DW), .MEMORY_BITWIDTH(128),
                   .FIFO_DEPTH(8), .INPUT_DELAY(3)) dut_noc (
        .clk(i_clk), .rstb(i_rstb),
        .i_read_valid(m_read_valid), .o_read_ready(m_read_ready),
        .i_read_addr(m_read_addr), .o_read_data(m_read_data),
        .i_write_valid(m_write_valid), .o_write_ready(m_write_ready),
        .i_write_addr(m_write_addr), .i_write_data(m_write_data),
        .i_control_mode(m_control_mode),
        .o_FIFO_read_ready(m_fifo_read_ready), .o_FIFO_write_ready(m_fifo_write_ready),
        .i_data_fifo_ready(m_data_fifo_ready),
        .i_pe_busy(pe_busy), .i_pe_ceb(pe_ceb), .i_pe_web(pe_web), .i_pe_addr(pe_addr),
        .i_pe_din(pe_din), .o_pe_dout(pe_dout));

    logic        bb_start = 0;
    logic [10:0] bb_in_base = 0, bb_out_base = 0;
    logic [8:0]  bb_in_len = 0, bb_out_len = 0;
    logic [31:0] bb_latency = 0;
    logic [1:0]  bb_inject = 0;
    logic        bb_out_sel = 0, bb_c2_prec = 0, bb_c2_hs = 0;
    logic [9:0]  bb_c2_h = 0, bb_c2_w = 0;
    logic [6:0]  bb_c2_nb = 0;
    logic        bram_we = 0, bram_sel = 0;
    logic [7:0]  bram_addr = 0;
    logic [DW-1:0] bram_wdata = '0;
    wire         bb_busy, bb_done, bb_first_valid, bb_err_start_busy;
    wire [15:0]  bb_mm_cnt, bb_first_idx;
    wire [31:0]  bb_first_got, bb_first_exp, bb_cycles;

    blackbox_pe #(.DW(DW), .L1_AW(11), .BRAM_DEPTH(256), .GUARD(2)) dut_bb (
        .clk(i_clk), .rstn(i_rstb),
        .i_start(bb_start), .i_noc_busy(busy_ch1_in),
        .i_in_base(bb_in_base), .i_in_len(bb_in_len), .i_out_base(bb_out_base), .i_out_len(bb_out_len),
        .i_latency(bb_latency), .i_inject(bb_inject),
        .i_out_sel(bb_out_sel), .i_c2_prec(bb_c2_prec), .i_c2_hs(bb_c2_hs),
        .i_c2_h(bb_c2_h), .i_c2_w(bb_c2_w), .i_c2_nb(bb_c2_nb),
        .o_c2_valid(c2_valid), .o_c2_addr(c2_addr), .o_c2_data(c2_data), .i_c2_ready(c2_ready), .i_c2_resp(c2_resp),
        .i_bram_we(bram_we), .i_bram_sel(bram_sel), .i_bram_addr(bram_addr), .i_bram_wdata(bram_wdata),
        .o_pe_busy(pe_busy), .o_ceb(pe_ceb), .o_web(pe_web), .o_addr(pe_addr), .o_din(pe_din), .i_dout(pe_dout),
        .o_busy(bb_busy), .o_done(bb_done),
        .o_mismatch_cnt(bb_mm_cnt), .o_first_mm_idx(bb_first_idx), .o_first_mm_valid(bb_first_valid),
        .o_first_mm_got(bb_first_got), .o_first_mm_exp(bb_first_exp),
        .o_err_start_busy(bb_err_start_busy), .o_cycle_cnt(bb_cycles));

    // =========================================================================
    //  weight path : ch1_wgt adapter -> FIFO_intf_bb (256b x 1024) <- weight Blackbox
    //  (weight Blackbox = blackbox_pe with DW=256, Expected 1024 rows, no output phase)
    // =========================================================================
    wire                 w_m_write_valid, w_m_write_ready, w_m_fifo_write_ready;
    wire [9:0]           w_m_write_addr, w_m_read_addr;
    wire [255:0]         w_m_write_data, w_m_read_data;
    wire                 w_m_read_valid, w_m_read_ready, w_m_fifo_read_ready, w_m_data_fifo_ready, w_m_control_mode;

    noc_ch1_wgt_adapter #(.DA_L2(DA_CH1_WGT), .ADDR_BW(10), .DW(256)) u_adapter_w (
        .l2_noc_write_valid(w_l2_w_valid), .l2_noc_write_addr(w_l2_w_addr), .l2_noc_write_data(w_l2_w_data),
        .l2_noc_write_ready(w_l2_w_ready), .l2_noc_write_response(w_l2_w_resp),
        .l2_noc_read_valid(w_l2_r_valid), .l2_noc_read_addr(w_l2_r_addr),
        .l2_noc_read_data_ready(w_l2_r_data_ready), .l2_noc_read_ready(w_l2_r_ready),
        .l2_noc_read_response(w_l2_r_resp), .l2_noc_read_data(w_l2_r_data),
        .l2_noc_control_mode(w_l2_ctrl_mode),
        .m_write_valid(w_m_write_valid), .m_write_addr(w_m_write_addr), .m_write_data(w_m_write_data),
        .m_write_ready(w_m_write_ready), .m_fifo_write_ready(w_m_fifo_write_ready),
        .m_read_valid(w_m_read_valid), .m_read_addr(w_m_read_addr), .m_read_ready(w_m_read_ready),
        .m_read_data(w_m_read_data), .m_fifo_read_ready(w_m_fifo_read_ready),
        .m_data_fifo_ready(w_m_data_fifo_ready), .m_control_mode(w_m_control_mode));

    wire              wpe_busy, wpe_ceb, wpe_web;
    wire [9:0]        wpe_addr;
    wire [255:0]      wpe_din, wpe_dout;

    FIFO_intf_bb #(.ADDR_DEPTH(1024), .DATA_WIDTH(256), .MEMORY_BITWIDTH(64),
                   .FIFO_DEPTH(8), .INPUT_DELAY(3)) dut_noc_w (
        .clk(i_clk), .rstb(i_rstb),
        .i_read_valid(w_m_read_valid), .o_read_ready(w_m_read_ready),
        .i_read_addr(w_m_read_addr), .o_read_data(w_m_read_data),
        .i_write_valid(w_m_write_valid), .o_write_ready(w_m_write_ready),
        .i_write_addr(w_m_write_addr), .i_write_data(w_m_write_data),
        .i_control_mode(w_m_control_mode),
        .o_FIFO_read_ready(w_m_fifo_read_ready), .o_FIFO_write_ready(w_m_fifo_write_ready),
        .i_data_fifo_ready(w_m_data_fifo_ready),
        .i_pe_busy(wpe_busy), .i_pe_ceb(wpe_ceb), .i_pe_web(wpe_web), .i_pe_addr(wpe_addr),
        .i_pe_din(wpe_din), .o_pe_dout(wpe_dout));

    logic         wbb_start = 0;
    logic [9:0]   wbb_in_base = 0;
    logic [10:0]  wbb_in_len = 0;
    logic [1:0]   wbb_inject = 0;
    logic         wbram_we = 0;
    logic [9:0]   wbram_addr = 0;
    logic [255:0] wbram_wdata = '0;
    wire          wbb_busy, wbb_done, wbb_first_valid, wbb_err_start_busy;
    wire [15:0]   wbb_mm_cnt, wbb_first_idx;
    wire [31:0]   wbb_first_got, wbb_first_exp, wbb_cycles;

    blackbox_pe #(.DW(256), .L1_AW(10), .BRAM_DEPTH(1024), .GUARD(2)) dut_bbw (
        .clk(i_clk), .rstn(i_rstb),
        .i_start(wbb_start), .i_noc_busy(busy_ch1_wgt),
        .i_in_base(wbb_in_base), .i_in_len(wbb_in_len), .i_out_base(10'd0), .i_out_len(11'd0),
        .i_latency(32'd0), .i_inject(wbb_inject),
        .i_out_sel(1'b0), .i_c2_prec(1'b0), .i_c2_hs(1'b0), .i_c2_h(10'd0), .i_c2_w(10'd0), .i_c2_nb(7'd0),
        .o_c2_valid(), .o_c2_addr(), .o_c2_data(), .i_c2_ready(1'b0), .i_c2_resp(1'b0),
        .i_bram_we(wbram_we), .i_bram_sel(1'b0), .i_bram_addr(wbram_addr), .i_bram_wdata(wbram_wdata),
        .o_pe_busy(wpe_busy), .o_ceb(wpe_ceb), .o_web(wpe_web), .o_addr(wpe_addr), .o_din(wpe_din), .i_dout(wpe_dout),
        .o_busy(wbb_busy), .o_done(wbb_done),
        .o_mismatch_cnt(wbb_mm_cnt), .o_first_mm_idx(wbb_first_idx), .o_first_mm_valid(wbb_first_valid),
        .o_first_mm_got(wbb_first_got), .o_first_mm_exp(wbb_first_exp),
        .o_err_start_busy(wbb_err_start_busy), .o_cycle_cnt(wbb_cycles));

    // =========================================================================
    //  bookkeeping
    // =========================================================================
    int errors = 0;
    bit skip_reset = 0;    // run the next flow without resetting (back-to-back commands)
    int npass = 0, nfail = 0;
    string results[$];
    longint cyc_now = 0;
    always @(posedge i_clk) cyc_now++;

    // ---- debug trace (+TRACE=<n> : print n cycles of the ch1_in handshake after each command)
    int trace_left = 0;
    int trace_n    = 0;
    initial if (!$value$plusargs("TRACE=%d", trace_n)) trace_n = 0;
    always @(posedge i_clk) if (trace_left > 0) begin
        trace_left--;
        $display("  TR c=%0d st=%0d hs=%0d | L2: sram_rv=%0d sram_rresp=%0d sram_rdr=%0d noc_wv=%0d noc_wr(fifo)=%0d noc_wresp=%0d noc_wa=%0d | rv=%0d rr=%0d rresp=%0d | L1 ceb=%0d web=%0d a=%0d pe=%0d busy=%0d",
            cyc_now, dut_l2.u_cmd_decoder_SRAM_group_merge.u_cmd_decoder_channel_1_in_wrapper.u_cmd_decoder_channel_1_in.current_state,
            dut_l2.u_cmd_decoder_SRAM_group_merge.u_cmd_decoder_channel_1_in_wrapper.u_cmd_decoder_channel_1_in.current_state_handshake,
            dut_l2.u_cmd_decoder_SRAM_group_merge.u_cmd_decoder_channel_1_in_wrapper.u_cmd_decoder_channel_1_in.o_sram_read_valid,
            dut_l2.u_cmd_decoder_SRAM_group_merge.u_cmd_decoder_channel_1_in_wrapper.u_cmd_decoder_channel_1_in.i_sram_read_response,
            dut_l2.u_cmd_decoder_SRAM_group_merge.u_cmd_decoder_channel_1_in_wrapper.u_cmd_decoder_channel_1_in.o_sram_read_data_ready,
            l2_w_valid, l2_w_ready, l2_w_resp, l2_w_addr[10:0], l2_r_valid, l2_r_ready, l2_r_resp,
            dut_noc.sram_ceb, dut_noc.sram_web, dut_noc.sram_addr, pe_busy, busy_ch1_in);
    end

    // ---- ch2_in store trace (+TRACE2=<n> : n clocks after every command push)
    int trace2_left = 0, trace2_n = 0;
    initial if (!$value$plusargs("TRACE2=%d", trace2_n)) trace2_n = 0;
    always @(posedge i_clk) if (trace2_left > 0) begin
        trace2_left--;
        $display("  T2 c=%0d st=%0d hs=%0d | rv=%0d rready=%0d resp=%0d r_rdy=%0d rd_done=%0d fifo_v=%0d | sram_wv=%0d wdone=%0d | busy=%0d bb_st=%0d",
            cyc_now, dut_l2.u_cmd_decoder_SRAM_group_merge.u_cmd_decoder_channel_2_in_wrapper.u_cmd_decoder_channel_2_in.current_state,
            dut_l2.u_cmd_decoder_SRAM_group_merge.u_cmd_decoder_channel_2_in_wrapper.u_cmd_decoder_channel_2_in.current_state_handshake,
            c2_valid, c2_ready, c2_resp,
            dut_l2.u_cmd_decoder_SRAM_group_merge.u_cmd_decoder_channel_2_in_wrapper.u_cmd_decoder_channel_2_in.r_noc_read_ready,
            dut_l2.u_cmd_decoder_SRAM_group_merge.u_cmd_decoder_channel_2_in_wrapper.u_cmd_decoder_channel_2_in.r_noc_read_done,
            dut_l2.u_cmd_decoder_SRAM_group_merge.u_cmd_decoder_channel_2_in_wrapper.u_cmd_decoder_channel_2_in.w_fifo_noc_read_valid,
            dut_l2.u_cmd_decoder_SRAM_group_merge.u_cmd_decoder_channel_2_in_wrapper.u_cmd_decoder_channel_2_in.o_sram_write_valid,
            dut_l2.u_cmd_decoder_SRAM_group_merge.u_cmd_decoder_channel_2_in_wrapper.u_cmd_decoder_channel_2_in.r_sram_write_done,
            busy_ch2_in, dut_bb.st);
    end

    // ---- NoC->L1 write monitors (S4 analysis) ----------------------------------
    //  dropped     : the L1-side on-fire bridge issued a write while pe_busy gated it away
    //  last_noc_wr : last clock the NoC (not the PE) actually wrote the L1 SRAM
    int     dropped_wr    = 0;
    int     conflicts     = 0;     // PE and NoC accessed L1 in the same clock (must stay 0)
    always @(posedge i_clk) if (i_rstb && (dut_noc.pe_conflict || dut_noc_w.pe_conflict)) begin
        conflicts++;
        if (conflicts < 5) $display("    !! L1 port conflict (PE access pushed out) at clk %0d", cyc_now);
    end
    longint last_noc_wr   = 0;
    longint busy_fall_cyc = 0;
    always @(posedge i_clk) if (i_rstb) begin
        if (dut_noc.UL1_FIFO_intf.UL1_FIFO_interface.w_write_valid_L1_on_fire && pe_busy) dropped_wr++;
        if (!dut_noc.u_l1_port_mux.sel_pe && dut_noc.sram_ceb == 1'b0 && dut_noc.sram_web == 1'b0) last_noc_wr = cyc_now;
    end

    task automatic chk(input string tag, input bit cond, input string msg);
        if (cond) $display("    [ok]   %s : %s", tag, msg);
        else begin $display("    [FAIL] %s : %s", tag, msg); errors++; end
    endtask

    task automatic report(input string tname, input int e0, input string note);
        results.push_back($sformatf("%-14s | %-4s | %s", tname, (errors == e0) ? "PASS" : "FAIL", note));
        if (errors == e0) npass++; else nfail++;
    endtask

    // ---- sampling helper : value at negedge+1 == value seen by the next posedge
    task automatic settle(); @(negedge i_clk); #1; endtask

    task automatic do_reset();
        @(negedge i_clk); i_rstb = 0;
        repeat (10) @(negedge i_clk); i_rstb = 1;
        repeat (5) @(negedge i_clk);
    endtask

    // =========================================================================
    //  L1 backdoor
    // =========================================================================
    task automatic l1_poke(input int a, input logic [DW-1:0] d);
        dut_noc.u_l1_sram.Usram_mimic_0.mem[a] = d[127:0];
        dut_noc.u_l1_sram.Usram_mimic_1.mem[a] = d[255:128];
        dut_noc.u_l1_sram.Usram_mimic_2.mem[a] = d[383:256];
        dut_noc.u_l1_sram.Usram_mimic_3.mem[a] = d[511:384];
    endtask
    function automatic logic [DW-1:0] l1_peek(input int a);
        return {dut_noc.u_l1_sram.Usram_mimic_3.mem[a], dut_noc.u_l1_sram.Usram_mimic_2.mem[a],
                dut_noc.u_l1_sram.Usram_mimic_1.mem[a], dut_noc.u_l1_sram.Usram_mimic_0.mem[a]};
    endfunction

    // =========================================================================
    //  command / busy
    // =========================================================================
    task automatic send_cmd(input logic [63:0] c);
        int t = 0;
        @(negedge i_clk);
        i_command = c; i_command_valid = 1; #1;
        trace_left = trace_n;
        trace2_left = trace2_n;
        while (!o_command_ready) begin
            @(negedge i_clk); #1;
            if (++t > 10000) begin $display("    !! command_ready timeout"); errors++; break; end
        end
        @(posedge i_clk);                       // accepted here
        @(negedge i_clk);
        i_command_valid = 0; i_command = '0;
    endtask

    // waits for busy 0->1->0 ; returns cycles from call to the falling edge
    task automatic wait_busy_cycle(input string what, output int cycles);
        longint t0;
        int t = 0;
        t0 = cyc_now;
        while (busy_ch1_in !== 1'b1) begin
            settle();
            if (++t > 20000) begin $display("    !! %s : busy never rose", what); errors++; cycles = -1; return; end
        end
        t = 0;
        while (busy_ch1_in !== 1'b0) begin
            settle();
            if (++t > 50000) begin $display("    !! %s : busy never fell", what); errors++; cycles = -1; return; end
        end
        cycles = int'(cyc_now - t0);
        busy_fall_cyc = cyc_now;
    endtask

    // =========================================================================
    //  ch0 (simplified AXI) tasks
    // =========================================================================
    task automatic ch0_write(input int addr, input logic [63:0] d[$]);
        int n, t;
        n = d.size();
        @(negedge i_clk);
        awaddr = addr[CH0_AW-1:0]; awlen = 8'(n - 1); awvalid = 1; #1;
        t = 0;
        while (!awready) begin settle(); if (++t > 10000) begin $display("    !! awready timeout"); errors++; break; end end
        @(posedge i_clk); @(negedge i_clk); awvalid = 0;
        for (int i = 0; i < n; i++) begin
            wdata = d[i]; wvalid = 1; wlast = (i == n - 1); #1;
            t = 0;
            while (!wready) begin settle(); if (++t > 10000) begin $display("    !! wready timeout"); errors++; break; end end
            @(posedge i_clk); @(negedge i_clk);
        end
        wvalid = 0; wlast = 0; #1;
        t = 0;
        while (!bvalid) begin settle(); if (++t > 10000) begin $display("    !! bvalid timeout"); errors++; break; end end
        @(posedge i_clk);
    endtask

    task automatic ch0_read(input int addr, input int n, output logic [63:0] d[$]);
        int t, got;
        d = {};
        @(negedge i_clk);
        araddr = addr[CH0_AW-1:0]; arlen = 8'(n - 1); arvalid = 1; #1;
        t = 0;
        while (!arready) begin settle(); if (++t > 10000) begin $display("    !! arready timeout"); errors++; break; end end
        @(posedge i_clk); @(negedge i_clk); arvalid = 0;
        got = 0; t = 0;
        while (got < n) begin
            #1;
            if (rvalid) begin
                d.push_back(rdata);
                got++;
                if (rlast !== (got == n)) begin $display("    !! rlast mismatch at beat %0d", got - 1); errors++; end
            end
            @(negedge i_clk);
            if (++t > 20000) begin $display("    !! rvalid timeout"); errors++; break; end
        end
    endtask

    // ch1_in beats [c0, c0+n) <-> L2 via ch0, one burst per lane (and per <=256 / no 4KB crossing)
    task automatic l2_write_beats(input int c0, input int n, ref logic [DW-1:0] v[$]);
        for (int b = 0; b < RATIO; b++) begin
            int k = 0;
            while (k < n) begin
                logic [63:0] q[$];
                int a0, len;
                a0  = ch1_to_ch0(c0 + k, b);
                len = 0;
                q   = {};
                // extend burst while ch0 addresses stay contiguous, <=256 beats, inside one 4 KiB page
                while (k + len < n && len < 256 && ch1_to_ch0(c0 + k + len, b) == a0 + len &&
                       (((a0 + len) * 8) >> 12) == ((a0 * 8) >> 12)) begin
                    q.push_back(v[k + len][b*64 +: 64]);
                    len++;
                end
                ch0_write(a0, q);
                k += len;
            end
        end
    endtask

    task automatic l2_read_beats(input int c0, input int n, ref logic [DW-1:0] v[$]);
        v = {};
        for (int k = 0; k < n; k++) v.push_back('0);
        for (int b = 0; b < RATIO; b++) begin
            int k = 0;
            while (k < n) begin
                logic [63:0] q[$];
                int a0, len;
                a0 = ch1_to_ch0(c0 + k, b);
                len = 0;
                while (k + len < n && len < 256 && ch1_to_ch0(c0 + k + len, b) == a0 + len &&
                       (((a0 + len) * 8) >> 12) == ((a0 * 8) >> 12))
                    len++;
                ch0_read(a0, len, q);
                for (int i = 0; i < len; i++) v[k + i][b*64 +: 64] = q[i];
                k += len;
            end
        end
    endtask

    // =========================================================================
    //  Blackbox helpers
    // =========================================================================
    task automatic bram_write(input bit sel, input int a, input logic [DW-1:0] d);
        @(negedge i_clk);
        bram_we = 1; bram_sel = sel; bram_addr = a[7:0]; bram_wdata = d;
        @(negedge i_clk);
        bram_we = 0;
    endtask

    task automatic bb_start_pulse();
        // called at a negedge -> start sampled by the next posedge
        bb_start = 1;
        @(negedge i_clk);
        bb_start = 0;
    endtask

    // =========================================================================
    //  MAP : 1 MiB 전 범위 검증 (L2 크기/주소 매핑이 맞는지)
    //   M1  ch0 로 1 MiB 전체(64b x 131072)에 주소마다 다른 값 쓰기 -> 전부 읽어 비교 (aliasing 없음)
    //   M2  ch1_in LOAD : 8 group 전부, block-pair 경계(row 1023->pair 1)·group 경계를 넘는 burst
    //   M3  ch1_in STORE : 맨 위 16 beat (0x3FF0~0x3FFF) + group 경계 -> ch0 로 읽어 확인
    // =========================================================================
    localparam int CH0_WORDS = 1 << CH0_AW;               // 131072 = 1 MiB / 8 B
    localparam int CH1_WORDS = 1 << SRC_W;                // 16384  = 1 MiB / 64 B

    function automatic logic [63:0] map_pat(input int a);  // unique per ch0 word
        return {32'hA5A5_0000 ^ 32'(a), 32'(a)};
    endfunction
    function automatic logic [DW-1:0] map_beat(input int c); // ch1 word c, as stored by M1
        logic [DW-1:0] v;
        for (int b = 0; b < RATIO; b++) v[b*64 +: 64] = map_pat(ch1_to_ch0(c, b));
        return v;
    endfunction

    task automatic test_map();
        int e0, bad, cyc, t0c;
        longint t0;
        $display("\n=== MAP : 1 MiB full-range (ch0 %0d words x 64b, ch1_in %0d words x 512b, SRC_W=%0d, CH0_AW=%0d) ===",
                 CH0_WORDS, CH1_WORDS, SRC_W, CH0_AW);
        e0 = errors;
        do_reset();

        // ---- M1 ------------------------------------------------------------
        t0 = cyc_now;
        for (int a = 0; a < CH0_WORDS; a += 256) begin
            logic [63:0] q[$];
            q = {};
            for (int i = 0; i < 256; i++) q.push_back(map_pat(a + i));
            ch0_write(a, q);
        end
        bad = 0;
        for (int a = 0; a < CH0_WORDS; a += 256) begin
            logic [63:0] q[$];
            ch0_read(a, 256, q);
            for (int i = 0; i < 256; i++)
                if (q[i] !== map_pat(a + i)) begin
                    if (bad < 5) $display("    M1 mismatch ch0[%05h] = %016h (want %016h)", a + i, q[i], map_pat(a + i));
                    bad++;
                end
        end
        chk("M1", bad == 0, $sformatf("ch0 write+read all %0d words (byte 0x00000~0x%05h) : %0d bad, %0d clk",
                                      CH0_WORDS, CH0_WORDS*8 - 1, bad, int'(cyc_now - t0)));

        // ---- M2 : LOAD across every group / pair / boundary -----------------
        bad = 0;
        begin
            int starts[$], lens[$], dst;
            for (int g = 0; g < GROUPS; g++) begin
                starts.push_back((g << IN_GRP_CH1) | ((1 << ROW_BITS) - 2)); lens.push_back(4); // pair0 row1022 -> pair1 row1
                if (g < GROUPS - 1) begin
                    starts.push_back((g << IN_GRP_CH1) | ((1 << IN_GRP_CH1) - 2)); lens.push_back(4); // group g -> g+1
                end
            end
            starts.push_back(CH1_WORDS - 4); lens.push_back(4);      // very top : 0x3FFC..0x3FFF
            dst = 0;
            foreach (starts[i]) begin
                send_cmd(mk_load(starts[i], lens[i], dst));
                wait_busy_cycle("M2 LOAD", cyc);
                repeat (4) @(negedge i_clk);
                for (int k = 0; k < lens[i]; k++)
                    if (l1_peek(dst + k) !== map_beat(starts[i] + k)) begin
                        if (bad < 5) $display("    M2 mismatch L2 word 0x%04h -> L1[%0d]", starts[i] + k, dst + k);
                        bad++;
                    end
                dst += lens[i];
            end
            chk("M2", bad == 0, $sformatf("%0d LOADs (8 groups, pair & group boundaries, top 0x%04h) : %0d bad beats",
                                          starts.size(), CH1_WORDS - 1, bad));
        end

        // ---- M3 : STORE to the top and across a group boundary --------------
        bad = 0;
        begin
            int c0s[2], n;
            logic [DW-1:0] rb[$];
            c0s[0] = CH1_WORDS - 16;                     // 0x3FF0..0x3FFF (group 7, pair 1, rows 1008..1023)
            c0s[1] = (3 << IN_GRP_CH1) - 8;              // 0x17F8..0x1807 (group 2 -> group 3)
            for (int j = 0; j < 2; j++) begin
                for (int k = 0; k < 16; k++) l1_poke(1500 + k, {16{32'h5700_0000 | (j << 16) | k}});
                send_cmd(mk_store(1500, 16, c0s[j]));
                wait_busy_cycle("M3 STORE", cyc);
                repeat (4) @(negedge i_clk);
                l2_read_beats(c0s[j], 16, rb);
                for (int k = 0; k < 16; k++)
                    if (rb[k] !== {16{32'h5700_0000 | (j << 16) | k}}) begin
                        if (bad < 5) $display("    M3 mismatch L2 word 0x%04h", c0s[j] + k);
                        bad++;
                    end
                // neighbours untouched (still the M1 pattern)
                l2_read_beats(c0s[j] - 1, 1, rb);
                if (rb[0] !== map_beat(c0s[j] - 1)) begin $display("    M3 neighbour below 0x%04h corrupted", c0s[j] - 1); bad++; end
                if (j == 1) begin
                    l2_read_beats(c0s[j] + 16, 1, rb);
                    if (rb[0] !== map_beat(c0s[j] + 16)) begin $display("    M3 neighbour above 0x%04h corrupted", c0s[j] + 16); bad++; end
                end
            end
            chk("M3", bad == 0, $sformatf("STORE to 0x3FF0-0x3FFF and 0x17F8-0x1807, neighbours intact : %0d bad", bad));
        end
        test_map_wgt();
        report("MAP 1MiB", e0, "M1 ch0 full 1 MiB, M2 LOAD all groups, M3 STORE top/boundary, M4 ch1_wgt boundaries");
    endtask

    // =========================================================================
    //  helpers for the weight / output paths
    // =========================================================================
    function automatic logic get_busy(input int sel);       // 0 ch1_in, 1 ch1_wgt, 2 ch2_in
        return (sel == 0) ? busy_ch1_in : (sel == 1) ? busy_ch1_wgt : busy_ch2_in;
    endfunction

    // busy 0->1->0 of the selected channel ; cycles from call to the fall
    task automatic wait_busy_sel(input int sel, input string what, output int cycles);
        longint t0;
        int t = 0;
        t0 = cyc_now;
        while (get_busy(sel) !== 1'b1) begin
            settle();
            if (++t > 20000) begin $display("    !! %s : busy never rose", what); errors++; cycles = -1; return; end
        end
        t = 0;
        while (get_busy(sel) !== 1'b0) begin
            settle();
            if (++t > 50000) begin $display("    !! %s : busy never fell", what); errors++; cycles = -1; return; end
        end
        cycles = int'(cyc_now - t0);
        busy_fall_cyc = cyc_now;
    endtask

    // 256b words (ch1_wgt / ch2 view) <-> L2 through ch0, one burst per lane
    task automatic l2_write_256(input int c0, input int n, ref logic [255:0] v[$]);
        for (int b = 0; b < RATIO_256; b++) begin
            int k = 0;
            while (k < n) begin
                logic [63:0] q[$];
                int a0, len;
                a0 = c256_to_ch0(c0 + k, b); len = 0; q = {};
                while (k + len < n && len < 256 && c256_to_ch0(c0 + k + len, b) == a0 + len &&
                       (((a0 + len) * 8) >> 12) == ((a0 * 8) >> 12)) begin
                    q.push_back(v[k + len][b*64 +: 64]);
                    len++;
                end
                ch0_write(a0, q);
                k += len;
            end
        end
    endtask

    task automatic l2_read_256(input int c0, input int n, ref logic [255:0] v[$]);
        v = {};
        for (int k = 0; k < n; k++) v.push_back('0);
        for (int b = 0; b < RATIO_256; b++) begin
            int k = 0;
            while (k < n) begin
                logic [63:0] q[$];
                int a0, len;
                a0 = c256_to_ch0(c0 + k, b); len = 0;
                while (k + len < n && len < 256 && c256_to_ch0(c0 + k + len, b) == a0 + len &&
                       (((a0 + len) * 8) >> 12) == ((a0 * 8) >> 12))
                    len++;
                ch0_read(a0, len, q);
                for (int i = 0; i < len; i++) v[k + i][b*64 +: 64] = q[i];
                k += len;
            end
        end
    endtask

    // weight L1 (cluster array stand-in) backdoor
    task automatic l1w_poke(input int a, input logic [255:0] d);
        dut_noc_w.u_l1_sram.Usram_mimic_0.mem[a] = d[63:0];
        dut_noc_w.u_l1_sram.Usram_mimic_1.mem[a] = d[127:64];
        dut_noc_w.u_l1_sram.Usram_mimic_2.mem[a] = d[191:128];
        dut_noc_w.u_l1_sram.Usram_mimic_3.mem[a] = d[255:192];
    endtask
    function automatic logic [255:0] l1w_peek(input int a);
        return {dut_noc_w.u_l1_sram.Usram_mimic_3.mem[a], dut_noc_w.u_l1_sram.Usram_mimic_2.mem[a],
                dut_noc_w.u_l1_sram.Usram_mimic_1.mem[a], dut_noc_w.u_l1_sram.Usram_mimic_0.mem[a]};
    endfunction

    task automatic wbram_write(input int a, input logic [255:0] d);
        @(negedge i_clk);
        wbram_we = 1; wbram_addr = a[9:0]; wbram_wdata = d;
        @(negedge i_clk);
        wbram_we = 0;
    endtask

    // weight Blackbox job : compare L1w[base .. base+len) with Expected ; returns mismatch count
    task automatic run_wbb(input int base, input int len, input int gap, output int mm);
        int t = 0;
        repeat (gap) @(negedge i_clk);
        wbb_in_base = base; wbb_in_len = len; wbb_inject = 0;
        wbb_start = 1;
        @(negedge i_clk);
        wbb_start = 0;
        while (!wbb_done) begin
            settle();
            if (++t > 50000) begin $display("    !! weight BB done timeout (err_start_busy=%0d)", wbb_err_start_busy); errors++; break; end
        end
        mm = wbb_mm_cnt;
        if (wbb_first_valid)
            $display("    weight BB first mismatch row %0d : got %08h exp %08h", wbb_first_idx, wbb_first_got, wbb_first_exp);
    endtask

    task automatic read_wimg(input int seed, ref logic [255:0] w[$]);
        logic [255:0] a [0:NWROWS-1];
        $readmemh($sformatf("%s/seed%0d/wgt.hex", VEC_ROOT, seed), a);
        w = {};
        foreach (a[k]) begin
            if ($isunknown(a[k])) begin $display("    !! wgt.hex row %0d has X (file not loaded?)", k); errors++; end
            w.push_back(a[k]);
        end
    endtask

    // =========================================================================
    //  W1 / W3 : ch1_wgt burst load 1024 rows -> weight BB compares all 1024 rows (CP-W)
    // =========================================================================
    task automatic test_wgt_burst(input string tname, input int seed, input bit hs, input int gap);
        logic [255:0] wq [$];
        int e0, c_load, mm;
        $display("\n=== %s : seed %0d, ch1_wgt burst load %0d rows, handshake %0d, START gap %0d ===",
                 tname, seed, NWROWS, hs, gap);
        e0 = errors;
        read_wimg(seed, wq);
        if (!skip_reset) do_reset();
        for (int k = 0; k < NWROWS; k++) l1w_poke(k, {8{32'hDEAD_0000 | k}});
        l2_write_256(WGT_W_WORD, NWROWS, wq);
        for (int k = 0; k < NWROWS; k++) wbram_write(k, wq[k]);
        send_cmd(mk_wload_burst(WGT_W_WORD, NWROWS, 0, hs));
        wait_busy_sel(1, {tname, " WLOAD"}, c_load);
        run_wbb(0, NWROWS, gap, mm);
        if (mm != 0)    // diagnostic : which weight row actually landed in L1w[0..5] ?
            for (int r = 0; r < 6; r++) begin
                int src;
                logic [255:0] v;
                src = -1;
                v = l1w_peek(r);
                for (int i = 0; i < NWROWS; i++) if (wq[i] === v) begin src = i; break; end
                $display("      L1w[%0d] = %08h..  <- weight row %0d", r, v[31:0], src);
            end
        chk(tname, mm == 0, $sformatf("CP-W : %0d/%0d rows == weight image (LOAD %0d clk, BB %0d clk)",
                                      NWROWS - mm, NWROWS, c_load, wbb_cycles));
        chk(tname, !wbb_err_start_busy, "no START during ch1_wgt busy");
        report(tname, e0, $sformatf("CP-W mm %0d | LOAD %0d clk", mm, c_load));
    endtask

    // =========================================================================
    //  W2 : clear (burst zeros) -> custom load (grp, LCU, LCC) -> compare all 1024 rows
    //       expected = zeros, except row wcustom_row(i) = weight row i
    // =========================================================================
    task automatic test_wgt_custom(input string tname, input int seed, input int g, input int u, input int c,
                                   input bit hs);
        logic [255:0] wq [$], zq [$];
        logic [255:0] expf [0:NWROWS-1];
        logic [255:0] expv [0:NWROWS-1];
        int e0, c_clr, c_load, mm, nb, fbad;
        nb = wcustom_beats(g, u, c);
        $display("\n=== %s : seed %0d, custom load grp_sel=%0d LCU_sel=%0d LCC_sel=%0d (%0d beats), handshake %0d ===",
                 tname, seed, g, u, c, nb, hs);
        e0 = errors;
        read_wimg(seed, wq);
        zq = {};
        for (int k = 0; k < NWROWS; k++) zq.push_back('0);
        // expected image from the SV formula, cross-checked with the Python file
        for (int k = 0; k < NWROWS; k++) expv[k] = '0;
        for (int i = 0; i < nb; i++) expv[wcustom_row(i, g, u, c)] = wq[i];
        $readmemh($sformatf("%s/seed%0d/wgt_custom_%0d%0d%0d.hex", VEC_ROOT, seed, g, u, c), expf);
        fbad = 0;
        foreach (expv[k]) if (expv[k] !== expf[k] || $isunknown(expf[k])) fbad++;
        chk(tname, fbad == 0, $sformatf("SV address formula == gen_vectors.py expected image (%0d rows differ)", fbad));

        if (!skip_reset) do_reset();
        for (int k = 0; k < NWROWS; k++) l1w_poke(k, {8{32'hDEAD_0000 | k}});
        l2_write_256(ZERO_W_WORD, NWROWS, zq);
        l2_write_256(WGT_W_WORD, NWROWS, wq);
        for (int k = 0; k < NWROWS; k++) wbram_write(k, expv[k]);
        send_cmd(mk_wload_burst(ZERO_W_WORD, NWROWS, 0, hs));           // clear the cluster array
        wait_busy_sel(1, {tname, " clear"}, c_clr);
        send_cmd(mk_wload_custom(WGT_W_WORD, g, u, c, hs));
        wait_busy_sel(1, {tname, " custom"}, c_load);
        run_wbb(0, NWROWS, 10, mm);
        chk(tname, mm == 0, $sformatf("CP-W : %0d/%0d rows == expected (weights at %0d rows, zeros elsewhere), custom LOAD %0d clk",
                                      NWROWS - mm, NWROWS, nb, c_load));
        report(tname, e0, $sformatf("CP-W mm %0d | %0d beats, LOAD %0d clk", mm, nb, c_load));
    endtask

    // =========================================================================
    //  W4 : ch1_wgt LOAD (1024 rows) -> STORE rows back to L2 (cluster array -> L2), same mode both
    //       hs LOAD followed by hs STORE is the sequence that hung ch1_in (FINDING (B)) -> checks fix (D)
    // =========================================================================
    task automatic test_wgt_store(input string tname, input int seed, input bit hs, input int n, input int gap = 10);
        logic [255:0] wq [$], pz [$], rb [$];
        int e0, c_load, c_store, bad;
        $display("\n=== %s : seed %0d, ch1_wgt LOAD %0d rows then STORE %0d rows -> L2 0x%04h, handshake %0d ===",
                 tname, seed, NWROWS, n, WSTORE_W_WORD, hs);
        e0 = errors;
        read_wimg(seed, wq);
        if (!skip_reset) do_reset();
        pz = {};
        for (int k = 0; k <= n; k++) pz.push_back({8{32'hBAD0_5700 | k}});
        l2_write_256(WSTORE_W_WORD, n + 1, pz);
        l2_write_256(WGT_W_WORD, NWROWS, wq);
        send_cmd(mk_wload_burst(WGT_W_WORD, NWROWS, 0, hs));
        wait_busy_sel(1, {tname, " WLOAD"}, c_load);
        repeat (gap) @(negedge i_clk);
        send_cmd(mk_wstore(0, n, WSTORE_W_WORD, hs));
        wait_busy_sel(1, {tname, " WSTORE"}, c_store);
        l2_read_256(WSTORE_W_WORD, n + 1, rb);
        bad = 0;
        for (int k = 0; k < n; k++) if (rb[k] !== wq[k]) begin
            if (bad < 3) $display("    row %0d : got %08h.. want %08h..", k, rb[k][31:0], wq[k][31:0]);
            bad++;
        end
        if (rb[n] !== pz[n]) begin $display("    word after the region overwritten"); bad++; end
        chk(tname, bad == 0, $sformatf("L2 <- cluster array : %0d/%0d rows == weight image, next word untouched (LOAD %0d, STORE %0d clk)",
                                      n - bad, n, c_load, c_store));
        report(tname, e0, $sformatf("STORE %0d/%0d | LOAD %0d, STORE %0d clk", n - bad, n, c_load, c_store));
    endtask

    // =========================================================================
    //  M4 (inside MAP) : ch1_wgt LOAD across quad / group boundaries and the top of 1 MiB
    //  reference = the same 256b words read through ch0 with c256_to_ch0()
    // =========================================================================
    task automatic test_map_wgt();
        int starts[$], dst, bad, cyc;
        logic [255:0] ref_q [$];
        for (int g = 0; g < GROUPS; g++) begin
            starts.push_back((g << IN_GRP_256) | ((1 << ROW_BITS) - 2));             // quad0 row1022 -> quad1 row1
            if (g < GROUPS - 1) starts.push_back((g << IN_GRP_256) | ((1 << IN_GRP_256) - 2));  // group g -> g+1
        end
        starts.push_back((1 << SRC_W_256) - 4);                                       // top 0x7FFC..0x7FFF
        dst = 0; bad = 0;
        foreach (starts[i]) begin
            l2_read_256(starts[i], 4, ref_q);
            send_cmd(mk_wload_burst(starts[i], 4, dst));
            wait_busy_sel(1, "M4 WLOAD", cyc);
            repeat (4) @(negedge i_clk);
            for (int k = 0; k < 4; k++)
                if (l1w_peek(dst + k) !== ref_q[k]) begin
                    if (bad < 5) $display("    M4 mismatch wgt word 0x%04h -> L1w[%0d]", starts[i] + k, dst + k);
                    bad++;
                end
            dst += 4;
        end
        chk("M4", bad == 0, $sformatf("%0d ch1_wgt LOADs (quad & group boundaries, top 0x%04h, SRC_W=%0d) : %0d bad",
                                      starts.size(), (1 << SRC_W_256) - 1, SRC_W_256, bad));
    endtask

    // =========================================================================
    //  O* : output path = Blackbox -> L2 ch2_in store
    //   X LOAD + CP-A as before, then Golden (psum16 / out8 words) is streamed into ch2_in.
    //   CP-B = L2 words read through ch0 ; chain = ch1_in LOAD of the stored words back to L1
    // =========================================================================
    task automatic test_out_c2(input string tname, input int seed, input bit psum, input int H, input int W,
                               input int NB, input bit prec, input bit hs, input bit cmd_first,
                               input logic [1:0] inj, input bit chain, input int dest);
        logic [DW-1:0] xa [0:NX-1];
        logic [DW-1:0] ga [0:31];
        logic [DW-1:0] xv [$], pz [$], rb [$], ex [$];
        logic [DW-1:0] poison;
        int e0, c_load, nw, njp, bad, cbad, t, lo, hi, cyc;
        longint t_c2;
        string gfile;
        njp = (NB + 1) / 2;
        nw  = njp * H * W;
        $display("\n=== %s : seed %0d %s H=%0d W=%0d NB=%0d prec_field=%0d hs=%0d %s inj=%0d dest=0x%04h (%0d words) ===",
                 tname, seed, psum ? "psum16" : "out8", H, W, NB, prec, hs,
                 cmd_first ? "cmd->START" : "START->cmd", inj, dest, nw);
        e0 = errors;
        $readmemh($sformatf("%s/seed%0d/x.hex", VEC_ROOT, seed), xa);
        if (psum) gfile = "psum16.hex"; else gfile = "out8.hex";   // (no ?: on string literals : it pads the short one)
        $readmemh($sformatf("%s/seed%0d/%s", VEC_ROOT, seed, gfile), ga);
        xv = {};
        foreach (xa[k]) xv.push_back(xa[k]);
        begin
            int nx_bad = 0;
            for (int k = 0; k < nw; k++) if ($isunknown(ga[k])) nx_bad++;
            foreach (xa[k]) if ($isunknown(xa[k])) nx_bad++;
            chk(tname, nx_bad == 0, $sformatf("vectors loaded (x.hex, %s) : %0d words with X", gfile, nx_bad));
        end

        if (!skip_reset) do_reset();
        for (int k = 0; k < NX; k++) l1_poke(L1_IN_BASE + k, {16{32'hDEAD_0000 | k}});
        // poison the destination (+1 word on each side, inside 1 MiB)
        poison = {16{32'hBAD0_C200}};
        lo = (dest > 0) ? dest - 1 : dest;
        hi = (dest + nw < (1 << SRC_W)) ? dest + nw : dest + nw - 1;
        pz = {};
        for (int k = lo; k <= hi; k++) pz.push_back(poison);
        l2_write_beats(lo, hi - lo + 1, pz);
        // X in L2 + Expected, Golden -> BRAM
        l2_write_beats(X_CH1_WORD, NX, xv);
        for (int k = 0; k < NX; k++) bram_write(0, k, xv[k]);
        for (int k = 0; k < nw; k++) bram_write(1, k, ga[k]);
        send_cmd(mk_load(X_CH1_WORD, NX, L1_IN_BASE));
        wait_busy_cycle({tname, " LOAD"}, c_load);

        // Blackbox : RD_IN (CP-A) -> ch2 out
        repeat (10) @(negedge i_clk);
        bb_in_base = L1_IN_BASE; bb_in_len = NX; bb_out_base = 0; bb_out_len = 0;
        bb_latency = 10; bb_inject = inj;
        bb_out_sel = 1; bb_c2_prec = prec; bb_c2_hs = hs; bb_c2_h = H; bb_c2_w = W; bb_c2_nb = NB;
        t_c2 = cyc_now;
        if (cmd_first) send_cmd(mk_c2_store(dest, H, W, prec, hs));
        bb_start_pulse();
        if (!cmd_first) begin
            repeat (300) @(negedge i_clk);                  // BB reaches the ch2 phase and waits for ready
            send_cmd(mk_c2_store(dest, H, W, prec, hs));
        end
        t = 0;
        while (!bb_done) begin
            settle();
            if (++t > 50000) begin $display("    !! BB done timeout (ch2 out stuck, state=%0d)", dut_bb.st); errors++; break; end
        end
        t = 0;
        while (busy_ch2_in !== 1'b0) begin
            settle();
            if (++t > 50000) begin $display("    !! ch2_in busy never fell"); errors++; break; end
        end
        cyc = int'(cyc_now - t_c2);
        bb_out_sel = 0;
        $display("    [3] BB cycles=%0d CP-A mismatch=%0d ; ch2 store done %0d clk after the store phase began",
                 bb_cycles, bb_mm_cnt, cyc);
        chk(tname, bb_mm_cnt == 0, $sformatf("CP-A mismatch = %0d", bb_mm_cnt));

        // CP-B : L2 words through ch0
        ex = {};
        for (int k = 0; k < nw; k++) begin
            logic [DW-1:0] e;
            e = ga[k];
            if (2 * (k / (H * W)) + 1 >= NB) e[DW-1:DW/2] = poison[DW-1:DW/2];   // upper 256b never written
            if (k == 0 && inj[0]) e[0] = ~e[0];
            ex.push_back(e);
        end
        l2_read_beats(dest, nw, rb);
        bad = 0;
        for (int k = 0; k < nw; k++)
            if (rb[k] !== ex[k]) begin
                if (bad < 4) $display("    CP-B word %0d (L2 0x%04h) : got ..%08h_%08h want ..%08h_%08h", k, dest + k,
                                      rb[k][287:256], rb[k][31:0], ex[k][287:256], ex[k][31:0]);
                bad++;
            end
        l2_read_beats(lo, 1, rb);
        if (lo != dest && rb[0] !== poison) begin $display("    word below the region was overwritten"); bad++; end
        l2_read_beats(hi, 1, rb);
        if (hi != dest + nw - 1 && rb[0] !== poison) begin $display("    word above the region was overwritten"); bad++; end
        if (inj[0]) chk(tname, bad == 0, $sformatf("CP-B with inject : only word0 bit0 differs from Golden (%0d unexpected)", bad));
        else        chk(tname, bad == 0, $sformatf("CP-B : %0d/%0d L2 words == Golden, neighbours untouched", nw - bad, nw));

        // chain : the stored words are the next layer's input -> ch1_in LOAD back to L1
        cbad = 0;
        if (chain) begin
            send_cmd(mk_load(dest, nw, 512));
            wait_busy_cycle({tname, " chain LOAD"}, c_load);
            repeat (4) @(negedge i_clk);
            for (int k = 0; k < nw; k++) if (l1_peek(512 + k) !== ex[k]) cbad++;
            chk(tname, cbad == 0, $sformatf("chain : ch1_in LOAD of the stored words -> L1 %0d/%0d == Golden", nw - cbad, nw));
        end
        report(tname, e0, $sformatf("CP-A %0d, CP-B %0d/%0d%s | ch2 %0d clk", bb_mm_cnt, nw - bad, nw,
                                    chain ? $sformatf(", chain %0d/%0d", nw - cbad, nw) : "", cyc));
    endtask

    // =========================================================================
    //  R0 : regression, BB idle
    // =========================================================================
    task automatic test_r0();
        int e0, cyc;
        logic [DW-1:0] pat [5];
        $display("\n=== R0 : regression STORE(L1 0..4 -> L2 0) -> LOAD(L2 0 -> L1 50..54), BB idle ===");
        e0 = errors;
        do_reset();
        for (int k = 0; k < 5; k++) begin
            pat[k] = '0;
            pat[k][31:0]    = 32'hC0DE_0000 + k;
            pat[k][159:128] = 32'h1111_0000 + k;
            pat[k][287:256] = 32'h2222_0000 + k;
            pat[k][511:480] = 32'h3333_0000 + k;
            l1_poke(k, pat[k]);
            l1_poke(50 + k, '0);
        end
        send_cmd(mk_store(0, 5, 0));
        wait_busy_cycle("R0 STORE", cyc);
        repeat (10) @(negedge i_clk);
        send_cmd(mk_load(0, 5, 50));
        wait_busy_cycle("R0 LOAD", cyc);
        repeat (10) @(negedge i_clk);
        for (int k = 0; k < 5; k++) begin
            logic [DW-1:0] g;
            g = l1_peek(50 + k);
            chk("R0", g === pat[k], $sformatf("L1[%0d] = ..%08h_%08h  (512b compare)", 50 + k, g[159:128], g[31:0]));
        end
        chk("R0", !pe_busy && !bb_busy, "Blackbox stayed idle");
        report("R0", e0, "5/5 beats, full 512b");
    endtask

    // =========================================================================
    //  full flow ① ~ ⑥
    // =========================================================================
    typedef struct {
        int    seed;
        logic [1:0] inject;
        int    latency;
        int    start_gap;   // clocks between LOAD busy fall and START (0 = very next clock)
        int    store_gap;   // clocks between BB done and STORE command
        bit    hs_load;     // LOAD  mode 01 (handshake) instead of 00
        bit    hs_store;    // STORE mode 11 (handshake) instead of 10
    } flow_cfg_t;

    // returns CP-B bad-beat bitmap (bit k = beat k bad)
    task automatic run_flow(input string tname, input flow_cfg_t cfg, output logic [NY-1:0] badmap,
                            output int cpa_mm, output string timing);
        logic [DW-1:0] xv [$], gv [$], rb [$];
        logic [DW-1:0] xa [0:NX-1];
        logic [DW-1:0] ga [0:NY-1];
        int c_wr, c_load, c_store, c_rd, t, l1_in_ok, l1_out_ok;
        longint t0;
        string vdir;

        vdir = $sformatf("%s/seed%0d", VEC_ROOT, cfg.seed);
        $readmemh({vdir, "/x.hex"}, xa);
        $readmemh({vdir, "/golden.hex"}, ga);
        foreach (xa[k]) if ($isunknown(xa[k])) begin $display("    !! x.hex beat %0d has X", k); errors++; end
        foreach (ga[k]) if ($isunknown(ga[k])) begin $display("    !! golden.hex beat %0d has X", k); errors++; end
        xv = {}; gv = {};
        foreach (xa[k]) xv.push_back(xa[k]);
        foreach (ga[k]) gv.push_back(ga[k]);
        if (!skip_reset) do_reset();
        dropped_wr = 0;
        // poison L1 IN / OUT so stale data can't pass
        for (int k = 0; k < NX; k++) l1_poke(L1_IN_BASE + k, {16{32'hDEAD_0000 | k}});
        for (int k = 0; k < NY; k++) l1_poke(L1_OUT_BASE + k, {16{32'hBEEF_0000 | k}});

        // ① ch0 : X -> L2 , poison L2 OUT, BRAM load
        t0 = cyc_now;
        l2_write_beats(X_CH1_WORD, NX, xv);
        c_wr = int'(cyc_now - t0);
        begin
            logic [DW-1:0] poison [$];
            for (int k = 0; k < NY; k++) poison.push_back({16{32'hBAD0_0000 | k}});
            l2_write_beats(OUT_CH1_WORD, NY, poison);
        end
        for (int k = 0; k < NX; k++) bram_write(0, k, xv[k]);
        for (int k = 0; k < NY; k++) bram_write(1, k, gv[k]);
        $display("    [1] ch0 write X : %0d beats in %0d clk (8 lane bursts)", NX, c_wr);

        // ② LOAD  L2 X -> L1 IN
        send_cmd(mk_load(X_CH1_WORD, NX, L1_IN_BASE, cfg.hs_load));
        wait_busy_cycle({tname, " LOAD"}, c_load);
        // diagnostic intermediate point (not a CP) : L1 IN right at busy fall
        l1_in_ok = 0;
        for (int k = 0; k < NX; k++) if (l1_peek(L1_IN_BASE + k) === xv[k]) l1_in_ok++;
        $display("    [2] LOAD  cmd->busy fall : %0d clk ; L1 IN at busy fall : %0d/%0d beats == X",
                 c_load, l1_in_ok, NX);

        // ③ START (start_gap 0 = START sampled on the clock right after busy fell)
        repeat (cfg.start_gap) @(negedge i_clk);
        bb_in_base = L1_IN_BASE; bb_in_len = NX; bb_out_base = L1_OUT_BASE; bb_out_len = NY;
        bb_latency = cfg.latency; bb_inject = cfg.inject;
        bb_start_pulse();
        t = 0;
        while (!bb_done) begin
            settle();
            if (++t > 100000) begin $display("    !! BB done timeout (busy=%0d err_start_busy=%0d)", bb_busy, bb_err_start_busy); errors++; break; end
        end
        cpa_mm = bb_mm_cnt;
        $display("    [3] BB   cycles=%0d  CP-A mismatch=%0d first_idx=%0d(valid=%0d) got=%08h exp=%08h err_start_busy=%0d",
                 bb_cycles, bb_mm_cnt, bb_first_idx, bb_first_valid, bb_first_got, bb_first_exp, bb_err_start_busy);
        // ④ (diagnostic) L1 OUT after BB
        l1_out_ok = 0;
        for (int k = 0; k < NY; k++) if (l1_peek(L1_OUT_BASE + k) === gv[k]) l1_out_ok++;
        $display("    [4] L1 OUT after BB : %0d/%0d beats == Golden ; NoC->L1 writes dropped by pe_busy : %0d ; last NoC L1 write = busy fall + %0d clk",
                 l1_out_ok, NY, dropped_wr, int'(last_noc_wr - busy_fall_cyc));

        // ⑤ STORE L1 OUT -> L2 0xA_0000
        repeat (cfg.store_gap) @(negedge i_clk);
        send_cmd(mk_store(L1_OUT_BASE, NY, OUT_CH1_WORD, cfg.hs_store));
        wait_busy_cycle({tname, " STORE"}, c_store);
        $display("    [5] STORE cmd->busy fall : %0d clk", c_store);

        // ⑥ ch0 read L2 0xA_0000 -> compare Golden (CP-B)
        t0 = cyc_now;
        l2_read_beats(OUT_CH1_WORD, NY, rb);
        c_rd = int'(cyc_now - t0);
        badmap = '0;
        for (int k = 0; k < NY; k++) if (rb[k] !== gv[k]) badmap[k] = 1'b1;
        $display("    [6] ch0 read OUT : %0d clk ; CP-B %0d/%0d beats == Golden (badmap=%04h)",
                 c_rd, NY - $countones(badmap), NY, badmap);
        if (badmap[0] && cfg.inject[0])
            $display("        beat0 diff = %0h", rb[0] ^ gv[0]);
        timing = $sformatf("ch0wr %0d / LOAD %0d / BB %0d / STORE %0d / ch0rd %0d clk",
                           c_wr, c_load, bb_cycles, c_store, c_rd);
    endtask

    task automatic test_flow_pass(input string tname, input flow_cfg_t cfg);
        int e0, mm;
        logic [NY-1:0] bad;
        string tm;
        $display("\n=== %s : seed %0d  latency %0d  start_gap %0d  store_gap %0d  hs_load %0d  hs_store %0d ===",
                 tname, cfg.seed, cfg.latency, cfg.start_gap, cfg.store_gap, cfg.hs_load, cfg.hs_store);
        e0 = errors;
        run_flow(tname, cfg, bad, mm, tm);
        chk(tname, mm == 0, $sformatf("CP-A mismatch = %0d", mm));
        chk(tname, bad == '0, $sformatf("CP-B %0d/%0d", NY - $countones(bad), NY));
        report(tname, e0, $sformatf("CP-A %0d mm, CP-B %0d/%0d | %s", mm, NY - $countones(bad), NY, tm));
    endtask

    // =========================================================================
    initial begin
        flow_cfg_t c;
        int e0, mm;
        logic [NY-1:0] bad;
        string tm;

        string only;
        if (!$value$plusargs("ONLY=%s", only)) only = "";

        repeat (3) @(negedge i_clk);

        if (only == "" || only == "R0") test_r0();
        if (only == "" || only == "MAP") test_map();

        if (only == "" || only == "S1") begin
            c = '{seed:1, inject:2'b00, latency:10, start_gap:10, store_gap:10, hs_load:0, hs_store:0};
            test_flow_pass("S1 seed1", c);
        end

        if (only == "" || only == "S2")
            for (int s = 2; s <= 4; s++) begin
                c = '{seed:s, inject:2'b00, latency:10, start_gap:10, store_gap:10, hs_load:0, hs_store:0};
                test_flow_pass($sformatf("S2 seed%0d", s), c);
            end

        if (only == "" || only == "S3") begin
            // S3 : inject[0] must be detected by CP-B on beat 0 only
            $display("\n=== S3 : inject[0] -> CP-B must flag exactly beat 0 ===");
            e0 = errors;
            c = '{seed:1, inject:2'b01, latency:10, start_gap:10, store_gap:10, hs_load:0, hs_store:0};
            run_flow("S3", c, bad, mm, tm);
            chk("S3", mm == 0, $sformatf("CP-A mismatch = %0d", mm));
            chk("S3", bad == 16'h0001, $sformatf("CP-B badmap = %04h (want 0001)", bad));
            report("S3 inject0", e0, $sformatf("CP-B detected beat0 only (badmap=%04h)", bad));
        end

        if (only == "" || only == "S4") begin
            c = '{seed:2, inject:2'b00, latency:10, start_gap:0, store_gap:0, hs_load:0, hs_store:0};
            test_flow_pass("S4 gap0", c);
        end

        if (only == "" || only == "S5") begin
            c = '{seed:3, inject:2'b00, latency:0, start_gap:10, store_gap:10, hs_load:0, hs_store:0};
            test_flow_pass("S5 lat0", c);
            c = '{seed:4, inject:2'b00, latency:10000, start_gap:10, store_gap:10, hs_load:0, hs_store:0};
            test_flow_pass("S5 lat10000", c);
        end

        if (only == "" || only == "S6") begin
            c = '{seed:1, inject:2'b00, latency:10, start_gap:10, store_gap:10, hs_load:1, hs_store:0};
            test_flow_pass("S6a hs LOAD", c);
            c = '{seed:2, inject:2'b00, latency:10, start_gap:10, store_gap:10, hs_load:0, hs_store:1};
            test_flow_pass("S6b hs STORE", c);
            c = '{seed:3, inject:2'b00, latency:10, start_gap:10, store_gap:10, hs_load:1, hs_store:1};
            test_flow_pass("S6c hs both", c);
            // back-to-back without reset : hs STORE (S6c) -> hs LOAD -> hs STORE
            skip_reset = 1;
            c = '{seed:4, inject:2'b00, latency:10, start_gap:10, store_gap:10, hs_load:1, hs_store:1};
            test_flow_pass("S6d hs no-reset", c);
            skip_reset = 0;
        end

        if (only == "" || only == "S7") begin
            c = '{seed:1, inject:2'b00, latency:10, start_gap:0, store_gap:0, hs_load:1, hs_store:1};
            test_flow_pass("S7 hs gap0", c);
        end

        chk("ALL", conflicts == 0, $sformatf("L1 PE/NoC port conflicts over the whole run = %0d", conflicts));

        if (only == "" || only == "W") begin
            test_wgt_burst("W1 wgt burst", 1, 0, 10);
            test_wgt_burst("W1h wgt burst hs", 2, 1, 10);
            skip_reset = 1;                                    // hs burst -> hs custom, no reset in between
            test_wgt_custom("W2h custom322 hs", 2, 3, 2, 2, 1);
            skip_reset = 0;
            test_wgt_custom("W2 custom711", 1, 7, 1, 1, 0);    // PDF p27 Conv(64,128,1,1)
            test_wgt_custom("W2 custom322", 2, 3, 2, 2, 0);    // PDF p28 Conv(16,64,3,3)
            test_wgt_custom("W2 custom723", 3, 7, 2, 3, 0);    // max : 768 rows
            test_wgt_custom("W2 custom000", 4, 0, 0, 0, 0);    // min : 8 rows
            test_wgt_burst("W3 wgt gap0", 3, 0, 0);
            test_wgt_store("W4 wgt store", 4, 0, 256);
            for (int g = 10; g <= 13; g++)                       // all phases of the stale-mode restart loop
                test_wgt_store($sformatf("W4h hs ld->st gap%0d", g), 1, 1, 256, g);
        end

        if (only == "O5")
            test_out_c2("O5 hs out8",         1, 0,  1, 16, 2, 0,  1, 1,  2'b00, 1, C2_OUT8_WORD);
        if (only == "" || only == "O") begin
            //            name              seed psum H  W  NB prec hs cmd1st inj chain dest
            test_out_c2("O1 psum16",          1, 1,  1, 16, 4, 1,  0, 1,  2'b00, 0, C2_PSUM_WORD);
            test_out_c2("O2 out8+chain",      2, 0,  1, 16, 2, 0,  0, 0,  2'b00, 1, C2_OUT8_WORD);
            test_out_c2("O3 psum H2W8 NB3",   3, 1,  2,  8, 3, 1,  0, 1,  2'b00, 0, C2_PSUM_WORD);
            test_out_c2("O4 inject0",         4, 1,  1, 16, 4, 1,  0, 1,  2'b01, 0, C2_PSUM_WORD);
            test_out_c2("O5 hs out8",         1, 0,  1, 16, 2, 0,  1, 1,  2'b00, 1, C2_OUT8_WORD);
            skip_reset = 1;                                    // 2nd hs store right after the 1st
            test_out_c2("O6 hs psum no-reset",2, 1,  1, 16, 4, 1,  1, 1,  2'b00, 0, C2_PSUM_WORD);
            skip_reset = 0;
            test_out_c2("O7 top 0x3FF0",      3, 0,  1, 16, 2, 0,  0, 1,  2'b00, 1, (1 << SRC_W) - 16);
            test_out_c2("O8 group cross",     4, 1,  1, 16, 4, 1,  0, 1,  2'b00, 1, (3 << IN_GRP_CH1) - 8);
        end

        // diagnostic (+ONLY=SWEEP) : from which START gap after LOAD busy fall is it safe?
        if (only == "SWEEP")
            for (int g = 0; g <= 6; g++) begin
                c = '{seed:2, inject:2'b00, latency:10, start_gap:g, store_gap:10, hs_load:0, hs_store:0};
                test_flow_pass($sformatf("SWEEP gap%0d", g), c);
            end

        $display("\n================ Phase 2 summary ================");
        foreach (results[i]) $display("  %s", results[i]);
        $display("  PASS %0d / FAIL %0d", npass, nfail);
        $display("=================================================");
        if (errors == 0) $display("PASS (errors=0)");
        else             $display("FAIL (errors=%0d)", errors);
        $finish;
    end

    initial begin
        #100_000_000;
        $display("!! GLOBAL TIMEOUT");
        $display("FAIL (errors=%0d)", errors + 1);
        $finish;
    end

endmodule
