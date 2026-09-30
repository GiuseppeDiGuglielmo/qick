# Create the project with extra ILAs on the readout path.
#
# The block design already carries system_ila_1/2/3 on the qick_processor debug
# buses. Those watch the processor; these watch the signal, which is what you
# need to see a pulse come back:
#
#   - the readout output stream feeding the averager buffer
#   - the readout trigger, tProc port 10
#
# With the NN classifier (NN=1, see proj_nn.tcl) they watch the NN instead:
#
#   - the NN input stream (readout 0, from the broadcaster)
#   - the NN prediction writes into its BRAM
#   - the readout trigger (probe0) and its resynchronized copy that the NN
#     sees (probe1)
#
# This is the top layer of the project scripts:
#
#   proj_ila.tcl        optional readout ILAs (ILA=1)
#     proj_nn.tcl       optional NN classifier (NN=1)
#       proj_dac.tcl    generator DAC (DAC=228|230)
#         proj.tcl      the design as delivered
#
# The design sources are left untouched; everything here is applied to the
# in-memory block design after the layers below have built it.
#
# Usage (from this directory):
#   vivado -mode batch -source proj_ila.tcl
#   DAC=230 vivado -mode batch -source proj_ila.tcl
#   NN=1 DAC=230 vivado -mode batch -source proj_ila.tcl
#
# The Makefile in ../../tools drives this with "make bitstream ILA=1", which
# also runs implementation.

# Build into top_dac228_ila/ (top_dac230_ila/ with DAC=230, top_dac230_nn_ila/
# with NN=1) so the project without the ILAs is left alone
if { ![info exists _xil_proj_name_suffix_] } {
    set _xil_proj_name_suffix_ ""
}
append _xil_proj_name_suffix_ "_ila"

source proj_nn.tcl

# === BEGIN: ILAs =============================================================

open_bd_design "${proj_dir}/${_xil_proj_name_}.srcs/sources_1/bd/d_1/d_1.bd"

# === BEGIN TEMPORARY: remove the processor ILAs and the debug bridge =========
# Temporary workaround: drop the ILAs that ship in the block design
# (system_ila_1/2/3 on the qick_processor debug buses) so that only the
# readout ILA added below ends up in the build, and drop debug_bridge_0.
# With the bridge in the design, the debug hub is reached through JTAG driven
# by the PS over AXI (XVC) and is invisible on the physical JTAG chain; without
# it Vivado builds a normal hub, so the ILAs show up after programming over
# JTAG, as in the tProc v1 designs. Remove this block to get the processor
# ILAs and the bridge back.
delete_bd_objs \
    [get_bd_nets qick_processor_0_t_fifo_do] \
    [get_bd_nets qick_processor_0_t_debug_do] \
    [get_bd_nets qick_processor_0_t_time_abs_o] \
    [get_bd_cells system_ila_2]
delete_bd_objs \
    [get_bd_nets qick_processor_0_c_core_do] \
    [get_bd_nets qick_processor_0_c_port_do] \
    [get_bd_nets qick_processor_0_c_time_ref_do] \
    [get_bd_nets qick_processor_0_c_debug_do] \
    [get_bd_nets qick_processor_0_c_time_usr_do] \
    [get_bd_nets qick_processor_0_c_proc_do] \
    [get_bd_cells system_ila_1]
delete_bd_objs \
    [get_bd_nets qick_processor_0_ps_debug_do] \
    [get_bd_cells system_ila_3]
# Its AXI slave sits on ps8_0_axi_periph/M01_AXI, which is left unconnected
delete_bd_objs [get_bd_cells debug_bridge_0]
# === END TEMPORARY ===========================================================

# The readout and its trigger both live inside the readout_wrapper hierarchy
set ro_net   [get_bd_intf_nets readout_wrapper/axis_dyn_readout_v1_0_m1_axis]
set trig_pin [get_bd_pins readout_wrapper/axis_avg_buffer_0/trigger]

if {[llength $ro_net] == 0} {
    error "ERROR: readout stream net not found, did the block design change?"
}
if {[llength $trig_pin] == 0} {
    error "ERROR: readout trigger pin not found, did the block design change?"
}

# With the NN (proj_nn.tcl), watch its input, its prediction writes and both
# copies of its trigger instead of the readout stream. The NN input carries
# the same samples as the readout stream; on the tProc v1 branches probing
# both with a 4096-sample ILA missed timing.
set has_nn [expr {[llength [get_bd_cells -quiet NN_0]] == 1}]
if { $has_nn } {
    set nn_in_net   [get_bd_intf_nets -of_objects [get_bd_intf_pins NN_0/in_V_V]]
    set nn_out_net  [get_bd_intf_nets -of_objects [get_bd_intf_pins NN_0/out_r_PORTA]]
    set nn_trig_pin [get_bd_pins nn_trigger_sync_0/dout]
    if {[llength $nn_in_net] != 1 || [llength $nn_out_net] != 1 || [llength $nn_trig_pin] != 1} {
        error "ERROR: NN nets not found, did proj_nn.tcl change?"
    }
    set debug_nets [list $nn_in_net $nn_out_net]
    set debug_dict [list \
        $nn_in_net  {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" APC_EN "0" } \
        $nn_out_net {NON_AXI_SIGNALS "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" } \
    ]
} else {
    set debug_nets [list $ro_net]
    set debug_dict [list \
        $ro_net {AXIS_SIGNALS "Data and Trigger" CLK_SRC "/usp_rf_data_converter_0/clk_adc2" SYSTEM_ILA "Auto" APC_EN "0" } \
    ]
}

foreach net $debug_nets {
    set_property HDL_ATTRIBUTE.DEBUG true $net
}

# The block design already has ILAs, so the one the automation adds has to be
# identified by comparing before and after rather than assumed to be system_ila_0
set ila_filter {VLNV =~ "xilinx.com:ip:system_ila:*"}
set ila_before [get_bd_cells -hierarchical -quiet -filter $ila_filter]

# Autoconnect one ILA to the nets above, in the ADC clock domain
apply_bd_automation -rule xilinx.com:bd_rule:debug -dict $debug_dict

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
if { $has_nn } {
    # probe0 is the raw tProc trigger (clk_dac2), probe1 the resynchronized one
    # that NN_0 sees. Keep 4096 samples (13.3 us) so one capture spans a
    # trigger and the NN_0 prediction write that follows it.
    set_property -dict [list CONFIG.C_MON_TYPE {MIX} CONFIG.C_NUM_OF_PROBES {2} \
        CONFIG.C_DATA_DEPTH {4096}] [get_bd_cells $ila]
    connect_bd_net [get_bd_pins $ila/probe0] $trig_pin
    connect_bd_net [get_bd_pins $ila/probe1] $nn_trig_pin
} else {
    set_property -dict [list CONFIG.C_MON_TYPE {MIX}] [get_bd_cells $ila]
    connect_bd_net [get_bd_pins $ila/probe0] $trig_pin
}

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
