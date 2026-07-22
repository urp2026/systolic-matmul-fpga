`timescale 1ns/1ps
// =====================================================================
//  tb_golden_compare.v
//   Python이 계산한 golden(C_golden.mem)과 하드웨어 결과를 비교
//   - tb는 golden을 계산하지 않음 (파일에서 읽기만)
//   - A,B는 하드웨어 입력, C_golden은 정답
// =====================================================================
module tb_golden_compare;
    localparam SIZE=4, DW=16, AW=48, NCASE=15;
    reg clk=0, rst=1, start=0;
    reg  [SIZE*SIZE*DW-1:0] a_flat, b_flat;
    wire [SIZE*SIZE*AW-1:0] c_flat;
    wire done;
    always #5 clk=~clk;

    matmul_top_ws #(SIZE,DW,AW) dut(
        .clk(clk),.rst(rst),.start(start),
        .a_flat(a_flat),.b_flat(b_flat),.c_flat(c_flat),.done(done));

    // 입력 A,B (16비트) + golden C (34비트) 모두 파일에서 읽음
    reg [15:0] Amem [0:NCASE*16-1];
    reg [15:0] Bmem [0:NCASE*16-1];
    reg [33:0] Cgold[0:NCASE*16-1];      // Python golden
    integer t,i,j,idx,cerr,terr,telem,badcase;
    reg [33:0] Cdut, Cexp;

    initial $readmemh("cases/all_A.mem",    Amem);
    initial $readmemh("cases/all_B.mem",    Bmem);
    initial $readmemh("cases/C_golden.mem", Cgold);   // ★ golden을 계산 대신 로드

    task load_inputs(input integer c);
        begin
            for(i=0;i<SIZE;i=i+1) for(j=0;j<SIZE;j=j+1) begin
                idx=i*SIZE+j;
                a_flat[idx*DW +: DW]=Amem[c*16+idx];
                b_flat[idx*DW +: DW]=Bmem[c*16+idx];
            end
        end
    endtask

    task run_case(input integer c, output integer errs);
        begin
            errs=0;
            load_inputs(c);
            rst=1; start=0; repeat(2)@(posedge clk);
            @(negedge clk) rst=0; @(negedge clk) start=1; @(negedge clk) start=0;
            wait(done==1); @(posedge clk);
            for(i=0;i<SIZE;i=i+1) for(j=0;j<SIZE;j=j+1) begin
                idx=i*SIZE+j;
                Cdut = c_flat[idx*AW +: AW];      // 하드웨어 결과
                Cexp = Cgold[c*16+idx];           // Python golden
                if(Cdut !== Cexp) errs=errs+1;
            end
        end
    endtask

    initial begin
        #1; terr=0; telem=0; badcase=0;
        $display("=====================================================");
        $display(" Python golden(.mem) vs 하드웨어 비교 : %0d 케이스", NCASE);
        $display("=====================================================");
        for(t=0;t<NCASE;t=t+1) begin
            run_case(t,cerr);
            terr=terr+cerr; telem=telem+SIZE*SIZE;
            if(cerr==0) $display(" case %2d : PASS", t);
            else begin badcase=badcase+1; $display(" case %2d : FAIL (%0d/16 불일치)", t, cerr); end
        end
        $display("-----------------------------------------------------");
        $display(" 총 %0d 케이스, %0d 원소 비교", NCASE, telem);
        $display(" 불일치 원소 : %0d,  불일치 케이스 : %0d", terr, badcase);
        if(terr==0)
            $display(" 최종 : PASS - 하드웨어가 Python golden과 완전 일치 (error 0%%)");
        else
            $display(" 최종 : FAIL");
        $display("=====================================================");
        $finish;
    end
    initial begin #500000; $display("TIMEOUT"); $finish; end
endmodule
```
