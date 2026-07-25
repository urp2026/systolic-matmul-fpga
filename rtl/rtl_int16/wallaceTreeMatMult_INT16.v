(* use_dsp = "no" *)
module array_multiplier_signed #(parameter W = 16) (
    input  wire signed [W-1:0] a,
    input  wire signed [W-1:0] b,
    output wire signed [2*W-1:0] p
);
    wire [2*W-1:0] a_ext = {{W{a[W-1]}}, a};
    wire [2*W-1:0] pp [0:W-1];

    genvar i;
    generate
        for (i = 0; i < W-1; i = i + 1) begin : gen_pp
            assign pp[i] = b[i] ? (a_ext << i) : {(2*W){1'b0}};
        end
        assign pp[W-1] = b[W-1] ? (~(a_ext << (W-1)) + 1'b1) : {(2*W){1'b0}};
    endgenerate

    function [2*W-1:0] csa_sum; input [2*W-1:0] x,y,z; csa_sum = x ^ y ^ z;                 endfunction
    function [2*W-1:0] csa_car; input [2*W-1:0] x,y,z; csa_car = ((x&y)|(y&z)|(z&x)) << 1;  endfunction

    wire [2*W-1:0] s0 = csa_sum(pp[0],pp[1],pp[2]),     c0 = csa_car(pp[0],pp[1],pp[2]);
    wire [2*W-1:0] s1 = csa_sum(pp[3],pp[4],pp[5]),     c1 = csa_car(pp[3],pp[4],pp[5]);
    wire [2*W-1:0] s2 = csa_sum(pp[6],pp[7],pp[8]),     c2 = csa_car(pp[6],pp[7],pp[8]);
    wire [2*W-1:0] s3 = csa_sum(pp[9],pp[10],pp[11]),   c3 = csa_car(pp[9],pp[10],pp[11]);
    wire [2*W-1:0] s4 = csa_sum(pp[12],pp[13],pp[14]),  c4 = csa_car(pp[12],pp[13],pp[14]);
    wire [2*W-1:0] s5 = csa_sum(s0,c0,s1),              c5 = csa_car(s0,c0,s1);
    wire [2*W-1:0] s6 = csa_sum(c1,s2,c2),              c6 = csa_car(c1,s2,c2);
    wire [2*W-1:0] s7 = csa_sum(s3,c3,s4),              c7 = csa_car(s3,c3,s4);
    wire [2*W-1:0] s8 = csa_sum(s5,c5,s6),              c8 = csa_car(s5,c5,s6);
    wire [2*W-1:0] s9 = csa_sum(c6,s7,c7),              c9 = csa_car(c6,s7,c7);
    wire [2*W-1:0] s10 = csa_sum(s8,c8,s9),             c10 = csa_car(s8,c8,s9);
    wire [2*W-1:0] s11 = csa_sum(c9,c4,pp[15]),         c11 = csa_car(c9,c4,pp[15]);
    wire [2*W-1:0] s12 = csa_sum(s10,c10,s11),          c12 = csa_car(s10,c10,s11);
    wire [2*W-1:0] s13 = csa_sum(s12,c12,c11),          c13 = csa_car(s12,c12,c11);

    assign p = s13 + c13;
endmodule


module pe_ws #(parameter DW = 16, parameter AW = 64) (
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
            
            ps_out <= ps_in + prod;
        end
    end
endmodule


module systolic_array_ws #(parameter SIZE = 4, DW = 16, AW = 64) (
    input wire clk,
    input wire rst,
    input wire load_w,
    input wire en,
    input wire [SIZE*SIZE*DW-1:0] w_flat,
    input wire [SIZE*DW-1:0] a_west,
    output wire [SIZE*AW-1:0] c_south
);
    wire signed [DW-1:0] a_h [0:SIZE-1][0:SIZE];   
    wire signed [AW-1:0] ps_v [0:SIZE][0:SIZE-1];  
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


module matmul_top_ws #(parameter SIZE = 4, DW = 16, AW = 64) (
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
