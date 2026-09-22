`timescale 1ns/1ps
// ===================================================================
//  NOC Phase 1 (STEP 0)  -  FIFO_intf  standalone functional sim
//
//  DUT = FIFO_intf  (FIFO_interface + L1_FIFO_interface + L1_Cache_Mimic)
//  Drive the master port directly:
//    - write 5 beats  (addr 0..4 , data 0xB0B0_0000+k)
//    - read  them back and compare
//  control mode = 0  (fire-on-valid)   <- same mode L2 burst path uses
//
//  Uses the sim-fixed RTL (noc_files_fix.f):
//    fix\FIFO_intf.v      : drop bogus .MEMORY_BITWIDTH , tie i_pe_busy=0
//    fix\sram_mimic.v     : o_dout  input->output
//    fix\L1_Cache_Mimic.v : o_read_data  input->output
// ===================================================================
module tb_noc_fifo_intf;

    localparam ADDR_DEPTH      = 1600;
    localparam DATA_WIDTH      = 512;
    localparam MEMORY_BITWIDTH = 128;
    localparam FIFO_DEPTH      = 8;
    localparam INPUT_DELAY     = 3;
    localparam ADDR_BW         = $clog2(ADDR_DEPTH);   // = 11
    localparam N_BEATS         = 5;

    localparam CLKP = 10;
    logic clk  = 1'b0;
    logic rstb = 1'b0;
    always #(CLKP/2) clk = ~clk;

    // ---- DUT master-port signals -----------------------------------
    logic                   i_read_valid   = 1'b0;
    wire                    o_read_ready;
    logic [ADDR_BW-1:0]     i_read_addr    = '0;
    wire  [DATA_WIDTH-1:0]  o_read_data;

    logic                   i_write_valid  = 1'b0;
    wire                    o_write_ready;
    logic [ADDR_BW-1:0]     i_write_addr   = '0;
    logic [DATA_WIDTH-1:0]  i_write_data   = '0;

    logic                   i_control_mode = 1'b0;   // fire-on-valid
    wire                    o_FIFO_read_ready;
    wire                    o_FIFO_write_ready;
    logic                   i_data_fifo_ready = 1'b0;

    FIFO_intf #(
        .ADDR_DEPTH(ADDR_DEPTH), .DATA_WIDTH(DATA_WIDTH),
        .MEMORY_BITWIDTH(MEMORY_BITWIDTH), .FIFO_DEPTH(FIFO_DEPTH),
        .INPUT_DELAY(INPUT_DELAY)
    ) dut (
        .clk(clk), .rstb(rstb),
        .i_read_valid(i_read_valid),   .o_read_ready(o_read_ready),
        .i_read_addr(i_read_addr),     .o_read_data(o_read_data),
        .i_write_valid(i_write_valid), .o_write_ready(o_write_ready),
        .i_write_addr(i_write_addr),   .i_write_data(i_write_data),
        .i_control_mode(i_control_mode),
        .o_FIFO_read_ready(o_FIFO_read_ready),
        .o_FIFO_write_ready(o_FIFO_write_ready),
        .i_data_fifo_ready(i_data_fifo_ready)
    );

    function automatic [DATA_WIDTH-1:0] pat(input int k);
        pat = { {(DATA_WIDTH-32){1'b0}}, (32'hB0B0_0000 + k) };
    endfunction

    integer errors = 0;

    // -----------------------------------------------------------------
    task automatic do_write(input [ADDR_BW-1:0] a, input [DATA_WIDTH-1:0] d);
        // wait until the interface can accept a new request
        @(negedge clk);
        while (!o_FIFO_write_ready) @(negedge clk);
        i_write_addr  = a;
        i_write_data  = d;
        i_write_valid = 1'b1;
        @(negedge clk);
        i_write_valid = 1'b0;
        $display("[%0t]  WR  addr=%0d  data=0x%08h", $time, a, d[31:0]);
    endtask

    task automatic do_read(input [ADDR_BW-1:0] a, input [DATA_WIDTH-1:0] expect_d);
        @(negedge clk);
        while (!o_FIFO_read_ready) @(negedge clk);
        i_read_addr  = a;
        i_read_valid = 1'b1;
        @(negedge clk);
        i_read_valid = 1'b0;
        // wait for the read data to come back
        fork : wait_rd
            begin
                integer to;
                for (to = 0; to < 200; to = to + 1) begin
                    @(posedge clk);
                    if (o_read_ready) begin
                        if (o_read_data === expect_d)
                            $display("[%0t]  RD  addr=%0d  data=0x%08h   OK", $time, a, o_read_data[31:0]);
                        else begin
                            $display("[%0t]  RD  addr=%0d  MISMATCH exp=0x%08h got=0x%h",
                                     $time, a, expect_d[31:0], o_read_data);
                            errors = errors + 1;
                        end
                        disable wait_rd;
                    end
                end
                $display("[%0t]  RD  addr=%0d  TIMEOUT (o_read_ready never asserted)", $time, a);
                errors = errors + 1;
            end
        join
    endtask

    // -----------------------------------------------------------------
    integer k;
    initial begin
        $dumpfile("tb_noc_fifo_intf.vcd");
        $dumpvars(0, tb_noc_fifo_intf);

        rstb = 1'b0;
        repeat (10) @(posedge clk);
        rstb = 1'b1;
        repeat (5) @(posedge clk);

        i_data_fifo_ready = 1'b1;   // master is always ready to take read data

        $display("\n---------------- WRITE phase ----------------");
        for (k = 0; k < N_BEATS; k = k + 1)
            do_write(k[ADDR_BW-1:0], pat(k));

        repeat (40) @(posedge clk);   // let the write pipeline drain

        $display("\n---- L1_Cache_Mimic bank0 memory after writes ----");
        for (k = 0; k < N_BEATS; k = k + 1)
            $display("   mem[%0d] = 0x%032h", k, dut.UL1_Cache_Mimic.Usram_mimic_0.mem[k]);

        $display("\n---------------- READ phase ----------------");
        for (k = 0; k < N_BEATS; k = k + 1)
            do_read(k[ADDR_BW-1:0], pat(k));

        repeat (20) @(posedge clk);
        $display("\n==================================================");
        $display("  NOC standalone : %s   (errors = %0d)",
                 (errors==0) ? "PASS" : "CHECK", errors);
        $display("==================================================\n");
        $finish;
    end

    initial begin
        #500000;
        $display("!! GLOBAL TIMEOUT !!");
        $finish;
    end

endmodule
