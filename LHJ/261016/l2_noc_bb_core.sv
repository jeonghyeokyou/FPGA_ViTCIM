`timescale 1ns/1ps
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
    input wire bb_start,
    input wire [1:0] bb_inject,
    input wire [10:0] bb_in_base, bb_out_base,
    input wire [8:0] bb_in_len, bb_out_len,
    input wire [31:0] bb_latency,
    input wire bram_we, bram_sel,
    input wire [7:0] bram_addr,
    input wire [511:0] bram_wdata,
    output wire bb_busy, bb_done, bb_first_valid, bb_err_start_busy,
    output wire [15:0] bb_mm_cnt, bb_first_idx,
    output wire [31:0] bb_first_got, bb_first_exp, bb_cycles
);
 localparam BW_CH1_IN=512, DA_CH1_IN=19, NOC_ADDR_DEPTH=2048, NOC_ADDR_BW=11;
 wire busy_ch1_in, l2_ready, l1_write_commit, port_conflict;
 reg in_flight, saw_busy, fence_error;
 reg [31:0] writes_issued, writes_committed;
 assign channel_busy[0]=busy_ch1_in;
 wire admit_command = !in_flight && !bb_busy && !bb_start && !fence_error;
 assign command_ready=l2_ready && admit_command;
 assign start_allowed=!bb_busy && !bb_start && !in_flight && !command_valid && !busy_ch1_in && !fence_error;
 assign exec_status={fence_error,start_allowed,in_flight};
 // Only one ch1_in command may enter L2. Count physical L1 write commits,
 // not a fixed delay from L2 busy. Handshake mode counts response pulses,
 // because valid is held across cycles and FIFO-ready is tied high.
 always @(posedge aclk or negedge aresetn) begin
   if(!aresetn) begin
     in_flight<=0; saw_busy<=0; completed_count<=0; fence_error<=0;
     writes_issued<=0; writes_committed<=0;
   end else begin
     if(port_conflict) fence_error<=1;
     if(command_valid && command_ready) begin
       in_flight<=1; saw_busy<=0; writes_issued<=0; writes_committed<=0;
     end else if(in_flight) begin
       if(busy_ch1_in) saw_busy<=1;
       if(l2_ctrl_mode ? l2_w_resp : (l2_w_valid && l2_w_ready)) writes_issued<=writes_issued+1;
       if(l1_write_commit) writes_committed<=writes_committed+1;
       if(saw_busy && !busy_ch1_in && writes_issued==writes_committed &&
          !l2_w_valid && !l1_write_commit) begin
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

        .i_command(command), .i_command_valid(command_valid && admit_command), .o_command_ready(l2_ready),

        .o_busy_channel_1_in(busy_ch1_in),
        .i_noc_write_ready_channel_1_in(l2_w_ready), .o_noc_write_valid_channel_1_in(l2_w_valid),
        .o_noc_write_addr_channel_1_in(l2_w_addr), .o_noc_write_data_channel_1_in(l2_w_data),
        .i_noc_write_response_channel_1_in(l2_w_resp),
        .o_noc_read_addr_channel_1_in(l2_r_addr), .o_noc_read_valid_channel_1_in(l2_r_valid),
        .o_noc_read_data_ready_channel_1_in(l2_r_data_ready), .i_noc_read_ready_channel_1_in(l2_r_ready),
        .i_noc_read_response_channel_1_in(l2_r_resp), .i_noc_read_data_channel_1_in(l2_r_data),
        .o_noc_control_mode_channel_1_in(l2_ctrl_mode),

        .o_busy_channel_2_in(channel_busy[1]),
        .i_noc_write_ready_channel_2_in(1'b0), .o_noc_write_valid_channel_2_in(),
        .o_noc_write_addr_channel_2_in(), .o_noc_write_data_channel_2_in(),
        .i_noc_write_response_channel_2_in(1'b0),
        .o_noc_read_ready_channel_2_in(), .i_noc_read_valid_channel_2_in(1'b0),
        .i_noc_read_addr_channel_2_in('0), .i_noc_read_data_channel_2_in('0),
        .o_noc_read_response_channel_2_in(), .o_noc_control_mode_channel_2_in(),

        .o_busy_channel_1_wgt(channel_busy[2]),
        .i_noc_write_ready_channel_1_wgt(1'b0), .o_noc_write_valid_channel_1_wgt(),
        .o_noc_write_addr_channel_1_wgt(), .o_noc_write_data_channel_1_wgt(),
        .i_noc_write_response_channel_1_wgt(1'b0),
        .o_noc_read_addr_channel_1_wgt(), .o_noc_read_valid_channel_1_wgt(),
        .o_noc_read_data_ready_channel_1_wgt(), .i_noc_read_ready_channel_1_wgt(1'b0),
        .i_noc_read_response_channel_1_wgt(1'b0), .i_noc_read_data_channel_1_wgt('0),
        .o_noc_control_mode_channel_1_wgt(),

        .o_busy_channel_2_wgt(channel_busy[3]),
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
        .i_pe_din(pe_din), .o_pe_dout(pe_dout), .o_noc_write_commit(l1_write_commit), .o_port_conflict(port_conflict));

    blackbox_pe #(.DW(BW_CH1_IN), .L1_AW(NOC_ADDR_BW), .BRAM_DEPTH(256), .GUARD(BB_GUARD)) u_bb (
        .clk(aclk), .rstn(aresetn),
        .i_start(bb_start), .i_noc_busy(busy_ch1_in || in_flight || command_valid || fence_error),
        .i_in_base(bb_in_base), .i_in_len(bb_in_len), .i_out_base(bb_out_base), .i_out_len(bb_out_len),
        .i_latency(bb_latency), .i_inject(bb_inject),
        .i_bram_we(bram_we), .i_bram_sel(bram_sel), .i_bram_addr(bram_addr), .i_bram_wdata(bram_wdata),
        .o_pe_busy(pe_busy), .o_ceb(pe_ceb), .o_web(pe_web), .o_addr(pe_addr), .o_din(pe_din), .i_dout(pe_dout),
        .o_busy(bb_busy), .o_done(bb_done),
        .o_mismatch_cnt(bb_mm_cnt), .o_first_mm_idx(bb_first_idx), .o_first_mm_valid(bb_first_valid),
        .o_first_mm_got(bb_first_got), .o_first_mm_exp(bb_first_exp),
        .o_err_start_busy(bb_err_start_busy), .o_cycle_cnt(bb_cycles));

endmodule
