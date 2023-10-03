source proj_216.tcl

# === BEGIN: NN ===============================================================
# Open block diagram
open_bd_design {${proj_dir}/top_216.srcs/sources_1/bd/d_1/d_1.bd}

# Set neural network IP path
set OTHER_IP_PATH "[file normalize ${orig_proj_dir}/ip]"
#set NN_IP_PATH "[file normalize ${orig_proj_dir}/../../models_HLS/fcnn/ioParallel/modelv3/fcnn_ioParallel_trigger_rf8]"
set NN_IP_PATH "[file normalize ${orig_proj_dir}/../../models_HLS/fcnn/ioParallel/dummy/dummy_model]"
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
connect_bd_intf_net [get_bd_intf_pins axis_broadcaster_0/M00_AXIS] [get_bd_intf_pins NN_0/in_r]
connect_bd_intf_net [get_bd_intf_pins axis_broadcaster_0/M01_AXIS] [get_bd_intf_pins axis_avg_buffer_0/s_axis]

# Connect NN IP triggers
connect_bd_net [get_bd_pins NN_0/trigger] [get_bd_pins vect2bits_16_0/dout14]

# Connect clock and reset signals
apply_bd_automation -rule xilinx.com:bd_rule:clkrst -config { Clk {/usp_rf_data_converter_0/clk_adc2 (307 MHz)} Freq {100} Ref_Clk0 {} Ref_Clk1 {} Ref_Clk2 {}}  [get_bd_pins axis_broadcaster_0/aclk]

# Add two-port BRAMs (NN 0)
create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 blk_mem_gen_0
set_property -dict [list \
    CONFIG.Memory_Type {True_Dual_Port_RAM} \
    CONFIG.Enable_B {Use_ENB_Pin} \
    CONFIG.Use_RSTB_Pin {true} \
    CONFIG.Port_B_Clock {100} \
    CONFIG.Port_B_Write_Rate {50} \
    CONFIG.Port_B_Enable_Rate {100}] [get_bd_cells blk_mem_gen_0]
connect_bd_intf_net [get_bd_intf_pins NN_0/out_r_PORTA] [get_bd_intf_pins blk_mem_gen_0/BRAM_PORTB]

# Add AXI-lite for debugging (NN 0)
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 axi_bram_ctrl_1
set_property -dict [list CONFIG.SINGLE_PORT_BRAM {1}] [get_bd_cells axi_bram_ctrl_1]
connect_bd_intf_net [get_bd_intf_pins axi_bram_ctrl_1/BRAM_PORTA] [get_bd_intf_pins blk_mem_gen_0/BRAM_PORTA]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { \
    Clk_master {/zynq_ultra_ps_e_0/pl_clk0 (99 MHz)} \
    Clk_slave {Auto} \
    Clk_xbar {/zynq_ultra_ps_e_0/pl_clk0 (99 MHz)} \
    Master {/zynq_ultra_ps_e_0/M_AXI_HPM0_FPD} \
    Slave {/axi_bram_ctrl_1/S_AXI} \
    ddr_seg {Auto} \
    intc_ip {/ps8_0_axi_periph} \
    master_apm {0}} [get_bd_intf_pins axi_bram_ctrl_1/S_AXI]

# Rename busses and signals for easier debugging (NN 0)
# *** CANNOT DO THIS RIGHT NOW, IT BREAKS SOMETHING BETWEEN QICK AND PYTHON ***
#set_property name NN_0_axis_in [get_bd_intf_nets axis_broadcaster_0_M01_AXIS]
#set_property name NN_0_reg_out [get_bd_intf_nets NN_0_out_r_PORTA]
#set_property name trigger_0 [get_bd_nets vect2bits_16_0_dout14]
#set_property name NN_0_axi_bram_ctrl [get_bd_cells axi_bram_ctrl_1]

validate_bd_design

set_property strategy Flow_AreaOptimized_high [get_runs synth_1]
set_property strategy Congestion_SpreadLogic_high [get_runs impl_1]

# Debug

