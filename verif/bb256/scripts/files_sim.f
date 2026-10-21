# bb256 : full system (sim models). + tb/bb256_pkg.sv + TB
# paths are relative to bb256/scripts/work_*/ (the directory the .bat files run in)
# rtl/base  = LHJ/261020 copy (unchanged)
# rtl/fix   = fixed copies (FIFO_intf_bb : decl order ; ch1_wgt (C), ch2_in (E1~E4) : share2/rtl/fix ; ch2_wgt (C2) : new)
# rtl/bb256 = new / changed for the 256b blackbox_ip system
# L2
../../rtl/base/FIFO.sv
../../rtl/base/FIFO_modified.sv
../../rtl/base/skid_buffer.sv
../../rtl/base/sync_fifo_L2.sv
../../rtl/model_sim/ram_mimic.sv
../../rtl/base/sram_controller.sv
../../rtl/base/sram_read_ctrl_axi.sv
../../rtl/base/sram_write_ctrl_axi.sv
../../rtl/base/sramctrl_channel_0.sv
../../rtl/base/FIFO_interface_handshake.sv
../../rtl/base/FIFO_interface_on_fire.sv
../../rtl/base/FIFO_interface.sv
../../rtl/base/L2_FIFO_interface_handshake.sv
../../rtl/base/L2_FIFO_interface_on_fire.sv
../../rtl/base/L2_FIFO_interface.sv
../../rtl/base/L2_FIFO_interface_wrapper.sv
../../rtl/base/SRAM_group.sv
../../rtl/base/SRAM_group_decoder.sv
../../rtl/base/SRAM_group_merge.sv
../../rtl/base/SRAM_group_interface_channel_0.sv
../../rtl/base/CMD_dispatcher.sv
../../rtl/base/cmd_decoder_SRAM_group_read_interface.sv
../../rtl/base/cmd_decoder_SRAM_group_write_interface.sv
../../rtl/base/cmd_decoder_SRAM_group_interface.sv
../../rtl/base/cmd_decoder_channel_1_in.sv
../../rtl/base/cmd_decoder_channel_1_in_wrapper.sv
../../rtl/fix/cmd_decoder_channel_2_in.sv
../../rtl/base/cmd_decoder_channel_2_in_wrapper.sv
../../rtl/fix/cmd_decoder_channel_1_wgt.sv
../../rtl/base/cmd_decoder_channel_1_wgt_wrapper.sv
../../rtl/fix/cmd_decoder_channel_2_wgt.sv
../../rtl/base/cmd_decoder_channel_2_wgt_wrapper.sv
../../rtl/base/cmd_decoder_SRAM_group_merge.sv
../../rtl/base/TOP_L2_cache.sv
# NoC
../../rtl/base/noc_FIFO.v
../../rtl/base/noc_FIFO_modified.v
../../rtl/base/noc_FIFO_interface_handshake.v
../../rtl/base/noc_FIFO_interface_on_fire.v
../../rtl/base/noc_FIFO_interface_hsfix.v
../../rtl/base/noc_sram_controller.v
../../rtl/base/L1_FIFO_interface_on_fire.v
../../rtl/model_sim/sram_mimic.v
../../rtl/base/L1_FIFO_interface_handshake.v
../../rtl/base/L1_FIFO_interface.v
# L1 / weight memory / blackbox / PS interface
../../rtl/base/noc_ch1_in_adapter.sv
../../rtl/bb256/noc_ch1_wgt_adapter.sv
../../rtl/base/noc_L1_FIFO_intf.v
../../rtl/base/l1_sram.sv
../../rtl/base/l1_port_mux.sv
../../rtl/fix/FIFO_intf_bb.sv
../../rtl/bb256/blackbox_ip.sv
../../rtl/bb256/noc_wr_adapter.sv
../../rtl/bb256/blackbox_nl.sv
../../rtl/base/axi4_l2_ch0_bridge.sv
../../rtl/bb256/axi_lite_bb_ctrl.sv
../../rtl/base/axi_lite_l2_cmd_adapter.sv
../../rtl/bb256/l2_noc_bb_core.sv
../../rtl/bb256/l2_system_top.sv
../../rtl/base/l2_system_bd_wrapper.v
