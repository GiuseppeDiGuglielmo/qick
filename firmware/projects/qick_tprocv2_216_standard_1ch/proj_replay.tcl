# Create the project with a readout replay buffer (REPLAY=1).
#
# Inserts axis_readout_replay (hdl/axis_readout_replay.v) between the
# readout's decimated output and the broadcaster that feeds the averager, the
# DDR buffer and the NN, inside readout_wrapper:
#
#   axis_dyn_readout_v1_0/m1_axis -> axis_readout_replay_0 -> axis_broadcaster_0
#
# In live mode it passes the readout through (one register later); in replay
# mode it streams stored I/Q samples from a BRAM after each readout trigger
# (tProc port 10; with the NN, the copy nn_trigger_sync_0 resynchronized, so
# the replay lands on the NN window at a fixed offset), so the averager and
# the NN see recorded traces exactly as stored. The PS loads the BRAM through replay_bram_ctrl_0 and sets the player
# through the AXI GPIOs replay_ctrl_0 (mode/reset, shot length and count) and
# replay_ctrl_1 (start delay, status). Register map and use:
# ../../notebooks/qick_ml/readout_replay/README.md.
#
# qick_lib traces the readout stream through known blocks; axis_readout_replay
# is one of them (qick_lib/qick/ip.py trace_back and trace_forward), so
# QickSoc works on these builds.
#
# This is a middle layer of the project scripts:
#
#   proj_ila.tcl            optional readout ILAs (ILA=1)
#     proj_replay.tcl       optional readout replay buffer (REPLAY=1)
#       proj_nn.tcl         optional NN classifier (NN=1)
#         proj_dac.tcl      generator DAC (DAC=228|230)
#           proj.tcl        the design as delivered
#
# The design sources are left untouched; everything here is applied to the
# in-memory block design after the layers below have built it.
#
# Usage (from this directory):
#   REPLAY=1 NN=1 DAC=230 vivado -mode batch -source proj_replay.tcl
#
# The Makefile in ../../tools drives this with "make bitstream REPLAY=1",
# which also runs implementation.

set replay 0
if { [info exists ::env(REPLAY)] && $::env(REPLAY) ne "" } {
    set replay $::env(REPLAY)
}
if { $replay ni {0 1} } {
    error "ERROR: REPLAY must be 0 or 1, got: $replay"
}

if { ![info exists _xil_proj_name_suffix_] } {
    set _xil_proj_name_suffix_ ""
}
# Prepend, so that it lands after the NN part and before the layers above
if { $replay } {
    set _xil_proj_name_suffix_ "_replay${_xil_proj_name_suffix_}"
}

source proj_nn.tcl

if { !$replay } {
    return
}

# Replay BRAM size in bytes (32-bit words): 256 KB = 64K words, e.g. 163 shots
# of 400 samples per load (~57 BRAM36)
set REPLAY_BYTES [expr {256 * 1024}]

# === BEGIN: readout replay ===================================================

open_bd_design "${proj_dir}/${_xil_proj_name_}.srcs/sources_1/bd/d_1/d_1.bd"

# Look up the pins first, so a renamed one fails here and not halfway through
set pins {}
foreach p {
    readout_wrapper/axis_dyn_readout_v1_0/aclk
    readout_wrapper/axis_dyn_readout_v1_0/aresetn
    readout_wrapper/trigger
} {
    set pin [get_bd_pins $p]
    if { [llength $pin] == 0 } {
        error "ERROR: pin $p not found, did the block design change?"
    }
    dict set pins $p $pin
}
set ro_out [get_bd_intf_pins readout_wrapper/axis_dyn_readout_v1_0/m1_axis]
set bc_in  [get_bd_intf_pins readout_wrapper/axis_broadcaster_0/S_AXIS]
if { [llength $ro_out] == 0 || [llength $bc_in] == 0 } {
    error "ERROR: readout output or broadcaster input not found, did the block design change?"
}
set ro_net [get_bd_intf_nets -of_objects $ro_out]
if { [llength $ro_net] != 1 || [get_bd_intf_nets -of_objects $bc_in] ne $ro_net } {
    error "ERROR: expected the readout to feed the broadcaster directly, got: $ro_net"
}

# The player, as a module reference
add_files -norecurse -fileset [get_filesets sources_1] \
    [file normalize "${orig_proj_dir}/hdl/axis_readout_replay.v"]
set_property top d_1_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

current_bd_instance readout_wrapper
create_bd_cell -type module -reference axis_readout_replay axis_readout_replay_0
set_property CONFIG.AW [expr {int(log($REPLAY_BYTES / 4) / log(2) + 0.5)}] [get_bd_cells axis_readout_replay_0]

# BRAM: the PS on port A (replay_bram_ctrl_0), the player on port B
create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 replay_bram_0
set_property -dict [list \
    CONFIG.Memory_Type {True_Dual_Port_RAM} \
    CONFIG.Enable_B {Use_ENB_Pin} \
    CONFIG.Use_RSTB_Pin {true} \
    CONFIG.Port_B_Clock {100} \
    CONFIG.Port_B_Write_Rate {50} \
    CONFIG.Port_B_Enable_Rate {100}] [get_bd_cells replay_bram_0]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 replay_bram_ctrl_0