set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {axis_readout_v2_0_m1_axis}]
set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {axis_readout_v2_0_m0_axis}]
set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {axis_broadcaster_0_M00_AXIS}]
set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {axis_broadcaster_0_M01_AXIS}]
apply_bd_automation -rule xilinx.com:bd_rule:debug -dict [
    list \
        [get_bd_intf_nets axis_broadcaster_0_M00_AXIS] {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" APC_EN "0" } \
]
set_property -dict [list CONFIG.C_SLOT {1} CONFIG.C_BRAM_CNT {18} CONFIG.C_NUM_MONITOR_SLOTS {4} CONFIG.C_SLOT_1_INTF_TYPE {xilinx.com:interface:axis_rtl:1.0}] [get_bd_cells system_ila_0]
set_property -dict [list CONFIG.C_SLOT {3} CONFIG.C_BRAM_CNT {7} CONFIG.C_SLOT_2_INTF_TYPE {xilinx.com:interface:axis_rtl:1.0} CONFIG.C_SLOT_3_INTF_TYPE {xilinx.com:interface:axis_rtl:1.0}] [get_bd_cells system_ila_0]
connect_bd_intf_net [get_bd_intf_pins system_ila_0/SLOT_1_AXIS] [get_bd_intf_pins axis_avg_buffer_0/s_axis]
connect_bd_intf_net [get_bd_intf_pins system_ila_0/SLOT_2_AXIS] [get_bd_intf_pins axis_broadcaster_0/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins system_ila_0/SLOT_3_AXIS] [get_bd_intf_pins axis_terminator_0/s_axis]
set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {NN_0_out_r_PORTA}]
apply_bd_automation -rule xilinx.com:bd_rule:debug -dict [
    list \
        [get_bd_intf_nets NN_0_out_r_PORTA] {NON_AXI_SIGNALS "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" } \
]
set_property -dict [list CONFIG.C_MON_TYPE {MIX}] [get_bd_cells system_ila_0]
set_property HDL_ATTRIBUTE.DEBUG true [get_bd_nets {vect2bits_16_0_dout14 }]
connect_bd_net [get_bd_pins system_ila_0/probe0] [get_bd_pins vect2bits_16_0/dout14]



#set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {axis_signal_gen_v6_0_m_axis}]
#apply_bd_automation -rule xilinx.com:bd_rule:debug -dict [list \
#    [get_bd_intf_nets axis_signal_gen_v6_0_m_axis] {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_dac2" SYSTEM_ILA "Auto" APC_EN "0" } \
#]
#set_property -dict [list CONFIG.C_SLOT {6} CONFIG.C_BRAM_CNT {2.5} CONFIG.C_NUM_MONITOR_SLOTS {7} CONFIG.C_SLOT_1_INTF_TYPE {xilinx.com:interface:axis_rtl:1.0} CONFIG.C_SLOT_2_INTF_TYPE {xilinx.com:interface:axis_rtl:1.0} CONFIG.C_SLOT_3_INTF_TYPE {xilinx.com:interface:axis_rtl:1.0} CONFIG.C_SLOT_4_INTF_TYPE {xilinx.com:interface:axis_rtl:1.0} CONFIG.C_SLOT_5_INTF_TYPE {xilinx.com:interface:axis_rtl:1.0} CONFIG.C_SLOT_6_INTF_TYPE {xilinx.com:interface:axis_rtl:1.0}] [get_bd_cells system_ila_1]
#set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {axis_signal_gen_v6_1_m_axis}]
#connect_bd_intf_net [get_bd_intf_pins system_ila_1/SLOT_1_AXIS] [get_bd_intf_pins axis_signal_gen_v6_1/m_axis]
#set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {axis_signal_gen_v6_2_m_axis}]
#connect_bd_intf_net [get_bd_intf_pins system_ila_1/SLOT_2_AXIS] [get_bd_intf_pins axis_signal_gen_v6_2/m_axis]
#set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {axis_signal_gen_v6_3_m_axis}]
#connect_bd_intf_net [get_bd_intf_pins system_ila_1/SLOT_3_AXIS] [get_bd_intf_pins axis_signal_gen_v6_3/m_axis]
#set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {axis_signal_gen_v6_4_m_axis}]
#connect_bd_intf_net [get_bd_intf_pins system_ila_1/SLOT_4_AXIS] [get_bd_intf_pins axis_signal_gen_v6_4/m_axis]
#set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {axis_signal_gen_v6_5_m_axis}]
#connect_bd_intf_net [get_bd_intf_pins system_ila_1/SLOT_5_AXIS] [get_bd_intf_pins axis_signal_gen_v6_5/m_axis]
#set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {axis_signal_gen_v6_6_m_axis}]
#connect_bd_intf_net [get_bd_intf_pins system_ila_1/SLOT_6_AXIS] [get_bd_intf_pins axis_signal_gen_v6_6/m_axis]
#
#
#disconnect_bd_intf_net [get_bd_intf_net axis_signal_gen_v6_6_m_axis] [get_bd_intf_pins system_ila_1/SLOT_6_AXIS]
#disconnect_bd_intf_net [get_bd_intf_net axis_signal_gen_v6_5_m_axis] [get_bd_intf_pins system_ila_1/SLOT_5_AXIS]
#disconnect_bd_intf_net [get_bd_intf_net axis_signal_gen_v6_4_m_axis] [get_bd_intf_pins system_ila_1/SLOT_4_AXIS]
#set_property -dict [list CONFIG.C_SLOT {0} CONFIG.C_BRAM_CNT {50.5} CONFIG.C_NUM_MONITOR_SLOTS {4}] [get_bd_cells system_ila_1]
#apply_bd_automation -rule xilinx.com:bd_rule:debug -dict [list \
#                                                          [get_bd_intf_nets axis_signal_gen_v6_4_m_axis] {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_dac3" SYSTEM_ILA "Auto" APC_EN "0" } \
#                                                         ]
#set_property -dict [list CONFIG.C_SLOT {2} CONFIG.C_BRAM_CNT {6.5} CONFIG.C_NUM_MONITOR_SLOTS {3} CONFIG.C_SLOT_1_INTF_TYPE {xilinx.com:interface:axis_rtl:1.0} CONFIG.C_SLOT_2_INTF_TYPE {xilinx.com:interface:axis_rtl:1.0}] [get_bd_cells system_ila_2]
#connect_bd_intf_net [get_bd_intf_pins system_ila_2/SLOT_1_AXIS] [get_bd_intf_pins axis_signal_gen_v6_5/m_axis]
#connect_bd_intf_net [get_bd_intf_pins system_ila_2/SLOT_2_AXIS] [get_bd_intf_pins axis_signal_gen_v6_6/m_axis]



validate_bd_design

# === END: NN ===============================================================

reset_run impl_1
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 20
wait_on_run -timeout 360 impl_1

open_run impl_1
report_utilization -file util_216.rpt -hierarchical -hierarchical_percentages
