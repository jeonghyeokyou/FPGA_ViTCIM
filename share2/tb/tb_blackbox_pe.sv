`timescale 1ns/1ps
// =============================================================================
//  tb_blackbox_pe  -  Phase 1 : blackbox_pe 단독 검증 (BLACKBOX_TASK.md 10절)
//
//  DUT : blackbox_pe + l1_port_mux + l1_sram   (NoC 쪽 포트는 idle 고정)
//  - L1 IN 영역은 backdoor (l1_sram 내부 sram_mimic.mem 에 직접 대입)
//  - Expected / Golden 은 BRAM 적재 포트로 넣는다
//  - 벡터 : vectors/seed1 (gen_vectors.py) , U7 은 TB 가 만든 256 beat 난수
//
//  U1 기본          U2 inject[1]      U3 inject[0]      U4 latency 0/1/1000
//  U5 IN beat 37 변조 U6 noc_busy 중 START  U7 len 1/1, 256/256
// =============================================================================
module tb_blackbox_pe;
    import bb_pkg::*;

    localparam int DW = 512, L1_AW = 11, BRAM_DEPTH = 256, GUARD = 2;
    localparam int CLKP = 10;
    localparam string VEC = "../../vectors/seed1";

    logic clk = 0, rstn = 0;
    always #(CLKP/2) clk = ~clk;

    // ---- blackbox control ---------------------------------------------------
    logic             start = 0, noc_busy = 0;
    logic [10:0]      in_base = 0, out_base = 0;
    logic [8:0]       in_len = 0, out_len = 0;
    logic [31:0]      latency = 0;
    logic [1:0]       inject = 0;
    logic             out_sel = 0, c2_prec = 0, c2_hs = 0;
    logic [9:0]       c2_h = 0, c2_w = 0;
    logic [6:0]       c2_nb = 0;
    wire              c2_valid;
    wire [31:0]       c2_addr;
    wire [DW/2-1:0]   c2_data;
    logic             c2_ready = 0, c2_resp = 0;
    logic             bram_we = 0, bram_sel = 0;
    logic [7:0]       bram_addr = 0;
    logic [DW-1:0]    bram_wdata = '0;

    wire              pe_busy, pe_ceb, pe_web;
    wire [L1_AW-1:0]  pe_addr;
    wire [DW-1:0]     pe_din, pe_dout;
    wire              bb_busy, bb_done, first_valid, err_start_busy;
    wire [15:0]       mm_cnt, first_idx;
    wire [31:0]       first_got, first_exp, cyc;

    // NoC side idle
    wire              sram_ceb, sram_web;
    wire [L1_AW-1:0]  sram_addr;
    wire [DW-1:0]     sram_din, sram_dout, noc_dout;

    blackbox_pe #(.DW(DW), .L1_AW(L1_AW), .BRAM_DEPTH(BRAM_DEPTH), .GUARD(GUARD)) dut (
        .clk(clk), .rstn(rstn),
        .i_start(start), .i_noc_busy(noc_busy),
        .i_in_base(in_base), .i_in_len(in_len), .i_out_base(out_base), .i_out_len(out_len),
        .i_latency(latency), .i_inject(inject),
        .i_out_sel(out_sel), .i_c2_prec(c2_prec), .i_c2_hs(c2_hs), .i_c2_h(c2_h), .i_c2_w(c2_w), .i_c2_nb(c2_nb),
        .o_c2_valid(c2_valid), .o_c2_addr(c2_addr), .o_c2_data(c2_data), .i_c2_ready(c2_ready), .i_c2_resp(c2_resp),
        .i_bram_we(bram_we), .i_bram_sel(bram_sel), .i_bram_addr(bram_addr), .i_bram_wdata(bram_wdata),
        .o_pe_busy(pe_busy), .o_ceb(pe_ceb), .o_web(pe_web), .o_addr(pe_addr), .o_din(pe_din), .i_dout(pe_dout),
        .o_busy(bb_busy), .o_done(bb_done),
        .o_mismatch_cnt(mm_cnt), .o_first_mm_idx(first_idx), .o_first_mm_valid(first_valid),
        .o_first_mm_got(first_got), .o_first_mm_exp(first_exp),
        .o_err_start_busy(err_start_busy), .o_cycle_cnt(cyc));

    l1_port_mux #(.ADDR_BW(L1_AW), .DATA_WIDTH(DW)) u_mux (
        .i_pe_busy(pe_busy),
        .i_noc_ceb(1'b1), .i_noc_web(1'b1), .i_noc_addr('0), .i_noc_din('0), .o_noc_dout(noc_dout),
        .i_pe_ceb(pe_ceb), .i_pe_web(pe_web), .i_pe_addr(pe_addr), .i_pe_din(pe_din), .o_pe_dout(pe_dout),
        .o_sram_ceb(sram_ceb), .o_sram_web(sram_web), .o_sram_addr(sram_addr), .o_sram_din(sram_din),
        .i_sram_dout(sram_dout), .o_pe_conflict());

    l1_sram #(.ADDR_DEPTH(2048), .DATA_WIDTH(DW), .MEMORY_BITWIDTH(128)) u_l1 (
        .i_clk(clk), .i_rstn(rstn), .i_ceb(sram_ceb), .i_web(sram_web), .i_addr(sram_addr),
        .i_din(sram_din), .o_dout(sram_dout));

    // ---- vectors -----------------------------------------------------------
    logic [DW-1:0] xv [0:NX-1];
    logic [DW-1:0] gv [0:NY-1];
    logic [DW-1:0] rin [0:255];
    logic [DW-1:0] rout[0:255];

    int errors = 0;
    int npass = 0, nfail = 0;
    string results[$];

    // ---- L1 backdoor ---------------------------------------------------------
    task automatic l1_poke(input int a, input logic [DW-1:0] d);
        u_l1.Usram_mimic_0.mem[a] = d[127:0];
        u_l1.Usram_mimic_1.mem[a] = d[255:128];
        u_l1.Usram_mimic_2.mem[a] = d[383:256];
        u_l1.Usram_mimic_3.mem[a] = d[511:384];
    endtask
    function automatic logic [DW-1:0] l1_peek(input int a);
        return {u_l1.Usram_mimic_3.mem[a], u_l1.Usram_mimic_2.mem[a],
                u_l1.Usram_mimic_1.mem[a], u_l1.Usram_mimic_0.mem[a]};
    endfunction

    // ---- BRAM load port ----------------------------------------------------
    task automatic bram_write(input bit sel, input int a, input logic [DW-1:0] d);
        @(negedge clk);
        bram_we = 1; bram_sel = sel; bram_addr = a[7:0]; bram_wdata = d;
        @(negedge clk);
        bram_we = 0;
    endtask

    task automatic do_reset();
        @(negedge clk); rstn = 0;
        repeat (5) @(negedge clk); rstn = 1;
        repeat (2) @(negedge clk);
    endtask

    task automatic load_seed_vectors();
        for (int k = 0; k < NX; k++) l1_poke(L1_IN_BASE + k, xv[k]);
        for (int k = 0; k < NX; k++) bram_write(0, k, xv[k]);
        for (int k = 0; k < NY; k++) bram_write(1, k, gv[k]);
    endtask

    // ---- one Blackbox job ----------------------------------------------------
    task automatic run_bb(input int ib, input int il, input int ob, input int ol,
                          input int lat, input logic [1:0] inj);
        int t;
        @(negedge clk);
        in_base = ib; in_len = il; out_base = ob; out_len = ol; latency = lat; inject = inj;
        start = 1;
        @(negedge clk);
        start = 0;
        t = 0;
        while (!bb_done) begin
            @(negedge clk);
            if (++t > 200000) begin $display("  !! timeout waiting for done"); errors++; break; end
        end
    endtask

    task automatic check(input string name, input bit cond, input string msg);
        if (cond) $display("    [ok]   %s : %s", name, msg);
        else begin $display("    [FAIL] %s : %s", name, msg); errors++; end
    endtask

    task automatic report(input string tname, input int e0, input string note);
        string s;
        s = $sformatf("%-4s | %-4s | %s", tname, (errors == e0) ? "PASS" : "FAIL", note);
        results.push_back(s);
        if (errors == e0) npass++; else nfail++;
    endtask

    // returns number of OUT beats that differ from ref
    function automatic int cmp_out(input int ob, input int n, ref logic [DW-1:0] refv[0:255], input int bit0_skip);
        int bad = 0;
        for (int k = 0; k < n; k++) begin
            logic [DW-1:0] got, e;
            got = l1_peek(ob + k);
            e   = refv[k];
            if (k == 0 && bit0_skip) e[0] = ~e[0];
            if (got !== e) bad++;
        end
        return bad;
    endfunction

    // ---- trace of the first RD_IN / WR_OUT cycles (Gate 1 timing evidence) ----
    // ---- ch2 store slave model (stands in for L2 ch2_in) -------------------
    //  burst : random ready, a beat is taken at a posedge with valid && ready
    //  hs    : like cmd_decoder_channel_2_in HANDSHAKE_STORE - capture valid, 1-clock response
    //          pulse on the next clock, then 0..2 idle clocks
    typedef struct { logic [31:0] addr; logic [DW/2-1:0] data; } c2_beat_t;
    c2_beat_t c2_got[$];
    bit       c2_model_on = 0;
    int       hs_idle = 0;
    always @(posedge clk) begin
        if (c2_model_on && !c2_hs) begin
            if (c2_valid && c2_ready) c2_got.push_back('{c2_addr, c2_data});
            c2_ready <= ($urandom % 3) != 0;
        end else if (c2_model_on && c2_hs) begin
            c2_resp <= 1'b0;
            if (hs_idle > 0) hs_idle <= hs_idle - 1;
            else if (c2_valid && !c2_resp) begin
                c2_got.push_back('{c2_addr, c2_data});
                c2_resp <= 1'b1;
                hs_idle <= 1 + ($urandom % 3);
            end
        end else begin
            c2_ready <= 1'b0;
            c2_resp  <= 1'b0;
        end
    end

    // expected beat list for a (H, W, NB) job : order (jp, h, w, col)
    task automatic c2_check(input string tag, input int H, input int W, input int NB, input bit prec,
                            ref logic [DW-1:0] g[0:255], input bit inj0);
        int n = 0, bad = 0;
        for (int jp = 0; jp < (NB + 1) / 2; jp++)
            for (int h = 0; h < H; h++)
                for (int w = 0; w < W; w++)
                    for (int col = 0; col < 2; col++) begin
                        logic [31:0] ea;
                        logic [DW/2-1:0] ed;
                        bit last;
                        if (2*jp + col >= NB) continue;
                        last = (jp == (NB+1)/2 - 1) && (h == H-1) && (w == W-1) && (col == 1 || 2*jp+1 >= NB);
                        ea = prec ? {last, 7'(jp), 1'(col), 3'd0, 10'(h), 10'(w)}
                                  : {last, 5'(jp), 1'(col), 5'd0, 10'(h), 10'(w)};
                        ed = col ? g[jp*H*W + h*W + w][DW-1:DW/2] : g[jp*H*W + h*W + w][DW/2-1:0];
                        if (n == 0 && inj0) ed[0] = ~ed[0];
                        if (n >= c2_got.size()) begin bad++; n++; continue; end
                        if (c2_got[n].addr !== ea || c2_got[n].data !== ed) begin
                            if (bad < 4) $display("    beat %0d : addr %08h data[31:0] %08h  want %08h %08h",
                                                  n, c2_got[n].addr, c2_got[n].data[31:0], ea, ed[31:0]);
                            bad++;
                        end
                        n++;
                    end
        check(tag, bad == 0 && c2_got.size() == n,
              $sformatf("%0d beats (want %0d), %0d bad (addr fields + data + last)", c2_got.size(), n, bad));
    endtask

    task automatic run_c2(input int H, input int W, input int NB, input bit prec, input bit hs, input logic [1:0] inj);
        c2_got = {};
        @(negedge clk);
        out_sel = 1; c2_prec = prec; c2_hs = hs; c2_h = H; c2_w = W; c2_nb = NB;
        c2_model_on = 1;
        run_bb(L1_IN_BASE, NX, 0, 0, 3, inj);
        repeat (5) @(negedge clk);
        c2_model_on = 0; out_sel = 0;
    endtask

    bit trace_on = 0;
    int trace_n  = 0;
    always @(posedge clk) if (trace_on && pe_busy && trace_n < 14) begin
        trace_n++;
        $display("    t=%0t st=%0d pe_busy=%0d ceb=%0d web=%0d addr=%0d | p2_v=%0d p2_idx=%0d dout[31:0]=%08h exp_q[31:0]=%08h",
                 $time, dut.st, pe_busy, sram_ceb, sram_web, sram_addr,
                 dut.p2_v, dut.p2_idx, pe_dout[31:0], dut.exp_q[31:0]);
    end

    // =========================================================================
    initial begin
        logic [DW-1:0] gref [0:255];
        int e0, c0, c1, c1000, bad;

        $readmemh({VEC, "/x.hex"}, xv);
        $readmemh({VEC, "/golden.hex"}, gv);
        for (int k = 0; k < 256; k++) gref[k] = (k < NY) ? gv[k] : '0;

        repeat (3) @(negedge clk);
        do_reset();

        // ------------------------------------------------------------- U1
        $display("\n=== U1 : basic  in 192 / out 16 / latency 10 ===");
        e0 = errors;
        load_seed_vectors();
        trace_on = 1; trace_n = 0;
        run_bb(L1_IN_BASE, NX, L1_OUT_BASE, NY, 10, 2'b00);
        trace_on = 0;
        check("U1", mm_cnt == 0, $sformatf("mismatch_cnt=%0d", mm_cnt));
        check("U1", !first_valid, "first_mm_valid=0");
        bad = cmp_out(L1_OUT_BASE, NY, gref, 0);
        check("U1", bad == 0, $sformatf("L1 OUT vs Golden : %0d/%0d beats bad", bad, NY));
        check("U1", bb_done && !bb_busy && !pe_busy, "done=1 busy=0 pe_busy=0");
        $display("    cycle_cnt=%0d", cyc);
        c0 = cyc;
        report("U1", e0, $sformatf("mismatch=%0d, OUT %0d/%0d, cycles=%0d", mm_cnt, NY-bad, NY, cyc));

        // ------------------------------------------------------------- U2
        $display("\n=== U2 : inject[1] (CP-A self test) ===");
        e0 = errors;
        run_bb(L1_IN_BASE, NX, L1_OUT_BASE, NY, 10, 2'b10);
        check("U2", mm_cnt == 1, $sformatf("mismatch_cnt=%0d (want 1)", mm_cnt));
        check("U2", first_valid && first_idx == 0, $sformatf("first_idx=%0d (want 0)", first_idx));
        check("U2", first_got == xv[0][31:0] && first_exp == (xv[0][31:0] ^ 32'h1),
              $sformatf("got=%08h exp=%08h", first_got, first_exp));
        report("U2", e0, $sformatf("mismatch=%0d first_idx=%0d", mm_cnt, first_idx));

        // ------------------------------------------------------------- U3
        $display("\n=== U3 : inject[0] (Golden beat0 bit0 flipped) ===");
        e0 = errors;
        for (int k = 0; k < NY; k++) l1_poke(L1_OUT_BASE + k, '0);
        run_bb(L1_IN_BASE, NX, L1_OUT_BASE, NY, 10, 2'b01);
        begin
            logic [DW-1:0] d0;
            d0 = l1_peek(L1_OUT_BASE) ^ gv[0];
            check("U3", d0 == {{(DW-1){1'b0}}, 1'b1}, "OUT beat0 differs from Golden in bit 0 only");
        end
        bad = cmp_out(L1_OUT_BASE, NY, gref, 1);
        check("U3", bad == 0, $sformatf("beats 1..15 == Golden, beat0 == Golden^1 (%0d bad)", bad));
        check("U3", mm_cnt == 0, $sformatf("CP-A unaffected, mismatch=%0d", mm_cnt));
        report("U3", e0, "only OUT beat 0 bit 0 differs");

        // ------------------------------------------------------------- U4
        $display("\n=== U4 : latency 0 / 1 / 1000 ===");
        e0 = errors;
        for (int i = 0; i < 3; i++) begin
            int L;
            L = (i == 0) ? 0 : (i == 1) ? 1 : 1000;
            for (int k = 0; k < NY; k++) l1_poke(L1_OUT_BASE + k, '0);
            run_bb(L1_IN_BASE, NX, L1_OUT_BASE, NY, L, 2'b00);
            bad = cmp_out(L1_OUT_BASE, NY, gref, 0);
            $display("    latency=%0d  cycle_cnt=%0d  mismatch=%0d  OUT bad=%0d", L, cyc, mm_cnt, bad);
            check("U4", mm_cnt == 0 && bad == 0, $sformatf("latency %0d result identical", L));
            if (i == 0) c0 = cyc; else if (i == 1) c1 = cyc; else c1000 = cyc;
        end
        check("U4", c1 - c0 == 1 && c1000 - c0 == 1000,
              $sformatf("cycle delta: L1-L0=%0d, L1000-L0=%0d", c1 - c0, c1000 - c0));
        report("U4", e0, $sformatf("cycles L0=%0d L1=%0d L1000=%0d", c0, c1, c1000));

        // ------------------------------------------------------------- U5
        $display("\n=== U5 : IN beat 37 corrupted ===");
        e0 = errors;
        begin
            logic [DW-1:0] bad37;
            bad37 = xv[37] ^ {{(DW-32){1'b0}}, 32'hA5A5_0001};
            l1_poke(L1_IN_BASE + 37, bad37);
            run_bb(L1_IN_BASE, NX, L1_OUT_BASE, NY, 10, 2'b00);
            check("U5", mm_cnt == 1, $sformatf("mismatch_cnt=%0d (want 1)", mm_cnt));
            check("U5", first_idx == 37, $sformatf("first_idx=%0d (want 37)", first_idx));
            check("U5", first_got == bad37[31:0] && first_exp == xv[37][31:0],
                  $sformatf("got=%08h (want %08h) exp=%08h (want %08h)", first_got, bad37[31:0], first_exp, xv[37][31:0]));
            l1_poke(L1_IN_BASE + 37, xv[37]);
        end
        report("U5", e0, $sformatf("mismatch=%0d first_idx=%0d got/exp low32 ok", mm_cnt, first_idx));

        // ------------------------------------------------------------- U7
        $display("\n=== U7 : boundary  len 1/1  and  256/256 ===");
        e0 = errors;
        for (int k = 0; k < NY; k++) l1_poke(L1_OUT_BASE + k, '0);
        run_bb(L1_IN_BASE, 1, L1_OUT_BASE, 1, 0, 2'b00);
        bad = cmp_out(L1_OUT_BASE, 1, gref, 0);
        check("U7", mm_cnt == 0 && bad == 0 && l1_peek(L1_OUT_BASE + 1) == '0,
              $sformatf("1/1 : mismatch=%0d OUT bad=%0d, beat1 untouched", mm_cnt, bad));
        // 256/256 random
        for (int k = 0; k < 256; k++) begin
            for (int w = 0; w < DW/32; w++) begin
                rin[k][w*32 +: 32]  = $urandom();
                rout[k][w*32 +: 32] = $urandom();
            end
            l1_poke(L1_IN_BASE + k, rin[k]);
            bram_write(0, k, rin[k]);
            bram_write(1, k, rout[k]);
            l1_poke(L1_OUT_BASE + k, '0);
        end
        run_bb(L1_IN_BASE, 256, L1_OUT_BASE, 256, 3, 2'b00);
        bad = cmp_out(L1_OUT_BASE, 256, rout, 0);
        check("U7", mm_cnt == 0 && bad == 0, $sformatf("256/256 : mismatch=%0d OUT bad=%0d", mm_cnt, bad));
        check("U7", l1_peek(L1_OUT_BASE + 256) == '0 && l1_peek(L1_IN_BASE + 256) == '0,
              "no write past OUT+255, nothing touched at IN+256");
        report("U7", e0, $sformatf("1/1 ok, 256/256 cycles=%0d", cyc));

        // ------------------------------------------------------------- U8 / U9 / U10 : ch2 output
        $display("\n=== U8 : ch2 out, burst (random ready), 32b fields, H=2 W=8 NB=4 (16b psum 64ch) ===");
        e0 = errors;
        for (int k = 0; k < NX; k++) l1_poke(L1_IN_BASE + k, xv[k]);
        for (int k = 0; k < NX; k++) bram_write(0, k, xv[k]);
        for (int k = 0; k < 256; k++) begin
            for (int w = 0; w < DW/32; w++) gref[k][w*32 +: 32] = {16'(k), 16'(w)};
            bram_write(1, k, gref[k]);
        end
        run_c2(2, 8, 4, 1'b1, 1'b0, 2'b00);
        check("U8", mm_cnt == 0 && bb_done && !pe_busy, $sformatf("CP-A mismatch=%0d, done", mm_cnt));
        c2_check("U8", 2, 8, 4, 1'b1, gref, 1'b0);
        report("U8", e0, $sformatf("ch2 burst 64 beats, cycles=%0d", cyc));

        $display("\n=== U9 : ch2 out, handshake (response pulse), 8b fields, H=1 W=5 NB=3 (odd) ===");
        e0 = errors;
        run_c2(1, 5, 3, 1'b0, 1'b1, 2'b00);
        c2_check("U9", 1, 5, 3, 1'b0, gref, 1'b0);
        report("U9", e0, $sformatf("ch2 handshake 15 beats, cycles=%0d", cyc));

        $display("\n=== U10 : ch2 out with inject[0] -> first beat bit 0 flipped only ===");
        e0 = errors;
        run_c2(1, 16, 2, 1'b0, 1'b0, 2'b01);
        c2_check("U10", 1, 16, 2, 1'b0, gref, 1'b1);
        report("U10", e0, "first beat bit0 flipped, others exact");
        for (int k = 0; k < 256; k++) gref[k] = (k < NY) ? gv[k] : '0;

        // ------------------------------------------------------------- U6
        $display("\n=== U6 : START while noc_busy=1 ===");
        e0 = errors;
        do_reset();
        check("U6", !err_start_busy, "err_start_busy=0 after reset");
        @(negedge clk); noc_busy = 1;
        begin
            bit saw_busy = 0;
            @(negedge clk);
            in_base = 0; in_len = 4; out_base = L1_OUT_BASE; out_len = 4; latency = 0; inject = 0;
            start = 1;
            @(negedge clk); start = 0;
            repeat (20) begin
                @(negedge clk);
                if (pe_busy || bb_busy || bb_done) saw_busy = 1;
            end
            check("U6", !saw_busy, "START ignored : pe_busy / busy / done never rose");
            check("U6", err_start_busy, "err_start_busy=1");
            noc_busy = 0;
            repeat (5) @(negedge clk);
            check("U6", err_start_busy, "err_start_busy is sticky after noc_busy falls");
        end
        report("U6", e0, "ignored, err_start_busy sticky");

        // ------------------------------------------------------------- summary
        $display("\n================ Phase 1 summary ================");
        foreach (results[i]) $display("  %s", results[i]);
        $display("  PASS %0d / FAIL %0d", npass, nfail);
        $display("=================================================");
        if (errors == 0) $display("PASS (errors=0)");
        else             $display("FAIL (errors=%0d)", errors);
        $finish;
    end

    initial begin
        #50_000_000;
        $display("!! GLOBAL TIMEOUT");
        $display("FAIL (errors=%0d)", errors + 1);
        $finish;
    end

endmodule
