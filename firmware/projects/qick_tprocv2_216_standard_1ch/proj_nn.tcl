# Create the project with the NN readout classifier on readout 0.
#
# Adds the hls4ml classifier (xilinx.com:hls:NN_axi:1.0, see
# ../../notebooks/qick_ml/ip/README.md) next to the averager buffer:
#
#   - readout 0 stream -> a third output of readout_wrapper/axis_broadcaster_0
#     -> NN_0/in_V_V (the averager and DDR buffer paths are left as they are)
#   - tProc trigger port 10 (the averager's trigger) -> nn_trigger_sync_0
#     (hdl/nn_trigger_sync.v, clk_dac2 to clk_adc2) -> NN_0/trigger
#   - NN_0 writes one logit per pulse to blk_bram_0, which the PS reads
#     through axi_blk_bram_ctrl_0
#
# NN_0 and axi_blk_bram_ctrl_0 are the cell names used by
# ../../notebooks/qick_ml/qick_ml_lib.py.
#
# This is a middle layer of the project scripts:
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
#   NN=1 DAC=230 vivado -mode batch -source proj_nn.tcl
#
# The Makefile in ../../tools drives this with "make bitstream NN=1", which
# also runs implementation.

set nn 0
if { [info exists ::env(NN)] && $::env(NN) ne "" } {
    set nn $::env(NN)
}
if { $nn ni {0 1} } {
    error "ERROR: NN must be 0 or 1, got: $nn"
}

if { ![info exists _xil_proj_name_suffix_] } {
    set _xil_proj_name_suffix_ ""
}
# Prepend, so that it lands after the DAC part and before the layers above
if { $nn } {
    set _xil_proj_name_suffix_ "_nn${_xil_proj_name_suffix_}"
}

source proj_dac.tcl

if { !$nn } {
    return
}

# === BEGIN: NN IP ============================================================

# Choose the NN IP (see ../../notebooks/qick_ml/ip/README.md)
set DATASET_DATE "20240528"
set MODEL_NAME "_l2"
set WINDOW_SIZE 400
set WINDOW_START 100
set MODEL_VARIANT "_ternary_h4"
set NN_IP_ZIP "[file normalize "${orig_proj_dir}/../../notebooks/qick_ml/ip/${DATASET_DATE}/xilinx_com_hls_NN_axi_1_0_nonregistered${MODEL_NAME}_w${WINDOW_SIZE}${MODEL_VARIANT}_s${WINDOW_START}.zip"]"
if { ![file exists $NN_IP_ZIP] } {
    error "ERROR: NN IP not found: $NN_IP_ZIP"
}

# Unpack the NN IP into a local repo inside the project dir (removed with it)
set LOCAL_IPS_PATH "${proj_dir}/${_xil_proj_name_}.ip_local"
file mkdir $LOCAL_IPS_PATH
set obj [get_filesets sources_1]
set_property "ip_repo_paths" [concat [get_property "ip_repo_paths" $obj] $LOCAL_IPS_PATH] $obj
update_ip_catalog -rebuild
update_ip_catalog -add_ip $NN_IP_ZIP -repo_path $LOCAL_IPS_PATH

# === END: NN IP ==============================================================

# === BEGIN: NN ===============================================================

open_bd_design "${proj_dir}/${_xil_proj_name_}.srcs/sources_1/bd/d_1/d_1.bd"

# Look up the pins first, so a renamed one fails here and not halfway through
set pins {}
foreach p {
    qick_processor_0/trig_10_o
    readout_wrapper/axis_avg_buffer_0/trigger
    usp_rf_data_converter_0/clk_adc2
    clk_rst_wrapper/peripheral_aresetn1
} {
    set pin [get_bd_pins $p]
    if { [llength $pin] == 0 } {
        error "ERROR: pin $p not found, did the block design change?"
    }
    dict set pins $p $pin
}
set bc [get_bd_cells readout_wrapper/axis_broadcaster_0]
if { [llength $bc] == 0 } {
    error "ERROR: readout_wrapper/axis_broadcaster_0 not found, did the block design change?"
}
if { [get_property CONFIG.NUM_MI $bc] != 2 } {
    error "ERROR: expected readout_wrapper/axis_broadcaster_0 with 2 outputs, got: [get_property CONFIG.NUM_MI $bc]"
}
# The NN must see the same trigger as the averager
set trig_net [get_bd_nets -of_objects [dict get $pins qick_processor_0/trig_10_o]]
set avg_trig_net [get_bd_nets -of_objects [dict get $pins readout_wrapper/axis_avg_buffer_0/trigger]]
if { [llength $trig_net] != 1 || [llength $avg_trig_net] != 1 } {
    error "ERROR: tProc trigger 10 is not connected to the averager trigger, did the block design change?"
}

# NN0 (cell name used by qick_ml_lib.py)
create_bd_cell -type ip -vlnv xilinx.com:hls:NN_axi:1.0 NN_0

