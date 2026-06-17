module charge_integrator#(
    parameter int DATA_WIDTH = 128,
    parameter int K = 12,
    parameter int CNT_WIDTH = 16
)(
    input logic clk,
    input logic rst,
    input logic [DATA_WIDTH-1:0] sample,
    input logic trigger,
    input logic [CNT_WIDTH-1 : 0] window_start,
    input logic [CNT_WIDTH-1 : 0] window_end,
    input logic [DATA_WIDTH-1 : 0] baseline,
    input logic auto_mode,      // 1- baseline estimation, 0 - basline from input
    
    output logic [DATA_WIDTH-1 : 0] charge,
    output logic control        // 1 - start, 0 - done
);

typedef enum logic [1:0]{
    IDLE,
    INTEGRATE
} state_t;

state_t state = IDLE;
logic [CNT_WIDTH-1 : 0] counter = 0;

always_ff @(posedge clk) begin
    if(rst) begin
        charge <= 0;
        control <= 0;
    end else begin
        case(state)
            IDLE: 
            begin
                if(trigger) begin
                    charge <= 0;
                    control <= 1;
                    state <= INTEGRATE;
                end
            end
            INTEGRATE:
            begin
                if(counter >= window_start && counter < window_end) begin
                    if(auto_mode == 0)
                        charge <= charge + (sample - baseline);
                    else
                        charge <= charge + sample;
                end if(counter >= window_end) begin
                    control <= 1;
                    state = IDLE;
                end
                counter <= counter + 1;
            end
        endcase
    end
end

endmodule