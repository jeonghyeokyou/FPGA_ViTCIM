`timescale 1ns / 1ps

module SRAM_group_decoder #(
    parameter BLOCKS = 32,                                                              
    parameter BANDWIDTH_CHANNEL_0 = 64,                                                   
    parameter BANDWIDTH_CHANNEL_1_IN = 512,                                                  
    parameter BANDWIDTH_CHANNEL_2_IN = 256,   
    parameter BANDWIDTH_CHANNEL_1_WGT= 256,                                                  
    parameter BANDWIDTH_CHANNEL_2_WGT= 256,     
                                                
    parameter ADDRESS_ROW = 2048,  

    localparam ADDR_BIT_IN_BLOCK = $clog2(ADDRESS_ROW),                                   
    localparam ADDR_BIT_PER_BLOCK = $clog2(BLOCKS),                                       
    localparam ADDR_BIT_TOTAL = $clog2(ADDRESS_ROW*BLOCKS),                               

    localparam GROUP_CHANNEL_1_IN              = BANDWIDTH_CHANNEL_1_IN/BANDWIDTH_CHANNEL_0,                 
    localparam BLOCKS_CHANNEL_1_IN             = BLOCKS/GROUP_CHANNEL_1_IN,                                 
    localparam ADDR_BIT_PER_BLOCK_CHANNEL_1_IN = $clog2(BLOCKS_CHANNEL_1_IN),                    
    localparam ADDR_BIT_TOTAL_CHANNEL_1_IN     = $clog2(ADDRESS_ROW*BLOCKS_CHANNEL_1_IN),   

    localparam GROUP_CHANNEL_2_IN              = BANDWIDTH_CHANNEL_2_IN/BANDWIDTH_CHANNEL_0,                 
    localparam BLOCKS_CHANNEL_2_IN             = BLOCKS/GROUP_CHANNEL_2_IN,                                  
    localparam ADDR_BIT_PER_BLOCK_CHANNEL_2_IN = $clog2(BLOCKS_CHANNEL_2_IN),                   
    localparam ADDR_BIT_TOTAL_CHANNEL_2_IN     = $clog2(ADDRESS_ROW*BLOCKS_CHANNEL_2_IN),

    localparam GROUP_CHANNEL_1_WGT              = BANDWIDTH_CHANNEL_1_WGT/BANDWIDTH_CHANNEL_0,                 
    localparam BLOCKS_CHANNEL_1_WGT             = BLOCKS/GROUP_CHANNEL_1_WGT,                                 
    localparam ADDR_BIT_PER_BLOCK_CHANNEL_1_WGT = $clog2(BLOCKS_CHANNEL_1_WGT),                    
    localparam ADDR_BIT_TOTAL_CHANNEL_1_WGT     = $clog2(ADDRESS_ROW*BLOCKS_CHANNEL_1_WGT),   

    localparam GROUP_CHANNEL_2_WGT              = BANDWIDTH_CHANNEL_2_WGT/BANDWIDTH_CHANNEL_0,                 
    localparam BLOCKS_CHANNEL_2_WGT             = BLOCKS/GROUP_CHANNEL_2_WGT,                                  
    localparam ADDR_BIT_PER_BLOCK_CHANNEL_2_WGT = $clog2(BLOCKS_CHANNEL_2_WGT),                   
    localparam ADDR_BIT_TOTAL_CHANNEL_2_WGT     = $clog2(ADDRESS_ROW*BLOCKS_CHANNEL_2_WGT)              
)(
    input wire           i_clk,
    input wire           i_rstn,

    // ========== channel 0(w/ ddma, I/O interface), BW=64-bit =================================
    input   wire                           i_ceb_channel_0,           // active-low
    input   wire                           i_web_channel_0,           // active-low
    input   wire [ADDR_BIT_TOTAL-1:0]      i_addr_channel_0,    
    input   wire [BANDWIDTH_CHANNEL_0-1:0] i_din_channel_0,
    output  wire [BANDWIDTH_CHANNEL_0-1:0] o_qout_channel_0,

    // ========== channel 1 in(w/ CIM Cluster L1), BW=512-bit ========================================
    input   wire                                   i_ceb_channel_1_in,           // active-low
    input   wire                                   i_web_channel_1_in,           // active-low
    input   wire [ADDR_BIT_TOTAL_CHANNEL_1_IN-1:0] i_addr_channel_1_in,    
    input   wire [BANDWIDTH_CHANNEL_1_IN-1:0]      i_din_channel_1_in,
    output  wire [BANDWIDTH_CHANNEL_1_IN-1:0]      o_qout_channel_1_in,

    // ========== channel 2 in(w/ Vector engine, Accumulator, Pooling engine), BW=256-bit ==========
    input   wire                                   i_ceb_channel_2_in,           // active-low
    input   wire                                   i_web_channel_2_in,           // active-low
    input   wire [ADDR_BIT_TOTAL_CHANNEL_2_IN-1:0] i_addr_channel_2_in,    
    input   wire [BANDWIDTH_CHANNEL_2_IN-1:0]      i_din_channel_2_in,
    output  wire [BANDWIDTH_CHANNEL_2_IN-1:0]      o_qout_channel_2_in,

    // ========== channel 1 wgt(w/ CIM Cluster Array), BW=256-bit ========================================
    input   wire                                    i_ceb_channel_1_wgt,           // active-low
    input   wire                                    i_web_channel_1_wgt,           // active-low
    input   wire [ADDR_BIT_TOTAL_CHANNEL_1_WGT-1:0] i_addr_channel_1_wgt,    
    input   wire [BANDWIDTH_CHANNEL_1_WGT-1:0]      i_din_channel_1_wgt,
    output  wire [BANDWIDTH_CHANNEL_1_WGT-1:0]      o_qout_channel_1_wgt,

    // ========== channel 2 wgt(w/ Vector engine), BW=256-bit ==========
    input   wire                                    i_ceb_channel_2_wgt,           // active-low
    input   wire                                    i_web_channel_2_wgt,           // active-low
    input   wire [ADDR_BIT_TOTAL_CHANNEL_2_WGT-1:0] i_addr_channel_2_wgt,    
    input   wire [BANDWIDTH_CHANNEL_2_WGT-1:0]      i_din_channel_2_wgt,
    output  wire [BANDWIDTH_CHANNEL_2_WGT-1:0]      o_qout_channel_2_wgt
);

    reg [ADDR_BIT_PER_BLOCK-1:0]               r_addr_bit_per_blk_ch_0;
    reg [ADDR_BIT_PER_BLOCK_CHANNEL_1_IN-1:0]  r_addr_bit_per_blk_ch_1_in; 
    reg [ADDR_BIT_PER_BLOCK_CHANNEL_2_IN-1:0]  r_addr_bit_per_blk_ch_2_in;
    reg [ADDR_BIT_PER_BLOCK_CHANNEL_1_WGT-1:0] r_addr_bit_per_blk_ch_1_wgt; 
    reg [ADDR_BIT_PER_BLOCK_CHANNEL_2_WGT-1:0] r_addr_bit_per_blk_ch_2_wgt;

    wire [BLOCKS-1:0] ceb_ch_0;
    wire [BLOCKS-1:0] web_ch_0;
    wire [ADDR_BIT_IN_BLOCK-1:0]            addr_ch_0 [BLOCKS-1:0];
    wire [ADDR_BIT_IN_BLOCK-1:0]            addr_bit_in_blk_ch_0 = i_addr_channel_0[ADDR_BIT_IN_BLOCK-1:0];
    wire [ADDR_BIT_PER_BLOCK-1:0]           addr_bit_per_blk_ch_0 = i_addr_channel_0[ADDR_BIT_TOTAL-1:ADDR_BIT_IN_BLOCK];
    wire [BANDWIDTH_CHANNEL_0-1:0]          din_ch_0 [BLOCKS-1:0];

    wire [BLOCKS-1:0] ceb_ch_1_in;
    wire [BLOCKS-1:0] web_ch_1_in;
    wire [ADDR_BIT_IN_BLOCK-1:0]               addr_ch_1_in [BLOCKS-1:0];
    wire [ADDR_BIT_IN_BLOCK-1:0]               addr_bit_in_blk_ch_1_in = i_addr_channel_1_in[ADDR_BIT_IN_BLOCK-1:0];
    wire [ADDR_BIT_PER_BLOCK_CHANNEL_1_IN-1:0] addr_bit_per_blk_ch_1_in = i_addr_channel_1_in[ADDR_BIT_TOTAL_CHANNEL_1_IN-1:ADDR_BIT_IN_BLOCK];
    wire [BANDWIDTH_CHANNEL_0-1:0]             din_ch_1_in [BLOCKS-1:0];


    wire [BLOCKS-1:0] ceb_ch_2_in;
    wire [BLOCKS-1:0] web_ch_2_in;
    wire [ADDR_BIT_IN_BLOCK-1:0]               addr_ch_2_in [BLOCKS-1:0];
    wire [ADDR_BIT_IN_BLOCK-1:0]               addr_bit_in_blk_ch_2_in = i_addr_channel_2_in[ADDR_BIT_IN_BLOCK-1:0];
    wire [ADDR_BIT_PER_BLOCK_CHANNEL_2_IN-1:0] addr_bit_per_blk_ch_2_in = i_addr_channel_2_in[ADDR_BIT_TOTAL_CHANNEL_2_IN-1:ADDR_BIT_IN_BLOCK];
    wire [BANDWIDTH_CHANNEL_0-1:0]             din_ch_2_in [BLOCKS-1:0];

    wire [BLOCKS-1:0] ceb_ch_1_wgt;
    wire [BLOCKS-1:0] web_ch_1_wgt;
    wire [ADDR_BIT_IN_BLOCK-1:0]                addr_ch_1_wgt [BLOCKS-1:0];
    wire [ADDR_BIT_IN_BLOCK-1:0]                addr_bit_in_blk_ch_1_wgt = i_addr_channel_1_wgt[ADDR_BIT_IN_BLOCK-1:0];
    wire [ADDR_BIT_PER_BLOCK_CHANNEL_1_WGT-1:0] addr_bit_per_blk_ch_1_wgt = i_addr_channel_1_wgt[ADDR_BIT_TOTAL_CHANNEL_1_WGT-1:ADDR_BIT_IN_BLOCK];
    wire [BANDWIDTH_CHANNEL_0-1:0]              din_ch_1_wgt [BLOCKS-1:0];


    wire [BLOCKS-1:0] ceb_ch_2_wgt;
    wire [BLOCKS-1:0] web_ch_2_wgt;
    wire [ADDR_BIT_IN_BLOCK-1:0]                addr_ch_2_wgt [BLOCKS-1:0];
    wire [ADDR_BIT_IN_BLOCK-1:0]                addr_bit_in_blk_ch_2_wgt = i_addr_channel_2_wgt[ADDR_BIT_IN_BLOCK-1:0];
    wire [ADDR_BIT_PER_BLOCK_CHANNEL_2_WGT-1:0] addr_bit_per_blk_ch_2_wgt = i_addr_channel_2_wgt[ADDR_BIT_TOTAL_CHANNEL_2_WGT-1:ADDR_BIT_IN_BLOCK];
    wire [BANDWIDTH_CHANNEL_0-1:0]              din_ch_2_wgt [BLOCKS-1:0];

    wire [BLOCKS-1:0] ceb_merge;
    wire [BLOCKS-1:0] web_merge;
    wire [ADDR_BIT_IN_BLOCK-1:0] addr_merge [BLOCKS-1:0]; 
    wire [BANDWIDTH_CHANNEL_0-1:0] din_merge [BLOCKS-1:0]; 
    wire [BANDWIDTH_CHANNEL_0-1:0] qout_merge [BLOCKS-1:0]; 

    wire [BANDWIDTH_CHANNEL_0-1:0]     w_qout_channel_0;
    wire [BANDWIDTH_CHANNEL_1_IN-1:0]  w_qout_channel_1_in;
    wire [BANDWIDTH_CHANNEL_2_IN-1:0]  w_qout_channel_2_in;
    wire [BANDWIDTH_CHANNEL_1_WGT-1:0] w_qout_channel_1_wgt;
    wire [BANDWIDTH_CHANNEL_2_WGT-1:0] w_qout_channel_2_wgt;
    
    genvar g_0;
    generate
        for (g_0 = 0; g_0 < BLOCKS; g_0 = g_0 + 1) begin : GRP_CH_0
            wire sel_blk_ch_0 = (addr_bit_per_blk_ch_0 == g_0);
            
            assign ceb_ch_0[g_0] = i_ceb_channel_0 | ~sel_blk_ch_0;
            assign web_ch_0[g_0] = i_web_channel_0 | ~sel_blk_ch_0;
            assign addr_ch_0[g_0] = sel_blk_ch_0 ? addr_bit_in_blk_ch_0 : {ADDR_BIT_IN_BLOCK{1'b0}};
            assign din_ch_0[g_0] = sel_blk_ch_0 ? i_din_channel_0 : {BANDWIDTH_CHANNEL_0{1'b0}};
        end
    endgenerate

    genvar g_1_in, b_1_in;
    generate
        for (g_1_in =0; g_1_in < BLOCKS_CHANNEL_1_IN; g_1_in = g_1_in + 1) begin : GRP_CH_1_IN
            wire sel_blk_ch_1_in = (addr_bit_per_blk_ch_1_in == g_1_in);
            for(b_1_in=0; b_1_in < GROUP_CHANNEL_1_IN; b_1_in = b_1_in + 1) begin : BLK_CH_1_IN
                assign ceb_ch_1_in[g_1_in*GROUP_CHANNEL_1_IN+b_1_in] = i_ceb_channel_1_in | ~sel_blk_ch_1_in;
                assign web_ch_1_in[g_1_in*GROUP_CHANNEL_1_IN+b_1_in] = i_web_channel_1_in | ~sel_blk_ch_1_in;
                assign addr_ch_1_in[g_1_in*GROUP_CHANNEL_1_IN+b_1_in] = sel_blk_ch_1_in ? addr_bit_in_blk_ch_1_in : {ADDR_BIT_IN_BLOCK{1'b0}};
                assign din_ch_1_in[g_1_in*GROUP_CHANNEL_1_IN+b_1_in] = sel_blk_ch_1_in ? i_din_channel_1_in[(b_1_in+1)*BANDWIDTH_CHANNEL_0-1:b_1_in*BANDWIDTH_CHANNEL_0] : {BANDWIDTH_CHANNEL_0{1'b0}};
            end
        end
    endgenerate

    genvar g_2_in, b_2_in;
    generate
        for (g_2_in =0; g_2_in < BLOCKS_CHANNEL_2_IN; g_2_in = g_2_in + 1) begin : GRP_CH_2_IN
            wire sel_blk_ch_2_in = (addr_bit_per_blk_ch_2_in == g_2_in);
            for (b_2_in =0; b_2_in < GROUP_CHANNEL_2_IN; b_2_in = b_2_in + 1) begin : BLK_CH_2_IN
                assign ceb_ch_2_in[g_2_in*GROUP_CHANNEL_2_IN+b_2_in] = i_ceb_channel_2_in | ~sel_blk_ch_2_in;
                assign web_ch_2_in[g_2_in*GROUP_CHANNEL_2_IN+b_2_in] = i_web_channel_2_in | ~sel_blk_ch_2_in;
                assign addr_ch_2_in[g_2_in*GROUP_CHANNEL_2_IN+b_2_in] = sel_blk_ch_2_in ? addr_bit_in_blk_ch_2_in : {ADDR_BIT_IN_BLOCK{1'b0}};
                assign din_ch_2_in[g_2_in*GROUP_CHANNEL_2_IN+b_2_in] = sel_blk_ch_2_in ? i_din_channel_2_in[(b_2_in+1)*BANDWIDTH_CHANNEL_0-1:b_2_in*BANDWIDTH_CHANNEL_0] : {BANDWIDTH_CHANNEL_0{1'b0}};
            end
        end
    endgenerate

    genvar g_1_wgt, b_1_wgt;
    generate
        for (g_1_wgt =0; g_1_wgt < BLOCKS_CHANNEL_1_WGT; g_1_wgt = g_1_wgt + 1) begin : GRP_CH_1_WGT
            wire sel_blk_ch_1_wgt = (addr_bit_per_blk_ch_1_wgt == g_1_wgt);
            for(b_1_wgt=0; b_1_wgt < GROUP_CHANNEL_1_WGT; b_1_wgt = b_1_wgt + 1) begin : BLK_CH_1_WGT
                assign ceb_ch_1_wgt[g_1_wgt*GROUP_CHANNEL_1_WGT+b_1_wgt] = i_ceb_channel_1_wgt | ~sel_blk_ch_1_wgt;
                assign web_ch_1_wgt[g_1_wgt*GROUP_CHANNEL_1_WGT+b_1_wgt] = i_web_channel_1_wgt | ~sel_blk_ch_1_wgt;
                assign addr_ch_1_wgt[g_1_wgt*GROUP_CHANNEL_1_WGT+b_1_wgt] = sel_blk_ch_1_wgt ? addr_bit_in_blk_ch_1_wgt : {ADDR_BIT_IN_BLOCK{1'b0}};
                assign din_ch_1_wgt[g_1_wgt*GROUP_CHANNEL_1_WGT+b_1_wgt] = sel_blk_ch_1_wgt ? i_din_channel_1_wgt[(b_1_wgt+1)*BANDWIDTH_CHANNEL_0-1:b_1_wgt*BANDWIDTH_CHANNEL_0] : {BANDWIDTH_CHANNEL_0{1'b0}};
            end
        end
    endgenerate

    genvar g_2_wgt, b_2_wgt;
    generate
        for (g_2_wgt =0; g_2_wgt < BLOCKS_CHANNEL_2_WGT; g_2_wgt = g_2_wgt + 1) begin : GRP_CH_2_WGT
            wire sel_blk_ch_2_wgt = (addr_bit_per_blk_ch_2_wgt == g_2_wgt);
            for (b_2_wgt =0; b_2_wgt < GROUP_CHANNEL_2_WGT; b_2_wgt = b_2_wgt + 1) begin : BLK_CH_2_WGT
                assign ceb_ch_2_wgt[g_2_wgt*GROUP_CHANNEL_2_WGT+b_2_wgt] = i_ceb_channel_2_wgt | ~sel_blk_ch_2_wgt;
                assign web_ch_2_wgt[g_2_wgt*GROUP_CHANNEL_2_WGT+b_2_wgt] = i_web_channel_2_wgt | ~sel_blk_ch_2_wgt;
                assign addr_ch_2_wgt[g_2_wgt*GROUP_CHANNEL_2_WGT+b_2_wgt] = sel_blk_ch_2_wgt ? addr_bit_in_blk_ch_2_wgt : {ADDR_BIT_IN_BLOCK{1'b0}};
                assign din_ch_2_wgt[g_2_wgt*GROUP_CHANNEL_2_WGT+b_2_wgt] = sel_blk_ch_2_wgt ? i_din_channel_2_wgt[(b_2_wgt+1)*BANDWIDTH_CHANNEL_0-1:b_2_wgt*BANDWIDTH_CHANNEL_0] : {BANDWIDTH_CHANNEL_0{1'b0}};
            end
        end
    endgenerate


    genvar b_merge;
    generate
        for (b_merge = 0; b_merge < BLOCKS; b_merge = b_merge + 1) begin : BLK_MERGE
            assign ceb_merge[b_merge] = ceb_ch_0[b_merge] & ceb_ch_1_in[b_merge] & ceb_ch_2_in[b_merge] & ceb_ch_1_wgt[b_merge] & ceb_ch_2_wgt[b_merge];
            assign web_merge[b_merge] = web_ch_0[b_merge] & web_ch_1_in[b_merge] & web_ch_2_in[b_merge] & web_ch_1_wgt[b_merge] & web_ch_2_wgt[b_merge];

            assign addr_merge[b_merge] = (!ceb_ch_0[b_merge])    ? addr_ch_0    [b_merge] :
                                         (!ceb_ch_1_in[b_merge]) ? addr_ch_1_in [b_merge] :
                                         (!ceb_ch_2_in[b_merge]) ? addr_ch_2_in [b_merge] : 
                                         (!ceb_ch_1_wgt[b_merge])? addr_ch_1_wgt[b_merge] :
                                         (!ceb_ch_2_wgt[b_merge])? addr_ch_2_wgt[b_merge] : {ADDR_BIT_IN_BLOCK{1'b0}};

            assign  din_merge[b_merge] = (!ceb_ch_0[b_merge])    ? din_ch_0    [b_merge] :
                                         (!ceb_ch_1_in[b_merge]) ? din_ch_1_in [b_merge] :
                                         (!ceb_ch_2_in[b_merge]) ? din_ch_2_in [b_merge] :
                                         (!ceb_ch_1_wgt[b_merge])? din_ch_1_wgt[b_merge] :
                                         (!ceb_ch_2_wgt[b_merge])? din_ch_2_wgt[b_merge] : {BANDWIDTH_CHANNEL_0{1'b0}};
        end
    endgenerate

    SRAM_group #(
        .BLOCKS(BLOCKS),
        .BIT_WIDTH(BANDWIDTH_CHANNEL_0),
        .ADDRESS_ROW(ADDRESS_ROW)
    ) u_SRAM_group (
        .i_clk(i_clk),
        .i_rstn(i_rstn),
        .i_ceb(ceb_merge),
        .i_web(web_merge),
        .i_addr(addr_merge),
        .i_din(din_merge),
        .o_qout(qout_merge)
    );
    
    always @ (posedge i_clk or negedge i_rstn)begin
        if(!i_rstn)begin
            r_addr_bit_per_blk_ch_0     <= {ADDR_BIT_PER_BLOCK{1'b0}};
            r_addr_bit_per_blk_ch_1_in  <= {ADDR_BIT_PER_BLOCK_CHANNEL_1_IN{1'b0}};
            r_addr_bit_per_blk_ch_2_in  <= {ADDR_BIT_PER_BLOCK_CHANNEL_2_IN{1'b0}};
            r_addr_bit_per_blk_ch_1_wgt <= {ADDR_BIT_PER_BLOCK_CHANNEL_1_WGT{1'b0}};
            r_addr_bit_per_blk_ch_2_wgt <= {ADDR_BIT_PER_BLOCK_CHANNEL_2_WGT{1'b0}};
        end
        else begin
            r_addr_bit_per_blk_ch_0     <= addr_bit_per_blk_ch_0;
            r_addr_bit_per_blk_ch_1_in  <= addr_bit_per_blk_ch_1_in;
            r_addr_bit_per_blk_ch_2_in  <= addr_bit_per_blk_ch_2_in;
            r_addr_bit_per_blk_ch_1_wgt <= addr_bit_per_blk_ch_1_wgt;
            r_addr_bit_per_blk_ch_2_wgt <= addr_bit_per_blk_ch_2_wgt;
        end
    end

    assign w_qout_channel_0 = qout_merge[r_addr_bit_per_blk_ch_0];

    genvar g_1_in_out;
    generate
        for (g_1_in_out = 0; g_1_in_out < GROUP_CHANNEL_1_IN; g_1_in_out = g_1_in_out + 1) begin : GRP_OUT_CH_1_IN
            assign w_qout_channel_1_in[(g_1_in_out+1)*BANDWIDTH_CHANNEL_0-1:g_1_in_out*BANDWIDTH_CHANNEL_0] = qout_merge[r_addr_bit_per_blk_ch_1_in*GROUP_CHANNEL_1_IN+g_1_in_out];
        end
    endgenerate

    genvar g_2_in_out;
    generate
        for (g_2_in_out = 0; g_2_in_out < GROUP_CHANNEL_2_IN; g_2_in_out = g_2_in_out + 1) begin : GRP_OUT_CH_2_IN
            assign w_qout_channel_2_in[(g_2_in_out+1)*BANDWIDTH_CHANNEL_0-1:g_2_in_out*BANDWIDTH_CHANNEL_0] = qout_merge[r_addr_bit_per_blk_ch_2_in*GROUP_CHANNEL_2_IN+g_2_in_out];
        end
    endgenerate

    genvar g_1_wgt_out;
    generate
        for (g_1_wgt_out = 0; g_1_wgt_out < GROUP_CHANNEL_1_WGT; g_1_wgt_out = g_1_wgt_out + 1) begin : GRP_OUT_CH_1_WGT
            assign w_qout_channel_1_wgt[(g_1_wgt_out+1)*BANDWIDTH_CHANNEL_0-1:g_1_wgt_out*BANDWIDTH_CHANNEL_0] = qout_merge[r_addr_bit_per_blk_ch_1_wgt*GROUP_CHANNEL_1_WGT+g_1_wgt_out];
        end
    endgenerate

    genvar g_2_wgt_out;
    generate
        for (g_2_wgt_out = 0; g_2_wgt_out < GROUP_CHANNEL_2_WGT; g_2_wgt_out = g_2_wgt_out + 1) begin : GRP_OUT_CH_2_WGT
            assign w_qout_channel_2_wgt[(g_2_wgt_out+1)*BANDWIDTH_CHANNEL_0-1:g_2_wgt_out*BANDWIDTH_CHANNEL_0] = qout_merge[r_addr_bit_per_blk_ch_2_wgt*GROUP_CHANNEL_2_WGT+g_2_wgt_out];
        end
    endgenerate

    
    assign o_qout_channel_0 = w_qout_channel_0;
    assign o_qout_channel_1_in = w_qout_channel_1_in;
    assign o_qout_channel_2_in = w_qout_channel_2_in;
    assign o_qout_channel_1_wgt = w_qout_channel_1_wgt;
    assign o_qout_channel_2_wgt = w_qout_channel_2_wgt;


endmodule 