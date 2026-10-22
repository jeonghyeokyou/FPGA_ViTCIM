`timescale 1ns/1ps
// Unified 1MiB system: independent DATA, CMD and BB AXI ports.
// Source hierarchy retained; synthesis may optimize across module boundaries.
// bb256 : all channels 256b. CH1 = blackbox_ip (ch1_in / ch1_wgt), CH2 = blackbox_nl (ch2_in / ch2_wgt),
//         CMD opcodes 1..7 allowed. Top-level ports are unchanged from LHJ/261020.
module l2_system_top #(
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
    input  wire                      s_axil_rready,
input wire [11:0] s_cmd_awaddr,
input wire [2:0] s_cmd_awprot,
input wire  s_cmd_awvalid,
output wire  s_cmd_awready,
input wire [63:0] s_cmd_wdata,
input wire [7:0] s_cmd_wstrb,
input wire  s_cmd_wvalid,
output wire  s_cmd_wready,
output wire [1:0] s_cmd_bresp,
output wire  s_cmd_bvalid,
input wire  s_cmd_bready,
input wire [11:0] s_cmd_araddr,
input wire [2:0] s_cmd_arprot,
input wire  s_cmd_arvalid,
output wire  s_cmd_arready,
output wire [63:0] s_cmd_rdata,
output wire [1:0] s_cmd_rresp,
output wire  s_cmd_rvalid,
input wire  s_cmd_rready
);

    localparam integer BW_CH0         = 64;
    localparam integer BW_CH1_IN      = 256;
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
    wire         command_valid, command_ready;
    wire         bb_start;
    wire         bb_inject;
    wire [10:0]  bb_in_base, bb_out_base;
    wire [11:0]  bb_in_len;
    wire [8:0]   bb_out_len;
    wire [9:0]   bb_w_base;
    wire [10:0]  bb_w_len;
    wire [31:0]  bb_latency;
    wire         gold_we;
    wire [7:0]   gold_addr;
    wire [255:0] gold_wdata;
    wire         bb_busy, bb_done, bb_err_start_busy;
    wire [31:0]  bb_cycles;
    wire [3:0]   channel_busy;
    wire [31:0]  completed_count;
    wire [2:0]   exec_status;
    wire         start_allowed, start_allowed2;
    // CH2 blackbox
    wire         bb2_start, bb2_dbg_req, bb2_dbg_sel;
    wire [10:0]  bb2_dbg_row;
    wire         bb2_inject, bb2_hs, bb2_prec;
    wire [10:0]  bb2_in_base;
    wire [11:0]  bb2_in_len;
    wire [8:0]   bb2_w_base;
    wire [9:0]   bb2_w_len;
    wire [9:0]   bb2_h, bb2_w;
    wire [6:0]   bb2_nb;
    wire [31:0]  bb2_latency;
    wire         gold2_we;
    wire [7:0]   gold2_addr;
    wire         bb2_busy, bb2_done, bb2_err_start_busy, bb2_dbg_valid;
    wire [31:0]  bb2_cycles;
    wire [255:0] bb2_dbg_data;

    axi_lite_bb_ctrl #(.ADDR_W(LITE_ADDR_W), .DW(BW_CH1_IN), .L1_AW(NOC_ADDR_BW), .W_AW(10), .BAW(8),
                       .W2_AW(9)) u_bb_ctrl (
        .clk(aclk), .rstn(aresetn),
        .s_axil_awaddr(s_axil_awaddr), .s_axil_awprot(s_axil_awprot), .s_axil_awvalid(s_axil_awvalid),
        .s_axil_awready(s_axil_awready), .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb),
        .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready), .s_axil_bresp(s_axil_bresp),
        .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready), .s_axil_araddr(s_axil_araddr),
        .s_axil_arprot(s_axil_arprot), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp), .s_axil_rvalid(s_axil_rvalid),
        .s_axil_rready(s_axil_rready),
        .i_start_allowed(start_allowed), .i_start_allowed2(start_allowed2),
        .o_bb_start(bb_start), .o_bb_inject(bb_inject),
        .o_bb_in_base(bb_in_base), .o_bb_in_len(bb_in_len),
        .o_bb_w_base(bb_w_base), .o_bb_w_len(bb_w_len),
        .o_bb_out_base(bb_out_base), .o_bb_out_len(bb_out_len), .o_bb_latency(bb_latency),
        .o_gold_we(gold_we), .o_gold_addr(gold_addr), .o_gold_wdata(gold_wdata),
        .i_bb_busy(bb_busy), .i_bb_done(bb_done),
        .i_bb_err_start_busy(bb_err_start_busy), .i_bb_cycle_cnt(bb_cycles),
        .o_bb2_start(bb2_start), .o_bb2_dbg_req(bb2_dbg_req), .o_bb2_dbg_sel(bb2_dbg_sel),
        .o_bb2_dbg_row(bb2_dbg_row), .o_bb2_inject(bb2_inject), .o_bb2_hs(bb2_hs), .o_bb2_prec(bb2_prec),
        .o_bb2_in_base(bb2_in_base), .o_bb2_in_len(bb2_in_len),
        .o_bb2_w_base(bb2_w_base), .o_bb2_w_len(bb2_w_len),
        .o_bb2_h(bb2_h), .o_bb2_w(bb2_w), .o_bb2_nb(bb2_nb), .o_bb2_latency(bb2_latency),
        .o_gold2_we(gold2_we), .o_gold2_addr(gold2_addr),
        .i_bb2_busy(bb2_busy), .i_bb2_done(bb2_done), .i_bb2_err_start_busy(bb2_err_start_busy),
        .i_bb2_cycle_cnt(bb2_cycles), .i_bb2_dbg_valid(bb2_dbg_valid), .i_bb2_dbg_data(bb2_dbg_data)
    );


 // opcode bits : 1 ch1_in LOAD, 2 ch1_in STORE, 3 ch2_in LOAD, 4 ch2_in STORE,
 //               5 ch1_wgt LOAD, 6 ch1_wgt STORE, 7 ch2_wgt LOAD   (0 = no command)
 axi_lite_l2_cmd_adapter #(.ALLOWED_OPCODES(8'hFE)) u_cmd_adapter (
 .aclk(aclk), .aresetn(aresetn),
 .s_axi_awaddr(s_cmd_awaddr),
 .s_axi_awprot(s_cmd_awprot),
 .s_axi_awvalid(s_cmd_awvalid),
 .s_axi_awready(s_cmd_awready),
 .s_axi_wdata(s_cmd_wdata),
 .s_axi_wstrb(s_cmd_wstrb),
 .s_axi_wvalid(s_cmd_wvalid),
 .s_axi_wready(s_cmd_wready),
 .s_axi_bresp(s_cmd_bresp),
 .s_axi_bvalid(s_cmd_bvalid),
 .s_axi_bready(s_cmd_bready),
 .s_axi_araddr(s_cmd_araddr),
 .s_axi_arprot(s_cmd_arprot),
 .s_axi_arvalid(s_cmd_arvalid),
 .s_axi_arready(s_cmd_arready),
 .s_axi_rdata(s_cmd_rdata),
 .s_axi_rresp(s_cmd_rresp),
 .s_axi_rvalid(s_cmd_rvalid),
 .s_axi_rready(s_cmd_rready),
 .o_command(command), .o_command_valid(command_valid), .i_command_ready(command_ready),
 .i_channel_busy(channel_busy), .i_completed_count(completed_count), .i_exec_status(exec_status));

 l2_noc_bb_core #(.GROUPS(GROUPS),.BLOCKS(BLOCKS),.ADDRESS_ROW(ADDRESS_ROW),.BB_GUARD(BB_GUARD)) u_core (
 .aclk(aclk),.aresetn(aresetn),
 .ch_awaddr(ch_awaddr),
 .ch_awlen(ch_awlen),
 .ch_awvalid(ch_awvalid),
 .ch_awready(ch_awready),
 .ch_wdata(ch_wdata),
 .ch_wlast(ch_wlast),
 .ch_wvalid(ch_wvalid),
 .ch_wready(ch_wready),
 .ch_bvalid(ch_bvalid),
 .ch_bready(ch_bready),
 .ch_araddr(ch_araddr),
 .ch_arlen(ch_arlen),
 .ch_arvalid(ch_arvalid),
 .ch_arready(ch_arready),
 .ch_rdata(ch_rdata),
 .ch_rlast(ch_rlast),
 .ch_rvalid(ch_rvalid),
 .ch_rready(ch_rready),
 .command(command),
 .command_valid(command_valid),
 .command_ready(command_ready),
 .channel_busy(channel_busy),
 .completed_count(completed_count),
 .exec_status(exec_status),
 .start_allowed(start_allowed),
 .start_allowed2(start_allowed2),
 .bb_start(bb_start),
 .bb_inject(bb_inject),
 .bb_in_base(bb_in_base),
 .bb_out_base(bb_out_base),
 .bb_in_len(bb_in_len),
 .bb_out_len(bb_out_len),
 .bb_w_base(bb_w_base),
 .bb_w_len(bb_w_len),
 .bb_latency(bb_latency),
 .gold_we(gold_we),
 .gold_addr(gold_addr),
 .gold_wdata(gold_wdata),
 .bb_busy(bb_busy),
 .bb_done(bb_done),
 .bb_err_start_busy(bb_err_start_busy),
 .bb_cycles(bb_cycles),
 .bb2_start(bb2_start), .bb2_dbg_req(bb2_dbg_req), .bb2_dbg_sel(bb2_dbg_sel), .bb2_dbg_row(bb2_dbg_row),
 .bb2_inject(bb2_inject), .bb2_hs(bb2_hs), .bb2_prec(bb2_prec),
 .bb2_in_base(bb2_in_base), .bb2_in_len(bb2_in_len), .bb2_w_base(bb2_w_base), .bb2_w_len(bb2_w_len),
 .bb2_h(bb2_h), .bb2_w(bb2_w), .bb2_nb(bb2_nb), .bb2_latency(bb2_latency),
 .gold2_we(gold2_we), .gold2_addr(gold2_addr),
 .bb2_busy(bb2_busy), .bb2_done(bb2_done), .bb2_err_start_busy(bb2_err_start_busy),
 .bb2_dbg_valid(bb2_dbg_valid), .bb2_cycles(bb2_cycles), .bb2_dbg_data(bb2_dbg_data)
 );
endmodule
