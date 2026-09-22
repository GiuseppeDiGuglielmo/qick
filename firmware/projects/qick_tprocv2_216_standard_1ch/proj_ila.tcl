# Create the project with extra ILAs on the readout path.
#
# The block design already carries system_ila_1/2/3 on the qick_processor debug
# buses. Those watch the processor; these watch the signal, which is what you
# need to see a pulse come back:
#
#   - the readout output stream feeding the averager buffer
#   - the readout trigger, tProc port 10
#
# The design sources are left untouched; everything here is applied to the
# in-memory block design after proj.tcl has built it.
#
# Usage (from this directory):
#   vivado -mode batch -source proj_ila.tcl
#
# The Makefile in ../../tools drives this with "make bitstream ILA=1", which
# also runs implementation.

# Build into top_ila/ so the plain project in top/ is left alone
set _xil_proj_name_suffix_ "_ila"

source proj.tcl

# === BEGIN: ILAs =============================================================

open_bd_design "${proj_dir}/${_xil_proj_name_}.srcs/sources_1/bd/d_1/d_1.bd"

# The readout and its trigger both live inside the readout_wrapper hierarchy
set ro_net   [get_bd_intf_nets readout_wrapper/axis_dyn_readout_v1_0_m1_axis]
set trig_pin [get_bd_pins readout_wrapper/axis_avg_buffer_0/trigger]

if {[llength $ro_net] == 0} {
    error "ERROR: readout stream net not found, did the block design change?"
}
if {[llength $trig_pin] == 0} {
    error "ERROR: readout trigger pin not found, did the block design change?"
}

set_property HDL_ATTRIBUTE.DEBUG true $ro_net

# The block design already has ILAs, so the one the automation adds has to be
# identified by comparing before and after rather than assumed to be system_ila_0
set ila_filter {VLNV =~ "xilinx.com:ip:system_ila:*"}
set ila_before [get_bd_cells -hierarchical -quiet -filter $ila_filter]

# Autoconnect an ILA to the readout stream, in the ADC clock domain
apply_bd_automation -rule xilinx.com:bd_rule:debug -dict [list \
    $ro_net {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" APC_EN "0" } \
]

set ila_new {}
foreach cell [get_bd_cells -hierarchical -quiet -filter $ila_filter] {
    if {[lsearch -exact $ila_before $cell] == -1} {
        lappend ila_new $cell
    }
}
if {[llength $ila_new] != 1} {
    error "ERROR: expected the debug automation to add one ILA, got: $ila_new"
}
set ila [lindex $ila_new 0]
puts "INFO: readout ILA is $ila"

# Mix the trigger in as a native probe alongside the AXI-Stream monitor
set_property -dict [list CONFIG.C_MON_TYPE {MIX}] [get_bd_cells $ila]
connect_bd_net [get_bd_pins $ila/probe0] $trig_pin

validate_bd_design
save_bd_design

# === END: ILAs ===============================================================
