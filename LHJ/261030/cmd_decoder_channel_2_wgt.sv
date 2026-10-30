// =============================================================================
//  FIXED COPY (bb256 환경 전용) - (C2), ch1_wgt 의 (C) 와 같은 문제
//  원본 경로 : LHJ/261020/cmd_decoder_channel_2_wgt.sv = rtl/L2_260901 원본과 같음 (원본은 수정하지 않음)
//  모듈 이름은 그대로 -> 파일 목록에서 원본 대신 이 파일을 넣는다.
//
//  바꾼 것 2곳 (원본으로는 512줄 handshake LOAD 후 weight 메모리 511줄 불일치, tb_bb256_system T11):
//   (C3) CMD_DECODE 에서 control_mode 01 (handshake LOAD) 의 다음 상태가 ADDR_GEN_LOAD 였다.
//        ADDR_GEN_LOAD 는 보조 handshake FSM 의 상태 이름이고 값이 3'd3 = 메인 FSM 의 BURST_LOAD.
//        -> handshake 명령이 burst 상태로 실행되고 NoC 쪽만 handshake 모드가 되어 데이터가 어긋났다.
//        HANDSHAKE_LOAD 로 고침 (ch1_wgt / ch2_in decoder 와 같은 형태).
//   (C2) o_sram_control_mode : r_control_mode[0] -> 1'b0
//        ch1_wgt 의 (C) 와 같은 패턴. handshake 명령이면 L2 내부 SRAM 쪽 FIFO 인터페이스까지 handshake
//        모드가 되어 SRAM 읽기 데이터가 다음 줄로 넘어가지 않는다. NoC 쪽 모드 (o_noc_control_mode) 는 그대로.
//   각 수정이 필요한지는 하나씩 되돌려 T11 로 확인한다 (README 참고).
// =============================================================================
// 2026-02-11
// version 0
// Jo Min Young bad bitch

