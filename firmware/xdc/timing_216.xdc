set clk_axi [get_clocks -of_objects [get_nets -of_objects [get_pins d_1_i/usp_rf_data_converter_0/s_axi_aclk]]]

# ADC/DAC
set clk_adc2  [get_clocks -of_objects [get_nets -of_objects [get_pins d_1_i/usp_rf_data_converter_0/clk_adc2]]]
set clk_dac2 [get_clocks -of_objects [get_nets -of_objects [get_pins d_1_i/usp_rf_data_converter_0/clk_dac2]]]

set_clock_group -name clk_axi_to_adc2 -asynchronous \
    -group [get_clocks $clk_axi] \
    -group [get_clocks $clk_adc2]

set_clock_group -name clk_axi_to_dac2 -asynchronous \
    -group [get_clocks $clk_axi] \
    -group [get_clocks $clk_dac2]

set_clock_group -name clk_tproc_to_adc2 -asynchronous \
    -group [get_clocks $clk_dac2] \
    -group [get_clocks $clk_adc2]

set_false_path -from [get_cells d_1_i/axis_set_reg_0/U0/dout_r_reg*]
