# Add the readout replay buffer to the d_1 block design (shared by
# proj_216_nn_replay*.tcl). Source after nn_216.tcl: it splices into the
# readout0 -> broadcaster0 link that nn_216.tcl creates.
#
# Inserts axis_readout_replay (hdl/axis_readout_replay.v) between readout0's
# decimated output and broadcaster0, which feeds NN0 and avg-buffer0:
#
#   axis_readout_v2_0/m1_axis -> axis_readout_replay_0 -> axis_broadcaster_0
#
# In live mode it passes the readout through (one register later); in replay
# mode it streams stored I/Q samples from a BRAM after each readout trigger,
# so avg-buffer0 and NN0 see recorded traces exactly as stored. The PS loads
# the BRAM through replay_bram_ctrl_0 and sets the player through the AXI
# GPIOs replay_ctrl_0 (mode/reset, shot length and count) and replay_ctrl_1
# (start delay, status). Register map and use:
# ../qick_ml/readout_replay/README.md.
#
# qick_lib traces the readout stream through known blocks; axis_readout_replay
# is one of them (qick_lib/qick/ip.py trace_back and trace_forward), so
# QickSoc works on these builds.

# Replay BRAM size in bytes (32-bit words): 256 KB = 64K words, e.g. 163 shots
# of 400 samples per load (~57 BRAM36)
set REPLAY_BYTES [expr {256 * 1024}]

# === BEGIN: readout replay ===================================================

open_bd_design "${proj_dir}/top_216.srcs/sources_1/bd/d_1/d_1.bd"

# Look up the pins first, so a renamed one fails here and not halfway through
set pins {}
foreach p {
    usp_rf_data_converter_0/clk_adc2
    rst_adc2/peripheral_aresetn
    nn_trigger_sync_0/dout
} {
    set pin [get_bd_pins $p]
    if { [llength $pin] == 0 } {
        error "ERROR: pin $p not found, did the block design change (source after nn_216.tcl)?"
    }
    dict set pins $p $pin
}
set ro_out [get_bd_intf_pins axis_readout_v2_0/m1_axis]
set bc_in  [get_bd_intf_pins axis_broadcaster_0/S_AXIS]
if { [llength $ro_out] == 0 || [llength $bc_in] == 0 } {
    error "ERROR: readout0 output or broadcaster0 input not found (source after nn_216.tcl)"
}
set ro_net [get_bd_intf_nets -of_objects $ro_out]
if { [llength $ro_net] != 1 || [get_bd_intf_nets -of_objects $bc_in] ne $ro_net } {
    error "ERROR: expected readout0 to feed broadcaster0 directly, got: $ro_net"
}

# The player, as a module reference (like nn_trigger_sync in nn_216.tcl)
add_files -norecurse -fileset [get_filesets sources_1] \
    [file normalize "${orig_proj_dir}/hdl/axis_readout_replay.v"]
update_compile_order -fileset sources_1
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

# Splice the player between readout0 and broadcaster0. Keep the old net name
# on the readout side. The player's m_axis has no tready, so broadcaster0
# loses its m_axis_tready pins: drop always_ready0 (nn_216.tcl), which ties
# them high, or generation fails on the dangling net ("Failed to find BusTerm
# object /axis_broadcaster_0/m_axis_tready"). Without tready nothing
# downstream can back-pressure the stream, as before.
set rdy [get_bd_cells always_ready0]
if { [llength $rdy] != 1 } {
    error "ERROR: always_ready0 not found, did nn_216.tcl change?"
}
delete_bd_objs [get_bd_nets -of_objects [get_bd_pins always_ready0/dout]] $rdy
delete_bd_objs $ro_net
connect_bd_intf_net -intf_net axis_readout_v2_0_m1_axis $ro_out [get_bd_intf_pins axis_readout_replay_0/s_axis]
connect_bd_intf_net [get_bd_intf_pins axis_readout_replay_0/m_axis] $bc_in

# Clock/reset from the ADC2 domain, like readout0
connect_bd_net [dict get $pins usp_rf_data_converter_0/clk_adc2] [get_bd_pins axis_readout_replay_0/clk]
connect_bd_net [dict get $pins rst_adc2/peripheral_aresetn] [get_bd_pins axis_readout_replay_0/aresetn]

# The readout trigger (tProc output 0 pin 8, clk_dac2), as the copy that
# nn_trigger_sync_0 already resynchronized into clk_adc2: two separate
# synchronizers can catch the asynchronous trigger edge one cycle apart (on
# the tProc v2 branch the player's own put ~14% of the shots one sample off
# the NN window), while from one shared copy the player's start and the NN
# window are locked. The player's synchronizer then only adds fixed latency.
connect_bd_net [dict get $pins nn_trigger_sync_0/dout] [get_bd_pins axis_readout_replay_0/trigger]

# AXI-Lite and the BRAM controller on the PS interconnect (clocks inferred:
# the PS clock for the AXI side; the player clocks port B itself)
foreach slave {replay_bram_ctrl_0/S_AXI replay_ctrl_0/S_AXI replay_ctrl_1/S_AXI} {
    apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config [list \
        Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} \
        Master {/zynq_ultra_ps_e_0/M_AXI_HPM0_FPD} Slave "/$slave" \
        ddr_seg {Auto} intc_ip {/ps8_0_axi_periph} master_apm {0}] [get_bd_intf_pins $slave]
}

# Fixed addresses in free space: the GPIOs after NN_0 (0xA0010000, 64K), the
# BRAM after the prediction buffer (0xA0300000, 128K)
assign_bd_address -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] \
    [get_bd_addr_segs -of_objects [get_bd_intf_pins replay_ctrl_0/S_AXI]] \
    -offset 0xA0020000 -range 64K -force
assign_bd_address -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] \
    [get_bd_addr_segs -of_objects [get_bd_intf_pins replay_ctrl_1/S_AXI]] \
    -offset 0xA0030000 -range 64K -force
assign_bd_address -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] \
    [get_bd_addr_segs -of_objects [get_bd_intf_pins replay_bram_ctrl_0/S_AXI]] \
    -offset 0xA0400000 -range [expr {$REPLAY_BYTES / 1024}]K -force

validate_bd_design
save_bd_design
# === END: readout replay =====================================================
