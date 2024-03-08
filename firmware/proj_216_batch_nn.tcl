source proj_216.tcl

# Open block diagram
open_bd_design {${proj_dir}/top_216.srcs/sources_1/bd/d_1/d_1.bd}

# Simplify the QICK design (faster synthesis)
source delete_ips_216.tcl

#reset_run impl_1
#launch_runs impl_1 -to_step write_bitstream -jobs 20
#wait_on_run -timeout 360 impl_1
#
#open_run impl_1
#report_utilization -file util_216.rpt -hierarchical -hierarchical_percentages
