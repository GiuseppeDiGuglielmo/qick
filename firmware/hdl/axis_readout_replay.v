`timescale 1ns / 1ps
// Readout replay: put stored I/Q samples on the readout output stream in
// place of the live readout, so that the average and decimated buffers and
// the NN downstream see recorded traces (replay_216.tcl, *_replay builds).
//
// Sits between the readout's decimated output (axis_readout_v2_0 m1_axis)
// and the broadcaster that feeds the NN and axis_avg_buffer_0, in
// the readout clock (clk_adc2, one 32-bit I/Q sample per cycle, Q in [31:16],
// I in [15:0]). The output is registered in both modes, so live and replay
// have the same latency (one cycle more than without this block).
//
//   mode 0 (live): m_axis = s_axis, one cycle later.
//   mode 1 (replay): m_axis is 0 except after each trigger rising edge: after
//     start_delay cycles it streams shot_len words of shot shot_index from the
//     BRAM (words shot_index*shot_len ... +shot_len-1), then shot_index
//     increments (wrapping at n_shots).
//
// The BRAM is a blk_mem_gen with the PS on port A (axi_bram_ctrl, byte
// addresses) and this block on port B (byte addresses, read only). RDLAT is
// port B's read latency in cycles.
//
// Control comes from two AXI GPIOs in the PS clock, one 32-bit word per
// channel, and is synchronized here: set it while no shot plays.
//   ctrl0[0] mode (0 live, 1 replay), ctrl0[1] index_reset (holds shot_index
//   at 0 while high); ctrl1 = {n_shots[31:16], shot_len[15:0]};
//   ctrl2[15:0] start_delay; status = {busy, 15'b0, shot_index[15:0]}. The
// trigger (the tProc readout trigger) goes through a 3-flop synchronizer.
// With the NN, replay_216.tcl feeds it the copy nn_trigger_sync already
// resynchronized into clk, so the replay and the NN window are locked; a
// second synchronizer on the raw trigger could catch its edge a cycle apart.
module axis_readout_replay #(
    parameter AW    = 16,   // BRAM depth: 2^AW words
    parameter RDLAT = 1,    // BRAM port B read latency
    parameter SYNC  = 3     // trigger synchronizer stages
)(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axis:m_axis, ASSOCIATED_RESET aresetn" *)
    input              clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input              aresetn,

    // Live readout
    input      [31:0]  s_axis_tdata,
    input              s_axis_tvalid,

    // To the broadcaster (always valid, like the readout)
    output reg [31:0]  m_axis_tdata,
    output             m_axis_tvalid,

    input              trigger,

    // Control (PS clock, quasi-static) and status (readout clock)
    input      [31:0]  ctrl0,
    input      [31:0]  ctrl1,
    input      [31:0]  ctrl2,
    output     [31:0]  status,

    // BRAM port B
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT CLK" *)
    (* X_INTERFACE_PARAMETER = "MASTER_TYPE BRAM_CTRL,MEM_ECC NONE,MEM_WIDTH 32,READ_WRITE_MODE READ_ONLY" *)
    output             bram_clk,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT RST" *)
    output             bram_rst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT EN" *)
    output             bram_en,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT WE" *)
    output     [3:0]   bram_we,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT ADDR" *)
    output     [31:0]  bram_addr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT DIN" *)
    output     [31:0]  bram_din,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 BRAM_PORT DOUT" *)
    input      [31:0]  bram_dout
);

// --- Synchronizers --------------------------------------------------------

(* ASYNC_REG = "TRUE" *) reg [SYNC-1:0] trig_sync = {SYNC{1'b0}};
reg trig_d = 1'b0;
always @(posedge clk) begin
    trig_sync <= {trig_sync[SYNC-2:0], trigger};
    trig_d    <= trig_sync[SYNC-1];
end
wire trig_edge = trig_sync[SYNC-1] & ~trig_d;

(* ASYNC_REG = "TRUE" *) reg [1:0]  mode_s = 2'b0, ireset_s = 2'b0;
(* ASYNC_REG = "TRUE" *) reg [15:0] len_s0 = 0, len_s1 = 0;
(* ASYNC_REG = "TRUE" *) reg [15:0] nsh_s0 = 0, nsh_s1 = 0;
(* ASYNC_REG = "TRUE" *) reg [15:0] dly_s0 = 0, dly_s1 = 0;
always @(posedge clk) begin
    mode_s   <= {mode_s[0], ctrl0[0]};
    ireset_s <= {ireset_s[0], ctrl0[1]};
    len_s0 <= ctrl1[15:0];  len_s1 <= len_s0;
    nsh_s0 <= ctrl1[31:16]; nsh_s1 <= nsh_s0;
    dly_s0 <= ctrl2[15:0];  dly_s1 <= dly_s0;
end
wire        replay   = mode_s[1];
wire        i_reset  = ireset_s[1];
wire [15:0] len_c    = len_s1;
wire [15:0] nshots_c = nsh_s1;
wire [15:0] delay_c  = dly_s1;

// --- Player ---------------------------------------------------------------

localparam IDLE = 2'd0, WAIT = 2'd1, PLAY = 2'd2;
reg [1:0]    state = IDLE;
reg [15:0]   count = 0;          // cycles waited / words played
reg [AW-1:0] base = 0;           // first word of the current shot
reg [AW-1:0] addr = 0;           // next word to read
reg [15:0]   shot_index = 0;

always @(posedge clk) begin
    if (!aresetn) begin
        state <= IDLE; count <= 0;
        base <= 0; shot_index <= 0;
    end else begin
        if (i_reset && state == IDLE) begin
            base <= 0; shot_index <= 0;
        end
        case (state)
            IDLE: if (replay && trig_edge && len_c != 0) begin
                count <= 0;
                state <= (delay_c == 0) ? PLAY : WAIT;
                addr  <= base;
            end
            WAIT: if (count == delay_c - 1) begin
                count <= 0;
                state <= PLAY;
            end else
                count <= count + 1;
            PLAY: begin
                addr <= addr + 1;
                if (count == len_c - 1) begin
                    state <= IDLE;
                    count <= 0;
                    if (shot_index + 1 >= nshots_c) begin
                        shot_index <= 0;
                        base <= 0;
                    end else begin
                        shot_index <= shot_index + 1;
                        base <= base + len_c;
                    end
                end else
                    count <= count + 1;
            end
            default: state <= IDLE;
        endcase
    end
end

// Every PLAY cycle reads the word at addr (then addr advances)
wire issue = (state == PLAY);
assign bram_clk  = clk;
assign bram_rst  = 1'b0;
assign bram_en   = issue;
assign bram_we   = 4'b0;
assign bram_din  = 32'b0;
assign bram_addr = {{(30-AW){1'b0}}, addr, 2'b00};   // byte address

// Data comes back RDLAT cycles after the read was issued
reg [RDLAT-1:0] valid_pipe = {RDLAT{1'b0}};
always @(posedge clk) valid_pipe <= {valid_pipe, issue};   // truncated to RDLAT bits
wire data_valid = valid_pipe[RDLAT-1];

// --- Output mux (registered in both modes) --------------------------------

always @(posedge clk) begin
    if (!replay)
        m_axis_tdata <= s_axis_tdata;
    else
        m_axis_tdata <= data_valid ? bram_dout : 32'b0;
end
assign m_axis_tvalid = 1'b1;
assign status = {(state != IDLE), 15'b0, shot_index};

endmodule
