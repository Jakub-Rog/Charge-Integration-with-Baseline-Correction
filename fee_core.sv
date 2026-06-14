`timescale 1ns / 1ps

/**
 * FEE (Front-End Electronics) Core Module
 * Performs charge integration with baseline correction
 * 
 * Features:
 *  - Configurable integration window (sample-based)
 *  - Automatic or manual baseline mode
 *  - Charge accumulation with saturation
 *  - Baseline estimation output
 *  - Control: start/done handshake
 */

module fee_core #(
    parameter int DATA_WIDTH = 14,
    parameter int CHARGE_WIDTH = 32,  // Accumulator for charge (wider than DATA_WIDTH)
    parameter int K = 12,              // IIR filter parameter
    parameter int FRAC_WIDTH = 10,     // Q-notation fractional bits
    parameter bit USE_FLOAT = 0        // 0 = fixed-point (synthesis), 1 = float (sim)
)(
    input logic clk,
    input logic rst,
    
    // Control interface
    input logic start,                 // Start integration
    output logic done,                 // Integration complete
    
    // Data input
    input logic sample_valid,
    input logic [DATA_WIDTH-1:0] sample_in,
    
    // Configuration registers
    input logic [31:0] window_start,   // Start sample index
    input logic [31:0] window_end,     // End sample index
    input logic [31:0] baseline_manual, // Manual baseline value (Q-notation)
    input logic baseline_auto_en,      // 1 = auto baseline, 0 = manual
    
    // Output data
    output logic [CHARGE_WIDTH-1:0] charge_out,
    output logic signed [DATA_WIDTH-1:0] baseline_out,
    output logic charge_valid
);

    // ===========================
    // Internal signals
    // ===========================
    
    // Baseline correction module
    logic [DATA_WIDTH-1:0] sample_corrected;
    logic signed [DATA_WIDTH-1:0] baseline_dc;
    
    // State machine
    typedef enum logic [2:0] {
        IDLE,
        WAIT_START_SAMPLE,
        INTEGRATING,
        WAIT_END_SAMPLE,
        OUTPUT_READY,
        DONE
    } state_t;
    
    state_t state, state_next;
    
    // Counters and accumulators
    logic [31:0] sample_count;
    logic [CHARGE_WIDTH-1:0] charge_acc;
    logic [CHARGE_WIDTH-1:0] charge_acc_next;
    
    // Baseline estimation (separate from DC compensator)
    logic signed [DATA_WIDTH+16:0] baseline_est;
    logic signed [DATA_WIDTH+16:0] sample_ext;
    logic signed [DATA_WIDTH+16:0] diff;
    
    // ===========================
    // DC Compensator Instance
    // ===========================
    
    dc_compensator #(
        .DATA_WIDTH(DATA_WIDTH),
        .K(K),
        .FRAC_WIDTH(FRAC_WIDTH),
        .USE_FLOAT(USE_FLOAT)
    ) dc_comp (
        .clk(clk),
        .rst(rst),
        .sample_valid(sample_valid & (state == INTEGRATING)),
        .sample_in(sample_in),
        .sample_out(sample_corrected),
        .baseline_out(baseline_dc)
    );
    
    // ===========================
    // Baseline Estimation (IIR)
    // ===========================
    
    always_ff @(posedge clk) begin
        if (rst) begin
            baseline_est <= 0;
        end else if (sample_valid) begin
            sample_ext <= $signed(sample_in) <<< FRAC_WIDTH;
            diff <= sample_ext - baseline_est;
            baseline_est <= baseline_est + (diff >>> K);
        end
    end
    
    assign baseline_out = (baseline_auto_en) ? baseline_dc : $signed(baseline_manual[DATA_WIDTH-1:0]);
    
    // ===========================
    // Charge Accumulator Logic
    // ===========================
    
    always_comb begin
        charge_acc_next = charge_acc;
        
        if (sample_valid && (state == INTEGRATING)) begin
            // Add corrected sample to charge accumulator with saturation
            logic [CHARGE_WIDTH:0] temp_sum;
            temp_sum = $signed(charge_acc) + $signed({sample_corrected, 6'b0}); // Scale sample
            
            if (temp_sum[CHARGE_WIDTH] != temp_sum[CHARGE_WIDTH-1]) begin
                // Saturation detected
                charge_acc_next = (temp_sum[CHARGE_WIDTH]) ? 
                    {{CHARGE_WIDTH-1{1'b1}}, 1'b0} :  // Most negative
                    {{CHARGE_WIDTH-1{1'b0}}, 1'b1};    // Most positive
            end else begin
                charge_acc_next = temp_sum[CHARGE_WIDTH-1:0];
            end
        end
    end
    
    // ===========================
    // State Machine
    // ===========================
    
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            sample_count <= 0;
            charge_acc <= 0;
            charge_out <= 0;
            charge_valid <= 0;
            done <= 0;
        end else begin
            state <= state_next;
            
            if (state == IDLE) begin
                sample_count <= 0;
                charge_acc <= 0;
                charge_valid <= 0;
                done <= 0;
            end else if (state == INTEGRATING && sample_valid) begin
                sample_count <= sample_count + 1;
                charge_acc <= charge_acc_next;
            end else if (state == OUTPUT_READY) begin
                charge_out <= charge_acc;
                charge_valid <= 1;
            end else if (state == DONE) begin
                done <= 1;
            end
        end
    end
    
    always_comb begin
        state_next = state;
        
        case (state)
            IDLE: begin
                if (start) state_next = WAIT_START_SAMPLE;
            end
            
            WAIT_START_SAMPLE: begin
                if (sample_valid && sample_count == window_start) begin
                    state_next = INTEGRATING;
                end else if (sample_valid) begin
                    sample_count = sample_count + 1; // Continue counting
                end
            end
            
            INTEGRATING: begin
                if (sample_valid && sample_count == window_end) begin
                    state_next = OUTPUT_READY;
                end
            end
            
            OUTPUT_READY: begin
                state_next = DONE;
            end
            
            DONE: begin
                state_next = IDLE;
            end
            
            default: state_next = IDLE;
        endcase
    end

endmodule
