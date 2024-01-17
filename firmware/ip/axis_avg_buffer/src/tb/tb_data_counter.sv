module tb_data_counter();

	// Maximum counter value
	parameter LENGTH = 770;

	// Number of clock cycles to wait before counting
	parameter OFFSET = 2;

	// Ports
	logic clk;
	logic rst_n;

	logic trigger_i;

	logic valid_o;

	// Local variables
	integer i, j;

	// DUT
	data_counter
	#(
	  .LENGTH (LENGTH),
	  .OFFSET (OFFSET)
	 )
	DUT
	(
	 // Reset and clock.
	 .rst_n (rst_n),
	 .clk   (clk  ),

	 // Trigger input.
	 .trigger (trigger_i),

	 // Valid output.
	 .valid (valid_o)
	);

	initial begin

		$dumpfile("data_counter.vcd");
		$dumpvars(0, DUT);

		// Reset signals
		rst_n       <= 1'b1;
		trigger_i   <= 1'b0;

		// Pulse the reset signal (active low)
		#40;
		rst_n       <= 1'b0;
		#40;

		// De-assert the reset signal
		rst_n       <= 1'b1;

		for (j = 0; j < 10; j = j+1)
		begin
			// Pulse the trigger signal
			for (i = 0; i < 2; i = i+1)
				@(posedge clk) ;
			trigger_i <= 1'b1;
			for (i = 0; i < 2; i = i+1)
				@(posedge clk) ;
			trigger_i <= 1'b0;

			// Wait for the valid signal going down (it should be about LENGTH
			// clock cycles)
			@(negedge valid_o);
		end

		$finish();
	end

	always begin
		clk = 0;
		#5;
		clk = 1;
		#5;
	end

endmodule
