`timescale 1ns/1ps

module tb_power_bench;
    reg        CLK100MHZ = 1'b0;
    reg        rst_btn   = 1'b1;
    wire [7:0] led;
    
    always #5 CLK100MHZ = ~CLK100MHZ;
    
    power_bench_wrapper dut (
        .CLK100MHZ (CLK100MHZ),
        .rst_btn   (rst_btn),
        .led       (led)
    );
    
    initial begin
        rst_btn = 1'b1;
        repeat (10) @(posedge CLK100MHZ);
        rst_btn = 1'b0;
    end
endmodule
