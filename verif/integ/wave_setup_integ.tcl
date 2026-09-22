# =====================================================================
#  xsim -gui setup for tb_l2_noc_ch1_in  (Phase 2 STEP 3)
#  Adds a curated signal set grouped by stage, runs to just before
#  $finish, leaves the GUI open.
# =====================================================================
set TB   /tb_l2_noc_ch1_in
set FSM  $TB/dut_l2/u_cmd_decoder_SRAM_group_merge/u_cmd_decoder_channel_1_in_wrapper/u_cmd_decoder_channel_1_in
set ADPT $TB/u_adapter
set NOC  $TB/dut_noc

catch {
    add_wave_divider "clock / reset / command"
    add_wave $TB/i_clk
    add_wave $TB/i_rstb
    add_wave $TB/i_command
    add_wave $TB/i_command_valid
    add_wave $TB/o_command_ready
    add_wave $TB/o_busy_channel_1_in

    add_wave_divider "L2 ch1_in FSM"
    add_wave $FSM/current_state
    add_wave $FSM/o_load_busy
    add_wave $FSM/o_store_busy

    add_wave_divider "STEP A STORE : L2 NOC-read path (L1 -> L2 SRAM)"
    add_wave $TB/o_noc_read_valid_channel_1_in
    add_wave $TB/o_noc_read_addr_channel_1_in
    add_wave $TB/i_noc_read_ready_channel_1_in
    add_wave $TB/i_noc_read_response_channel_1_in
    add_wave $TB/i_noc_read_data_channel_1_in
    add_wave $FSM/o_sram_write_valid
    add_wave $FSM/o_sram_write_addr
    add_wave $FSM/o_sram_write_data

    add_wave_divider "STEP B LOAD : L2 NOC-write path (L2 SRAM -> L1)"
    add_wave $FSM/o_sram_read_valid
    add_wave $FSM/o_sram_read_addr
    add_wave $FSM/i_sram_read_data
    add_wave $TB/o_noc_write_valid_channel_1_in
    add_wave $TB/o_noc_write_addr_channel_1_in
    add_wave $TB/o_noc_write_data_channel_1_in
    add_wave $TB/i_noc_write_ready_channel_1_in
    add_wave $TB/i_noc_write_response_channel_1_in

    add_wave_divider "noc_ch1_in_adapter  (STEP 2)"
    add_wave $ADPT/m_write_valid
    add_wave $ADPT/m_write_addr
    add_wave $ADPT/m_write_data
    add_wave $ADPT/m_read_valid
    add_wave $ADPT/m_read_addr
    add_wave $ADPT/m_read_data
    add_wave $ADPT/m_control_mode

    add_wave_divider "FIFO_intf -> L1_Cache_Mimic  (NOC, renamed STEP 1)"
    add_wave $NOC/w_write_valid
    add_wave $NOC/w_write_addr
    add_wave $NOC/w_write_data
    add_wave $NOC/UL1_Cache_Mimic/w_sram_enb
    add_wave $NOC/UL1_Cache_Mimic/w_sram_web
    add_wave $NOC/UL1_Cache_Mimic/w_sram_addr
    add_wave $NOC/UL1_Cache_Mimic/w_sram_din
}
run 900 ns
