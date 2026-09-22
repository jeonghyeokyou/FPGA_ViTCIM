# ============================================================
# NOC_260902 RTL file list for L2+NOC INTEGRATION (STEP 1 renamed)
#   top: FIFO_intf   (same module name, safe to combine with L2 top)
#
# Six modules that collide with L2_260901 (same name, different body)
# are renamed with a noc_ prefix in verif/noc/rename/:
#   FIFO -> noc_FIFO, FIFO_modified -> noc_FIFO_modified,
#   FIFO_interface_handshake -> noc_FIFO_interface_handshake,
#   FIFO_interface_on_fire -> noc_FIFO_interface_on_fire,
#   FIFO_interface -> noc_FIFO_interface, sram_controller -> noc_sram_controller.
# L1_FIFO_interface_on_fire.v / FIFO_intf.v / L1_Cache_Mimic.v are copies whose
# only change is retargeting instances to the renamed modules (+ the STEP 0
# sim-model fixes: o_dout / o_read_data direction, dropped .MEMORY_BITWIDTH,
# i_pe_busy tied 0). L1_FIFO_interface.v / L1_FIFO_interface_handshake.v have
# no colliding instances, so they are used straight from rtl/NOC_260902/.
# ============================================================
C:/RTL_YJH/L2_verification/verif/noc/rename/noc_FIFO.v
C:/RTL_YJH/L2_verification/verif/noc/rename/noc_FIFO_modified.v
C:/RTL_YJH/L2_verification/verif/noc/rename/noc_FIFO_interface_handshake.v
C:/RTL_YJH/L2_verification/verif/noc/rename/noc_FIFO_interface_on_fire.v
C:/RTL_YJH/L2_verification/verif/noc/rename/noc_FIFO_interface.v
C:/RTL_YJH/L2_verification/verif/noc/rename/noc_sram_controller.v
C:/RTL_YJH/L2_verification/verif/noc/rename/L1_FIFO_interface_on_fire.v
C:/RTL_YJH/L2_verification/verif/noc/fix/sram_mimic.v
C:/RTL_YJH/L2_verification/verif/noc/rename/L1_Cache_Mimic.v
C:/RTL_YJH/L2_verification/rtl/NOC_260902/L1_FIFO_interface_handshake.v
C:/RTL_YJH/L2_verification/rtl/NOC_260902/L1_FIFO_interface.v
C:/RTL_YJH/L2_verification/verif/noc/rename/FIFO_intf.v
