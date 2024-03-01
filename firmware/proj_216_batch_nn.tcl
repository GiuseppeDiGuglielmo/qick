source proj_216.tcl

## === BEGIN: NN ===============================================================
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

# Connect NN IP to average block that just forward the input AXIS
#connect_bd_intf_net [get_bd_intf_pins axis_avg_buffer_0/fwd_axis] [get_bd_intf_pins NN_0/in_V]
connect_bd_intf_net [get_bd_intf_pins axis_avg_buffer_0/fwd_axis] [get_bd_intf_pins NN_0/in_V_V]


set_property CONFIG.FREQ_HZ 307200000 [get_bd_intf_pins /axis_avg_buffer_0/fwd_axis]
connect_bd_net [get_bd_pins NN_0/ap_clk] [get_bd_pins usp_rf_data_converter_0/clk_adc2]
connect_bd_net [get_bd_pins NN_0/ap_rst_n] [get_bd_pins rst_adc/peripheral_aresetn]

#set_property -dict [list CONFIG.LENGTH {770}] [get_bd_cells axis_avg_buffer_0]
#
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

# Add AXI-lite scaler port on NN
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { \
    Clk_master {/zynq_ultra_ps_e_0/pl_clk0 (99 MHz)} \
    Clk_slave {/usp_rf_data_converter_0/clk_adc2 (307 MHz)} \
    Clk_xbar {/zynq_ultra_ps_e_0/pl_clk0 (99 MHz)} \
    Master {/zynq_ultra_ps_e_0/M_AXI_HPM0_FPD} \
    Slave {/NN_0/s_axi_scaler} \
    ddr_seg {Auto} \
    intc_ip {/ps8_0_axi_periph} \
    master_apm {0}} [get_bd_intf_pins NN_0/s_axi_scaler]

validate_bd_design

set_property strategy Flow_AreaOptimized_high [get_runs synth_1]
set_property strategy Congestion_SpreadLogic_high [get_runs impl_1]

# === END: NN ===============================================================

# === BEGIN: ILA ===============================================================
set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {ps8_0_axi_periph_M28_AXI axis_avg_buffer_0_fwd_axis NN_0_out_r_PORTA}]
apply_bd_automation -rule xilinx.com:bd_rule:debug -dict [list \
    [get_bd_intf_nets axis_avg_buffer_0_fwd_axis] {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" APC_EN "0" } \
    [get_bd_intf_nets NN_0_out_r_PORTA] {NON_AXI_SIGNALS "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" } \
    [get_bd_intf_nets ps8_0_axi_periph_M28_AXI] {AXI_R_ADDRESS "Data and Trigger" AXI_R_DATA "Data and Trigger" AXI_W_ADDRESS "Data and Trigger" AXI_W_DATA "Data and Trigger" AXI_W_RESPONSE "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" APC_EN "0" } \
]

# Trigger
set_property -dict [list CONFIG.C_MON_TYPE {MIX}] [get_bd_cells system_ila_0]
set_property HDL_ATTRIBUTE.DEBUG true [get_bd_nets {vect2bits_16_0_dout14 }]
connect_bd_net [get_bd_pins system_ila_0/probe0] [get_bd_pins vect2bits_16_0/dout14]


validate_bd_design
# === END: ILA ===============================================================

update_compile_order -fileset sources_1
launch_runs synth_1 -jobs 20
wait_on_run -timeout 360 synth_1

## === BEGIN: RTL ILA =========================================================
#
#open_run synth_1 -name synth_1
#update_compile_order -fileset sources_1
#for {set i 0} {$i < 14*2} {incr i} {
#    set_property mark_debug true [get_nets [list d_1_i/NN_0/inst/in_local_V_fu_160[$i]]]
#}
#set_property mark_debug true [get_nets [list d_1_i/NN_0/inst/grp_myproject_fu_206_ap_start]]
#set_property mark_debug true [get_nets [list d_1_i/NN_0/inst/grp_myproject_fu_206_ap_done]]
#file mkdir ${proj_dir}/top_216.srcs/constrs_1/new
#close [ open ${proj_dir}/top_216.srcs/constrs_1/new/dbg_constraints.xdc w ]
#add_files -fileset constrs_1 ${proj_dir}/top_216.srcs/constrs_1/new/dbg_constraints.xdc
#set_property target_constrs_file ${proj_dir}/top_216.srcs/constrs_1/new/dbg_constraints.xdc [current_fileset -constrset]
#save_constraints -force
#create_debug_core u_ila_0 ila
#set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_0]
#set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
#set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
#set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
#set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
#set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_0]
#set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
#set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_0]
#connect_debug_port u_ila_0/clk [get_nets [list d_1_i/usp_rf_data_converter_0/inst/i_d_1_usp_rf_data_converter_0_0_bufg_gt_ctrl/clk_adc2 ]]
#set_property port_width 56 [get_debug_ports u_ila_0/probe0]
#set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
#for {set i 0} {$i < 14*2} {incr i} {
#    connect_debug_port u_ila_0/probe0 [get_nets [list d_1_i/NN_0/inst/in_local_V_fu_160[$i]]]
#}
#create_debug_port u_ila_0 probe
#set_property port_width 1 [get_debug_ports u_ila_0/probe1]
#set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
#connect_debug_port u_ila_0/probe1 [get_nets [list d_1_i/NN_0/inst/grp_myproject_fu_206_ap_done ]]
#create_debug_port u_ila_0 probe
#set_property port_width 1 [get_debug_ports u_ila_0/probe2]
#set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
#connect_debug_port u_ila_0/probe2 [get_nets [list d_1_i/NN_0/inst/grp_myproject_fu_206_ap_start ]]
#save_constraints
#reset_run d_1_axi_smc_0_synth_1
#reset_run d_1_axi_smc_1_0_synth_1
#reset_run d_1_system_ila_0_0_synth_1
#save_bd_design
#reset_run synth_1
#
## === END: RTL ILA ===========================================================

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 20
wait_on_run -timeout 360 impl_1

open_run impl_1
report_utilization -file util_216.rpt -hierarchical -hierarchical_percentages
