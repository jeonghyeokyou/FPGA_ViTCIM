`timescale 1ns/1ps
// L2-only module reference. The data and command adapters are separate BD cells.
// Native ch0 is a word-address interface, NOT a complete AXI4 interface.
// Default geometry: 8*16*256 64-bit words = 256 KiB, ch0 address width = 15.
// NoC/L1 inputs remain tied off, as in the previous integration version.
// Command acceptance is available; complete NoC/L1 execution is not supported.
module l2_top #(
    parameter integer DATA_WIDTH = 64,
    parameter integer GROUPS = 8,
    parameter integer BLOCKS = 16,
    parameter integer ADDRESS_ROW = 256
)(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK",
       X_INTERFACE_PARAMETER = "ASSOCIATED_RESET aresetn" *)
    input wire aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST",
       X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input wire aresetn,
    input wire [63:0] i_command,
    input wire i_command_valid,
    output wire o_command_ready,
    output wire [3:0] o_channel_busy,
    // Native L2 ch0 (same signal names as the data adapter):

    input wire [$clog2(GROUPS)+$clog2(BLOCKS*ADDRESS_ROW)-1:0] ch_awaddr,
    input wire [7:0]                ch_awlen,
    input wire                      ch_awvalid,
    output  wire                      ch_awready,
    input wire [DATA_WIDTH-1:0]               ch_wdata,
    input wire                      ch_wlast,
    input wire                      ch_wvalid,
    output  wire                      ch_wready,
    output  wire                      ch_bvalid,
    input wire                      ch_bready,
    input wire [$clog2(GROUPS)+$clog2(BLOCKS*ADDRESS_ROW)-1:0] ch_araddr,
    input wire [7:0]                ch_arlen,
    input wire                      ch_arvalid,
    output  wire                      ch_arready,
    output  wire [DATA_WIDTH-1:0]               ch_rdata,
    output  wire                      ch_rlast,
    output  wire                      ch_rvalid,
    input wire                      ch_rready

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

        .i_command(i_command), .i_command_valid(i_command_valid), .o_command_ready(o_command_ready),

        .o_busy_channel_1_in(o_channel_busy[0]),
        .i_noc_write_ready_channel_1_in(1'b0), .o_noc_write_valid_channel_1_in(),
        .o_noc_write_addr_channel_1_in(), .o_noc_write_data_channel_1_in(),
        .i_noc_write_response_channel_1_in(1'b0),
        .o_noc_read_addr_channel_1_in(), .o_noc_read_valid_channel_1_in(),
        .o_noc_read_data_ready_channel_1_in(), .i_noc_read_ready_channel_1_in(1'b0),
        .i_noc_read_response_channel_1_in(1'b0), .i_noc_read_data_channel_1_in('0),
        .o_noc_control_mode_channel_1_in(),

        .o_busy_channel_2_in(o_channel_busy[1]),
        .i_noc_write_ready_channel_2_in(1'b0), .o_noc_write_valid_channel_2_in(),
        .o_noc_write_addr_channel_2_in(), .o_noc_write_data_channel_2_in(),
        .i_noc_write_response_channel_2_in(1'b0),
        .o_noc_read_ready_channel_2_in(), .i_noc_read_valid_channel_2_in(1'b0),
        .i_noc_read_addr_channel_2_in('0), .i_noc_read_data_channel_2_in('0),
        .o_noc_read_response_channel_2_in(), .o_noc_control_mode_channel_2_in(),

        .o_busy_channel_1_wgt(o_channel_busy[2]),
        .i_noc_write_ready_channel_1_wgt(1'b0), .o_noc_write_valid_channel_1_wgt(),
        .o_noc_write_addr_channel_1_wgt(), .o_noc_write_data_channel_1_wgt(),
        .i_noc_write_response_channel_1_wgt(1'b0),
        .o_noc_read_addr_channel_1_wgt(), .o_noc_read_valid_channel_1_wgt(),
        .o_noc_read_data_ready_channel_1_wgt(), .i_noc_read_ready_channel_1_wgt(1'b0),
        .i_noc_read_response_channel_1_wgt(1'b0), .i_noc_read_data_channel_1_wgt('0),
        .o_noc_control_mode_channel_1_wgt(),

        .o_busy_channel_2_wgt(o_channel_busy[3]),
        .i_noc_write_ready_channel_2_wgt(1'b0), .o_noc_write_valid_channel_2_wgt(),
        .o_noc_write_addr_channel_2_wgt(), .o_noc_write_data_channel_2_wgt(),
        .i_noc_write_response_channel_2_wgt(1'b0), .o_noc_control_mode_channel_2_wgt()
    );

endmodule