set_property -dict [list CONFIG.SINGLE_PORT_BRAM {1}] [get_bd_cells replay_bram_ctrl_0]
connect_bd_intf_net [get_bd_intf_pins replay_bram_ctrl_0/BRAM_PORTA] [get_bd_intf_pins replay_bram_0/BRAM_PORTA]
connect_bd_intf_net [get_bd_intf_pins axis_readout_replay_0/BRAM_PORT] [get_bd_intf_pins replay_bram_0/BRAM_PORTB]

# Control: two dual-channel GPIOs, one 32-bit word per channel
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 replay_ctrl_0
set_property -dict [list CONFIG.C_IS_DUAL {1} CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_ALL_OUTPUTS_2 {1} \
    CONFIG.C_GPIO_WIDTH {32} CONFIG.C_GPIO2_WIDTH {32}] [get_bd_cells replay_ctrl_0]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 replay_ctrl_1
set_property -dict [list CONFIG.C_IS_DUAL {1} CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_ALL_INPUTS_2 {1} \
    CONFIG.C_GPIO_WIDTH {32} CONFIG.C_GPIO2_WIDTH {32}] [get_bd_cells replay_ctrl_1]
connect_bd_net [get_bd_pins replay_ctrl_0/gpio_io_o]  [get_bd_pins axis_readout_replay_0/ctrl0]
connect_bd_net [get_bd_pins replay_ctrl_0/gpio2_io_o] [get_bd_pins axis_readout_replay_0/ctrl1]
connect_bd_net [get_bd_pins replay_ctrl_1/gpio_io_o]  [get_bd_pins axis_readout_replay_0/ctrl2]
connect_bd_net [get_bd_pins axis_readout_replay_0/status] [get_bd_pins replay_ctrl_1/gpio2_io_i]

# Splice the player between the readout and the broadcaster. Keep the old
# net name on the readout side, which proj_ila.tcl probes without the NN.
delete_bd_objs $ro_net
connect_bd_intf_net -intf_net axis_dyn_readout_v1_0_m1_axis $ro_out [get_bd_intf_pins axis_readout_replay_0/s_axis]
connect_bd_intf_net [get_bd_intf_pins axis_readout_replay_0/m_axis] $bc_in

# Readout clock and reset
connect_bd_net [dict get $pins readout_wrapper/axis_dyn_readout_v1_0/aclk] [get_bd_pins axis_readout_replay_0/clk]
connect_bd_net [dict get $pins readout_wrapper/axis_dyn_readout_v1_0/aresetn] [get_bd_pins axis_readout_replay_0/aresetn]
current_bd_instance /

# The readout trigger (tProc port 10, clk_dac2). With the NN, take the copy
# that nn_trigger_sync_0 already resynchronized into clk_adc2: two separate
# synchronizers can catch the asynchronous trigger edge one cycle apart (on
# the board, the player's own put ~14% of the shots one sample off the NN
# window), while from one shared copy the player's start and the NN window
# are locked. The player's synchronizer then only adds fixed latency. Without
# the NN, it synchronizes the raw trigger itself.
set nn_sync [get_bd_pins -quiet nn_trigger_sync_0/dout]
if { [llength $nn_sync] } {
    create_bd_pin -dir I readout_wrapper/replay_trigger
    connect_bd_net [get_bd_pins readout_wrapper/replay_trigger] [get_bd_pins readout_wrapper/axis_readout_replay_0/trigger]
    connect_bd_net $nn_sync [get_bd_pins readout_wrapper/replay_trigger]
} else {
    connect_bd_net [dict get $pins readout_wrapper/trigger] [get_bd_pins readout_wrapper/axis_readout_replay_0/trigger]
}

# AXI-Lite and the BRAM controller on the PS interconnect (clocks inferred:
# the PS clock for the AXI side; the player clocks port B itself)
foreach slave {readout_wrapper/replay_bram_ctrl_0/S_AXI readout_wrapper/replay_ctrl_0/S_AXI readout_wrapper/replay_ctrl_1/S_AXI} {
    apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config [list \
        Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} \
        Master {/zynq_ultra_ps_e_0/M_AXI_HPM0_FPD} Slave "/$slave" \
        ddr_seg {Auto} intc_ip {/ps8_0_axi_periph} master_apm {0}] [get_bd_intf_pins $slave]
}

# Fixed addresses in the free space after NN_0 and its prediction buffer
assign_bd_address -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] \
    [get_bd_addr_segs -of_objects [get_bd_intf_pins readout_wrapper/replay_ctrl_0/S_AXI]] \
    -offset 0x0004002D0000 -range 64K -force
assign_bd_address -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] \
    [get_bd_addr_segs -of_objects [get_bd_intf_pins readout_wrapper/replay_ctrl_1/S_AXI]] \
    -offset 0x0004002E0000 -range 64K -force
assign_bd_address -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] \
    [get_bd_addr_segs -of_objects [get_bd_intf_pins readout_wrapper/replay_bram_ctrl_0/S_AXI]] \
    -offset 0x000400400000 -range [expr {$REPLAY_BYTES / 1024}]K -force

validate_bd_design
save_bd_design

# The layers below generated the block design's synthesis products before
# these edits, and Vivado does not mark them stale afterwards, so synthesis
# would read the old netlist. Regenerate them explicitly.
set bd_file [get_files d_1.bd]
reset_target all $bd_file
generate_target all $bd_file

# === END: readout replay =====================================================
