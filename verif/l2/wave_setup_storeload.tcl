# =====================================================================
#  xsim -gui setup for  tb_l2_ch1_in_storeload
#  Adds a curated signal set, runs the sim, leaves the GUI open.
# =====================================================================
set TB  /tb_l2_ch1_in_storeload
set FSM $TB/dut/u_cmd_decoder_SRAM_group_merge/u_cmd_decoder_channel_1_in_wrapper/u_cmd_decoder_channel_1_in

catch {
    add_wave_divider "clock / reset"
    add_wave $TB/i_clk
    add_wave $TB/i_rstb

    add_wave_divider "command in"
    add_wave $TB/i_command
    add_wave $TB/i_command_valid
    add_wave $TB/o_command_ready
    add_wave $TB/o_busy_channel_1_in

    add_wave_divider "ch1_in FSM"
    add_wave $FSM/current_state
    add_wave $FSM/o_load_busy
    add_wave $FSM/o_store_busy
    add_wave $FSM/r_noc_write_last_flag
    add_wave $FSM/r_sram_write_last_flag

    add_wave_divider "STEP1  STORE : NOC read  (fake NOC -> L2)"
    add_wave $FSM/o_noc_read_valid
    add_wave $FSM/o_noc_read_addr
    add_wave $TB/i_noc_read_ready_channel_1_in
    add_wave $TB/i_noc_read_response_channel_1_in
    add_wave $TB/i_noc_read_data_channel_1_in
    add_wave $FSM/o_noc_read_data_ready

    add_wave_divider "STEP1  STORE : SRAM write  (L2 internal)"
    add_wave $FSM/o_sram_write_valid
    add_wave $FSM/o_sram_write_addr
    add_wave $FSM/o_sram_write_data
    add_wave $FSM/i_sram_write_ready

    add_wave_divider "STEP2  LOAD : SRAM read  (L2 internal)"
    add_wave $FSM/o_sram_read_valid
    add_wave $FSM/o_sram_read_addr
    add_wave $FSM/i_sram_read_response
    add_wave $FSM/i_sram_read_data

    add_wave_divider "STEP2  LOAD : NOC write  (L2 -> fake NOC)"
    add_wave $FSM/o_noc_write_valid
    add_wave $FSM/o_noc_write_addr
    add_wave $FSM/o_noc_write_data
    add_wave $TB/i_noc_write_ready_channel_1_in
    add_wave $TB/i_noc_write_response_channel_1_in
}

# run up to just before $finish (sim ends ~775 ns) so the GUI stays open
run 760 ns
