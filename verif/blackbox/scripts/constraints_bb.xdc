# =====================================================================
#  Blackbox system top (l2_noc_bb_bd_wrapper), OOC synthesis constraints
#  single clock aclk = PS pl_clk0 100 MHz in the Block Design
# =====================================================================
create_clock -period 10.000 -name aclk [get_ports aclk]
