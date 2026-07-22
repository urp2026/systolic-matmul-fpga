`timescale 1ns/1ps

module tb_golden_compare;

    localparam SIZE  = 4;
    localparam DW    = 4;
    localparam AW    = 16;
    localparam NCASE = 15;
    localparam NELEM = SIZE * SIZE;

    reg clk   = 0;
    reg rst   = 1;
    reg start = 0;

    reg  [SIZE*SIZE*DW-1:0] a_flat;
    reg  [SIZE*SIZE*DW-1:0] b_flat;
    wire [SIZE*SIZE*AW-1:0] c_flat;

    wire done;

    always #5 clk = ~clk;

    matmul_top_ws #(
        SIZE,
        DW,
        AW
    ) dut (
        .clk    (clk),
        .rst    (rst),
        .start  (start),
        .a_flat (a_flat),
        .b_flat (b_flat),
        .c_flat (c_flat),
        .done   (done)
    );

    reg [DW-1:0] Amem  [0:NCASE*NELEM-1];
    reg [DW-1:0] Bmem  [0:NCASE*NELEM-1];
    reg [AW-1:0] Cgold [0:NCASE*NELEM-1];

    integer t;
    integer i;
    integer j;
    integer idx;
    integer cerr;
    integer terr;
    integer telem;
    integer badcase;

    reg [AW-1:0] Cdut;
    reg [AW-1:0] Cexp;

    initial begin
        $readmemh(
            "cases_int4/all_A_int4.mem",
            Amem
        );
    end

    initial begin
        $readmemh(
            "cases_int4/all_B_int4.mem",
            Bmem
        );
    end

    initial begin
        $readmemh(
            "cases_int4/C_golden_int4.mem",
            Cgold
        );
    end

    task load_inputs;
        input integer c;

        begin
            a_flat = 0;
            b_flat = 0;

            for (i = 0; i < SIZE; i = i + 1) begin
                for (j = 0; j < SIZE; j = j + 1) begin
                    idx = i * SIZE + j;

                    a_flat[idx*DW +: DW]
                        = Amem[c*NELEM + idx];

                    b_flat[idx*DW +: DW]
                        = Bmem[c*NELEM + idx];
                end
            end
        end
    endtask

    task run_case;
        input integer c;
        output integer errs;

        begin
            errs = 0;

            load_inputs(c);

            rst   = 1;
            start = 0;

            repeat (2) @(posedge clk);

            @(negedge clk);
            rst = 0;

            @(negedge clk);
            start = 1;

            @(negedge clk);
            start = 0;

            wait(done == 1);

            @(posedge clk);

            for (i = 0; i < SIZE; i = i + 1) begin
                for (j = 0; j < SIZE; j = j + 1) begin
                    idx = i * SIZE + j;

                    Cdut = c_flat[idx*AW +: AW];
                    Cexp = Cgold[c*NELEM + idx];

                    if (Cdut !== Cexp) begin
                        errs = errs + 1;

                        $display(
                            "MISMATCH case=%0d row=%0d col=%0d HW=%0d GOLDEN=%0d",
                            c,
                            i,
                            j,
                            $signed(Cdut),
                            $signed(Cexp)
                        );
                    end
                end
            end
        end
    endtask

    initial begin
        $dumpfile("golden_compare_int4.vcd");
        $dumpvars(0, tb_golden_compare);

        #1;

        terr    = 0;
        telem   = 0;
        badcase = 0;

        $display("=====================================================");
        $display(" INT4 Python Golden vs Hardware");
        $display(" Number of test cases : %0d", NCASE);
        $display(" DW = %0d, AW = %0d", DW, AW);
        $display("=====================================================");

        for (t = 0; t < NCASE; t = t + 1) begin
            run_case(t, cerr);

            terr  = terr + cerr;
            telem = telem + NELEM;

            if (cerr == 0) begin
                $display(
                    " case %2d : PASS",
                    t
                );
            end
            else begin
                badcase = badcase + 1;

                $display(
                    " case %2d : FAIL (%0d/%0d mismatches)",
                    t,
                    cerr,
                    NELEM
                );
            end
        end

        $display("-----------------------------------------------------");
        $display(" Total cases    : %0d", NCASE);
        $display(" Total elements : %0d", telem);
        $display(" Mismatches     : %0d", terr);
        $display(" Failed cases   : %0d", badcase);

        if (terr == 0)
            $display(
                " FINAL: PASS - INT4 hardware matches Python Golden"
            );
        else
            $display(
                " FINAL: FAIL"
            );

        $display("=====================================================");

        $finish;
    end

    initial begin
        #500000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
