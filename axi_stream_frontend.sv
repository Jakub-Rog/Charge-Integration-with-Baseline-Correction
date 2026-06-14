`timescale 1ns / 1ps

/**
 * AXI Stream Frontend for FEE Core
 * Provides high-speed streaming I/O (Phase 2)
 * 
 * Features:
 *  - AXI Stream master for input samples
 *  - Trigger-based windowing (external trigger defines integration window)
 *  - Continuous integration per event
 *  - Ready/Valid handshake protocol
 *  - Configurable trigger polarity
 */

module axi_stream_frontend #(
    parameter int DATA_WIDTH = 14,
    parameter int CHARGE_WIDTH = 32,
    parameter int K = 12,
    parameter int FRAC_WIDTH = 10
)(
    // Clock and Reset
    input logic aclk,
    input logic aresetn,
    
    // AXI Stream Slave (Input Samples)
    input logic [DATA_WIDTH-1:0] s_axis_tdata,
    input logic s_axis_tvalid,
    output logic s_axis_tready,
    
    // Trigger Input
    input logic trigger,
    input logic [31:0] pretrigger_samples,  // Samples before trigger
    input logic [31:0] posttrigger_samples, // Samples after trigger
    input logic trigger_polarity,           // 1 = rising edge, 0 = falling edge
    
    // AXI Stream Master (Output Results)
    output logic [CHARGE_WIDTH+DATA_WIDTH-1:0] m_axis_tdata,  // [charge | baseline]
    output logic m_axis_tvalid,
    input logic m_axis_tready,
    
    // Control
    input logic enable,
    output logic busy
);

    // ===========================
    // Internal Signals
    // ===========================
    
    // Sample buffer (circular FIFO for pre-trigger samples)
    localparam int MAX_PRETRIGGER = 4096;
    localparam int ADDR_WIDTH = $clog2(MAX_PRETRIGGER);
    
    logic [DATA_WIDTH-1:0] buffer_mem [MAX_PRETRIGGER-1:0];
    logic [ADDR_WIDTH-1:0] buffer_write_ptr;
    logic [ADDR_WIDTH-1:0] buffer_read_ptr;
    logic buffer_full;
    logic buffer_empty;
    
    // Trigger edge detection
    logic trigger_r, trigger_r2;
    logic trigger_edge;
    
    // State machine
    typedef enum logic [2:0] {
        IDLE,
        BUFFERING,
        TRIGGER_DETECTED,
        PLAYBACK_PRETRIGGER,
        ACQUIRE_POSTTRIGGER,
        OUTPUT_RESULT,
        DONE
    } state_t;
    
    state_t state, state_next;
    
    // Counters
    logic [31:0] pre_count, post_count;
    logic [31:0] pre_count_next, post_count_next;
    
    // Integration accumulator
    logic [CHARGE_WIDTH-1:0] charge_acc;
    logic signed [DATA_WIDTH-1:0] baseline_acc;
    
    // ===========================
    // FEE Core Instance
    // ===========================
    
    logic fee_start;
    logic fee_done;
    logic fee_sample_valid;
    logic [DATA_WIDTH-1:0] fee_sample_in;
    logic [CHARGE_WIDTH-1:0] fee_charge;
    logic signed [DATA_WIDTH-1:0] fee_baseline;
    logic fee_charge_valid;
    
    fee_core #(
        .DATA_WIDTH(DATA_WIDTH),
        .CHARGE_WIDTH(CHARGE_WIDTH),
        .K(K),
        .FRAC_WIDTH(FRAC_WIDTH),
        .USE_FLOAT(0)
    ) fee_inst (
        .clk(aclk),
        .rst(~aresetn),
        .start(fee_start),
        .done(fee_done),
        .sample_valid(fee_sample_valid),
        .sample_in(fee_sample_in),
        .window_start(32'h0),           // Internal windowing
        .window_end(pre_count + post_count),
        .baseline_manual(32'h0),
        .baseline_auto_en(1'b1),        // Auto baseline
        .charge_out(fee_charge),
        .baseline_out(fee_baseline),
        .charge_valid(fee_charge_valid)
    );
    
    // ===========================
    // Trigger Edge Detection
    // ===========================
    
    always_ff @(posedge aclk) begin
        if (~aresetn) begin
            trigger_r <= 1'b0;
            trigger_r2 <= 1'b0;
        end else begin
            trigger_r <= trigger;
            trigger_r2 <= trigger_r;
        end
    end
    
    assign trigger_edge = (trigger_polarity) ? 
                         (~trigger_r2 & trigger_r) :  // Rising edge
                         (trigger_r2 & ~trigger_r);    // Falling edge
    
    // ===========================
    // Sample Buffer (Circular FIFO)
    // ===========================
    
    always_ff @(posedge aclk) begin
        if (~aresetn) begin
            buffer_write_ptr <= {ADDR_WIDTH{1'b0}};
        end else if (s_axis_tvalid & s_axis_tready) begin
            buffer_mem[buffer_write_ptr] <= s_axis_tdata;
            buffer_write_ptr <= buffer_write_ptr + 1;
        end
    end
    
    // ===========================
    // State Machine
    // ===========================
    
    always_ff @(posedge aclk) begin
        if (~aresetn) begin
            state <= IDLE;
            buffer_read_ptr <= {ADDR_WIDTH{1'b0}};
            pre_count <= 32'h0;
            post_count <= 32'h0;
            charge_acc <= {CHARGE_WIDTH{1'b0}};
            baseline_acc <= {DATA_WIDTH{1'b0}};
            busy <= 1'b0;
        end else begin
            state <= state_next;
            
            if (state == BUFFERING) begin
                // Continuously fill buffer with incoming samples
                // (oldest samples are overwritten if buffer full)
            end else if (state == TRIGGER_DETECTED) begin
                pre_count <= (pretrigger_samples > MAX_PRETRIGGER) ? 
                            MAX_PRETRIGGER : pretrigger_samples;
                post_count <= posttrigger_samples;
                fee_start <= 1'b1;
                busy <= 1'b1;
            end else if (state == PLAYBACK_PRETRIGGER) begin
                if (s_axis_tready & s_axis_tvalid) begin
                    pre_count <= pre_count - 1;
                end
            end else if (state == ACQUIRE_POSTTRIGGER) begin
                if (s_axis_tready & s_axis_tvalid) begin
                    post_count <= post_count - 1;
                end
            end else if (state == OUTPUT_RESULT) begin
                if (m_axis_tready & m_axis_tvalid) begin
                    charge_acc <= fee_charge;
                    baseline_acc <= fee_baseline;
                    busy <= 1'b0;
                end
            end else if (state == IDLE) begin
                busy <= 1'b0;
                fee_start <= 1'b0;
            end
        end
    end
    
    always_comb begin
        state_next = state;
        
        case (state)
            IDLE: begin
                if (enable) begin
                    state_next = BUFFERING;
                end
            end
            
            BUFFERING: begin
                if (trigger_edge) begin
                    state_next = TRIGGER_DETECTED;
                end
            end
            
            TRIGGER_DETECTED: begin
                state_next = PLAYBACK_PRETRIGGER;
            end
            
            PLAYBACK_PRETRIGGER: begin
                if (pre_count == 0) begin
                    state_next = ACQUIRE_POSTTRIGGER;
                end
            end
            
            ACQUIRE_POSTTRIGGER: begin
                if (post_count == 0) begin
                    state_next = OUTPUT_RESULT;
                end
            end
            
            OUTPUT_RESULT: begin
                if (m_axis_tready & m_axis_tvalid) begin
                    state_next = IDLE;
                end
            end
            
            DONE: begin
                state_next = IDLE;
            end
            
            default: state_next = IDLE;
        endcase
    end
    
    // ===========================
    // Data Path Control
    // ===========================
    
    always_comb begin
        // Input side
        s_axis_tready = (state == BUFFERING) | 
                       (state == ACQUIRE_POSTTRIGGER);
        
        // FEE Core sample input
        fee_sample_valid = s_axis_tvalid & s_axis_tready;
        fee_sample_in = s_axis_tdata;
        
        // Output side
        m_axis_tdata = {{CHARGE_WIDTH{1'b0}} | charge_acc, baseline_acc};
        m_axis_tvalid = (state == OUTPUT_RESULT);
    end

endmodule
