`timescale 1ns / 1ps

module cmd_decoder_channel_1_in #(
    parameter  SOURCE_ADDR_BIT        = 17,  // source_addr bit number
    parameter  DESTINATION_ADDR_BIT   = 19,  // destination addr bit number(fixed) ==> 19b
    parameter  BANDWIDTH_CHANNEL_1    = 512
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
    // ========== Interface with L1_FIFO_interface (SRAM Read Path) ========== 
    output wire [SOURCE_ADDR_BIT-1:0]      o_sram_read_addr,
    output wire                            o_sram_read_valid, 
    output wire                            o_sram_read_data_ready,  //data_fifo_ready                                                  
    input  wire                            i_sram_read_ready,       //fifo_read_ready                                                      
    input  wire                            i_sram_read_response,    //read_ready                                                        
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
    output wire [DESTINATION_ADDR_BIT-1:0]   o_noc_read_addr,
    output wire                              o_noc_read_valid, 
    output wire                              o_noc_read_data_ready,
    input  wire                              i_noc_read_ready,     
    input  wire                              i_noc_read_response,        
    input  wire [BANDWIDTH_CHANNEL_1-1:0]    i_noc_read_data,
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

    // sram read path register
    reg [SOURCE_ADDR_BIT-1:0]  r_sram_read_addr;
    reg                        r_sram_read_valid;
    reg                        r_sram_read_data_ready;
    // noc write path register
    reg [DESTINATION_ADDR_BIT-1:0]  r_noc_write_addr;
    reg [BANDWIDTH_CHANNEL_1-1:0]   r_noc_write_data;
    reg                             r_noc_write_valid;
    // load operation command register
    reg [7:0]  r_multicast;
    reg [1:0]  r_control_mode; 
    reg        r_prec_mode;
    reg [SOURCE_ADDR_BIT-1:0]      r_source_start_addr;
    reg [DESTINATION_ADDR_BIT-9:0] r_source_read_addr;
    reg [DESTINATION_ADDR_BIT-9:0] r_destination_start_addr;
    reg [2:0]                      r_resize_step_addr;
    //additional register
    reg [DESTINATION_ADDR_BIT-9:0]  r_destination_write_addr;
    reg [1:0]                       r_resize_read_cnt;
    reg [1:0]                       r_resize_write_cnt;
    reg [7:0]                       r_resize_width_cnt;
    reg [8:0]                       r_resize_width;
    // cache first & last addr 
    reg [SOURCE_ADDR_BIT-1:0]       r_first_addr; 
    reg [SOURCE_ADDR_BIT-1:0]       r_last_addr;
    //top ctrl interface
    reg        r_ch1_rw_cmd_ready;
    reg        r_load_busy;
    reg        r_noc_write_last_flag;
    reg        r_noc_read_last_flag;
    reg        r_sram_write_last_flag;
    reg        r_sram_read_last_flag;
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // burst store
    reg    r_store_busy;
    assign o_store_busy = r_store_busy;

    // channel 1 weight store cmd register
    reg [SOURCE_ADDR_BIT-1:0] r_destination_start_addr_store;      //17b
    // burst store
    reg [13:0] r_destination_write_addr_store;      // 14b
    reg [13:0] r_source_read_addr_store;            // 14b
    reg [13:0] r_noc_read_addr;                     // 14b
    reg [13:0] r_source_start_addr_store;           // 14b

    // burst store
    // noc read
    reg        r_noc_read_valid;
    wire [7:0] w_multicast_store;
    assign w_multicast_store = 1'b1 << r_source_start_addr_store[13:11];
    assign o_noc_read_addr       = {w_multicast_store,r_source_start_addr_store[10:0]};
    assign o_noc_read_valid      = r_noc_read_valid && (~r_noc_read_last_flag);
    //sram write
    reg                            r_noc_read_data_ready;
    assign o_noc_read_data_ready = r_noc_read_data_ready && i_sram_write_ready;
    reg                            r_sram_write_valid;
    reg [SOURCE_ADDR_BIT-1:0]      r_sram_write_addr;
    reg [BANDWIDTH_CHANNEL_1-1:0]  r_sram_write_data;

    assign o_sram_write_valid = r_sram_write_valid;
    assign o_sram_write_addr  = r_sram_write_addr;
    assign o_sram_write_data  = r_sram_write_data;

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
            CMD_DECODE: begin //default assignment ==> if문법 괜찮
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
    assign o_ch1_rw_cmd_ready     = r_ch1_rw_cmd_ready;
    assign o_load_busy            = r_load_busy;
    assign o_sram_control_mode    = 1'b0;
    assign o_noc_control_mode     = r_control_mode[0];

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            // sram read path register reset
            r_sram_read_addr         <= {SOURCE_ADDR_BIT{1'b0}};
            r_sram_read_valid        <= 1'b0;
            r_sram_read_data_ready   <= 1'b0;
            // noc write path register reset
            r_noc_write_valid        <= 1'b0;
            r_noc_write_addr         <= {DESTINATION_ADDR_BIT{1'b0}};
            r_noc_write_data         <= {BANDWIDTH_CHANNEL_1{1'b0}};
            // load operation command register reset
            r_multicast              <= 8'b0;                         //8b
            r_control_mode           <= 2'b0;                         //2b 
            r_prec_mode              <= 1'b0;                         //1b 
            r_source_start_addr      <= {SOURCE_ADDR_BIT{1'b0}};      //17b
            r_source_read_addr       <= {DESTINATION_ADDR_BIT-8{1'b0}}; //11b
            r_destination_start_addr <= {DESTINATION_ADDR_BIT-8{1'b0}}; //11b
            r_resize_step_addr       <= 3'b0;                         //3b
            // additional register
            r_destination_write_addr <= {DESTINATION_ADDR_BIT-8{1'b0}}; //11b
            r_resize_read_cnt        <= 2'b0;                         //2b
            r_resize_write_cnt       <= 2'b0;                         //2b
            r_resize_width_cnt       <= 8'b0;                         //8b
            r_resize_width           <= 9'b0;                         //9b
            // top ctrl interface
            r_ch1_rw_cmd_ready       <= 1'b0;
            r_load_busy              <= 1'b0;
            // cache first & last addr
            r_first_addr             <= {SOURCE_ADDR_BIT{1'b0}};
            r_last_addr              <= {SOURCE_ADDR_BIT{1'b1}};
            //
            r_noc_write_last_flag    <= 1'b0;     
            r_sram_read_last_flag    <= 1'b0;    
        end
        else begin
            if(current_state==IDLE)begin
                r_ch1_rw_cmd_ready       <= 1'b1;
            end

            if(current_state==IDLE && next_state==CMD_DECODE) begin
                r_ch1_rw_cmd_ready       <= 1'b0;
                r_load_busy              <= 1'b1; // 어짜피 하나로 놔둘거라서 문제 없음
                r_multicast              <= i_ch1_rw_cmd[14:7];  // 8b
                r_control_mode           <= i_ch1_rw_cmd[59:58]; // 2b 
                r_prec_mode              <= i_ch1_rw_cmd[57];    // 1b 
                r_source_start_addr      <= i_ch1_rw_cmd[SOURCE_ADDR_BIT+39:40]; //8MB 기준 17b
                r_source_read_addr       <= i_ch1_rw_cmd[39:29]; //11b
                r_destination_start_addr <= i_ch1_rw_cmd[28:18]; //11b
                r_resize_step_addr       <= i_ch1_rw_cmd[17:15]; // 3b
                r_destination_write_addr <= i_ch1_rw_cmd[39:29]; //11b
                r_resize_read_cnt        <= 2'b0;                   //2b
                r_resize_write_cnt       <= 2'b0;                   //2b
                r_resize_width_cnt       <= 8'b0;                   //8b
                r_resize_width           <= i_ch1_rw_cmd[17:15]*20; //9b 
              //r_resize_width           <= i_ch1_rw_cmd[17:15]*2;  //9b
                r_noc_write_last_flag    <= 1'b0;
                r_sram_read_last_flag    <= 1'b0;
            end
            
            if(current_state==BURST_LOAD)begin
                //sram read operation
                // resize O
                if(r_resize_step_addr>0) begin
                    if(!r_sram_read_last_flag) begin
                        r_sram_read_valid <= 1'b1;
                        if(i_sram_read_ready&&o_sram_read_valid) begin
                            if(r_resize_read_cnt==2'd3) begin
                                r_resize_read_cnt  <= 2'b0;
                                if (r_source_read_addr==0)begin
                                    r_sram_read_last_flag <= 1'b1;
                                end
                                else begin
                                    r_source_read_addr <= r_source_read_addr-1;
                                end
                                if(r_source_start_addr==r_last_addr) begin
                                    r_source_start_addr <= r_first_addr;
                                end
                                else begin
                                    r_source_start_addr <= r_source_start_addr+1;
                                end
                            end
                            else begin
                                r_resize_read_cnt <= r_resize_read_cnt+1;
                            end
                        end
                    end
                    else begin
                        r_sram_read_valid <= 1'b0;
                    end
                end
                // resize X
                else begin
                    if(!r_sram_read_last_flag) begin 
                        r_sram_read_valid        <= 1'b1; 
                        if(i_sram_read_ready&&o_sram_read_valid) begin 
                            if (r_source_read_addr==0)begin
                                r_sram_read_last_flag <= 1'b1;
                            end
                            else begin
                                r_source_read_addr <= r_source_read_addr-1;
                            end
                            if(r_source_start_addr==r_last_addr)begin
                                r_source_start_addr <= r_first_addr;
                            end
                            else begin
                                r_source_start_addr <= r_source_start_addr+1;
                            end
                        end
                    end
                    else begin
                        r_sram_read_valid        <= 1'b0; 
                    end
                end
                //noc write operation
                // resize O
                if(r_resize_step_addr>0) begin  //r_noc_write_last_flag
                    if(!r_noc_write_last_flag) begin
                        r_sram_read_data_ready       <= 1'b1; // noc write ready and ==> o_sram_read_data_ready
                        if(i_sram_read_response&&o_sram_read_data_ready) begin
                            r_noc_write_valid        <=  1'b1;
                            r_noc_write_data         <=  i_sram_read_data;
                            r_noc_write_addr         <=  {r_multicast,r_destination_start_addr};
                            if(i_noc_write_ready) begin
                                case (r_resize_write_cnt)
                                    2'd0: begin
                                        r_resize_write_cnt        <=  r_resize_write_cnt+1;
                                        r_destination_start_addr  <=  r_destination_start_addr+1;
                                    end
                                    2'd1: begin
                                        r_resize_write_cnt        <=  r_resize_write_cnt+1;
                                        r_destination_start_addr  <=  r_destination_start_addr+r_resize_width-1;
                                    end
                                    2'd2: begin
                                        r_resize_write_cnt        <=  r_resize_write_cnt+1;
                                        r_destination_start_addr  <=  r_destination_start_addr+1;                                    
                                    end
                                    2'd3: begin
                                        if (r_destination_write_addr==0)begin
                                            r_noc_write_last_flag <= 1'b1;
                                        end
                                        else begin
                                            r_destination_write_addr <= r_destination_write_addr-1;
                                        end
                                        r_resize_write_cnt        <=  2'b0;
                                        if(r_resize_width_cnt==(r_resize_width[7:0]-2)) begin
                                            r_resize_width_cnt        <= 8'b0; 
                                            r_destination_start_addr  <= r_destination_start_addr+1;
                                        end
                                        else begin
                                            r_resize_width_cnt        <=  r_resize_width_cnt+2;
                                            r_destination_start_addr  <=  r_destination_start_addr-r_resize_width+1;
                                        end
                                    end
                                endcase 
                            end
                        end
                    end
                    else if (i_noc_write_ready && o_noc_write_valid)begin
                        r_sram_read_data_ready  <=  1'b0;
                        r_noc_write_valid       <=  1'b0;
                    end
                end

                // resize X
                else begin
                    if(!r_noc_write_last_flag) begin
                        r_sram_read_data_ready       <= 1'b1; // noc write ready and ==> o_sram_read_data_ready
                        if(i_sram_read_response&&o_sram_read_data_ready) begin
                            r_noc_write_valid        <=  1'b1;
                            r_noc_write_data         <=  i_sram_read_data;
                            r_noc_write_addr         <=  {r_multicast,r_destination_start_addr};
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
            end
/////////////////////////////////////////////////////////////////////////////////////////
            if (current_state==HANDSHAKE_LOAD) begin
                /// sram read
                // resize O
                if(r_resize_step_addr>0) begin
                    if(!r_sram_read_last_flag) begin
                        r_sram_read_valid <= 1'b1;
                        if(i_sram_read_ready&&o_sram_read_valid) begin
                            if(r_resize_read_cnt==2'd3) begin
                                r_resize_read_cnt  <= 2'b0;
                                if (r_source_read_addr==0)begin
                                    r_sram_read_last_flag <= 1'b1;
                                end
                                else begin
                                    r_source_read_addr <= r_source_read_addr-1;
                                end
                                if(r_source_start_addr==r_last_addr) begin
                                    r_source_start_addr <= r_first_addr;
                                end
                                else begin
                                    r_source_start_addr <= r_source_start_addr+1;
                                end
                            end
                            else begin
                                r_resize_read_cnt <= r_resize_read_cnt+1;
                            end
                        end
                    end
                    else begin
                        r_sram_read_valid <= 1'b0;
                    end
                end
                // resize X
                else begin
                    if(!r_sram_read_last_flag) begin 
                        r_sram_read_valid        <= 1'b1; 
                        if(i_sram_read_ready&&o_sram_read_valid) begin 
                            if (r_source_read_addr==0)begin
                                r_sram_read_last_flag <= 1'b1;
                            end
                            else begin
                                r_source_read_addr <= r_source_read_addr-1;
                            end
                            if(r_source_start_addr==r_last_addr)begin
                                r_source_start_addr <= r_first_addr;
                            end
                            else begin
                                r_source_start_addr <= r_source_start_addr+1;
                            end
                        end
                    end
                    else begin
                        r_sram_read_valid        <= 1'b0; 
                    end
                end
                //// noc write
                case(current_state_handshake)
                    DATA_FETCH_LOAD:begin
                        if(i_sram_read_response&&o_sram_read_data_ready)begin
                            r_sram_read_data_ready <= 1'b0;
                            r_noc_write_valid      <= 1'b1;
                            r_noc_write_data       <= i_sram_read_data;
                            r_noc_write_addr       <= {r_multicast,r_destination_start_addr};
                        end
                        else begin
                            r_sram_read_data_ready <= 1'b1;
                        end
                    end
                    ADDR_GEN_LOAD:begin //generation for next noc address
                        if(r_resize_step_addr>0) begin
                            if(i_noc_write_response) begin
                                r_noc_write_valid        <= 1'b0;
                                case (r_resize_write_cnt)
                                    2'd0: begin
                                        r_resize_write_cnt        <=  r_resize_write_cnt+1;
                                        r_destination_start_addr  <=  r_destination_start_addr+1;
                                    end
                                    2'd1: begin
                                        r_resize_write_cnt        <=  r_resize_write_cnt+1;
                                        r_destination_start_addr  <=  r_destination_start_addr+r_resize_width-1;
                                    end
                                    2'd2: begin
                                        r_resize_write_cnt        <=  r_resize_write_cnt+1;
                                        r_destination_start_addr  <=  r_destination_start_addr+1;                                    
                                    end
                                    2'd3: begin
                                        if (r_destination_write_addr==0)begin
                                            r_noc_write_last_flag <= 1'b1;
                                        end
                                        else begin
                                            r_destination_write_addr <= r_destination_write_addr-1;
                                        end
                                        r_resize_write_cnt        <=  2'b0;
                                        if(r_resize_width_cnt==(r_resize_width[7:0]-2)) begin
                                            r_resize_width_cnt        <= 8'b0; 
                                            r_destination_start_addr  <= r_destination_start_addr+1;
                                        end
                                        else begin
                                            r_resize_width_cnt        <=  r_resize_width_cnt+2;
                                            r_destination_start_addr  <=  r_destination_start_addr-r_resize_width+1;
                                        end
                                    end
                                endcase 
                            end
                        end
                        else begin
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
                    end
                endcase
            end
///////////////////////////////////////////////////////////////////////////////////
            if (current_state==CMD_DONE) begin
                r_load_busy <= 1'b0;
            end
        end
    end

/// store operation
    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin
            //
            r_store_busy                        <= 1'b0;
            r_destination_start_addr_store      <= {SOURCE_ADDR_BIT{1'b0}};
            // burst store
            r_destination_write_addr_store      <= 14'b0;
            r_source_read_addr_store            <= 14'b0;
            r_source_start_addr_store           <= 14'b0;
            //
            r_noc_read_valid                    <=  1'b0;
            //
            r_noc_read_data_ready               <= 1'b0;
            //
            r_sram_write_valid                  <= 1'b0;
            r_sram_write_addr                   <= {SOURCE_ADDR_BIT{1'b0}};
            r_sram_write_data                   <= {BANDWIDTH_CHANNEL_1{1'b0}};
            //
            r_noc_read_last_flag                <= 1'b0;
            r_sram_write_last_flag              <= 1'b0;
        end
        else begin
            if((current_state==IDLE)&&(next_state==CMD_DECODE)) begin
                if (i_ch1_rw_cmd[59]==1'b1) begin
                    r_destination_start_addr_store       <= i_ch1_rw_cmd[SOURCE_ADDR_BIT+40:41];
                    // burst store
                    r_destination_write_addr_store       <= i_ch1_rw_cmd[40:27];
                    r_source_read_addr_store             <= i_ch1_rw_cmd[40:27];
                    r_source_start_addr_store            <= i_ch1_rw_cmd[26:13];
                    r_noc_read_last_flag                 <= 1'b0;
                    r_sram_write_last_flag               <= 1'b0;
                end
            end
            if(current_state==BURST_STORE)begin
                if (!r_noc_read_last_flag)begin
                    r_noc_read_valid <= 1'b1;
                    if(i_noc_read_ready&&o_noc_read_valid)begin 
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
                            if(r_destination_start_addr_store==r_last_addr)begin
                                r_destination_start_addr_store <= r_first_addr;
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
            if(current_state==HANDSHAKE_STORE) begin
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
                            if(r_destination_start_addr_store==r_last_addr)begin
                                r_destination_start_addr_store <= r_first_addr;
                            end
                            else begin
                                r_destination_start_addr_store <= r_destination_start_addr_store+1;
                            end
                        end
                    end
                endcase
            end
        end
    end
endmodule