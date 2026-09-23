# Create the project with extra ILAs on the readout path.
#
# The block design already carries system_ila_1/2/3 on the qick_processor debug
# buses. Those watch the processor; these watch the signal, which is what you
# need to see a pulse come back:
#
#   - the readout output stream feeding the averager buffer
#   - the readout trigger, tProc port 10
#
# This is the top layer of the project scripts:
#
#   proj_ila.tcl    optional readout ILAs (ILA=1)
#     proj_dac.tcl  generator DAC (DAC=228|230)
#       proj.tcl    the design as delivered
#
# The design sources are left untouched; everything here is applied to the
# in-memory block design after the layers below have built it.
#
# Usage (from this directory):
#   vivado -mode batch -source proj_ila.tcl
#   DAC=230 vivado -mode batch -source proj_ila.tcl
#
# The Makefile in ../../tools drives this with "make bitstream ILA=1", which
# also runs implementation.

# Build into top_dac228_ila/ (top_dac230_ila/ with DAC=230) so the project
# without the ILAs is left alone
if { ![info exists _xil_proj_name_suffix_] } {
    set _xil_proj_name_suffix_ ""
}
append _xil_proj_name_suffix_ "_ila"

source proj_dac.tcl

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

# Place the new ILA on the block design canvas
set_property location {7 5237 2098} $ila

validate_bd_design
save_bd_design

# proj.tcl generated the block design's synthesis products before these ILAs
# existed, and Vivado does not mark them stale afterwards, so synthesis would
# read a netlist without the ILA in it. Regenerate them explicitly.
set bd_file [get_files d_1.bd]
reset_target all $bd_file
generate_target all $bd_file

# === END: ILAs ===============================================================
