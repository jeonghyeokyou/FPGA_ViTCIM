`timescale 1ns/1ps
// Verilog boundary for Vivado BD Add Module; all implementation stays in .sv.
// Pure one-to-one port wiring: no registers, FIFO, or added clock latency.
module l2_bd_wrapper #(
    parameter integer DATA_WIDTH = 64,
    parameter integer GROUPS = 8,
    parameter integer BLOCKS = 16,
    parameter integer ADDRESS_ROW = 256
)(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK",
       X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF ch, ASSOCIATED_RESET aresetn" *)
    input wire aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST",
       X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input wire aresetn,
    input wire [63:0] i_command,
    input wire i_command_valid,
    output wire o_command_ready,
    output wire [3:0] o_channel_busy,
    // Native L2 ch0 (same signal names as the data adapter):

    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch AWADDR" *)
    (* X_INTERFACE_MODE = "slave" *)
    input wire [$clog2(GROUPS)+$clog2(BLOCKS*ADDRESS_ROW)-1:0] ch_awaddr,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch AWLEN" *)
    input wire [7:0]                ch_awlen,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch AWVALID" *)
    input wire                      ch_awvalid,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch AWREADY" *)
    output  wire                      ch_awready,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch WDATA" *)
    input wire [DATA_WIDTH-1:0]               ch_wdata,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch WLAST" *)
    input wire                      ch_wlast,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch WVALID" *)
    input wire                      ch_wvalid,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch WREADY" *)
    output  wire                      ch_wready,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch BVALID" *)
    output  wire                      ch_bvalid,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch BREADY" *)
    input wire                      ch_bready,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch ARADDR" *)
    input wire [$clog2(GROUPS)+$clog2(BLOCKS*ADDRESS_ROW)-1:0] ch_araddr,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch ARLEN" *)
    input wire [7:0]                ch_arlen,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch ARVALID" *)
    input wire                      ch_arvalid,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch ARREADY" *)
    output  wire                      ch_arready,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch RDATA" *)
    output  wire [DATA_WIDTH-1:0]               ch_rdata,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch RLAST" *)
    output  wire                      ch_rlast,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch RVALID" *)
    output  wire                      ch_rvalid,
    (* X_INTERFACE_INFO = "lab.local:interface:l2_ch0:1.0 ch RREADY" *)
    input wire                      ch_rready

);

    l2_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .GROUPS(GROUPS),
        .BLOCKS(BLOCKS),
        .ADDRESS_ROW(ADDRESS_ROW)
    ) u_impl (
        .aclk(aclk),
        .aresetn(aresetn),
        .i_command(i_command),
        .i_command_valid(i_command_valid),
        .o_command_ready(o_command_ready),
        .o_channel_busy(o_channel_busy),
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
