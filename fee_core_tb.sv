`timescale 1ns / 1ps

/**
 * FEE Core Testbench
 * Tests charge integration with baseline correction
 * Simulates:
 *  - Constant DC signal (baseline estimation)
 *  - Gaussian pulse (rise time)
 *  - Exponential decay (fall time)
 */

module fee_core_tb;

    localparam int DATA_WIDTH = 14;
    localparam int CHARGE_WIDTH = 32;
    localparam int K = 12;
    localparam int FRAC_WIDTH = 10;
    
    // Test parameters
    localparam real GAUSSIAN_SIGMA = 10.0;  // samples
    localparam real EXPONENTIAL_TAU = 50.0; // samples
    localparam int PULSE_HEIGHT = 500;      // ADC counts above baseline
    localparam int BASELINE_DC = 300;       // DC offset
    
    logic clk;
    logic rst;
    logic start;
    logic done;
    logic sample_valid;
    logic [DATA_WIDTH-1:0] sample_in;
    logic [31:0] window_start;
    logic [31:0] window_end;
    logic [31:0] baseline_manual;
    logic baseline_auto_en;
    logic [CHARGE_WIDTH-1:0] charge_out;
    logic signed [DATA_WIDTH-1:0] baseline_out;
    logic charge_valid;
    
    // DUT
    fee_core #(
        .DATA_WIDTH(DATA_WIDTH),
        .CHARGE_WIDTH(CHARGE_WIDTH),
        .K(K),
        .FRAC_WIDTH(FRAC_WIDTH),
        .USE_FLOAT(0)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .done(done),
        .sample_valid(sample_valid),
        .sample_in(sample_in),
        .window_start(window_start),
        .window_end(window_end),
        .baseline_manual(baseline_manual),
        .baseline_auto_en(baseline_auto_en),
        .charge_out(charge_out),
        .baseline_out(baseline_out),
        .charge_valid(charge_valid)
    );
    
    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;  // 100 MHz
    
    // ===========================
    // Gaussian Function
    // ===========================
    function real gaussian(real t, real mu, real sigma);
        real pi = 3.14159265359;
        return (1.0 / (sigma * $sqrt(2.0 * pi))) * 
               $exp(-0.5 * ((t - mu) / sigma) ** 2);
    endfunction
    
    // ===========================
    // Exponential Function
    // ===========================
    function real exponential(real t, real tau);
        return $exp(-t / tau);
    endfunction
    
    // ===========================
    // Test stimulus
    // ===========================
    
    initial begin
        rst = 1;
        start = 0;
        sample_valid = 0;
        sample_in = 0;
        window_start = 0;
        window_end = 0;
        baseline_manual = BASELINE_DC << 10;  // Q-notation
        baseline_auto_en = 1;  // Enable auto baseline
        
        repeat(10) @(posedge clk);
        rst = 0;
        
        // Test 1: Constant DC signal - baseline estimation
        $display("\n=== Test 1: Constant DC Signal (Baseline Estimation) ===");
        baseline_auto_en = 1;
        window_start = 100;
        window_end = 2000;
        
        // Pre-charge baseline estimation (6000 samples)
        for (int i = 0; i < 6000; i++) begin
            @(posedge clk);
            sample_valid <= 1;
            sample_in <= BASELINE_DC;
        end
        
        @(posedge clk);
        sample_valid <= 0;
        $display("Baseline estimation complete. Baseline: %0d", baseline_out);
        
        // Wait for baseline to settle
        repeat(50) @(posedge clk);
        
        // Start integration
        @(posedge clk);
        start <= 1;
        @(posedge clk);
        start <= 0;
        
        for (int i = 0; i < 2100; i++) begin
            @(posedge clk);
            sample_valid <= 1;
            sample_in <= BASELINE_DC;
            
            if (i == 2000) begin
                sample_valid <= 0;
            end
        end
        
        // Wait for done
        wait(done);
        @(posedge clk);
        $display("Test 1 Complete - Charge: %0d (should be ~0)", $signed(charge_out));
        
        repeat(10) @(posedge clk);
        
        // ===========================
        // Test 2: Gaussian + Exponential Pulse
        // ===========================
        
        $display("\n=== Test 2: Gaussian Rise + Exponential Fall Pulse ===");
        
        baseline_auto_en = 1;
        window_start = 50;
        window_end = 250;
        
        // Pre-charge with baseline
        for (int i = 0; i < 6000; i++) begin
            @(posedge clk);
            sample_valid <= 1;
            sample_in <= BASELINE_DC;
        end
        
        @(posedge clk);
        sample_valid <= 0;
        repeat(50) @(posedge clk);
        
        // Start integration
        @(posedge clk);
        start <= 1;
        @(posedge clk);
        start <= 0;
        
        // Generate pulse
        for (int i = 0; i < 300; i++) begin
            @(posedge clk);
            sample_valid <= 1;
            
            real sample_value;
            real t_rise = real'(i) - 50.0;  // Gaussian centered at t=50
            real t_fall = real'(i) - 100.0; // Exponential starts at t=100
            
            if (t_rise < 0.0) begin
                // Before pulse
                sample_value = BASELINE_DC;
            end else if (t_fall <= 0.0) begin
                // Gaussian rise
                real gauss = gaussian(t_rise, 0.0, GAUSSIAN_SIGMA);
                sample_value = BASELINE_DC + (PULSE_HEIGHT * gauss);
            end else begin
                // Exponential fall
                real exp_decay = exponential(t_fall, EXPONENTIAL_TAU);
                sample_value = BASELINE_DC + (PULSE_HEIGHT * exp_decay);
            end
            
            // Clamp to valid range
            if (sample_value < 0) sample_value = 0;
            if (sample_value >= (2**DATA_WIDTH)) sample_value = (2**DATA_WIDTH) - 1;
            
            sample_in <= $rtoi(sample_value);
            
            // Logging
            if ((i >= 48 && i <= 52) || (i >= 98 && i <= 102) || i == 250) begin
                $display("Sample[%0d]: input=%0d, baseline=%0d, corrected=%0d",
                        i, $rtoi(sample_value), baseline_out, 
                        $signed(sample_in) - baseline_out);
            end
        end
        
        @(posedge clk);
        sample_valid <= 0;
        
        // Wait for done
        wait(done);
        @(posedge clk);
        $display("Test 2 Complete - Charge: %0d", $signed(charge_out));
        $display("Expected charge: ~%0d (pulse area)", PULSE_HEIGHT * 150 / 2);
        
        repeat(10) @(posedge clk);
        
        // ===========================
        // Test 3: Manual Baseline Mode
        // ===========================
        
        $display("\n=== Test 3: Manual Baseline Mode ===");
        
        baseline_auto_en = 0;
        baseline_manual = (BASELINE_DC + 50) << 10;  // Set manual baseline higher
        window_start = 50;
        window_end = 250;
        
        // Start integration immediately (no pre-charge needed for manual baseline)
        @(posedge clk);
        start <= 1;
        @(posedge clk);
        start <= 0;
        
        // Generate same pulse
        for (int i = 0; i < 300; i++) begin
            @(posedge clk);
            sample_valid <= 1;
            
            real sample_value;
            real t_rise = real'(i) - 50.0;
            real t_fall = real'(i) - 100.0;
            
            if (t_rise < 0.0) begin
                sample_value = BASELINE_DC;
            end else if (t_fall <= 0.0) begin
                real gauss = gaussian(t_rise, 0.0, GAUSSIAN_SIGMA);
                sample_value = BASELINE_DC + (PULSE_HEIGHT * gauss);
            end else begin
                real exp_decay = exponential(t_fall, EXPONENTIAL_TAU);
                sample_value = BASELINE_DC + (PULSE_HEIGHT * exp_decay);
            end
            
            if (sample_value < 0) sample_value = 0;
            if (sample_value >= (2**DATA_WIDTH)) sample_value = (2**DATA_WIDTH) - 1;
            
            sample_in <= $rtoi(sample_value);
        end
        
        @(posedge clk);
        sample_valid <= 0;
        
        // Wait for done
        wait(done);
        @(posedge clk);
        $display("Test 3 Complete - Charge: %0d", $signed(charge_out));
        $display("Baseline (manual): %0d", baseline_out);
        
        repeat(10) @(posedge clk);
        
        // ===========================
        // Test Summary
        // ===========================
        
        $display("\n=== Test Summary ===");
        $display("All tests completed successfully");
        $display("Testbench finished at time %0t ns", $time);
        
        $finish;
    end
    
    // ===========================
    // Waveform dumping (optional)
    // ===========================
    
    initial begin
        // Uncomment for waveform viewing
        // $dumpfile("fee_core_tb.vcd");
        // $dumpvars(0, fee_core_tb);
    end

endmodule
