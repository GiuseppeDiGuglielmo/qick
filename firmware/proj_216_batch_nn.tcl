set _xil_proj_name_suffix_ "_nn"

source proj_216.tcl

## === BEGIN: NN ==============================================================
# Open block diagram
open_bd_design {${proj_dir}/top_216.srcs/sources_1/bd/d_1/d_1.bd}

# Set neural network IP path
set QICK_IPS_PATH "[file normalize ${orig_proj_dir}/ip]"
set LOCAL_IPS_PATH "[file normalize ${orig_proj_dir}/ip_local]"
set_property ip_repo_paths "${QICK_IPS_PATH} ${LOCAL_IPS_PATH}" [current_project]
update_ip_catalog

update_ip_catalog -add_ip "[file normalize ${orig_proj_dir}/../qick_ml/xilinx_com_hls_NN_axi_1_0.zip]" -repo_path ${LOCAL_IPS_PATH}

# Add NN IPs
create_bd_cell -type ip -vlnv xilinx.com:hls:NN_axi:1.0 NN_axi_0
set_property name NN_0 [get_bd_cells nn_axi_0]

# Broadcaster0 for readout0
set_property -dict [list CONFIG.NUM_MI {3} CONFIG.M02_TDATA_REMAP {tdata[31:0]}] [get_bd_cells axis_broadcaster_0]

# Connect NN0 to broadcaster0
connect_bd_intf_net [get_bd_intf_pins axis_broadcaster_0/M02_AXIS] [get_bd_intf_pins NN_0/in_V_V]
#create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 always_ready0
#connect_bd_net [get_bd_pins always_ready0/dout] [get_bd_pins axis_broadcaster_0/m_axis_tready]

# Connect NN0 trigger
connect_bd_net [get_bd_pins NN_0/trigger] [get_bd_pins vect2bits_16_0/dout14]

# Autoconnect clk/rst for broadcaster0 and NN0
#apply_bd_automation -rule xilinx.com:bd_rule:clkrst -config { \
#    Clk {/usp_rf_data_converter_0/clk_adc2 (307 MHz)} \
#    Freq {100} \
#    Ref_Clk0 {} \
#    Ref_Clk1 {} \
#    Ref_Clk2 {}} [get_bd_pins axis_broadcaster_0/aclk]
#
# Autoconnect AXI-lite NN0
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { \
    Clk_master {/zynq_ultra_ps_e_0/pl_clk0 (99 MHz)} \
    Clk_slave {/usp_rf_data_converter_0/clk_adc2 (307 MHz)} \
    Clk_xbar {/zynq_ultra_ps_e_0/pl_clk0 (99 MHz)} \
    Master {/zynq_ultra_ps_e_0/M_AXI_HPM0_FPD} \
    Slave {/NN_0/s_axi_config} \
    ddr_seg {Auto} \
    intc_ip {/ps8_0_axi_periph} \
    master_apm {0}} [get_bd_intf_pins NN_0/s_axi_config]

# Add two-port BRAMs (NN0)
create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 blk_bram_0
set_property -dict [list \
    CONFIG.Memory_Type {True_Dual_Port_RAM} \
    CONFIG.Enable_B {Use_ENB_Pin} \
    CONFIG.Use_RSTB_Pin {true} \
    CONFIG.Port_B_Clock {100} \
    CONFIG.Port_B_Write_Rate {50} \
    CONFIG.Port_B_Enable_Rate {100}] [get_bd_cells blk_bram_0]
connect_bd_intf_net [get_bd_intf_pins NN_0/out_r_PORTA] [get_bd_intf_pins blk_bram_0/BRAM_PORTB]

# Add AXI-lite for debugging (NN0)
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 axi_blk_bram_ctrl_0
set_property -dict [list CONFIG.SINGLE_PORT_BRAM {1}] [get_bd_cells axi_blk_bram_ctrl_0]
connect_bd_intf_net [get_bd_intf_pins axi_blk_bram_ctrl_0/BRAM_PORTA] [get_bd_intf_pins blk_bram_0/BRAM_PORTA]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { \
    Clk_master {/zynq_ultra_ps_e_0/pl_clk0 (99 MHz)} \
    Clk_slave {Auto} \
    Clk_xbar {/zynq_ultra_ps_e_0/pl_clk0 (99 MHz)} \
    Master {/zynq_ultra_ps_e_0/M_AXI_HPM0_FPD} \
    Slave {/axi_blk_bram_ctrl_0/S_AXI} \
    ddr_seg {Auto} \
    intc_ip {/ps8_0_axi_periph} \
    master_apm {0}} [get_bd_intf_pins axi_blk_bram_ctrl_0/S_AXI]

set_property strategy Flow_AreaOptimized_high [get_runs synth_1]
set_property strategy Congestion_SpreadLogic_high [get_runs impl_1]

# Set locations
#set_property location {4 2550 4498} [get_bd_cells axi_blk_bram_ctrl_0]
#set_property location {5 3330 4508} [get_bd_cells blk_bram_0]
#set_property location {5 3328 4331} [get_bd_cells NN_0]
# === END: NN =================================================================

