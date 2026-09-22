`timescale 1ns/1ps
// ===================================================================
//  L2 + NOC integration, channel 1 weight  (same pattern as
//  tb_l2_noc_ch1_in.sv - ch1_wgt has an identical master-both-ways
//  port shape, see cmd_decoder_channel_1_wgt.sv).
//
//  DUTs   : TOP_L2_cache  (L2_260901, ram_mimic-fixed)
//           FIFO_intf     (NOC_260902, renamed + sim-fixed, STEP 1) -
//           reused as-is, just re-parameterized for ch1_wgt's width
//           (DATA_WIDTH=256, local addr = 10b instead of ch1_in's 11b)
//  Glue   : noc_ch1_wgt_adapter
//
//  Story (identical shape to ch1_in's):
//   1. Backdoor-load 5 words into this FIFO_intf's L1_Cache_Mimic
//      bank 0, addr 0..4 - stands in for "weights already sitting in
//      the CIM Cluster Array".
//   2. L2 ch1_wgt STORE (cmd_idx=6, burst) : NOC read path pulls those
//      5 words from addr 0..4 into L2's internal SRAM addr 0..4.
//   3. L2 ch1_wgt LOAD  (cmd_idx=5, burst) : NOC write path pushes L2
//      SRAM addr 0..4 back out to addr 60..64 (different address).
//   4. Backdoor-read addr 60..64 and compare.
// ===================================================================
module tb_l2_noc_ch1_wgt;

    // ---- L2 parameters (TOP_L2_cache defaults) ----------------------
    localparam GROUPS      = 8;
    localparam BLOCKS      = 32;
    localparam ADDRESS_ROW = 2048;
    localparam BW_CH0      = 64;
    localparam BW_CH1_IN   = 512;
    localparam BW_CH2_IN   = 256;
    localparam BW_CH1_WGT  = 256;
    localparam BW_CH2_WGT  = 256;
    localparam DA_CH0      = 20;
    localparam DA_CH1_IN   = 19;
    localparam DA_CH2_IN   = 15;
    localparam DA_CH1_WGT  = 18;
    localparam DA_CH2_WGT  = 9;
    localparam AW_CH0_GRP  = 19;

    // ---- NOC parameters (FIFO_intf, re-parameterized for ch1_wgt) -----
    localparam NOC_ADDR_DEPTH = 1024;                     // -> ADDR_BW = 10 (matches ch1_wgt local addr)
    localparam NOC_ADDR_BW    = $clog2(NOC_ADDR_DEPTH);   // = 10
    localparam NOC_MEM_BW     = 128;                      // BW_CH1_WGT(256) = 2 banks of 128
    localparam NOC_FIFO_DEPTH = 8;
    localparam NOC_IN_DELAY   = 3;

    localparam N_BEATS = 5;

    // ---- clock / reset ------------------------------------------------
    localparam CLKP = 10;
    logic i_clk  = 1'b0;
    logic i_rstb = 1'b0;
    always #(CLKP/2) i_clk = ~i_clk;

    // ---- TOP ctrl command interface -----------------------------------
    logic [63:0] i_command       = 64'd0;
    logic        i_command_valid = 1'b0;
    wire         o_command_ready;

    // ---- channel 0 (AXI) : idle ---------------------------------------
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

    // ---- channel 1 input : tied off ------------------------------------
    wire                   o_busy_channel_1_in;
    logic                  i_noc_write_ready_channel_1_in    = 1'b1;
    wire                   o_noc_write_valid_channel_1_in;
    wire [DA_CH1_IN-1:0]   o_noc_write_addr_channel_1_in;
    wire [BW_CH1_IN-1:0]   o_noc_write_data_channel_1_in;
    logic                  i_noc_write_response_channel_1_in = 1'b0;
    wire [DA_CH1_IN-1:0]   o_noc_read_addr_channel_1_in;
    wire                   o_noc_read_valid_channel_1_in;
    wire                   o_noc_read_data_ready_channel_1_in;
    logic                  i_noc_read_ready_channel_1_in     = 1'b1;
    logic                  i_noc_read_response_channel_1_in  = 1'b0;
    logic [BW_CH1_IN-1:0]  i_noc_read_data_channel_1_in      = '0;
    wire                   o_noc_control_mode_channel_1_in;

    // ---- channel 2 input : tied off ------------------------------------
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

    // ---- channel 1 wgt : wired to the adapter --------------------------
    wire                   o_busy_channel_1_wgt;
    wire                   i_noc_write_ready_channel_1_wgt;
    wire                   o_noc_write_valid_channel_1_wgt;
    wire [DA_CH1_WGT-1:0]  o_noc_write_addr_channel_1_wgt;
    wire [BW_CH1_WGT-1:0]  o_noc_write_data_channel_1_wgt;
    wire                   i_noc_write_response_channel_1_wgt;
    wire [DA_CH1_WGT-1:0]  o_noc_read_addr_channel_1_wgt;
    wire                   o_noc_read_valid_channel_1_wgt;
    wire                   o_noc_read_data_ready_channel_1_wgt;
    wire                   i_noc_read_ready_channel_1_wgt;
    wire                   i_noc_read_response_channel_1_wgt;
    wire [BW_CH1_WGT-1:0]  i_noc_read_data_channel_1_wgt;
    wire                   o_noc_control_mode_channel_1_wgt;

    // ---- channel 2 wgt : tied off ---------------------------------------
    wire                   o_busy_channel_2_wgt;
    logic                  i_noc_write_ready_channel_2_wgt    = 1'b1;
    wire                   o_noc_write_valid_channel_2_wgt;
    wire [DA_CH2_WGT-1:0]  o_noc_write_addr_channel_2_wgt;
    wire [BW_CH2_WGT-1:0]  o_noc_write_data_channel_2_wgt;
    logic                  i_noc_write_response_channel_2_wgt = 1'b0;
    wire                   o_noc_control_mode_channel_2_wgt;

    // =====================================================================
    //  DUT 1 : TOP_L2_cache
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
    ) dut_l2 (
        .i_clk (i_clk), .i_rstb(i_rstb),
        .i_araddr_channel_0(i_araddr_channel_0), .i_arvalid_channel_0(i_arvalid_channel_0),
        .o_arready_channel_0(o_arready_channel_0), .i_arlen_channel_0(i_arlen_channel_0),
        .o_rdata_channel_0(o_rdata_channel_0), .o_rvalid_channel_0(o_rvalid_channel_0),
        .i_rready_channel_0(i_rready_channel_0), .o_rlast_channel_0(o_rlast_channel_0),
        .i_awaddr_channel_0(i_awaddr_channel_0), .i_awvalid_channel_0(i_awvalid_channel_0),
        .o_awready_channel_0(o_awready_channel_0), .i_awlen_channel_0(i_awlen_channel_0),
        .i_wdata_channel_0(i_wdata_channel_0), .i_wvalid_channel_0(i_wvalid_channel_0),
        .i_wlast_channel_0(i_wlast_channel_0), .o_wready_channel_0(o_wready_channel_0),
        .o_bvalid_channel_0(o_bvalid_channel_0), .i_bready_channel_0(i_bready_channel_0),
        .i_command(i_command), .i_command_valid(i_command_valid), .o_command_ready(o_command_ready),
        // channel 1 in : tied off
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
        // channel 2 in : tied off
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
        // channel 1 wgt -> adapter
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
        // channel 2 wgt : tied off
        .o_busy_channel_2_wgt(o_busy_channel_2_wgt),
        .i_noc_write_ready_channel_2_wgt(i_noc_write_ready_channel_2_wgt),
        .o_noc_write_valid_channel_2_wgt(o_noc_write_valid_channel_2_wgt),
        .o_noc_write_addr_channel_2_wgt(o_noc_write_addr_channel_2_wgt),
        .o_noc_write_data_channel_2_wgt(o_noc_write_data_channel_2_wgt),
        .i_noc_write_response_channel_2_wgt(i_noc_write_response_channel_2_wgt),
        .o_noc_control_mode_channel_2_wgt(o_noc_control_mode_channel_2_wgt)
    );

    // =====================================================================
    //  adapter
    // =====================================================================
    wire                     m_write_valid, m_write_ready, m_fifo_write_ready;
    wire [NOC_ADDR_BW-1:0]   m_write_addr;
    wire [BW_CH1_WGT-1:0]    m_write_data;
    wire                     m_read_valid, m_read_ready, m_fifo_read_ready, m_data_fifo_ready;
    wire [NOC_ADDR_BW-1:0]   m_read_addr;
    wire [BW_CH1_WGT-1:0]    m_read_data;
    wire                     m_control_mode;

    noc_ch1_wgt_adapter #(
        .DA_L2(DA_CH1_WGT), .ADDR_BW(NOC_ADDR_BW), .DW(BW_CH1_WGT)
    ) u_adapter (
        .l2_noc_write_valid    (o_noc_write_valid_channel_1_wgt),
        .l2_noc_write_addr     (o_noc_write_addr_channel_1_wgt),
        .l2_noc_write_data     (o_noc_write_data_channel_1_wgt),
        .l2_noc_write_ready    (i_noc_write_ready_channel_1_wgt),
        .l2_noc_write_response (i_noc_write_response_channel_1_wgt),

        .l2_noc_read_valid       (o_noc_read_valid_channel_1_wgt),
        .l2_noc_read_addr        (o_noc_read_addr_channel_1_wgt),
        .l2_noc_read_data_ready  (o_noc_read_data_ready_channel_1_wgt),
        .l2_noc_read_ready       (i_noc_read_ready_channel_1_wgt),
        .l2_noc_read_response    (i_noc_read_response_channel_1_wgt),
        .l2_noc_read_data        (i_noc_read_data_channel_1_wgt),

        .l2_noc_control_mode   (o_noc_control_mode_channel_1_wgt),

        .m_write_valid(m_write_valid), .m_write_addr(m_write_addr), .m_write_data(m_write_data),
        .m_write_ready(m_write_ready), .m_fifo_write_ready(m_fifo_write_ready),

        .m_read_valid(m_read_valid), .m_read_addr(m_read_addr),
        .m_read_ready(m_read_ready), .m_read_data(m_read_data),
        .m_fifo_read_ready(m_fifo_read_ready), .m_data_fifo_ready(m_data_fifo_ready),

        .m_control_mode(m_control_mode)
    );

    // =====================================================================
    //  DUT 2 : FIFO_intf  (NOC_260902, renamed + sim-fixed) - reused,
    //  re-parameterized for ch1_wgt's 256b / 10b address space
    // =====================================================================
    FIFO_intf #(
        .ADDR_DEPTH(NOC_ADDR_DEPTH), .DATA_WIDTH(BW_CH1_WGT),
        .MEMORY_BITWIDTH(NOC_MEM_BW), .FIFO_DEPTH(NOC_FIFO_DEPTH),
        .INPUT_DELAY(NOC_IN_DELAY)
    ) dut_noc (
        .clk(i_clk), .rstb(i_rstb),
        .i_read_valid(m_read_valid),   .o_read_ready(m_read_ready),
        .i_read_addr(m_read_addr),     .o_read_data(m_read_data),
        .i_write_valid(m_write_valid), .o_write_ready(m_write_ready),
        .i_write_addr(m_write_addr),   .i_write_data(m_write_data),
        .i_control_mode(m_control_mode),
        .o_FIFO_read_ready(m_fifo_read_ready),
        .o_FIFO_write_ready(m_fifo_write_ready),
        .i_data_fifo_ready(m_data_fifo_ready)
    );

    // =====================================================================
    //  helper : push one command word
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
    localparam [31:0] PAT_BASE = 32'hA11A_0000;   // "ALIA" - distinguish from ch1_in's C0DE
    localparam int    L1_SRC   = 0;    // NOC-side addr the pattern is preloaded at
    localparam int    L1_DST   = 60;   // NOC-side addr the LOAD should write it back to

    logic [63:0] cmd;
    integer k, errors;

    initial begin
        $dumpfile("tb_l2_noc_ch1_wgt.vcd");
        $dumpvars(0, tb_l2_noc_ch1_wgt);

        i_rstb = 1'b0;
        repeat (10) @(posedge i_clk);
        i_rstb = 1'b1;
        repeat (5) @(posedge i_clk);

        // ---- STEP 1 : backdoor-preload FIFO_intf's L1_Cache_Mimic bank0 --
        $display("\n---------------- preload (backdoor) ----------------");
        for (k = 0; k < N_BEATS; k = k + 1) begin
            dut_noc.UL1_Cache_Mimic.Usram_mimic_0.mem[L1_SRC + k] =
                { {(NOC_MEM_BW-32){1'b0}}, (PAT_BASE + k) };
            $display("  NOC[%0d] <= 0x%08h", L1_SRC + k, PAT_BASE + k);
        end

        // ---- STEP 2 : ch1_wgt STORE (burst)  : NOC read -> L2 SRAM -------
        //  cmd[62:60]=110 store, cmd[59:58]=10 burst store
        //  cmd[57:40]=dest_start_addr(L2 SRAM)=0, cmd[39:27]=dest_write_addr=N_BEATS-1
        //  cmd[26:14]=source_start_addr_store (NOC local addr, top3b=cluster sel=0) = L1_SRC
        cmd = 64'd0;
        cmd[62:60] = 3'b110;
        cmd[59:58] = 2'b10;
        cmd[57:40] = 18'(0);
        cmd[39:27] = 13'(N_BEATS-1);
        cmd[26:14] = 13'(L1_SRC);
        $display("\n---------------- STEP A : ch1_wgt STORE  (NOC -> L2 SRAM) ----------------");
        send_cmd(cmd);
        wait (o_busy_channel_1_wgt === 1'b1);
        wait (o_busy_channel_1_wgt === 1'b0);
        repeat (10) @(posedge i_clk);

        // ---- STEP 3 : ch1_wgt LOAD (burst)   : L2 SRAM -> NOC write ------
        //  cmd[62:60]=101 load, cmd[59:58]=00 burst load, cmd[57]=0 (burst, not custom)
        //  cmd[56:39]=source_start_addr(L2 SRAM)=0, cmd[38:29]=source_read_addr=N_BEATS-1
        //  cmd[28:19]=destination_start_addr(NOC local addr)=L1_DST
        cmd = 64'd0;
        cmd[62:60] = 3'b101;
        cmd[59:58] = 2'b00;
        cmd[57]    = 1'b0;
        cmd[56:39] = 18'(0);
        cmd[38:29] = 10'(N_BEATS-1);
        cmd[28:19] = 10'(L1_DST);
        cmd[14:7]  = 8'h01;             // multicast (dropped by the adapter, kept for realism)
        $display("\n---------------- STEP B : ch1_wgt LOAD   (L2 SRAM -> NOC) ----------------");
        send_cmd(cmd);
        wait (o_busy_channel_1_wgt === 1'b1);
        wait (o_busy_channel_1_wgt === 1'b0);
        repeat (10) @(posedge i_clk);

        // ---- STEP 4 : backdoor-read at the LOAD destination --------------
        $display("\n---------------- verify NOC[%0d..%0d] (backdoor) ----------------", L1_DST, L1_DST+N_BEATS-1);
        errors = 0;
        for (k = 0; k < N_BEATS; k = k + 1) begin
            logic [NOC_MEM_BW-1:0] got, exp;
            got = dut_noc.UL1_Cache_Mimic.Usram_mimic_0.mem[L1_DST + k];
            exp = { {(NOC_MEM_BW-32){1'b0}}, (PAT_BASE + k) };
            if (got === exp)
                $display("  NOC[%0d] = 0x%08h   OK", L1_DST + k, got[31:0]);
            else begin
                $display("  NOC[%0d] = 0x%08h   MISMATCH (expected 0x%08h)", L1_DST + k, got[31:0], exp[31:0]);
                errors = errors + 1;
            end
        end

        $display("\n==================================================");
        $display("  L2 <-> NOC integration (ch1_wgt) : %s   (errors=%0d)",
                 (errors==0) ? "PASS" : "CHECK", errors);
        $display("==================================================\n");
        $finish;
    end

    initial begin
        #500000;
        $display("!! GLOBAL TIMEOUT !!  (inspect the waveform - a handshake probably stalled)");
        $finish;
    end

endmodule
