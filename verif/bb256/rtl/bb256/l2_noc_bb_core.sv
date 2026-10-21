`timescale 1ns/1ps
// =============================================================================
//  l2_noc_bb_core  (256b 버전, CH1 + CH2)
//
//    CH1 (linear / MAC 자리)
//    TOP_L2_cache ch1_in  (256b) -> noc_ch1_in_adapter  -> FIFO_intf_bb (L1 256b x 2048) <-> blackbox_ip
//    TOP_L2_cache ch1_wgt (256b) -> noc_ch1_wgt_adapter -> blackbox_ip 내부 weight 메모리 (256b x 1024)
//    CH2 (nonlinear 자리)
//    TOP_L2_cache ch2_in  LOAD  (256b) -> noc_wr_adapter -> blackbox_nl 내부 input 메모리  (256b x 2048)
//    TOP_L2_cache ch2_wgt LOAD  (256b) -> noc_wr_adapter -> blackbox_nl 내부 weight 메모리 (256b x 512)
//    TOP_L2_cache ch2_in  STORE        <- blackbox_nl (Golden -> L2, BB 가 master)
//
//  LHJ/261020 에서 바뀐 것
//  - ch1_in 512b -> 256b (L1 도 256b x 2048)
//  - ch1_wgt, ch2_in, ch2_wgt 연결 (이전에는 tie-off)
//  - blackbox_pe -> blackbox_ip (CH1) + blackbox_nl (CH2) : weight 저장, input 읽기, Golden 출력. 비교 없음.
//  - fence : 받아들인 명령의 opcode 를 기억해서 그 채널의 busy 와 NoC 쓰기 commit 으로 완료를 판정한다.
//            명령은 여전히 한 번에 하나만 들어간다. blackbox 와의 배타 관계는 채널 묶음별로 나눈다:
//              CH1 묶음 (opcode 1,2,5,6) <-> blackbox_ip  : 서로 배타
//              CH2 LOAD (opcode 3,7)     <-> blackbox_nl  : 서로 배타
//              CH2 STORE (opcode 4)      : blackbox_nl 의 출력 경로라 blackbox_nl 실행 중에도 받는다.
// =============================================================================
module l2_noc_bb_core #(
 parameter GROUPS=8, BLOCKS=16, ADDRESS_ROW=1024, BB_GUARD=2,
 parameter BW_CH0=64,
 parameter CH0_ADDR_WIDTH=$clog2(GROUPS*BLOCKS*ADDRESS_ROW)
)(

    input wire aclk, aresetn,
    input wire [CH0_ADDR_WIDTH-1:0] ch_awaddr,
    input wire [7:0]                ch_awlen,
    input wire                      ch_awvalid,
    output  wire                      ch_awready,
    input wire [BW_CH0-1:0]               ch_wdata,
    input wire                      ch_wlast,
    input wire                      ch_wvalid,
    output  wire                      ch_wready,
    output  wire                      ch_bvalid,
    input wire                      ch_bready,
    input wire [CH0_ADDR_WIDTH-1:0] ch_araddr,
    input wire [7:0]                ch_arlen,
    input wire                      ch_arvalid,
    output  wire                      ch_arready,
    output  wire [BW_CH0-1:0]               ch_rdata,
    output  wire                      ch_rlast,
    output  wire                      ch_rvalid,
    input wire                      ch_rready,
    input wire [63:0] command,
    input wire command_valid,
    output wire command_ready,
    output wire [3:0] channel_busy,
    output reg [31:0] completed_count,
    output wire [2:0] exec_status,
    output wire start_allowed,
    output wire start_allowed2,
    // ---- CH1 blackbox ----
    input wire bb_start,
    input wire bb_inject,
    input wire [10:0] bb_in_base, bb_out_base,
    input wire [11:0] bb_in_len,
    input wire [8:0] bb_out_len,
    input wire [9:0] bb_w_base,
    input wire [10:0] bb_w_len,
    input wire [31:0] bb_latency,
    input wire gold_we,
    input wire [7:0] gold_addr,
    input wire [255:0] gold_wdata,
    output wire bb_busy, bb_done, bb_err_start_busy,
    output wire [31:0] bb_cycles,
    // ---- CH2 blackbox ----
    input wire bb2_start,
    input wire bb2_dbg_req,
    input wire bb2_dbg_sel,
    input wire [10:0] bb2_dbg_row,
    input wire bb2_inject, bb2_hs, bb2_prec,
    input wire [10:0] bb2_in_base,
    input wire [11:0] bb2_in_len,
    input wire [8:0] bb2_w_base,
    input wire [9:0] bb2_w_len,
    input wire [9:0] bb2_h, bb2_w,
    input wire [6:0] bb2_nb,
    input wire [31:0] bb2_latency,
    input wire gold2_we,
    input wire [7:0] gold2_addr,
    output wire bb2_busy, bb2_done, bb2_err_start_busy, bb2_dbg_valid,
    output wire [31:0] bb2_cycles,
    output wire [255:0] bb2_dbg_data
);
 localparam BW_CH1_IN=256, DA_CH1_IN=19, NOC_ADDR_DEPTH=2048, NOC_ADDR_BW=11;
 localparam BW_CH1_WGT=256, DA_CH1_WGT=18, W_DEPTH=1024, W_AW=10;
 localparam BW_CH2_IN=256, DA_CH2_IN=15, I2_DEPTH=2048, I2_AW=11;
 localparam BW_CH2_WGT=256, DA_CH2_WGT=9, W2_DEPTH=512, W2_AW=9;

    // ch1_in NoC (L2 side)
    wire                 l2_w_ready, l2_w_valid, l2_w_resp;
    wire [DA_CH1_IN-1:0] l2_w_addr, l2_r_addr;
    wire [BW_CH1_IN-1:0] l2_w_data, l2_r_data;
    wire                 l2_r_valid, l2_r_data_ready, l2_r_ready, l2_r_resp, l2_ctrl_mode;
    // ch1_wgt NoC (L2 side)
    wire                  wl2_w_ready, wl2_w_valid, wl2_w_resp;
    wire [DA_CH1_WGT-1:0] wl2_w_addr, wl2_r_addr;
    wire [BW_CH1_WGT-1:0] wl2_w_data, wl2_r_data;
    wire                  wl2_r_valid, wl2_r_data_ready, wl2_r_ready, wl2_r_resp, wl2_ctrl_mode;
    // ch2_in NoC (L2 side) : write = LOAD, read = STORE (engine is the master)
    wire                  c2_w_ready, c2_w_valid, c2_w_resp, c2_ctrl_mode;
    wire [DA_CH2_IN-1:0]  c2_w_addr;
    wire [BW_CH2_IN-1:0]  c2_w_data;
    wire                  c2_s_valid, c2_s_ready, c2_s_resp;
    wire [31:0]           c2_s_addr;
    wire [BW_CH2_IN-1:0]  c2_s_data;
    // ch2_wgt NoC (L2 side)
    wire                  c2w_w_ready, c2w_w_valid, c2w_w_resp, c2w_ctrl_mode;
    wire [DA_CH2_WGT-1:0] c2w_w_addr;
    wire [BW_CH2_WGT-1:0] c2w_w_data;

 wire busy_ch1_in, busy_ch1_wgt, busy_ch2_in, busy_ch2_wgt, l2_ready;
 wire l1_write_commit, w_write_commit, i2_write_commit, w2_write_commit;
 wire l1_port_conflict, w_port_conflict, i2_port_conflict, w2_port_conflict;
 wire port_conflict = l1_port_conflict || w_port_conflict || i2_port_conflict || w2_port_conflict;
 reg in_flight, saw_busy, fence_error;
 reg [2:0] r_op;
 reg [31:0] writes_issued, writes_committed;
 assign channel_busy = {busy_ch2_wgt, busy_ch1_wgt, busy_ch2_in, busy_ch1_in};

 // opcode classes
 localparam [1:0] CLS_CH1 = 2'd0, CLS_C2L = 2'd1, CLS_C2S = 2'd2, CLS_NONE = 2'd3;
 function automatic [1:0] op_cls(input [2:0] op);
   case (op)
     3'd1, 3'd2, 3'd5, 3'd6: op_cls = CLS_CH1;
     3'd3, 3'd7:             op_cls = CLS_C2L;
     3'd4:                   op_cls = CLS_C2S;
     default:                op_cls = CLS_NONE;
   endcase
 endfunction
 wire [1:0] cmd_cls = op_cls(command[62:60]);
 wire [1:0] cur_cls = op_cls(r_op);
 wire ch1_cmd_pending = (in_flight && cur_cls == CLS_CH1) || (command_valid && cmd_cls == CLS_CH1);
 wire c2l_cmd_pending = (in_flight && cur_cls == CLS_C2L) || (command_valid && cmd_cls == CLS_C2L);
 wire bb2_any_busy    = bb2_busy || bb2_start || bb2_dbg_req;

 wire admit_command = !in_flight && !fence_error &&
                      !(cmd_cls == CLS_CH1 && (bb_busy || bb_start)) &&
                      !(cmd_cls == CLS_C2L && bb2_any_busy);
 assign command_ready = l2_ready && admit_command;
 wire bb_noc_busy  = busy_ch1_in || busy_ch1_wgt || ch1_cmd_pending || fence_error;
 wire bb2_noc_busy = busy_ch2_wgt || c2l_cmd_pending || fence_error;
 assign start_allowed  = !bb_busy && !bb_start && !bb_noc_busy;
 assign start_allowed2 = !bb2_any_busy && !bb2_noc_busy;
 assign exec_status = {fence_error, start_allowed, in_flight};

 // Only one command may enter L2. Count physical memory write commits,
 // not a fixed delay from L2 busy. Handshake mode counts response pulses,
 // because valid is held across cycles and FIFO-ready is tied high.
 // STORE opcodes (2, 4, 6) issue no NoC writes : they complete when the channel busy falls.
 reg sel_busy, sel_wvalid, sel_issue, sel_commit;
 always @(*) begin
   case (r_op)
     3'd1, 3'd2: begin
       sel_busy = busy_ch1_in;  sel_wvalid = l2_w_valid;  sel_commit = l1_write_commit;
       sel_issue = l2_ctrl_mode ? l2_w_resp : (l2_w_valid && l2_w_ready);
     end
     3'd5, 3'd6: begin
       sel_busy = busy_ch1_wgt; sel_wvalid = wl2_w_valid; sel_commit = w_write_commit;
       sel_issue = wl2_ctrl_mode ? wl2_w_resp : (wl2_w_valid && wl2_w_ready);
     end
     3'd3, 3'd4: begin
       sel_busy = busy_ch2_in;  sel_wvalid = c2_w_valid;  sel_commit = i2_write_commit;
       sel_issue = c2_ctrl_mode ? c2_w_resp : (c2_w_valid && c2_w_ready);
     end
     3'd7: begin
       sel_busy = busy_ch2_wgt; sel_wvalid = c2w_w_valid; sel_commit = w2_write_commit;
       sel_issue = c2w_ctrl_mode ? c2w_w_resp : (c2w_w_valid && c2w_w_ready);
     end
     default: begin
       sel_busy = 1'b0; sel_wvalid = 1'b0; sel_commit = 1'b0; sel_issue = 1'b0;
     end
   endcase
 end
 always @(posedge aclk or negedge aresetn) begin
   if(!aresetn) begin
     in_flight<=0; saw_busy<=0; completed_count<=0; fence_error<=0; r_op<=0;
     writes_issued<=0; writes_committed<=0;
   end else begin
     if(port_conflict) fence_error<=1;
     if(command_valid && command_ready) begin
       in_flight<=1; saw_busy<=0; writes_issued<=0; writes_committed<=0;
       r_op<=command[62:60];
     end else if(in_flight) begin
       if(sel_busy) saw_busy<=1;
       if(sel_issue) writes_issued<=writes_issued+1;
       if(sel_commit) writes_committed<=writes_committed+1;
       if(saw_busy && !sel_busy && writes_issued==writes_committed &&
          !sel_wvalid && !sel_commit) begin
          in_flight<=0; completed_count<=completed_count+1;
       end
     end
   end
 end
 initial begin
   if(GROUPS!=8 || BLOCKS!=16 || ADDRESS_ROW!=1024 || BB_GUARD<1)
      $fatal(1,"This validated integration targets 8x16x1024 with GUARD>=1");
 end
    // ---------------------------------------------------------------------
    //  L2
    // ---------------------------------------------------------------------
    TOP_L2_cache #(
        .GROUPS(GROUPS), .BLOCKS(BLOCKS), .ADDRESS_ROW(ADDRESS_ROW),
        .BANDWIDTH_CHANNEL_0(BW_CH0), .BANDWIDTH_CHANNEL_1_IN(BW_CH1_IN),
        .BANDWIDTH_CHANNEL_1_WGT(BW_CH1_WGT),
        .BANDWIDTH_CHANNEL_2_IN(BW_CH2_IN), .BANDWIDTH_CHANNEL_2_WGT(BW_CH2_WGT),
        .DESTINATION_ADDR_BIT_CHANNEL_1_IN(DA_CH1_IN), .DESTINATION_ADDR_BIT_CHANNEL_1_WGT(DA_CH1_WGT),
        .DESTINATION_ADDR_BIT_CHANNEL_2_IN(DA_CH2_IN), .DESTINATION_ADDR_BIT_CHANNEL_2_WGT(DA_CH2_WGT)
    ) u_l2 (
        .i_clk(aclk), .i_rstb(aresetn),
        .i_araddr_channel_0(ch_araddr), .i_arvalid_channel_0(ch_arvalid),
        .o_arready_channel_0(ch_arready), .i_arlen_channel_0(ch_arlen),
        .o_rdata_channel_0(ch_rdata), .o_rvalid_channel_0(ch_rvalid),
        .i_rready_channel_0(ch_rready), .o_rlast_channel_0(ch_rlast),
        .i_awaddr_channel_0(ch_awaddr), .i_awvalid_channel_0(ch_awvalid),
        .o_awready_channel_0(ch_awready), .i_awlen_channel_0(ch_awlen),
        .i_wdata_channel_0(ch_wdata), .i_wvalid_channel_0(ch_wvalid),
        .i_wlast_channel_0(ch_wlast), .o_wready_channel_0(ch_wready),
        .o_bvalid_channel_0(ch_bvalid), .i_bready_channel_0(ch_bready),

        .i_command(command), .i_command_valid(command_valid && admit_command), .o_command_ready(l2_ready),

        .o_busy_channel_1_in(busy_ch1_in),
        .i_noc_write_ready_channel_1_in(l2_w_ready), .o_noc_write_valid_channel_1_in(l2_w_valid),
        .o_noc_write_addr_channel_1_in(l2_w_addr), .o_noc_write_data_channel_1_in(l2_w_data),
        .i_noc_write_response_channel_1_in(l2_w_resp),
        .o_noc_read_addr_channel_1_in(l2_r_addr), .o_noc_read_valid_channel_1_in(l2_r_valid),
        .o_noc_read_data_ready_channel_1_in(l2_r_data_ready), .i_noc_read_ready_channel_1_in(l2_r_ready),
        .i_noc_read_response_channel_1_in(l2_r_resp), .i_noc_read_data_channel_1_in(l2_r_data),
        .o_noc_control_mode_channel_1_in(l2_ctrl_mode),

        .o_busy_channel_2_in(busy_ch2_in),
        .i_noc_write_ready_channel_2_in(c2_w_ready), .o_noc_write_valid_channel_2_in(c2_w_valid),
        .o_noc_write_addr_channel_2_in(c2_w_addr), .o_noc_write_data_channel_2_in(c2_w_data),
        .i_noc_write_response_channel_2_in(c2_w_resp),
        .o_noc_read_ready_channel_2_in(c2_s_ready), .i_noc_read_valid_channel_2_in(c2_s_valid),
        .i_noc_read_addr_channel_2_in(c2_s_addr), .i_noc_read_data_channel_2_in(c2_s_data),
        .o_noc_read_response_channel_2_in(c2_s_resp), .o_noc_control_mode_channel_2_in(c2_ctrl_mode),

        .o_busy_channel_1_wgt(busy_ch1_wgt),
        .i_noc_write_ready_channel_1_wgt(wl2_w_ready), .o_noc_write_valid_channel_1_wgt(wl2_w_valid),
        .o_noc_write_addr_channel_1_wgt(wl2_w_addr), .o_noc_write_data_channel_1_wgt(wl2_w_data),
        .i_noc_write_response_channel_1_wgt(wl2_w_resp),
        .o_noc_read_addr_channel_1_wgt(wl2_r_addr), .o_noc_read_valid_channel_1_wgt(wl2_r_valid),
        .o_noc_read_data_ready_channel_1_wgt(wl2_r_data_ready), .i_noc_read_ready_channel_1_wgt(wl2_r_ready),
        .i_noc_read_response_channel_1_wgt(wl2_r_resp), .i_noc_read_data_channel_1_wgt(wl2_r_data),
        .o_noc_control_mode_channel_1_wgt(wl2_ctrl_mode),

        .o_busy_channel_2_wgt(busy_ch2_wgt),
        .i_noc_write_ready_channel_2_wgt(c2w_w_ready), .o_noc_write_valid_channel_2_wgt(c2w_w_valid),
        .o_noc_write_addr_channel_2_wgt(c2w_w_addr), .o_noc_write_data_channel_2_wgt(c2w_w_data),
        .i_noc_write_response_channel_2_wgt(c2w_w_resp), .o_noc_control_mode_channel_2_wgt(c2w_ctrl_mode)
    );

    // =====================================================================
    //  CH1
    // =====================================================================
    // ---------------------------------------------------------------------
    //  ch1_in : adapter -> FIFO_intf_bb (L1) <- blackbox_ip
    // ---------------------------------------------------------------------
    wire                   m_write_valid, m_write_ready, m_fifo_write_ready;
    wire [NOC_ADDR_BW-1:0] m_write_addr, m_read_addr;
    wire [BW_CH1_IN-1:0]   m_write_data, m_read_data;
    wire                   m_read_valid, m_read_ready, m_fifo_read_ready, m_data_fifo_ready, m_control_mode;

    noc_ch1_in_adapter #(.DA_L2(DA_CH1_IN), .ADDR_BW(NOC_ADDR_BW), .DW(BW_CH1_IN)) u_adapter (
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

    wire                   pe_busy, pe_ceb, pe_web;
    wire [NOC_ADDR_BW-1:0] pe_addr;
    wire [BW_CH1_IN-1:0]   pe_din, pe_dout;

    FIFO_intf_bb #(.ADDR_DEPTH(NOC_ADDR_DEPTH), .DATA_WIDTH(BW_CH1_IN), .MEMORY_BITWIDTH(BW_CH1_IN/4),
                   .FIFO_DEPTH(8), .INPUT_DELAY(3)) u_noc (
        .clk(aclk), .rstb(aresetn),
        .i_read_valid(m_read_valid), .o_read_ready(m_read_ready),
        .i_read_addr(m_read_addr), .o_read_data(m_read_data),
        .i_write_valid(m_write_valid), .o_write_ready(m_write_ready),
        .i_write_addr(m_write_addr), .i_write_data(m_write_data),
        .i_control_mode(m_control_mode),
        .o_FIFO_read_ready(m_fifo_read_ready), .o_FIFO_write_ready(m_fifo_write_ready),
        .i_data_fifo_ready(m_data_fifo_ready),
        .i_pe_busy(pe_busy), .i_pe_ceb(pe_ceb), .i_pe_web(pe_web), .i_pe_addr(pe_addr),
        .i_pe_din(pe_din), .o_pe_dout(pe_dout), .o_noc_write_commit(l1_write_commit), .o_port_conflict(l1_port_conflict));

    // ---------------------------------------------------------------------
    //  ch1_wgt : adapter -> blackbox_ip weight memory
    // ---------------------------------------------------------------------
    wire                  wm_write_valid, wm_write_ready, wm_fifo_write_ready;
    wire [W_AW-1:0]       wm_write_addr, wm_read_addr;
    wire [BW_CH1_WGT-1:0] wm_write_data, wm_read_data;
    wire                  wm_read_valid, wm_read_ready, wm_fifo_read_ready, wm_data_fifo_ready, wm_control_mode;

    noc_ch1_wgt_adapter #(.DA_L2(DA_CH1_WGT), .ADDR_BW(W_AW), .DW(BW_CH1_WGT)) u_adapter_w (
        .l2_noc_write_valid(wl2_w_valid), .l2_noc_write_addr(wl2_w_addr), .l2_noc_write_data(wl2_w_data),
        .l2_noc_write_ready(wl2_w_ready), .l2_noc_write_response(wl2_w_resp),
        .l2_noc_read_valid(wl2_r_valid), .l2_noc_read_addr(wl2_r_addr),
        .l2_noc_read_data_ready(wl2_r_data_ready), .l2_noc_read_ready(wl2_r_ready),
        .l2_noc_read_response(wl2_r_resp), .l2_noc_read_data(wl2_r_data),
        .l2_noc_control_mode(wl2_ctrl_mode),
        .m_write_valid(wm_write_valid), .m_write_addr(wm_write_addr), .m_write_data(wm_write_data),
        .m_write_ready(wm_write_ready), .m_fifo_write_ready(wm_fifo_write_ready),
        .m_read_valid(wm_read_valid), .m_read_addr(wm_read_addr), .m_read_ready(wm_read_ready),
        .m_read_data(wm_read_data), .m_fifo_read_ready(wm_fifo_read_ready),
        .m_data_fifo_ready(wm_data_fifo_ready), .m_control_mode(wm_control_mode));

    // ---------------------------------------------------------------------
    //  blackbox_ip (CH1)
    // ---------------------------------------------------------------------
    blackbox_ip #(.DW(BW_CH1_IN), .L1_AW(NOC_ADDR_BW), .W_DEPTH(W_DEPTH), .G_DEPTH(256),
                  .GUARD(BB_GUARD)) u_bb (
        .clk(aclk), .rstn(aresetn),
        .i_start(bb_start),
        .i_noc_busy(bb_noc_busy),
        .i_in_base(bb_in_base), .i_in_len(bb_in_len), .i_w_base(bb_w_base), .i_w_len(bb_w_len),
        .i_out_base(bb_out_base), .i_out_len(bb_out_len),
        .i_latency(bb_latency), .i_inject(bb_inject),
        .i_gold_we(gold_we), .i_gold_addr(gold_addr), .i_gold_wdata(gold_wdata),
        .o_pe_busy(pe_busy), .o_ceb(pe_ceb), .o_web(pe_web), .o_addr(pe_addr), .o_din(pe_din), .i_dout(pe_dout),
        .i_w_read_valid(wm_read_valid), .o_w_read_ready(wm_read_ready),
        .i_w_read_addr(wm_read_addr), .o_w_read_data(wm_read_data),
        .i_w_write_valid(wm_write_valid), .o_w_write_ready(wm_write_ready),
        .i_w_write_addr(wm_write_addr), .i_w_write_data(wm_write_data),
        .i_w_control_mode(wm_control_mode),
        .o_w_FIFO_read_ready(wm_fifo_read_ready), .o_w_FIFO_write_ready(wm_fifo_write_ready),
        .i_w_data_fifo_ready(wm_data_fifo_ready),
        .o_w_noc_write_commit(w_write_commit), .o_w_port_conflict(w_port_conflict),
        .o_busy(bb_busy), .o_done(bb_done),
        .o_err_start_busy(bb_err_start_busy), .o_cycle_cnt(bb_cycles));

    // =====================================================================
    //  CH2
    // =====================================================================
    wire                 i2_write_valid, i2_write_ready, i2_fifo_write_ready, i2_control_mode;
    wire [I2_AW-1:0]     i2_write_addr;
    wire [BW_CH2_IN-1:0] i2_write_data;

    noc_wr_adapter #(.DA_L2(DA_CH2_IN), .ADDR_BW(I2_AW), .DW(BW_CH2_IN)) u_adapter_c2 (
        .l2_noc_write_valid(c2_w_valid), .l2_noc_write_addr(c2_w_addr), .l2_noc_write_data(c2_w_data),
        .l2_noc_write_ready(c2_w_ready), .l2_noc_write_response(c2_w_resp),
        .l2_noc_control_mode(c2_ctrl_mode),
        .m_write_valid(i2_write_valid), .m_write_addr(i2_write_addr), .m_write_data(i2_write_data),
        .m_write_ready(i2_write_ready), .m_fifo_write_ready(i2_fifo_write_ready),
        .m_control_mode(i2_control_mode));

    wire                  w2_write_valid, w2_write_ready, w2_fifo_write_ready, w2_control_mode;
    wire [W2_AW-1:0]      w2_write_addr;
    wire [BW_CH2_WGT-1:0] w2_write_data;

    noc_wr_adapter #(.DA_L2(DA_CH2_WGT), .ADDR_BW(W2_AW), .DW(BW_CH2_WGT)) u_adapter_c2w (
        .l2_noc_write_valid(c2w_w_valid), .l2_noc_write_addr(c2w_w_addr), .l2_noc_write_data(c2w_w_data),
        .l2_noc_write_ready(c2w_w_ready), .l2_noc_write_response(c2w_w_resp),
        .l2_noc_control_mode(c2w_ctrl_mode),
        .m_write_valid(w2_write_valid), .m_write_addr(w2_write_addr), .m_write_data(w2_write_data),
        .m_write_ready(w2_write_ready), .m_fifo_write_ready(w2_fifo_write_ready),
        .m_control_mode(w2_control_mode));

    // ---------------------------------------------------------------------
    //  blackbox_nl (CH2)
    // ---------------------------------------------------------------------
    blackbox_nl #(.DW(BW_CH2_IN), .I_DEPTH(I2_DEPTH), .W_DEPTH(W2_DEPTH), .G_DEPTH(256),
                  .GUARD(BB_GUARD)) u_bb2 (
        .clk(aclk), .rstn(aresetn),
        .i_start(bb2_start), .i_dbg_req(bb2_dbg_req), .i_dbg_sel(bb2_dbg_sel), .i_dbg_row(bb2_dbg_row),
        .i_noc_busy(bb2_noc_busy),
        .i_in_base(bb2_in_base), .i_in_len(bb2_in_len), .i_w_base(bb2_w_base), .i_w_len(bb2_w_len),
        .i_latency(bb2_latency), .i_inject(bb2_inject),
        .i_c2_prec(bb2_prec), .i_c2_hs(bb2_hs), .i_c2_h(bb2_h), .i_c2_w(bb2_w), .i_c2_nb(bb2_nb),
        .i_gold_we(gold2_we), .i_gold_addr(gold2_addr), .i_gold_wdata(gold_wdata),
        .i_i_write_valid(i2_write_valid), .o_i_write_ready(i2_write_ready),
        .i_i_write_addr(i2_write_addr), .i_i_write_data(i2_write_data),
        .i_i_control_mode(i2_control_mode), .o_i_FIFO_write_ready(i2_fifo_write_ready),
        .o_i_noc_write_commit(i2_write_commit), .o_i_port_conflict(i2_port_conflict),
        .i_w_write_valid(w2_write_valid), .o_w_write_ready(w2_write_ready),
        .i_w_write_addr(w2_write_addr), .i_w_write_data(w2_write_data),
        .i_w_control_mode(w2_control_mode), .o_w_FIFO_write_ready(w2_fifo_write_ready),
        .o_w_noc_write_commit(w2_write_commit), .o_w_port_conflict(w2_port_conflict),
        .o_c2_valid(c2_s_valid), .o_c2_addr(c2_s_addr), .o_c2_data(c2_s_data),
        .i_c2_ready(c2_s_ready), .i_c2_resp(c2_s_resp),
        .o_busy(bb2_busy), .o_done(bb2_done),
        .o_err_start_busy(bb2_err_start_busy), .o_cycle_cnt(bb2_cycles),
        .o_dbg_data(bb2_dbg_data), .o_dbg_valid(bb2_dbg_valid));

endmodule
