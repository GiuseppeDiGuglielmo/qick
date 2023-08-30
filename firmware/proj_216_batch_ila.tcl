source proj_216.tcl

# === BEGIN: NN ===============================================================
# Open block diagram
open_bd_design {${proj_dir}/top_216.srcs/sources_1/bd/d_1/d_1.bd}

# Set neural network IP path
set OTHER_IP_PATH "[file normalize ${orig_proj_dir}/ip]"
set NN_IP_PATH "[file normalize ${orig_proj_dir}/../../models_HLS/fcnn/ioParallel/modelv3/fcnn_ioParallel_trigger_rf8]"
set_property ip_repo_paths "${OTHER_IP_PATH} ${NN_IP_PATH}" [current_project]
update_ip_catalog

# Add NN IPs
create_bd_cell -type ip -vlnv xilinx.com:hls:myproject_axi:1.0 myproject_axi_0
set_property name NN_0 [get_bd_cells myproject_axi_0]

# Add AXI-stream broadcaster IPs
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_broadcaster:1.1 axis_broadcaster_0

# Wire broadcaster, average block, NN, readout IPs
delete_bd_objs [get_bd_intf_nets axis_readout_v2_0_m1_axis]
connect_bd_intf_net [get_bd_intf_pins axis_readout_v2_0/m1_axis] [get_bd_intf_pins axis_broadcaster_0/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins axis_broadcaster_0/M00_AXIS] [get_bd_intf_pins axis_avg_buffer_0/s_axis]
connect_bd_intf_net [get_bd_intf_pins axis_broadcaster_0/M01_AXIS] [get_bd_intf_pins NN_0/in_r]

# Connect NN IP triggers
connect_bd_net [get_bd_pins NN_0/trigger] [get_bd_pins vect2bits_16_0/dout14]

# Connect clock and reset signals
apply_bd_automation -rule xilinx.com:bd_rule:clkrst -config { Clk {/usp_rf_data_converter_0/clk_adc2 (307 MHz)} Freq {100} Ref_Clk0 {} Ref_Clk1 {} Ref_Clk2 {}}  [get_bd_pins axis_broadcaster_0/aclk]

# Connect AXI-stream terminators
create_bd_cell -type ip -vlnv user.org:user:axis_terminator:1.0 axis_terminator_2
set_property name NN_terminator_0 [get_bd_cells axis_terminator_2]
set_property -dict [list CONFIG.DATA_WIDTH {32}] [get_bd_cells NN_terminator_0]
connect_bd_intf_net [get_bd_intf_pins NN_0/out_r] [get_bd_intf_pins NN_terminator_0/s_axis]
apply_bd_automation -rule xilinx.com:bd_rule:clkrst -config { Clk {/usp_rf_data_converter_0/clk_adc2 (307 MHz)} Freq {100} Ref_Clk0 {} Ref_Clk1 {} Ref_Clk2 {}}  [get_bd_pins NN_terminator_0/s_axis_aclk]

# Add ILAs for debugging (NN 0)
set_property HDL_ATTRIBUTE.DEBUG true [get_bd_nets {vect2bits_16_0_dout14 }]
set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {axis_broadcaster_0_M01_AXIS NN_0_out_r}]
apply_bd_automation -rule xilinx.com:bd_rule:debug -dict [list \
    [get_bd_intf_nets axis_broadcaster_0_M01_AXIS] {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" APC_EN "0" } \
    [get_bd_intf_nets NN_0_out_r] {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" APC_EN "0" } \
]
set_property -dict [list CONFIG.C_BRAM_CNT {1} CONFIG.C_MON_TYPE {MIX}] [get_bd_cells system_ila_0]
connect_bd_net [get_bd_pins system_ila_0/probe0] [get_bd_pins vect2bits_16_0/dout14]

validate_bd_design
# === END: NN ===============================================================

#reset_run impl_1
#reset_run synth_1
#launch_runs impl_1 -to_step write_bitstream -jobs 20
#wait_on_run -timeout 360 impl_1
#
#open_run impl_1
#report_utilization -file util_216.rpt -hierarchical -hierarchical_percentages
