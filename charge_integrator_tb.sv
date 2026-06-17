`timescale 1ns / 1ps
module charge_integrator_tb;

localparam DATA_WIDTH = 128;
localparam CNT_WIDTH = 16;

logic clk;
logic rst;
logic [DATA_WIDTH-1 : 0] sample;
logic [DATA_WIDTH-1 : 0] baseline;
logic trigger;
logic [CNT_WIDTH - 1 : 0] window_start;
logic [CNT_WIDTH - 1 : 0] window_end;
logic auto_mode;
logic [DATA_WIDTH-1 : 0] charge;
logic control;

charge_integrator dut(
    .clk(clk),
    .rst(rst),
    .sample(sample),
    .trigger(trigger),
    .window_start(window_start),
    .window_end(window_end),
    .baseline(baseline),
    .auto_mode(auto_mode),
    .charge(charge),
    .control(control)    
);

int file_handle;
int status;
int values[0:1999];
int i;

initial clk = 0;
always #1 clk = ~clk;

initial begin
    rst = 1;
    repeat(10) @(posedge clk);
    rst = 0;
end

initial begin
    @(negedge rst)
    trigger = 1;
    window_start = 0;
    window_end = 2000;
    auto_mode = 1;
    file_handle = $fopen("C:/Users/Jakub/OneDrive/Pulpit/PMT_signal.txt", "r");
    while (i < 2000) begin
        status = $fscanf(file_handle, "%d", values[i]);

        if (status == 1) begin
            @(posedge clk);
            sample <= values[i];
            i++;
        end
    end
    
    $fclose(file_handle);
    $display("Integrated charge=", charge);
    repeat (30) @(posedge clk);
    $finish;
end




endmodule
