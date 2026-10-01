`timescale 1ns / 1ps
// Self-checking testbench for axis_readout_replay.v (Icarus Verilog):
//   iverilog -g2012 -P tb_axis_readout_replay.RDLAT=1 -o tb tb_axis_readout_replay.v axis_readout_replay.v && vvp -n tb
// (and RDLAT=2). Prints "PASS" or the first failure; exits via $finish.
//
// The BRAM model holds 0xA0000000 | word index, with a read latency of RDLAT.
// Checks: live mode passes s_axis through one cycle late; replay streams
// exactly shot_len words of the current shot after each trigger, at a fixed
// latency that grows by exactly start_delay, zeros otherwise; shot_index
// advances and wraps at n_shots; index_reset returns to shot 0.
module tb_axis_readout_replay;
    parameter RDLAT = 1;
    localparam AW = 10;

    reg clk = 0;
    always #1.6 clk = ~clk;                // ~307 MHz
    reg aresetn = 0;

    reg  [31:0] s_tdata = 0;
    wire [31:0] m_tdata;
    wire        m_tvalid;
    reg         trigger = 0;
    reg         mode = 0, index_reset = 0;
    reg  [15:0] shot_len = 0, n_shots = 0, start_delay = 0;
    wire [31:0] status;
    wire [15:0] shot_index = status[15:0];
    wire        busy = status[31];
    wire        bram_clk, bram_rst, bram_en;
    wire [3:0]  bram_we;
    wire [31:0] bram_addr, bram_din;
    reg  [31:0] bram_dout = 0;

    axis_readout_replay #(.AW(AW), .RDLAT(RDLAT)) dut (
        .clk(clk), .aresetn(aresetn),
        .s_axis_tdata(s_tdata), .s_axis_tvalid(1'b1),
        .m_axis_tdata(m_tdata), .m_axis_tvalid(m_tvalid),
        .trigger(trigger),
        .ctrl0({30'b0, index_reset, mode}), .ctrl1({n_shots, shot_len}),
        .ctrl2({16'b0, start_delay}), .status(status),
        .bram_clk(bram_clk), .bram_rst(bram_rst), .bram_en(bram_en), .bram_we(bram_we),
        .bram_addr(bram_addr), .bram_din(bram_din), .bram_dout(bram_dout));

    // BRAM model: data RDLAT cycles after the address
    reg [31:0] pipe [0:7];
    integer k;
    always @(posedge clk) begin
        pipe[0] <= bram_en ? (32'hA0000000 | (bram_addr >> 2)) : 32'hDEADBEEF;
        for (k = 1; k < 8; k = k + 1) pipe[k] <= pipe[k-1];
    end
    always @(*) bram_dout = pipe[RDLAT-1];

    integer cycle = 0;
    always @(posedge clk) cycle <= cycle + 1;

    integer errors = 0;
    task fail(input [8*80-1:0] msg);
        begin
            $display("FAIL at cycle %0d: %0s", cycle, msg);
            errors = errors + 1;
        end
    endtask

    // Fire one trigger (7 cycles high, like the tProc's ~10 clk_dac2 cycles)
    // and check the replayed shot: returns its latency from the trigger rise
    task shot(input integer expect_shot, input integer len, output integer latency);
        integer t0, i, first;
        begin
            @(posedge clk); #0.1 trigger = 1; t0 = cycle;
            first = -1;
            // watch the output from the trigger edge on (the replay can start
            // while the trigger is still high); drop the trigger after 7 cycles.
            // Data words are never 0.
            for (i = 0; i < 200 && first < 0; i = i + 1) begin
                @(posedge clk); #0.1;
                if (i == 6) trigger = 0;
                if (m_tdata != 0) first = cycle;
            end
            trigger = 0;
            if (first < 0) fail("no data after trigger");
            latency = first - t0;
            for (i = 0; i < len; i = i + 1) begin
                if (m_tdata !== (32'hA0000000 | (expect_shot * len + i)))
                    begin $display("  word %0d = %h, expected %h", i, m_tdata, 32'hA0000000 | (expect_shot*len+i)); fail("wrong word"); end
                @(posedge clk); #0.1;
            end
            for (i = 0; i < 5; i = i + 1) begin
                if (m_tdata !== 0) fail("nonzero after the shot");
                @(posedge clk); #0.1;
            end
        end
    endtask

    integer lat0, lat, i;
    initial begin
        repeat (5) @(posedge clk);
        aresetn = 1;

        // Live mode: one cycle late
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk); #0.1 s_tdata = 32'h1000 + i;
            if (i > 1 && m_tdata !== 32'h1000 + i - 1) fail("live passthrough");
        end
        // A trigger in live mode must not play anything
        @(posedge clk); #0.1 trigger = 1; repeat (7) @(posedge clk); #0.1 trigger = 0;
        repeat (20) @(posedge clk);
        if (shot_index !== 0) fail("shot index moved in live mode");

        // Replay: 3 shots of 5 words, start_delay 0
        s_tdata = 32'h55555555;              // live data must not leak through
        shot_len = 5; n_shots = 3; start_delay = 0; mode = 1;
        repeat (5) @(posedge clk);
        #0.1 if (m_tdata !== 0) fail("idle replay output not 0");
        shot(0, 5, lat0);
        if (shot_index !== 1) fail("index not 1");
        shot(1, 5, lat); if (lat != lat0) fail("latency changed");
        shot(2, 5, lat); if (lat != lat0) fail("latency changed");
        if (shot_index !== 0) fail("index did not wrap");
        shot(0, 5, lat); if (lat != lat0) fail("latency changed after wrap");
        $display("RDLAT %0d: latency trigger rise -> first word %0d cycles at start_delay 0", RDLAT, lat0);

        // start_delay adds exactly its value
        start_delay = 10; repeat (5) @(posedge clk);
        shot(1, 5, lat); if (lat != lat0 + 10) fail("start_delay not exact");
        $display("RDLAT %0d: latency %0d cycles at start_delay 10", RDLAT, lat);

        // index_reset returns to shot 0
        index_reset = 1; repeat (5) @(posedge clk); index_reset = 0; repeat (5) @(posedge clk);
        if (shot_index !== 0) fail("index_reset");
        start_delay = 0; repeat (5) @(posedge clk);
        shot(0, 5, lat);

        // Longer shots
        shot_len = 400; n_shots = 2; index_reset = 1; repeat (5) @(posedge clk); index_reset = 0; repeat (5) @(posedge clk);
        shot(0, 400, lat); shot(1, 400, lat); shot(0, 400, lat);

        // Back to live
        mode = 0; repeat (5) @(posedge clk);
        @(posedge clk); #0.1 s_tdata = 32'h777;
        @(posedge clk); #0.1;
        if (m_tdata !== 32'h777) fail("back to live");

        if (errors == 0) $display("PASS (RDLAT %0d)", RDLAT);
        $finish;
    end

    initial begin #200000; $display("TIMEOUT"); $finish; end
endmodule
