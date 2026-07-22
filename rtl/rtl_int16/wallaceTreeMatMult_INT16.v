(* use_dsp = "no" *)
module array_multiplier_signed #(parameter W = 16) ( // INT16을 위해 Default 16 설정
    input wire signed [W-1:0] a,
    input wire signed [W-1:0] b,
    output wire signed [2*W-1:0] p
);
    wire signed [2*W-1:0] a_ext = {{W{a[W-1]}}, a};
    wire signed [2*W-1:0] pp [0:W-1];
    
    // 1. 부분 곱 (Partial Product) 생성
    genvar i;
    generate
        for (i = 0; i < W-1; i = i + 1) begin : gen_pp
            assign pp[i] = b[i] ? (a_ext <<< i) : {(2*W){1'b0}};
        end
        // 마지막 sign bit(MSB) 곱셈은 뺄셈 연산 (2의 보수화) 적용
        assign pp[W-1] = b[W-1] ? (~(a_ext <<< (W-1)) + 1'b1) : {(2*W){1'b0}};
    endgenerate

    // 2. 가산 트리 (W=16일 때 pp[0]~pp[15]를 안전하고 효율적으로 더하기 위한 조합 회로 구조)
    reg signed [2*W-1:0] tree_sum;
    integer idx;
    always @(*) begin
        tree_sum = 0;
        for (idx = 0; idx < W; idx = idx + 1) begin
            tree_sum = tree_sum + pp[idx];
        end
    end

    assign p = tree_sum;

endmodule


module pe_ws #(parameter DW = 16, parameter AW = 48) (  // DW(Data Width)=16, AW(Accumulator Width)=48로 확장
    input wire clk,
    input wire rst,
    input wire load_w,
    input wire signed [DW-1:0] w_load,
    input wire en,
    input wire signed [DW-1:0] a_in,
    input wire signed [AW-1:0] ps_in,
    output reg signed [DW-1:0] a_out,
    output reg signed [AW-1:0] ps_out
);
    reg  signed [DW-1:0] w;
    wire signed [2*DW-1:0] prod;

    array_multiplier_signed #(.W(DW)) u_mul (
        .a(a_in), .b(w), .p(prod)
    );

    always @(posedge clk) begin
        if (load_w) w <= w_load;
        if (rst) begin
            a_out  <= 0;
            ps_out <= 0;
        end 
        else if (en) begin
            a_out  <= a_in;
            // 32-bit signed 결과인 prod가 48-bit signed인 ps_in과 더해질 때 자동으로 부호 확장(Sign-Extension)이 일어납니다.
            ps_out <= ps_in + prod;
        end
    end
endmodule


module systolic_array_ws #(parameter SIZE = 4, DW = 16, AW = 48) (
    input wire clk,
    input wire rst,
    input wire load_w,
    input wire en,
    input wire [SIZE*SIZE*DW-1:0] w_flat,
    input wire [SIZE*DW-1:0] a_west,
    output wire [SIZE*AW-1:0] c_south
);
    wire signed [DW-1:0] a_h [0:SIZE-1][0:SIZE];   // 데이터를 왼쪽에서 오른쪽으로 넘겨주기 위한 전선망
    wire signed [AW-1:0] ps_v [0:SIZE][0:SIZE-1];  // 위에서 더한 합계를 아래로 넘겨주기 위한 전선망

    genvar i, j;
    generate
        for (i = 0; i < SIZE; i = i + 1) begin : edge_wiring
            assign a_h[i][0] = a_west[i*DW +: DW];
            assign ps_v[0][i] = 0;
            assign c_south[i*AW +: AW] = ps_v[SIZE][i];
        end

        for (i = 0; i < SIZE; i = i + 1) begin : row
            for (j = 0; j < SIZE; j = j + 1) begin : col
                pe_ws #(.DW(DW), .AW(AW)) u_pe (
                    .clk(clk), .rst(rst), .load_w(load_w), .en(en),
                    .w_load(w_flat[(i*SIZE + j)*DW +: DW]),
                    .a_in  (a_h[i][j]),
                    .ps_in (ps_v[i][j]),
                    .a_out (a_h[i][j+1]),
                    .ps_out(ps_v[i+1][j])
                );
            end
        end
    endgenerate
endmodule


module matmul_top_ws #(parameter SIZE = 4, DW = 16, AW = 48) (
    input wire clk,
    input wire rst,
    input wire start,
    input wire [SIZE*SIZE*DW-1:0] a_flat,
    input wire [SIZE*SIZE*DW-1:0] b_flat,
    output reg [SIZE*SIZE*AW-1:0] c_flat,
    output reg done
);
    localparam IDLE = 2'd0, LOAD = 2'd1, RUN = 2'd2, FIN = 2'd3;

    reg [1:0] state;
    reg [7:0] tc;
    reg [SIZE*DW-1:0] a_west;

    wire [SIZE*AW-1:0] c_south;

    systolic_array_ws #(.SIZE(SIZE), .DW(DW), .AW(AW)) u_sa (
        .clk(clk), .rst(state == IDLE), .load_w(state == LOAD), .en(state == RUN),
        .w_flat(b_flat), .a_west(a_west), .c_south(c_south)
    );

    integer p, q, oi, ia;

    always @(*) begin
        a_west = 0;
        if (state == RUN) begin
            for (p = 0; p < SIZE; p = p + 1) begin
                ia = tc - p;
                if (ia >= 0 && ia < SIZE)
                    a_west[p*DW +: DW] = a_flat[(ia*SIZE + p)*DW +: DW];
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE; tc <= 0; done <= 0; c_flat <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0; tc <= 0;
                    if (start) state <= LOAD;
                end
                LOAD: state <= RUN; 
                RUN:  begin
                    for (q = 0; q < SIZE; q = q + 1) begin
                        oi = tc - q - SIZE; 
                        if (oi >= 0 && oi < SIZE)
                            c_flat[(oi*SIZE + q)*AW +: AW] <= c_south[q*AW +: AW];
                    end
                    if (tc == 3*SIZE) state <= FIN;
                    tc <= tc + 1;
                end
                FIN: done <= 1'b1;
            endcase
        end
    end
endmodule
