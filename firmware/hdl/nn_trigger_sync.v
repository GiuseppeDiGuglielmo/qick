`timescale 1ns / 1ps
// Synchronize the tProc readout trigger (clk_dac2) into the NN clock domain
// (clk_adc2) before it reaches NN_0/trigger.
//
// NN_0 reads its trigger input unsynchronized into its FSM state and loop
// counters (report_cdc: CDC-1 into 98 flops), which drops pulses and corrupts
// the prediction count. axis_avg_buffer synchronizes the same bit the same way
// (trigger_resync).
//
// The trigger is a level pulse (10 tProc cycles, ~7 clk_adc2 cycles by
// default) and is passed through as a level, not an edge: NN_0 samples it only
// once every 5 clocks while idle, so a 1-cycle pulse could be missed.
module nn_trigger_sync #(
    parameter STAGES = 3
)(
    input  clk,
    input  din,
    output dout
);

(* ASYNC_REG = "TRUE" *) reg [STAGES-1:0] sync_r = {STAGES{1'b0}};

always @(posedge clk)
    sync_r <= {sync_r[STAGES-2:0], din};

assign dout = sync_r[STAGES-1];

endmodule
