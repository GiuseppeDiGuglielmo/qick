set _xil_proj_name_suffix_ "_nn"

source proj_216.tcl

## === BEGIN: NN ===============================================================
# Open block diagram
open_bd_design {${proj_dir}/top_216.srcs/sources_1/bd/d_1/d_1.bd}

# Set neural network IP path
set QICK_IPS_PATH "[file normalize ${orig_proj_dir}/ip]"
set LOCAL_IPS_PATH "[file normalize ${orig_proj_dir}/ip_local]"
set_property ip_repo_paths "${QICK_IPS_PATH} ${LOCAL_IPS_PATH}" [current_project]
update_ip_catalog


# Choose one of the NN IPs
set NN_IP_ZIP "xilinx_com_hls_NN_axi_1_0_nonregistered_axis_200.zip"
#set NN_IP_ZIP "xilinx_com_hls_NN_axi_1_0_registered_axis_200.zip"
#
#set NN_IP_ZIP "xilinx_com_hls_NN_axi_1_0_nonregistered_axis_770.zip"
#set NN_IP_ZIP "xilinx_com_hls_NN_axi_1_0_registered_axis_770.zip"

update_ip_catalog -add_ip "[file normalize ${orig_proj_dir}/../qick_ml/ip/${NN_IP_ZIP}]" -repo_path ${LOCAL_IPS_PATH}

# Add NN IPs
create_bd_cell -type ip -vlnv xilinx.com:hls:NN_axi:1.0 NN_axi_0
set_property name NN_0 [get_bd_cells nn_axi_0]

# Broadcaster0 for readout0
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_broadcaster:1.1 axis_broadcaster_0

# Rewire avg-buffer0 input
delete_bd_objs [get_bd_intf_nets axis_readout_v2_0_m1_axis]
connect_bd_intf_net [get_bd_intf_pins axis_broadcaster_0/M01_AXIS] [get_bd_intf_pins axis_avg_buffer_0/s_axis]
connect_bd_intf_net [get_bd_intf_pins axis_readout_v2_0/m1_axis] [get_bd_intf_pins axis_broadcaster_0/S_AXIS]

# Connect NN0 to broadcaster0
connect_bd_intf_net [get_bd_intf_pins axis_broadcaster_0/M00_AXIS] [get_bd_intf_pins NN_0/in_V_V]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 always_ready0
set_property -dict [list CONFIG.CONST_WIDTH {2} CONFIG.CONST_VAL {3}] [get_bd_cells always_ready0]
connect_bd_net [get_bd_pins always_ready0/dout] [get_bd_pins axis_broadcaster_0/m_axis_tready]

# Connect NN0 trigger
connect_bd_net [get_bd_pins NN_0/trigger] [get_bd_pins vect2bits_16_0/dout8]

# Autoconnect clk/rst for broadcaster0 and NN0
apply_bd_automation -rule xilinx.com:bd_rule:clkrst -config { \
    Clk {/usp_rf_data_converter_0/clk_adc2 (307 MHz)} \
    Freq {100} \
    Ref_Clk0 {} \
    Ref_Clk1 {} \
    Ref_Clk2 {}} [get_bd_pins axis_broadcaster_0/aclk]

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

# Set locations
set_property location {7 2954 1995} [get_bd_cells NN_0]
set_property location {8 3442 1984} [get_bd_cells blk_bram_0]
set_property location {7 2977 1770} [get_bd_cells axi_blk_bram_ctrl_0]
set_property location {8 3467 2232} [get_bd_cells always_ready0]
# === END: NN =================================================================

## === BEGIN: ILAs =============================================================
#
## Debug readout0
#set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {axis_readout_v2_0_m1_axis}]
## Debug broadcaster0 to avg-buffer0
#set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {axis_broadcaster_0_M00_AXIS}]
## Debug broadcaster0 to NN0
#set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {axis_broadcaster_0_M01_AXIS}]
## Debug brams0
#set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {NN_0_out_r_PORTA}]
## Debug trigger
#set_property HDL_ATTRIBUTE.DEBUG true [get_bd_nets {vect2bits_16_0_dout8 }]
#
## Autoconnect ILAs
#apply_bd_automation -rule xilinx.com:bd_rule:debug -dict [list \
#    [get_bd_intf_nets axis_readout_v2_0_m1_axis] {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" APC_EN "0" } \
#    [get_bd_intf_nets axis_broadcaster_0_M00_AXIS] {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" APC_EN "0" } \
#    [get_bd_intf_nets axis_broadcaster_0_M01_AXIS] {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" APC_EN "0" } \
#    [get_bd_intf_nets NN_0_out_r_PORTA] {NON_AXI_SIGNALS "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" } \
#]
#
#set_property -dict [list CONFIG.C_MON_TYPE {MIX}] [get_bd_cells system_ila_0]
#connect_bd_net [get_bd_pins system_ila_0/probe0] [get_bd_pins vect2bits_16_0/dout8]
#
## Set locations
#set_property location {8 3492 1813} [get_bd_cells system_ila_0]
## === END: ILAs ===============================================================

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 20
wait_on_run -timeout 360 impl_1

open_run impl_1
report_utilization -file util_216.rpt -hierarchical -hierarchical_percentages
