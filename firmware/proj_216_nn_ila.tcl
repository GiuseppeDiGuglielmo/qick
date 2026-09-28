# Build into top_216_nn_ila instead of top_216
set _xil_proj_name_suffix_ "_nn_ila"

# Create project (see proj_216.tcl)
source proj_216.tcl

# Add the NN IP to the block design (see nn_216.tcl)
source nn_216.tcl

# === BEGIN: ILAs =============================================================

# Debug NN0 input (broadcaster0 to NN0). Readout0 (into broadcaster0) is not
# probed: it carries the same samples, and with it the 4096-sample ILA
# missed timing (RFDAC2_CLK WNS -0.197 ns, RFADC2_CLK -0.022 ns)
set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {axis_broadcaster_0_M00_AXIS}]

# Debug NN0 prediction writes (NN0 to blk_bram_0)
set_property HDL_ATTRIBUTE.DEBUG true [get_bd_intf_nets {NN_0_out_r_PORTA}]

# Debug trigger 0 (avg-buffer0 and NN0)
set_property HDL_ATTRIBUTE.DEBUG true [get_bd_nets {vect2bits_16_0_dout8}]

# Autoconnect ILAs
apply_bd_automation -rule xilinx.com:bd_rule:debug -dict [list \
    [get_bd_intf_nets axis_broadcaster_0_M00_AXIS] {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" APC_EN "0" } \
    [get_bd_intf_nets NN_0_out_r_PORTA] {NON_AXI_SIGNALS "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" } \
]

# Connect trigger to ILA: probe0 is the raw tProc trigger (clk_dac2), probe1
# the resynchronized one that NN0 sees. Keep 4096 samples (13.3 us) so one
# capture spans a trigger and the NN0 prediction write that follows it
# (~1.2k clocks later).
set_property -dict [list CONFIG.C_NUM_OF_PROBES {2} CONFIG.C_MON_TYPE {MIX} \
    CONFIG.C_DATA_DEPTH {4096}] [get_bd_cells system_ila_0]
connect_bd_net [get_bd_pins system_ila_0/probe0] [get_bd_pins vect2bits_16_0/dout8]
connect_bd_net [get_bd_pins system_ila_0/probe1] [get_bd_pins nn_trigger_sync_0/dout]

validate_bd_design
# === END: ILAs ===============================================================

# Force synth_1/impl_1 to rerun even if Vivado thinks they're up to date
reset_run impl_1
reset_run synth_1

# Close timing on RFADC2_CLK: with the ILAs added, NN_0 misses by up to
# 0.23 ns with the NN build's strategy (Performance_ExplorePostRoutePhysOpt).
# Retiming in phys_opt plus aggressive post-route physical optimization met
# timing on ml-integration-2024 (Vivado 2022.1, WNS +0.045 ns); not yet
# checked with this branch's block design and Vivado 2023.1.
set_property strategy Performance_Retiming [get_runs impl_1]
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
