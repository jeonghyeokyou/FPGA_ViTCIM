`timescale 1ns/1ps
// Unified 1MiB system: independent DATA, CMD and BB AXI ports.
// Source hierarchy retained; synthesis may optimize across module boundaries.
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
    wire         command_valid, command_ready;
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

    axi_lite_bb_ctrl #(.ADDR_W(LITE_ADDR_W), .DW(BW_CH1_IN), .L1_AW(NOC_ADDR_BW), .BAW(8)) u_bb_ctrl (
        .clk(aclk), .rstn(aresetn),
        .s_axil_awaddr(s_axil_awaddr), .s_axil_awprot(s_axil_awprot), .s_axil_awvalid(s_axil_awvalid),
        .s_axil_awready(s_axil_awready), .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb),
        .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready), .s_axil_bresp(s_axil_bresp),
        .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready), .s_axil_araddr(s_axil_araddr),
        .s_axil_arprot(s_axil_arprot), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp), .s_axil_rvalid(s_axil_rvalid),
        .s_axil_rready(s_axil_rready),
        .i_start_allowed(start_allowed),
        .o_bb_start(bb_start), .o_bb_inject(bb_inject),
        .o_bb_in_base(bb_in_base), .o_bb_in_len(bb_in_len),
        .o_bb_out_base(bb_out_base), .o_bb_out_len(bb_out_len), .o_bb_latency(bb_latency),
        .o_bram_we(bram_we), .o_bram_sel(bram_sel), .o_bram_addr(bram_addr), .o_bram_wdata(bram_wdata),
        .i_bb_busy(bb_busy), .i_bb_done(bb_done), .i_bb_first_mm_valid(bb_first_valid),
        .i_bb_err_start_busy(bb_err_start_busy), .i_bb_mismatch_cnt(bb_mm_cnt),
        .i_bb_first_mm_idx(bb_first_idx), .i_bb_first_mm_got(bb_first_got),
        .i_bb_first_mm_exp(bb_first_exp), .i_bb_cycle_cnt(bb_cycles)
    );


 wire [3:0] channel_busy;
 wire [31:0] completed_count;
 wire [2:0] exec_status;
 wire start_allowed;
 axi_lite_l2_cmd_adapter #(.ALLOWED_OPCODES(8'h06)) u_cmd_adapter (
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
 .bb_start(bb_start),
 .bb_inject(bb_inject),
 .bb_in_base(bb_in_base),
 .bb_out_base(bb_out_base),
 .bb_in_len(bb_in_len),
 .bb_out_len(bb_out_len),
 .bb_latency(bb_latency),
 .bram_we(bram_we),
 .bram_sel(bram_sel),
 .bram_addr(bram_addr),
 .bram_wdata(bram_wdata),
 .bb_busy(bb_busy),
 .bb_done(bb_done),
 .bb_first_valid(bb_first_valid),
 .bb_err_start_busy(bb_err_start_busy),
 .bb_mm_cnt(bb_mm_cnt),
 .bb_first_idx(bb_first_idx),
 .bb_first_got(bb_first_got),
 .bb_first_exp(bb_first_exp),
 .bb_cycles(bb_cycles)
 );
endmodule
