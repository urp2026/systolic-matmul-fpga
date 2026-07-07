`timescale 1ns/1ps

module tb_arrayMatMult;
    parameter W = 8;
    reg  signed [W-1:0] a, b;
    wire signed [2*W-1:0] p;

    array_multiplier_signed #(.W(W)) dut (.a(a), .b(b), .p(p));

    integer errors = 0;
    integer k;
    reg signed [2*W-1:0] expected;

    task check;
        input signed [W-1:0] ta, tb;
        begin
            a = ta; b = tb;
            #1;
            expected = ta * tb;
            if (p !== expected) begin
                $display("FAIL: %0d * %0d = %0d (expected %0d)", ta, tb, p, expected);
                errors = errors + 1;
            end else begin
                $display("ok  : %0d * %0d = %0d", ta, tb, p);
            end
        end
    endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_arrayMatMult);

        check(  0,   0);
        check(  1,   1);
        check( -1,   1);
        check(  1,  -1);
        check( -1,  -1);
        check(127, 127); 
        check(-128,-128);
        check(-128, 127);
        check( 127,-128);
        check(-128,   1);
        check( 100, -50);
        check( -73,  42);

        for (k = 0; k < 100; k = k + 1) begin
            check($random % 256 - 128, $random % 256 - 128);
        end

        if (errors == 0)
            $display("\n=== ALL TESTS PASSED ===");
        else
            $display("\n=== %0d TEST(S) FAILED ===", errors);
        $finish;
    end
endmodule
