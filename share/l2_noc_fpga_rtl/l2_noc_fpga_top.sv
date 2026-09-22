`timescale 1ns/1ps
// =====================================================================
//  l2_noc_fpga_top  -  synthesizable FPGA top : TOP_L2_cache + adapter +
//  FIFO_intf (ch1_in), with a self-contained BIST sequencer so the whole
//  L2<->NOC path can be exercised on real silicon with no host interface
//  (no JTAG-to-AXI / VIO required for this first bring-up).
//
//  How it proves the design out, on hardware:
//    1. FIFO_intf's L1_Cache_Mimic is preloaded at CONFIGURATION time
//       (not simulation time) with a known pattern at NOC-local addr 0..4
//       - see verif/fpga/fpga_fix/sram_mimic_fpga.v's `initial` block,
//       which Vivado bakes into the BRAM/URAM primitive's INIT strings.
//    2. On reset release this module automatically issues the exact same
//       two commands proven in verif/integ/tb/tb_l2_noc_ch1_in.sv:
//         STORE (NOC addr 0..4  -> L2 internal SRAM addr 0..4)
//         LOAD  (L2 SRAM 0..4   -> NOC addr BIST_DST..BIST_DST+4)
//    3. A monitor snoops the 5 write beats L2 sends out on the NOC write
//       path during LOAD and compares each against the known pattern.
//    4. o_led_done / o_led_pass / o_mismatch_count report the result on
//       LEDs; every state/count is `mark_debug`'d for an ILA if you want
//       to probe deeper (see verif/fpga/build_synth.tcl for how to wire
//       one up with `create_debug_core`).
//
//  NOTE on the known beat-0 finding (verif/integ/FINDING_first_write_beat_
//  timing.md): tb_l2_noc_ch1_in.sv / tb_l2_noc_ch1_wgt.sv both reliably lose
//  the first beat of every NOC burst write. This BIST, running the exact
//  same STORE->LOAD sequence through the exact same bridge RTL, does NOT
//  reproduce it (o_mismatch_count reads 0 in simulation - verified with
//  both the reduced and full-scale GROUPS/BLOCKS/ADDRESS_ROW, and with the
//  LOAD destination address matched to tb_l2_noc_ch1_in.sv's). The exact
//  environmental trigger (something in how that testbench preloads/paces
//  commands vs. this always-block sequencer) has not been isolated - see
//  the finding doc's "BIST sequencer did not reproduce it" section. Do not
//  read a clean result here as the bug being fixed; re-run
//  verif/integ/00_run_integ.bat, which still fails, before trusting that.
// =====================================================================

module l2_noc_fpga_top #(
    // ---- reduced L2 internal SRAM for a fast first bring-up ----------
    //  GROUPS MUST stay at the RTL's default (8): cmd_decoder_channel_*
    //  _wrapper.sv hard-codes an internal 2-level group split (its own
    //  GROUPS_1/GROUPS_2 localparams, not exposed through TOP_L2_cache's
    //  parameter list) that assumes GROUPS=8 - elaborating with GROUPS=2
    //  throws "array element widths do not match" / "index out of
    //  bounds" from that mismatch (verified 2026 - see fpga/BRINGUP_NOTES.md).
    //  BLOCKS must be a multiple of BANDWIDTH_CHANNEL_1_IN/BANDWIDTH_CHANNEL_0
    //  = 8 (so BLOCKS_CHANNEL_1_IN=BLOCKS/8 is an integer) AND that quotient
    //  must be >=2 (BLOCKS_CHANNEL_1_IN=1 makes $clog2(1)=0 -> a [-1:0]
    //  zero-width per-block address field -> "part-select direction is
    //  opposite" elaboration errors). BLOCKS=16 is the smallest value that
    //  clears both constraints.
    //  ADDRESS_ROW has no such hidden coupling - shrunk freely to 256.
    //  DESTINATION_ADDR_BIT_CHANNEL_* are independent top-level parameters
    //  (not derived from GROUPS/BLOCKS/ADDRESS_ROW) so they stay at their
    //  defaults - the NOC-facing command formats are unaffected.
    //  Net: 8*16*256*64b = 256 KB (vs 4 MB at the RTL's default
    //  GROUPS=8/BLOCKS=32/ADDRESS_ROW=2048).
    parameter GROUPS      = 8,
    parameter BLOCKS      = 16,
    parameter ADDRESS_ROW = 256
) (
    input  wire        i_clk,        // constrain to the board's oscillator pin in the XDC
    input  wire        i_rst_n,      // async, active-low (board reset button)

    output wire        o_led_done,   // BIST finished
    output wire        o_led_pass,   // done && mismatch_count == 0
    output wire [2:0]  o_mismatch_count
);

    localparam BW_CH0     = 64;
    localparam BW_CH1_IN  = 512;
    localparam BW_CH2_IN  = 256;
    localparam BW_CH1_WGT = 256;
    localparam BW_CH2_WGT = 256;
    localparam DA_CH0     = 20;
    localparam DA_CH1_IN  = 19;
    localparam DA_CH2_IN  = 15;
    localparam DA_CH1_WGT = 18;
    localparam DA_CH2_WGT = 9;
    localparam AW_CH0_GRP = $clog2(ADDRESS_ROW*BLOCKS) + $clog2(GROUPS);

    localparam NOC_ADDR_DEPTH = 2048;
    localparam NOC_ADDR_BW    = $clog2(NOC_ADDR_DEPTH);   // = 11, matches ch1_in local addr
    localparam NOC_MEM_BW     = 128;
    localparam NOC_FIFO_DEPTH = 8;
    localparam NOC_IN_DELAY   = 3;

    localparam N_BEATS      = 5;
    localparam [31:0] PAT_BASE  = 32'hDEAD_BEE0;   // must match sram_mimic_fpga.v's preload
    localparam        BIST_SRC  = 0;               // NOC-local addr the preload sits at
    localparam        BIST_DST  = 20;               // NOC-local addr LOAD should land at

    // ---- channel 0 AXI : idle (BIST doesn't need it - see file header) --
    wire                    o_arready_channel_0, o_rvalid_channel_0, o_rlast_channel_0;
    wire [BW_CH0-1:0]       o_rdata_channel_0;
    wire                    o_awready_channel_0, o_wready_channel_0, o_bvalid_channel_0;

    // ---- channel 1 input : wired to the adapter + FIFO_intf --------------
    wire                    o_busy_channel_1_in;
    wire                    i_noc_write_ready_channel_1_in, i_noc_write_response_channel_1_in;
    wire                    o_noc_write_valid_channel_1_in;
    wire [DA_CH1_IN-1:0]    o_noc_write_addr_channel_1_in;
    wire [BW_CH1_IN-1:0]    o_noc_write_data_channel_1_in;
    wire [DA_CH1_IN-1:0]    o_noc_read_addr_channel_1_in;
    wire                    o_noc_read_valid_channel_1_in, o_noc_read_data_ready_channel_1_in;
    wire                    i_noc_read_ready_channel_1_in, i_noc_read_response_channel_1_in;
    wire [BW_CH1_IN-1:0]    i_noc_read_data_channel_1_in;
    wire                    o_noc_control_mode_channel_1_in;

    // ---- everything else : tied off (not part of this bring-up) ----------
    wire                    o_busy_channel_2_in, o_noc_read_ready_channel_2_in;
    wire                    o_noc_write_valid_channel_2_in;
    wire [DA_CH2_IN-1:0]    o_noc_write_addr_channel_2_in;
    wire [BW_CH2_IN-1:0]    o_noc_write_data_channel_2_in;
    wire                    o_noc_read_response_channel_2_in, o_noc_control_mode_channel_2_in;

    wire                    o_busy_channel_1_wgt;
    wire                    o_noc_write_valid_channel_1_wgt;
    wire [DA_CH1_WGT-1:0]   o_noc_write_addr_channel_1_wgt;
    wire [BW_CH1_WGT-1:0]   o_noc_write_data_channel_1_wgt;
    wire [DA_CH1_WGT-1:0]   o_noc_read_addr_channel_1_wgt;
    wire                    o_noc_read_valid_channel_1_wgt, o_noc_read_data_ready_channel_1_wgt;
    wire                    o_noc_control_mode_channel_1_wgt;

    wire                    o_busy_channel_2_wgt;
    wire                    o_noc_write_valid_channel_2_wgt;
    wire [DA_CH2_WGT-1:0]   o_noc_write_addr_channel_2_wgt;
    wire [BW_CH2_WGT-1:0]   o_noc_write_data_channel_2_wgt;
    wire                    o_noc_control_mode_channel_2_wgt;

    // ---- BIST <-> command interface ---------------------------------------
    reg  [63:0] r_command;
    reg         r_command_valid;
    wire        o_command_ready;

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
    ) u_l2 (
        .i_clk(i_clk), .i_rstb(i_rst_n),
        // channel 0 : idle
        .i_araddr_channel_0('0), .i_arvalid_channel_0(1'b0),
        .o_arready_channel_0(o_arready_channel_0), .i_arlen_channel_0(8'd0),
        .o_rdata_channel_0(o_rdata_channel_0), .o_rvalid_channel_0(o_rvalid_channel_0),
        .i_rready_channel_0(1'b1), .o_rlast_channel_0(o_rlast_channel_0),
        .i_awaddr_channel_0('0), .i_awvalid_channel_0(1'b0),
        .o_awready_channel_0(o_awready_channel_0), .i_awlen_channel_0(8'd0),
        .i_wdata_channel_0('0), .i_wvalid_channel_0(1'b0),
        .i_wlast_channel_0(1'b0), .o_wready_channel_0(o_wready_channel_0),
        .o_bvalid_channel_0(o_bvalid_channel_0), .i_bready_channel_0(1'b1),
        // TOP ctrl : driven by the BIST sequencer below
        .i_command(r_command), .i_command_valid(r_command_valid), .o_command_ready(o_command_ready),
        // channel 1 in -> adapter
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
        .i_noc_write_ready_channel_2_in(1'b1),
        .o_noc_write_valid_channel_2_in(o_noc_write_valid_channel_2_in),
        .o_noc_write_addr_channel_2_in(o_noc_write_addr_channel_2_in),
        .o_noc_write_data_channel_2_in(o_noc_write_data_channel_2_in),
        .i_noc_write_response_channel_2_in(1'b0),
        .o_noc_read_ready_channel_2_in(o_noc_read_ready_channel_2_in),
        .i_noc_read_valid_channel_2_in(1'b0),
        .i_noc_read_addr_channel_2_in(32'd0),
        .i_noc_read_data_channel_2_in({BW_CH2_IN{1'b0}}),
        .o_noc_read_response_channel_2_in(o_noc_read_response_channel_2_in),
        .o_noc_control_mode_channel_2_in(o_noc_control_mode_channel_2_in),
        // channel 1 wgt : tied off
        .o_busy_channel_1_wgt(o_busy_channel_1_wgt),
        .i_noc_write_ready_channel_1_wgt(1'b1),
        .o_noc_write_valid_channel_1_wgt(o_noc_write_valid_channel_1_wgt),
        .o_noc_write_addr_channel_1_wgt(o_noc_write_addr_channel_1_wgt),
        .o_noc_write_data_channel_1_wgt(o_noc_write_data_channel_1_wgt),
        .i_noc_write_response_channel_1_wgt(1'b0),
        .o_noc_read_addr_channel_1_wgt(o_noc_read_addr_channel_1_wgt),
        .o_noc_read_valid_channel_1_wgt(o_noc_read_valid_channel_1_wgt),
        .o_noc_read_data_ready_channel_1_wgt(o_noc_read_data_ready_channel_1_wgt),
        .i_noc_read_ready_channel_1_wgt(1'b1),
        .i_noc_read_response_channel_1_wgt(1'b0),
        .i_noc_read_data_channel_1_wgt({BW_CH1_WGT{1'b0}}),
        .o_noc_control_mode_channel_1_wgt(o_noc_control_mode_channel_1_wgt),
        // channel 2 wgt : tied off
        .o_busy_channel_2_wgt(o_busy_channel_2_wgt),
        .i_noc_write_ready_channel_2_wgt(1'b1),
        .o_noc_write_valid_channel_2_wgt(o_noc_write_valid_channel_2_wgt),
        .o_noc_write_addr_channel_2_wgt(o_noc_write_addr_channel_2_wgt),
        .o_noc_write_data_channel_2_wgt(o_noc_write_data_channel_2_wgt),
        .i_noc_write_response_channel_2_wgt(1'b0),
        .o_noc_control_mode_channel_2_wgt(o_noc_control_mode_channel_2_wgt)
    );

    // =====================================================================
    //  adapter + FIFO_intf  (identical to verif/integ/tb/tb_l2_noc_ch1_in.sv)
    // =====================================================================
    wire                     m_write_valid, m_write_ready, m_fifo_write_ready;
    wire [NOC_ADDR_BW-1:0]   m_write_addr;
    wire [BW_CH1_IN-1:0]     m_write_data;
    wire                     m_read_valid, m_read_ready, m_fifo_read_ready, m_data_fifo_ready;
    wire [NOC_ADDR_BW-1:0]   m_read_addr;
    wire [BW_CH1_IN-1:0]     m_read_data;
    wire                     m_control_mode;

    noc_ch1_in_adapter #(
        .DA_L2(DA_CH1_IN), .ADDR_BW(NOC_ADDR_BW), .DW(BW_CH1_IN)
    ) u_adapter (
        .l2_noc_write_valid(o_noc_write_valid_channel_1_in), .l2_noc_write_addr(o_noc_write_addr_channel_1_in),
        .l2_noc_write_data(o_noc_write_data_channel_1_in),   .l2_noc_write_ready(i_noc_write_ready_channel_1_in),
        .l2_noc_write_response(i_noc_write_response_channel_1_in),
        .l2_noc_read_valid(o_noc_read_valid_channel_1_in),   .l2_noc_read_addr(o_noc_read_addr_channel_1_in),
        .l2_noc_read_data_ready(o_noc_read_data_ready_channel_1_in),
        .l2_noc_read_ready(i_noc_read_ready_channel_1_in),   .l2_noc_read_response(i_noc_read_response_channel_1_in),
        .l2_noc_read_data(i_noc_read_data_channel_1_in),
        .l2_noc_control_mode(o_noc_control_mode_channel_1_in),
        .m_write_valid(m_write_valid), .m_write_addr(m_write_addr), .m_write_data(m_write_data),
        .m_write_ready(m_write_ready), .m_fifo_write_ready(m_fifo_write_ready),
        .m_read_valid(m_read_valid), .m_read_addr(m_read_addr),
        .m_read_ready(m_read_ready), .m_read_data(m_read_data),
        .m_fifo_read_ready(m_fifo_read_ready), .m_data_fifo_ready(m_data_fifo_ready),
        .m_control_mode(m_control_mode)
    );

    FIFO_intf #(
        .ADDR_DEPTH(NOC_ADDR_DEPTH), .DATA_WIDTH(BW_CH1_IN),
        .MEMORY_BITWIDTH(NOC_MEM_BW), .FIFO_DEPTH(NOC_FIFO_DEPTH),
        .INPUT_DELAY(NOC_IN_DELAY)
    ) u_noc (
        .clk(i_clk), .rstb(i_rst_n),
        .i_read_valid(m_read_valid),   .o_read_ready(m_read_ready),
        .i_read_addr(m_read_addr),     .o_read_data(m_read_data),
        .i_write_valid(m_write_valid), .o_write_ready(m_write_ready),
        .i_write_addr(m_write_addr),   .i_write_data(m_write_data),
        .i_control_mode(m_control_mode),
        .o_FIFO_read_ready(m_fifo_read_ready), .o_FIFO_write_ready(m_fifo_write_ready),
        .i_data_fifo_ready(m_data_fifo_ready)
    );

    // =====================================================================
    //  BIST sequencer  -  RTL equivalent of tb_l2_noc_ch1_in.sv's
    //  initial-block stimulus (STEP A store, STEP B load, compare)
    // =====================================================================
    localparam S_RESET      = 4'd0,
               S_SEND_STORE = 4'd1,
               S_WAIT_STORE_BUSY_HI = 4'd2,
               S_WAIT_STORE_BUSY_LO = 4'd3,
               S_GAP        = 4'd8,   // matches tb_l2_noc_ch1_in.sv's 10-cycle gap
               S_SEND_LOAD  = 4'd4,
               S_WAIT_LOAD_BUSY_HI  = 4'd5,
               S_WAIT_LOAD_BUSY_LO  = 4'd6,
               S_DONE       = 4'd7;

    (* mark_debug = "true" *) reg [3:0]  r_state;
    (* mark_debug = "true" *) reg [2:0]  r_beat_cnt;      // NOC write beats seen during LOAD
    (* mark_debug = "true" *) reg [2:0]  r_mismatch_cnt;
    (* mark_debug = "true" *) reg        r_done;
    reg [3:0]  r_gap_cnt;

    // Built with explicit per-field bit-slice assignment (not one big
    // concatenation - a hand-counted concatenation of this many fields is
    // exactly the kind of off-by-a-few-bits mistake that's easy to make
    // and hard to spot; this mirrors tb_l2_noc_ch1_in.sv's proven, already
    // simulation-validated command construction field-for-field).
    function automatic [63:0] mk_cmd_store(input [12:0] src_addr);
        reg [63:0] c;
        begin
            c = 64'd0;
            c[62:60] = 3'b010;         // cmd_idx : ch1_In store
            c[59:58] = 2'b10;          // ctrl_mode : burst store
            c[57:41] = 17'd0;          // destination_start_addr (L2 SRAM)  = 0
            c[40:27] = 14'(N_BEATS-1); // destination_write_addr (beats-1)
            c[26:13] = 14'(src_addr);  // source_start_addr (NOC local addr)
            mk_cmd_store = c;
        end
    endfunction

    function automatic [63:0] mk_cmd_load(input [10:0] dst_addr);
        reg [63:0] c;
        begin
            c = 64'd0;
            c[62:60] = 3'b001;         // cmd_idx : ch1_In load
            c[59:58] = 2'b00;          // ctrl_mode : burst load
            c[57]    = 1'b0;           // prec_mode (unused for ch1_in)
            c[56:40] = 17'd0;          // source_start_addr (L2 SRAM)       = 0
            c[39:29] = 11'(N_BEATS-1); // source_read_addr (beats-1)
            c[28:18] = 11'(dst_addr);  // destination_start_addr (NOC local addr)
            c[14:7]  = 8'h01;          // multicast
            mk_cmd_load = c;
        end
    endfunction

    wire [63:0] w_cmd_store = mk_cmd_store(BIST_SRC);
    wire [63:0] w_cmd_load  = mk_cmd_load(BIST_DST);

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_state         <= S_RESET;
            r_command       <= 64'd0;
            r_command_valid <= 1'b0;
            r_beat_cnt      <= 3'd0;
            r_mismatch_cnt  <= 3'd0;
            r_done          <= 1'b0;
        end
        else begin
            case (r_state)
                S_RESET: begin
                    r_command       <= w_cmd_store;
                    r_command_valid <= 1'b1;
                    r_state         <= S_SEND_STORE;
                end
                S_SEND_STORE: begin
                    if (o_command_ready) begin
                        r_command_valid <= 1'b0;
                        r_state         <= S_WAIT_STORE_BUSY_HI;
                    end
                end
                S_WAIT_STORE_BUSY_HI: if (o_busy_channel_1_in) r_state <= S_WAIT_STORE_BUSY_LO;
                S_WAIT_STORE_BUSY_LO: if (!o_busy_channel_1_in) begin
                    r_gap_cnt <= 4'd0;
                    r_state   <= S_GAP;
                end
                S_GAP: begin
                    if (r_gap_cnt == 4'd9) begin
                        r_command       <= w_cmd_load;
                        r_command_valid <= 1'b1;
                        r_state         <= S_SEND_LOAD;
                    end
                    else r_gap_cnt <= r_gap_cnt + 4'd1;
                end
                S_SEND_LOAD: begin
                    if (o_command_ready) begin
                        r_command_valid <= 1'b0;
                        r_state         <= S_WAIT_LOAD_BUSY_HI;
                    end
                end
                S_WAIT_LOAD_BUSY_HI: if (o_busy_channel_1_in) r_state <= S_WAIT_LOAD_BUSY_LO;
                S_WAIT_LOAD_BUSY_LO: if (!o_busy_channel_1_in) begin
                    r_state <= S_DONE;
                    r_done  <= 1'b1;
                end
                S_DONE: ; // latch forever until reset
                default: r_state <= S_RESET;
            endcase

            // ---- beat monitor : runs throughout, only meaningful during LOAD ----
            if (o_noc_write_valid_channel_1_in && i_noc_write_ready_channel_1_in &&
                (r_state == S_WAIT_LOAD_BUSY_HI || r_state == S_WAIT_LOAD_BUSY_LO)) begin
                if (o_noc_write_data_channel_1_in[31:0] !== (PAT_BASE + {29'd0, r_beat_cnt}))
                    r_mismatch_cnt <= r_mismatch_cnt + 3'd1;
                r_beat_cnt <= r_beat_cnt + 3'd1;
            end
        end
    end

    assign o_led_done       = r_done;
    assign o_led_pass       = r_done && (r_mismatch_cnt == 3'd0);
    assign o_mismatch_count = r_mismatch_cnt;

endmodule
