`timescale 1ns/1ps
// =============================================================================
//  tb_l2_noc_bb_top  -  Phase 3 : PS 인터페이스 포함 시스템 (BLACKBOX_TASK.md 10절)
//
//  DUT = l2_noc_bb_bd_wrapper (Verilog-2001 BD 껍데기) -> l2_noc_bb_top
//  TB 가 PS 역할: AXI4 master task (L2 데이터 창, 64b) + AXI-Lite master task (레지스터)
//  Phase 2 의 S1~S6 을 같은 hex 로 다시 돌린다. 판정은 전부 레지스터/AXI 로 읽은 값으로 한다
//  (backdoor 는 진단 출력에만 사용).
//
//  REG : 레지스터 읽기/쓰기, BRAM_ADDR 자동 증가, BRAM 창 readback
// =============================================================================
module tb_l2_noc_bb_top;
    import bb_pkg::*;

    localparam int CLKP = 10;
    localparam int DW   = 512;
    localparam string VEC_ROOT = "../../vectors";
    localparam int AXI_AW = 40, AXI_IDW = 16, LITE_AW = 12;

    // register offsets
    localparam int R_CMD_LO = 'h00, R_CMD_HI = 'h04, R_CMD_PUSH = 'h08, R_STATUS = 'h0C;
    localparam int R_BB_CTRL = 'h20, R_BB_IN = 'h24, R_BB_OUT = 'h28, R_BB_LAT = 'h2C;
    localparam int R_BB_STATUS = 'h30, R_BB_MM = 'h34, R_BB_GOT = 'h38, R_BB_EXP = 'h3C, R_BB_CYC = 'h40;
    localparam int R_BRAM_ADDR = 'h44, R_BRAM_COMMIT = 'h48, R_BRAM_WIN = 'h80;

    logic aclk = 0, aresetn = 0;
    always #(CLKP/2) aclk = ~aclk;

    // ---- AXI4 master signals -------------------------------------------------
    logic [AXI_IDW-1:0] awid = 0, arid = 0;
    logic [AXI_AW-1:0]  awaddr = 0, araddr = 0;
    logic [7:0]         awlen = 0, arlen = 0;
    logic [2:0]         awsize = 3, arsize = 3;
    logic [1:0]         awburst = 1, arburst = 1;
    logic               awvalid = 0, arvalid = 0;
    wire                awready, arready;
    logic [63:0]        wdata = 0;
    logic [7:0]         wstrb = 8'hFF;
    logic               wlast = 0, wvalid = 0;
    wire                wready;
    wire [AXI_IDW-1:0]  bid, rid;
    wire [1:0]          bresp, rresp;
    wire                bvalid, rvalid, rlast;
    logic               bready = 1, rready = 1;
    wire [63:0]         rdata;

    // ---- AXI-Lite master signals ----------------------------------------------
    logic [LITE_AW-1:0] l_awaddr = 0, l_araddr = 0;
    logic               l_awvalid = 0, l_wvalid = 0, l_arvalid = 0;
    logic [31:0]        l_wdata = 0;
    logic [3:0]         l_wstrb = 4'hF;
    wire                l_awready, l_wready, l_bvalid, l_arready, l_rvalid;
    wire [1:0]          l_bresp, l_rresp;
    wire [31:0]         l_rdata;
    logic               l_bready = 1, l_rready = 1;

    l2_noc_bb_bd_wrapper #(
        .GROUPS(GROUPS), .BLOCKS(BLOCKS), .ADDRESS_ROW(ADDRESS_ROW),
        .AXI_ADDR_WIDTH(AXI_AW), .AXI_ID_WIDTH(AXI_IDW), .LITE_ADDR_W(LITE_AW), .BB_GUARD(2)
    ) dut (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awid(awid), .s_axi_awaddr(awaddr), .s_axi_awlen(awlen), .s_axi_awsize(awsize),
        .s_axi_awburst(awburst), .s_axi_awlock(1'b0), .s_axi_awcache(4'b0011), .s_axi_awprot(3'b000),
        .s_axi_awqos(4'b0), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wlast(wlast), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bid(bid), .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_arid(arid), .s_axi_araddr(araddr), .s_axi_arlen(arlen), .s_axi_arsize(arsize),
        .s_axi_arburst(arburst), .s_axi_arlock(1'b0), .s_axi_arcache(4'b0011), .s_axi_arprot(3'b000),
        .s_axi_arqos(4'b0), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rid(rid), .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rlast(rlast),
        .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .s_axil_awaddr(l_awaddr), .s_axil_awprot(3'b000), .s_axil_awvalid(l_awvalid), .s_axil_awready(l_awready),
        .s_axil_wdata(l_wdata), .s_axil_wstrb(l_wstrb), .s_axil_wvalid(l_wvalid), .s_axil_wready(l_wready),
        .s_axil_bresp(l_bresp), .s_axil_bvalid(l_bvalid), .s_axil_bready(l_bready),
        .s_axil_araddr(l_araddr), .s_axil_arprot(3'b000), .s_axil_arvalid(l_arvalid), .s_axil_arready(l_arready),
        .s_axil_rdata(l_rdata), .s_axil_rresp(l_rresp), .s_axil_rvalid(l_rvalid), .s_axil_rready(l_rready)
    );

    // =========================================================================
    //  bookkeeping
    // =========================================================================
    int errors = 0, npass = 0, nfail = 0;
    string results[$];
    longint cyc_now = 0;
    always @(posedge aclk) cyc_now++;

    // START-gap monitor : clocks from L2 busy fall to the BB START pulse
    longint busy_fall_at = 0, start_at = 0;
    logic   busy_q = 0;
    always @(posedge aclk) begin
        busy_q <= dut.u_top.busy_ch1_in;
        if (busy_q && !dut.u_top.busy_ch1_in) busy_fall_at = cyc_now;
        if (dut.u_top.bb_start) start_at = cyc_now;
    end

    int conflicts = 0;     // PE and NoC accessed L1 in the same clock (must stay 0)
    always @(posedge aclk) if (aresetn && dut.u_top.u_noc.pe_conflict) conflicts++;

    task automatic chk(input string tag, input bit cond, input string msg);
        if (cond) $display("    [ok]   %s : %s", tag, msg);
        else begin $display("    [FAIL] %s : %s", tag, msg); errors++; end
    endtask
    task automatic report(input string tname, input int e0, input string note);
        results.push_back($sformatf("%-14s | %-4s | %s", tname, (errors == e0) ? "PASS" : "FAIL", note));
        if (errors == e0) npass++; else nfail++;
    endtask
    task automatic settle(); @(negedge aclk); #1; endtask

    task automatic do_reset();
        @(negedge aclk); aresetn = 0;
        repeat (10) @(negedge aclk); aresetn = 1;
        repeat (5) @(negedge aclk);
    endtask

    // =========================================================================
    //  AXI-Lite master
    // =========================================================================
    task automatic lite_wr(input int off, input logic [31:0] d, input logic [3:0] strb = 4'hF);
        bit aw_done = 0, w_done = 0;
        int t = 0;
        @(negedge aclk);
        l_awaddr = off[LITE_AW-1:0]; l_awvalid = 1; l_wdata = d; l_wstrb = strb; l_wvalid = 1; #1;
        while (!(aw_done && w_done)) begin
            bit aw_hs, w_hs;
            aw_hs = l_awvalid && l_awready;
            w_hs  = l_wvalid && l_wready;
            @(posedge aclk);
            if (aw_hs) aw_done = 1;
            if (w_hs)  w_done  = 1;
            @(negedge aclk);
            if (aw_done) l_awvalid = 0;
            if (w_done)  l_wvalid  = 0;
            #1;
            if (++t > 1000) begin $display("    !! lite_wr timeout"); errors++; break; end
        end
        t = 0;
        while (!l_bvalid) begin settle(); if (++t > 1000) begin $display("    !! lite bvalid timeout"); errors++; break; end end
        if (l_bresp !== 2'b00) begin $display("    !! lite bresp=%0d", l_bresp); errors++; end
        @(posedge aclk);
    endtask

    task automatic lite_rd(input int off, output logic [31:0] d);
        int t = 0;
        @(negedge aclk);
        l_araddr = off[LITE_AW-1:0]; l_arvalid = 1; #1;
        while (!l_arready) begin settle(); if (++t > 1000) begin $display("    !! lite arready timeout"); errors++; break; end end
        @(posedge aclk); @(negedge aclk); l_arvalid = 0; #1;
        t = 0;
        while (!l_rvalid) begin settle(); if (++t > 1000) begin $display("    !! lite rvalid timeout"); errors++; break; end end
        d = l_rdata;
        if (l_rresp !== 2'b00) begin $display("    !! lite rresp=%0d", l_rresp); errors++; end
        @(posedge aclk);
    endtask

    // =========================================================================
    //  AXI4 master (64b, INCR, full strobes)
    // =========================================================================
    task automatic axi_wr(input longint byte_addr, input logic [63:0] q[$]);
        int n, t;
        n = q.size();
        @(negedge aclk);
        awid = 16'h00A1; awaddr = byte_addr; awlen = 8'(n - 1); awsize = 3; awburst = 1; awvalid = 1; #1;
        t = 0;
        while (!awready) begin settle(); if (++t > 10000) begin $display("    !! awready timeout"); errors++; break; end end
        @(posedge aclk); @(negedge aclk); awvalid = 0;
        for (int i = 0; i < n; i++) begin
            wdata = q[i]; wstrb = 8'hFF; wlast = (i == n - 1); wvalid = 1; #1;
            t = 0;
            while (!wready) begin settle(); if (++t > 10000) begin $display("    !! wready timeout"); errors++; break; end end
            @(posedge aclk); @(negedge aclk);
        end
        wvalid = 0; wlast = 0; #1;
        t = 0;
        while (!bvalid) begin settle(); if (++t > 10000) begin $display("    !! bvalid timeout"); errors++; break; end end
        if (bresp !== 2'b00 || bid !== 16'h00A1) begin $display("    !! bresp=%0d bid=%h", bresp, bid); errors++; end
        @(posedge aclk);
    endtask

    task automatic axi_rd(input longint byte_addr, input int n, output logic [63:0] q[$]);
        int t, got;
        q = {};
        @(negedge aclk);
        arid = 16'h00B2; araddr = byte_addr; arlen = 8'(n - 1); arsize = 3; arburst = 1; arvalid = 1; #1;
        t = 0;
        while (!arready) begin settle(); if (++t > 10000) begin $display("    !! arready timeout"); errors++; break; end end
        @(posedge aclk); @(negedge aclk); arvalid = 0;
        got = 0; t = 0;
        while (got < n) begin
            #1;
            if (rvalid) begin
                q.push_back(rdata);
                got++;
                if (rresp !== 2'b00 || rid !== 16'h00B2) begin $display("    !! rresp=%0d rid=%h", rresp, rid); errors++; end
                if (rlast !== (got == n)) begin $display("    !! rlast mismatch"); errors++; end
            end
            @(negedge aclk);
            if (++t > 20000) begin $display("    !! rvalid timeout"); errors++; break; end
        end
    endtask

    // ch1_in beats <-> L2 through the AXI4 window, one burst per lane (<=256, no 4 KB crossing)
    task automatic l2_write_beats(input int c0, input int n, ref logic [DW-1:0] v[$]);
        for (int b = 0; b < RATIO; b++) begin
            int k = 0;
            while (k < n) begin
                logic [63:0] q[$];
                int a0, len;
                a0 = ch1_to_ch0(c0 + k, b); len = 0; q = {};
                while (k + len < n && len < 256 && ch1_to_ch0(c0 + k + len, b) == a0 + len &&
                       (((a0 + len) * 8) >> 12) == ((a0 * 8) >> 12)) begin
                    q.push_back(v[k + len][b*64 +: 64]);
                    len++;
                end
                axi_wr(longint'(a0) * 8, q);
                k += len;
            end
        end
    endtask

    task automatic l2_read_beats(input int c0, input int n, ref logic [DW-1:0] v[$]);
        v = {};
        for (int k = 0; k < n; k++) v.push_back('0);
        for (int b = 0; b < RATIO; b++) begin
            int k = 0;
            while (k < n) begin
                logic [63:0] q[$];
                int a0, len;
                a0 = ch1_to_ch0(c0 + k, b); len = 0;
                while (k + len < n && len < 256 && ch1_to_ch0(c0 + k + len, b) == a0 + len &&
                       (((a0 + len) * 8) >> 12) == ((a0 * 8) >> 12))
                    len++;
                axi_rd(longint'(a0) * 8, len, q);
                for (int i = 0; i < len; i++) v[k + i][b*64 +: 64] = q[i];
                k += len;
            end
        end
    endtask

    // =========================================================================
    //  PS-style helpers (what the C code will do)
    // =========================================================================
    task automatic bram_load(input bit sel, ref logic [DW-1:0] v[$]);
        lite_wr(R_BRAM_ADDR, {23'd0, sel, 8'd0});
        foreach (v[k]) begin
            for (int w = 0; w < DW/32; w++) lite_wr(R_BRAM_WIN + 4*w, v[k][w*32 +: 32]);
            lite_wr(R_BRAM_COMMIT, 32'd1);
        end
    endtask

    task automatic push_cmd(input logic [63:0] c);
        lite_wr(R_CMD_LO, c[31:0]);
        lite_wr(R_CMD_HI, c[63:32]);
        lite_wr(R_CMD_PUSH, 32'd1);
    endtask

    // poll STATUS.busy : 1 then 0 ; returns clocks from call to the poll that saw 0
    task automatic wait_cmd_done(input string what, output int cycles);
        logic [31:0] st;
        longint t0;
        int n;
        t0 = cyc_now;
        n = 0;
        do begin lite_rd(R_STATUS, st); n++; end while (!st[1] && n < 200);
        if (!st[1]) $display("    (%s : busy=1 never observed by polling - command may have finished already)", what);
        n = 0;
        do begin lite_rd(R_STATUS, st); n++; end while (st[1] && n < 20000);
        if (st[1]) begin $display("    !! %s : busy never fell", what); errors++; cycles = -1; return; end
        if (st[2]) begin $display("    !! %s : STATUS.cmd_overflow=1", what); errors++; end
        cycles = int'(cyc_now - t0);
    endtask

    // =========================================================================
    //  MAP : PS(AXI4) 창이 정확히 1 MiB 인지
    //   - 맨 아래 / 맨 위 4 KB 페이지의 마지막 256 beat 쓰기+읽기 (OKAY)
    //   - 맨 위 512b 워드 (0x3FFF) 를 LOAD -> L1 에서 확인 (명령 경로도 top 까지)
    //   - bridge 는 addr[19:0] 만 본다 (상위는 SmartConnect 몫) -> 0x10_0000 은 0x0 과 같은 곳
    //   - 1 MiB 끝을 넘는 burst 는 SLVERR
    // =========================================================================
    task automatic test_map();
        int e0, bad, cyc;
        logic [63:0] q[$], r[$];
        longint bases[2];
        $display("\n=== MAP : AXI4 window = 1 MiB ===");
        e0 = errors;
        do_reset();
        bad = 0;
        bases[0] = 64'h0_0000;
        bases[1] = 64'hF_F800;                       // last 2 KB below 1 MiB (one 4 KB page)
        foreach (bases[j]) begin
            q = {};
            for (int i = 0; i < 256; i++) q.push_back({32'hFACE_0000 | j, 32'(bases[j] + 8*i)});
            axi_wr(bases[j], q);
            axi_rd(bases[j], 256, r);
            for (int i = 0; i < 256; i++) if (r[i] !== q[i]) bad++;
        end
        chk("MAP", bad == 0, $sformatf("AXI4 256-beat write/read at 0x00000 and 0xFF800..0xFFFFF : %0d bad", bad));

        // top 512b word 0x3FFF : its 8 lanes are at ch0 words (7<<14)|((8+b)<<10)|1023
        begin
            logic [DW-1:0] v [$];
            logic [DW-1:0] want, got;
            v.push_back('0);
            for (int b = 0; b < RATIO; b++) v[0][b*64 +: 64] = {32'h70B0_0000 | b, 32'hFFFF_FFF0 | b};
            l2_write_beats((1 << SRC_W) - 1, 1, v);
            want = v[0];
            push_cmd(mk_load((1 << SRC_W) - 1, 1, 77));
            wait_cmd_done("MAP LOAD top", cyc);
            repeat (5) @(negedge aclk);
            got = {dut.u_top.u_noc.u_l1_sram.Usram_mimic_3.mem[77], dut.u_top.u_noc.u_l1_sram.Usram_mimic_2.mem[77],
                   dut.u_top.u_noc.u_l1_sram.Usram_mimic_1.mem[77], dut.u_top.u_noc.u_l1_sram.Usram_mimic_0.mem[77]};
            chk("MAP", got === want, $sformatf("LOAD of top ch1 word 0x%04h through AXI-Lite command -> L1[77]", (1 << SRC_W) - 1));
        end

        // bridge decodes exactly addr[19:0] (= 1 MiB). Upper bits belong to SmartConnect (LHJ bridge header),
        // so 0x10_0000 aliases to 0x0_0000 inside the bridge.
        axi_rd(64'h10_0000, 1, r);
        chk("MAP", r[0] === {32'hFACE_0000, 32'h0}, $sformatf("read 0x100000 = %016h -> same as 0x00000 (20-bit window = 1 MiB)", r[0]));
        // a burst running past the 1 MiB end must be rejected (SLVERR, no L2 access; read error does not latch a fault)
        begin
            int t = 0, nb = 0;
            logic [1:0] resp;
            @(negedge aclk);
            arid = 16'h00C3; araddr = 40'hF_FFF8; arlen = 1; arsize = 3; arburst = 1; arvalid = 1; #1;
            while (!arready) begin settle(); if (++t > 1000) break; end
            @(posedge aclk); @(negedge aclk); arvalid = 0;
            t = 0; resp = 2'b00;
            while (nb < 2 && t < 1000) begin
                #1;
                if (rvalid) begin nb++; if (rresp != 2'b00) resp = rresp; end
                @(negedge aclk); t++;
            end
            chk("MAP", resp == 2'b10, $sformatf("2-beat read at 0xFFFF8 (crosses 1 MiB end) -> RRESP=%0d (want 2 = SLVERR)", resp));
        end
        report("MAP 1MiB", e0, "AXI4 window bottom/top OK, top word LOAD OK, 20-bit decode, crossing 1 MiB -> SLVERR");
    endtask

    // =========================================================================
    //  PS helpers for the weight / output paths
    // =========================================================================
    localparam int R_BB_C2_CFG = 'h4C;
    localparam int R_WBB_CTRL = 'h120, R_WBB_IN = 'h124, R_WBB_STATUS = 'h130, R_WBB_MM = 'h134;
    localparam int R_WBB_CYC = 'h140, R_WBRAM_ADDR = 'h144, R_WBRAM_COMMIT = 'h148;

    // poll STATUS bit `b` : 1 then 0 (bit1 ch1_in, bit3 ch2_in, bit4 ch1_wgt)
    task automatic wait_busy_bit(input int b, input string what, output int cycles);
        logic [31:0] st;
        longint t0;
        int n;
        t0 = cyc_now; n = 0;
        do begin lite_rd(R_STATUS, st); n++; end while (!st[b] && n < 200);
        n = 0;
        do begin lite_rd(R_STATUS, st); n++; end while (st[b] && n < 20000);
        if (st[b]) begin $display("    !! %s : busy never fell", what); errors++; cycles = -1; return; end
        if (st[2]) begin $display("    !! %s : STATUS.cmd_overflow=1", what); errors++; end
        cycles = int'(cyc_now - t0);
    endtask

    task automatic l2_write_256(input int c0, input int n, ref logic [255:0] v[$]);
        for (int b = 0; b < RATIO_256; b++) begin
            int k = 0;
            while (k < n) begin
                logic [63:0] q[$];
                int a0, len;
                a0 = c256_to_ch0(c0 + k, b); len = 0; q = {};
                while (k + len < n && len < 256 && c256_to_ch0(c0 + k + len, b) == a0 + len &&
                       (((a0 + len) * 8) >> 12) == ((a0 * 8) >> 12)) begin
                    q.push_back(v[k + len][b*64 +: 64]);
                    len++;
                end
                axi_wr(longint'(a0) * 8, q);
                k += len;
            end
        end
    endtask

    task automatic wbram_load(ref logic [255:0] v[$]);
        lite_wr(R_WBRAM_ADDR, 32'd0);
        foreach (v[k]) begin
            for (int w = 0; w < 8; w++) lite_wr(R_BRAM_WIN + 4*w, v[k][w*32 +: 32]);
            lite_wr(R_WBRAM_COMMIT, 32'd1);
        end
    endtask

    task automatic run_wbb_ps(input int len, output int mm, output int cyc);
        logic [31:0] st, d;
        int n = 0;
        lite_wr(R_WBB_IN, {5'd0, 11'(len), 6'd0, 10'd0});
        lite_wr(R_WBB_CTRL, 32'd1);
        do begin lite_rd(R_WBB_STATUS, st); n++; end while (!st[1] && n < 20000);
        if (!st[1]) begin $display("    !! weight BB done never seen (WBB_STATUS=%08h)", st); errors++; end
        lite_rd(R_WBB_MM, d);  mm = d[15:0];
        lite_rd(R_WBB_CYC, d); cyc = d;
    endtask

    task automatic read_wimg(input int seed, ref logic [255:0] w[$]);
        logic [255:0] a [0:NWROWS-1];
        $readmemh($sformatf("%s/seed%0d/wgt.hex", VEC_ROOT, seed), a);
        w = {};
        foreach (a[k]) begin
            if ($isunknown(a[k])) begin $display("    !! wgt.hex row %0d has X", k); errors++; end
            w.push_back(a[k]);
        end
    endtask

    // =========================================================================
    //  PW : weight path through the PS interfaces
    //   custom < 0 : burst load of all 1024 rows ; else custom load (g,u,c) after a zero clear
    // =========================================================================
    task automatic test_wgt_ps(input string tname, input int seed, input int g, input int u, input int c,
                               input bit custom, input bit hs);
        logic [255:0] wq [$], zq [$], ev [$];
        int e0, c_clr, c_load, mm, cyc, nb;
        string kind;
        if (custom) kind = $sformatf("custom (%0d,%0d,%0d)", g, u, c);
        else        kind = "burst 1024 rows";
        $display("\n=== %s : seed %0d %s hs=%0d ===", tname, seed, kind, hs);
        e0 = errors;
        read_wimg(seed, wq);
        do_reset();
        ev = {};
        if (custom) begin
            nb = wcustom_beats(g, u, c);
            for (int k = 0; k < NWROWS; k++) ev.push_back('0);
            for (int i = 0; i < nb; i++) ev[wcustom_row(i, g, u, c)] = wq[i];
            zq = {};
            for (int k = 0; k < NWROWS; k++) zq.push_back('0);
            l2_write_256(ZERO_W_WORD, NWROWS, zq);
        end else begin
            nb = NWROWS;
            ev = wq;
        end
        l2_write_256(WGT_W_WORD, NWROWS, wq);
        wbram_load(ev);
        if (custom) begin
            push_cmd(mk_wload_burst(ZERO_W_WORD, NWROWS, 0, hs));
            wait_busy_bit(4, {tname, " clear"}, c_clr);
            push_cmd(mk_wload_custom(WGT_W_WORD, g, u, c, hs));
        end else
            push_cmd(mk_wload_burst(WGT_W_WORD, NWROWS, 0, hs));
        wait_busy_bit(4, {tname, " WLOAD"}, c_load);
        run_wbb_ps(NWROWS, mm, cyc);
        chk(tname, mm == 0, $sformatf("CP-W (WBB_MISMATCH) = %0d over %0d rows (%0d beats loaded, LOAD %0d clk)",
                                      mm, NWROWS, nb, c_load));
        report(tname, e0, $sformatf("CP-W mm %0d | %0d beats, LOAD %0d clk", mm, nb, c_load));
    endtask

    // =========================================================================
    //  PO : output path through the PS interfaces (Blackbox -> ch2_in store)
    //   CP-B = AXI4 readback ; chain = ch1_in LOAD of the stored words into L1 512.. and a 2nd
    //   Blackbox run that compares them (Expected = the same words) -> CP-A of the 2nd run
    // =========================================================================
    task automatic test_out_ps(input string tname, input int seed, input bit psum, input int H, input int W,
                               input int NB, input bit prec, input bit hs, input bit chain, input int dest);
        logic [DW-1:0] xa [0:NX-1];
        logic [DW-1:0] ga [0:31];
        logic [DW-1:0] xv [$], gv [$], rb [$], pz [$];
        logic [31:0] st, d;
        int e0, c_load, c_st, nw, bad, n, mm2;
        string ctxt;
        string gfile;
        nw = ((NB + 1) / 2) * H * W;
        if (psum) gfile = "psum16.hex"; else gfile = "out8.hex";
        $display("\n=== %s : seed %0d %s H=%0d W=%0d NB=%0d prec_field=%0d hs=%0d dest=0x%04h ===",
                 tname, seed, gfile, H, W, NB, prec, hs, dest);
        e0 = errors;
        $readmemh($sformatf("%s/seed%0d/x.hex", VEC_ROOT, seed), xa);
        $readmemh($sformatf("%s/seed%0d/%s", VEC_ROOT, seed, gfile), ga);
        xv = {}; gv = {};
        foreach (xa[k]) xv.push_back(xa[k]);
        for (int k = 0; k < nw; k++) begin
            if ($isunknown(ga[k])) begin $display("    !! %s word %0d has X", gfile, k); errors++; end
            gv.push_back(ga[k]);
        end
        do_reset();
        pz = {};
        for (int k = 0; k < nw; k++) pz.push_back({16{32'hBAD0_C200}});
        l2_write_beats(dest, nw, pz);
        l2_write_beats(X_CH1_WORD, NX, xv);
        bram_load(0, xv);
        bram_load(1, gv);
        push_cmd(mk_load(X_CH1_WORD, NX, L1_IN_BASE));
        wait_cmd_done({tname, " LOAD"}, c_load);
        // Blackbox -> ch2 store
        lite_wr(R_BB_IN,  {7'd0, 9'(NX), 5'd0, 11'(L1_IN_BASE)});
        lite_wr(R_BB_LAT, 32'd10);
        lite_wr(R_BB_C2_CFG, {prec, 4'd0, 7'(NB), 10'(H), 10'(W)});
        push_cmd(mk_c2_store(dest, H, W, prec, hs));
        lite_wr(R_BB_CTRL, {27'd0, hs, 1'b1, 2'b00, 1'b1});          // C2_HS, OUT_SEL=1, START
        n = 0;
        do begin lite_rd(R_BB_STATUS, st); n++; end while (!st[1] && n < 20000);
        if (!st[1]) begin $display("    !! BB done never seen (BB_STATUS=%08h)", st); errors++; end
        wait_busy_bit(3, {tname, " ch2 store"}, c_st);
        lite_rd(R_BB_MM, d);
        chk(tname, d[15:0] == 0, $sformatf("CP-A (input X) mismatch = %0d", d[15:0]));
        // CP-B
        l2_read_beats(dest, nw, rb);
        bad = 0;
        for (int k = 0; k < nw; k++) if (rb[k] !== gv[k]) bad++;
        chk(tname, bad == 0, $sformatf("CP-B : %0d/%0d L2 words == Golden (AXI4 readback)", nw - bad, nw));
        // chain : stored words -> ch1_in LOAD -> L1 512.. -> Blackbox compares them (CP-A of a 2nd run)
        mm2 = -1;
        if (chain) begin
            push_cmd(mk_load(dest, nw, 512));
            wait_cmd_done({tname, " chain LOAD"}, c_load);
            bram_load(0, gv);
            lite_wr(R_BB_IN,  {7'd0, 9'(nw), 5'd0, 11'd512});
            lite_wr(R_BB_OUT, 32'd0);                                   // no output phase
            lite_wr(R_BB_CTRL, 32'd1);                                  // OUT_SEL=0, START
            n = 0;
            do begin lite_rd(R_BB_STATUS, st); n++; end while (!st[1] && n < 20000);
            lite_rd(R_BB_MM, d);
            mm2 = d[15:0];
            chk(tname, mm2 == 0, $sformatf("chain : ch1_in LOAD of the stored words, Blackbox CP-A mismatch = %0d", mm2));
        end
        if (chain) ctxt = $sformatf(", chain mm %0d", mm2);
        else       ctxt = "";
        report(tname, e0, $sformatf("CP-A 0, CP-B %0d/%0d%s | ch2 store %0d clk", nw - bad, nw, ctxt, c_st));
    endtask

    // =========================================================================
    //  REG test
    // =========================================================================
    task automatic test_reg();
        int e0;
        logic [31:0] d;
        $display("\n=== REG : register map read/write ===");
        e0 = errors;
        do_reset();
        lite_rd(R_STATUS, d);
        chk("REG", d[0] == 1 && d[2:1] == 0, $sformatf("STATUS after reset = %08h (cmd_ready=1, busy=0, ovf=0)", d));
        lite_wr(R_CMD_LO, 32'h1234_5678); lite_wr(R_CMD_HI, 32'h9ABC_DEF0);
        lite_rd(R_CMD_LO, d); chk("REG", d == 32'h1234_5678, $sformatf("CMD_LO = %08h", d));
        lite_rd(R_CMD_HI, d); chk("REG", d == 32'h9ABC_DEF0, $sformatf("CMD_HI = %08h", d));
        lite_wr(R_BB_IN, {7'd0, 9'd192, 5'd0, 11'd0}); lite_rd(R_BB_IN, d);
        chk("REG", d == 32'h00C0_0000, $sformatf("BB_IN = %08h", d));
        lite_wr(R_BB_OUT, {7'd0, 9'd16, 5'd0, 11'd1024}); lite_rd(R_BB_OUT, d);
        chk("REG", d == 32'h0010_0400, $sformatf("BB_OUT = %08h", d));
        lite_wr(R_BB_LAT, 32'd12345); lite_rd(R_BB_LAT, d); chk("REG", d == 12345, $sformatf("BB_LATENCY = %0d", d));
        lite_wr(R_BB_CTRL, 32'h6); lite_rd(R_BB_CTRL, d); chk("REG", d == 32'h6, $sformatf("BB_CTRL inject readback = %08h (START reads 0)", d));
        lite_wr(R_BB_CTRL, 32'h0);
        lite_wr(R_BB_LAT, 32'hAABB_CCDD); lite_wr(R_BB_LAT, 32'h0000_1100, 4'b0010); lite_rd(R_BB_LAT, d);
        chk("REG", d == 32'hAABB_11DD, $sformatf("WSTRB byte merge = %08h", d));
        lite_wr(R_BRAM_ADDR, 32'h0000_0105); lite_rd(R_BRAM_ADDR, d);
        chk("REG", d == 32'h0000_0105, $sformatf("BRAM_ADDR = %08h (sel=1 addr=5)", d));
        for (int w = 0; w < 16; w++) lite_wr(R_BRAM_WIN + 4*w, 32'hC0DE_0000 + w);
        lite_rd(R_BRAM_WIN + 4*15, d); chk("REG", d == 32'hC0DE_000F, $sformatf("BRAM_WDATA[15] = %08h", d));
        lite_wr(R_BRAM_COMMIT, 1); lite_wr(R_BRAM_COMMIT, 1);
        lite_rd(R_BRAM_ADDR, d); chk("REG", d == 32'h0000_0107, $sformatf("BRAM_ADDR auto-increment = %08h (want 107)", d));
        chk("REG", dut.u_top.u_bb.gold_mem[5][31:0] == 32'hC0DE_0000 && dut.u_top.u_bb.gold_mem[6][511:480] == 32'hC0DE_000F,
            "Golden[5], Golden[6] written through window (backdoor check)");
        lite_rd('h10, d); chk("REG", d == 0, "unmapped offset reads 0");
        // registers added for the weight / output paths
        lite_rd(R_STATUS, d); chk("REG", d[4:3] == 2'b00, $sformatf("STATUS busy_ch2_in / busy_ch1_wgt = %0d%0d", d[4], d[3]));
        lite_wr(R_BB_C2_CFG, 32'h8180_4010); lite_rd(R_BB_C2_CFG, d);
        chk("REG", d == 32'h8180_4010, $sformatf("BB_C2_CFG = %08h (PREC=1 NB=24 H=16 W=16)", d));
        lite_wr(R_BB_CTRL, 32'h18); lite_rd(R_BB_CTRL, d); chk("REG", d == 32'h18, $sformatf("BB_CTRL OUT_SEL/C2_HS readback = %08h", d));
        lite_wr(R_BB_CTRL, 32'h0);
        lite_wr(R_WBB_IN, 32'h0400_0003); lite_rd(R_WBB_IN, d); chk("REG", d == 32'h0400_0003, $sformatf("WBB_IN = %08h", d));
        lite_wr(R_WBRAM_ADDR, 32'h3FE);
        for (int w = 0; w < 8; w++) lite_wr(R_BRAM_WIN + 4*w, 32'hA000_0000 + w);
        lite_wr(R_WBRAM_COMMIT, 1); lite_wr(R_WBRAM_COMMIT, 1);
        lite_rd(R_WBRAM_ADDR, d); chk("REG", d == 32'h0, $sformatf("WBRAM_ADDR 0x3FE +2 wraps to %03h", d));
        chk("REG", dut.u_top.u_bbw.exp_mem[10'h3FF][255:224] == 32'hA000_0007, "weight Expected[0x3FF] written through the lower 256b window");
        report("REG", e0, "register map / WSTRB / BRAM window");
    endtask

    // =========================================================================
    //  full flow through PS interfaces
    // =========================================================================
    bit skip_reset = 0;    // run the next flow without resetting (back-to-back commands)
    typedef struct {
        int    seed;
        logic [1:0] inject;
        int    latency;
        bit    fast;        // S4 : no extra wait between steps (as fast as the PS can go)
        bit    hs_load;
        bit    hs_store;
    } flow_cfg_t;

    task automatic run_flow(input string tname, input flow_cfg_t cfg, output logic [NY-1:0] badmap,
                            output int cpa_mm, output string timing);
        logic [DW-1:0] xv [$], gv [$], rb [$];
        logic [DW-1:0] xa [0:NX-1];
        logic [DW-1:0] ga [0:NY-1];
        logic [31:0] d, st;
        int c_wr, c_bram, c_load, c_store, c_rd, n, bb_cyc, start_gap;
        longint t0;
        string vdir;

        vdir = $sformatf("%s/seed%0d", VEC_ROOT, cfg.seed);
        $readmemh({vdir, "/x.hex"}, xa);
        $readmemh({vdir, "/golden.hex"}, ga);
        xv = {}; gv = {};
        foreach (xa[k]) xv.push_back(xa[k]);
        foreach (ga[k]) gv.push_back(ga[k]);

        if (!skip_reset) do_reset();
        // poison L2 OUT region through AXI (so a missing STORE can't pass)
        begin
            logic [DW-1:0] poison [$];
            for (int k = 0; k < NY; k++) poison.push_back({16{32'hBAD0_0000 | k}});
            l2_write_beats(OUT_CH1_WORD, NY, poison);
        end

        // ① X -> L2 (AXI4) ; Expected / Golden -> BB BRAM (AXI-Lite window)
        t0 = cyc_now; l2_write_beats(X_CH1_WORD, NX, xv); c_wr = int'(cyc_now - t0);
        t0 = cyc_now; bram_load(0, xv); bram_load(1, gv); c_bram = int'(cyc_now - t0);
        $display("    [1] AXI4 X->L2 : %0d clk ; AXI-Lite BRAM load (%0d+%0d beats) : %0d clk", c_wr, NX, NY, c_bram);

        // ② LOAD
        push_cmd(mk_load(X_CH1_WORD, NX, L1_IN_BASE, cfg.hs_load));
        wait_cmd_done({tname, " LOAD"}, c_load);
        $display("    [2] LOAD  push->done seen : %0d clk", c_load);

        // ③ START
        if (!cfg.fast) repeat (10) @(negedge aclk);
        lite_wr(R_BB_IN,  {7'd0, 9'(NX), 5'd0, 11'(L1_IN_BASE)});
        lite_wr(R_BB_OUT, {7'd0, 9'(NY), 5'd0, 11'(L1_OUT_BASE)});
        lite_wr(R_BB_LAT, cfg.latency);
        lite_wr(R_BB_CTRL, {29'd0, cfg.inject, 1'b1});
        n = 0;
        do begin lite_rd(R_BB_STATUS, st); n++; end while (!st[1] && n < 20000);
        start_gap = int'(start_at - busy_fall_at);
        if (!st[1]) begin $display("    !! BB done never seen (BB_STATUS=%08h)", st); errors++; end
        lite_rd(R_BB_MM, d);  cpa_mm = d[15:0];
        lite_rd(R_BB_CYC, d); bb_cyc = d;
        begin
            logic [31:0] got, exp, mm;
            lite_rd(R_BB_MM, mm); lite_rd(R_BB_GOT, got); lite_rd(R_BB_EXP, exp);
            $display("    [3] BB   START gap after busy fall = %0d clk ; BB_STATUS=%08h cycles=%0d ; CP-A mismatch=%0d first_idx=%0d got=%08h exp=%08h",
                     start_gap, st, bb_cyc, mm[15:0], mm[31:16], got, exp);
        end

        // ⑤ STORE
        if (!cfg.fast) repeat (10) @(negedge aclk);
        push_cmd(mk_store(L1_OUT_BASE, NY, OUT_CH1_WORD, cfg.hs_store));
        wait_cmd_done({tname, " STORE"}, c_store);
        $display("    [5] STORE push->done seen : %0d clk", c_store);

        // ⑥ AXI4 readback -> CP-B
        t0 = cyc_now; l2_read_beats(OUT_CH1_WORD, NY, rb); c_rd = int'(cyc_now - t0);
        badmap = '0;
        for (int k = 0; k < NY; k++) if (rb[k] !== gv[k]) badmap[k] = 1'b1;
        $display("    [6] AXI4 readback : %0d clk ; CP-B %0d/%0d beats == Golden (badmap=%04h)",
                 c_rd, NY - $countones(badmap), NY, badmap);
        timing = $sformatf("AXI wr %0d / BRAM %0d / LOAD %0d / BB %0d / STORE %0d / AXI rd %0d clk",
                           c_wr, c_bram, c_load, bb_cyc, c_store, c_rd);
    endtask

    task automatic test_flow_pass(input string tname, input flow_cfg_t cfg);
        int e0, mm;
        logic [NY-1:0] bad;
        string tm;
        $display("\n=== %s : seed %0d latency %0d fast %0d hs_load %0d hs_store %0d ===",
                 tname, cfg.seed, cfg.latency, cfg.fast, cfg.hs_load, cfg.hs_store);
        e0 = errors;
        run_flow(tname, cfg, bad, mm, tm);
        chk(tname, mm == 0, $sformatf("CP-A mismatch = %0d", mm));
        chk(tname, bad == '0, $sformatf("CP-B %0d/%0d", NY - $countones(bad), NY));
        report(tname, e0, $sformatf("CP-A %0d mm, CP-B %0d/%0d | %s", mm, NY - $countones(bad), NY, tm));
    endtask

    // =========================================================================
    initial begin
        flow_cfg_t c;
        int e0, mm;
        logic [NY-1:0] bad;
        string tm, only;
        if (!$value$plusargs("ONLY=%s", only)) only = "";

        repeat (3) @(negedge aclk);

        if (only == "" || only == "REG") test_reg();
        if (only == "" || only == "MAP") test_map();

        if (only == "" || only == "W") begin
            test_wgt_ps("PW1 wgt burst",        1, 0, 0, 0, 1'b0, 1'b0);
            test_wgt_ps("PW2 custom711",        2, 7, 1, 1, 1'b1, 1'b0);
            test_wgt_ps("PW3 custom322 hs",     3, 3, 2, 2, 1'b1, 1'b1);
        end
        if (only == "" || only == "O") begin
            //         name               seed psum H  W  NB prec hs chain dest
            test_out_ps("PO1 psum16",       1, 1,  1, 16, 4, 1,  0, 0,   C2_PSUM_WORD);
            test_out_ps("PO2 out8 + chain", 2, 0,  1, 16, 2, 0,  0, 1,   C2_OUT8_WORD);
            test_out_ps("PO3 out8 hs+chain",3, 0,  1, 16, 2, 0,  1, 1,   C2_OUT8_WORD);
        end

        if (only == "" || only == "S1") begin
            c = '{seed:1, inject:2'b00, latency:10, fast:0, hs_load:0, hs_store:0};
            test_flow_pass("S1 seed1", c);
        end
        if (only == "" || only == "S2")
            for (int s = 2; s <= 4; s++) begin
                c = '{seed:s, inject:2'b00, latency:10, fast:0, hs_load:0, hs_store:0};
                test_flow_pass($sformatf("S2 seed%0d", s), c);
            end
        if (only == "" || only == "S3") begin
            $display("\n=== S3 : inject[0] -> CP-B must flag exactly beat 0 ===");
            e0 = errors;
            c = '{seed:1, inject:2'b01, latency:10, fast:0, hs_load:0, hs_store:0};
            run_flow("S3", c, bad, mm, tm);
            chk("S3", mm == 0, $sformatf("CP-A mismatch = %0d", mm));
            chk("S3", bad == 16'h0001, $sformatf("CP-B badmap = %04h (want 0001)", bad));
            report("S3 inject0", e0, $sformatf("CP-B detected beat0 only (badmap=%04h)", bad));
        end
        if (only == "" || only == "S4") begin
            c = '{seed:2, inject:2'b00, latency:10, fast:1, hs_load:0, hs_store:0};
            test_flow_pass("S4 fastest", c);
        end
        if (only == "" || only == "S5") begin
            c = '{seed:3, inject:2'b00, latency:0, fast:0, hs_load:0, hs_store:0};
            test_flow_pass("S5 lat0", c);
            c = '{seed:4, inject:2'b00, latency:10000, fast:0, hs_load:0, hs_store:0};
            test_flow_pass("S5 lat10000", c);
        end
        if (only == "" || only == "S6") begin
            c = '{seed:1, inject:2'b00, latency:10, fast:0, hs_load:1, hs_store:0};
            test_flow_pass("S6a hs LOAD", c);
            c = '{seed:2, inject:2'b00, latency:10, fast:0, hs_load:0, hs_store:1};
            test_flow_pass("S6b hs STORE", c);
            c = '{seed:3, inject:2'b00, latency:10, fast:0, hs_load:1, hs_store:1};
            test_flow_pass("S6c hs both", c);
            skip_reset = 1;
            c = '{seed:4, inject:2'b00, latency:10, fast:0, hs_load:1, hs_store:1};
            test_flow_pass("S6d hs no-reset", c);
            skip_reset = 0;
        end
        if (only == "" || only == "S7") begin
            c = '{seed:1, inject:2'b00, latency:10, fast:1, hs_load:1, hs_store:1};
            test_flow_pass("S7 hs fastest", c);
        end

        chk("ALL", conflicts == 0, $sformatf("L1 PE/NoC port conflicts over the whole run = %0d", conflicts));
        $display("\n================ Phase 3 summary ================");
        foreach (results[i]) $display("  %s", results[i]);
        $display("  PASS %0d / FAIL %0d", npass, nfail);
        $display("=================================================");
        if (errors == 0) $display("PASS (errors=0)");
        else             $display("FAIL (errors=%0d)", errors);
        $finish;
    end

    initial begin
        #200_000_000;
        $display("!! GLOBAL TIMEOUT");
        $display("FAIL (errors=%0d)", errors + 1);
        $finish;
    end

endmodule
