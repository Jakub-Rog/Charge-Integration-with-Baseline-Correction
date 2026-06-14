`timescale 1ns / 1ps

/**
 * AXI-Lite Wrapper for FEE Core
 * Provides register-based control and data interface (Phase 1)
 * 
 * Register Map:
 *  0x00: CONTROL      - Start/Reset/Enable signals
 *  0x04: STATUS       - Done, Busy, Error flags
 *  0x08: WINDOW_START - Integration window start sample
 *  0x0C: WINDOW_END   - Integration window end sample
 *  0x10: BASELINE_CFG - Baseline mode (auto/manual) and manual value
 *  0x14: CHARGE_OUT   - Output charge (lower 32 bits)
 *  0x18: CHARGE_OUT_HI- Output charge (upper bits if >32)
 *  0x1C: BASELINE_OUT - Estimated baseline value
 *  0x20: VERSION      - Firmware version (read-only)
 */

module axi_lite_wrapper #(
    parameter int DATA_WIDTH = 14,
    parameter int CHARGE_WIDTH = 32,
    parameter int K = 12,
    parameter int FRAC_WIDTH = 10,
    parameter int VERSION = 32'h00010000  // v1.0.0
)(
    // AXI Clock and Reset
    input logic aclk,
    input logic aresetn,
    
    // AXI-Lite Write Address Channel
    input logic [31:0] awaddr,
    input logic [2:0] awprot,
    input logic awvalid,
    output logic awready,
    
    // AXI-Lite Write Data Channel
    input logic [31:0] wdata,
    input logic [3:0] wstrb,
    input logic wvalid,
    output logic wready,
    
    // AXI-Lite Write Response Channel
    output logic [1:0] bresp,
    output logic bvalid,
    input logic bready,
    
    // AXI-Lite Read Address Channel
    input logic [31:0] araddr,
    input logic [2:0] arprot,
    input logic arvalid,
    output logic arready,
    
    // AXI-Lite Read Data Channel
    output logic [31:0] rdata,
    output logic [1:0] rresp,
    output logic rvalid,
    input logic rready,
    
    // FEE Core data input
    input logic sample_valid,
    input logic [DATA_WIDTH-1:0] sample_in,
    
    // FEE Core outputs
    output logic [CHARGE_WIDTH-1:0] charge_out,
    output logic signed [DATA_WIDTH-1:0] baseline_out
);

    // ===========================
    // Register Definitions
    // ===========================
    
    // CONTROL Register (0x00)
    logic start_pulse;
    logic reset_core;
    logic enable_core;
    
    // STATUS Register (0x04)
    logic done_flag;
    logic busy_flag;
    logic error_flag;
    
    // Configuration Registers
    logic [31:0] window_start_reg;
    logic [31:0] window_end_reg;
    logic [31:0] baseline_cfg_reg;
    logic [31:0] charge_out_reg;
    logic [31:0] baseline_out_reg;
    
    // ===========================
    // FEE Core Instance
    // ===========================
    
    logic fee_start;
    logic fee_done;
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
        .rst(reset_core | ~aresetn),
        .start(fee_start),
        .done(fee_done),
        .sample_valid(sample_valid),
        .sample_in(sample_in),
        .window_start(window_start_reg),
        .window_end(window_end_reg),
        .baseline_manual(baseline_cfg_reg),
        .baseline_auto_en(baseline_cfg_reg[31]),
        .charge_out(fee_charge),
        .baseline_out(fee_baseline),
        .charge_valid(fee_charge_valid)
    );
    
    // ===========================
    // Output Assignments
    // ===========================
    
    assign charge_out = fee_charge;
    assign baseline_out = fee_baseline;
    
    // ===========================
    // AXI Write Path
    // ===========================
    
    logic [31:0] write_address;
    logic write_handshake;
    
    assign write_handshake = awvalid & awready & wvalid & wready;
    
    always_ff @(posedge aclk) begin
        if (~aresetn) begin
            awready <= 1'b0;
            wready <= 1'b0;
            bvalid <= 1'b0;
            bresp <= 2'b00;
            write_address <= 32'h0;
        end else begin
            // Write address ready
            awready <= awvalid & ~wvalid;
            
            if (awvalid & awready) begin
                write_address <= awaddr;
            end
            
            // Write data ready
            wready <= wvalid & ~bvalid;
            
            // Write response
            if (wvalid & wready) begin
                bvalid <= 1'b1;
                bresp <= 2'b00;  // OKAY response
            end else if (bvalid & bready) begin
                bvalid <= 1'b0;
            end
        end
    end
    
    // Write data processing
    always_ff @(posedge aclk) begin
        if (~aresetn) begin
            start_pulse <= 1'b0;
            reset_core <= 1'b0;
            enable_core <= 1'b1;
            window_start_reg <= 32'h0;
            window_end_reg <= 32'h0;
            baseline_cfg_reg <= 32'h80000000;  // Auto baseline mode enabled
        end else if (write_handshake) begin
            case (write_address[7:2])
                6'h00: begin  // CONTROL
                    reset_core <= wdata[1];
                    enable_core <= wdata[0];
                    start_pulse <= wdata[2];
                end
                6'h02: begin  // WINDOW_START
                    window_start_reg <= wdata;
                end
                6'h03: begin  // WINDOW_END
                    window_end_reg <= wdata;
                end
                6'h04: begin  // BASELINE_CFG
                    baseline_cfg_reg <= wdata;
                end
                default: begin
                    // Read-only or invalid addresses
                end
            endcase
        end else begin
            start_pulse <= 1'b0;  // Pulse for one cycle
        end
    end
    
    // ===========================
    // AXI Read Path
    // ===========================
    
    logic [31:0] read_address;
    logic [31:0] read_data;
    logic read_valid;
    
    always_ff @(posedge aclk) begin
        if (~aresetn) begin
            arready <= 1'b0;
            rvalid <= 1'b0;
            rresp <= 2'b00;
            read_address <= 32'h0;
        end else begin
            // Read address ready
            arready <= arvalid & ~rvalid;
            
            if (arvalid & arready) begin
                read_address <= araddr;
                rvalid <= 1'b1;
                rresp <= 2'b00;  // OKAY response
            end else if (rvalid & rready) begin
                rvalid <= 1'b0;
            end
        end
    end
    
    // Read data multiplexer
    always_comb begin
        read_data = 32'h0;
        
        case (read_address[7:2])
            6'h00: begin  // CONTROL
                read_data = {29'h0, enable_core, reset_core, start_pulse};
            end
            6'h01: begin  // STATUS
                read_data = {29'h0, error_flag, busy_flag, done_flag};
            end
            6'h02: begin  // WINDOW_START
                read_data = window_start_reg;
            end
            6'h03: begin  // WINDOW_END
                read_data = window_end_reg;
            end
            6'h04: begin  // BASELINE_CFG
                read_data = baseline_cfg_reg;
            end
            6'h05: begin  // CHARGE_OUT (lower 32 bits)
                read_data = charge_out_reg;
            end
            6'h07: begin  // BASELINE_OUT
                read_data = {{(32-DATA_WIDTH){baseline_out_reg[DATA_WIDTH-1]}}, baseline_out_reg};
            end
            6'h08: begin  // VERSION
                read_data = VERSION;
            end
            default: begin
                read_data = 32'hDEADBEEF;  // Invalid address marker
            end
        endcase
    end
    
    assign rdata = read_data;
    
    // ===========================
    // Status Flags
    // ===========================
    
    always_ff @(posedge aclk) begin
        if (~aresetn) begin
            done_flag <= 1'b0;
            busy_flag <= 1'b0;
            error_flag <= 1'b0;
        end else begin
            // Done flag (set by FEE, cleared by read or reset)
            if (fee_done) begin
                done_flag <= 1'b1;
            end else if (read_valid & (read_address[7:2] == 6'h01)) begin
                done_flag <= 1'b0;
            end
            
            // Busy flag (during integration)
            busy_flag <= fee_start & ~fee_done & enable_core;
            
            // Error flag (placeholder for future error detection)
            error_flag <= 1'b0;
        end
    end
    
    // Latch charge and baseline outputs when valid
    always_ff @(posedge aclk) begin
        if (~aresetn) begin
            charge_out_reg <= 32'h0;
            baseline_out_reg <= 32'h0;
        end else if (fee_charge_valid) begin
            charge_out_reg <= fee_charge[31:0];
            baseline_out_reg <= fee_baseline;
        end
    end
    
    // ===========================
    // Control Signal Routing
    // ===========================
    
    assign fee_start = start_pulse & enable_core;

endmodule
