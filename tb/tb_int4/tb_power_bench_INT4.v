`timescale 1ns/1ps

module tb_power_bench;

    reg CLK100MHZ = 1'b0;
    reg rst_btn   = 1'b1;

    wire [7:0] led;

    always #5 CLK100MHZ = ~CLK100MHZ;

    power_bench_wrapper_INT4 dut (
        .CLK100MHZ (CLK100MHZ),
        .rst_btn   (rst_btn),
        .led       (led)
    );

    initial begin
        $dumpfile("power_bench_int4.vcd");
        $dumpvars(0, tb_power_bench);

        rst_btn = 1'b1;

        repeat (10)
            @(posedge CLK100MHZ);

        rst_btn = 1'b0;

        repeat (10000)
            @(posedge CLK100MHZ);

        $display("INT4 power bench simulation finished");

        $finish;
    end

endmodule
