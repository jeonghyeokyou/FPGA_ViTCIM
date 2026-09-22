# =====================================================================
#  Creates a Vivado GUI project for Phase-1 L2 ch1_in simulation.
#  Usage (from a cmd window):
#     cd C:\RTL_YJH\L2_verification\verif\l2
#     "C:\Xilinx\Vivado\2024.2\bin\vivado.bat" -mode gui -source make_vivado_project.tcl
#  It builds the project, adds all sources, sets the sim top, and
#  leaves Vivado open so you can click "Run Simulation".
# =====================================================================

set proj_name  l2_ch1_sim
set proj_dir   [file normalize [file dirname [info script]]/vivado]
set rtl_dir    [file normalize [file dirname [info script]]/../../rtl/L2_260901]
set tb_file    [file normalize [file dirname [info script]]/tb/tb_l2_ch1_in.sv]

# 1. create project (no board / generic part is fine for pure simulation)
create_project $proj_name $proj_dir -part xc7a35tcpg236-1 -force

# 2. add all L2 RTL (.sv) as design sources
add_files -norecurse [glob $rtl_dir/*.sv]

# 3. add the testbench as a SIMULATION-only source
add_files -fileset sim_1 -norecurse $tb_file

# 4. tell Vivado which module is the top for simulation
set_property top tb_l2_ch1_in [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

# 5. keep every signal visible in the waveform, run 5 us automatically
set_property -name {xsim.elaborate.debug_level} -value {all} -objects [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {5us}      -objects [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "======================================================================"
puts "  Project ready:  $proj_dir/$proj_name.xpr"
puts "  Now in the Vivado GUI:  Flow Navigator > SIMULATION > Run Simulation"
puts "                          > Run Behavioral Simulation"
puts "======================================================================"
