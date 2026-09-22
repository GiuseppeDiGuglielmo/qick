# Build a QICK design through to a bitstream.
#
# Run with the design directory as the working directory, so that the proj.tcl
# next to it resolves its own relative paths:
#
#   cd ../projects/<design> && vivado -mode batch -source ../../tools/bitstream.tcl
#
# The Makefile does this for you; see "make help".
#
# Set the JOBS environment variable to limit parallel synthesis jobs. Each job
# is a full Vivado process of roughly 2.5 GB, so the default of 20 needs a
# large machine. Set ILA=1 to build the variant with the readout ILAs.

set jobs 20
if { [info exists ::env(JOBS)] } {
    set jobs $::env(JOBS)
}

# ILA=1 selects the design's proj_ila.tcl, which adds ILAs on the readout path
# and builds into top_ila/ instead of top/
set proj_script "proj.tcl"
if { [info exists ::env(ILA)] && $::env(ILA) ne "0" } {
    set proj_script "proj_ila.tcl"
}
if { ![file exists $proj_script] } {
    error "ERROR: $proj_script not found, run this with the design directory as the working directory"
}

# Create the project (see proj.tcl next to this design)
source $proj_script

# Force synth_1/impl_1 to rerun even if Vivado thinks they're up to date
reset_run impl_1
reset_run synth_1

# Run synthesis and implementation through bitstream generation
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run -timeout 360 impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "ERROR: impl_1 did not complete successfully (progress: [get_property PROGRESS [get_runs impl_1]])"
}

# Report utilization of the implemented design; BRAM is the limiting resource
open_run impl_1
report_utilization -file "util${_xil_proj_name_suffix_}.rpt" -hierarchical -hierarchical_percentages
