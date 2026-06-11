`timescale 1ns / 1ps

module dc_compensator#(
    parameter int DATA_WIDTH = 14,
    parameter int K = 12
)(
    input logic clk,
    input logic rst,
    
    input logic sample_valid,
    input logic [DATA_WIDTH-1 : 0] sample_in,
    
    output logic signed [DATA_WIDTH-1 : 0] sample_out,
    output logic signed [DATA_WIDTH-1 : 0] baseline_out
);

logic signed [DATA_WIDTH+16 : 0] baseline;
logic signed [DATA_WIDTH+16 : 0] sample_ext = 0;
logic signed [DATA_WIDTH+16 : 0] diff = 0;

always_ff @(posedge clk) begin
    if(rst) begin
        baseline <= 0;
    end else begin
        sample_ext <= sample_in <<< 10;
        diff <= sample_ext - baseline;
        baseline <= baseline + (diff >>> K);
    end
end

assign baseline_out = baseline >>> 10;
assign sample_out = $signed(sample_in) - $signed(baseline_out);

endmodule