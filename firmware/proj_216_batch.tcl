source proj_216.tcl

# === BEGIN: DEBUG ===============================================================
# Open block diagram
open_bd_design {${proj_dir}/top_216.srcs/sources_1/bd/d_1/d_1.bd}

# AXI-stream
set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {axis_readout_v2_0_m1_axis}]
apply_bd_automation -rule xilinx.com:bd_rule:debug -dict [list \
    [get_bd_intf_nets axis_readout_v2_0_m1_axis] \
    {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" APC_EN "0" } \
]

# Trigger
set_property HDL_ATTRIBUTE.DEBUG true [get_bd_nets {vect2bits_16_0_dout14 }]
set_property -dict [list CONFIG.C_BRAM_CNT {1} CONFIG.C_MON_TYPE {MIX}] [get_bd_cells system_ila_0]
connect_bd_net [get_bd_pins system_ila_0/probe0] [get_bd_pins vect2bits_16_0/dout14]

# === END: DEBUG ===============================================================

reset_run impl_1
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 20
wait_on_run -timeout 360 impl_1

open_run impl_1
report_utilization -file util_216.rpt -hierarchical -hierarchical_percentages
