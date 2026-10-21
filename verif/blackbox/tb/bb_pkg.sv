`timescale 1ns/1ps
// =============================================================================
//  bb_pkg  -  Blackbox 검증 공통 상수 / 명령어 생성 함수 (BLACKBOX_TASK.md 8절)
//
//  SRC_W (명령어의 L2 주소 필드 폭) 는 L2 크기에서 계산한다 (하드코딩 금지):
//    SRC_W = clog2(GROUPS) + clog2(ADDRESS_ROW * BLOCKS / (512/64))   -> 14 (1 MiB)
//  근거: TOP_L2_cache.ADDR_BIT_TOTAL_CHANNEL_1_IN_GRP,
//        cmd_decoder_channel_1_in.sv  LOAD  [SOURCE_ADDR_BIT+39:40] / [39:29] / [28:18]
//                                     STORE [SOURCE_ADDR_BIT+40:41] / [40:27] / [26:13]
//
//  ch1_to_ch0 : ch1_in 512b 워드의 lane 하나가 L2 안에서 어느 ch0 64b 워드에
//  저장되는지 (SRAM_group_decoder.sv 의 GRP_CH_1_IN / GRP_CH_0 매핑).
//  -> FINDING_l2_ch0_ch1_layout.md 참고. gen_vectors.py 의 ch1_to_ch0 와 같은 식.
// =============================================================================
package bb_pkg;

    localparam int GROUPS      = 8;
    localparam int BLOCKS      = 16;
    localparam int ADDRESS_ROW = 1024;
    localparam int BW_CH0      = 64;
    localparam int BW_CH1      = 512;
    localparam int RATIO       = BW_CH1 / BW_CH0;                               // 8 lanes

    localparam int ROW_BITS    = $clog2(ADDRESS_ROW);                           // 10
    localparam int IN_GRP_CH1  = $clog2(ADDRESS_ROW * BLOCKS / RATIO);          // 11
    localparam int IN_GRP_CH0  = $clog2(ADDRESS_ROW * BLOCKS);                  // 14
    localparam int SRC_W       = $clog2(GROUPS) + IN_GRP_CH1;                   // 14
    localparam int CH0_AW      = $clog2(GROUPS) + IN_GRP_CH0;                   // 17

    // 메모리 맵 (4.1 / 4.2절)
    localparam int X_CH1_WORD   = 'h0_0000 / 64;     // 0x0000
    localparam int OUT_CH1_WORD = 'hA_0000 / 64;     // 0x2800
    localparam int L1_IN_BASE   = 0;
    localparam int L1_OUT_BASE  = 1024;

    localparam int NX = 192;   // X beats
    localparam int NY = 16;    // Golden beats

    // ---- LOAD (L2 -> L1) ---------------------------------------------------
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

    // ---- STORE (L1 -> L2) --------------------------------------------------
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

    // ---- ch1_in word / lane -> ch0 64b word address ------------------------
    function automatic int ch1_to_ch0(input int c, input int lane);
        int grp, pair, row;
        grp  = c >> IN_GRP_CH1;
        pair = (c >> ROW_BITS) & ((BLOCKS / RATIO) - 1);
        row  = c & (ADDRESS_ROW - 1);
        return (grp << IN_GRP_CH0) | ((pair * RATIO + lane) << ROW_BITS) | row;
    endfunction

    // =========================================================================
    //  256b channels (ch1_wgt / ch2_in) : 4 lanes of 64b
    //    in-group addr = {quad[1:0], row[9:0]} ; lane b lives in block quad*4+b
    //    (SRAM_group_decoder.sv GRP_CH_1_WGT / GRP_CH_2_IN)
    // =========================================================================
    localparam int RATIO_256  = 256 / BW_CH0;                               // 4
    localparam int IN_GRP_256 = $clog2(ADDRESS_ROW * BLOCKS / RATIO_256);   // 12
    localparam int SRC_W_256  = $clog2(GROUPS) + IN_GRP_256;                // 15 (ch1_wgt, ch2_in)

    // memory map (256b word = 32 B)
    localparam int WGT_W_WORD   = 'h1_0000 / 32;   // 0x0800 : weight image, 1024 rows (quad 2 of group 0)
    localparam int ZERO_W_WORD  = 'h1_8000 / 32;   // 0x0C00 : 1024 zero rows (quad 3) - clears L1 weight
    localparam int NWROWS       = 1024;
    // ch2_in store destinations (14b = ch1_in 512b word address)
    localparam int C2_PSUM_WORD = OUT_CH1_WORD + 'h40;   // 0x2840 (byte 0xA_1000)
    localparam int C2_OUT8_WORD = OUT_CH1_WORD + 'h80;   // 0x2880 (byte 0xA_2000)

    function automatic int c256_to_ch0(input int c, input int lane);
        int grp, quad, row;
        grp  = c >> IN_GRP_256;
        quad = (c >> ROW_BITS) & ((BLOCKS / RATIO_256) - 1);
        row  = c & (ADDRESS_ROW - 1);
        return (grp << IN_GRP_CH0) | ((quad * RATIO_256 + lane) << ROW_BITS) | row;
    endfunction

    // ---- ch1_wgt LOAD (cmd_idx 101) : rtl cmd_decoder_channel_1_wgt.sv 259~273 ----
    function automatic logic [63:0] mk_wload_burst(input int l2_word, input int nbeats,
                                                   input int l1_word, input bit handshake = 0);
        logic [63:0] c;
        c = '0;
        c[62:60]             = 3'b101;
        c[59:58]             = handshake ? 2'b01 : 2'b00;
        c[57]                = 1'b0;                    // load_mode : burst
        c[SRC_W_256+38:39]   = l2_word[SRC_W_256-1:0];
        c[38:29]             = 10'(nbeats - 1);
        c[28:19]             = 10'(l1_word);
        c[14:7]              = 8'h01;                   // multicast (one-hot cluster)
        return c;
    endfunction

    function automatic logic [63:0] mk_wload_custom(input int l2_word, input int grp, input int lcu,
                                                    input int lcc, input bit handshake = 0);
        logic [63:0] c;
        c = '0;
        c[62:60]             = 3'b101;
        c[59:58]             = handshake ? 2'b01 : 2'b00;
        c[57]                = 1'b1;                    // load_mode : custom
        c[SRC_W_256+38:39]   = l2_word[SRC_W_256-1:0];
        c[38:36]             = 3'(grp);                 // wgt_grp_sel : grp+1 groups
        c[35:34]             = 2'(lcu);                 // LCU_sel     : lcu+1 LCUs
        c[33:32]             = 2'(lcc);                 // LCC_sel     : 2*(lcc+1) rows per LCC
        c[14:7]              = 8'h01;
        return c;
    endfunction

    // ---- ch1_wgt STORE (cmd_idx 110) : rtl cmd_decoder_channel_1_wgt.sv 525~535 ----
    //   cluster array [26:14] (= {cluster 3b, local 10b}) -> L2 [SRC_W_256+39:40], length-1 [39:27]
    localparam int WSTORE_W_WORD = 'h2_0000 / 32;    // 0x1000 : ch1_wgt store destination (group 1)
    function automatic logic [63:0] mk_wstore(input int l1_word, input int nbeats,
                                              input int l2_word, input bit handshake = 0);
        logic [63:0] c;
        c = '0;
        c[62:60]             = 3'b110;
        c[59:58]             = handshake ? 2'b11 : 2'b10;
        c[SRC_W_256+39:40]   = l2_word[SRC_W_256-1:0];
        c[39:27]             = 13'(nbeats - 1);
        c[26:24]             = 3'b000;                  // cluster select
        c[23:14]             = 10'(l1_word);
        return c;
    endfunction

    // custom load : beat count and L1 (cluster array) row of beat i
    //   row = grp*96 + LCU*32 + LCC*8 + r   (3 LCU per grp, 4 LCC per LCU, 8 rows per LCC)
    function automatic int wcustom_beats(input int grp, input int lcu, input int lcc);
        return (grp + 1) * (lcu + 1) * (lcc + 1) * 8;
    endfunction
    function automatic int wcustom_row(input int i, input int grp, input int lcu, input int lcc);
        int rows, per_lcu, per_grp, g, u, b, r, rem;
        rows    = 2 * (lcc + 1);
        per_lcu = 4 * rows;
        per_grp = (lcu + 1) * per_lcu;
        g   = i / per_grp;   rem = i % per_grp;
        u   = rem / per_lcu; rem = rem % per_lcu;
        b   = rem / rows;    r   = rem % rows;
        return g * 96 + u * 32 + b * 8 + r;
    endfunction

    // ---- ch2_in STORE (cmd_idx 100) : rtl cmd_decoder_channel_2_in.sv 399~406 ----
    //   L2 address of beat (j, h, w) = start + (j>>1)*H*W + h*W + w ; j&1 = upper / lower 256b
    function automatic logic [63:0] mk_c2_store(input int l2_word14, input int h, input int w,
                                                input bit prec, input bit handshake = 0);
        logic [63:0] c;
        c = '0;
        c[62:60]             = 3'b100;
        c[59:58]             = handshake ? 2'b11 : 2'b10;
        c[57]                = prec;                    // channel-field layout of the beat address
        c[SRC_W_256+38:40]   = l2_word14[SRC_W_256-2:0];
        c[39:30]             = 10'(h);
        c[29:20]             = 10'(w);
        return c;
    endfunction

endpackage
