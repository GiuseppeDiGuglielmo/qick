source proj_111_rfbv2.tcl

## === BEGIN: ILAs =============================================================
# TODO: REMOVE THE ABSOLUTE PATH!
open_bd_design {/extras/home/gdg/research/projects/quantum/qick/firmware/top_111_rfbv2/top_111_rfbv2.srcs/sources_1/bd/d_1/d_1.bd}

set_property HDL_ATTRIBUTE.DEBUG true [get_bd_nets {vect2bits_16_0_dout14 vect2bits_16_0_dout15 }]
set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {\
    axis_avg_buffer_1_m1_axis \
    axis_avg_buffer_0_m2_axis \
    ps8_0_axi_periph_M09_AXI \
    axis_readout_v2_1_m1_axis \
    axis_readout_v2_0_m1_axis \
    axis_avg_buffer_0_m1_axis \
    axis_avg_buffer_0_m0_axis \
    axis_avg_buffer_1_m0_axis \
    ps8_0_axi_periph_M10_AXI \
    axis_avg_buffer_1_m2_axis}]

apply_bd_automation -rule xilinx.com:bd_rule:debug -dict [list \
    [get_bd_intf_nets axis_avg_buffer_0_m0_axis] {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/zynq_ultra_ps_e_0/pl_clk0" SYSTEM_ILA "Auto" APC_EN "0" } \
    [get_bd_intf_nets axis_avg_buffer_0_m1_axis] {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/zynq_ultra_ps_e_0/pl_clk0" SYSTEM_ILA "Auto" APC_EN "0" } \
    [get_bd_intf_nets axis_avg_buffer_0_m2_axis] {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/zynq_ultra_ps_e_0/pl_clk0" SYSTEM_ILA "Auto" APC_EN "0" } \
    [get_bd_intf_nets axis_avg_buffer_1_m0_axis] {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/zynq_ultra_ps_e_0/pl_clk0" SYSTEM_ILA "Auto" APC_EN "0" } \
    [get_bd_intf_nets axis_avg_buffer_1_m1_axis] {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/zynq_ultra_ps_e_0/pl_clk0" SYSTEM_ILA "Auto" APC_EN "0" } \
    [get_bd_intf_nets axis_avg_buffer_1_m2_axis] {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/zynq_ultra_ps_e_0/pl_clk0" SYSTEM_ILA "Auto" APC_EN "0" } \
    [get_bd_intf_nets axis_readout_v2_0_m1_axis] {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/clk_adc0_x2/clk_out1" SYSTEM_ILA "Auto" APC_EN "0" } \
    [get_bd_intf_nets axis_readout_v2_1_m1_axis] {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/clk_adc0_x2/clk_out1" SYSTEM_ILA "Auto" APC_EN "0" } \
    [get_bd_intf_nets ps8_0_axi_periph_M09_AXI] {AXI_R_ADDRESS "Data and Trigger" AXI_R_DATA "Data and Trigger" AXI_W_ADDRESS "Data and Trigger" AXI_W_DATA "Data and Trigger" AXI_W_RESPONSE "Data and Trigger" CLK_SRC "/zynq_ultra_ps_e_0/pl_clk0" SYSTEM_ILA "Auto" APC_EN "0" } \
    [get_bd_intf_nets ps8_0_axi_periph_M10_AXI] {AXI_R_ADDRESS "Data and Trigger" AXI_R_DATA "Data and Trigger" AXI_W_ADDRESS "Data and Trigger" AXI_W_DATA "Data and Trigger" AXI_W_RESPONSE "Data and Trigger" CLK_SRC "/zynq_ultra_ps_e_0/pl_clk0" SYSTEM_ILA "Auto" APC_EN "0" } \
]

set_property -dict [list CONFIG.C_BRAM_CNT {1.5} CONFIG.C_DATA_DEPTH {2048}] [get_bd_cells system_ila_1]
set_property -dict [list CONFIG.C_BRAM_CNT {27} CONFIG.C_DATA_DEPTH {2048}] [get_bd_cells system_ila_0]

set_property -dict [list CONFIG.C_BRAM_CNT {1.5} CONFIG.C_NUM_OF_PROBES {2} CONFIG.C_MON_TYPE {MIX}] [get_bd_cells system_ila_1]
connect_bd_net [get_bd_pins system_ila_1/probe0] [get_bd_pins vect2bits_16_0/dout14]
connect_bd_net [get_bd_pins system_ila_1/probe1] [get_bd_pins vect2bits_16_0/dout15]

validate_bd_design
## === END: ILAs ===============================================================

reset_run impl_1
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 20
wait_on_run -timeout 360 impl_1

open_run impl_1
report_utilization -file util_111_rfbv2.rpt -hierarchical -hierarchical_percentages
