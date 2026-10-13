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

endpackage
