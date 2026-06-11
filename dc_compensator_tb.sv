`timescale 1ns / 1ps

module dc_compensator_tb;

localparam DATA_WIDTH = 14;

logic clk;
logic rst;

logic sample_valid;
logic [DATA_WIDTH-1:0] sample_in;

logic signed [DATA_WIDTH-1:0] sample_out;
logic signed [DATA_WIDTH-1:0] baseline_out;

int file_handle;
int out_file;
int status;
int values[0:1999];
int i;

// DUT
dc_compensator dut (
    .clk(clk),
    .rst(rst),
    .sample_valid(sample_valid),
    .sample_in(sample_in),
    .sample_out(sample_out),
    .baseline_out(baseline_out)
);

// clock
initial clk = 0;
always #1 clk = ~clk;

// reset
initial begin
    rst = 1;
    sample_valid = 0;
    sample_in = 0;

    repeat(10) @(posedge clk);

    rst = 0;
    sample_valid = 1;
end

// stimulus + file IO + logging
initial begin
    // output file
    out_file = $fopen("C:/Users/Jakub/OneDrive/Pulpit/sample_out.txt", "w");
    if (out_file == 0) begin
        $display("ERROR: cannot open output file");
        $finish;
    end

    @(negedge rst);

    // -------------------------------------------------
    // 1) 6000 x 2048
    // -------------------------------------------------
    repeat (6000) begin
        @(posedge clk);
        sample_in <= 14'd300;

        // zapis outputu
        //$fwrite(out_file, "%0d\n", sample_out);
    end

    // -------------------------------------------------
    // 2) open input file
    // -------------------------------------------------
    file_handle = $fopen("C:/Users/Jakub/OneDrive/Pulpit/PMT_signal.txt", "r");

    if (file_handle == 0) begin
        $display("ERROR: cannot open input file!");
        $finish;
    end

    // -------------------------------------------------
    // 3) read + write output
    // -------------------------------------------------
    i = 0;

    while (i < 2000) begin
        status = $fscanf(file_handle, "%d", values[i]);

        if (status == 1) begin
            @(posedge clk);
            sample_in <= values[i];

            // zapis outputu
            $fwrite(out_file, "%0d\n", sample_out);

            i++;
        end
    end

    $fclose(file_handle);

    // -------------------------------------------------
    // 4) finish
    // -------------------------------------------------
    repeat (20) @(posedge clk);

    $fclose(out_file);

    $display("DONE - sample_out saved to sample_out.txt");
    $finish;
end

endmodule