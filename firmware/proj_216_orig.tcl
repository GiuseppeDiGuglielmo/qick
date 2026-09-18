# Build into top_216_orig instead of top_216
set _xil_proj_name_suffix_ "_orig"

# Create project (see proj_216.tcl)
source proj_216.tcl

# Force synth_1/impl_1 to rerun even if Vivado thinks they're up to date
reset_run impl_1
reset_run synth_1

# Run synthesis and implementation through bitstream generation
launch_runs impl_1 -to_step write_bitstream -jobs 20
wait_on_run -timeout 360 impl_1

# Report utilization of the implemented design
open_run impl_1
report_utilization -file "util_216${_xil_proj_name_suffix_}.rpt" -hierarchical -hierarchical_percentages
