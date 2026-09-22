# Build a QICK design through to a bitstream.
#
# Run with the design directory as the working directory, so that the
# unmodified proj.tcl next to it resolves its own relative paths:
#
#   cd ../projects/<design> && vivado -mode batch -source ../../tools/bitstream.tcl
#
# The Makefile does this for you; see "make help".
#
# Set the JOBS environment variable to limit parallel synthesis jobs. Each job
# is a full Vivado process of roughly 2.5 GB, so the default of 20 needs a
# large machine.

set jobs 20
if { [info exists ::env(JOBS)] } {
    set jobs $::env(JOBS)
}

# Create the project (see proj.tcl in this directory)
source proj.tcl

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
report_utilization -file "util.rpt" -hierarchical -hierarchical_percentages
