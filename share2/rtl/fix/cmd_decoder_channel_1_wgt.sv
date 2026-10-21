// =============================================================================
//  FIXED COPY (Blackbox 환경 전용) - FINDING_handshake_mode.md (C)
//  원본 경로 : rtl/L2_260901/cmd_decoder_channel_1_wgt.sv  (원본은 수정하지 않음)
//  모듈 이름은 그대로 -> 파일 목록에서 원본 대신 이 파일을 넣는다.
//
//  바꾼 것 1곳:
//   (C) o_sram_control_mode : r_control_mode[0] -> 1'b0
//       handshake 명령이면 L2 내부 SRAM 쪽 FIFO 인터페이스까지 handshake 모드로 바뀌어,
//       SRAM 읽기 데이터가 다음 것으로 넘어가지 않고 첫 줄만 반복해서 나갔다
//       (1024줄 handshake LOAD -> L1 전부 weight 0번 줄). ch1_in decoder 는 이미 1'b0 로
//       고정돼 있다 (cmd_decoder_channel_1_in.sv 278행) -> 같게 맞춤. NoC 쪽 모드(o_noc_control_mode)는 그대로.
//  참고: ch1_in (B) 와 같은 IDLE_HS 코드 패턴이 있지만, handshake LOAD -> handshake STORE 를
//       간격 10~13 클럭 (재출발 루프의 모든 위상) 으로 돌려도 hang 이 재현되지 않아 고치지 않았다 (W4h).
// =============================================================================
`timescale 1ns / 1ps

module cmd_decoder_channel_1_wgt #(
    parameter  SOURCE_ADDR_BIT        = 18,  // source_addr bit number
    parameter  DESTINATION_ADDR_BIT   = 18,  // destination addr bit number(fixed)
    parameter  BANDWIDTH_CHANNEL_1    = 256
)(
    input  wire        i_clk,
    input  wire        i_rstn,

    // ========== Interface with command_decoder ==========
    input  wire [63:0] i_ch1_rw_cmd,       
    input  wire        i_ch1_rw_cmd_valid, 
    output wire        o_ch1_rw_cmd_ready,

    // ==========     load operation      ==========
    // ========== Interface with top_ctrl ==========
    output wire        o_load_busy,      
    // ========== Interface with L2_FIFO_interface (SRAM Read Path) ========== 
    output wire [SOURCE_ADDR_BIT-1:0]      o_sram_read_addr,
    output wire                            o_sram_read_valid, 
    output wire                            o_sram_read_data_ready,
    input  wire                            i_sram_read_ready,     
    input  wire                            i_sram_read_response,        
    input  wire [BANDWIDTH_CHANNEL_1-1:0]  i_sram_read_data,

    // ========== Interface with FIFO_interface (NOC Write Path) ========== 
    input  wire                              i_noc_write_ready,   
    output wire                              o_noc_write_valid,
    output wire [DESTINATION_ADDR_BIT-1:0]   o_noc_write_addr,
    output wire [BANDWIDTH_CHANNEL_1-1:0]    o_noc_write_data,
    input  wire                              i_noc_write_response,

    // ==========     store operation     ==========
    // ========== Interface with top_ctrl ==========
    output wire        o_store_busy,      
    // ========== Interface with FIFO_interface (NOC Read Path) ========== 
    output wire [DESTINATION_ADDR_BIT-1:0] o_noc_read_addr,
    output wire                            o_noc_read_valid, 
    output wire                            o_noc_read_data_ready,
    input  wire                            i_noc_read_ready,     
    input  wire                            i_noc_read_response,        
    input  wire [BANDWIDTH_CHANNEL_1-1:0]  i_noc_read_data,

    // ========== Interface with L2_FIFO_interface (SRAM Write Path) ========== 
    input  wire                              i_sram_write_ready,   
    output wire                              o_sram_write_valid,
    output wire [SOURCE_ADDR_BIT-1:0]        o_sram_write_addr,
    output wire [BANDWIDTH_CHANNEL_1-1:0]    o_sram_write_data,
    input  wire                              i_sram_write_response,

    output wire o_sram_control_mode,    
    output wire o_noc_control_mode
);

    // =================================================================
    // 1. FSM States and Command Decoding
    // =================================================================

    //===============================================================================================
    // FSM State Parameter
    localparam IDLE             = 3'd1;
    localparam CMD_DECODE       = 3'd2;
    localparam BURST_LOAD       = 3'd3;  // LOAD  : burst  handshake mode
    localparam HANDSHAKE_LOAD   = 3'd4;  // LOAD  : normal handshake mode
    localparam BURST_STORE      = 3'd5;  // STORE : burst  handshake mode
    localparam HANDSHAKE_STORE  = 3'd6;  // STORE : normal handshake mode
    localparam CMD_DONE         = 3'd7;  // command end state
    //===============================================================================================
    reg [2:0] current_state;
    reg [2:0] next_state;
    //===============================================================================================

    // normal handshake mode FSM
    //===============================================================================================
    // FSM State Parameter
    localparam IDLE_HS          = 3'd1;
    localparam DATA_FETCH_LOAD  = 3'd2;  // LOAD  : normal handshake mode
    localparam ADDR_GEN_LOAD    = 3'd3;  // LOAD  : normal handshake mode
    localparam ADDR_GEN_STORE   = 3'd4;  // STORE : normal handshake mode
    localparam DATA_FETCH_STORE = 3'd5;  // STORE : normal handshake mode
    localparam DATA_SEND_STORE  = 3'd6;  // STORE : normal handshake mode
    localparam CMD_DONE_HS      = 3'd7;  // command end state
    //===============================================================================================
    reg [2:0] current_state_handshake;
    reg [2:0] next_state_handshake;
    //===============================================================================================


    // cache first & last addr 
    reg [SOURCE_ADDR_BIT-1:0]       r_first_addr_18b; 
    reg [SOURCE_ADDR_BIT-1:0]       r_last_addr_18b;

    // common cmd register
    reg [1:0] r_control_mode;
    reg       r_ch1_rw_cmd_ready;

    reg    r_load_busy;
    assign o_load_busy = r_load_busy;

    assign o_ch1_rw_cmd_ready = r_ch1_rw_cmd_ready;
    assign o_sram_control_mode= 1'b0;   // FIX (C): SRAM side always on-fire, same as ch1_in
    assign o_noc_control_mode = r_control_mode[0];

    // channel 1 weight load cmd register (burst load & custom load)
    reg                       r_load_mode;
    reg [SOURCE_ADDR_BIT-1:0] r_source_start_addr;
    reg [7:0]                 r_multicast;
    // burst load
    reg [9:0]  r_source_read_addr;
    reg [9:0]  r_destination_write_addr;
    reg [9:0]  r_destination_start_addr;
    // custom load
    reg [2:0] r_destination_wgt_grp_sel;
    reg [1:0] r_destination_LCU_sel;
    reg [1:0] r_destination_LCC_sel;

    // burst load
    // sram read
    reg       r_sram_read_valid;

    //last flag
    reg                           r_noc_write_last_flag ;
    reg                           r_noc_read_last_flag  ;
    reg                           r_sram_write_last_flag;
    reg                           r_sram_read_last_flag ;

    reg                                r_sram_read_data_ready;
    reg                                r_noc_write_valid;
    reg [DESTINATION_ADDR_BIT-1:0]     r_noc_write_addr;
    reg [BANDWIDTH_CHANNEL_1-1:0]      r_noc_write_data;

    // custom load
    // sram read
    wire [9:0] w_custom_load_addr_1;
    wire [9:0] w_custom_load_addr_2;
    //assign     w_custom_load_addr_1 =    r_destination_wgt_grp_sel * r_destination_LCU_sel * r_destination_LCC_sel
    //                                    +r_destination_wgt_grp_sel * r_destination_LCU_sel
    //                                    +r_destination_wgt_grp_sel * r_destination_LCC_sel
    //                                    +r_destination_LCU_sel     * r_destination_LCC_sel 
    //                                    +r_destination_wgt_grp_sel + r_destination_LCU_sel + r_desitination_LCC_sel + 1;
    // According to GEMINI, this way is better efficient than before way.
    assign     w_custom_load_addr_1 =    (r_destination_wgt_grp_sel+1) * (r_destination_LCU_sel+1) * (r_destination_LCC_sel+1);
    assign     w_custom_load_addr_2 =    (w_custom_load_addr_1 << 3)-1;

    reg [2:0] r_jump_addr_LCC; //0~8
    reg [6:0] r_jump_addr_LCU; //0~32*2(7b)

    reg [2:0] r_cnt_LCC;
    reg [1:0] r_cnt_bit;
    reg [1:0] r_cnt_LCU;

    reg [2:0] r_target_LCC;
    reg [1:0] r_target_LCU;

    // sram read path output
    assign o_sram_read_addr       = r_source_start_addr;
    assign o_sram_read_valid      = r_sram_read_valid && (~r_sram_read_last_flag);
    assign o_sram_read_data_ready = r_sram_read_data_ready && i_noc_write_ready;
    // noc write path output
    assign o_noc_write_valid      = r_noc_write_valid;
    assign o_noc_write_addr       = r_noc_write_addr;
    assign o_noc_write_data       = r_noc_write_data;

    // burst store
    reg    r_store_busy;
    assign o_store_busy = r_store_busy;

    // channel 1 weight store cmd register

    reg [SOURCE_ADDR_BIT-1:0] r_destination_start_addr_store;      //18b
    // burst store
    reg [12:0] r_destination_write_addr_store;      // 13b (when cmd receive, no multicast addr ver ==> 13b)
    reg [12:0] r_source_read_addr_store;  // 13b
    reg [12:0] r_source_start_addr_store; // 13b

    // burst store
    // noc read
    reg       r_noc_read_valid;

    wire [7:0] w_multicast_store;
    assign w_multicast_store = 1'b1 << r_source_start_addr_store[12:10];

    assign o_noc_read_addr       = {w_multicast_store,r_source_start_addr_store[9:0]};
    assign o_noc_read_valid      = r_noc_read_valid && (~r_noc_read_last_flag);

    //sram write
    reg                           r_noc_read_data_ready;

    assign o_noc_read_data_ready = r_noc_read_data_ready && i_sram_write_ready;
    reg                           r_sram_write_valid;
    reg [SOURCE_ADDR_BIT-1:0]     r_sram_write_addr;
    reg [BANDWIDTH_CHANNEL_1-1:0] r_sram_write_data;

    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin
            r_first_addr_18b <= {SOURCE_ADDR_BIT{1'b0}};
            r_last_addr_18b  <= {SOURCE_ADDR_BIT{1'b1}};
        end
    end
    
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin
            r_control_mode     <= 2'b00;
            r_ch1_rw_cmd_ready <= 1'b0;
        end
        else begin
            if(current_state==IDLE)begin
                r_ch1_rw_cmd_ready <= 1'b1;
            end
            if((current_state==IDLE)&&(next_state==CMD_DECODE)) begin
                r_ch1_rw_cmd_ready <= 1'b0; 
                r_control_mode     <= i_ch1_rw_cmd[59:58];
            end
        end
    end

    assign o_sram_write_valid = r_sram_write_valid;
    assign o_sram_write_addr  = r_sram_write_addr;
    assign o_sram_write_data  = r_sram_write_data;

    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin
            r_load_busy <= 1'b0;
            r_load_mode              <=  1'b0;
            r_source_start_addr      <= {SOURCE_ADDR_BIT{1'b0}};
            r_multicast              <=  8'b0;
            // burst load
            r_source_read_addr       <= 10'b0;
            r_destination_write_addr <= 10'b0;
            r_destination_start_addr <= 10'b0;
            // custom load
            r_destination_wgt_grp_sel<= 3'b0;
            r_destination_LCC_sel    <= 2'b0;
            r_destination_LCU_sel    <= 2'b0;
            //
            r_sram_read_valid      <=  1'b0;
            //
            r_sram_read_data_ready <= 1'b0;
            //
            r_jump_addr_LCC     <= 3'b0;
            r_jump_addr_LCU     <= 7'b0;
            r_cnt_LCC           <= 3'b0;
            r_cnt_bit           <= 2'b0;
            r_cnt_LCU           <= 2'b0;
            r_target_LCC        <= 3'b0;
            r_target_LCU        <= 2'b0;
            //
            r_noc_write_valid   <= 1'b0;
            r_noc_write_addr    <= {SOURCE_ADDR_BIT{1'b0}};
            r_noc_write_data    <= {BANDWIDTH_CHANNEL_1{1'b0}};
            //
            r_noc_write_last_flag <= 1'b0;
            r_sram_read_last_flag <= 1'b0;
        end
        else begin

            if((current_state==IDLE)&&(next_state==CMD_DECODE)) begin
                if (i_ch1_rw_cmd[59]==1'b0) begin
                    r_load_mode              <= i_ch1_rw_cmd[57];
                    r_source_start_addr      <= i_ch1_rw_cmd[SOURCE_ADDR_BIT+38:39];
                    r_multicast              <= i_ch1_rw_cmd[14:7];
                    //
                    r_noc_write_last_flag    <= 1'b0;
                    r_sram_read_last_flag    <= 1'b0;
                    // burst load
                    r_source_read_addr       <= i_ch1_rw_cmd[38:29];
                    r_destination_write_addr <= i_ch1_rw_cmd[38:29];
                    r_destination_start_addr <= i_ch1_rw_cmd[28:19];
                    // custom load
                    r_destination_wgt_grp_sel<= i_ch1_rw_cmd[38:36]; //3b
                    r_destination_LCU_sel    <= i_ch1_rw_cmd[35:34]; //2b
                    r_destination_LCC_sel    <= i_ch1_rw_cmd[33:32]; //2b
                    //
                    r_load_busy <= 1'b1;
                end
            end

            if(current_state==CMD_DECODE)begin
                if(r_load_mode==1) begin
                    r_source_read_addr       <= w_custom_load_addr_2;
                    r_destination_write_addr <= w_custom_load_addr_2;
                    r_destination_start_addr <= 10'b0;
                    r_jump_addr_LCC          <= (4-(r_destination_LCC_sel+1))<<1;
                    r_jump_addr_LCU          <= (3-(r_destination_LCU_sel+1))<<5;
                    r_cnt_LCC                <= 3'b0;
                    r_cnt_bit                <= 2'b0;
                    r_cnt_LCU                <= 2'b0;
                    r_target_LCC             <= (r_destination_LCC_sel+2'd1)<<1;
                    r_target_LCU             <=  r_destination_LCU_sel;
                end
            end


            if(current_state==BURST_LOAD)begin
                if(!r_load_mode)begin
                    ////
                    if(!r_sram_read_last_flag)begin
                        r_sram_read_valid <= 1'b1;
                        if(i_sram_read_ready && o_sram_read_valid)begin 
                            if (r_source_read_addr==0)begin
                                r_sram_read_last_flag <= 1'b1;
                            end
                            else begin
                                r_source_read_addr <= r_source_read_addr-1;
                            end
                            if(r_source_start_addr==r_last_addr_18b)begin
                                r_source_start_addr <= r_first_addr_18b;
                            end
                            else begin
                                r_source_start_addr <= r_source_start_addr+1;
                            end
                        end
                    end
                    else begin
                        r_sram_read_valid <= 1'b0;
                    end
                    ////
                    if(!r_noc_write_last_flag)begin 
                        r_sram_read_data_ready <= 1'b1;
                        if(i_sram_read_response && o_sram_read_data_ready) begin 
                            r_noc_write_valid <= 1'b1;
                            r_noc_write_addr  <= {r_multicast,r_destination_start_addr};
                            r_noc_write_data  <= i_sram_read_data;
                            if(i_noc_write_ready) begin //check point!! // if (i_noc_write_ready&&o_noc_write_valid)begin doesn't operate
                            // reason, o_noc_write_valid signal is reg signal so, it moves after rising edge of clock. so, combinational condition logic operates after edge clock.
                                if (r_destination_write_addr==0)begin
                                    r_noc_write_last_flag <= 1'b1;
                                end
                                else begin
                                    r_destination_write_addr <= r_destination_write_addr-1;
                                end
                                r_destination_start_addr <= r_destination_start_addr+1;
                            end
                        end
                    end
                    else if(i_noc_write_ready && o_noc_write_valid)begin
                        r_sram_read_data_ready <= 1'b0;
                        r_noc_write_valid      <= 1'b0;
                    end
                end

                else begin
                    /////
                    if(!r_sram_read_last_flag)begin
                        r_sram_read_valid <= 1'b1;
                        if(i_sram_read_ready && o_sram_read_valid)begin 
                            if (r_source_read_addr==0)begin
                                r_sram_read_last_flag <= 1'b1;
                            end
                            else begin
                                r_source_read_addr <= r_source_read_addr-1;
                            end
                            if(r_source_start_addr==r_last_addr_18b)begin
                                r_source_start_addr <= r_first_addr_18b;
                            end
                            else begin
                                r_source_start_addr <= r_source_start_addr+1;
                            end
                        end
                    end
                    else begin
                        r_sram_read_valid <= 1'b0;
                    end
                    /////
                    if(!r_noc_write_last_flag)begin
                        r_sram_read_data_ready <= 1'b1;
                        if(i_sram_read_response && o_sram_read_data_ready) begin 
                            r_noc_write_valid <= 1'b1;
                            r_noc_write_addr  <= {r_multicast,r_destination_start_addr};
                            r_noc_write_data  <= i_sram_read_data;
                            if(i_noc_write_ready) begin 
                                if(r_destination_write_addr==0)begin
                                    r_noc_write_last_flag <= 1'b1;
                                end
                                else begin
                                    r_destination_write_addr <= r_destination_write_addr-1;
                                end
                                if(r_cnt_LCC==r_target_LCC-3'd1)begin
                                    r_cnt_LCC <= 3'b0;
                                    if(r_cnt_bit==3)begin
                                        r_cnt_bit <= 2'b0;
                                        if (r_cnt_LCU==r_target_LCU)begin
                                            r_cnt_LCU <= 2'b0;
                                            r_destination_start_addr <= r_destination_start_addr+r_jump_addr_LCC+r_jump_addr_LCU+1;
                                        end
                                        else begin
                                            r_cnt_LCU <= r_cnt_LCU+1;
                                            r_destination_start_addr <= r_destination_start_addr+r_jump_addr_LCC+1;
                                        end
                                    end
                                    else begin
                                        r_cnt_bit <= r_cnt_bit+1;
                                        r_destination_start_addr <= r_destination_start_addr+r_jump_addr_LCC+1;
                                    end
                                end
                                else begin
                                    r_cnt_LCC <= r_cnt_LCC+1;
                                    r_destination_start_addr <= r_destination_start_addr+1;
                                end
                            end
                        end
                    end
                    else if(i_noc_write_ready && o_noc_write_valid)begin
                        r_sram_read_data_ready <= 1'b0;
                        r_noc_write_valid      <= 1'b0;
                    end
                end
            end
            //////////////////////////////////////////////////////////
            if(current_state==HANDSHAKE_LOAD)begin
                //// sram read
                if(!r_sram_read_last_flag)begin
                    r_sram_read_valid <= 1'b1;
                    if(i_sram_read_ready && o_sram_read_valid)begin 
                        if (r_source_read_addr==0)begin
                            r_sram_read_last_flag <= 1'b1;
                        end
                        else begin
                            r_source_read_addr <= r_source_read_addr-1;
                        end
                        if(r_source_start_addr==r_last_addr_18b)begin
                            r_source_start_addr <= r_first_addr_18b;
                        end
                        else begin
                            r_source_start_addr <= r_source_start_addr+1;
                        end
                    end
                end
                else begin
                    r_sram_read_valid <= 1'b0;
                end
                //// noc write
                case(current_state_handshake)
                    DATA_FETCH_LOAD:begin
                        if(i_sram_read_response&&o_sram_read_data_ready)begin
                            r_sram_read_data_ready <= 1'b0;
                            r_noc_write_valid <= 1'b1;
                            r_noc_write_addr  <= {r_multicast,r_destination_start_addr};
                            r_noc_write_data  <= i_sram_read_data;
                        end
                        else begin
                            r_sram_read_data_ready <= 1'b1;
                        end
                    end
                    ADDR_GEN_LOAD:begin //generation for next noc address
                        if(!r_load_mode)begin
                            if(i_noc_write_response) begin 
                                if (r_destination_write_addr==0)begin
                                    r_noc_write_last_flag <= 1'b1;
                                end
                                else begin
                                    r_destination_write_addr <= r_destination_write_addr-1;
                                end
                                r_destination_start_addr <= r_destination_start_addr+1;
                                r_noc_write_valid        <= 1'b0;
                            end
                        end
                        else begin
                            if(i_noc_write_response) begin 
                                r_noc_write_valid <= 1'b0;
                                if(r_destination_write_addr==0)begin
                                    r_noc_write_last_flag <= 1'b1;
                                end
                                else begin
                                    r_destination_write_addr <= r_destination_write_addr-1;
                                end
                                if(r_cnt_LCC==r_target_LCC-3'd1)begin
                                    r_cnt_LCC <= 3'b0;
                                    if(r_cnt_bit==3)begin
                                        r_cnt_bit <= 2'b0;
                                        if (r_cnt_LCU==r_target_LCU)begin
                                            r_cnt_LCU <= 2'b0;
                                            r_destination_start_addr <= r_destination_start_addr+r_jump_addr_LCC+r_jump_addr_LCU+1;
                                        end
                                        else begin
                                            r_cnt_LCU <= r_cnt_LCU+1;
                                            r_destination_start_addr <= r_destination_start_addr+r_jump_addr_LCC+1;
                                        end
                                    end
                                    else begin
                                        r_cnt_bit <= r_cnt_bit+1;
                                        r_destination_start_addr <= r_destination_start_addr+r_jump_addr_LCC+1;
                                    end
                                end
                                else begin
                                    r_cnt_LCC <= r_cnt_LCC+1;
                                    r_destination_start_addr <= r_destination_start_addr+1;
                                end
                            end
                        end
                    end
                endcase
            end
            if (current_state==CMD_DONE) begin
                r_load_busy <= 1'b0;
            end
        end
    end

//store combine
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin
            //
            r_store_busy                        <= 1'b0;
            r_destination_start_addr_store      <= {SOURCE_ADDR_BIT{1'b0}};
            // burst store
            r_destination_write_addr_store      <= 13'b0;
            r_source_read_addr_store  <= 13'b0;
            r_source_start_addr_store <= 13'b0;
            //
            r_noc_read_valid      <=  1'b0;
            //
            r_noc_read_data_ready <= 1'b0;
            //
            r_sram_write_last_flag    <= 1'b0;
            r_noc_read_last_flag      <= 1'b0;
            //
            r_sram_write_valid        <= 1'b0;
            r_sram_write_addr         <= {SOURCE_ADDR_BIT{1'b0}};
            r_sram_write_data         <= {BANDWIDTH_CHANNEL_1{1'b0}};
        end
        else begin
            if((current_state==IDLE)&&(next_state==CMD_DECODE)) begin
                if (i_ch1_rw_cmd[59]==1'b1) begin
                    //
                    r_sram_write_last_flag    <= 1'b0;
                    r_noc_read_last_flag      <= 1'b0;
                    r_store_busy              <= 1'b1;
                    //
                    r_destination_start_addr_store       <= i_ch1_rw_cmd[SOURCE_ADDR_BIT+39:40];
                    // burst store
                    r_destination_write_addr_store       <= i_ch1_rw_cmd[39:27];
                    r_source_read_addr_store             <= i_ch1_rw_cmd[39:27];
                    r_source_start_addr_store            <= i_ch1_rw_cmd[26:14];
                end
            end
            if(current_state==BURST_STORE)begin
                if (!r_noc_read_last_flag)begin
                    r_noc_read_valid <= 1'b1;
                    if(i_noc_read_ready && o_noc_read_valid)begin 
                        if (r_source_read_addr_store==0)begin
                            r_noc_read_last_flag <= 1'b1;
                        end
                        else begin
                            r_source_read_addr_store <= r_source_read_addr_store-1;
                        end
                        if(r_source_start_addr_store=={13{1'b1}})begin
                            r_source_start_addr_store <= {13{1'b0}};
                        end
                        else begin
                            r_source_start_addr_store <= r_source_start_addr_store+1;
                        end
                    end
                end
                else begin
                    r_noc_read_valid <= 1'b0;
                end
                if(!r_sram_write_last_flag)begin
                    r_noc_read_data_ready <= 1'b1; 
                    if(i_noc_read_response && o_noc_read_data_ready) begin 
                        r_sram_write_valid <= 1'b1;
                        r_sram_write_data  <= i_noc_read_data;
                        r_sram_write_addr  <= r_destination_start_addr_store;
                        if(i_sram_write_ready) begin 
                            if (r_destination_write_addr_store==0)begin
                                r_sram_write_last_flag <= 1'b1;
                            end
                            else begin
                                r_destination_write_addr_store <= r_destination_write_addr_store-1;
                            end
                            if(r_destination_start_addr_store==r_last_addr_18b)begin
                                r_destination_start_addr_store <= r_first_addr_18b;
                            end
                            else begin
                                r_destination_start_addr_store <= r_destination_start_addr_store+1;
                            end
                        end
                    end
                end
                else if (i_sram_write_ready && o_sram_write_valid)begin
                    r_noc_read_data_ready   <= 1'b0;
                    r_sram_write_valid      <= 1'b0;
                end
            end
            if (current_state==HANDSHAKE_STORE) begin
                case(current_state_handshake)
                    ADDR_GEN_STORE: begin
                        if(i_noc_read_response)begin
                            r_noc_read_valid  <= 1'b0;
                            if (r_source_read_addr_store==0)begin
                                r_noc_read_last_flag <= 1'b1;
                            end
                            else begin
                                r_source_read_addr_store <= r_source_read_addr_store-1;
                            end
                            if(r_source_start_addr_store=={14{1'b1}})begin 
                                r_source_start_addr_store <= {14{1'b0}};
                            end
                            else begin
                                r_source_start_addr_store <= r_source_start_addr_store+1;
                            end
                        end
                        else if(!r_noc_read_last_flag)begin
                            r_noc_read_valid  <= 1'b1;
                        end
                        else begin
                            r_noc_read_valid  <= 1'b0;
                        end
                    end
                    DATA_FETCH_STORE: begin
                        r_sram_write_valid<= 1'b1;
                        r_sram_write_data <= i_noc_read_data;
                        r_sram_write_addr <= r_destination_start_addr_store;
                    end
                    DATA_SEND_STORE: begin
                        if(i_sram_write_ready)begin
                            r_sram_write_valid<=1'b0;
                            if (r_destination_write_addr_store==0)begin
                                r_sram_write_last_flag <= 1'b1;
                            end
                            else begin
                                r_destination_write_addr_store <= r_destination_write_addr_store-1;
                            end
                            if(r_destination_start_addr_store==r_last_addr_18b)begin
                                r_destination_start_addr_store <= r_first_addr_18b;
                            end
                            else begin
                                r_destination_start_addr_store <= r_destination_start_addr_store+1;
                            end
                        end
                    end
                endcase
            end
            if (current_state==CMD_DONE) begin
                r_store_busy <= 1'b0;
            end
        end
    end
    //===============================================================================================
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            current_state_handshake <= IDLE_HS;
        end
        else begin
            current_state_handshake <= next_state_handshake;
        end
    end
    //===============================================================================================
    always @(*) begin
        next_state_handshake = current_state_handshake;
        case(current_state_handshake)
            IDLE_HS: begin
                if(r_control_mode==2'b01) begin
                    next_state_handshake = DATA_FETCH_LOAD;
                end
                if(r_control_mode==2'b11) begin
                    next_state_handshake = ADDR_GEN_STORE;
                end
            end
            DATA_FETCH_LOAD: begin
                if(r_noc_write_last_flag)begin
                    next_state_handshake = CMD_DONE_HS;
                end
                else if(i_sram_read_response&&o_sram_read_data_ready)begin
                    next_state_handshake = ADDR_GEN_LOAD;
                end
            end
            ADDR_GEN_LOAD: begin
                if(i_noc_write_response)begin
                    next_state_handshake = DATA_FETCH_LOAD;
                end
            end
            ADDR_GEN_STORE: begin
                if(r_sram_write_last_flag)begin
                    next_state_handshake = CMD_DONE_HS;
                end
                else if(i_noc_read_response)begin
                    next_state_handshake = DATA_FETCH_STORE;
                end
            end
            DATA_FETCH_STORE: begin
                next_state_handshake = DATA_SEND_STORE;
            end
            DATA_SEND_STORE: begin
                if(i_sram_write_ready)begin
                    next_state_handshake = ADDR_GEN_STORE;
                end
            end
            CMD_DONE_HS: begin
                next_state_handshake = IDLE;
            end
        endcase
    end
    //===============================================================================================

    //===============================================================================================
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            current_state <= IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end
    //===============================================================================================
    always @(*) begin
        next_state = current_state;

        case(current_state)
            IDLE: begin
                if(i_ch1_rw_cmd_valid && o_ch1_rw_cmd_ready) begin
                    next_state = CMD_DECODE;
                end
            end
            CMD_DECODE: begin
                if(r_control_mode==2'b00) begin
                    next_state = BURST_LOAD;
                end
                if(r_control_mode==2'b01) begin
                    next_state = HANDSHAKE_LOAD;
                end
                if(r_control_mode==2'b10) begin
                    next_state = BURST_STORE;
                end
                if(r_control_mode==2'b11) begin
                    next_state = HANDSHAKE_STORE;
                end
            end
            BURST_LOAD: begin
                if(r_noc_write_last_flag && i_noc_write_ready && o_noc_write_valid) begin
                    next_state = CMD_DONE;
                end
            end
            HANDSHAKE_LOAD: begin
                if(r_noc_write_last_flag) begin
                    next_state = CMD_DONE;
                end
            end
            BURST_STORE: begin
                if(r_sram_write_last_flag &&i_sram_write_ready && o_sram_write_valid) begin
                    next_state = CMD_DONE;
                end
            end
            HANDSHAKE_STORE: begin
                if(r_sram_write_last_flag) begin
                    next_state = CMD_DONE;
                end
            end
            CMD_DONE: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule
