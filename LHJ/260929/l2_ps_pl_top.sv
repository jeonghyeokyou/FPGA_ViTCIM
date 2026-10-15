`timescale 1ns/1ps
// =============================================================================
//  l2_ps_pl_top
//
//  PS(HPM0) / AXI CDMA  --AXI4-->  axi4_l2_ch0_bridge  -->  TOP_L2_cache ch0
//
//  L2 크기는 GROUPS / BLOCKS / ADDRESS_ROW / DATA_WIDTH로 정한다.
//  ch0 주소 폭과 메모리 크기는 여기서 계산해 bridge 로 넘긴다.
//    CH0_ADDR_WIDTH = clog2(GROUPS) + clog2(BLOCKS*ADDRESS_ROW)   (TOP_L2_cache 와 동일한 식)
//    MEM_BYTES      = GROUPS * BLOCKS * ADDRESS_ROW * (DATA_WIDTH/8)
//  기본값 8/16/256 -> CH0_ADDR_WIDTH = 15, MEM_BYTES = 256 KiB
//
//  Vivado Address Editor 의 range 는 MEM_BYTES 와 같게 설정할 것.
//  base 주소는 RTL 과 무관 (Address Editor 에서 자유롭게 배정).
// =============================================================================
module l2_ps_pl_top #(
    parameter integer DATA_WIDTH  = 64, // ch0 and SRAM word width; 64 or 128
    parameter integer ADDR_WIDTH  = 40,
    parameter integer ID_WIDTH    = 16,
    parameter integer GROUPS      = 8,     // TOP_L2_cache 제약: 8 고정
    parameter integer BLOCKS      = 16,    // TOP_L2_cache 제약: 8의 배수, BLOCKS/8 >= 2
    parameter integer ADDRESS_ROW = 256
)(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK",
       X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET aresetn" *)
    input  wire                  aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST",
       X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire                  aresetn,

    input  wire [ID_WIDTH-1:0]   s_axi_awid,
    input  wire [ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire [7:0]            s_axi_awlen,
    input  wire [2:0]            s_axi_awsize,
    input  wire [1:0]            s_axi_awburst,
    input  wire                  s_axi_awlock,
    input  wire [3:0]            s_axi_awcache,
    input  wire [2:0]            s_axi_awprot,
    input  wire [3:0]            s_axi_awqos,
    input  wire                  s_axi_awvalid,
    output wire                  s_axi_awready,
    input  wire [DATA_WIDTH-1:0]           s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                  s_axi_wlast,
    input  wire                  s_axi_wvalid,
    output wire                  s_axi_wready,
    output wire [ID_WIDTH-1:0]   s_axi_bid,
    output wire [1:0]            s_axi_bresp,
    output wire                  s_axi_bvalid,
    input  wire                  s_axi_bready,
    input  wire [ID_WIDTH-1:0]   s_axi_arid,
    input  wire [ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire [7:0]            s_axi_arlen,
    input  wire [2:0]            s_axi_arsize,
    input  wire [1:0]            s_axi_arburst,
    input  wire                  s_axi_arlock,
    input  wire [3:0]            s_axi_arcache,
    input  wire [2:0]            s_axi_arprot,
    input  wire [3:0]            s_axi_arqos,
    input  wire                  s_axi_arvalid,
    output wire                  s_axi_arready,
    output wire [ID_WIDTH-1:0]   s_axi_rid,
    output wire [DATA_WIDTH-1:0]           s_axi_rdata,
    output wire [1:0]            s_axi_rresp,
    output wire                  s_axi_rlast,
    output wire                  s_axi_rvalid,
    input  wire                  s_axi_rready
);

    // ---------------- 크기 계산 ----------------
    localparam integer GRP_BITS       = $clog2(GROUPS);
    localparam integer INGRP_BITS     = $clog2(BLOCKS * ADDRESS_ROW);
    localparam integer CH0_ADDR_WIDTH = GRP_BITS + INGRP_BITS;
    localparam longint MEM_BYTES      = longint'(GROUPS) * BLOCKS * ADDRESS_ROW * (DATA_WIDTH/8);

    // ch0 주소 {group, in-group} 가 선형 주소와 일치하려면 둘 다 2의 거듭제곱이어야 함
    // (아니면 group 사이에 빈 주소가 생겨 burst 가 group 경계를 넘을 때 깨짐)
    generate
        if(DATA_WIDTH!=64 && DATA_WIDTH!=128) begin : g_bad_width
            initial $fatal(1,"DATA_WIDTH must be 64 or 128 for this release");
        end
        if(GROUPS!=8 || BLOCKS<16 || (BLOCKS & (BLOCKS-1))!=0 || ADDRESS_ROW<2 || (ADDRESS_ROW & (ADDRESS_ROW-1))!=0) begin : g_bad_geometry
            initial $fatal(1,"L2 requires GROUPS=8, power-of-two BLOCKS>=16 and power-of-two rows>=2");
        end
        if ((1 << GRP_BITS) != GROUPS)
            $error("GROUPS(%0d) must be a power of 2", GROUPS);
        if ((1 << INGRP_BITS) != BLOCKS * ADDRESS_ROW)
            $error("BLOCKS*ADDRESS_ROW(%0d) must be a power of 2", BLOCKS * ADDRESS_ROW);
        if (CH0_ADDR_WIDTH + $clog2(DATA_WIDTH/8) < 12)
            $error("memory must be >= 4 KiB");
    endgenerate

    // ---------------- bridge ----------------
    wire [CH0_ADDR_WIDTH-1:0] ch_awaddr, ch_araddr;
    wire [7:0]                ch_awlen,  ch_arlen;
    wire [DATA_WIDTH-1:0]               ch_wdata,  ch_rdata;
    wire ch_awvalid, ch_awready, ch_wlast, ch_wvalid, ch_wready, ch_bvalid, ch_bready;
    wire ch_arvalid, ch_arready, ch_rlast, ch_rvalid, ch_rready;

    axi4_l2_ch0_bridge #(
        .DATA_WIDTH     (DATA_WIDTH),
        .ADDR_WIDTH     (ADDR_WIDTH),
        .ID_WIDTH       (ID_WIDTH),
        .CH0_ADDR_WIDTH (CH0_ADDR_WIDTH)
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

    // ---------------- L2 (ch0 만 사용, 나머지 채널은 0 으로 묶음) ----------------
    TOP_L2_cache #(.BANDWIDTH_CHANNEL_0(DATA_WIDTH), .GROUPS(GROUPS), .BLOCKS(BLOCKS), .ADDRESS_ROW(ADDRESS_ROW)) u_l2 (
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

        .i_command('0), .i_command_valid(1'b0), .o_command_ready(),

        .o_busy_channel_1_in(),
        .i_noc_write_ready_channel_1_in(1'b0), .o_noc_write_valid_channel_1_in(),
        .o_noc_write_addr_channel_1_in(), .o_noc_write_data_channel_1_in(),
        .i_noc_write_response_channel_1_in(1'b0),
        .o_noc_read_addr_channel_1_in(), .o_noc_read_valid_channel_1_in(),
        .o_noc_read_data_ready_channel_1_in(), .i_noc_read_ready_channel_1_in(1'b0),
        .i_noc_read_response_channel_1_in(1'b0), .i_noc_read_data_channel_1_in('0),
        .o_noc_control_mode_channel_1_in(),

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

endmodule
