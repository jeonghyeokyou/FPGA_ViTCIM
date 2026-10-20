`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// Project      : L1 Cache Controller
// Module       : L1_Cache_ReadWriteCTRL_WithMode
// Author       : ParkSunJong
// Description  : Unified Read/Write controller with optional handshaking.
// Version      : 2025-06-18 <Basic Version>
//                2025-06-20 <r_addr : Debugging>      
// -----------------------------------------------------------------------------


module sram_controller #(
    parameter ADDR_DEPTH = 64,
    parameter DATA_WIDTH = 128,
    localparam ADDR_BW    = $clog2(ADDR_DEPTH)
)(
    // -------------------------------------------------------------------------
    // Global Signals
    input  wire                    i_clk,
    input  wire                    i_rstn,

    // -------------------------------------------------------------------------
    // Control Mode
    // 1: Use handshaking (valid & ready)
    // 0: Fire-on-valid mode
    input  wire                    i_control_mode,

    // -------------------------------------------------------------------------
    // Read Interface
    input  wire                    i_read_valid,
    output wire                    o_read_ready,
    input  wire [ADDR_BW-1:0]      i_read_addr,
    output wire [DATA_WIDTH-1:0]   o_read_data,

    // -------------------------------------------------------------------------
    // Write Interface
    input  wire                    i_write_valid,
    output wire                    o_write_ready,
    input  wire [ADDR_BW-1:0]      i_write_addr,
    input  wire [DATA_WIDTH-1:0]   i_write_data,

    // -------------------------------------------------------------------------
    // SRAM Interface (Active-Low)
    output wire                    o_sram_ceb,
    output wire                    o_sram_web,
    output wire [ADDR_BW-1:0]      o_sram_addr,
    output wire [DATA_WIDTH-1:0]   o_sram_din,
    input  wire [DATA_WIDTH-1:0]   i_sram_dout
);

    // -------------------------------------------------------------------------
    // FSM States
    // -------------------------------------------------------------------------
    localparam IDLE                 = 3'd0;
    localparam READ_OPERATION       = 3'd1;
    localparam WRITE_OPERATION      = 3'd2;
    localparam GET_DATA             = 3'd3;
    localparam WRITE_DONE           = 3'd4;
    localparam READ_RESPONSE        = 3'd5;
    localparam WRITE_RESPONSE       = 3'd6;
    // -------------------------------------------------------------------------
    // Internal Registers
    // -------------------------------------------------------------------------
    reg [2:0]               r_current_state;
    reg [2:0]               r_next_state;
    reg                     r_ceb;
    reg                     r_web;
    reg [ADDR_BW-1:0]       r_addr;
    reg [DATA_WIDTH-1:0]    r_read_data;
    reg [DATA_WIDTH-1:0]    r_write_data;
    reg                     r_read_ready;
    reg                     r_write_ready;
    reg                     del1_i_read_valid;
    reg                     del2_i_read_valid;
    reg                     del1_i_write_valid;
    // -------------------------------------------------------------------------
    // Output Assignments
    // -------------------------------------------------------------------------
    assign o_sram_ceb       = r_ceb;
    assign o_sram_web       = r_web;
    assign o_sram_addr      = r_addr;
    assign o_sram_din       = r_write_data;
    assign o_read_ready     = r_read_ready;
    assign o_write_ready    = r_write_ready;
    assign o_read_data      = r_read_data; 
    // -------------------------------------------------------------------------
    // FSM Logic
    // -------------------------------------------------------------------------
    always @(posedge i_clk or negedge i_rstn)begin 
        if(i_rstn == 1'b0)begin
            r_current_state <= IDLE;
        end 
        else begin 
            r_current_state <= r_next_state;
        end 
    end 
    
    always@(*) begin
        case(r_current_state)
            IDLE:begin
                r_next_state = (i_control_mode && i_read_valid)  ?   READ_OPERATION   :
                               (i_control_mode && i_write_valid) ?   WRITE_OPERATION  :
                               IDLE;
             end
            WRITE_OPERATION :  r_next_state = WRITE_DONE;
            WRITE_DONE :       r_next_state = WRITE_RESPONSE;
            READ_OPERATION :   r_next_state = GET_DATA;
            GET_DATA :         r_next_state = READ_RESPONSE;
            WRITE_RESPONSE :   r_next_state = (i_write_valid ==1'b0) ? IDLE : WRITE_RESPONSE;
            READ_RESPONSE  :   r_next_state = (i_read_valid ==1'b0)  ? IDLE : READ_RESPONSE;
            default        :   r_next_state = IDLE;
        endcase
    end 
    
    always@(posedge i_clk or negedge i_rstn)begin
        if(i_rstn == 1'b0)begin 
            r_ceb <= 1'b1;
        end 
        else begin
            if(i_control_mode == 1'b1) begin
                case(r_current_state)
                        IDLE                 :  r_ceb <= ((i_read_valid == 1'b1) || (i_write_valid == 1'b1 )) ?   1'b0: 1'b1;
                        default              :  r_ceb <= 1'b1;
                endcase 
            end
            else if (i_control_mode == 1'b0)begin
                r_ceb <= ((i_read_valid == 1'b1) || (i_write_valid == 1'b1 )) ?   1'b0: 1'b1;
            end
            else begin
                r_ceb <= 1'b1;
            end
        end 
    end 
    
    always@(posedge i_clk or negedge i_rstn)begin
        if(i_rstn == 1'b0)begin 
            r_web <= 1'b1;
        end 
        else begin
            if(i_control_mode == 1'b1)begin
                case(r_current_state)
                        IDLE                 :  r_web <= (i_write_valid) ? 1'b0 : 1'b1;
                        default              :  r_web <= 1'b1;
                endcase 
            end
            else if(i_control_mode == 1'b0)begin
                    r_web <= (i_write_valid) ? 1'b0 : 1'b1;
            end 
            else begin
                    r_web <= 1'b1;
            end
        end 
    end 
    
    always @(posedge i_clk or negedge i_rstn) begin
        if(i_rstn == 1'b0) begin 
            r_addr <= {ADDR_BW{1'b0}};
        end 
        else begin 
                 if(i_read_valid == 1'b1 && i_write_valid == 1'b0) r_addr <= i_read_addr;
            else if(i_read_valid == 1'b0 && i_write_valid == 1'b1) r_addr <= i_write_addr;
            else                                                   r_addr <= {ADDR_BW{1'b0}}; 
            /*
            if(i_control_mode == 1'b1)begin
               case(r_current_state) 
                        IDLE            :   r_addr  <= (i_read_valid)  ?   i_read_addr  :   (i_write_valid)  ?  i_write_addr :  {ADDR_BW{1'b0}};   
                        default         :   r_addr  <= {ADDR_BW{1'b0}};
                endcase  
            end
            else if(i_control_mode == 1'b0)begin 
                r_addr <= i_read_addr;
            end
            */ 
        end 
    end 
    
    always @(posedge i_clk or negedge i_rstn)begin
        if(i_rstn == 1'b0) begin 
            r_write_data <= {DATA_WIDTH{1'b0}};
        end 
        else begin
            if(i_control_mode == 1'b1) begin
                case(r_current_state) 
                        IDLE           :  r_write_data    <=      (i_write_valid == 1'b1) ? i_write_data : {DATA_WIDTH{1'b0}};      //write data Capute
                        default        :  r_write_data    <=      {DATA_WIDTH{1'b0}};   
                endcase 
            end 
            else if(i_control_mode == 1'b0) begin
                   r_write_data <= (i_write_valid == 1'b1 )? i_write_data : {DATA_WIDTH{1'b0}};
            end
        end 
    end 
    
    always@(posedge i_clk or negedge i_rstn)begin
        if(i_rstn == 1'b0)begin
            r_read_data <={DATA_WIDTH{1'b0}};
        end
        else begin 
            if(i_control_mode == 1'b1) begin
                case(r_current_state) 
                    GET_DATA      :    r_read_data <= i_sram_dout;
                    READ_RESPONSE :    r_read_data <= r_read_data;
                    default       :    r_read_data <= {DATA_WIDTH{1'b0}};      
                endcase
            end 
            else if (i_control_mode == 1'b0) begin 
                r_read_data  <= (del2_i_read_valid) ? i_sram_dout : {DATA_WIDTH{1'b0}}; 
            end
            else begin 
                r_read_data <= {DATA_WIDTH{1'b0}};    
            end 
        end 
    end 
    
    always @(posedge i_clk or negedge i_rstn)begin
        if(i_rstn == 1'b0)begin
            r_read_ready <= 1'b0;
        end 
        else begin
            if(i_control_mode == 1'b1)begin
                case(r_current_state) 
                    GET_DATA            :  r_read_ready  <= 1'b1;
                    READ_RESPONSE       :  r_read_ready  <= (i_read_valid ==1'b0) ? 1'b0 : 1'b1; 
                    default             :  r_read_ready  <= 1'b0;
                endcase
            end 
            else if (i_control_mode == 1'b0) r_read_ready <= del2_i_read_valid;
            else r_read_ready <= 1'b0;
        end 
    end 
    
    
    always @ (posedge i_clk or negedge i_rstn)begin
        if(i_rstn == 1'b0)begin
            del1_i_read_valid <= 1'b0;
            del2_i_read_valid <= 1'b0;
        end 
        else begin
            del1_i_read_valid <= i_read_valid;
            del2_i_read_valid <= del1_i_read_valid ;
        end 
    end 
    
    
    always @(posedge i_clk or negedge i_rstn)begin
        if(i_rstn == 1'b0)begin
            r_write_ready <= 1'b0;
        end 
        else begin
            if(i_control_mode == 1'b1)begin
                case(r_current_state) 
                    WRITE_OPERATION            :  r_write_ready  <= 1'b1;
                    default                    :  r_write_ready  <= 1'b0;
                endcase
            end 
            else if (i_control_mode == 1'b0) r_write_ready <= del1_i_write_valid;
            else r_write_ready <= 1'b0;
        end 
    end
    
    always @(posedge i_clk or negedge i_rstn)begin
        if(i_rstn == 1'b0)begin
            del1_i_write_valid <= 1'b0;
        end 
        else begin 
            del1_i_write_valid <= i_write_valid;
        end 
    end 
 
endmodule
