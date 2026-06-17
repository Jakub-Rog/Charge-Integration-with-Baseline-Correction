module charge_integrator#(
    parameter int DATA_WIDTH = 64,
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

logic [DATA_WIDTH-1:0] sample_comp = 0;
logic [DATA_WIDTH-1:0] baseline_comp = 0;
longint SCALE = 22511000;
logic [DATA_WIDTH-1:0] temp;

dc_compensator #(
    .DATA_WIDTH(DATA_WIDTH),
    .K(K)
)dc_compensator(
    .clk(clk),
    .rst(rst),
    .sample_valid(auto_mode),
    .sample_in(sample),
    .sample_out(sample_comp),
    .baseline_out(baseline_comp)
);

typedef enum logic [1:0]{
    IDLE,
    INTEGRATE
} state_t;

state_t state = IDLE;
logic [CNT_WIDTH-1 : 0] counter = 0;

//always_ff @(posedge clk) begin
//    if(rst) begin
//        charge <= 0;
//        control <= 0;
//    end else begin
//        case(state)
//            IDLE: 
//            begin
//                if(trigger) begin
//                    charge <= 0;
//                    control <= 1;
//                    state <= INTEGRATE;
//                    counter <= 0;
//                end
//            end
//            INTEGRATE:
//            begin
//                if(counter >= window_start && counter < window_end) begin
//                    if(auto_mode == 0)
//                        charge <= charge + (sample - baseline);
//                    else
//                        charge <= ((charge + sample) * SCALE) >> 14;
//                end if(counter >= window_end) begin
//                    control <= 1;
//                    state = IDLE;
//                end
//                counter <= counter + 1;
//            end
//        endcase
//    end
//end

logic signed [127:0] acc;
logic signed [127:0] scaled;

always_ff @(posedge clk) begin
    if (rst) begin
        acc <= 0;
        charge <= 0;
        counter <= 0;
        control <= 0;
        state <= IDLE;
    end else begin
        case(state)

        IDLE: begin
            control <= 0;
            if (trigger) begin
                acc <= 0;
                counter <= 0;
                state <= INTEGRATE;
                control <= 1;
            end
        end

        INTEGRATE: begin

            if (counter >= window_start && counter < window_end) begin
                if (auto_mode == 0)
                    acc <= acc + (sample - baseline);
                else
                    acc <= acc + sample;
            end

            if (counter == window_end) begin
                scaled <= (acc * SCALE) >> 14;
                charge <= scaled;
                control <= 0;
                state <= IDLE;
            end

            counter <= counter + 1;
        end

        endcase
    end
end

endmodule