`timescale 1ns / 1ps

module cmd_decoder_channel_2_wgt #(
    parameter  SOURCE_ADDR_BIT        = 18,  // source_addr bit number
    parameter  DESTINATION_ADDR_BIT   = 9,  // destination addr bit number(fixed)
    parameter  BANDWIDTH_CHANNEL_2    = 256
)(
    input  wire        i_clk,
    input  wire        i_rstn,

    // ========== Interface with command_decoder ==========
    input  wire [63:0] i_ch2_rw_cmd,       
    input  wire        i_ch2_rw_cmd_valid, 
    output wire        o_ch2_rw_cmd_ready,      

    // ========== Interface with top_ctrl ==========
    output wire        o_load_busy,               

    // ========== Interface with VE_interface (SRAM Read Path) ========== 
    output wire [SOURCE_ADDR_BIT-1:0]                  o_sram_read_addr,
    output wire                                        o_sram_read_valid, 
    output wire                                        o_sram_read_data_ready,
    input  wire                                        i_sram_read_ready,    
    input  wire                                        i_sram_read_response, 
    input  wire [BANDWIDTH_CHANNEL_2-1:0]              i_sram_read_data,
    
    output wire o_sram_control_mode,

    // ========== Interface with FIFO_interface (NOC Write Path) ========== 
    input  wire                                        i_noc_write_ready,    
    output wire                                        o_noc_write_valid,
    output wire [DESTINATION_ADDR_BIT-1:0]             o_noc_write_addr,
    output wire [BANDWIDTH_CHANNEL_2-1:0]              o_noc_write_data,
    input  wire                                        i_noc_write_response,

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
    localparam CMD_DONE         = 3'd5;  // command end state
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
    localparam CMD_DONE_HS      = 3'd4;  // command end state
    //===============================================================================================
    reg [2:0] current_state_handshake;
    reg [2:0] next_state_handshake;
    //===============================================================================================
    // sram read path register
    reg [SOURCE_ADDR_BIT-1:0]         r_sram_read_addr;
    reg                               r_sram_read_valid;
    reg                               r_sram_read_data_ready;
    // noc write path register
    reg [DESTINATION_ADDR_BIT-1:0]    r_noc_write_addr;
    reg [BANDWIDTH_CHANNEL_2-1:0]     r_noc_write_data;
    reg                               r_noc_write_valid;
    // load operation command register
    reg [1:0]                         r_control_mode; 
    reg [SOURCE_ADDR_BIT-1:0]         r_source_start_addr;
    reg [DESTINATION_ADDR_BIT-1:0]    r_source_read_addr;
    reg [DESTINATION_ADDR_BIT-1:0]    r_destination_start_addr;
    // load : additional register
    reg [DESTINATION_ADDR_BIT-1:0]    r_destination_write_addr;

    // cache first & last addr
    reg [SOURCE_ADDR_BIT-1:0]         r_first_addr_18b; 
    reg [SOURCE_ADDR_BIT-1:0]         r_last_addr_18b;

    // top ctrl interface
    reg                               r_ch2_rw_cmd_ready;
    reg                               r_load_busy;
    //
    reg                               r_noc_write_last_flag;
    reg                               r_sram_read_last_flag;

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
            CMD_DECODE: begin
                if(r_control_mode==2'b00)begin
                    next_state = BURST_LOAD;
                end
                else if(r_control_mode==2'b01)begin
                    next_state = HANDSHAKE_LOAD;   // FIX (C3): was ADDR_GEN_LOAD (= 3'd3 = BURST_LOAD)
                end
                else if(r_control_mode==2'b10)begin
                    next_state = IDLE;
                end
                else if(r_control_mode==2'b11)begin
                    next_state = IDLE;
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
            // cmd end state
            CMD_DONE: begin
                next_state = IDLE;
            end
        endcase
    end
    //===============================================================================================
    // sram read path output
    assign o_sram_read_addr       = r_source_start_addr;
    assign o_sram_read_valid      = r_sram_read_valid && (~r_sram_read_last_flag);
    assign o_sram_read_data_ready = r_sram_read_data_ready && i_noc_write_ready;
    // noc write path output
    assign o_noc_write_addr       = r_noc_write_addr;
    assign o_noc_write_data       = r_noc_write_data;
    assign o_noc_write_valid      = r_noc_write_valid;
    // top ctrl interface
    assign o_ch2_rw_cmd_ready     = r_ch2_rw_cmd_ready;
    assign o_load_busy            = r_load_busy;
    assign o_sram_control_mode    = 1'b0;   // FIX (C2): SRAM side always on-fire, same as ch1_in / ch1_wgt (C)
    assign o_noc_control_mode     = r_control_mode[0];

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
            r_source_start_addr               <= {SOURCE_ADDR_BIT{1'b0}};
            r_source_read_addr                <= {DESTINATION_ADDR_BIT{1'b0}};
            // load operation : additional register
            r_destination_write_addr          <= {DESTINATION_ADDR_BIT{1'b0}};
            r_destination_start_addr          <= {DESTINATION_ADDR_BIT{1'b0}};
            // cache first & last addr
            r_first_addr_18b                  <= {SOURCE_ADDR_BIT{1'b0}};
            r_last_addr_18b                   <= {SOURCE_ADDR_BIT{1'b1}};
            // top ctrl interface
            r_ch2_rw_cmd_ready                <= 1'b0;
            r_load_busy                       <= 1'b0;
            //
            r_noc_write_last_flag             <= 1'b0;
            r_sram_read_last_flag             <= 1'b0;
        end
        else begin
            if(current_state==IDLE)begin
                r_ch2_rw_cmd_ready  <= 1'b1;
            end
            if(current_state==IDLE && next_state==CMD_DECODE) begin
                r_ch2_rw_cmd_ready  <= 1'b0;
                r_control_mode                    <= i_ch2_rw_cmd[59:58]; //2b 
                r_source_start_addr               <= i_ch2_rw_cmd[SOURCE_ADDR_BIT+39:40]; //18b
                r_source_read_addr                <= i_ch2_rw_cmd[39:31]; //8b
                r_destination_write_addr          <= i_ch2_rw_cmd[39:31]; //8b
                r_destination_start_addr          <= i_ch2_rw_cmd[30:22]; //8b
                r_load_busy                       <= 1'b1;
                //
                r_noc_write_last_flag             <= 1'b0;
                r_sram_read_last_flag             <= 1'b0;
            end
            if(current_state==BURST_LOAD) begin
                //sram read operation
                if(!r_sram_read_last_flag) begin 
                    r_sram_read_valid        <= 1'b1; 
                    if(i_sram_read_ready && o_sram_read_valid) begin
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
                    r_sram_read_valid        <= 1'b0; 
                end

                //noc write operation
                if(!r_noc_write_last_flag) begin 
                    r_sram_read_data_ready <= 1'b1; 
                    if(i_sram_read_response&&o_sram_read_data_ready) begin
                        r_noc_write_valid        <=  1'b1;
                        r_noc_write_addr         <=  r_destination_start_addr;
                        r_noc_write_data         <=  i_sram_read_data; 
                        if(i_noc_write_ready) begin
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
                else if (i_noc_write_ready && o_noc_write_valid)begin
                    r_sram_read_data_ready  <=  1'b0;
                    r_noc_write_valid       <=  1'b0;
                end
            end
            if(current_state==HANDSHAKE_LOAD)begin
                //sram read
                if(!r_sram_read_last_flag) begin 
                    r_sram_read_valid        <= 1'b1; 
                    if(i_sram_read_ready && o_sram_read_valid) begin
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
                    r_sram_read_valid        <= 1'b0; 
                end
                //noc write
                case(current_state_handshake)
                    DATA_FETCH_LOAD:begin
                        if(i_sram_read_response&&o_sram_read_data_ready)begin
                            r_sram_read_data_ready <= 1'b0;
                            r_noc_write_valid      <= 1'b1;
                            r_noc_write_data       <= i_sram_read_data;
                            r_noc_write_addr       <= r_destination_start_addr;
                        end
                        else begin
                            r_sram_read_data_ready <= 1'b1;
                        end
                    end
                    ADDR_GEN_LOAD:begin //generation for next noc address
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
                endcase
            end
            if(current_state==CMD_DONE) begin
                r_ch2_rw_cmd_ready  <= 1'b1;
                r_load_busy         <= 1'b0;
            end
        end
    end

endmodule
