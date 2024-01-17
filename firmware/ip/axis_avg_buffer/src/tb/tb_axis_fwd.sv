module tb_axis_fwd();

	// Number of bits.
	parameter B = 16;

	// Maximum counter value
	parameter LENGTH = 770;

	// Number of clock cycles to wait before counting
	parameter OFFSET = 2;

	// Ports
	logic clk;
	logic rst_n;

	logic           axis_valid_i;
	logic           axis_ready_o;
	logic [2*B-1:0] axis_data_i;

	logic trigger_i;

	logic           fwd_axis_valid_o;
	logic           fwd_axis_ready_i;
	logic [2*B-1:0] fwd_axis_data_o;

	// Local variables
	integer i, j;


	// DUT
	axis_fwd
	#(
	  .B     (B     ),
	  .LENGTH(LENGTH),
	  .OFFSET(OFFSET)
	 )
	DUT
	(
	 // Reset and clock
	 .s_axis_aclk    (clk             ),
	 .s_axis_aresetn (rst_n           ),
	 // AXI-stream input
	 .s_axis_tvalid  (axis_valid_i    ),
	 .s_axis_tready  (axis_ready_o    ),
	 .s_axis_tdata   (axis_data_i     ),
	 // Trigger input
	 .trigger        (trigger_i       ),
	 // AXI-stream output
	 .fwd_axis_tvalid(fwd_axis_valid_o),
	 .fwd_axis_tready(fwd_axis_ready_i),
	 .fwd_axis_tdata (fwd_axis_data_o )
	);

	initial begin
		$dumpfile("axis_fwd.vcd");
		$dumpvars(0, DUT);

		// Reset signals
		rst_n       <= 1'b1;
		trigger_i   <= 1'b0;
		axis_valid_i <= 1'b0;
		axis_valid_i <= 0;
		fwd_axis_ready_i <= 1'b0;

		// Pulse the reset signal (active low)
		#40;
		rst_n       <= 1'b0;
		#40;
		rst_n       <= 1'b1;

		// Ready to received data
		for (i = 0; i < 2; i = i+1)
			@(posedge clk) ;
		fwd_axis_ready_i <= 1'b1;
		for (i = 0; i < 2; i = i+1)
			@(posedge clk) ;

		for (i = 0; i < 10000; i = i + 1) begin
			@(posedge clk);
			if (i % 850 == 0) begin
				trigger_i <= 1'b1;
			end
			if (i % 850 == 1) begin
				trigger_i <= 1'b0;
			end
			wait(axis_ready_o == 1'b1);
			axis_valid_i <= 1'b1;
			axis_data_i <= i;
		end

		// Done, let's go home
		$finish();
	end

	always begin
		clk = 0;
		#5;
		clk = 1;
		#5;
	end

endmodule
