`timescale 1ns/1ps
// ===================================================================
//  Phase 1 testbench  (v2)  -  TOP_L2_cache , channel 1 input
//
//  GUIDE section 5-(A) : store -> load
//    step 1 : ch1_in BURST STORE  - the fake NOC feeds a known
//             data pattern, L2 writes it into its internal SRAM
//    step 2 : ch1_in BURST LOAD   - L2 reads that SRAM back out and
//             drives it on o_noc_write_data.  Now the data is real,
//             so we can check load_data == the pattern we stored.
//
//  Difference vs tb_l2_ch1_in.sv :
//    - added a STORE scenario before the LOAD
//    - the NOC "read" side (used by store) is now a paced 1-outstanding
//      model instead of always-ready, so no beat is dropped
//    - a tiny inline check on the LOAD data (still not a full scoreboard)
// ===================================================================
module tb_l2_ch1_in_storeload;

    // ---- DUT parameters (defaults of TOP_L2_cache) -----------------
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

    // ---- clock / reset -------------------------------------------------
    localparam CLKP = 10;
    logic i_clk  = 1'b0;
    logic i_rstb = 1'b0;
    always #(CLKP/2) i_clk = ~i_clk;

    // ---- TOP ctrl command interface -------------------------------
    logic [63:0] i_command       = 64'd0;
    logic        i_command_valid = 1'b0;
    wire         o_command_ready;

    // ---- channel 0 (AXI slave) : idle ----------------------------
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

    // ---- channel 1 input (under test) ---------------------------
    wire                   o_busy_channel_1_in;
    logic                  i_noc_write_ready_channel_1_in    = 1'b1;
    wire                   o_noc_write_valid_channel_1_in;
    wire [DA_CH1_IN-1:0]   o_noc_write_addr_channel_1_in;
    wire [BW_CH1_IN-1:0]   o_noc_write_data_channel_1_in;
    logic                  i_noc_write_response_channel_1_in = 1'b0;
    wire [DA_CH1_IN-1:0]   o_noc_read_addr_channel_1_in;
    wire                   o_noc_read_valid_channel_1_in;
    wire                   o_noc_read_data_ready_channel_1_in;
    wire                   i_noc_read_ready_channel_1_in;             // driven by assign in the paced BFM
    logic                  i_noc_read_response_channel_1_in  = 1'b0;
    logic [BW_CH1_IN-1:0]  i_noc_read_data_channel_1_in      = '0;
    wire                   o_noc_control_mode_channel_1_in;

    // ---- channel 2 input : tied off ------------------------------
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

    // ---- channel 1 / 2 weight : tied off ------------------------
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
        .o_busy_channel_2_wgt(o_busy_channel_2_wgt),
        .i_noc_write_ready_channel_2_wgt(i_noc_write_ready_channel_2_wgt),
        .o_noc_write_valid_channel_2_wgt(o_noc_write_valid_channel_2_wgt),
        .o_noc_write_addr_channel_2_wgt(o_noc_write_addr_channel_2_wgt),
        .o_noc_write_data_channel_2_wgt(o_noc_write_data_channel_2_wgt),
        .i_noc_write_response_channel_2_wgt(i_noc_write_response_channel_2_wgt),
        .o_noc_control_mode_channel_2_wgt(o_noc_control_mode_channel_2_wgt)
    );

    // =====================================================================
    //  Fake NOC : WRITE path (used by LOAD).  Always ready, 1-cyc ack.
    //  Also checks the load data against the pattern we stored.
    // =====================================================================
    localparam [31:0] PAT_BASE = 32'hA5A5_0000;
    function automatic [BW_CH1_IN-1:0] pattern(input int beat);
        pattern = { {(BW_CH1_IN-32){1'b0}}, (PAT_BASE + beat) };
    endfunction

    integer wr_cnt = 0;
    integer wr_bad = 0;
    logic   checking = 1'b0;      // enable the load-data check only during the LOAD phase

    always @(posedge i_clk or negedge i_rstb) begin
        if (!i_rstb) begin
            i_noc_write_response_channel_1_in <= 1'b0;
            wr_cnt <= 0;
            wr_bad <= 0;
        end
        else begin
            i_noc_write_response_channel_1_in <= o_noc_write_valid_channel_1_in &
                                                 i_noc_write_ready_channel_1_in;
            if (o_noc_write_valid_channel_1_in & i_noc_write_ready_channel_1_in) begin
                if (checking) begin
                    if (o_noc_write_data_channel_1_in === pattern(wr_cnt))
                        $display("[%0t]  LOAD beat %0d  addr=0x%05h  data=0x%h   OK",
                                 $time, wr_cnt, o_noc_write_addr_channel_1_in,
                                 o_noc_write_data_channel_1_in);
                    else begin
                        $display("[%0t]  LOAD beat %0d  addr=0x%05h  MISMATCH  exp=0x%h  got=0x%h",
                                 $time, wr_cnt, o_noc_write_addr_channel_1_in,
                                 pattern(wr_cnt), o_noc_write_data_channel_1_in);
                        wr_bad <= wr_bad + 1;
                    end
                end
                wr_cnt <= wr_cnt + 1;
            end
        end
    end

    // =====================================================================
    //  Fake NOC : READ path (used by STORE).
    //  Paced 1-outstanding model:
    //    - i_noc_read_ready = 1 only while no request is in flight
    //    - after accepting a request, hold i_noc_read_response + data
    //      until L2 actually consumes it (response & o_noc_read_data_ready)
    //    - beat k returns pattern(k)
    // =====================================================================
    typedef enum logic {RD_IDLE, RD_RESP} rd_state_e;
    rd_state_e   rd_st  = RD_IDLE;
    integer      rd_beat = 0;

    assign i_noc_read_ready_channel_1_in = (rd_st == RD_IDLE);

    always @(posedge i_clk or negedge i_rstb) begin
        if (!i_rstb) begin
            rd_st   <= RD_IDLE;
            rd_beat <= 0;
            i_noc_read_response_channel_1_in <= 1'b0;
            i_noc_read_data_channel_1_in     <= '0;
        end
        else begin
            case (rd_st)
                RD_IDLE: begin
                    i_noc_read_response_channel_1_in <= 1'b0;
                    if (o_noc_read_valid_channel_1_in & i_noc_read_ready_channel_1_in) begin
                        $display("[%0t]  STORE NOC-RD req  beat %0d  addr=0x%05h",
                                 $time, rd_beat, o_noc_read_addr_channel_1_in);
                        rd_st <= RD_RESP;
                    end
                end
                RD_RESP: begin
                    i_noc_read_response_channel_1_in <= 1'b1;
                    i_noc_read_data_channel_1_in     <= pattern(rd_beat);
                    if (i_noc_read_response_channel_1_in & o_noc_read_data_ready_channel_1_in) begin
                        $display("[%0t]  STORE NOC-RD data beat %0d  = 0x%h  (consumed)",
                                 $time, rd_beat, pattern(rd_beat));
                        rd_beat <= rd_beat + 1;
                        rd_st   <= RD_IDLE;
                        i_noc_read_response_channel_1_in <= 1'b0;
                    end
                end
            endcase
        end
    end

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
    logic [63:0] cmd;
    localparam N_BEATS = 5;

    initial begin
        $dumpfile("tb_l2_ch1_in_storeload.vcd");
        $dumpvars(0, tb_l2_ch1_in_storeload);

        i_rstb = 1'b0;
        repeat (10) @(posedge i_clk);
        i_rstb = 1'b1;
        repeat (5) @(posedge i_clk);

        // -----------------------------------------------------------------
        //  STEP 1 : ch1_in  BURST STORE   (NOC -> L2 internal SRAM)
        //   cmd[62:60]=010 ch1_In store , cmd[59:58]=10 burst store
        //   destination_start_addr = 0        (where in L2 SRAM to write)
        //   destination_write_addr = N_BEATS-1 (beats-1)
        //   source_start_addr      = 0        (NOC read base addr)
        // -----------------------------------------------------------------
        cmd = 64'd0;
        cmd[62:60] = 3'b010;             // ch1_In store
        cmd[59:58] = 2'b10;             // burst store
        cmd[57:41] = 17'd0;            // destination_start_addr
        cmd[40:27] = 14'(N_BEATS-1);   // destination_write_addr
        cmd[26:13] = 14'd0;            // source_start_addr
        $display("\n---------------- STEP 1 : STORE ----------------");
        send_cmd(cmd);
        wait (o_busy_channel_1_in === 1'b1);   // store started
        wait (o_busy_channel_1_in === 1'b0);   // store finished
        repeat (10) @(posedge i_clk);
        $display("---- store done : %0d beats issued ----", rd_beat);

        // -----------------------------------------------------------------
        //  STEP 2 : ch1_in  BURST LOAD    (L2 internal SRAM -> NOC)
        //   should read back exactly what STEP 1 wrote
        // -----------------------------------------------------------------
        cmd = 64'd0;
        cmd[62:60] = 3'b001;             // ch1_In load
        cmd[59:58] = 2'b00;             // burst load
        cmd[56:40] = 17'd0;            // source_start_addr  (= store dest)
        cmd[39:29] = 11'(N_BEATS-1);   // source_read_addr   (beats-1)
        cmd[28:18] = 11'd0;            // destination_start_addr
        cmd[17:15] = 3'd0;            // resize_step_addr
        cmd[14:7]  = 8'h01;           // multicast
        $display("\n---------------- STEP 2 : LOAD ----------------");
        checking = 1'b1;
        send_cmd(cmd);
        wait (o_busy_channel_1_in === 1'b1);
        wait (o_busy_channel_1_in === 1'b0);
        repeat (10) @(posedge i_clk);

        $display("\n==================================================");
        if (wr_cnt == N_BEATS && wr_bad == 0)
            $display("  RESULT : PASS   (%0d/%0d load beats match stored pattern)", wr_cnt, N_BEATS);
        else
            $display("  RESULT : CHECK  (load beats=%0d , mismatches=%0d)", wr_cnt, wr_bad);
        $display("==================================================\n");
        $finish;
    end

    // safety timeout
    initial begin
        #300000;
        $display("!! TIMEOUT !!  (FSM probably stalled - inspect the waveform)");
        $finish;
    end

endmodule
