`timescale 1ns/1ps
// BB-only control (256b blackbox_ip + blackbox_nl). Unknown / removed addresses return SLVERR.
//
//  ---- CH1 blackbox (blackbox_ip) ----
//  0x20 CTRL      W: bit0 START (pulse), bit1 INJECT (Golden beat 0 bit0 flip)   R: {inject,0}
//  0x24 IN        {in_len[27:16], in_base[10:0]}    L1 input  : len 0..2048, base+len <= 2048
//  0x28 OUT       {out_len[24:16], out_base[10:0]}  L1 output : len 0..256,  base+len <= 2048
//  0x2C LATENCY   clocks between input/weight read and output write
//  0x30 STATUS    R: {err_start_busy[3], 0, done[1], busy[0]}
//  0x40 CYCLES    R: clocks of the last job
//  0x44 GOLD_ADDR Golden BRAM row for the next COMMIT (auto-increment)
//  0x48 GOLD_COMMIT W: bit0 -> Golden[GOLD_ADDR] <= WIN, GOLD_ADDR++
//  0x4C WGT       {w_len[26:16], w_base[9:0]}       weight read : len 0..1024, base+len <= 1024
//  0x80~0x9C WIN  256b staging window (word k = bits [32k+31:32k]), shared by both Golden BRAMs
//
//  ---- CH2 blackbox (blackbox_nl) ----
//  0x120 CTRL2    W: bit0 START (pulse), bit1 INJECT, bit2 HS (ch2 store handshake), bit3 PREC (addr field)
//                 R: {prec, hs, inject, 0}
//  0x124 IN2      {in_len[27:16], in_base[10:0]}    input memory : len 0..2048, base+len <= 2048
//  0x128 SHAPE2   {nb[30:24], h[19:10], w[9:0]}     output beats = nb*h*w <= 256
//  0x12C LATENCY2
//  0x130 STATUS2  R: {err_start_busy[3], dbg_valid[2], done[1], busy[0]}
//  0x140 CYCLES2  R
//  0x144 GOLD_ADDR2
//  0x148 GOLD_COMMIT2 W: bit0 -> Golden2[GOLD_ADDR2] <= WIN, GOLD_ADDR2++
//  0x14C WGT2     {w_len[25:16], w_base[8:0]}       weight memory : len 0..512, base+len <= 512
//  0x150 DBG2     W: {sel[16], row[10:0]} -> read one row (sel 0 = input memory, 1 = weight memory)
//                 R: last value written
//  0x160~0x17C DBG2_DATA  R: the row read by DBG2 (valid when STATUS2.dbg_valid = 1)
module axi_lite_bb_ctrl #(
    parameter int ADDR_W = 12,
    parameter int DW     = 256,      // Golden BRAM width
    parameter int L1_AW  = 11,
    parameter int W_AW   = 10,
    parameter int BAW    = 8,
    parameter int W2_AW  = 9,
    localparam int IN_LW  = L1_AW + 1,
    localparam int W_LW   = W_AW + 1,
    localparam int W2_LW  = W2_AW + 1,
    localparam int OUT_LW = BAW + 1
)(
    input  wire              clk,
    input  wire              rstn,

    // ---- AXI4-Lite slave --------------------------------------------------
    input  wire [ADDR_W-1:0] s_axil_awaddr,
    input  wire [2:0]        s_axil_awprot,
    input  wire              s_axil_awvalid,
    output wire              s_axil_awready,
    input  wire [31:0]       s_axil_wdata,
    input  wire [3:0]        s_axil_wstrb,
    input  wire              s_axil_wvalid,
    output wire              s_axil_wready,
    output reg  [1:0]        s_axil_bresp,
    output reg               s_axil_bvalid,
    input  wire              s_axil_bready,
    input  wire [ADDR_W-1:0] s_axil_araddr,
    input  wire [2:0]        s_axil_arprot,
    input  wire              s_axil_arvalid,
    output wire              s_axil_arready,
    output reg  [31:0]       s_axil_rdata,
    output reg  [1:0]        s_axil_rresp,
    output reg               s_axil_rvalid,
    input  wire              s_axil_rready,

    input wire i_start_allowed,  // CH1 admission, not a duplicate L2 status register
    input wire i_start_allowed2, // CH2 admission
    // ---- CH1 Blackbox control -------------------------------------------------
    output reg               o_bb_start,
    output wire              o_bb_inject,
    output wire [L1_AW-1:0]  o_bb_in_base,
    output wire [IN_LW-1:0]  o_bb_in_len,
    output wire [W_AW-1:0]   o_bb_w_base,
    output wire [W_LW-1:0]   o_bb_w_len,
    output wire [L1_AW-1:0]  o_bb_out_base,
    output wire [OUT_LW-1:0] o_bb_out_len,
    output wire [31:0]       o_bb_latency,
    output reg               o_gold_we,
    output reg  [BAW-1:0]    o_gold_addr,
    output wire [DW-1:0]     o_gold_wdata,      // also Golden2 write data

    // ---- CH1 Blackbox status --------------------------------------------------
    input  wire              i_bb_busy,
    input  wire              i_bb_done,
    input  wire              i_bb_err_start_busy,
    input  wire [31:0]       i_bb_cycle_cnt,

    // ---- CH2 Blackbox control -------------------------------------------------
    output reg               o_bb2_start,
    output reg               o_bb2_dbg_req,
    output wire              o_bb2_dbg_sel,
    output wire [L1_AW-1:0]  o_bb2_dbg_row,
    output wire              o_bb2_inject,
    output wire              o_bb2_hs,
    output wire              o_bb2_prec,
    output wire [L1_AW-1:0]  o_bb2_in_base,
    output wire [IN_LW-1:0]  o_bb2_in_len,
    output wire [W2_AW-1:0]  o_bb2_w_base,
    output wire [W2_LW-1:0]  o_bb2_w_len,
    output wire [9:0]        o_bb2_h,
    output wire [9:0]        o_bb2_w,
    output wire [6:0]        o_bb2_nb,
    output wire [31:0]       o_bb2_latency,
    output reg               o_gold2_we,
    output reg  [BAW-1:0]    o_gold2_addr,

    // ---- CH2 Blackbox status --------------------------------------------------
    input  wire              i_bb2_busy,
    input  wire              i_bb2_done,
    input  wire              i_bb2_err_start_busy,
    input  wire [31:0]       i_bb2_cycle_cnt,
    input  wire              i_bb2_dbg_valid,
    input  wire [DW-1:0]     i_bb2_dbg_data
);

    localparam int NWIN = DW / 32;   // 8

    // ---- registers --------------------------------------------------------------
    reg        r_inject;
    reg [31:0] r_bb_in, r_bb_out, r_bb_lat, r_bb_w;
    reg [BAW-1:0] r_gold_addr;
    reg [31:0] r_win [0:NWIN-1];
    reg [3:1]  r_ctrl2;                       // {prec, hs, inject}
    reg [31:0] r_bb2_in, r_bb2_shape, r_bb2_lat, r_bb2_w, r_bb2_dbg;
    reg [BAW-1:0] r_gold2_addr;

    assign o_bb_inject   = r_inject;
    assign o_bb_in_base  = r_bb_in[L1_AW-1:0];
    assign o_bb_in_len   = r_bb_in[16 +: IN_LW];
    assign o_bb_out_base = r_bb_out[L1_AW-1:0];
    assign o_bb_out_len  = r_bb_out[16 +: OUT_LW];
    assign o_bb_w_base   = r_bb_w[W_AW-1:0];
    assign o_bb_w_len    = r_bb_w[16 +: W_LW];
    assign o_bb_latency  = r_bb_lat;

    assign o_bb2_inject  = r_ctrl2[1];
    assign o_bb2_hs      = r_ctrl2[2];
    assign o_bb2_prec    = r_ctrl2[3];
    assign o_bb2_in_base = r_bb2_in[L1_AW-1:0];
    assign o_bb2_in_len  = r_bb2_in[16 +: IN_LW];
    assign o_bb2_w_base  = r_bb2_w[W2_AW-1:0];
    assign o_bb2_w_len   = r_bb2_w[16 +: W2_LW];
    assign o_bb2_w       = r_bb2_shape[9:0];
    assign o_bb2_h       = r_bb2_shape[19:10];
    assign o_bb2_nb      = r_bb2_shape[30:24];
    assign o_bb2_latency = r_bb2_lat;
    assign o_bb2_dbg_row = r_bb2_dbg[L1_AW-1:0];
    assign o_bb2_dbg_sel = r_bb2_dbg[16];

    genvar gi;
    generate
        for (gi = 0; gi < NWIN; gi = gi + 1) begin : g_win
            assign o_gold_wdata[gi*32 +: 32] = r_win[gi];
        end
    endgenerate

    // ---- AXI write channel --------------------------------------------------------
    reg              aw_full, w_full;
    reg [ADDR_W-1:0] aw_addr_q;
    reg [31:0]       w_data_q;
    reg [3:0]        w_strb_q;

    assign s_axil_awready = rstn && !aw_full && !s_axil_bvalid;
    assign s_axil_wready  = rstn && !w_full  && !s_axil_bvalid;


    wire       do_write = aw_full && w_full && !s_axil_bvalid;
    wire [ADDR_W-1:0] w_off = aw_addr_q;
    wire [ADDR_W-1:0] r_off = s_axil_araddr;
    wire       pulse_b0 = w_strb_q[0] && w_data_q[0];

    function automatic [31:0] strb_merge(input [31:0] old_v, input [31:0] new_v, input [3:0] s);
        strb_merge = { s[3] ? new_v[31:24] : old_v[31:24],
                       s[2] ? new_v[23:16] : old_v[23:16],
                       s[1] ? new_v[15:8]  : old_v[15:8],
                       s[0] ? new_v[7:0]   : old_v[7:0] };
    endfunction

    localparam int WIN_LAST  = 'h80  + 4*(NWIN-1);   // 0x9C
    localparam int DBG_LAST  = 'h160 + 4*(NWIN-1);   // 0x17C

    wire window_write = w_off >= 'h80 && w_off <= WIN_LAST && w_off[1:0] == 0;
    wire bank1_write  = w_off=='h20 || w_off=='h24 || w_off=='h28 || w_off=='h2C ||
                        w_off=='h44 || w_off=='h48 || w_off=='h4C;
    wire bank2_write  = w_off=='h120 || w_off=='h124 || w_off=='h128 || w_off=='h12C ||
                        w_off=='h144 || w_off=='h148 || w_off=='h14C || w_off=='h150;
    wire write_known  = window_write || bank1_write || bank2_write;

    wire bounds_ok = o_bb_in_len  <= (1 << L1_AW) && o_bb_out_len <= (1 << BAW) &&
                     o_bb_w_len   <= (1 << W_AW)  &&
        ({1'b0,o_bb_in_base}  + (L1_AW+1)'(o_bb_in_len)  <= (1 << L1_AW)) &&
        ({1'b0,o_bb_out_base} + (L1_AW+1)'(o_bb_out_len) <= (1 << L1_AW)) &&
        ({1'b0,o_bb_w_base}   + (W_AW+1)'(o_bb_w_len)    <= (1 << W_AW));
    // nb*h*w, 2 pipeline registers (timing). SHAPE2 is written at least 3 clocks before any
    // later write can reach do_write (B response -> next AW/W), so START2 always sees the new value.
    reg  [19:0] r_hw2;
    reg  [26:0] r_nbeats2;
    always @(posedge clk) begin
        r_hw2     <= o_bb2_h * o_bb2_w;
        r_nbeats2 <= o_bb2_nb * r_hw2;
    end
    wire bounds2_ok = o_bb2_in_len <= (1 << L1_AW) && o_bb2_w_len <= (1 << W2_AW) &&
                      r_nbeats2 <= (1 << BAW) &&
        ({1'b0,o_bb2_in_base} + (L1_AW+1)'(o_bb2_in_len) <= (1 << L1_AW)) &&
        ({1'b0,o_bb2_w_base}  + (W2_AW+1)'(o_bb2_w_len)  <= (1 << W2_AW));
    // DBG2 request : row inside the selected memory
    wire dbg_row_ok = w_data_q[16] ? (w_data_q[L1_AW-1:0] < (1 << W2_AW)) : 1'b1;

    // Freeze each bank's configuration while that blackbox runs; the window is shared.
    wire busy_any  = i_bb_busy || o_bb_start || i_bb2_busy || o_bb2_start || o_bb2_dbg_req;
    wire write_bad = !write_known ||
        (bank1_write  && (i_bb_busy  || o_bb_start)) ||
        (bank2_write  && (i_bb2_busy || o_bb2_start || o_bb2_dbg_req)) ||
        (window_write && busy_any) ||
        (w_off=='h20  && pulse_b0 && (!bounds_ok  || !i_start_allowed)) ||
        (w_off=='h120 && pulse_b0 && (!bounds2_ok || !i_start_allowed2)) ||
        (w_off=='h150 && (!dbg_row_ok || !i_start_allowed2));
    wire read_known = (r_off >= 'h80 && r_off <= WIN_LAST && r_off[1:0]==0) ||
        (r_off >= 'h160 && r_off <= DBG_LAST && r_off[1:0]==0) ||
        r_off=='h20  || r_off=='h24  || r_off=='h28  || r_off=='h2C  ||
        r_off=='h30  || r_off=='h40  || r_off=='h44  || r_off=='h4C  ||
        r_off=='h120 || r_off=='h124 || r_off=='h128 || r_off=='h12C ||
        r_off=='h130 || r_off=='h140 || r_off=='h144 || r_off=='h14C || r_off=='h150;
    initial begin
        if (ADDR_W!=12 || DW!=256 || L1_AW!=11 || W_AW!=10 || BAW!=8 || W2_AW!=9)
            $fatal(1,"BB register layout requires 12/256/11/10/8/9 parameters");
    end

    integer i;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            aw_full <= 1'b0; w_full <= 1'b0; s_axil_bvalid <= 1'b0; s_axil_bresp <= 0;
            aw_addr_q <= '0; w_data_q <= '0; w_strb_q <= '0;
            r_inject <= 1'b0; r_bb_in <= '0; r_bb_out <= '0; r_bb_lat <= '0; r_bb_w <= '0;
            r_gold_addr <= '0;
            r_ctrl2 <= '0; r_bb2_in <= '0; r_bb2_shape <= '0; r_bb2_lat <= '0; r_bb2_w <= '0;
            r_bb2_dbg <= '0; r_gold2_addr <= '0;
            for (i = 0; i < NWIN; i = i + 1) r_win[i] <= '0;
            o_bb_start <= 1'b0; o_bb2_start <= 1'b0; o_bb2_dbg_req <= 1'b0;
            o_gold_we <= 1'b0; o_gold_addr <= '0;
            o_gold2_we <= 1'b0; o_gold2_addr <= '0;
        end else begin
            // one-clock pulses
            o_bb_start    <= 1'b0;
            o_bb2_start   <= 1'b0;
            o_bb2_dbg_req <= 1'b0;
            o_gold_we     <= 1'b0;
            o_gold2_we    <= 1'b0;


            if (s_axil_awvalid && s_axil_awready) begin aw_full <= 1'b1; aw_addr_q <= s_axil_awaddr; end
            if (s_axil_wvalid  && s_axil_wready)  begin w_full  <= 1'b1; w_data_q <= s_axil_wdata; w_strb_q <= s_axil_wstrb; end
            if (s_axil_bvalid  && s_axil_bready)  s_axil_bvalid <= 1'b0;

            if (do_write) begin
                aw_full <= 1'b0;
                w_full  <= 1'b0;
                s_axil_bvalid <= 1'b1;
                s_axil_bresp <= (w_strb_q!=0 && write_bad) ? 2'b10 : 2'b00;
                if (w_strb_q!=0 && !write_bad) case (w_off)
                    // ---- CH1 ----
                    12'h020: begin
                        if (w_strb_q[0]) r_inject <= w_data_q[1];
                        if (pulse_b0)    o_bb_start <= 1'b1;
                    end
                    12'h024: r_bb_in  <= strb_merge(r_bb_in,  w_data_q, w_strb_q);
                    12'h028: r_bb_out <= strb_merge(r_bb_out, w_data_q, w_strb_q);
                    12'h02C: r_bb_lat <= strb_merge(r_bb_lat, w_data_q, w_strb_q);
                    12'h044: if (w_strb_q[0]) r_gold_addr <= w_data_q[BAW-1:0];
                    12'h048: if (pulse_b0) begin
                        o_gold_we   <= 1'b1;
                        o_gold_addr <= r_gold_addr;
                        r_gold_addr <= r_gold_addr + 1'b1;
                    end
                    12'h04C: r_bb_w   <= strb_merge(r_bb_w,   w_data_q, w_strb_q);
                    // ---- CH2 ----
                    12'h120: begin
                        if (w_strb_q[0]) r_ctrl2 <= w_data_q[3:1];
                        if (pulse_b0)    o_bb2_start <= 1'b1;
                    end
                    12'h124: r_bb2_in    <= strb_merge(r_bb2_in,    w_data_q, w_strb_q);
                    12'h128: r_bb2_shape <= strb_merge(r_bb2_shape, w_data_q, w_strb_q);
                    12'h12C: r_bb2_lat   <= strb_merge(r_bb2_lat,   w_data_q, w_strb_q);
                    12'h144: if (w_strb_q[0]) r_gold2_addr <= w_data_q[BAW-1:0];
                    12'h148: if (pulse_b0) begin
                        o_gold2_we   <= 1'b1;
                        o_gold2_addr <= r_gold2_addr;
                        r_gold2_addr <= r_gold2_addr + 1'b1;
                    end
                    12'h14C: r_bb2_w     <= strb_merge(r_bb2_w,     w_data_q, w_strb_q);
                    12'h150: begin
                        r_bb2_dbg <= strb_merge(r_bb2_dbg, w_data_q, w_strb_q);
                        o_bb2_dbg_req <= 1'b1;
                    end
                    default: begin
                        if (window_write)
                            r_win[w_off[4:2]] <= strb_merge(r_win[w_off[4:2]], w_data_q, w_strb_q);
                    end
                endcase
            end
        end
    end

    // ---- AXI read channel ----------------------------------------------------------
    assign s_axil_arready = rstn && !s_axil_rvalid;


    reg  [31:0] rmux;
    always @(*) begin
        rmux = 32'd0;
        case (r_off)
            12'h020: rmux = {30'd0, r_inject, 1'b0};
            12'h024: rmux = r_bb_in;
            12'h028: rmux = r_bb_out;
            12'h02C: rmux = r_bb_lat;
            12'h030: rmux = {28'd0, i_bb_err_start_busy, 1'b0, i_bb_done, i_bb_busy};
            12'h040: rmux = i_bb_cycle_cnt;
            12'h044: rmux = {24'd0, r_gold_addr};
            12'h04C: rmux = r_bb_w;
            12'h120: rmux = {28'd0, r_ctrl2, 1'b0};
            12'h124: rmux = r_bb2_in;
            12'h128: rmux = r_bb2_shape;
            12'h12C: rmux = r_bb2_lat;
            12'h130: rmux = {28'd0, i_bb2_err_start_busy, i_bb2_dbg_valid, i_bb2_done, i_bb2_busy};
            12'h140: rmux = i_bb2_cycle_cnt;
            12'h144: rmux = {24'd0, r_gold2_addr};
            12'h14C: rmux = r_bb2_w;
            12'h150: rmux = r_bb2_dbg;
            default: begin
                if (r_off >= 'h80  && r_off <= WIN_LAST) rmux = r_win[r_off[4:2]];
                if (r_off >= 'h160 && r_off <= DBG_LAST) rmux = i_bb2_dbg_data[r_off[4:2]*32 +: 32];
            end
        endcase
    end

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            s_axil_rvalid <= 1'b0;
            s_axil_rresp <= 0;
            s_axil_rdata  <= '0;
        end else begin
            if (s_axil_arvalid && s_axil_arready) begin
                s_axil_rvalid <= 1'b1;
                s_axil_rdata  <= read_known ? rmux : 0;
                s_axil_rresp <= read_known ? 2'b00 : 2'b10;
            end else if (s_axil_rvalid && s_axil_rready)
                s_axil_rvalid <= 1'b0;
        end
    end

endmodule
