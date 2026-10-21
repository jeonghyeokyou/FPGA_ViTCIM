`timescale 1ns/1ps
// =============================================================================
//  tb_bb256_system  -  256b blackbox_ip 시스템 (LHJ/261020 구조) PS 경유 검증
//
//  DUT = l2_system_bd_wrapper -> l2_system_top -> l2_noc_bb_core
//  TB 가 PS 역할 : S_AXI_DATA (AXI4 64b, L2 1 MiB 창)
//                  S_AXI_BB   (AXI-Lite 32b, blackbox 제어 / Golden 적재)
//                  S_AXI_CMD  (AXI-Lite 64b, L2 명령 push / 완료 카운터)
//  판정은 전부 AXI 로 읽은 값으로 한다. backdoor (내부 메모리 직접 보기) 는 진단 출력에만 쓴다.
//
//  T0 REG     : BB 레지스터 읽기/쓰기, 없앤 주소 SLVERR, Golden 창
//  T1 WGT_B   : weight 1024줄 L2 -> WMEM (burst) -> ch1_wgt STORE -> L2 다시 읽어 일치
//  T2 WGT_HS  : 같은 흐름, handshake 모드
//  T3 IN_B    : input 192 beat L2 -> L1 (burst) -> ch1_in STORE -> L2 다시 읽어 일치
//  T4 RUN     : Golden 64 beat, START (input 192 / weight 1024 읽기, latency 100)
//               -> L1 OUT -> ch1_in STORE -> L2 에서 Golden 과 일치, weight 는 그대로
//  T5 RUN_HS  : Golden 256 beat (전체 깊이), L1 끝 (1792~2047), handshake STORE
//  T6 INJECT  : inject 로 Golden 0번 beat bit0 반전 -> 정확히 그 1비트만 다르게 나옴
//  T7 GAP0    : LOAD 완료 직후 바로 START. START 금지 구간에는 SLVERR, 입력 마지막 beat 유실 없음
//  T8 TOP     : L2 맨 위 (0x7FC0~0x7FFF) -> L1 끝 / WMEM 끝, 다시 STORE 해서 일치
//  T9 OPCODE  : 허용 안 된 명령 (opcode 0) 은 SLVERR, L2 로 안 들어감
//
//  CH2 (blackbox_nl) : weight / input 은 STORE 가 없으므로 BB 레지스터의 디버그 읽기 창 (DBG2) 으로 확인
//  T10 C2W_B   : ch2_wgt LOAD 512줄 burst -> DBG2 로 512줄 전부 읽어 일치
//  T11 C2W_HS  : 같은 흐름, handshake
//  T12 C2IN_B  : ch2_in LOAD 192 beat burst -> DBG2 로 읽어 일치
//  T13 C2IN_HS : 같은 흐름, handshake, 목적지 1024~
//  T14 C2RUN   : ch2_in STORE 명령 먼저 -> START (input 192 / weight 512 읽기, latency 50)
//                NB=3 H=2 W=8 (48 beat) -> L2 의 (jp,col,h,w) 위치마다 Golden 과 일치, 주변 poison 유지
//  T15 C2RUN_HS: START 먼저 -> STORE 명령 (handshake, prec 1), NB=4 H=8 W=8 (256 beat, 전체 깊이)
//  T16 C2INJ   : inject -> 첫 beat bit0 만 다름
//  T17 FENCE2  : ch2 LOAD 중 START2 / DBG2 거절. ch2 STORE 대기 중에도 CH1 blackbox 는 실행 가능
// =============================================================================
module tb_bb256_system;
    import bb256_pkg::*;

    localparam int CLKP = 10;
    localparam int AXI_AW = 40, AXI_IDW = 16, LITE_AW = 12;

    // ---- BB register offsets (S_AXI_BB) ----
    localparam int R_CTRL = 'h20, R_IN = 'h24, R_OUT = 'h28, R_LAT = 'h2C, R_STATUS = 'h30;
    localparam int R_CYC = 'h40, R_GADDR = 'h44, R_GCOMMIT = 'h48, R_WGT = 'h4C, R_WIN = 'h80;
    localparam int R2_CTRL = 'h120, R2_IN = 'h124, R2_SHAPE = 'h128, R2_LAT = 'h12C, R2_STATUS = 'h130;
    localparam int R2_CYC = 'h140, R2_GADDR = 'h144, R2_GCOMMIT = 'h148, R2_WGT = 'h14C;
    localparam int R2_DBG = 'h150, R2_DBG_DATA = 'h160;
    // ---- CMD register offsets (S_AXI_CMD) ----
    localparam int C_PUSH = 'h000, C_STATUS = 'h008, C_ACCEPT = 'h010, C_BUSY = 'h020;
    localparam int C_ERRORS = 'h028, C_VERSION = 'h030, C_DONE = 'h038, C_EXEC = 'h040;

    logic aclk = 0, aresetn = 0;
    always #(CLKP/2) aclk = ~aclk;

    // ---- AXI4 master (DATA) ----------------------------------------------------
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

    // ---- AXI-Lite master (BB, 32b) -----------------------------------------------
    logic [LITE_AW-1:0] l_awaddr = 0, l_araddr = 0;
    logic               l_awvalid = 0, l_wvalid = 0, l_arvalid = 0;
    logic [31:0]        l_wdata = 0;
    logic [3:0]         l_wstrb = 4'hF;
    wire                l_awready, l_wready, l_bvalid, l_arready, l_rvalid;
    wire [1:0]          l_bresp, l_rresp;
    wire [31:0]         l_rdata;
    logic               l_bready = 1, l_rready = 1;

    // ---- AXI-Lite master (CMD, 64b) ------------------------------------------------
    logic [11:0]        c_awaddr = 0, c_araddr = 0;
    logic               c_awvalid = 0, c_wvalid = 0, c_arvalid = 0;
    logic [63:0]        c_wdata = 0;
    logic [7:0]         c_wstrb = 8'hFF;
    wire                c_awready, c_wready, c_bvalid, c_arready, c_rvalid;
    wire [1:0]          c_bresp, c_rresp;
    wire [63:0]         c_rdata;
    logic               c_bready = 1, c_rready = 1;

    l2_system_bd_wrapper #(
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
        .s_axil_rdata(l_rdata), .s_axil_rresp(l_rresp), .s_axil_rvalid(l_rvalid), .s_axil_rready(l_rready),
        .s_cmd_awaddr(c_awaddr), .s_cmd_awprot(3'b000), .s_cmd_awvalid(c_awvalid), .s_cmd_awready(c_awready),
        .s_cmd_wdata(c_wdata), .s_cmd_wstrb(c_wstrb), .s_cmd_wvalid(c_wvalid), .s_cmd_wready(c_wready),
        .s_cmd_bresp(c_bresp), .s_cmd_bvalid(c_bvalid), .s_cmd_bready(c_bready),
        .s_cmd_araddr(c_araddr), .s_cmd_arprot(3'b000), .s_cmd_arvalid(c_arvalid), .s_cmd_arready(c_arready),
        .s_cmd_rdata(c_rdata), .s_cmd_rresp(c_rresp), .s_cmd_rvalid(c_rvalid), .s_cmd_rready(c_rready)
    );

    // =========================================================================
    //  bookkeeping
    // =========================================================================
    int errors = 0, npass = 0, nfail = 0;
    string results[$];
    longint cyc_now = 0;
    always @(posedge aclk) cyc_now++;

    // PE and NoC accessed the same memory in the same clock (must stay 0)
    int conflicts = 0;
    always @(posedge aclk) if (aresetn && dut.u_top.u_core.port_conflict) conflicts++;

    task automatic chk(input string tag, input bit cond, input string msg);
        if (cond) $display("    [ok]   %s : %s", tag, msg);
        else begin $display("    [FAIL] %s : %s", tag, msg); errors++; end
    endtask
    task automatic report(input string tname, input int e0, input string note);
        results.push_back($sformatf("%-8s | %-4s | %s", tname, (errors == e0) ? "PASS" : "FAIL", note));
        if (errors == e0) npass++; else nfail++;
    endtask
    task automatic settle(); @(negedge aclk); #1; endtask

    task automatic do_reset();
        @(negedge aclk); aresetn = 0;
        repeat (10) @(negedge aclk); aresetn = 1;
        repeat (5) @(negedge aclk);
    endtask

    // =========================================================================
    //  AXI-Lite masters  (exp_err = 1 : SLVERR is the expected answer)
    // =========================================================================
    task automatic bb_wr(input int off, input logic [31:0] d, input bit exp_err = 0,
                         input logic [3:0] strb = 4'hF);
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
            if (++t > 1000) begin $display("    !! bb_wr timeout"); errors++; break; end
        end
        t = 0;
        while (!l_bvalid) begin settle(); if (++t > 1000) begin $display("    !! bb bvalid timeout"); errors++; break; end end
        if (l_bresp !== (exp_err ? 2'b10 : 2'b00)) begin
            $display("    !! bb_wr 0x%03h bresp=%0d (expected %0d)", off, l_bresp, exp_err ? 2 : 0); errors++;
        end
        @(posedge aclk);
    endtask

    task automatic bb_rd(input int off, output logic [31:0] d, input bit exp_err = 0);
        int t = 0;
        @(negedge aclk);
        l_araddr = off[LITE_AW-1:0]; l_arvalid = 1; #1;
        while (!l_arready) begin settle(); if (++t > 1000) begin $display("    !! bb arready timeout"); errors++; break; end end
        @(posedge aclk); @(negedge aclk); l_arvalid = 0; #1;
        t = 0;
        while (!l_rvalid) begin settle(); if (++t > 1000) begin $display("    !! bb rvalid timeout"); errors++; break; end end
        d = l_rdata;
        if (l_rresp !== (exp_err ? 2'b10 : 2'b00)) begin
            $display("    !! bb_rd 0x%03h rresp=%0d (expected %0d)", off, l_rresp, exp_err ? 2 : 0); errors++;
        end
        @(posedge aclk);
    endtask

    task automatic cmd_wr(input int off, input logic [63:0] d, input bit exp_err = 0);
        bit aw_done = 0, w_done = 0;
        int t = 0;
        @(negedge aclk);
        c_awaddr = off[11:0]; c_awvalid = 1; c_wdata = d; c_wstrb = 8'hFF; c_wvalid = 1; #1;
        while (!(aw_done && w_done)) begin
            bit aw_hs, w_hs;
            aw_hs = c_awvalid && c_awready;
            w_hs  = c_wvalid && c_wready;
            @(posedge aclk);
            if (aw_hs) aw_done = 1;
            if (w_hs)  w_done  = 1;
            @(negedge aclk);
            if (aw_done) c_awvalid = 0;
            if (w_done)  c_wvalid  = 0;
            #1;
            if (++t > 1000) begin $display("    !! cmd_wr timeout"); errors++; break; end
        end
        t = 0;
        while (!c_bvalid) begin settle(); if (++t > 100000) begin $display("    !! cmd bvalid timeout"); errors++; break; end end
        if (c_bresp !== (exp_err ? 2'b10 : 2'b00)) begin
            $display("    !! cmd_wr 0x%03h bresp=%0d (expected %0d)", off, c_bresp, exp_err ? 2 : 0); errors++;
        end
        @(posedge aclk);
    endtask

    task automatic cmd_rd(input int off, output logic [63:0] d);
        int t = 0;
        @(negedge aclk);
        c_araddr = off[11:0]; c_arvalid = 1; #1;
        while (!c_arready) begin settle(); if (++t > 1000) begin $display("    !! cmd arready timeout"); errors++; break; end end
        @(posedge aclk); @(negedge aclk); c_arvalid = 0; #1;
        t = 0;
        while (!c_rvalid) begin settle(); if (++t > 1000) begin $display("    !! cmd rvalid timeout"); errors++; break; end end
        d = c_rdata;
        if (c_rresp !== 2'b00) begin $display("    !! cmd_rd 0x%03h rresp=%0d", off, c_rresp); errors++; end
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

    // 256b channel words <-> L2 through the AXI4 window, one burst per lane run (<=256, no 4 KB crossing)
    task automatic l2_write_words(input int c0, ref logic [DW-1:0] v[$]);
        int n = v.size();
        for (int b = 0; b < RATIO; b++) begin
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

    task automatic l2_read_words(input int c0, input int n, ref logic [DW-1:0] v[$]);
        v = {};
        for (int k = 0; k < n; k++) v.push_back('0);
        for (int b = 0; b < RATIO; b++) begin
            int k = 0;
            while (k < n) begin
                logic [63:0] q[$];
                int a0, len;
                a0 = c256_to_ch0(c0 + k, b); len = 0;
                while (k + len < n && len < 256 && c256_to_ch0(c0 + k + len, b) == a0 + len &&
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
    function automatic void mk_vec(output logic [DW-1:0] v[$], input int n, input int seed, input int tag);
        v = {};
        for (int k = 0; k < n; k++) v.push_back(mk_word(seed, tag, k));
    endfunction

    task automatic gold_load(ref logic [DW-1:0] v[$]);
        bb_wr(R_GADDR, 32'd0);
        foreach (v[k]) begin
            for (int w = 0; w < DW/32; w++) bb_wr(R_WIN + 4*w, v[k][w*32 +: 32]);
            bb_wr(R_GCOMMIT, 32'd1);
        end
    endtask

    // push one L2 command and wait until the fence counts it complete
    task automatic run_cmd(input string what, input logic [63:0] c, output int cycles);
        logic [63:0] d0, d;
        longint t0;
        int t = 0;
        cmd_rd(C_DONE, d0);
        t0 = cyc_now;
        cmd_wr(C_PUSH, c);
        do begin
            cmd_rd(C_DONE, d);
            if (++t > 20000) begin $display("    !! %s : completion timeout", what); errors++; break; end
        end while (d[31:0] == d0[31:0]);
        cycles = int'(cyc_now - t0);
        $display("    %-26s done after %0d clk (cmd 0x%016h)", what, cycles, c);
    endtask

    task automatic bb_run(input int in_base, input int in_len, input int w_base, input int w_len,
                          input int out_base, input int out_len, input int lat, input bit inj,
                          output logic [31:0] st, output logic [31:0] cyc);
        int t = 0;
        bb_wr(R_IN,  {4'd0, 12'(in_len),  5'd0, 11'(in_base)});
        bb_wr(R_WGT, {5'd0, 11'(w_len),   6'd0, 10'(w_base)});
        bb_wr(R_OUT, {7'd0, 9'(out_len),  5'd0, 11'(out_base)});
        bb_wr(R_LAT, 32'(lat));
        bb_wr(R_CTRL, {30'd0, inj, 1'b1});
        do begin
            bb_rd(R_STATUS, st);
            if (++t > 20000) begin $display("    !! blackbox done timeout"); errors++; break; end
        end while (!st[1]);
        bb_rd(R_CYC, cyc);
        $display("    blackbox done : STATUS=0x%0h CYCLES=%0d", st, cyc);
    endtask

    // compare two vectors, print the first few differences
    task automatic cmp_vec(input string tag, ref logic [DW-1:0] got[$], ref logic [DW-1:0] exp[$]);
        int bad = 0;
        if (got.size() != exp.size()) begin
            chk(tag, 0, $sformatf("size %0d vs %0d", got.size(), exp.size()));
            return;
        end
        foreach (exp[k]) begin
            if ($isunknown(got[k]) || got[k] !== exp[k]) begin
                if (bad < 3) $display("      %s beat %0d\n        got %h\n        exp %h", tag, k, got[k], exp[k]);
                bad++;
            end
        end
        chk(tag, bad == 0, $sformatf("%0d beats, mismatch %0d", exp.size(), bad));
    endtask

    // fill a region with poison so a result that never arrives cannot look right
    task automatic poison(input int c0, input int n, input int seed);
        logic [DW-1:0] p[$];
        mk_vec(p, n, seed, 3);
        l2_write_words(c0, p);
    endtask

    // backdoor (diagnostic only) : blackbox weight memory row
    function automatic logic [DW-1:0] wmem_peek(input int r);
        return {dut.u_top.u_core.u_bb.u_wmem.u_l1_sram.Usram_mimic_3.mem[r],
                dut.u_top.u_core.u_bb.u_wmem.u_l1_sram.Usram_mimic_2.mem[r],
                dut.u_top.u_core.u_bb.u_wmem.u_l1_sram.Usram_mimic_1.mem[r],
                dut.u_top.u_core.u_bb.u_wmem.u_l1_sram.Usram_mimic_0.mem[r]};
    endfunction

    // =========================================================================
    //  tests
    // =========================================================================
    logic [DW-1:0] W1[$], W2[$], X[$], G[$], got[$], exp_v[$];

    task automatic t0_reg();
        int e0 = errors;
        logic [31:0] d;
        logic [63:0] q;
        $display("\n=== T0 REG ===");
        bb_wr(R_IN,  32'h00C0_0000); bb_rd(R_IN,  d); chk("IN",  d == 32'h00C0_0000, $sformatf("0x%08h", d));
        bb_wr(R_WGT, 32'h0400_0000); bb_rd(R_WGT, d); chk("WGT", d == 32'h0400_0000, $sformatf("0x%08h", d));
        bb_wr(R_OUT, 32'h0040_0400); bb_rd(R_OUT, d); chk("OUT", d == 32'h0040_0400, $sformatf("0x%08h", d));
        bb_wr(R_LAT, 32'd100);       bb_rd(R_LAT, d); chk("LAT", d == 32'd100,       $sformatf("%0d", d));
        for (int w = 0; w < 8; w++) bb_wr(R_WIN + 4*w, 32'hA5A5_0000 + w);
        bb_rd(R_WIN + 4*7, d); chk("WIN[7]", d == 32'hA5A5_0007, $sformatf("0x%08h", d));
        bb_wr(R_GADDR, 32'd5); bb_wr(R_GCOMMIT, 32'd1); bb_rd(R_GADDR, d);
        chk("GADDR++", d == 32'd6, $sformatf("after commit %0d", d));
        // removed (512b compare) registers and the old upper half of the window
        bb_rd('h34, d, 1); bb_rd('h38, d, 1); bb_rd('hA0, d, 1); bb_wr('hA0, 32'd0, 1);
        // START with an out-of-range job is refused
        bb_wr(R_IN, {4'd0, 12'd2048, 5'd0, 11'd1}); bb_wr(R_CTRL, 32'd1, 1);
        bb_wr(R_IN, 32'd0);
        cmd_rd(C_VERSION, q); chk("CMD VERSION", q[31:0] == 32'h0001_0001, $sformatf("0x%08h", q[31:0]));
        cmd_rd(C_EXEC, q);    chk("start_allowed", q[1] == 1'b1, $sformatf("exec_status=%03b", q[2:0]));
        report("T0 REG", e0, "registers / SLVERR on removed addresses");
    endtask

    task automatic t_wgt(input string name, input int seed, input bit hs, ref logic [DW-1:0] W[$]);
        int e0 = errors, cy;
        int bad_bd = 0;
        $display("\n=== %s ===", name);
        mk_vec(W, W_DEPTH, seed, 1);
        l2_write_words(WGT_WORD, W);
        poison(WBACK_WORD, W_DEPTH, seed + 100);
        run_cmd("ch1_wgt LOAD 1024", mk_wload(WGT_WORD, W_DEPTH, 0, hs), cy);
        for (int r = 0; r < W_DEPTH; r++) if (wmem_peek(r) !== W[r]) bad_bd++;
        $display("    (diag) WMEM backdoor mismatch rows = %0d", bad_bd);
        run_cmd("ch1_wgt STORE 1024", mk_wstore(0, W_DEPTH, WBACK_WORD, hs), cy);
        l2_read_words(WBACK_WORD, W_DEPTH, got);
        cmp_vec("WMEM -> L2", got, W);
        // no string ?: here : XSim 2024.2 kernel crashes on it (see share2 FIX_SUMMARY)
        if (hs) report(name, e0, "weight LOAD/STORE handshake, 1024 rows");
        else    report(name, e0, "weight LOAD/STORE burst, 1024 rows");
    endtask

    task automatic t3_in();
        int e0 = errors, cy;
        $display("\n=== T3 IN_B ===");
        mk_vec(X, 192, 3, 0);
        l2_write_words(X_WORD, X);
        poison(XBACK_WORD, 192, 103);
        run_cmd("ch1_in LOAD 192", mk_load(X_WORD, 192, L1_IN_BASE), cy);
        run_cmd("ch1_in STORE 192", mk_store(L1_IN_BASE, 192, XBACK_WORD), cy);
        l2_read_words(XBACK_WORD, 192, got);
        cmp_vec("L1 -> L2", got, X);
        report("T3 IN_B", e0, "input LOAD/STORE burst, 192 beats");
    endtask

    task automatic t4_run();
        int e0 = errors, cy;
        logic [31:0] st, cyc;
        $display("\n=== T4 RUN ===");
        mk_vec(G, 64, 4, 2);
        gold_load(G);
        poison(OUT_WORD, 64, 104);
        bb_run(L1_IN_BASE, 192, 0, W_DEPTH, L1_OUT_BASE, 64, 100, 0, st, cyc);
        chk("STATUS", st[3:0] == 4'b0010, $sformatf("0x%0h (done, no err)", st));
        chk("CYCLES", cyc >= 192 + 1024 + 100 + 64 && cyc <= 192 + 1024 + 100 + 64 + 20,
            $sformatf("%0d (192 in + 1024 w + 100 lat + 64 out + guard)", cyc));
        run_cmd("ch1_in STORE 64 (output)", mk_store(L1_OUT_BASE, 64, OUT_WORD), cy);
        l2_read_words(OUT_WORD, 64, got);
        cmp_vec("output = Golden", got, G);
        // weight memory must be unchanged by the job
        run_cmd("ch1_wgt STORE 1024", mk_wstore(0, W_DEPTH, WBACK_WORD), cy);
        l2_read_words(WBACK_WORD, W_DEPTH, got);
        cmp_vec("weight kept", got, W2);
        report("T4 RUN", e0, "Golden 64 beats -> L1 OUT -> L2, in 192 / w 1024 / lat 100");
    endtask

    task automatic t5_run_hs();
        int e0 = errors, cy;
        logic [31:0] st, cyc;
        $display("\n=== T5 RUN_HS ===");
        mk_vec(G, G_DEPTH, 5, 2);
        gold_load(G);
        poison(OUT_WORD, G_DEPTH, 105);
        bb_run(0, 0, 0, 0, L1_DEPTH - G_DEPTH, G_DEPTH, 0, 0, st, cyc);
        chk("STATUS", st[3:0] == 4'b0010, $sformatf("0x%0h", st));
        run_cmd("ch1_in STORE 256 hs", mk_store(L1_DEPTH - G_DEPTH, G_DEPTH, OUT_WORD, 1), cy);
        l2_read_words(OUT_WORD, G_DEPTH, got);
        cmp_vec("output = Golden", got, G);
        report("T5 RUN_HS", e0, "Golden 256 beats (full depth) -> L1 1792~2047, handshake STORE");
    endtask

    task automatic t6_inject();
        int e0 = errors, cy, nbits;
        logic [31:0] st, cyc;
        logic [DW-1:0] diff;
        $display("\n=== T6 INJECT ===");
        mk_vec(G, 16, 6, 2);
        gold_load(G);
        bb_run(0, 0, 0, 0, L1_OUT_BASE, 16, 0, 1, st, cyc);
        run_cmd("ch1_in STORE 16", mk_store(L1_OUT_BASE, 16, OUT_WORD), cy);
        l2_read_words(OUT_WORD, 16, got);
        diff = got[0] ^ G[0];
        nbits = $countones(diff);
        chk("beat 0", nbits == 1 && diff[0] == 1'b1, $sformatf("%0d bit(s) differ, bit0=%0b", nbits, diff[0]));
        for (int k = 1; k < 16; k++) if (got[k] !== G[k]) begin chk("beat k>0", 0, $sformatf("beat %0d differs", k)); break; end
        report("T6 INJECT", e0, "PS-side compare catches a 1-bit error in beat 0");
    endtask

    task automatic t7_gap0();
        int e0 = errors, cy, t;
        logic [31:0] st, cyc;
        logic [63:0] q, d0, d;
        $display("\n=== T7 GAP0 ===");
        mk_vec(X, 192, 7, 0);
        l2_write_words(X_WORD, X);
        mk_vec(G, 8, 7, 2);
        gold_load(G);
        bb_wr(R_IN,  {4'd0, 12'd192, 5'd0, 11'd0});
        bb_wr(R_WGT, 32'd0);
        bb_wr(R_OUT, {7'd0, 9'd8, 5'd0, 11'(L1_OUT_BASE)});
        bb_wr(R_LAT, 32'd0);
        cmd_rd(C_DONE, d0);
        cmd_wr(C_PUSH, mk_load(X_WORD, 192, L1_IN_BASE));
        // START while the LOAD is in flight must be refused
        bb_wr(R_CTRL, 32'd1, 1);
        // then START at the first moment it is allowed
        t = 0;
        do begin cmd_rd(C_EXEC, q); if (++t > 20000) begin errors++; break; end end while (!q[1]);
        bb_wr(R_CTRL, 32'd1);
        cmd_rd(C_DONE, d);
        chk("LOAD counted", d[31:0] == d0[31:0] + 1, $sformatf("completed %0d -> %0d", d0[31:0], d[31:0]));
        t = 0;
        do begin bb_rd(R_STATUS, st); if (++t > 20000) begin errors++; break; end end while (!st[1]);
        chk("STATUS", st[3:0] == 4'b0010, $sformatf("0x%0h (err_start_busy must be 0)", st));
        run_cmd("ch1_in STORE 192", mk_store(L1_IN_BASE, 192, XBACK_WORD), cy);
        l2_read_words(XBACK_WORD, 192, got);
        cmp_vec("input kept (last beat too)", got, X);
        report("T7 GAP0", e0, "START refused while LOAD in flight, then START at once : no lost beat");
    endtask

    task automatic t8_top();
        int e0 = errors, cy;
        logic [DW-1:0] T[$];
        $display("\n=== T8 TOP ===");
        mk_vec(T, 64, 8, 0);
        l2_write_words(NWORDS - 64, T);
        // ch1_in : L2 top -> L1 top -> L2
        poison(XBACK_WORD, 64, 108);
        run_cmd("ch1_in LOAD top", mk_load(NWORDS - 64, 64, L1_DEPTH - 64), cy);
        run_cmd("ch1_in STORE top", mk_store(L1_DEPTH - 64, 64, XBACK_WORD), cy);
        l2_read_words(XBACK_WORD, 64, got);
        cmp_vec("ch1_in top", got, T);
        // ch1_wgt : L2 top -> WMEM top -> L2
        poison(WBACK_WORD, 64, 109);
        run_cmd("ch1_wgt LOAD top", mk_wload(NWORDS - 64, 64, W_DEPTH - 64), cy);
        run_cmd("ch1_wgt STORE top", mk_wstore(W_DEPTH - 64, 64, WBACK_WORD), cy);
        l2_read_words(WBACK_WORD, 64, got);
        cmp_vec("ch1_wgt top", got, T);
        // STORE to the L2 top as well
        poison(NWORDS - 64, 64, 110);
        run_cmd("ch1_in STORE -> L2 top", mk_store(L1_DEPTH - 64, 64, NWORDS - 64), cy);
        l2_read_words(NWORDS - 64, 64, got);
        cmp_vec("L2 top STORE", got, T);
        report("T8 TOP", e0, "L2 0x7FC0~0x7FFF <-> L1 1984~2047 / WMEM 960~1023");
    endtask

    task automatic t9_opcode();
        int e0 = errors;
        logic [63:0] a0, a1, c;
        $display("\n=== T9 OPCODE ===");
        cmd_rd(C_ACCEPT, a0);
        c = '0; c[62:60] = 3'b000; c[59:58] = 2'b10;            // opcode 0 : no channel
        cmd_wr(C_PUSH, c, 1);
        cmd_rd(C_ACCEPT, a1);
        chk("not accepted", a1 == a0, $sformatf("accepted %0d -> %0d", a0, a1));
        cmd_wr(C_ERRORS, 64'h1F);                                // W1C the sticky error bits
        report("T9 OPCODE", e0, "opcode 0 refused with SLVERR");
    endtask

    // =========================================================================
    //  CH2 helpers (PS-style)
    // =========================================================================
    task automatic gold2_load(ref logic [DW-1:0] v[$]);
        bb_wr(R2_GADDR, 32'd0);
        foreach (v[k]) begin
            for (int w = 0; w < DW/32; w++) bb_wr(R_WIN + 4*w, v[k][w*32 +: 32]);
            bb_wr(R2_GCOMMIT, 32'd1);
        end
    endtask

    // one row of the CH2 input (sel 0) / weight (sel 1) memory through DBG2
    task automatic dbg2_read(input bit sel, input int row, output logic [DW-1:0] v);
        logic [31:0] st, d;
        int t = 0;
        bb_wr(R2_DBG, {15'd0, sel, 5'd0, 11'(row)});
        do begin
            bb_rd(R2_STATUS, st);
            if (++t > 1000) begin $display("    !! DBG2 timeout"); errors++; break; end
        end while (!(st[2] && !st[0]));
        for (int w = 0; w < DW/32; w++) begin
            bb_rd(R2_DBG_DATA + 4*w, d);
            v[w*32 +: 32] = d;
        end
    endtask

    task automatic dbg2_read_rows(input bit sel, input int row0, input int n, ref logic [DW-1:0] v[$]);
        logic [DW-1:0] r;
        v = {};
        for (int k = 0; k < n; k++) begin
            dbg2_read(sel, row0 + k, r);
            v.push_back(r);
        end
    endtask

    // backdoor (diagnostic only)
    function automatic logic [DW-1:0] mem2_peek(input bit sel, input int r);
        if (sel)
            return {dut.u_top.u_core.u_bb2.u_wmem.u_l1_sram.Usram_mimic_3.mem[r],
                    dut.u_top.u_core.u_bb2.u_wmem.u_l1_sram.Usram_mimic_2.mem[r],
                    dut.u_top.u_core.u_bb2.u_wmem.u_l1_sram.Usram_mimic_1.mem[r],
                    dut.u_top.u_core.u_bb2.u_wmem.u_l1_sram.Usram_mimic_0.mem[r]};
        else
            return {dut.u_top.u_core.u_bb2.u_imem.u_l1_sram.Usram_mimic_3.mem[r],
                    dut.u_top.u_core.u_bb2.u_imem.u_l1_sram.Usram_mimic_2.mem[r],
                    dut.u_top.u_core.u_bb2.u_imem.u_l1_sram.Usram_mimic_1.mem[r],
                    dut.u_top.u_core.u_bb2.u_imem.u_l1_sram.Usram_mimic_0.mem[r]};
    endfunction

    task automatic bb2_cfg(input int in_base, input int in_len, input int w_base, input int w_len,
                           input int nb, input int h, input int w, input int lat);
        bb_wr(R2_IN,    {4'd0, 12'(in_len), 5'd0, 11'(in_base)});
        bb_wr(R2_WGT,   {6'd0, 10'(w_len),  7'd0, 9'(w_base)});
        bb_wr(R2_SHAPE, {1'b0, 7'(nb), 4'd0, 10'(h), 10'(w)});
        bb_wr(R2_LAT,   32'(lat));
    endtask

    task automatic bb2_wait_done(output logic [31:0] st, output logic [31:0] cyc);
        int t = 0;
        do begin
            bb_rd(R2_STATUS, st);
            if (++t > 20000) begin $display("    !! blackbox_nl done timeout"); errors++; break; end
        end while (!st[1]);
        bb_rd(R2_CYC, cyc);
        $display("    blackbox_nl done : STATUS2=0x%0h CYCLES2=%0d", st, cyc);
    endtask

    task automatic wait_cmd_count(input string what, input logic [31:0] target);
        logic [63:0] d;
        int t = 0;
        do begin
            cmd_rd(C_DONE, d);
            if (++t > 20000) begin $display("    !! %s : completion timeout", what); errors++; break; end
        end while (d[31:0] != target);
    endtask

    // poison / read the L2 words a ch2 STORE of nb x h x w beats can touch (both cols, rows 0..n-1)
    task automatic c2_poison_out(input int w14, input int nrow, input int seed);
        poison(c256_of(w14, 0), nrow, seed);
        poison(c256_of(w14, 1), nrow, seed + 1);
    endtask

    // full ch2 output job : Golden -> blackbox_nl -> ch2_in STORE -> L2, then compare by position
    task automatic t_c2run(input string name, input int seed, input int nb, input int h, input int w,
                           input bit prec, input bit hs, input bit cmd_first, input bit inj,
                           input int in_len, input int w_len, input int lat);
        int e0 = errors, n, nrow, bad = 0, nbits;
        logic [31:0] st, cyc;
        logic [63:0] d0;
        logic [DW-1:0] P0[$], P1[$], rb[$];
        logic [DW-1:0] e;
        $display("\n=== %s : NB=%0d H=%0d W=%0d prec=%0d hs=%0d cmd_first=%0d inj=%0d ===",
                 name, nb, h, w, prec, hs, cmd_first, inj);
        n    = nb * h * w;
        nrow = ((nb + 1) / 2) * h * w + 1;                  // +1 : the row just above must stay poison
        mk_vec(G, n, seed, 2);
        gold2_load(G);
        c2_poison_out(OUT2_W14, nrow, 200 + seed);
        mk_vec(P0, nrow, 200 + seed, 3);                    // what poison() wrote, for the untouched check
        mk_vec(P1, nrow, 201 + seed, 3);
        bb2_cfg(0, in_len, 0, w_len, nb, h, w, lat);
        cmd_rd(C_DONE, d0);
        if (cmd_first) cmd_wr(C_PUSH, mk_c2_store(OUT2_W14, h, w, prec, hs));
        bb_wr(R2_CTRL, {28'd0, prec, hs, inj, 1'b1});
        if (!cmd_first) begin
            repeat (200) @(negedge aclk);                   // blackbox_nl reaches the output phase and waits
            cmd_wr(C_PUSH, mk_c2_store(OUT2_W14, h, w, prec, hs));
        end
        bb2_wait_done(st, cyc);
        chk("STATUS2", st[3] == 1'b0 && st[1] == 1'b1, $sformatf("0x%0h (done, no err)", st));
        wait_cmd_count("ch2_in STORE", d0[31:0] + 1);
        // compare : every beat at its (jp, col, h, w) position
        for (int k = 0; k < n; k++) begin
            int c = c2_out_word(k, OUT2_W14, nb, h, w);
            rb = {};
            l2_read_words(c, 1, rb);
            e = G[k];
            if (k == 0 && inj) e[0] = ~e[0];
            if (rb[0] !== e) begin
                if (bad < 3) $display("      beat %0d -> L2 0x%04h\n        got %h\n        exp %h", k, c, rb[0], e);
                bad++;
            end
        end
        if (inj) begin
            l2_read_words(c2_out_word(0, OUT2_W14, nb, h, w), 1, rb);
            nbits = $countones(rb[0] ^ G[0]);
            chk("inject", nbits == 1, $sformatf("beat 0 differs in %0d bit(s)", nbits));
        end
        chk("output = Golden", bad == 0, $sformatf("%0d beats at their (ch,h,w) positions, mismatch %0d", n, bad));
        // row just above the written range, both cols : untouched
        l2_read_words(c256_of(OUT2_W14 + nrow - 1, 0), 1, rb);
        chk("above col0", rb[0] === P0[nrow - 1], "poison kept");
        l2_read_words(c256_of(OUT2_W14 + nrow - 1, 1), 1, rb);
        chk("above col1", rb[0] === P1[nrow - 1], "poison kept");
        report(name, e0, $sformatf("ch2 STORE %0d beats (NB %0d, %0dx%0d), cycles %0d", n, nb, h, w, cyc));
    endtask

    // =========================================================================
    //  CH2 tests
    // =========================================================================
    logic [DW-1:0] W2c[$], X2c[$];

    task automatic t_c2w(input string name, input int seed, input bit hs);
        int e0 = errors, cy, bad_bd = 0;
        $display("\n=== %s ===", name);
        mk_vec(W2c, W2_DEPTH, seed, 1);
        l2_write_words(WGT2_WORD, W2c);
        run_cmd("ch2_wgt LOAD 512", mk_c2w_load(WGT2_WORD, W2_DEPTH, 0, hs), cy);
        for (int r = 0; r < W2_DEPTH; r++) if (mem2_peek(1, r) !== W2c[r]) bad_bd++;
        $display("    (diag) CH2 WMEM backdoor mismatch rows = %0d", bad_bd);
        dbg2_read_rows(1, 0, W2_DEPTH, got);
        cmp_vec("WMEM2 via DBG2", got, W2c);
        if (hs) report(name, e0, "ch2 weight LOAD handshake, 512 rows, checked through DBG2");
        else    report(name, e0, "ch2 weight LOAD burst, 512 rows, checked through DBG2");
    endtask

    task automatic t_c2in(input string name, input int seed, input bit hs, input int dst, input int n);
        int e0 = errors, cy, bad_bd = 0;
        $display("\n=== %s ===", name);
        mk_vec(X2c, n, seed, 0);
        l2_write_words(X2_WORD, X2c);
        run_cmd("ch2_in LOAD", mk_c2_load(X2_WORD, n, dst, hs), cy);
        for (int r = 0; r < n; r++) if (mem2_peek(0, dst + r) !== X2c[r]) bad_bd++;
        $display("    (diag) CH2 IMEM backdoor mismatch rows = %0d", bad_bd);
        dbg2_read_rows(0, dst, n, got);
        cmp_vec("IMEM2 via DBG2", got, X2c);
        if (hs) report(name, e0, $sformatf("ch2 input LOAD handshake, %0d beats -> row %0d", n, dst));
        else    report(name, e0, $sformatf("ch2 input LOAD burst, %0d beats -> row %0d", n, dst));
    endtask

    task automatic t17_fence2();
        int e0 = errors, t;
        logic [31:0] st, cyc;
        logic [63:0] d0;
        $display("\n=== T17 FENCE2 ===");
        // (a) START2 / DBG2 refused while a ch2 LOAD is in flight
        mk_vec(X2c, 192, 17, 0);
        l2_write_words(X2_WORD, X2c);
        bb2_cfg(0, 0, 0, 0, 1, 1, 1, 0);
        cmd_rd(C_DONE, d0);
        cmd_wr(C_PUSH, mk_c2_load(X2_WORD, 192, 0));
        bb_wr(R2_CTRL, 32'd1, 1);
        bb_wr(R2_DBG, 32'd0, 1);
        wait_cmd_count("ch2_in LOAD", d0[31:0] + 1);
        // (b) ch2 STORE waiting for blackbox_nl : CH1 blackbox still runs
        mk_vec(G, 8, 17, 2);
        gold_load(G);
        poison(OUT_WORD, 8, 117);
        mk_vec(G, 4, 18, 2);
        gold2_load(G);
        c2_poison_out(OUT2_W14, 5, 118);
        bb2_cfg(0, 192, 0, 0, 1, 1, 4, 0);
        cmd_rd(C_DONE, d0);
        cmd_wr(C_PUSH, mk_c2_store(OUT2_W14, 1, 4, 0));
        repeat (20) @(negedge aclk);
        bb_run(0, 0, 0, 0, L1_OUT_BASE, 8, 0, 0, st, cyc);
        chk("CH1 during ch2 STORE", st[3:0] == 4'b0010, $sformatf("STATUS=0x%0h", st));
        bb_wr(R2_CTRL, 32'd1);
        bb2_wait_done(st, cyc);
        wait_cmd_count("ch2_in STORE", d0[31:0] + 1);
        begin
            logic [DW-1:0] rb[$];
            int bad = 0;
            for (int k = 0; k < 4; k++) begin
                l2_read_words(c2_out_word(k, OUT2_W14, 1, 1, 4), 1, rb);
                if (rb[0] !== G[k]) bad++;
            end
            chk("ch2 output", bad == 0, $sformatf("4 beats, mismatch %0d", bad));
        end
        report("T17 FENCE2", e0, "START2/DBG2 refused during ch2 LOAD ; CH1 runs while ch2 STORE waits");
    endtask

    task automatic t_c2_all();
        t_c2w("T10 C2W_B",  10, 0);
        t_c2w("T11 C2W_HS", 11, 1);
        t_c2in("T12 C2IN_B",  12, 0, 0, 192);
        t_c2in("T13 C2IN_HS", 13, 1, 1024, 192);
        t_c2run("T14 C2RUN",    14, 3, 2, 8, 0, 0, 1, 0, 192, W2_DEPTH, 50);
        t_c2run("T15 C2RUN_HS", 15, 4, 8, 8, 1, 1, 0, 0, 0, 0, 0);
        t_c2run("T16 C2INJ",    16, 1, 1, 16, 0, 0, 1, 1, 0, 0, 0);
        t17_fence2();
    endtask

    // =========================================================================
    initial begin
        $display("tb_bb256_system : 256b CH1 blackbox_ip + CH2 blackbox_nl via PS interface");
        do_reset();
        t0_reg();
        t_wgt("T1 WGT_B",  1, 0, W1);
        t_wgt("T2 WGT_HS", 2, 1, W2);
        t3_in();
        t4_run();
        t5_run_hs();
        t6_inject();
        t7_gap0();
        t8_top();
        t9_opcode();
        t_c2_all();
        chk("port conflicts", conflicts == 0, $sformatf("%0d clocks with PE/NoC on the same memory", conflicts));

        $display("\n==================== SUMMARY ====================");
        foreach (results[i]) $display("  %s", results[i]);
        $display("  tests: %0d pass, %0d fail", npass, nfail);
        if (errors == 0) $display("PASS (errors=0)");
        else             $display("FAIL (errors=%0d)", errors);
        $finish;
    end

    initial begin
        #(64'd400_000_000);
        $display("FAIL (errors=global timeout)");
        $finish;
    end

endmodule