# Readout0 to NN0: a third output on the broadcaster that already splits
# readout0 between the averager (M00) and the DDR buffer (M01). It has no
# tready, so NN0 cannot back-pressure the readout.
set_property CONFIG.NUM_MI {3} $bc
current_bd_instance readout_wrapper
create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 M02_AXIS
current_bd_instance /
connect_bd_intf_net [get_bd_intf_pins readout_wrapper/axis_broadcaster_0/M02_AXIS] [get_bd_intf_pins readout_wrapper/M02_AXIS]
connect_bd_intf_net [get_bd_intf_pins readout_wrapper/M02_AXIS] [get_bd_intf_pins NN_0/in_V_V]

# NN0 starts a window on the same tProc trigger as the averager. The trigger
# comes from the tProc timing domain (clk_dac2), so resynchronize it into
# clk_adc2 first, like the averager does internally (see hdl/nn_trigger_sync.v)
add_files -norecurse -fileset [get_filesets sources_1] \
    [file normalize "${orig_proj_dir}/hdl/nn_trigger_sync.v"]
set_property top d_1_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1
create_bd_cell -type module -reference nn_trigger_sync nn_trigger_sync_0
connect_bd_net [dict get $pins qick_processor_0/trig_10_o] [get_bd_pins nn_trigger_sync_0/din]
connect_bd_net [get_bd_pins nn_trigger_sync_0/dout] [get_bd_pins NN_0/trigger]

# Clock/reset NN0 and the synchronizer from the ADC2 domain, like readout0
connect_bd_net [dict get $pins usp_rf_data_converter_0/clk_adc2] \
    [get_bd_pins NN_0/ap_clk] [get_bd_pins nn_trigger_sync_0/clk]
connect_bd_net [dict get $pins clk_rst_wrapper/peripheral_aresetn1] [get_bd_pins NN_0/ap_rst_n]

# NN0 config registers on the PS interconnect (clocks inferred from the
# existing connections)
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { \
    Clk_master {Auto} \
    Clk_slave {Auto} \
    Clk_xbar {Auto} \
    Master {/zynq_ultra_ps_e_0/M_AXI_HPM0_FPD} \
    Slave {/NN_0/s_axi_config} \
    ddr_seg {Auto} \
    intc_ip {/ps8_0_axi_periph} \
    master_apm {0}} [get_bd_intf_pins NN_0/s_axi_config]

# Prediction buffer: NN0 writes port B, the PS reads port A
create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:8.4 blk_bram_0
set_property -dict [list \
    CONFIG.Memory_Type {True_Dual_Port_RAM} \
    CONFIG.Enable_B {Use_ENB_Pin} \
    CONFIG.Use_RSTB_Pin {true} \
    CONFIG.Port_B_Clock {100} \
    CONFIG.Port_B_Write_Rate {50} \
    CONFIG.Port_B_Enable_Rate {100}] [get_bd_cells blk_bram_0]
connect_bd_intf_net [get_bd_intf_pins NN_0/out_r_PORTA] [get_bd_intf_pins blk_bram_0/BRAM_PORTB]

# PS access to the prediction buffer (cell name used by qick_ml_lib.py)
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 axi_blk_bram_ctrl_0
set_property -dict [list CONFIG.SINGLE_PORT_BRAM {1}] [get_bd_cells axi_blk_bram_ctrl_0]
connect_bd_intf_net [get_bd_intf_pins axi_blk_bram_ctrl_0/BRAM_PORTA] [get_bd_intf_pins blk_bram_0/BRAM_PORTA]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { \
    Clk_master {Auto} \
    Clk_slave {Auto} \
    Clk_xbar {Auto} \
    Master {/zynq_ultra_ps_e_0/M_AXI_HPM0_FPD} \
    Slave {/axi_blk_bram_ctrl_0/S_AXI} \
    ddr_seg {Auto} \
    intc_ip {/ps8_0_axi_periph} \
    master_apm {0}} [get_bd_intf_pins axi_blk_bram_ctrl_0/S_AXI]

# Fixed addresses in the free space after usp_rf_data_converter_0
# (0x4_0028_0000, 256K): NN0 registers at 0x4_002C_0000 (64K), the prediction
# buffer at 0x4_0030_0000 (128K). The notebook finds both through the HWH file.
assign_bd_address -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] \
    [get_bd_addr_segs -of_objects [get_bd_intf_pins NN_0/s_axi_config]] \
    -offset 0x0004002C0000 -range 64K -force
assign_bd_address -target_address_space [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] \
    [get_bd_addr_segs -of_objects [get_bd_intf_pins axi_blk_bram_ctrl_0/S_AXI]] \
    -offset 0x000400300000 -range 128K -force

validate_bd_design
save_bd_design

# proj.tcl generated the block design's synthesis products before these edits,
# and Vivado does not mark them stale afterwards, so synthesis would read the
# old netlist. Regenerate them explicitly.
set bd_file [get_files d_1.bd]
reset_target all $bd_file
generate_target all $bd_file

# === END: NN =================================================================

# Close timing on RFADC2_CLK with NN_0 in the design. On the tProc v1 branches
# (Vivado 2022.1 and 2023.1) the NN builds missed by a few tens of ps with the
# default strategy and met timing with Explore directives in every step plus
# aggressive post-route physical optimization; not yet checked on this design.
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
