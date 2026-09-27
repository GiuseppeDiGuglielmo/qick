# Add the NN IP to the d_1 block design (shared by proj_216_nn*.tcl)
# Source after proj_216.tcl, which sets orig_proj_dir, proj_dir and _xil_proj_name_

# === BEGIN: NN IP ============================================================

# Choose the NN IP (see ../qick_ml/ip/README.md)
set DATASET_DATE "20240528"
set MODEL_NAME "_l2"
set WINDOW_SIZE 400
set WINDOW_START 100
set MODEL_VARIANT "_ternary_h4"
set NN_IP_ZIP "[file normalize "${orig_proj_dir}/../qick_ml/ip/${DATASET_DATE}/xilinx_com_hls_NN_axi_1_0_nonregistered${MODEL_NAME}_w${WINDOW_SIZE}${MODEL_VARIANT}_s${WINDOW_START}.zip"]"

# Unpack the NN IP into a local repo inside the project dir (removed with it)
set LOCAL_IPS_PATH "${proj_dir}/${_xil_proj_name_}.ip_local"
file mkdir $LOCAL_IPS_PATH
set obj [get_filesets sources_1]
set_property "ip_repo_paths" [concat [get_property "ip_repo_paths" $obj] $LOCAL_IPS_PATH] $obj
update_ip_catalog -rebuild
update_ip_catalog -add_ip $NN_IP_ZIP -repo_path $LOCAL_IPS_PATH

# === END: NN IP ==============================================================

# === BEGIN: NN ===============================================================

# Open block diagram
open_bd_design "${proj_dir}/top_216.srcs/sources_1/bd/d_1/d_1.bd"

# NN0 (cell name used by qick_ml/qick_ml_lib.py)
create_bd_cell -type ip -vlnv xilinx.com:hls:NN_axi:1.0 NN_0

# Broadcaster0 splits readout0 between avg-buffer0 and NN0
create_bd_cell -type ip -vlnv xilinx.com:ip:axis_broadcaster:1.1 axis_broadcaster_0

# Rewire readout0 -> broadcaster0 -> {NN0, avg-buffer0}
delete_bd_objs [get_bd_intf_nets axis_readout_v2_0_m1_axis]
connect_bd_intf_net [get_bd_intf_pins axis_readout_v2_0/m1_axis] [get_bd_intf_pins axis_broadcaster_0/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins axis_broadcaster_0/M00_AXIS] [get_bd_intf_pins NN_0/in_V_V]
connect_bd_intf_net [get_bd_intf_pins axis_broadcaster_0/M01_AXIS] [get_bd_intf_pins axis_avg_buffer_0/s_axis]

# Tie broadcaster0 ready high so NN0 never back-pressures readout0/avg-buffer0
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 always_ready0
set_property -dict [list CONFIG.CONST_WIDTH {2} CONFIG.CONST_VAL {3}] [get_bd_cells always_ready0]
connect_bd_net [get_bd_pins always_ready0/dout] [get_bd_pins axis_broadcaster_0/m_axis_tready]

# NN0 starts a window on the same tProc trigger as avg-buffer0. The trigger
# comes from the tProc domain (clk_dac2), so resynchronize it into clk_adc2
# first, like avg-buffer0 does internally (see hdl/nn_trigger_sync.v)
add_files -norecurse -fileset [get_filesets sources_1] \
    [file normalize "${orig_proj_dir}/hdl/nn_trigger_sync.v"]
update_compile_order -fileset sources_1
create_bd_cell -type module -reference nn_trigger_sync nn_trigger_sync_0
connect_bd_net [get_bd_pins vect2bits_16_0/dout8] [get_bd_pins nn_trigger_sync_0/din]
connect_bd_net [get_bd_pins nn_trigger_sync_0/dout] [get_bd_pins NN_0/trigger]

# Clock/reset NN0 and broadcaster0 from the ADC2 domain, like readout0
connect_bd_net [get_bd_pins usp_rf_data_converter_0/clk_adc2] \
    [get_bd_pins NN_0/ap_clk] [get_bd_pins axis_broadcaster_0/aclk] \
    [get_bd_pins nn_trigger_sync_0/clk]
connect_bd_net [get_bd_pins rst_adc2/peripheral_aresetn] \
    [get_bd_pins NN_0/ap_rst_n] [get_bd_pins axis_broadcaster_0/aresetn]

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

# PS access to the prediction buffer (cell name used by qick_ml/qick_ml_lib.py)
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

# Place the prediction buffer at 0xA0300000 (128K), clear of axi_bram_ctrl_0
set_property offset 0x00A0300000 [get_bd_addr_segs {zynq_ultra_ps_e_0/Data/SEG_axi_blk_bram_ctrl_0_Mem0}]
set_property range 128K [get_bd_addr_segs {zynq_ultra_ps_e_0/Data/SEG_axi_blk_bram_ctrl_0_Mem0}]

validate_bd_design
save_bd_design
# === END: NN =================================================================
