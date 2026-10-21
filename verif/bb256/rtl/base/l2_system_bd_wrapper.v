`timescale 1ns/1ps
// Verilog BD boundary: wiring and Vivado interface metadata only.
module l2_system_bd_wrapper #(
    parameter integer GROUPS         = 8,
    parameter integer BLOCKS         = 16,
    parameter integer ADDRESS_ROW    = 1024,
    parameter integer AXI_ADDR_WIDTH = 40,
    parameter integer AXI_ID_WIDTH   = 16,
    parameter integer LITE_ADDR_W    = 12,
    parameter integer BB_GUARD       = 2
)(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK",
       X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI_DATA:S_AXI_BB:S_AXI_CMD, ASSOCIATED_RESET aresetn" *)
    input  wire aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST",
       X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire aresetn,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA AWID" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI_DATA, PROTOCOL AXI4, DATA_WIDTH 64, READ_WRITE_MODE READ_WRITE, SUPPORTS_NARROW_BURST 0, MAX_BURST_LENGTH 256, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1" *)
    input  wire [AXI_ID_WIDTH-1:0]     s_axi_awid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA AWADDR" *)
    input  wire [AXI_ADDR_WIDTH-1:0]   s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA AWLEN" *)
    input  wire [7:0]                  s_axi_awlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA AWSIZE" *)
    input  wire [2:0]                  s_axi_awsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA AWBURST" *)
    input  wire [1:0]                  s_axi_awburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA AWLOCK" *)
    input  wire                        s_axi_awlock,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA AWCACHE" *)
    input  wire [3:0]                  s_axi_awcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA AWPROT" *)
    input  wire [2:0]                  s_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA AWQOS" *)
    input  wire [3:0]                  s_axi_awqos,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA AWVALID" *)
    input  wire                        s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA AWREADY" *)
    output wire                        s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA WDATA" *)
    input  wire [63:0]                 s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA WSTRB" *)
    input  wire [7:0]                  s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA WLAST" *)
    input  wire                        s_axi_wlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA WVALID" *)
    input  wire                        s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA WREADY" *)
    output wire                        s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA BID" *)
    output wire [AXI_ID_WIDTH-1:0]     s_axi_bid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA BRESP" *)
    output wire [1:0]                  s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA BVALID" *)
    output wire                        s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA BREADY" *)
    input  wire                        s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA ARID" *)
    input  wire [AXI_ID_WIDTH-1:0]     s_axi_arid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA ARADDR" *)
    input  wire [AXI_ADDR_WIDTH-1:0]   s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA ARLEN" *)
    input  wire [7:0]                  s_axi_arlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA ARSIZE" *)
    input  wire [2:0]                  s_axi_arsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA ARBURST" *)
    input  wire [1:0]                  s_axi_arburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA ARLOCK" *)
    input  wire                        s_axi_arlock,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA ARCACHE" *)
    input  wire [3:0]                  s_axi_arcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA ARPROT" *)
    input  wire [2:0]                  s_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA ARQOS" *)
    input  wire [3:0]                  s_axi_arqos,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA ARVALID" *)
    input  wire                        s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA ARREADY" *)
    output wire                        s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA RID" *)
    output wire [AXI_ID_WIDTH-1:0]     s_axi_rid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA RDATA" *)
    output wire [63:0]                 s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA RRESP" *)
    output wire [1:0]                  s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA RLAST" *)
    output wire                        s_axi_rlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA RVALID" *)
    output wire                        s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_DATA RREADY" *)
    input  wire                        s_axi_rready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BB AWADDR" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI_BB, PROTOCOL AXI4LITE, DATA_WIDTH 32, READ_WRITE_MODE READ_WRITE, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1" *)
    input  wire [LITE_ADDR_W-1:0]      s_axil_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BB AWPROT" *)
    input  wire [2:0]                  s_axil_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BB AWVALID" *)
    input  wire                        s_axil_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BB AWREADY" *)
    output wire                        s_axil_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BB WDATA" *)
    input  wire [31:0]                 s_axil_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BB WSTRB" *)
    input  wire [3:0]                  s_axil_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BB WVALID" *)
    input  wire                        s_axil_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BB WREADY" *)
    output wire                        s_axil_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BB BRESP" *)
    output wire [1:0]                  s_axil_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BB BVALID" *)
    output wire                        s_axil_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BB BREADY" *)
    input  wire                        s_axil_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BB ARADDR" *)
    input  wire [LITE_ADDR_W-1:0]      s_axil_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BB ARPROT" *)
    input  wire [2:0]                  s_axil_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BB ARVALID" *)
    input  wire                        s_axil_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BB ARREADY" *)
    output wire                        s_axil_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BB RDATA" *)
    output wire [31:0]                 s_axil_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BB RRESP" *)
    output wire [1:0]                  s_axil_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BB RVALID" *)
    output wire                        s_axil_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BB RREADY" *)
    input  wire                        s_axil_rready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CMD AWADDR" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI_CMD, PROTOCOL AXI4LITE, DATA_WIDTH 64, ADDR_WIDTH 12" *)
    input wire [11:0] s_cmd_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CMD AWPROT" *)
    input wire [2:0] s_cmd_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CMD AWVALID" *)
    input wire  s_cmd_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CMD AWREADY" *)
    output wire  s_cmd_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CMD WDATA" *)
    input wire [63:0] s_cmd_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CMD WSTRB" *)
    input wire [7:0] s_cmd_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CMD WVALID" *)
    input wire  s_cmd_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CMD WREADY" *)
    output wire  s_cmd_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CMD BRESP" *)
    output wire [1:0] s_cmd_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CMD BVALID" *)
    output wire  s_cmd_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CMD BREADY" *)
    input wire  s_cmd_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CMD ARADDR" *)
    input wire [11:0] s_cmd_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CMD ARPROT" *)
    input wire [2:0] s_cmd_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CMD ARVALID" *)
    input wire  s_cmd_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CMD ARREADY" *)
    output wire  s_cmd_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CMD RDATA" *)
    output wire [63:0] s_cmd_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CMD RRESP" *)
    output wire [1:0] s_cmd_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CMD RVALID" *)
    output wire  s_cmd_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_CMD RREADY" *)
    input wire  s_cmd_rready
);

    l2_system_top #(
        .GROUPS(GROUPS), .BLOCKS(BLOCKS), .ADDRESS_ROW(ADDRESS_ROW),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH), .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .LITE_ADDR_W(LITE_ADDR_W), .BB_GUARD(BB_GUARD)
    ) u_top (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axi_awid(s_axi_awid),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awlen(s_axi_awlen),
        .s_axi_awsize(s_axi_awsize),
        .s_axi_awburst(s_axi_awburst),
        .s_axi_awlock(s_axi_awlock),
        .s_axi_awcache(s_axi_awcache),
        .s_axi_awprot(s_axi_awprot),
        .s_axi_awqos(s_axi_awqos),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wlast(s_axi_wlast),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bid(s_axi_bid),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_arid(s_axi_arid),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arlen(s_axi_arlen),
        .s_axi_arsize(s_axi_arsize),
        .s_axi_arburst(s_axi_arburst),
        .s_axi_arlock(s_axi_arlock),
        .s_axi_arcache(s_axi_arcache),
        .s_axi_arprot(s_axi_arprot),
        .s_axi_arqos(s_axi_arqos),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rid(s_axi_rid),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rlast(s_axi_rlast),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .s_axil_awaddr(s_axil_awaddr),
        .s_axil_awprot(s_axil_awprot),
        .s_axil_awvalid(s_axil_awvalid),
        .s_axil_awready(s_axil_awready),
        .s_axil_wdata(s_axil_wdata),
        .s_axil_wstrb(s_axil_wstrb),
        .s_axil_wvalid(s_axil_wvalid),
        .s_axil_wready(s_axil_wready),
        .s_axil_bresp(s_axil_bresp),
        .s_axil_bvalid(s_axil_bvalid),
        .s_axil_bready(s_axil_bready),
        .s_axil_araddr(s_axil_araddr),
        .s_axil_arprot(s_axil_arprot),
        .s_axil_arvalid(s_axil_arvalid),
        .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata),
        .s_axil_rresp(s_axil_rresp),
        .s_axil_rvalid(s_axil_rvalid),
        .s_axil_rready(s_axil_rready),
 .s_cmd_awaddr(s_cmd_awaddr),
 .s_cmd_awprot(s_cmd_awprot),
 .s_cmd_awvalid(s_cmd_awvalid),
 .s_cmd_awready(s_cmd_awready),
 .s_cmd_wdata(s_cmd_wdata),
 .s_cmd_wstrb(s_cmd_wstrb),
 .s_cmd_wvalid(s_cmd_wvalid),
 .s_cmd_wready(s_cmd_wready),
 .s_cmd_bresp(s_cmd_bresp),
 .s_cmd_bvalid(s_cmd_bvalid),
 .s_cmd_bready(s_cmd_bready),
 .s_cmd_araddr(s_cmd_araddr),
 .s_cmd_arprot(s_cmd_arprot),
 .s_cmd_arvalid(s_cmd_arvalid),
 .s_cmd_arready(s_cmd_arready),
 .s_cmd_rdata(s_cmd_rdata),
 .s_cmd_rresp(s_cmd_rresp),
 .s_cmd_rvalid(s_cmd_rvalid),
 .s_cmd_rready(s_cmd_rready)
);

endmodule
