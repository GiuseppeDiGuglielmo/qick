`timescale 1 ns / 1 ps
// Testbench for NN_axi (the RTL of the NN IP). Configures the IP over
// AXI-Lite (window_size 400, window_offset 0, scaling_factor from +gain), then for each
// shot pulses the trigger, streams the shot's 400 packed (I,Q) samples and
// prints the BRAM write. The stream source advances only on a TVALID & TREADY
// handshake: this checks the trigger, load, compute and output path, not the
// timing against the free-running ADC stream.
//
// Plusargs: +hex=<file> (one 32-bit word per sample, Q in [31:16], I in [15:0],
// 16-bit two's complement as the readout sends them, 400 words per shot),
// +nshots=<n>, +gain=<scaling_factor> (default 1). Output lines:
//   W shot=<i> cycle=<c> addr=<a> data=<float32 bits, hex>
//   S shot=<i> latency_cycles=<n> consumed=<total samples read so far>
module tb_nn_axi;
    parameter MAXSHOTS = 20;
    parameter SAMPLES = 400;

    reg ap_clk = 0;
    reg ap_rst_n = 0;
    always #1.5 ap_clk = ~ap_clk;   // 3 ns

    reg [31:0] mem [0:MAXSHOTS*SAMPLES-1];
    integer idx = 0;
    wire in_V_V_TREADY;
    wire [31:0] in_V_V_TDATA = mem[idx];
    wire in_V_V_TVALID = 1'b1;

    wire [31:0] out_r_Addr_A, out_r_Din_A;
    wire out_r_EN_A, out_r_Clk_A, out_r_Rst_A;
    wire [3:0] out_r_WEN_A;

    reg trigger = 0;

    reg awvalid = 0, wvalid = 0, arvalid = 0, rready = 1, bready = 1;
    reg [5:0] awaddr = 0, araddr = 0;
    reg [31:0] wdata = 0;
    wire awready, wready, arready, rvalid, bvalid;
    wire [31:0] rdata;
    wire [1:0] rresp, bresp;

    NN_axi dut (
        .ap_clk(ap_clk), .ap_rst_n(ap_rst_n),
        .in_V_V_TDATA(in_V_V_TDATA), .in_V_V_TVALID(in_V_V_TVALID), .in_V_V_TREADY(in_V_V_TREADY),
        .out_r_Addr_A(out_r_Addr_A), .out_r_EN_A(out_r_EN_A), .out_r_WEN_A(out_r_WEN_A),
        .out_r_Din_A(out_r_Din_A), .out_r_Dout_A(32'd0), .out_r_Clk_A(out_r_Clk_A), .out_r_Rst_A(out_r_Rst_A),
        .trigger(trigger),
        .s_axi_config_AWVALID(awvalid), .s_axi_config_AWREADY(awready), .s_axi_config_AWADDR(awaddr),
        .s_axi_config_WVALID(wvalid), .s_axi_config_WREADY(wready), .s_axi_config_WDATA(wdata),
        .s_axi_config_WSTRB(4'hf),
        .s_axi_config_ARVALID(arvalid), .s_axi_config_ARREADY(arready), .s_axi_config_ARADDR(araddr),
        .s_axi_config_RVALID(rvalid), .s_axi_config_RREADY(rready), .s_axi_config_RDATA(rdata),
        .s_axi_config_RRESP(rresp),
        .s_axi_config_BVALID(bvalid), .s_axi_config_BREADY(bready), .s_axi_config_BRESP(bresp));

    // advance the source on each accepted sample
    always @(posedge ap_clk)
        if (in_V_V_TREADY && in_V_V_TVALID) idx <= idx + 1;

    integer cycle = 0;
    always @(posedge ap_clk) cycle <= cycle + 1;

    integer nshot = 0;
    integer nwrites = 0;
    always @(posedge ap_clk)
        if (out_r_EN_A && |out_r_WEN_A) begin
            $display("W shot=%0d cycle=%0d addr=%0d data=%h", nshot, cycle, out_r_Addr_A, out_r_Din_A);
            nwrites <= nwrites + 1;
        end

    // The HLS AXI-Lite slave takes the address first, then the data
    task axi_write(input [5:0] a, input [31:0] d);
        begin
            @(posedge ap_clk); #0.1;
            awaddr = a; awvalid = 1;
            @(posedge ap_clk); while (!awready) @(posedge ap_clk);
            #0.1 awvalid = 0; wdata = d; wvalid = 1;
            @(posedge ap_clk); while (!wready) @(posedge ap_clk);
            #0.1 wvalid = 0;
            @(posedge ap_clk); while (!bvalid) @(posedge ap_clk);
            #0.1;
        end
    endtask

    task axi_read(input [5:0] a, output [31:0] d);
        begin
            @(posedge ap_clk); #0.1;
            araddr = a; arvalid = 1;
            @(posedge ap_clk); while (!arready) @(posedge ap_clk);
            #0.1 arvalid = 0;
            @(posedge ap_clk); while (!rvalid) @(posedge ap_clk);
            d = rdata; #0.1;
        end
    endtask

    integer nshots, gain, target, t0;
    reg [8*512-1:0] hexfile;   // path, up to 512 characters
    reg [31:0] rd;
    initial begin
        if (!$value$plusargs("nshots=%d", nshots)) nshots = 1;
        if (!$value$plusargs("hex=%s", hexfile)) hexfile = "shots.hex";
        if (!$value$plusargs("gain=%d", gain)) gain = 1;
        if (nshots > MAXSHOTS) begin
            $display("ERROR nshots %0d > MAXSHOTS %0d", nshots, MAXSHOTS);
            $finish;
        end
        $readmemh(hexfile, mem);
        repeat (10) @(posedge ap_clk);
        ap_rst_n = 1;
        repeat (10) @(posedge ap_clk);
        axi_write(6'h10, SAMPLES);         // window_size
        axi_write(6'h18, 0);               // window_offset
        axi_write(6'h20, gain);            // scaling_factor
        axi_write(6'h28, 0);               // out_reset
        repeat (20) @(posedge ap_clk);
        for (nshot = 0; nshot < nshots; nshot = nshot + 1) begin
            target = nwrites + 1;
            t0 = cycle;
            @(posedge ap_clk); #0.1 trigger = 1;
            repeat (7) @(posedge ap_clk);
            #0.1 trigger = 0;
            wait (nwrites >= target);
            $display("S shot=%0d latency_cycles=%0d consumed=%0d", nshot, cycle - t0, idx);
            repeat (30) @(posedge ap_clk);
        end
        axi_read(6'h30, rd);
        $display("count register = %0d", rd);
        $finish;
    end

    // watchdog: a shot takes ~430 cycles
    initial begin
        #(3 * 1000 * MAXSHOTS + 30000);
        $display("TIMEOUT");
        $finish;
    end
endmodule
