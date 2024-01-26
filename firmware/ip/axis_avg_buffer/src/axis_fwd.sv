module axis_fwd
    #(parameter B = 16, LENGTH = 770, OFFSET = 2)
    (
        input   logic               s_axis_aclk,
        input   logic               s_axis_aresetn,

        input   logic               s_axis_tvalid,
        output  logic               s_axis_tready,
        input   logic   [2*B-1:0]   s_axis_tdata,

        input   logic               trigger,

        output  logic               fwd_axis_tvalid,
        input   logic               fwd_axis_tready,
        output  logic   [2*B-1:0]   fwd_axis_tdata
    );

    logic valid;

    data_counter #(  .LENGTH(LENGTH), .OFFSET(OFFSET)   ) data_counter_i (
        .clk(s_axis_aclk),
        .rst_n(s_axis_aresetn),
        .trigger(trigger),
        .valid(valid)
    );

    assign fwd_axis_tvalid = s_axis_tvalid && valid;
    assign fwd_axis_tdata = s_axis_tdata;
    // assign s_axis_tready = fwd_axis_tready;

endmodule

module data_counter #(
    parameter LENGTH = 770, // Maximum counter value
    parameter OFFSET = 2    // Number of clock cycles to wait before counting
) (
    input  logic clk,      // Clock
    input  logic rst_n,    // Active low reset
    input  logic trigger,  // Trigger signal
    output logic valid     // Valid signal
);

    // Define the states for the FSM
    typedef enum logic [2:0] {
        IDLE     = 3'b000,
        WAITING  = 3'b001,
        COUNTING = 3'b010
    } state_t;

    state_t current_state, next_state;
    logic [$clog2(LENGTH):0] counter; // Counter up to LENGTH value
    logic [$clog2(OFFSET):0] wait_counter; // Wait counter

    // FSM state transition and output logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // Datapath: Counter logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 0;
            wait_counter <= 0;
        end else begin
            case(next_state)
                IDLE: begin
                    counter <= 0;
                    wait_counter <= 0;
                end
                WAITING: begin
                    wait_counter <= wait_counter + 1;
                end
                COUNTING: begin
                    if (counter < LENGTH) begin
                        counter <= counter + 1;
                    end
                end
            endcase
        end
    end

    // Next state logic
    always_comb begin
        case(current_state)
            IDLE: begin
                if (trigger) begin
                    next_state = WAITING;
                end else begin
                    next_state = IDLE;
                end
            end
            WAITING: begin
                if (wait_counter >= OFFSET) begin
                    next_state = COUNTING;
                end else begin
                    next_state = WAITING;
                end
            end
            COUNTING: begin
                if (counter >= LENGTH) begin
                    next_state = IDLE;
                end else begin
                    next_state = COUNTING;
                end
            end
        endcase
    end

    // FSM output logic
    always_comb begin
        valid = (current_state == COUNTING);
    end

endmodule
