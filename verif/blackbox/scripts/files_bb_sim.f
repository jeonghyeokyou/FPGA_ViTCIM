# ============================================================
# FIXES : verif/blackbox/rtl/fix/*  (FINDING_handshake_mode.md) + rtl/l1_port_mux.sv (FINDING_busy_fall_before_l1_write.md)
# Blackbox sim file list (Phase 2/3) : xvlog -sv -f files_bb_sim.f  (+ tb/bb_pkg.sv + TB)
#  L2  : rtl/L2_260901 + verif/l2/fix/ram_mimic.sv (bug #1 fix)
#  NOC : verif/noc/rename (bug #6 fix, noc_ prefix) + sim sram_mimic
#  BB  : verif/blackbox/rtl
# ============================================================
C:/RTL_YJH/L2_verification/rtl/L2_260901/FIFO.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/FIFO_modified.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/skid_buffer.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/sync_fifo_L2.sv
C:/RTL_YJH/L2_verification/verif/l2/fix/ram_mimic.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/sram_controller.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/sram_read_ctrl_axi.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/sram_write_ctrl_axi.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/sramctrl_channel_0.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/FIFO_interface_handshake.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/FIFO_interface_on_fire.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/FIFO_interface.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/L2_FIFO_interface_handshake.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/L2_FIFO_interface_on_fire.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/L2_FIFO_interface.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/L2_FIFO_interface_wrapper.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/SRAM_group.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/SRAM_group_decoder.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/SRAM_group_merge.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/SRAM_group_interface_channel_0.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/CMD_dispatcher.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/cmd_decoder_SRAM_group_read_interface.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/cmd_decoder_SRAM_group_write_interface.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/cmd_decoder_SRAM_group_interface.sv
C:/RTL_YJH/L2_verification/verif/blackbox/rtl/fix/cmd_decoder_channel_1_in.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/cmd_decoder_channel_1_in_wrapper.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/cmd_decoder_channel_2_in.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/cmd_decoder_channel_2_in_wrapper.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/cmd_decoder_channel_1_wgt.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/cmd_decoder_channel_1_wgt_wrapper.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/cmd_decoder_channel_2_wgt.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/cmd_decoder_channel_2_wgt_wrapper.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/cmd_decoder_SRAM_group_merge.sv
C:/RTL_YJH/L2_verification/rtl/L2_260901/TOP_L2_cache.sv
C:/RTL_YJH/L2_verification/verif/noc/rename/noc_FIFO.v
C:/RTL_YJH/L2_verification/verif/noc/rename/noc_FIFO_modified.v
C:/RTL_YJH/L2_verification/verif/noc/rename/noc_FIFO_interface_handshake.v
C:/RTL_YJH/L2_verification/verif/noc/rename/noc_FIFO_interface_on_fire.v
C:/RTL_YJH/L2_verification/verif/blackbox/rtl/fix/noc_FIFO_interface_hsfix.v
C:/RTL_YJH/L2_verification/verif/noc/rename/noc_sram_controller.v
C:/RTL_YJH/L2_verification/verif/noc/rename/L1_FIFO_interface_on_fire.v
C:/RTL_YJH/L2_verification/verif/noc/fix/sram_mimic.v
C:/RTL_YJH/L2_verification/rtl/NOC_260902/L1_FIFO_interface_handshake.v
C:/RTL_YJH/L2_verification/rtl/NOC_260902/L1_FIFO_interface.v
C:/RTL_YJH/L2_verification/verif/integ/noc_ch1_in_adapter.sv
C:/RTL_YJH/L2_verification/verif/blackbox/rtl/noc_L1_FIFO_intf.v
C:/RTL_YJH/L2_verification/verif/blackbox/rtl/l1_sram.sv
C:/RTL_YJH/L2_verification/verif/blackbox/rtl/l1_port_mux.sv
C:/RTL_YJH/L2_verification/verif/blackbox/rtl/FIFO_intf_bb.sv
C:/RTL_YJH/L2_verification/verif/blackbox/rtl/blackbox_pe.sv
# ---- Phase 3 : PS interface ----
C:/RTL_YJH/L2_verification/LHJ/axi4_l2_ch0_bridge.sv
C:/RTL_YJH/L2_verification/verif/blackbox/rtl/axi_lite_ctrl.sv
C:/RTL_YJH/L2_verification/verif/blackbox/rtl/l2_noc_bb_top.sv
C:/RTL_YJH/L2_verification/verif/blackbox/rtl/l2_noc_bb_bd_wrapper.v
