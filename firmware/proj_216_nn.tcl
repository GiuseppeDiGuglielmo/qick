# Build into top_216_nn instead of top_216
set _xil_proj_name_suffix_ "_nn"

# Create project (see proj_216.tcl)
source proj_216.tcl

# Add the NN IP to the block design (see nn_216.tcl)
source nn_216.tcl

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
