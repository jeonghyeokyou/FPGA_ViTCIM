`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// Project      : L1 Cache Mimic
// Module       : L1_Cache_Mimic Code
// Author       : ParkSunJong
// Description  : SRAM Controller < Version  0.0>  +  SRAM Controller < Version  0.0>
// Version      : 2025-06-18 <Basic Version>
// -----------------------------------------------------------------------------
//  Copy for the RENAMED integration build (original: rtl/NOC_260902/L1_Cache_Mimic.v)
//  Fix (same as verif/noc/fix/L1_Cache_Mimic.v) : `o_read_data` input -> output.
//  Fix (integration-only) : instantiates noc_sram_controller instead of
//  sram_controller, since L2_260901/sram_controller.sv collides with the plain
//  name in a combined compile. Module name unchanged (no collision itself).
// -----------------------------------------------------------------------------

module L1_Cache_Mimic#(
    parameter ADDR_DEPTH         = 1024,
    parameter DATA_WIDTH         = 512,
    parameter MEMORY_BITWIDTH    = 128,
    localparam ADDR_BW    = $clog2(ADDR_DEPTH)
)(
    // -------------------------------------------------------------------------
    // Global Signals
    input  wire                        i_clk,
    input  wire                        i_rstn,
    // -------------------------------------------------------------------------
    // Control Mode
    // 1: Use handshaking (valid & ready)
    // 0: Fire-on-valid mode
    input  wire                        i_control_mode,
    // -------------------------------------------------------------------------
    // Read Interface
    input  wire                        i_read_valid,
    output wire                        o_read_ready,
    input  wire  [ADDR_BW    -1 : 0]   i_read_addr,
    output wire  [DATA_WIDTH -1 : 0]   o_read_data,
    // -------------------------------------------------------------------------
    // Write Interface
    input  wire                        i_write_valid,
    output wire                        o_write_ready,
    input  wire  [ADDR_BW    -1 : 0]   i_write_addr,
    input  wire  [DATA_WIDTH -1 : 0]   i_write_data
);


    // -------------------------------------------------------------------------
    // Internal Wire List
    // -------------------------------------------------------------------------
    wire [ADDR_BW-1 : 0]       w_sram_addr;
    wire [DATA_WIDTH-1 : 0]    w_sram_din;
    wire [DATA_WIDTH-1 : 0]    w_sram_dout_Merge;
    wire [MEMORY_BITWIDTH-1:0] w_sram_dout_0;
    wire [MEMORY_BITWIDTH-1:0] w_sram_dout_1;
    wire [MEMORY_BITWIDTH-1:0] w_sram_dout_2;
    wire [MEMORY_BITWIDTH-1:0] w_sram_dout_3;
    wire                       w_sram_web;         //active low
    wire                       w_sram_enb;         //active low
    // -------------------------------------------------------------------------
    // Bit Assignments
    // -------------------------------------------------------------------------
    assign w_sram_dout_Merge = {w_sram_dout_3,w_sram_dout_2,w_sram_dout_1,w_sram_dout_0};
    //===========================================================================
    // L1 Cache Array Bank 0
    //============================================================================
    noc_sram_controller # (
        .ADDR_DEPTH         (ADDR_DEPTH          ),
        .DATA_WIDTH         (DATA_WIDTH          )
    )
    Usram_controller (
        // Clock / Reset
        .i_clk              (i_clk               ),
        .i_rstn             (i_rstn              ),

        // Control Interface
        .i_control_mode     (i_control_mode      ),
        .i_read_valid       (i_read_valid        ),
        .i_write_valid      (i_write_valid       ),
        .o_read_ready       (o_read_ready        ),
        .o_write_ready      (o_write_ready       ),

        // Read/Write Interface
        .i_read_addr        (i_read_addr         ),
        .i_write_addr       (i_write_addr        ),
        .i_write_data       (i_write_data        ),
        .o_read_data        (o_read_data         ),

        // SRAM Interface
        .o_sram_ceb              (w_sram_enb          ),
        .o_sram_web              (w_sram_web          ),
        .o_sram_addr             (w_sram_addr         ),
        .o_sram_din              (w_sram_din          ),
        .i_sram_dout             (w_sram_dout_Merge         )
    );


    //========================================================
    // L1 Cache Array Bank 0
    //========================================================
    sram_mimic    #(
        .BIT_WIDTH          (MEMORY_BITWIDTH     ),
        .ADDRESS_ROW        (ADDR_DEPTH          )
    )Usram_mimic_0 (
        // Clock / Reset
        .i_clk              (i_clk                                          ),
        .i_rstn             (i_rstn                                         ),

        //  Input List
        .i_web              (w_sram_web                                     ),
        .i_ceb              (w_sram_enb                                     ),
        .i_addr             (w_sram_addr                                    ),
        .i_din              (w_sram_din[0*MEMORY_BITWIDTH+:MEMORY_BITWIDTH] ),

        //Output List
        .o_dout             (w_sram_dout_0         )
    );

    //========================================================
    // L1 Cache Array Bank 1
    //========================================================
    sram_mimic    #(
        .BIT_WIDTH          (MEMORY_BITWIDTH     ),
        .ADDRESS_ROW        (ADDR_DEPTH          )
    )Usram_mimic_1 (
        // Clock / Reset
        .i_clk              (i_clk                                          ),
        .i_rstn             (i_rstn                                         ),

        //  Input List
        .i_web              (w_sram_web                                     ),
        .i_ceb              (w_sram_enb                                     ),
        .i_addr             (w_sram_addr                                    ),
        .i_din              (w_sram_din[1*MEMORY_BITWIDTH+:MEMORY_BITWIDTH] ),

        //Output List
        .o_dout             (w_sram_dout_1         )
    );

    //========================================================
    // L1 Cache Array Bank 2
    //========================================================
    sram_mimic    #(
        .BIT_WIDTH          (MEMORY_BITWIDTH     ),
        .ADDRESS_ROW        (ADDR_DEPTH          )
    )Usram_mimic_2 (
        // Clock / Reset
        .i_clk              (i_clk                                          ),
        .i_rstn             (i_rstn                                         ),

        //  Input List
        .i_web              (w_sram_web                                     ),
        .i_ceb              (w_sram_enb                                     ),
        .i_addr             (w_sram_addr                                    ),
        .i_din              (w_sram_din[2*MEMORY_BITWIDTH+:MEMORY_BITWIDTH] ),

        //Output List
        .o_dout             (w_sram_dout_2         )
    );

    //========================================================
    // L1 Cache Array Bank 3
    //========================================================
    sram_mimic    #(
        .BIT_WIDTH          (MEMORY_BITWIDTH     ),
        .ADDRESS_ROW        (ADDR_DEPTH          )
    )Usram_mimic_3 (
        // Clock / Reset
        .i_clk              (i_clk                                          ),
        .i_rstn             (i_rstn                                         ),

        //  Input List
        .i_web              (w_sram_web                                     ),
        .i_ceb              (w_sram_enb                                     ),
        .i_addr             (w_sram_addr                                    ),
        .i_din              (w_sram_din[3*MEMORY_BITWIDTH+:MEMORY_BITWIDTH] ),

        //Output List
        .o_dout             (w_sram_dout_3         )
    );

endmodule
