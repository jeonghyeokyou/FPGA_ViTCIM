`timescale 1ns/1ps
// =============================================================================
//  bb256_pkg  -  256b blackbox_ip 시스템 검증 공통 상수 / 명령어 생성 / 주소 공식
//
//  ch1_in 과 ch1_wgt 가 둘 다 256b 이므로 L2 안의 배치가 같다 (4 lane x 64b):
//    채널 워드 c (15b) = {grp[2:0], quad[1:0], row[9:0]}
//    lane b 는 block quad*4+b 의 같은 row  (SRAM_group_decoder.sv GRP_CH_1_IN / GRP_CH_1_WGT)
//    -> ch0 64b 워드 = (grp<<14) | ((quad*4+b)<<10) | row ,  PS 바이트 주소 = ch0 * 8
//  SRC_W = clog2(GROUPS) + clog2(ADDRESS_ROW*BLOCKS/4) = 3 + 12 = 15
//
//  명령어 필드 (rtl/base/cmd_decoder_channel_1_in.sv, rtl/fix/cmd_decoder_channel_1_wgt.sv)
//    ch1_in  LOAD  (001) : L2 [SRC_W+39:40]=[54:40], len-1 [39:29], L1 [28:18], multicast [14:7]
//    ch1_in  STORE (010) : L2 [SRC_W+40:41]=[55:41], len-1 [40:27], cluster [26:24], L1 [23:13]
//    ch1_wgt LOAD  (101) : L2 [SRC_W+38:39]=[53:39], len-1 [38:29], WMEM [28:19], multicast [14:7]
//    ch1_wgt STORE (110) : L2 [SRC_W+39:40]=[54:40], len-1 [39:27], cluster [26:24], WMEM [23:14]
//    [59:58] = control mode : LOAD 00 burst / 01 handshake, STORE 10 burst / 11 handshake
// =============================================================================
package bb256_pkg;

    localparam int GROUPS      = 8;
    localparam int BLOCKS      = 16;
    localparam int ADDRESS_ROW = 1024;
    localparam int BW_CH0      = 64;
    localparam int DW          = 256;
    localparam int RATIO       = DW / BW_CH0;                                  // 4 lanes

    localparam int ROW_BITS    = $clog2(ADDRESS_ROW);                          // 10
    localparam int IN_GRP      = $clog2(ADDRESS_ROW * BLOCKS / RATIO);         // 12
    localparam int IN_GRP_CH0  = $clog2(ADDRESS_ROW * BLOCKS);                 // 14
    localparam int SRC_W       = $clog2(GROUPS) + IN_GRP;                      // 15
    localparam int NWORDS      = 1 << SRC_W;                                   // 32768 x 32 B = 1 MiB

    localparam int L1_DEPTH    = 2048;
    localparam int W_DEPTH     = 1024;
    localparam int G_DEPTH     = 256;

    // ---- memory map (256b word index ; PS byte = see c256_to_ch0) -----------
    localparam int X_WORD      = 'h0000;   // input image           (grp 0 quad 0)
    localparam int WGT_WORD    = 'h0800;   // weight image          (grp 0 quad 2)
    localparam int WBACK_WORD  = 'h1000;   // ch1_wgt STORE target  (grp 1 quad 0)
    localparam int OUT_WORD    = 'h2800;   // ch1_in STORE (output) (grp 2 quad 2)
    localparam int XBACK_WORD  = 'h3000;   // ch1_in STORE (input readback) (grp 3 quad 0)

    localparam int L1_IN_BASE  = 0;
    localparam int L1_OUT_BASE = 1024;

    function automatic int c256_to_ch0(input int c, input int lane);
        int grp, quad, row;
        grp  = c >> IN_GRP;
        quad = (c >> ROW_BITS) & ((BLOCKS / RATIO) - 1);
        row  = c & (ADDRESS_ROW - 1);
        return (grp << IN_GRP_CH0) | ((quad * RATIO + lane) << ROW_BITS) | row;
    endfunction

    // ---- ch1_in LOAD (L2 -> L1) ----------------------------------------------
    function automatic logic [63:0] mk_load(input int l2_word, input int nbeats,
                                            input int l1_word, input bit handshake = 0);
        logic [63:0] c;
        c = '0;
        c[62:60]          = 3'b001;
        c[59:58]          = handshake ? 2'b01 : 2'b00;
        c[57]             = 1'b0;                     // prec_mode
        c[SRC_W+39:40]    = l2_word[SRC_W-1:0];
        c[39:29]          = 11'(nbeats - 1);
        c[28:18]          = 11'(l1_word);
        c[17:15]          = 3'b000;                   // resize
        c[14:7]           = 8'h01;                    // multicast
        return c;
    endfunction

    // ---- ch1_in STORE (L1 -> L2) ---------------------------------------------
    function automatic logic [63:0] mk_store(input int l1_word, input int nbeats,
                                             input int l2_word, input bit handshake = 0);
        logic [63:0] c;
        c = '0;
        c[62:60]          = 3'b010;
        c[59:58]          = handshake ? 2'b11 : 2'b10;
        c[SRC_W+40:41]    = l2_word[SRC_W-1:0];
        c[40:27]          = 14'(nbeats - 1);
        c[26:24]          = 3'b000;                   // cluster select
        c[23:13]          = 11'(l1_word);
        return c;
    endfunction

    // ---- ch1_wgt LOAD burst (L2 -> blackbox weight memory) ---------------------
    function automatic logic [63:0] mk_wload(input int l2_word, input int nbeats,
                                             input int w_row, input bit handshake = 0);
        logic [63:0] c;
        c = '0;
        c[62:60]          = 3'b101;
        c[59:58]          = handshake ? 2'b01 : 2'b00;
        c[57]             = 1'b0;                     // load_mode : burst
        c[SRC_W+38:39]    = l2_word[SRC_W-1:0];
        c[38:29]          = 10'(nbeats - 1);
        c[28:19]          = 10'(w_row);
        c[14:7]           = 8'h01;                    // multicast
        return c;
    endfunction

    // ---- ch1_wgt STORE (blackbox weight memory -> L2) --------------------------
    function automatic logic [63:0] mk_wstore(input int w_row, input int nbeats,
                                              input int l2_word, input bit handshake = 0);
        logic [63:0] c;
        c = '0;
        c[62:60]          = 3'b110;
        c[59:58]          = handshake ? 2'b11 : 2'b10;
        c[SRC_W+39:40]    = l2_word[SRC_W-1:0];
        c[39:27]          = 13'(nbeats - 1);
        c[26:24]          = 3'b000;                   // cluster select
        c[23:14]          = 10'(w_row);
        return c;
    endfunction

    // =========================================================================
    //  CH2 (rtl/fix/cmd_decoder_channel_2_in.sv, rtl/base|fix/cmd_decoder_channel_2_wgt.sv)
    //    ch2_in  LOAD  (011) : L2 [53:39] (15b), len-1 [38:25], PE/Accum [24], dest [23:10]
    //                          L2 은 {c[14:11], c[9:0]} (14b) 만 +1 하고 c[10] (col) 은 고정
    //    ch2_in  STORE (100) : start w14 [53:40], prec [57], H [39:30], W [29:20]
    //                          beat (jp, col, h, w) -> a14 = w14 + w + h*W + jp*H*W
    //                          -> 256b word {a14[13:10], col, a14[9:0]}
    //    ch2_wgt LOAD  (111) : L2 [54:40] (15b, +1), len-1 [39:31], dest [30:22]
    // =========================================================================
    localparam int I2_DEPTH    = 2048;
    localparam int W2_DEPTH    = 512;
    localparam int WGT2_WORD   = 'h4000;   // ch2 weight image   (grp 4 quad 0)
    localparam int X2_WORD     = 'h5000;   // ch2 input image    (grp 5 quad 0, col 0)
    localparam int OUT2_W14    = 'h3000;   // ch2 STORE start (14b) -> 256b words 0x6000 (col 0) / 0x6400 (col 1)

    function automatic int w14_of(input int c);           // 256b word -> 14b (col dropped)
        return ((c >> 11) << 10) | (c & 1023);
    endfunction
    function automatic int c256_of(input int a14, input int col);
        return ((a14 >> 10) << 11) | (col << 10) | (a14 & 1023);
    endfunction

    function automatic logic [63:0] mk_c2_load(input int l2_word, input int nbeats,
                                               input int dst_row, input bit handshake = 0);
        logic [63:0] c;
        c = '0;
        c[62:60]          = 3'b011;
        c[59:58]          = handshake ? 2'b01 : 2'b00;
        c[57]             = 1'b0;                     // prec_mode
        c[53:39]          = 15'(l2_word);
        c[38:25]          = 14'(nbeats - 1);
        c[24]             = 1'b0;                     // destination : PE
        c[23:10]          = 14'(dst_row);
        return c;
    endfunction

    function automatic logic [63:0] mk_c2_store(input int w14, input int h, input int w,
                                                input bit prec, input bit handshake = 0);
        logic [63:0] c;
        c = '0;
        c[62:60]          = 3'b100;
        c[59:58]          = handshake ? 2'b11 : 2'b10;
        c[57]             = prec;                     // channel-field layout of the beat address
        c[53:40]          = 14'(w14);
        c[39:30]          = 10'(h);
        c[29:20]          = 10'(w);
        return c;
    endfunction

    function automatic logic [63:0] mk_c2w_load(input int l2_word, input int nbeats,
                                                input int dst_row, input bit handshake = 0);
        logic [63:0] c;
        c = '0;
        c[62:60]          = 3'b111;
        c[59:58]          = handshake ? 2'b01 : 2'b00;
        c[54:40]          = 15'(l2_word);
        c[39:31]          = 9'(nbeats - 1);
        c[30:22]          = 9'(dst_row);
        return c;
    endfunction

    // 256b L2 word of output beat k of a blackbox_nl job (same order as blackbox_nl.sv)
    function automatic int c2_out_word(input int k, input int w14, input int nb, input int h, input int w);
        int jp, col, hh, ww, n;
        n = 0;
        for (jp = 0; 2 * jp < nb; jp++)
            for (hh = 0; hh < h; hh++)
                for (ww = 0; ww < w; ww++)
                    for (col = 0; col < 2 && 2 * jp + col < nb; col++) begin
                        if (n == k) return c256_of(w14 + ww + hh * w + jp * h * w, col);
                        n++;
                    end
        return -1;
    endfunction

    // ---- deterministic test data --------------------------------------------
    //  tag : 0 = input, 1 = weight, 2 = Golden, 3 = poison ; k = row
    function automatic logic [DW-1:0] mk_word(input int seed, input int tag, input int k);
        logic [DW-1:0] v;
        int unsigned s;
        s = 32'h9E37_79B9 * (seed + 1) ^ (tag << 24) ^ k;
        for (int i = 0; i < DW / 32; i++) begin
            s = s * 32'd1664525 + 32'd1013904223;      // LCG
            v[i*32 +: 32] = s ^ {tag[7:0], 8'(i), 16'(k)};
        end
        return v;
    endfunction

endpackage
