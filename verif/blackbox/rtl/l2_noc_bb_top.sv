`timescale 1ns/1ps
// =============================================================================
//  l2_noc_bb_top  -  Blackbox 시스템 top (Phase 3)
//
//   S_AXI (AXI4, 64b)  ─► axi4_l2_ch0_bridge (LHJ/, 참조만) ─► TOP_L2_cache ch0
//   S_AXI_LITE (32b)   ─► axi_lite_ctrl ─► i_command / Blackbox 레지스터 / BRAM 창
//   TOP_L2_cache ch1_in ─► noc_ch1_in_adapter ─► FIFO_intf_bb ─► l1_sram
//                                                   ▲ l1_port_mux
//                                             blackbox_pe (pe_busy)
//
//  - 클럭 1개(aclk), 리셋 active-low(aresetn) 1개. CDC 없음.
//  - L2 크기: GROUPS/BLOCKS/ADDRESS_ROW (기본 8/16/1024 = 1 MiB).
//    ch0 워드 = 64b 이므로 S_AXI 데이터 폭은 64 고정 (ch1_in 512b = 8 lane 매핑 때문에).
//  - S_AXI 주소 창 = MEM_BYTES (1 MiB). Vivado Address Editor range 를 같게 둘 것.
//  - ch1_wgt / ch2_* 는 tie-off (범위 밖, 12절 ③④).
//  - ch0 <-> ch1_in 배치: FINDING_l2_ch0_ch1_layout.md
// =============================================================================
module l2_noc_bb_top #(
    parameter integer GROUPS         = 8,
    parameter integer BLOCKS         = 16,
    parameter integer ADDRESS_ROW    = 1024,
    parameter integer AXI_ADDR_WIDTH = 40,
    parameter integer AXI_ID_WIDTH   = 16,
    parameter integer LITE_ADDR_W    = 12,
    parameter integer BB_GUARD       = 2
)(
    input  wire                      aclk,
    input  wire                      aresetn,

    // ---------------- S_AXI : AXI4 slave -> L2 ch0 ----------------
    input  wire [AXI_ID_WIDTH-1:0]   s_axi_awid,
    input  wire [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire [7:0]                s_axi_awlen,
    input  wire [2:0]                s_axi_awsize,
    input  wire [1:0]                s_axi_awburst,
    input  wire                      s_axi_awlock,
    input  wire [3:0]                s_axi_awcache,
    input  wire [2:0]                s_axi_awprot,
    input  wire [3:0]                s_axi_awqos,
    input  wire                      s_axi_awvalid,
    output wire                      s_axi_awready,
    input  wire [63:0]               s_axi_wdata,
    input  wire [7:0]                s_axi_wstrb,
    input  wire                      s_axi_wlast,
    input  wire                      s_axi_wvalid,
    output wire                      s_axi_wready,
    output wire [AXI_ID_WIDTH-1:0]   s_axi_bid,
    output wire [1:0]                s_axi_bresp,
    output wire                      s_axi_bvalid,
    input  wire                      s_axi_bready,
    input  wire [AXI_ID_WIDTH-1:0]   s_axi_arid,
    input  wire [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire [7:0]                s_axi_arlen,
    input  wire [2:0]                s_axi_arsize,
    input  wire [1:0]                s_axi_arburst,
    input  wire                      s_axi_arlock,
    input  wire [3:0]                s_axi_arcache,
    input  wire [2:0]                s_axi_arprot,
    input  wire [3:0]                s_axi_arqos,
    input  wire                      s_axi_arvalid,
    output wire                      s_axi_arready,
    output wire [AXI_ID_WIDTH-1:0]   s_axi_rid,
    output wire [63:0]               s_axi_rdata,
    output wire [1:0]                s_axi_rresp,
    output wire                      s_axi_rlast,
    output wire                      s_axi_rvalid,
    input  wire                      s_axi_rready,

    // ---------------- S_AXI_LITE : control ----------------
    input  wire [LITE_ADDR_W-1:0]    s_axil_awaddr,
    input  wire [2:0]                s_axil_awprot,
    input  wire                      s_axil_awvalid,
    output wire                      s_axil_awready,
    input  wire [31:0]               s_axil_wdata,
    input  wire [3:0]                s_axil_wstrb,
    input  wire                      s_axil_wvalid,
    output wire                      s_axil_wready,
    output wire [1:0]                s_axil_bresp,
    output wire                      s_axil_bvalid,
    input  wire                      s_axil_bready,
    input  wire [LITE_ADDR_W-1:0]    s_axil_araddr,
    input  wire [2:0]                s_axil_arprot,
    input  wire                      s_axil_arvalid,
    output wire                      s_axil_arready,
    output wire [31:0]               s_axil_rdata,
    output wire [1:0]                s_axil_rresp,
    output wire                      s_axil_rvalid,
    input  wire                      s_axil_rready
);

    localparam integer BW_CH0         = 64;
    localparam integer BW_CH1_IN      = 512;
    localparam integer CH0_ADDR_WIDTH = $clog2(GROUPS) + $clog2(BLOCKS * ADDRESS_ROW);
    localparam integer DA_CH1_IN      = 19;
    localparam integer NOC_ADDR_DEPTH = 2048;
    localparam integer NOC_ADDR_BW    = 11;

    // ---------------------------------------------------------------------
    //  AXI4 -> ch0 bridge (LHJ, unmodified)
    // ---------------------------------------------------------------------
    wire [CH0_ADDR_WIDTH-1:0] ch_awaddr, ch_araddr;
    wire [7:0]                ch_awlen,  ch_arlen;
    wire [BW_CH0-1:0]         ch_wdata,  ch_rdata;
    wire ch_awvalid, ch_awready, ch_wlast, ch_wvalid, ch_wready, ch_bvalid, ch_bready;
    wire ch_arvalid, ch_arready, ch_rlast, ch_rvalid, ch_rready;

    axi4_l2_ch0_bridge #(
        .DATA_WIDTH(BW_CH0), .ADDR_WIDTH(AXI_ADDR_WIDTH), .ID_WIDTH(AXI_ID_WIDTH),
        .CH0_ADDR_WIDTH(CH0_ADDR_WIDTH)
    ) u_bridge (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awid(s_axi_awid),       .s_axi_awaddr(s_axi_awaddr),   .s_axi_awlen(s_axi_awlen),
        .s_axi_awsize(s_axi_awsize),   .s_axi_awburst(s_axi_awburst), .s_axi_awlock(s_axi_awlock),
        .s_axi_awcache(s_axi_awcache), .s_axi_awprot(s_axi_awprot),   .s_axi_awqos(s_axi_awqos),
        .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),     .s_axi_wstrb(s_axi_wstrb),     .s_axi_wlast(s_axi_wlast),
        .s_axi_wvalid(s_axi_wvalid),   .s_axi_wready(s_axi_wready),
        .s_axi_bid(s_axi_bid),         .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),   .s_axi_bready(s_axi_bready),
        .s_axi_arid(s_axi_arid),       .s_axi_araddr(s_axi_araddr),   .s_axi_arlen(s_axi_arlen),
        .s_axi_arsize(s_axi_arsize),   .s_axi_arburst(s_axi_arburst), .s_axi_arlock(s_axi_arlock),
        .s_axi_arcache(s_axi_arcache), .s_axi_arprot(s_axi_arprot),   .s_axi_arqos(s_axi_arqos),
        .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rid(s_axi_rid),         .s_axi_rdata(s_axi_rdata),     .s_axi_rresp(s_axi_rresp),
        .s_axi_rlast(s_axi_rlast),     .s_axi_rvalid(s_axi_rvalid),   .s_axi_rready(s_axi_rready),
        .ch_awaddr(ch_awaddr), .ch_awlen(ch_awlen), .ch_awvalid(ch_awvalid), .ch_awready(ch_awready),
        .ch_wdata(ch_wdata),   .ch_wlast(ch_wlast), .ch_wvalid(ch_wvalid),   .ch_wready(ch_wready),
        .ch_bvalid(ch_bvalid), .ch_bready(ch_bready),
        .ch_araddr(ch_araddr), .ch_arlen(ch_arlen), .ch_arvalid(ch_arvalid), .ch_arready(ch_arready),
        .ch_rdata(ch_rdata),   .ch_rlast(ch_rlast), .ch_rvalid(ch_rvalid),   .ch_rready(ch_rready)
    );

    // ---------------------------------------------------------------------
    //  AXI-Lite control
    // ---------------------------------------------------------------------
    wire [63:0]  command;
    wire         command_valid, command_ready, busy_ch1_in;
    wire         bb_start;
    wire [1:0]   bb_inject;
    wire [10:0]  bb_in_base, bb_out_base;
    wire [8:0]   bb_in_len, bb_out_len;
    wire [31:0]  bb_latency;
    wire         bram_we, bram_sel;
    wire [7:0]   bram_addr;
    wire [511:0] bram_wdata;
    wire         bb_busy, bb_done, bb_first_valid, bb_err_start_busy;
    wire [15:0]  bb_mm_cnt, bb_first_idx;
    wire [31:0]  bb_first_got, bb_first_exp, bb_cycles;

    axi_lite_ctrl #(.ADDR_W(LITE_ADDR_W), .DW(BW_CH1_IN), .L1_AW(NOC_ADDR_BW), .BAW(8)) u_ctrl (
        .clk(aclk), .rstn(aresetn),
        .s_axil_awaddr(s_axil_awaddr), .s_axil_awprot(s_axil_awprot), .s_axil_awvalid(s_axil_awvalid),
        .s_axil_awready(s_axil_awready), .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb),
        .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready), .s_axil_bresp(s_axil_bresp),
        .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready), .s_axil_araddr(s_axil_araddr),
        .s_axil_arprot(s_axil_arprot), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp), .s_axil_rvalid(s_axil_rvalid),
        .s_axil_rready(s_axil_rready),
        .o_command(command), .o_command_valid(command_valid), .i_command_ready(command_ready),
        .i_busy_ch1_in(busy_ch1_in),
        .o_bb_start(bb_start), .o_bb_inject(bb_inject),
        .o_bb_in_base(bb_in_base), .o_bb_in_len(bb_in_len),
        .o_bb_out_base(bb_out_base), .o_bb_out_len(bb_out_len), .o_bb_latency(bb_latency),
        .o_bram_we(bram_we), .o_bram_sel(bram_sel), .o_bram_addr(bram_addr), .o_bram_wdata(bram_wdata),
        .i_bb_busy(bb_busy), .i_bb_done(bb_done), .i_bb_first_mm_valid(bb_first_valid),
        .i_bb_err_start_busy(bb_err_start_busy), .i_bb_mismatch_cnt(bb_mm_cnt),
        .i_bb_first_mm_idx(bb_first_idx), .i_bb_first_mm_got(bb_first_got),
        .i_bb_first_mm_exp(bb_first_exp), .i_bb_cycle_cnt(bb_cycles)
    );

    // ---------------------------------------------------------------------
    //  L2
    // ---------------------------------------------------------------------
    wire                 l2_w_ready, l2_w_valid, l2_w_resp;
    wire [DA_CH1_IN-1:0] l2_w_addr, l2_r_addr;
    wire [BW_CH1_IN-1:0] l2_w_data, l2_r_data;
    wire                 l2_r_valid, l2_r_data_ready, l2_r_ready, l2_r_resp, l2_ctrl_mode;

    TOP_L2_cache #(
        .GROUPS(GROUPS), .BLOCKS(BLOCKS), .ADDRESS_ROW(ADDRESS_ROW),
        .BANDWIDTH_CHANNEL_0(BW_CH0), .BANDWIDTH_CHANNEL_1_IN(BW_CH1_IN)
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

        .i_command(command), .i_command_valid(command_valid), .o_command_ready(command_ready),

        .o_busy_channel_1_in(busy_ch1_in),
        .i_noc_write_ready_channel_1_in(l2_w_ready), .o_noc_write_valid_channel_1_in(l2_w_valid),
        .o_noc_write_addr_channel_1_in(l2_w_addr), .o_noc_write_data_channel_1_in(l2_w_data),
        .i_noc_write_response_channel_1_in(l2_w_resp),
        .o_noc_read_addr_channel_1_in(l2_r_addr), .o_noc_read_valid_channel_1_in(l2_r_valid),
        .o_noc_read_data_ready_channel_1_in(l2_r_data_ready), .i_noc_read_ready_channel_1_in(l2_r_ready),
        .i_noc_read_response_channel_1_in(l2_r_resp), .i_noc_read_data_channel_1_in(l2_r_data),
        .o_noc_control_mode_channel_1_in(l2_ctrl_mode),

        .o_busy_channel_2_in(),
        .i_noc_write_ready_channel_2_in(1'b0), .o_noc_write_valid_channel_2_in(),
        .o_noc_write_addr_channel_2_in(), .o_noc_write_data_channel_2_in(),
        .i_noc_write_response_channel_2_in(1'b0),
        .o_noc_read_ready_channel_2_in(), .i_noc_read_valid_channel_2_in(1'b0),
        .i_noc_read_addr_channel_2_in('0), .i_noc_read_data_channel_2_in('0),
        .o_noc_read_response_channel_2_in(), .o_noc_control_mode_channel_2_in(),

        .o_busy_channel_1_wgt(),
        .i_noc_write_ready_channel_1_wgt(1'b0), .o_noc_write_valid_channel_1_wgt(),
        .o_noc_write_addr_channel_1_wgt(), .o_noc_write_data_channel_1_wgt(),
        .i_noc_write_response_channel_1_wgt(1'b0),
        .o_noc_read_addr_channel_1_wgt(), .o_noc_read_valid_channel_1_wgt(),
        .o_noc_read_data_ready_channel_1_wgt(), .i_noc_read_ready_channel_1_wgt(1'b0),
        .i_noc_read_response_channel_1_wgt(1'b0), .i_noc_read_data_channel_1_wgt('0),
        .o_noc_control_mode_channel_1_wgt(),

        .o_busy_channel_2_wgt(),
        .i_noc_write_ready_channel_2_wgt(1'b0), .o_noc_write_valid_channel_2_wgt(),
        .o_noc_write_addr_channel_2_wgt(), .o_noc_write_data_channel_2_wgt(),
        .i_noc_write_response_channel_2_wgt(1'b0), .o_noc_control_mode_channel_2_wgt()
    );

    // ---------------------------------------------------------------------
    //  ch1_in : adapter -> FIFO_intf_bb <- blackbox_pe
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

    FIFO_intf_bb #(.ADDR_DEPTH(NOC_ADDR_DEPTH), .DATA_WIDTH(BW_CH1_IN), .MEMORY_BITWIDTH(128),
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
        .i_pe_din(pe_din), .o_pe_dout(pe_dout));

    blackbox_pe #(.DW(BW_CH1_IN), .L1_AW(NOC_ADDR_BW), .BRAM_DEPTH(256), .GUARD(BB_GUARD)) u_bb (
        .clk(aclk), .rstn(aresetn),
        .i_start(bb_start), .i_noc_busy(busy_ch1_in),
        .i_in_base(bb_in_base), .i_in_len(bb_in_len), .i_out_base(bb_out_base), .i_out_len(bb_out_len),
        .i_latency(bb_latency), .i_inject(bb_inject),
        .i_bram_we(bram_we), .i_bram_sel(bram_sel), .i_bram_addr(bram_addr), .i_bram_wdata(bram_wdata),
        .o_pe_busy(pe_busy), .o_ceb(pe_ceb), .o_web(pe_web), .o_addr(pe_addr), .o_din(pe_din), .i_dout(pe_dout),
        .o_busy(bb_busy), .o_done(bb_done),
        .o_mismatch_cnt(bb_mm_cnt), .o_first_mm_idx(bb_first_idx), .o_first_mm_valid(bb_first_valid),
        .o_first_mm_got(bb_first_got), .o_first_mm_exp(bb_first_exp),
        .o_err_start_busy(bb_err_start_busy), .o_cycle_cnt(bb_cycles));

endmodule
