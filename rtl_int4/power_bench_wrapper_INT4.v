module power_bench_wrapper #(
    parameter SIZE = 4,
    parameter DW   = 4,
    parameter AW   = 32
)(
    input  wire       CLK100MHZ,
    input  wire       rst_btn,
    output reg  [7:0] led
);

    wire clk = CLK100MHZ;
    wire rst = rst_btn;

    reg  [31:0] lfsr;
    wire fb = lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0];

    wire [SIZE*SIZE*DW-1:0] a_in;
    wire [SIZE*SIZE*DW-1:0] b_in;

    genvar gi;
    generate
        for (gi = 0; gi < SIZE*SIZE; gi = gi + 1) begin : gen_in
            assign a_in[gi*DW +: DW]
                = lfsr[DW-1:0] ^ gi[DW-1:0];

            assign b_in[gi*DW +: DW]
                = lfsr[2*DW-1:DW] ^ (gi[DW-1:0] << 1);
        end
    endgenerate

    wire [SIZE*SIZE*AW-1:0] c_flat;
    wire done;

    wire [7:0] xacc [0:SIZE*SIZE];
    assign xacc[0] = 8'b0;

    genvar gk;
    generate
        for (gk = 0; gk < SIZE*SIZE; gk = gk + 1) begin : xor_tree
            assign xacc[gk+1]
                = xacc[gk] ^ c_flat[gk*AW +: 8];
        end
    endgenerate

    wire [7:0] c_xor = xacc[SIZE*SIZE];

    localparam S_RST  = 2'd0;
    localparam S_GO   = 2'd1;
    localparam S_WAIT = 2'd2;
    localparam S_NEXT = 2'd3;

    reg [1:0] st;
    reg       core_rst;
    reg       start;
    reg [2:0] gap;
    reg       done_d;

    always @(posedge clk) begin
        if (rst) begin
            lfsr    <= 32'hACE1_2345;
            st      <= S_RST;
            core_rst <= 1'b1;
            start   <= 1'b0;
            gap     <= 3'd0;
            done_d  <= 1'b0;
            led     <= 8'b0;
        end else begin
            done_d <= done;

            case (st)
                S_RST: begin
                    core_rst <= 1'b1;
                    start    <= 1'b0;
                    gap      <= gap + 3'd1;

                    if (gap == 3'd3) begin
                        core_rst <= 1'b0;
                        gap      <= 3'd0;
                        st       <= S_GO;
                    end
                end

                S_GO: begin
                    start <= 1'b1;
                    st    <= S_WAIT;
                end

                S_WAIT: begin
                    start <= 1'b0;

                    if (done & ~done_d) begin
                        led  <= c_xor;
                        lfsr <= {lfsr[30:0], fb};
                        st   <= S_NEXT;
                    end
                end

                S_NEXT: begin
                    st <= S_RST;
                end

                default: begin
                    st <= S_RST;
                end
            endcase
        end
    end

    matmul_top_ws #(
        .SIZE(SIZE),
        .DW(DW),
        .AW(AW)
    ) core (
        .clk(clk),
        .rst(core_rst),
        .start(start),
        .a_flat(a_in),
        .b_flat(b_in),
        .c_flat(c_flat),
        .done(done)
    );

endmodule
