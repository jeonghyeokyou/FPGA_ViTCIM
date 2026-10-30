// =============================================================================
//  FIXED COPY (Blackbox 환경 전용) - FINDING_handshake_mode.md (E)
//  원본 경로 : rtl/L2_260901/cmd_decoder_channel_2_in.sv  (원본은 수정하지 않음)
//  모듈 이름은 그대로 -> 파일 목록에서 원본 대신 이 파일을 넣는다.
//
//  ch2_in handshake STORE (ctrl_mode 11) 를 동작하게 고친 3곳:
//   (E1) o_sram_control_mode : r_control_mode[0] -> 1'b0
//        handshake 명령이면 L2 내부 SRAM 쪽 FIFO 인터페이스까지 handshake 모드가 되어 쓰기 ready 가
//        오지 않음 -> 내부 FIFO 가 차서 DATA_SEND_STORE 에서 정지. ch1_in 처럼 SRAM 쪽은 on-fire 고정.
//   (E2) 메인 FSM HANDSHAKE_STORE 에 빠져나갈 조건이 없었음 (빈 블록) -> BURST_STORE 와 같이
//        r_sram_write_done 이면 CMD_DONE.
//   (E3) store 주소 오프셋(w + h*W + ch*H*W)을 BURST_STORE 에서만 계산 -> handshake 에서는 모든 beat 가
//        시작 주소 하나에 덮어써짐. HANDSHAKE_STORE 에서도 계산하도록.
//   (E4) 200 MHz 타이밍 (기능 동일, 지연 변화 없음) - store 주소 계산 경로 단축
//        - h / w / ch / col / last 필드의 i_noc_read_valid 게이팅 mux 제거: 이 값들은 valid 일 때만
//          r_fifo_noc_read_addr / r_noc_read_done 에 들어가므로 게이팅은 불필요. 출발점이 입력 FIFO 의
//          empty 판정 (wr_ptr 비교) 에서 FIFO 데이터로 바뀐다.
//        - store 상태 게이팅 (w_store_state) 도 같은 이유로 제거 (store 상태에서만 레지스터에 들어감).
//        - wrap 쪽 상수 (first - 1 - offset) 를 명령 받을 때 r_wrap_k 로 미리 계산 -> 덧셈 1단 감소.
//          모두 17b mod 산술이라 결과 동일.
//  burst STORE / LOAD 경로의 동작은 바꾸지 않음.
//
//  [ch2lin] (F1) ch2_in 주소를 ch1 (256b) 과 같은 15b 선형 줄 번호 c = {group, quad, row} 로 맞춤
//   - 원래 : col(= c[10]) 을 고정하고 나머지 14b 만 +1  -> ch1 256b 기준으로 quad 하나씩 건너뜀
//   - LOAD  : 명령 [53:39] 15b 를 그대로 카운터로 사용, 0x7FFF -> 0 wrap
//   - STORE : 시작 주소 명령 [54:40] 15b (1b 확장, [54] 는 원래 미사용)
//             주소 = 시작 + w + h*W + cg*H*W ,  cg = {jp, col} (= beat 번호, 256b 채널 묶음)
//             nb = 1 이면 시작 + w + h*W : ch1 순서 그대로 이어서 씀
//   - wrap 상수 (offset / wrap_k) 를 15b (r_first_addr_18b / r_last_addr_18b) 기준으로
//  참고: ch1_in (B) 와 같은 IDLE_HS 코드 패턴이 있다. handshake STORE 연속 (O6) 에서는 문제가 없었고,
//       handshake LOAD (L2 -> Accumulator) 는 이 환경에 받는 쪽이 없어 확인하지 못해 고치지 않았다.
// =============================================================================
`timescale 1ns / 1ps

module cmd_decoder_channel_2_in #( 
    parameter  SOURCE_ADDR_BIT        = 18,
    parameter  DESTINATION_ADDR_BIT   = 15,
    parameter  BANDWIDTH_CHANNEL_2    = 256,
    parameter  ADDR_BIT_IN_BLOCK      = 11 
)(
    input  wire        i_clk,
    input  wire        i_rstn,

    // ========== Interface with command_decoder ==========
    input  wire [63:0] i_ch2_rw_cmd,       
    input  wire        i_ch2_rw_cmd_valid, 
    output wire        o_ch2_rw_cmd_ready,      

    // ========== Interface with top_ctrl ==========
    output wire        o_load_busy,         
    output wire        o_store_busy,        

    // ========== Interface with VE_interface (SRAM Read Path) ========== 
    output wire [SOURCE_ADDR_BIT-1:0]                  o_sram_read_addr,
    output wire                                        o_sram_read_valid, 
    output wire                                        o_sram_read_data_ready,
    input  wire                                        i_sram_read_ready,    
    input  wire                                        i_sram_read_response, 
    input  wire [BANDWIDTH_CHANNEL_2-1:0]              i_sram_read_data,

    // ========== Interface with VE_interface (SRAM Write Path) ========== 
    output wire [SOURCE_ADDR_BIT-1:0]                  o_sram_write_addr,
    output wire                                        o_sram_write_valid, 
    output wire [BANDWIDTH_CHANNEL_2-1:0]              o_sram_write_data,
    input  wire                                        i_sram_write_ready,   // o_FIFO_write_ready (L2_FIFO_interface)
    input  wire                                        i_sram_write_response,// o_write_ready      (L2_FIFO_interface)
    
    output wire o_sram_control_mode,

    // ========== Interface with FIFO_interface (NOC Write Path) ========== 
    input  wire                                        i_noc_write_ready,   // o_FIFO_write_ready_M (FIFO_interface)
    output wire                                        o_noc_write_valid,
    output wire [DESTINATION_ADDR_BIT-1:0]             o_noc_write_addr,
    output wire [BANDWIDTH_CHANNEL_2-1:0]              o_noc_write_data,
    input  wire                                        i_noc_write_response,

     // ========== Interface with FIFO_interface (NOC Read Path) ========== (cmd master but, works like slave)
    output wire                                        o_noc_read_ready,    
    input  wire                                        i_noc_read_valid,
    input  wire [31:0]                                 i_noc_read_addr,
    input  wire [BANDWIDTH_CHANNEL_2-1:0]              i_noc_read_data,   
    output wire                                        o_noc_read_response,

    output wire                                        o_noc_control_mode
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
    localparam DATA_FETCH_STORE = 3'd4;  // STORE : normal handshake mode
    localparam DATA_SEND_STORE  = 3'd5;  // STORE : normal handshake mode
    localparam CMD_DONE_HS      = 3'd6;  // command end state
    //===============================================================================================
    reg [2:0] current_state_handshake;
    reg [2:0] next_state_handshake;
    //===============================================================================================

    // sram read path register
    reg [SOURCE_ADDR_BIT-1:0]         r_sram_read_addr;
    reg                               r_sram_read_valid;
    reg                               r_sram_read_data_ready;
    reg                               r_sram_read_last_flag;
    // noc write path register
    reg [DESTINATION_ADDR_BIT-1:0]    r_noc_write_addr;
    reg [BANDWIDTH_CHANNEL_2-1:0]     r_noc_write_data;
    reg                               r_noc_write_valid;
    reg                               r_noc_write_last_flag;
    // load operation command register
    reg [1:0]                         r_control_mode; 
    reg                               r_prec_mode;
    reg [SOURCE_ADDR_BIT-1:0]         r_source_start_addr_18b;
    reg [SOURCE_ADDR_BIT-2:0]         r_source_start_addr_17b;
    reg                               r_source_in_ch;
    reg [DESTINATION_ADDR_BIT-2:0]    r_source_read_addr;
    reg                               r_destination_PE_Accum;
    reg [DESTINATION_ADDR_BIT-4:0]    r_destination_start_addr_load_12b;
    reg [1:0]                         r_destination_offset_addr;
    reg [DESTINATION_ADDR_BIT-2:0]    r_destination_start_addr_load_14b;
    // load : additional register
    reg [DESTINATION_ADDR_BIT-2:0]    r_destination_write_addr;

    // noc read path register
    reg                               r_noc_read_ready;
    // sram write path register
    reg [SOURCE_ADDR_BIT-1:0]         r_sram_write_addr;
    reg [BANDWIDTH_CHANNEL_2-1:0]     r_sram_write_data;
    reg                               r_sram_write_valid;
    //store operation command register
    reg [SOURCE_ADDR_BIT-1:0]         r_destination_start_addr_store;   // [ch2lin] 15b
    reg [9:0]                         r_data_height;
    reg [9:0]                         r_data_width;

    // store operation command additional register & wire
    reg [19:0]                        r_data_channel;
    reg [SOURCE_ADDR_BIT-1:0]         r_destination_offset_addr_store;  // [ch2lin] 15b
    reg [SOURCE_ADDR_BIT-1:0]         r_wrap_k;       // FIX (E4) / [ch2lin] 15b : r_first_addr_18b - 1 - r_destination_offset_addr_store
    reg                               r_noc_read_done;
    reg                               r_sram_write_done;
    wire                              w_last;         //w_noc_read_addr_last
    wire[4:0]                         w_channel_8b;   //w_noc_read_addr_channel_8b  (5b)
    wire[6:0]                         w_channel_32b;  //w_noc_read_addr_channel_32b (7b)
    wire[9:0]                         w_height;       //w_noc_read_addr_height
    wire[9:0]                         w_width;        //w_noc_read_addr_width
    wire[SOURCE_ADDR_BIT-1:0]         w_fifo_sram_write_addr_17b_1;     // [ch2lin] 15b
    wire[SOURCE_ADDR_BIT-1:0]         w_fifo_sram_write_addr_17b_2;     // [ch2lin] 15b
    wire                              w_fifo_sram_write_addr_col;     

    // cache first & last addr
    reg [SOURCE_ADDR_BIT-1:0]         r_first_addr_18b; 
    reg [SOURCE_ADDR_BIT-1:0]         r_last_addr_18b;
    reg [SOURCE_ADDR_BIT-2:0]         r_first_addr_17b; 
    reg [SOURCE_ADDR_BIT-2:0]         r_last_addr_17b;
    // top ctrl interface
    reg                               r_ch2_rw_cmd_ready;
    reg                               r_load_busy;
    reg                               r_store_busy;

    // fifo noc read fifo addr
    wire                       w_fifo_noc_read_addr_ready;
    wire                       w_fifo_noc_read_valid;
    reg                        r_fifo_noc_read_valid; 
    reg  [SOURCE_ADDR_BIT:0]   r_fifo_noc_read_addr;   //19b
    wire                       w_fifo_sram_write_ready;
    reg                        r_fifo_sram_write_ready;
    wire                       w_fifo_sram_write_addr_valid;
    wire [SOURCE_ADDR_BIT:0]   w_fifo_sram_write_addr; //19b

    // fifo noc read fifo data
    wire                           w_fifo_noc_read_data_ready;
    reg  [BANDWIDTH_CHANNEL_2-1:0] r_fifo_noc_read_data;
    wire                           w_fifo_sram_write_data_valid;
    wire [BANDWIDTH_CHANNEL_2-1:0] w_fifo_sram_write_data;
    wire                           w_fifo_noc_read_ready;
    reg                            r_noc_read_response;
    assign o_noc_read_response  =  r_noc_read_response;

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
                    next_state_handshake = DATA_FETCH_STORE;
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
            DATA_FETCH_STORE: begin
                if(r_sram_write_done)begin
                    next_state_handshake = CMD_DONE_HS;
                end
                else if(i_noc_read_valid)begin
                    next_state_handshake = DATA_SEND_STORE;
                end
            end
            DATA_SEND_STORE: begin
                if(w_fifo_noc_read_ready)begin
                    next_state_handshake = DATA_FETCH_STORE;
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
                if(i_ch2_rw_cmd_valid && o_ch2_rw_cmd_ready) begin
                    next_state = CMD_DECODE;
                end
            end
            CMD_DECODE: begin //else assign 문법 사용
                if(r_control_mode==2'b00)begin
                    next_state = BURST_LOAD;
                end
                else if(r_control_mode==2'b01)begin
                    next_state = HANDSHAKE_LOAD;
                end
                else if(r_control_mode==2'b10)begin
                    next_state = BURST_STORE;
                end
                else if(r_control_mode==2'b11)begin
                    next_state = HANDSHAKE_STORE;
                end
                else begin
                    next_state = IDLE;
                end
            end
            // LOAD : burst handshake mode
            BURST_LOAD: begin
                if(r_noc_write_last_flag && i_noc_write_ready && o_noc_write_valid) begin
                    next_state = CMD_DONE;
                end
            end
            // LOAD : normal handshake mode
            HANDSHAKE_LOAD: begin
                if(r_noc_write_last_flag) begin
                    next_state = CMD_DONE;
                end
            end
            // STORE : burst handshake mode
            BURST_STORE: begin
                if(r_sram_write_done==1'b1) begin
                    next_state = CMD_DONE;
                end
            end
            // STORE : normal handshake mode
            HANDSHAKE_STORE: begin
                if(r_sram_write_done==1'b1) begin   // FIX (E2): exit like BURST_STORE
                    next_state = CMD_DONE;
                end
            end
            // cmd end state
            CMD_DONE: begin
                next_state = IDLE;
            end
        endcase
    end
    //===============================================================================================

    // sram read path output
    assign o_sram_read_addr       = r_source_start_addr_18b;   // [ch2lin] linear 15b (was {hi, in_ch, lo})
    assign o_sram_read_valid      = r_sram_read_valid && (~r_sram_read_last_flag);
    assign o_sram_read_data_ready = r_sram_read_data_ready && i_noc_write_ready;
    // noc write path output
    assign o_noc_write_addr       = r_noc_write_addr;
    assign o_noc_write_data       = r_noc_write_data;
    assign o_noc_write_valid      = r_noc_write_valid;
    // top ctrl interface
    assign o_ch2_rw_cmd_ready     = r_ch2_rw_cmd_ready;
    assign o_load_busy            = r_load_busy;
    assign o_store_busy           = r_store_busy;
    assign o_sram_control_mode    = 1'b0;   // FIX (E1): SRAM side always on-fire, same as ch1_in
    assign o_noc_control_mode     = r_control_mode[0];
    // noc read path output
    assign o_noc_read_ready       = r_noc_read_ready && w_fifo_noc_read_ready && ~r_noc_read_done;
    // sram write path output
    assign o_sram_write_addr      = w_fifo_sram_write_addr[SOURCE_ADDR_BIT-1:0];
    assign o_sram_write_data      = w_fifo_sram_write_data;
    assign o_sram_write_valid     = w_fifo_sram_write_addr_valid && w_fifo_sram_write_data_valid;

    // store operation command additional register & wire
    // FIX (E4): no i_noc_read_valid / store-state gating - every use below is already qualified by
    //           i_noc_read_valid in BURST_STORE / HANDSHAKE_STORE (this also covers E3: both store states).
    assign w_last       = i_noc_read_addr[31];                                   //w_noc_read_addr_last
    assign w_channel_8b = i_noc_read_addr[30:26];                                //w_noc_read_addr_channel_8b
    assign w_channel_32b= i_noc_read_addr[30:24];                                //w_noc_read_addr_channel_32b
    assign w_height     = i_noc_read_addr[19:10];                                //w_noc_read_addr_height
    assign w_width      = i_noc_read_addr[9:0];                                  //w_noc_read_addr_width
    assign w_fifo_sram_write_addr_col        = (r_prec_mode==1'b0) ? i_noc_read_addr[25] : i_noc_read_addr[23];
    wire [6:0] w_channel = (r_prec_mode==1'b0) ? {2'b0, w_channel_8b} : w_channel_32b;
    wire [7:0] w_cg      = {w_channel, w_fifo_sram_write_addr_col};   // [ch2lin] 256b channel group = beat no.
    assign w_fifo_sram_write_addr_17b_1 = w_width+w_height*r_data_width+w_cg*r_data_channel;
    assign w_fifo_sram_write_addr_17b_2 = (w_fifo_sram_write_addr_17b_1>r_destination_offset_addr_store) ? w_fifo_sram_write_addr_17b_1+r_wrap_k :
                                                                                                        w_fifo_sram_write_addr_17b_1+r_destination_start_addr_store;
    
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            // sram read path register
            r_sram_read_addr         <= {SOURCE_ADDR_BIT{1'b0}};
            r_sram_read_valid        <= 1'b0;
            r_sram_read_data_ready   <= 1'b0;
            // noc write path register
            r_noc_write_valid        <= 1'b0;
            r_noc_write_addr         <= {DESTINATION_ADDR_BIT{1'b0}};
            r_noc_write_data         <= {BANDWIDTH_CHANNEL_2{1'b0}};
            // load operation command register
            r_control_mode                    <= 2'b0;
            r_prec_mode                       <= 1'b0;
            r_source_start_addr_18b           <= {SOURCE_ADDR_BIT{1'b0}};
            r_source_start_addr_17b           <= {SOURCE_ADDR_BIT-1{1'b0}};
            r_source_in_ch                    <= 1'b0;
            r_source_read_addr                <= {DESTINATION_ADDR_BIT-1{1'b0}};
            r_destination_PE_Accum            <= 1'b0;
            r_destination_start_addr_load_12b <= {DESTINATION_ADDR_BIT-3{1'b0}};
            r_destination_offset_addr         <= 2'b0;
            r_destination_start_addr_load_14b <= {DESTINATION_ADDR_BIT-1{1'b0}};
            // load operation : additional register
            r_destination_write_addr          <= {DESTINATION_ADDR_BIT-1{1'b0}};
            // noc read path register
            r_noc_read_ready                  <= 1'b0;
            // sram write path register
            r_sram_write_addr                 <= {SOURCE_ADDR_BIT{1'b0}};
            r_sram_write_data                 <= {BANDWIDTH_CHANNEL_2{1'b0}};
            r_sram_write_valid                <= 1'b0;
            // store operation command register
            r_destination_start_addr_store    <= {SOURCE_ADDR_BIT{1'b0}};
            r_data_height                     <= 10'b0;
            r_data_width                      <= 10'b0;
            // store operation command additional register
            r_data_channel                    <= 20'b0;
            r_destination_offset_addr_store   <= {SOURCE_ADDR_BIT{1'b0}};
            r_wrap_k                          <= {SOURCE_ADDR_BIT{1'b0}};
            r_noc_read_done                   <= 1'b0;
            r_sram_write_done                 <= 1'b0;
            // cache first & last addr
            r_first_addr_18b                  <= {SOURCE_ADDR_BIT{1'b0}}; // no need maybe
            r_last_addr_18b                   <= {SOURCE_ADDR_BIT{1'b1}}; // no need maybe
            r_first_addr_17b                  <= {SOURCE_ADDR_BIT-1{1'b0}}; 
            r_last_addr_17b                   <= {SOURCE_ADDR_BIT-1{1'b1}}; 
            // top ctrl interface
            r_ch2_rw_cmd_ready                <= 1'b0;
            r_load_busy                       <= 1'b0;
            r_store_busy                      <= 1'b0;
            // store command : fifo register
            r_fifo_noc_read_valid             <= 1'b0;
            r_fifo_noc_read_addr              <= {SOURCE_ADDR_BIT+1{1'b0}};
            r_fifo_sram_write_ready           <= 1'b0;
            r_fifo_noc_read_data              <= {BANDWIDTH_CHANNEL_2{1'b0}};
            //
            r_noc_write_last_flag             <= 1'b0;
            r_sram_read_last_flag             <= 1'b0;   
            //
            r_noc_read_response               <= 1'b0;

        end
        else begin
            if(current_state==IDLE)begin
                r_ch2_rw_cmd_ready  <= 1'b1;
            end
            if(current_state==IDLE && next_state==CMD_DECODE) begin
                r_ch2_rw_cmd_ready  <= 1'b0;
                if(i_ch2_rw_cmd[59]==1'b0) begin
                    r_control_mode                    <= i_ch2_rw_cmd[59:58];  //2b 
                    r_prec_mode                       <= i_ch2_rw_cmd[57];     //1b 
                    r_source_start_addr_18b           <= i_ch2_rw_cmd[SOURCE_ADDR_BIT+38:39];  //18b [56:39]
                    r_source_start_addr_17b           <={i_ch2_rw_cmd[SOURCE_ADDR_BIT+38:ADDR_BIT_IN_BLOCK+40],i_ch2_rw_cmd[ADDR_BIT_IN_BLOCK+38:39]};//17b {[56:51],[49:39]}
                    r_source_in_ch                    <= i_ch2_rw_cmd[ADDR_BIT_IN_BLOCK+39]; //1b [50]
                    r_source_read_addr                <= i_ch2_rw_cmd[38:25]; //14b
                    r_destination_write_addr          <= i_ch2_rw_cmd[38:25]; //14b
                    r_destination_PE_Accum            <= i_ch2_rw_cmd[24];    //1b
                    r_destination_offset_addr         <= i_ch2_rw_cmd[11:10]; //2b
                    r_destination_start_addr_load_12b <= i_ch2_rw_cmd[23:12]; //12b
                    r_destination_start_addr_load_14b <= i_ch2_rw_cmd[23:10]; //14b
                    r_load_busy                       <= 1'b1;
                    //
                    r_noc_write_last_flag             <= 1'b0;
                    r_sram_read_last_flag             <= 1'b0;
                end
                else if(i_ch2_rw_cmd[59]==1'b1) begin
                    r_control_mode                    <= i_ch2_rw_cmd[59:58];                     //2b 
                    r_prec_mode                       <= i_ch2_rw_cmd[57];                        //1b 
                    r_destination_start_addr_store    <= i_ch2_rw_cmd[SOURCE_ADDR_BIT+39:40];     // [ch2lin] 15b [54:40]
                    r_destination_offset_addr_store   <= r_last_addr_18b - i_ch2_rw_cmd[SOURCE_ADDR_BIT+39:40];
                    r_wrap_k                          <= r_first_addr_18b - 1'b1 - (r_last_addr_18b - i_ch2_rw_cmd[SOURCE_ADDR_BIT+39:40]); // FIX (E4)
                    r_data_height                     <= i_ch2_rw_cmd[39:30];                     //10b
                    r_data_width                      <= i_ch2_rw_cmd[29:20];                     //10b
                    r_data_channel                    <= i_ch2_rw_cmd[39:30]*i_ch2_rw_cmd[29:20]; //20b
                    r_noc_read_done                   <= 1'b0;
                    r_sram_write_done                 <= 1'b0;
                    r_store_busy                      <= 1'b1;
                end
            end
            if(current_state==BURST_LOAD) begin
                //sram read operation
                if(!r_sram_read_last_flag) begin
                    r_sram_read_valid        <= 1'b1; 
                    if(i_sram_read_ready&&o_sram_read_valid) begin
                        if (r_source_read_addr==0)begin
                            r_sram_read_last_flag <= 1'b1;
                        end
                        else begin
                            r_source_read_addr <= r_source_read_addr-1;
                        end
                        if(r_source_start_addr_18b==r_last_addr_18b)begin      // [ch2lin] 15b
                            r_source_start_addr_18b <= r_first_addr_18b;
                        end
                        else begin
                            r_source_start_addr_18b <= r_source_start_addr_18b+1;
                        end
                    end
                end
                else begin
                    r_sram_read_valid        <= 1'b0; 
                end

                //noc write operation
                if(!r_noc_write_last_flag) begin 
                    r_sram_read_data_ready <= 1'b1; // noc write ready and ==> o_sram_read_data_ready
                    if(i_sram_read_response&&o_sram_read_data_ready) begin
                        r_noc_write_valid        <=  1'b1;
                        r_noc_write_data         <=  i_sram_read_data; 
                        if(r_destination_PE_Accum && r_prec_mode) begin
                            r_noc_write_addr     <=  {r_destination_PE_Accum,r_destination_start_addr_load_12b,r_destination_offset_addr};
                        end
                        else begin
                            r_noc_write_addr     <=  {r_destination_PE_Accum,r_destination_start_addr_load_14b};
                        end
                        if(i_noc_write_ready) begin
                            if(r_destination_write_addr==0)begin
                                r_noc_write_last_flag <= 1'b1;
                            end
                            else begin
                                r_destination_write_addr <= r_destination_write_addr-1;
                            end

                            if (r_destination_PE_Accum && r_prec_mode) begin
                                r_destination_start_addr_load_12b <= r_destination_start_addr_load_12b+1;
                            end
                            else begin
                                r_destination_start_addr_load_14b <= r_destination_start_addr_load_14b+1;
                            end
                        end
                    end
                end
                else if (i_noc_write_ready && o_noc_write_valid)begin
                    r_sram_read_data_ready  <=  1'b0;
                    r_noc_write_valid       <=  1'b0;
                end
            end
            //////////////////////////////////////////////////////////////////////////////////
            if(current_state==HANDSHAKE_LOAD)begin
                //sram read
                if(!r_sram_read_last_flag) begin
                    r_sram_read_valid        <= 1'b1; 
                    if(i_sram_read_ready&&o_sram_read_valid) begin
                        if (r_source_read_addr==0)begin
                            r_sram_read_last_flag <= 1'b1;
                        end
                        else begin
                            r_source_read_addr <= r_source_read_addr-1;
                        end
                        if(r_source_start_addr_18b==r_last_addr_18b)begin      // [ch2lin] 15b
                            r_source_start_addr_18b <= r_first_addr_18b;
                        end
                        else begin
                            r_source_start_addr_18b <= r_source_start_addr_18b+1;
                        end
                    end
                end
                else begin
                    r_sram_read_valid        <= 1'b0; 
                end
                //noc write
                case(current_state_handshake)
                    DATA_FETCH_LOAD:begin
                        if(i_sram_read_response&&o_sram_read_data_ready)begin
                            r_sram_read_data_ready <= 1'b0;
                            r_noc_write_valid      <= 1'b1;
                            r_noc_write_data       <= i_sram_read_data;
                            if(r_destination_PE_Accum && r_prec_mode) begin
                                r_noc_write_addr   <= {r_destination_PE_Accum,r_destination_start_addr_load_12b,r_destination_offset_addr};
                            end
                            else begin
                                r_noc_write_addr   <= {r_destination_PE_Accum,r_destination_start_addr_load_14b};
                            end
                        end
                        else begin
                            r_sram_read_data_ready <= 1'b1;
                        end
                    end
                    ADDR_GEN_LOAD:begin //generation for next noc address
                        if(i_noc_write_response) begin
                            if(r_destination_write_addr==0)begin
                                r_noc_write_last_flag <= 1'b1;
                            end
                            else begin
                                r_destination_write_addr <= r_destination_write_addr-1;
                            end
                            if (r_destination_PE_Accum && r_prec_mode) begin
                                r_destination_start_addr_load_12b <= r_destination_start_addr_load_12b+1;
                            end
                            else begin
                                r_destination_start_addr_load_14b <= r_destination_start_addr_load_14b+1;
                            end
                            r_noc_write_valid  <= 1'b0;
                        end
                    end
                endcase        
            end
            //////////////////////////////////////////////////////////////////////////////////
            if(current_state==BURST_STORE) begin
                //noc read operation
                r_noc_read_ready <= 1'b1; 
                if(i_noc_read_valid && o_noc_read_ready) begin
                    r_fifo_noc_read_valid <= 1'b1;
                    r_fifo_noc_read_addr  <= {w_last,w_fifo_sram_write_addr_17b_2};   // [ch2lin] linear 15b
                    r_fifo_noc_read_data  <= i_noc_read_data;
                    if (w_last) begin
                        r_noc_read_done     <= 1'b1;
                    end
                end
                else begin
                    r_fifo_noc_read_valid   <= 1'b0;
                end 
                //sram write operation
                if(o_sram_write_valid && i_sram_write_ready) begin
                    if (w_fifo_sram_write_addr[SOURCE_ADDR_BIT]) begin
                        r_sram_write_done   <= 1'b1;
                        r_fifo_sram_write_ready   <= 1'b0;
                    end
                end
                else begin
                    r_fifo_sram_write_ready <= 1'b1; 
                end
            end
            //////////////////////////////////////////////////////////////////////////////////
            if(current_state==HANDSHAKE_STORE)begin
                case (current_state_handshake)
                    DATA_FETCH_STORE:begin
                        if(i_noc_read_valid)begin
                            r_fifo_noc_read_valid <= 1'b1;
                            r_fifo_noc_read_addr  <= {w_last,w_fifo_sram_write_addr_17b_2};   // [ch2lin] linear 15b
                            r_fifo_noc_read_data  <= i_noc_read_data;
                            if (w_last) begin
                                r_noc_read_done   <= 1'b1;
                            end
                            r_noc_read_response   <= 1'b1;
                        end
                        else begin
                            r_fifo_noc_read_valid <= 1'b0;
                        end
                    end
                    DATA_SEND_STORE:begin
                        r_noc_read_response  <= 1'b0;
                        if(w_fifo_noc_read_ready)begin
                            r_fifo_noc_read_valid <= 1'b0;
                        end
                    end
                endcase
                if(o_sram_write_valid && i_sram_write_ready) begin
                    if (w_fifo_sram_write_addr[SOURCE_ADDR_BIT]) begin
                        r_sram_write_done   <= 1'b1;
                        r_fifo_sram_write_ready   <= 1'b0;
                    end
                end
                else begin
                    r_fifo_sram_write_ready <= 1'b1; 
                end
            end
            //////////////////////////////////////////////////////////////////////////////////
            if(current_state==CMD_DONE) begin
                r_load_busy  <= 1'b0;
                r_store_busy <= 1'b0;
            end
        end
    end

    assign w_fifo_noc_read_valid = r_fifo_noc_read_valid && r_noc_read_ready && ~r_noc_read_done;
    assign w_fifo_sram_write_ready = i_sram_write_ready && r_fifo_sram_write_ready && ~r_sram_write_done;

    FIFO #(
        .DATA_WIDTH ( SOURCE_ADDR_BIT+1 ),
        .FIFO_DEPTH ( 4 )
    ) u_FIFO_noc_read_addr (
        .i_clk          ( i_clk ),
        .i_rstn         ( i_rstn ),
        .o_input_ready  ( w_fifo_noc_read_addr_ready ),
        .i_input_valid  ( r_fifo_noc_read_valid ),
        .i_input_data   ( r_fifo_noc_read_addr ),
        .i_output_ready ( w_fifo_sram_write_ready ),
        .o_output_valid ( w_fifo_sram_write_addr_valid ),
        .o_output_data  ( w_fifo_sram_write_addr )
    );

    assign w_fifo_noc_read_ready = w_fifo_noc_read_addr_ready && w_fifo_noc_read_data_ready;

    FIFO #(
        .DATA_WIDTH ( BANDWIDTH_CHANNEL_2 ),
        .FIFO_DEPTH ( 4 )
    ) u_FIFO_noc_read_data (
        .i_clk          ( i_clk ),
        .i_rstn         ( i_rstn ),
        .o_input_ready  ( w_fifo_noc_read_data_ready ),
        .i_input_valid  ( r_fifo_noc_read_valid ),
        .i_input_data   ( r_fifo_noc_read_data ),
        .i_output_ready ( w_fifo_sram_write_ready ),
        .o_output_valid ( w_fifo_sram_write_data_valid ),
        .o_output_data  ( w_fifo_sram_write_data )
    );

endmodule 