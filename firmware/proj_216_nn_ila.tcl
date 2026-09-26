# Build into top_216_nn_ila instead of top_216
set _xil_proj_name_suffix_ "_nn_ila"

# Create project (see proj_216.tcl)
source proj_216.tcl

# Add the NN IP to the block design (see nn_216.tcl)
source nn_216.tcl

# === BEGIN: ILAs =============================================================

# Debug readout0 (into broadcaster0)
set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {axis_readout_v2_0_m1_axis}]

# Debug NN0 input (broadcaster0 to NN0)
set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {axis_broadcaster_0_M00_AXIS}]

# Debug NN0 prediction writes (NN0 to blk_bram_0)
set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {NN_0_out_r_PORTA}]

# Debug trigger 0 (avg-buffer0 and NN0)
set_property HDL_ATTRIBUTE.DEBUG true [get_bd_nets {vect2bits_16_0_dout8}]

# Autoconnect ILAs
apply_bd_automation -rule xilinx.com:bd_rule:debug -dict [list \
    [get_bd_intf_nets axis_readout_v2_0_m1_axis] {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" APC_EN "0" } \
    [get_bd_intf_nets axis_broadcaster_0_M00_AXIS] {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" APC_EN "0" } \
    [get_bd_intf_nets NN_0_out_r_PORTA] {NON_AXI_SIGNALS "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" } \
]

# Connect trigger to ILA
set_property -dict [list CONFIG.C_NUM_OF_PROBES {1} CONFIG.C_MON_TYPE {MIX}] [get_bd_cells system_ila_0]
connect_bd_net [get_bd_pins system_ila_0/probe0] [get_bd_pins vect2bits_16_0/dout8]

validate_bd_design
# === END: ILAs ===============================================================

# Force synth_1/impl_1 to rerun even if Vivado thinks they're up to date
reset_run impl_1
reset_run synth_1

# Close timing on RFADC2_CLK: with the default strategy NN_0 misses by a few
# tens of ps (routing-dominated paths). Explore directives in every step plus
# aggressive post-route physical optimization met timing (WNS +0.007 ns).
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]

# Run synthesis and implementation through bitstream generation
launch_runs impl_1 -to_step write_bitstream -jobs 20
wait_on_run -timeout 360 impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "ERROR: impl_1 did not complete successfully (progress: [get_property PROGRESS [get_runs impl_1]])"
}

# Report utilization of the implemented design
open_run impl_1
report_utilization -file "util_216${_xil_proj_name_suffix_}.rpt" -hierarchical -hierarchical_percentages
