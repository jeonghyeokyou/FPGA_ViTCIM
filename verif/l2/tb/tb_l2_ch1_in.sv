`timescale 1ns/1ps
// ===================================================================
//  Phase 1 testbench  -  TOP_L2_cache , channel 1 input path only
//  Goal : drive ONE i_command and watch the waveform.
//         The NOC side is a trivial "always ready" model (BFM) so the
//         internal FSM can run to completion instead of stalling.
//  Not a self-checking test yet - inspection only.
// ===================================================================
module tb_l2_ch1_in;

    // ---- DUT parameters (defaults of TOP_L2_cache) -----------------
    localparam GROUPS      = 8;
    localparam BLOCKS      = 32;
    localparam ADDRESS_ROW = 2048;
    localparam BW_CH0      = 64;
    localparam BW_CH1_IN   = 512;
    localparam BW_CH2_IN   = 256;
    localparam BW_CH1_WGT  = 256;
    localparam BW_CH2_WGT  = 256;
    localparam DA_CH0      = 20;                 // DESTINATION_ADDR_BIT_CHANNEL_0
    localparam DA_CH1_IN   = 19;
    localparam DA_CH2_IN   = 15;
    localparam DA_CH1_WGT  = 18;
    localparam DA_CH2_WGT  = 9;
    localparam AW_CH0_GRP  = 19;                 // clog2(2048*32)+clog2(8) = 16+3

    // ---- clock / reset -------------------------------------------------
    localparam CLKP = 10;                        // 100 MHz
    logic i_clk  = 1'b0;
    logic i_rstb = 1'b0;
    always #(CLKP/2) i_clk = ~i_clk;

    // ---- TOP ctrl command interface ---------------------------------
    logic [63:0] i_command       = 64'd0;
    logic        i_command_valid = 1'b0;
    wire         o_command_ready;

    // =====================================================================
    //  channel 0  (AXI slave) : kept idle for this test
    // =====================================================================
    logic [AW_CH0_GRP-1:0] i_araddr_channel_0  = '0;
    logic                  i_arvalid_channel_0 = 1'b0;
    wire                   o_arready_channel_0;
    logic [7:0]            i_arlen_channel_0   = 8'd0;
    wire  [BW_CH0-1:0]     o_rdata_channel_0;
    wire                   o_rvalid_channel_0;
    logic                  i_rready_channel_0  = 1'b1;
    wire                   o_rlast_channel_0;
    logic [AW_CH0_GRP-1:0] i_awaddr_channel_0  = '0;
    logic                  i_awvalid_channel_0 = 1'b0;
    wire                   o_awready_channel_0;
    logic [7:0]            i_awlen_channel_0   = 8'd0;
    logic [BW_CH0-1:0]     i_wdata_channel_0   = '0;
    logic                  i_wvalid_channel_0  = 1'b0;
    logic                  i_wlast_channel_0   = 1'b0;
    wire                   o_wready_channel_0;
    wire                   o_bvalid_channel_0;
    logic                  i_bready_channel_0  = 1'b1;

    // =====================================================================
    //  channel 1 input  (the one under test)
    // =====================================================================
    wire                   o_busy_channel_1_in;
    // NOC write path (L2 is master)
    logic                  i_noc_write_ready_channel_1_in    = 1'b1;
    wire                   o_noc_write_valid_channel_1_in;
    wire [DA_CH1_IN-1:0]   o_noc_write_addr_channel_1_in;
    wire [BW_CH1_IN-1:0]   o_noc_write_data_channel_1_in;
    logic                  i_noc_write_response_channel_1_in = 1'b0;
    // NOC read path (L2 is master)
    wire [DA_CH1_IN-1:0]   o_noc_read_addr_channel_1_in;
    wire                   o_noc_read_valid_channel_1_in;
    wire                   o_noc_read_data_ready_channel_1_in;
    logic                  i_noc_read_ready_channel_1_in     = 1'b1;
    logic                  i_noc_read_response_channel_1_in  = 1'b0;
    logic [BW_CH1_IN-1:0]  i_noc_read_data_channel_1_in      = '0;
    wire                   o_noc_control_mode_channel_1_in;

    // =====================================================================
    //  channel 2 input  : tied off (not driven this test)
    // =====================================================================
    wire                   o_busy_channel_2_in;
    logic                  i_noc_write_ready_channel_2_in    = 1'b1;
    wire                   o_noc_write_valid_channel_2_in;
    wire [DA_CH2_IN-1:0]   o_noc_write_addr_channel_2_in;
    wire [BW_CH2_IN-1:0]   o_noc_write_data_channel_2_in;
    logic                  i_noc_write_response_channel_2_in = 1'b0;
    wire                   o_noc_read_ready_channel_2_in;
    logic                  i_noc_read_valid_channel_2_in     = 1'b0;
    logic [31:0]           i_noc_read_addr_channel_2_in      = 32'd0;
    logic [BW_CH2_IN-1:0]  i_noc_read_data_channel_2_in      = '0;
    wire                   o_noc_read_response_channel_2_in;
    wire                   o_noc_control_mode_channel_2_in;

    // =====================================================================
    //  channel 1 / 2 weight : tied off
    // =====================================================================
    wire                   o_busy_channel_1_wgt;
    logic                  i_noc_write_ready_channel_1_wgt    = 1'b1;
    wire                   o_noc_write_valid_channel_1_wgt;
    wire [DA_CH1_WGT-1:0]  o_noc_write_addr_channel_1_wgt;
    wire [BW_CH1_WGT-1:0]  o_noc_write_data_channel_1_wgt;
    logic                  i_noc_write_response_channel_1_wgt = 1'b0;
    wire [DA_CH1_WGT-1:0]  o_noc_read_addr_channel_1_wgt;
    wire                   o_noc_read_valid_channel_1_wgt;
    wire                   o_noc_read_data_ready_channel_1_wgt;
    logic                  i_noc_read_ready_channel_1_wgt     = 1'b1;
    logic                  i_noc_read_response_channel_1_wgt  = 1'b0;
    logic [BW_CH1_WGT-1:0] i_noc_read_data_channel_1_wgt      = '0;
    wire                   o_noc_control_mode_channel_1_wgt;

    wire                   o_busy_channel_2_wgt;
    logic                  i_noc_write_ready_channel_2_wgt    = 1'b1;
    wire                   o_noc_write_valid_channel_2_wgt;
    wire [DA_CH2_WGT-1:0]  o_noc_write_addr_channel_2_wgt;
    wire [BW_CH2_WGT-1:0]  o_noc_write_data_channel_2_wgt;
    logic                  i_noc_write_response_channel_2_wgt = 1'b0;
    wire                   o_noc_control_mode_channel_2_wgt;

    // =====================================================================
    //  DUT
    // =====================================================================
    TOP_L2_cache #(
        .GROUPS(GROUPS), .BLOCKS(BLOCKS), .ADDRESS_ROW(ADDRESS_ROW),
        .BANDWIDTH_CHANNEL_0(BW_CH0),
        .BANDWIDTH_CHANNEL_1_IN(BW_CH1_IN),   .BANDWIDTH_CHANNEL_2_IN(BW_CH2_IN),
        .BANDWIDTH_CHANNEL_1_WGT(BW_CH1_WGT), .BANDWIDTH_CHANNEL_2_WGT(BW_CH2_WGT),
        .DESTINATION_ADDR_BIT_CHANNEL_0(DA_CH0),
        .DESTINATION_ADDR_BIT_CHANNEL_1_IN(DA_CH1_IN),
        .DESTINATION_ADDR_BIT_CHANNEL_2_IN(DA_CH2_IN),
        .DESTINATION_ADDR_BIT_CHANNEL_1_WGT(DA_CH1_WGT),
        .DESTINATION_ADDR_BIT_CHANNEL_2_WGT(DA_CH2_WGT)
    ) dut (
        .i_clk (i_clk), .i_rstb(i_rstb),
        // channel 0
        .i_araddr_channel_0(i_araddr_channel_0), .i_arvalid_channel_0(i_arvalid_channel_0),
        .o_arready_channel_0(o_arready_channel_0), .i_arlen_channel_0(i_arlen_channel_0),
        .o_rdata_channel_0(o_rdata_channel_0), .o_rvalid_channel_0(o_rvalid_channel_0),
        .i_rready_channel_0(i_rready_channel_0), .o_rlast_channel_0(o_rlast_channel_0),
        .i_awaddr_channel_0(i_awaddr_channel_0), .i_awvalid_channel_0(i_awvalid_channel_0),
        .o_awready_channel_0(o_awready_channel_0), .i_awlen_channel_0(i_awlen_channel_0),
        .i_wdata_channel_0(i_wdata_channel_0), .i_wvalid_channel_0(i_wvalid_channel_0),
        .i_wlast_channel_0(i_wlast_channel_0), .o_wready_channel_0(o_wready_channel_0),
        .o_bvalid_channel_0(o_bvalid_channel_0), .i_bready_channel_0(i_bready_channel_0),
        // TOP ctrl
        .i_command(i_command), .i_command_valid(i_command_valid), .o_command_ready(o_command_ready),
        // channel 1 in
        .o_busy_channel_1_in(o_busy_channel_1_in),
        .i_noc_write_ready_channel_1_in(i_noc_write_ready_channel_1_in),
        .o_noc_write_valid_channel_1_in(o_noc_write_valid_channel_1_in),
        .o_noc_write_addr_channel_1_in(o_noc_write_addr_channel_1_in),
        .o_noc_write_data_channel_1_in(o_noc_write_data_channel_1_in),
        .i_noc_write_response_channel_1_in(i_noc_write_response_channel_1_in),
        .o_noc_read_addr_channel_1_in(o_noc_read_addr_channel_1_in),
        .o_noc_read_valid_channel_1_in(o_noc_read_valid_channel_1_in),
        .o_noc_read_data_ready_channel_1_in(o_noc_read_data_ready_channel_1_in),
        .i_noc_read_ready_channel_1_in(i_noc_read_ready_channel_1_in),
        .i_noc_read_response_channel_1_in(i_noc_read_response_channel_1_in),
        .i_noc_read_data_channel_1_in(i_noc_read_data_channel_1_in),
        .o_noc_control_mode_channel_1_in(o_noc_control_mode_channel_1_in),
        // channel 2 in
        .o_busy_channel_2_in(o_busy_channel_2_in),
        .i_noc_write_ready_channel_2_in(i_noc_write_ready_channel_2_in),
        .o_noc_write_valid_channel_2_in(o_noc_write_valid_channel_2_in),
        .o_noc_write_addr_channel_2_in(o_noc_write_addr_channel_2_in),
        .o_noc_write_data_channel_2_in(o_noc_write_data_channel_2_in),
        .i_noc_write_response_channel_2_in(i_noc_write_response_channel_2_in),
        .o_noc_read_ready_channel_2_in(o_noc_read_ready_channel_2_in),
        .i_noc_read_valid_channel_2_in(i_noc_read_valid_channel_2_in),
        .i_noc_read_addr_channel_2_in(i_noc_read_addr_channel_2_in),
        .i_noc_read_data_channel_2_in(i_noc_read_data_channel_2_in),
        .o_noc_read_response_channel_2_in(o_noc_read_response_channel_2_in),
        .o_noc_control_mode_channel_2_in(o_noc_control_mode_channel_2_in),
        // channel 1 wgt
        .o_busy_channel_1_wgt(o_busy_channel_1_wgt),
        .i_noc_write_ready_channel_1_wgt(i_noc_write_ready_channel_1_wgt),
        .o_noc_write_valid_channel_1_wgt(o_noc_write_valid_channel_1_wgt),
        .o_noc_write_addr_channel_1_wgt(o_noc_write_addr_channel_1_wgt),
        .o_noc_write_data_channel_1_wgt(o_noc_write_data_channel_1_wgt),
        .i_noc_write_response_channel_1_wgt(i_noc_write_response_channel_1_wgt),
        .o_noc_read_addr_channel_1_wgt(o_noc_read_addr_channel_1_wgt),
        .o_noc_read_valid_channel_1_wgt(o_noc_read_valid_channel_1_wgt),
        .o_noc_read_data_ready_channel_1_wgt(o_noc_read_data_ready_channel_1_wgt),
        .i_noc_read_ready_channel_1_wgt(i_noc_read_ready_channel_1_wgt),
        .i_noc_read_response_channel_1_wgt(i_noc_read_response_channel_1_wgt),
        .i_noc_read_data_channel_1_wgt(i_noc_read_data_channel_1_wgt),
        .o_noc_control_mode_channel_1_wgt(o_noc_control_mode_channel_1_wgt),
        // channel 2 wgt
        .o_busy_channel_2_wgt(o_busy_channel_2_wgt),
        .i_noc_write_ready_channel_2_wgt(i_noc_write_ready_channel_2_wgt),
        .o_noc_write_valid_channel_2_wgt(o_noc_write_valid_channel_2_wgt),
        .o_noc_write_addr_channel_2_wgt(o_noc_write_addr_channel_2_wgt),
        .o_noc_write_data_channel_2_wgt(o_noc_write_data_channel_2_wgt),
        .i_noc_write_response_channel_2_wgt(i_noc_write_response_channel_2_wgt),
        .o_noc_control_mode_channel_2_wgt(o_noc_control_mode_channel_2_wgt)
    );

    // =====================================================================
    //  Trivial NOC model for channel 1 input
    //   - write path : accept every beat, ack 1 cycle later, log it
    //   - read  path : return data (= address pattern) 1 cycle after req
    // =====================================================================
    integer wr_cnt = 0;
    integer rd_cnt = 0;

    always @(posedge i_clk or negedge i_rstb) begin
        if (!i_rstb) begin
            i_noc_write_response_channel_1_in <= 1'b0;
            i_noc_read_response_channel_1_in  <= 1'b0;
            i_noc_read_data_channel_1_in      <= '0;
            wr_cnt <= 0;
            rd_cnt <= 0;
        end
        else begin
            // -- NOC write path ------------------------------------------------
            i_noc_write_response_channel_1_in <= o_noc_write_valid_channel_1_in &
                                                 i_noc_write_ready_channel_1_in;
            if (o_noc_write_valid_channel_1_in & i_noc_write_ready_channel_1_in) begin
                wr_cnt <= wr_cnt + 1;
                $display("[%0t]  NOC WR  ch1_in  #%0d  addr=0x%05h  data=0x%h",
                         $time, wr_cnt, o_noc_write_addr_channel_1_in,
                         o_noc_write_data_channel_1_in);
            end
            // -- NOC read path -----------------------------------------------
            i_noc_read_response_channel_1_in <= o_noc_read_valid_channel_1_in &
                                                i_noc_read_ready_channel_1_in;
            if (o_noc_read_valid_channel_1_in & i_noc_read_ready_channel_1_in) begin
                rd_cnt <= rd_cnt + 1;
                // visible pattern: low bits carry the requested address
                i_noc_read_data_channel_1_in <=
                    { {(BW_CH1_IN-32){1'b0}}, 13'h1AB0, o_noc_read_addr_channel_1_in };
                $display("[%0t]  NOC RD  ch1_in  #%0d  addr=0x%05h",
                         $time, rd_cnt, o_noc_read_addr_channel_1_in);
            end
        end
    end

    // =====================================================================
    //  helper : push one command word into the L2 command queue
    // =====================================================================
    task automatic send_cmd(input [63:0] c);
        @(negedge i_clk);
        i_command       = c;
        i_command_valid = 1'b1;
        @(posedge i_clk);
        while (!o_command_ready) @(posedge i_clk);
        @(negedge i_clk);
        i_command_valid = 1'b0;
        i_command       = 64'd0;
        $display("[%0t]  CMD pushed : 0x%016h", $time, c);
    endtask

    // =====================================================================
    //  stimulus
    // =====================================================================
    logic [63:0] cmd;

    initial begin
        $dumpfile("tb_l2_ch1_in.vcd");
        $dumpvars(0, tb_l2_ch1_in);

        // reset
        i_rstb = 1'b0;
        repeat (10) @(posedge i_clk);
        i_rstb = 1'b1;
        repeat (5) @(posedge i_clk);

        // ---- Scenario : channel 1 input  BURST LOAD -----------------------
        //  cmd[62:60]=001 ch1_In load , cmd[59:58]=00 burst load
        //  source_read_addr = 4  -> 5 beats
        //  multicast = 0x01
        cmd = 64'd0;
        cmd[62:60] = 3'b001;          // cmd index : ch1_In load
        cmd[59:58] = 2'b00;           // ctrl_mode : burst load
        cmd[57]    = 1'b0;            // prec_mode
        cmd[56:40] = 17'd0;           // source_start_addr
        cmd[39:29] = 11'd4;           // source_read_addr  (beats-1)
        cmd[28:18] = 11'd0;           // destination_start_addr
        cmd[17:15] = 3'd0;            // resize_step_addr (no resize)
        cmd[14:7]  = 8'h01;           // multicast
        cmd[6:0]   = 7'd0;            // opcode

        send_cmd(cmd);

        // let the transfer run
        repeat (400) @(posedge i_clk);

        $display("\n==== done : %0d NOC writes, %0d NOC reads ====", wr_cnt, rd_cnt);
        $finish;
    end

    // safety timeout
    initial begin
        #200000;
        $display("!! TIMEOUT !!");
        $finish;
    end

endmodule