## === BEGIN: BD ILAs ==========================================================
## Debug readout0
#set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {axis_readout_v2_0_m1_axis}]
#
## Debug broadcaster0 to NN0
#set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {axis_broadcaster_0_M02_AXIS}]
#
## Debug brams0
#set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {NN_0_out_r_PORTA}]
#
## Debug trigger
#set_property HDL_ATTRIBUTE.DEBUG true [get_bd_nets {vect2bits_16_0_dout14 }]
#
## Debug AXI-lite
#set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {ps8_0_axi_periph_M27_AXI}]
#
## Autoconnect ILAs
#apply_bd_automation -rule xilinx.com:bd_rule:debug -dict [list \
#    [get_bd_intf_nets ps8_0_axi_periph_M27_AXI] {AXI_R_ADDRESS "Data and Trigger" AXI_R_DATA "Data and Trigger" AXI_W_ADDRESS "Data and Trigger" AXI_W_DATA "Data and Trigger" AXI_W_RESPONSE "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" APC_EN "0" } \
#    [get_bd_intf_nets axis_readout_v2_0_m1_axis] {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" APC_EN "0" } \
#    [get_bd_intf_nets axis_broadcaster_0_M02_AXIS] {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" APC_EN "0" } \
#    [get_bd_intf_nets NN_0_out_r_PORTA] {NON_AXI_SIGNALS "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" } \
#]
##apply_bd_automation -rule xilinx.com:bd_rule:debug -dict [list \
##    [get_bd_intf_nets ps8_0_axi_periph_M27_AXI] {AXI_R_ADDRESS "Data and Trigger" AXI_R_DATA "Data and Trigger" AXI_W_ADDRESS "Data and Trigger" AXI_W_DATA "Data and Trigger" AXI_W_RESPONSE "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" APC_EN "0" } \
##    [get_bd_intf_nets axis_readout_v2_0_m1_axis] {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" APC_EN "0" } \
##    [get_bd_intf_nets axis_broadcaster_0_M02_AXIS] {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" APC_EN "0" } \
##]
#
## Connect trigger signal to ILA
#set_property -dict [list CONFIG.C_MON_TYPE {MIX}] [get_bd_cells system_ila_0]
#connect_bd_net [get_bd_pins system_ila_0/probe0] [get_bd_pins vect2bits_16_0/dout14]
#
## Connect NN0.in.ready signal to ILA
#set_property -dict [list CONFIG.C_NUM_OF_PROBES {2}] [get_bd_cells system_ila_0]
#connect_bd_net [get_bd_pins system_ila_0/probe1] [get_bd_pins NN_0/in_V_V_TREADY]
#set_property HDL_ATTRIBUTE.DEBUG true [get_bd_nets {NN_0_in_V_V_TREADY }]
#
## Set locations
##set_property location {5 3315 4752} [get_bd_cells system_ila_0]
#
#validate_bd_design
## === END: BD ILAs ============================================================

## === BEGIN: RTL ILAs =========================================================
#update_compile_order -fileset sources_1
#launch_runs synth_1 -jobs 20
#wait_on_run -timeout 360 synth_1
#
#set BIT_PER_SAMPLE 14
#set SAMPLE_COUNT 6
#set TOTAL_BITS [expr $SAMPLE_COUNT * $BIT_PER_SAMPLE]
#
#open_run synth_1 -name synth_1
#update_compile_order -fileset sources_1
#for {set i 0} {$i < $TOTAL_BITS} {incr i} {
#    set_property mark_debug true [get_nets [list d_1_i/NN_0/inst/in_local_V_fu_174[$i]]]
#}
#
#file mkdir ${proj_dir}/top_216.srcs/constrs_1/new
#close [ open ${proj_dir}/top_216.srcs/constrs_1/new/dbg_constraints.xdc w ]
#add_files -fileset constrs_1 ${proj_dir}/top_216.srcs/constrs_1/new/dbg_constraints.xdc
#set_property target_constrs_file ${proj_dir}/top_216.srcs/constrs_1/new/dbg_constraints.xdc [current_fileset -constrset]
#save_constraints -force
#
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
#
#set_property port_width $TOTAL_BITS [get_debug_ports u_ila_0/probe0]
#set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
#for {set i 0} {$i < $TOTAL_BITS} {incr i} {
#    connect_debug_port u_ila_0/probe0 [get_nets [list d_1_i/NN_0/inst/in_local_V_fu_174[$i]]]
#}
#
#set_property mark_debug true [get_nets [list d_1_i/NN_0/inst/grp_NN_fu_315_ap_start_reg]]
#set_property mark_debug true [get_nets [list d_1_i/NN_0/inst/grp_NN_fu_315_ap_ready]]
#create_debug_port u_ila_0 probe
#set_property port_width 1 [get_debug_ports u_ila_0/probe1]
#set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
#connect_debug_port u_ila_0/probe1 [get_nets [list d_1_i/NN_0/inst/grp_NN_fu_315_ap_start_reg ]]
#create_debug_port u_ila_0 probe
#set_property port_width 1 [get_debug_ports u_ila_0/probe2]
#set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
#connect_debug_port u_ila_0/probe2 [get_nets [list d_1_i/NN_0/inst/grp_NN_fu_315_ap_ready ]]
#
#save_constraints -force
#
###reset_run d_1_axi_smc_0_synth_1
###reset_run d_1_axi_smc_1_0_synth_1
###reset_run d_1_system_ila_0_0_synth_1
#save_bd_design
##reset_run synth_1
## === END: RTL ILAs ===========================================================


# Remove IPs
#source delete_ips_216.tcl

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 20
wait_on_run -timeout 360 impl_1

open_run impl_1
report_utilization -file util_216.rpt -hierarchical -hierarchical_percentages
