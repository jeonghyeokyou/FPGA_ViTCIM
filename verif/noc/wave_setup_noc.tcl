# xsim -gui setup for tb_noc_fifo_intf
set TB /tb_noc_fifo_intf
catch {
    add_wave_divider "clock / reset / mode"
    add_wave $TB/clk
    add_wave $TB/rstb
    add_wave $TB/i_control_mode

    add_wave_divider "master WRITE port"
    add_wave $TB/i_write_valid
    add_wave $TB/i_write_addr
    add_wave $TB/i_write_data
    add_wave $TB/o_write_ready
    add_wave $TB/o_FIFO_write_ready

    add_wave_divider "master READ port"
    add_wave $TB/i_read_valid
    add_wave $TB/i_read_addr
    add_wave $TB/o_read_ready
    add_wave $TB/o_read_data
    add_wave $TB/o_FIFO_read_ready
    add_wave $TB/i_data_fifo_ready

    add_wave_divider "L1 memory interface (inside FIFO_intf)"
    add_wave $TB/dut/w_write_valid
    add_wave $TB/dut/w_write_addr
    add_wave $TB/dut/w_write_data
    add_wave $TB/dut/w_read_valid
    add_wave $TB/dut/w_read_addr
    add_wave $TB/dut/w_read_data
    add_wave $TB/dut/w_control_mode

    add_wave_divider "L1_Cache_Mimic sram_controller"
    add_wave $TB/dut/UL1_Cache_Mimic/Usram_controller/r_current_state
    add_wave $TB/dut/UL1_Cache_Mimic/w_sram_enb
    add_wave $TB/dut/UL1_Cache_Mimic/w_sram_web
    add_wave $TB/dut/UL1_Cache_Mimic/w_sram_addr
    add_wave $TB/dut/UL1_Cache_Mimic/w_sram_din
    add_wave $TB/dut/UL1_Cache_Mimic/w_sram_dout_Merge
}
run 1300 ns
