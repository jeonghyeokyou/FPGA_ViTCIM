`timescale 1ns/1ps
// Pre-synthesis functional smoke test for l2_noc_fpga_top's BIST sequencer
// - NOT part of the synthesizable fileset, sim-only wrapper.
module tb_fpga_top_smoke;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;

    wire done, pass;
    wire [2:0] mismatch;

    l2_noc_fpga_top dut (
        .i_clk(clk), .i_rst_n(rst_n),
        .o_led_done(done), .o_led_pass(pass), .o_mismatch_count(mismatch)
    );

    initial begin
        $dumpfile("tb_fpga_top_smoke.vcd");
        $dumpvars(0, tb_fpga_top_smoke);
        repeat (10) @(posedge clk);
        rst_n = 1'b1;

        fork
            begin : wmon
                integer wb;
                wb = 0;
                forever begin
                    @(posedge clk);
                    if (dut.o_noc_write_valid_channel_1_in && dut.i_noc_write_ready_channel_1_in) begin
                        $display("[%0t]  NOC WR beat %0d  addr=0x%05h  data[31:0]=0x%08h  (state=%0d)",
                                 $time, wb, dut.o_noc_write_addr_channel_1_in,
                                 dut.o_noc_write_data_channel_1_in[31:0], dut.r_state);
                        wb = wb + 1;
                    end
                end
            end
        join_none

        fork
            begin : mon
                integer t;
                reg [3:0] prev_state = 4'hF;
                for (t = 0; t < 2000; t = t + 1) begin
                    @(posedge clk);
                    if (dut.r_state !== prev_state) begin
                        $display("[%0t] state -> %0d  command_ready=%b busy=%b command_valid=%b command=0x%016h",
                                 $time, dut.r_state, dut.o_command_ready, dut.o_busy_channel_1_in,
                                 dut.r_command_valid, dut.r_command);
                        prev_state = dut.r_state;
                    end
                end
            end
        join_none

        wait (done === 1'b1);
        repeat (5) @(posedge clk);
        $display("\n==================================================");
        $display("  FPGA BIST : done=%0d pass=%0d mismatch_count=%0d", done, pass, mismatch);
        $display("==================================================\n");
        $finish;
    end

    initial begin
        #2_000_000;
        $display("!! TIMEOUT !! BIST never finished (done stuck at 0) - inspect r_state");
        $finish;
    end
endmodule
