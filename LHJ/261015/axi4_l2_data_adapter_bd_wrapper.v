`timescale 1ns/1ps
// Verilog boundary for Vivado BD Add Module; all implementation stays in .sv.
// Pure one-to-one port wiring: no registers, FIFO, or added clock latency.
module axi4_l2_data_adapter_bd_wrapper #(
    parameter integer DATA_WIDTH     = 64, // supported configurations: 64,128
    parameter integer ADDR_WIDTH     = 40,
    parameter integer ID_WIDTH       = 16,
    parameter integer CH0_ADDR_WIDTH = 15      // L2 ch0 word 주소 폭 (top 에서 계산해 넘김)
)(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK", X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI:ch, ASSOCIATED_RESET aresetn" *)
    input  wire                      aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST", X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire                      aresetn,

    // ---------------- AXI4 slave ----------------
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWID" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI, PROTOCOL AXI4, READ_WRITE_MODE READ_WRITE, MAX_BURST_LENGTH 256, SUPPORTS_NARROW_BURST 0, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1" *)
    input  wire [ID_WIDTH-1:0]       s_axi_awid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *)
    input  wire [ADDR_WIDTH-1:0]     s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWLEN" *)
    input  wire [7:0]                s_axi_awlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWSIZE" *)
    input  wire [2:0]                s_axi_awsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWBURST" *)
    input  wire [1:0]                s_axi_awburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWLOCK" *)
    input  wire                      s_axi_awlock,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWCACHE" *)
    input  wire [3:0]                s_axi_awcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *)
    input  wire [2:0]                s_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWQOS" *)
    input  wire [3:0]                s_axi_awqos,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input  wire                      s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output wire                      s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  wire [DATA_WIDTH-1:0]               s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  wire [DATA_WIDTH/8-1:0]   s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WLAST" *)
    input  wire                      s_axi_wlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  wire                      s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output wire                      s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BID" *)
    output wire [ID_WIDTH-1:0]       s_axi_bid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output wire [1:0]                s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output wire                      s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  wire                      s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARID" *)
    input  wire [ID_WIDTH-1:0]       s_axi_arid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  wire [ADDR_WIDTH-1:0]     s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARLEN" *)
    input  wire [7:0]                s_axi_arlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARSIZE" *)
    input  wire [2:0]                s_axi_arsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARBURST" *)
    input  wire [1:0]                s_axi_arburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARLOCK" *)
    input  wire                      s_axi_arlock,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARCACHE" *)
    input  wire [3:0]                s_axi_arcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
    input  wire [2:0]                s_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARQOS" *)
    input  wire [3:0]                s_axi_arqos,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  wire                      s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output wire                      s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RID" *)
    output wire [ID_WIDTH-1:0]       s_axi_rid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output wire [DATA_WIDTH-1:0]               s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output wire [1:0]                s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RLAST" *)
    output wire                      s_axi_rlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output wire                      s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  wire                      s_axi_rready,

    // ---------------- L2 channel 0 ----------------
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch AWADDR" *)
    (* X_INTERFACE_MODE = "master" *)
    output wire [CH0_ADDR_WIDTH-1:0] ch_awaddr,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch AWLEN" *)
    output wire [7:0]                ch_awlen,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch AWVALID" *)
    output wire                      ch_awvalid,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch AWREADY" *)
    input  wire                      ch_awready,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch WDATA" *)
    output wire [DATA_WIDTH-1:0]               ch_wdata,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch WLAST" *)
    output wire                      ch_wlast,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch WVALID" *)
    output wire                      ch_wvalid,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch WREADY" *)
    input  wire                      ch_wready,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch BVALID" *)
    input  wire                      ch_bvalid,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch BREADY" *)
    output wire                      ch_bready,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch ARADDR" *)
    output wire [CH0_ADDR_WIDTH-1:0] ch_araddr,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch ARLEN" *)
    output wire [7:0]                ch_arlen,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch ARVALID" *)
    output wire                      ch_arvalid,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch ARREADY" *)
    input  wire                      ch_arready,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch RDATA" *)
    input  wire [DATA_WIDTH-1:0]               ch_rdata,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch RLAST" *)
    input  wire                      ch_rlast,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch RVALID" *)
    input  wire                      ch_rvalid,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch RREADY" *)
    output wire                      ch_rready
);

    axi4_l2_data_adapter #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ID_WIDTH(ID_WIDTH),
        .CH0_ADDR_WIDTH(CH0_ADDR_WIDTH)
    ) u_impl (
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
        .ch_rready(ch_rready)
    );
endmodule
