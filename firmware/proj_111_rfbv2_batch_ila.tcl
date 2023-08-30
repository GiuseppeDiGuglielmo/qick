source proj_111_rfbv2.tcl

#reset_run impl_1
#reset_run synth_1
#launch_runs impl_1 -to_step write_bitstream -jobs 20
#wait_on_run -timeout 360 impl_1
#
#open_run impl_1
#report_utilization -file util_111_rfbv2.rpt -hierarchical -hierarchical_percentages
