# Create the project with the generator on a chosen DAC.
#
# The delivered block design drives its one generator out of DAC tile 0 blk 0
# (0_228 on JHC1, QICK box DAC port 0). DAC=230 moves it to DAC tile 2 blk 0
# (0_230 on JHC3, QICK box DAC port 8), the port the tProc v1 designs used, so a
# bench wired for those works unchanged.
#
#   DAC=228  (default) the design as delivered, built into top_dac228/
#   DAC=230  generator on 0_230, built into top_dac230/
#
# This is the middle layer of the project scripts:
#
#   proj_ila.tcl    optional readout ILAs (ILA=1)
#     proj_dac.tcl  generator DAC (DAC=228|230)
#       proj.tcl    the design as delivered
#
# The design sources are left untouched; everything here is applied to the
# in-memory block design after proj.tcl has built it.
#
# Usage (from this directory):
#   DAC=230 vivado -mode batch -source proj_dac.tcl
#
# The Makefile in ../../tools drives this with "make bitstream DAC=230", which
# also runs implementation.

set dac 228
if { [info exists ::env(DAC)] && $::env(DAC) ne "" } {
    set dac $::env(DAC)
}
if { $dac ni {228 230} } {
    error "ERROR: DAC must be 228 or 230, got: $dac"
}

if { ![info exists _xil_proj_name_suffix_] } {
    set _xil_proj_name_suffix_ ""
}
# Prepend, so that layers above append their own part after this one. Both DACs
# get a suffix, so every build of this design names its DAC.
set _xil_proj_name_suffix_ "_dac${dac}${_xil_proj_name_suffix_}"

source proj.tcl

if { $dac == 228 } {
    return
}

# === BEGIN: generator on DAC 0_230 ===========================================

open_bd_design "${proj_dir}/${_xil_proj_name_}.srcs/sources_1/bd/d_1/d_1.bd"

set rfdc [get_bd_cells usp_rf_data_converter_0]
set sg   [get_bd_cells signal_gen_wrapper]
set rst  [get_bd_cells clk_rst_wrapper]
foreach {name obj} [list usp_rf_data_converter_0 $rfdc signal_gen_wrapper $sg clk_rst_wrapper $rst] {
    if { [llength $obj] == 0 } {
        error "ERROR: $name not found, did the block design change?"
    }
}

# DAC tile 2 carried interpolating generators upstream. Put it in the same
# full-rate direct mode as tile 0 (no interpolation, 16 samples per fabric
# clock, coarse mixer bypassed), which is what axis_signal_gen_v6 drives:
# 6881.28 Msps over the 430.08 MHz clk_dac2, as in the tProc v1 designs. The
# four slices share s2_axis_aclk, so all of them get the same data rate; they
# stay enabled so vout8..11 remain connected.
set dac_cfg {}
foreach blk {20 21 22 23} {
    lappend dac_cfg \
        CONFIG.DAC_Interpolation_Mode$blk {1} \
        CONFIG.DAC_Data_Width$blk         {16} \
        CONFIG.DAC_Mixer_Type$blk         {1} \
        CONFIG.DAC_Mixer_Mode$blk         {2} \
        CONFIG.DAC_Coarse_Mixer_Freq$blk  {3} \
        CONFIG.DAC_Mode$blk               {3}
}
set_property -dict $dac_cfg $rfdc

# Look up the pins first, so a renamed one fails here and not halfway through
set pins {}
foreach p {
    usp_rf_data_converter_0/s00_axis
    usp_rf_data_converter_0/s20_axis
    signal_gen_wrapper/m_axis
} {
    set pin [get_bd_intf_pins $p]
    if { [llength $pin] == 0 } {
        error "ERROR: interface pin $p not found, did the block design change?"
    }
    dict set pins $p $pin
}
foreach p {
    usp_rf_data_converter_0/clk_dac2
    signal_gen_wrapper/aclk
    signal_gen_wrapper/aresetn
    clk_rst_wrapper/peripheral_aresetn4
} {
    set pin [get_bd_pins $p]
    if { [llength $pin] == 0 } {
        error "ERROR: pin $p not found, did the block design change?"
    }
    dict set pins $p $pin
}

# Data: generator output from DAC 0_228 (s00_axis) to DAC 0_230 (s20_axis).
# The net is looked up from the pin because signal_gen_wrapper has an inner net
# of the same name.
set sg_net [get_bd_intf_nets -of_objects [dict get $pins usp_rf_data_converter_0/s00_axis]]
if { [llength $sg_net] != 1 } {
    error "ERROR: expected one net on usp_rf_data_converter_0/s00_axis, got: $sg_net"
}
delete_bd_objs $sg_net
connect_bd_intf_net [dict get $pins signal_gen_wrapper/m_axis] [dict get $pins usp_rf_data_converter_0/s20_axis]

# Clock and reset: the generator side of signal_gen_wrapper moves from the
# DAC tile 0 domain (clk_dac0, rst_dac0) to the DAC tile 2 domain (clk_dac2,
# rst_dac2). Its aclk1 input, the tProc side of the CDC, is already on clk_dac2.
foreach {pin new_src} {
    signal_gen_wrapper/aclk     usp_rf_data_converter_0/clk_dac2
    signal_gen_wrapper/aresetn  clk_rst_wrapper/peripheral_aresetn4
} {
    set old_net [get_bd_nets -of_objects [dict get $pins $pin]]
    if { [llength $old_net] == 1 } {
        disconnect_bd_net $old_net [dict get $pins $pin]
    }
    connect_bd_net [dict get $pins $new_src] [dict get $pins $pin]
}

validate_bd_design
save_bd_design

# proj.tcl generated the block design's synthesis products before these edits,
# and Vivado does not mark them stale afterwards, so synthesis would read the
# old netlist. Regenerate them explicitly.
set bd_file [get_files d_1.bd]
reset_target all $bd_file
generate_target all $bd_file

# === END: generator on DAC 0_230 =============================================
