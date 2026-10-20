`timescale 1ns/1ps
// BB-only control. Removed L2 command addresses return SLVERR.
module axi_lite_bb_ctrl #(
    parameter int ADDR_W = 12,
    parameter int DW     = 512,      // Blackbox BRAM width
    parameter int L1_AW  = 11,
    parameter int BAW    = 8,
    localparam int LW    = BAW + 1
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

    input wire i_start_allowed, // system admission, not a duplicate L2 status register
    // ---- Blackbox control -----------------------------------------------------
    output reg               o_bb_start,
    output wire [1:0]        o_bb_inject,
    output wire [L1_AW-1:0]  o_bb_in_base,
    output wire [LW-1:0]     o_bb_in_len,
    output wire [L1_AW-1:0]  o_bb_out_base,
    output wire [LW-1:0]     o_bb_out_len,
    output wire [31:0]       o_bb_latency,
    output reg               o_bram_we,
    output reg               o_bram_sel,
    output reg  [BAW-1:0]    o_bram_addr,
    output wire [DW-1:0]     o_bram_wdata,

    // ---- Blackbox status ------------------------------------------------------
    input  wire              i_bb_busy,
    input  wire              i_bb_done,
    input  wire              i_bb_first_mm_valid,
    input  wire              i_bb_err_start_busy,
    input  wire [15:0]       i_bb_mismatch_cnt,
    input  wire [15:0]       i_bb_first_mm_idx,
    input  wire [31:0]       i_bb_first_mm_got,
    input  wire [31:0]       i_bb_first_mm_exp,
    input  wire [31:0]       i_bb_cycle_cnt
);

    localparam int NWIN = DW / 32;   // 16

    // ---- registers --------------------------------------------------------------
    reg [1:0]  r_inject;
    reg [31:0] r_bb_in, r_bb_out, r_bb_lat;
    reg [BAW-1:0] r_bram_addr;
    reg        r_bram_sel;
    reg [31:0] r_win [0:NWIN-1];

    assign o_bb_inject   = r_inject;
    assign o_bb_in_base  = r_bb_in[L1_AW-1:0];
    assign o_bb_in_len   = r_bb_in[16 +: LW];
    assign o_bb_out_base = r_bb_out[L1_AW-1:0];
    assign o_bb_out_len  = r_bb_out[16 +: LW];
    assign o_bb_latency  = r_bb_lat;

    genvar gi;
    generate
        for (gi = 0; gi < NWIN; gi = gi + 1) begin : g_win
            assign o_bram_wdata[gi*32 +: 32] = r_win[gi];
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
    wire       pulse_b0 = w_strb_q[0] && w_data_q[0];

    function automatic [31:0] strb_merge(input [31:0] old_v, input [31:0] new_v, input [3:0] s);
        strb_merge = { s[3] ? new_v[31:24] : old_v[31:24],
                       s[2] ? new_v[23:16] : old_v[23:16],
                       s[1] ? new_v[15:8]  : old_v[15:8],
                       s[0] ? new_v[7:0]   : old_v[7:0] };
    endfunction


    wire window_write = w_off >= 'h80 && w_off <= 'hBC && w_off[1:0] == 0;
    wire write_known = window_write || w_off=='h20 || w_off=='h24 ||
                       w_off=='h28 || w_off=='h2C || w_off=='h44 || w_off=='h48;
    wire bounds_ok = o_bb_in_len <= 256 && o_bb_out_len <= 256 &&
        ({1'b0,o_bb_in_base} + 12'(o_bb_in_len) <= 2048) &&
        ({1'b0,o_bb_out_base} + 12'(o_bb_out_len) <= 2048);
    // Freeze configuration and payload staging during execution/start pipeline.
    wire write_bad = !write_known || i_bb_busy || o_bb_start ||
        (w_off=='h20 && pulse_b0 && (!bounds_ok || !i_start_allowed));
    wire read_known = (r_off >= 'h80 && r_off <= 'hBC && r_off[1:0]==0) ||
        r_off=='h20 || r_off=='h24 || r_off=='h28 || r_off=='h2C ||
        r_off=='h30 || r_off=='h34 || r_off=='h38 || r_off=='h3C ||
        r_off=='h40 || r_off=='h44;
    initial begin
        if (ADDR_W!=12 || DW!=512 || L1_AW!=11 || BAW!=8)
            $fatal(1,"BB register layout requires 12/512/11/8 parameters");
    end

    integer i;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            aw_full <= 1'b0; w_full <= 1'b0; s_axil_bvalid <= 1'b0; s_axil_bresp <= 0;
            aw_addr_q <= '0; w_data_q <= '0; w_strb_q <= '0;
            r_inject <= '0; r_bb_in <= '0; r_bb_out <= '0; r_bb_lat <= '0;
            r_bram_addr <= '0; r_bram_sel <= 1'b0;
            for (i = 0; i < NWIN; i = i + 1) r_win[i] <= '0;
            o_bb_start <= 1'b0;
            o_bram_we <= 1'b0; o_bram_sel <= 1'b0; o_bram_addr <= '0;
        end else begin
            // one-clock pulses
            o_bb_start      <= 1'b0;
            o_bram_we       <= 1'b0;


            if (s_axil_awvalid && s_axil_awready) begin aw_full <= 1'b1; aw_addr_q <= s_axil_awaddr; end
            if (s_axil_wvalid  && s_axil_wready)  begin w_full  <= 1'b1; w_data_q <= s_axil_wdata; w_strb_q <= s_axil_wstrb; end
            if (s_axil_bvalid  && s_axil_bready)  s_axil_bvalid <= 1'b0;

            if (do_write) begin
                aw_full <= 1'b0;
                w_full  <= 1'b0;
                s_axil_bvalid <= 1'b1;
                s_axil_bresp <= (w_strb_q!=0 && write_bad) ? 2'b10 : 2'b00;
                if (w_strb_q!=0 && !write_bad) case (w_off)
                    8'h20: begin
                        if (w_strb_q[0]) r_inject <= w_data_q[2:1];
                        if (pulse_b0)    o_bb_start <= 1'b1;
                    end
                    8'h24: r_bb_in  <= strb_merge(r_bb_in,  w_data_q, w_strb_q);
                    8'h28: r_bb_out <= strb_merge(r_bb_out, w_data_q, w_strb_q);
                    8'h2C: r_bb_lat <= strb_merge(r_bb_lat, w_data_q, w_strb_q);
                    8'h44: begin
                        if (w_strb_q[0]) r_bram_addr <= w_data_q[BAW-1:0];
                        if (w_strb_q[1]) r_bram_sel  <= w_data_q[8];
                    end
                    8'h48: if (pulse_b0) begin
                        o_bram_we   <= 1'b1;
                        o_bram_sel  <= r_bram_sel;
                        o_bram_addr <= r_bram_addr;
                        r_bram_addr <= r_bram_addr + 1'b1;
                    end
                    default: begin
                        if (w_off >= 8'h80 && w_off <= 8'hBC)
                            r_win[w_off[5:2]] <= strb_merge(r_win[w_off[5:2]], w_data_q, w_strb_q);
                    end
                endcase
            end
        end
    end

    // ---- AXI read channel ----------------------------------------------------------
    assign s_axil_arready = rstn && !s_axil_rvalid;


    wire [ADDR_W-1:0] r_off = s_axil_araddr;
    reg  [31:0] rmux;
    always @(*) begin
        rmux = 32'd0;
        case (r_off)
            8'h20: rmux = {29'd0, r_inject, 1'b0};
            8'h24: rmux = r_bb_in;
            8'h28: rmux = r_bb_out;
            8'h2C: rmux = r_bb_lat;
            8'h30: rmux = {28'd0, i_bb_err_start_busy, i_bb_first_mm_valid, i_bb_done, i_bb_busy};
            8'h34: rmux = {i_bb_first_mm_idx, i_bb_mismatch_cnt};
            8'h38: rmux = i_bb_first_mm_got;
            8'h3C: rmux = i_bb_first_mm_exp;
            8'h40: rmux = i_bb_cycle_cnt;
            8'h44: rmux = {23'd0, r_bram_sel, r_bram_addr};
            default: if (r_off >= 8'h80 && r_off <= 8'hBC) rmux = r_win[r_off[5:2]];
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
