`timescale 1ns/1ps 

module sramctrl_channel_0 #(
    parameter AXI_DATA_WIDTH  = 64,
    parameter SRAM_DATA_WIDTH = 64,
    parameter SRAM_ADDR_WIDTH = 20,
    parameter MOR_DEPTH       = 4
)(
    // clk & rstb signal
    input  logic                          i_clk,
    input  logic                          i_rstb,

    // AXI interface w/ sram_read_ctrl_axi
    // Read Address Channel (AR)
    input  logic [SRAM_ADDR_WIDTH-1:0]    i_araddr,
    input  logic                          i_arvalid,
    output logic                          o_arready,
    input  logic [7:0]                    i_arlen,
    // Read Data Channel (R)
    output logic [AXI_DATA_WIDTH-1:0]     o_rdata,
    output logic                          o_rvalid,
    input  logic                          i_rready,
    output logic                          o_rlast,

    // AXI interface w/ sram_write_ctrl_axi
    // Write Address Channel (AW)
    input  logic [SRAM_ADDR_WIDTH-1:0]    i_awaddr,
    input  logic                          i_awvalid,
    output logic                          o_awready,
    input  logic [7:0]                    i_awlen,
    // Write Data Channel (W)
    input  logic [AXI_DATA_WIDTH-1:0]     i_wdata,
    input  logic                          i_wvalid,
    input  logic                          i_wlast,
    output logic                          o_wready,
    // Write Response Channel (B)
    output logic                          o_bvalid,
    input  logic                          i_bready,
    
    // SRAM Interface
    // read operation
    // read addr
    output logic [SRAM_ADDR_WIDTH-1:0]        o_read_addr,
    output logic                              o_read_addr_valid,
    input  logic                              i_read_addr_ready,
    // read data
    input  logic [SRAM_DATA_WIDTH-1:0]        i_read_data,
    input  logic                              i_read_data_valid,
    output logic                              o_read_data_ready,
    // write operation
    // write data & addr
    output logic [SRAM_ADDR_WIDTH-1:0]    o_write_addr,
    output logic [SRAM_DATA_WIDTH-1:0]    o_write_data,
    output logic                          o_write_valid,
    input  logic                          i_write_ready
);

    // Read Controller wire output
    wire                       w_arready;
    wire [AXI_DATA_WIDTH-1:0]  w_rdata;
    wire                       w_rvalid;
    wire                       w_rlast;
    wire [SRAM_ADDR_WIDTH-1:0] w_read_addr;
    wire                       w_read_addr_valid;
    wire                       w_read_data_ready;
    wire                       w_read_busy;

    // Write Controller wire output
    wire                       w_awready;
    wire                       w_wready;
    wire [SRAM_ADDR_WIDTH-1:0] w_write_addr;
    wire [SRAM_DATA_WIDTH-1:0] w_write_data;
    wire                       w_write_valid;
    wire                       w_write_busy;
    wire                       w_bvalid;

    //
    wire w_arvalid;
    wire w_awvalid;
    wire w_wvalid;

    assign w_arvalid = (w_write_busy) ? 1'b0 : i_arvalid;
    assign w_awvalid = (w_read_busy) ? 1'b0 : i_awvalid;
    assign w_wvalid  = (w_read_busy) ? 1'b0 : i_wvalid;

    // sram interface output definition
    assign o_arready = (w_write_busy) ? 1'b0 : w_arready;
    assign o_rdata   =  w_rdata;
    assign o_rvalid  =  w_rvalid;
    assign o_rlast   =  w_rlast;
    
    assign o_awready = (w_read_busy)  ? 1'b0 : w_awready;
    assign o_wready  = (w_read_busy)  ? 1'b0 : w_wready;

    assign o_read_addr       = w_read_addr;
    assign o_read_addr_valid = w_read_addr_valid;
    assign o_read_data_ready = w_read_data_ready;

    assign o_write_addr      = w_write_addr;
    assign o_write_data      = w_write_data;
    assign o_write_valid     = w_write_valid;
    assign o_bvalid          = w_bvalid;

    // instance definition
    // Read Controller
    sram_read_ctrl_axi #(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .SRAM_DATA_WIDTH(SRAM_DATA_WIDTH),
        .SRAM_ADDR_WIDTH(SRAM_ADDR_WIDTH),
        .FIFO_DEPTH(8),
        .MOR_DEPTH(MOR_DEPTH)
    ) u_read_ctrl (
        .i_clk      (i_clk),
        .i_rstb     (i_rstb),
        .i_araddr   (i_araddr), 
        .i_arvalid  (w_arvalid), 
        .o_arready  (w_arready), 
        .i_arlen    (i_arlen),
        .o_rdata    (w_rdata),
        .o_rvalid   (w_rvalid), 
        .i_rready   (i_rready),
        .o_rlast    (w_rlast),
        .o_a        (w_read_addr),
        .o_a_valid  (w_read_addr_valid),
        .i_a_ready  (i_read_addr_ready),
        .i_q        (i_read_data),
        .i_q_valid  (i_read_data_valid),
        .o_q_ready  (w_read_data_ready),
        .o_read_busy(w_read_busy)
    );

    // Write Controller
    sram_write_ctrl_axi #(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .SRAM_DATA_WIDTH(SRAM_DATA_WIDTH), 
        .SRAM_ADDR_WIDTH(SRAM_ADDR_WIDTH),
        .MOR_DEPTH(MOR_DEPTH)
    ) u_write_ctrl (
        .i_clk       (i_clk),
        .i_rstb      (i_rstb),
        .i_awaddr    (i_awaddr), 
        .i_awvalid   (w_awvalid), 
        .o_awready   (w_awready), 
        .i_awlen     (i_awlen),
        .i_wdata     (i_wdata),
        .i_wvalid    (w_wvalid), 
        .i_wlast     (i_wlast),
        .o_wready    (w_wready),
        .o_bvalid    (w_bvalid),
        .i_bready    (i_bready),
        .o_a         (w_write_addr),
        .o_q         (w_write_data),
        .o_q_valid   (w_write_valid),
        .i_q_ready   (i_write_ready),
        .o_write_busy(w_write_busy)
    );

endmodule
