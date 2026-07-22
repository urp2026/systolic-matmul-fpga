module wide_ram #(
    parameter DATA_WIDTH = 64,
    parameter DEPTH      = 2,
    parameter INIT_FILE  = ""
) (
    input  wire                     clk,
    input  wire                     we,
    input  wire [$clog2(DEPTH)-1:0] addr,
    input  wire [DATA_WIDTH-1:0]    din,
    output reg  [DATA_WIDTH-1:0]    dout
);
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end
    always @(posedge clk) begin
        if (we) mem[addr] <= din;
        dout <= mem[addr];
    end
endmodule

module fpga_top_bram (
    input  wire        CLK100MHZ,
    input  wire        btnC,
    input  wire        btnU,
    input  wire [15:0] SW,
    output reg  [6:0]  seg,
    output wire        dp,
    output reg  [7:0]  an
);
    localparam SIZE = 4, DW = 4, AW = 16;
    localparam AWIDTH = SIZE*SIZE*DW;
    localparam CWIDTH = SIZE*SIZE*AW;

    reg b0, b1, r0, r1;
    always @(posedge CLK100MHZ) begin
        b0 <= btnC; b1 <= b0;
        r0 <= btnU; r1 <= r0;
    end
    wire start = b1;
    wire rst   = r1;

    wire sel = SW[15];
    wire [AWIDTH-1:0] a_flat, b_flat;
    wire [0:0] aaddr = sel;

    wide_ram #(.DATA_WIDTH(AWIDTH), .DEPTH(2), .INIT_FILE("ab_a.mem")) u_ram_a (
        .clk(CLK100MHZ), .we(1'b0), .addr(aaddr), .din({AWIDTH{1'b0}}), .dout(a_flat)
    );
    wide_ram #(.DATA_WIDTH(AWIDTH), .DEPTH(2), .INIT_FILE("ab_b.mem")) u_ram_b (
        .clk(CLK100MHZ), .we(1'b0), .addr(aaddr), .din({AWIDTH{1'b0}}), .dout(b_flat)
    );

    wire [CWIDTH-1:0] c_flat;
    wire done;
    matmul_top_ws #(.SIZE(SIZE), .DW(DW), .AW(AW)) core (
        .clk(CLK100MHZ), .rst(rst), .start(start),
        .a_flat(a_flat), .b_flat(b_flat),
        .c_flat(c_flat), .done(done)
    );

    reg [CWIDTH-1:0] c_stored;
    reg done_d;
    always @(posedge CLK100MHZ) begin
        if (rst) begin done_d <= 1'b0; c_stored <= {CWIDTH{1'b0}}; end
        else begin
            done_d <= done;
            if (done & ~done_d) c_stored <= c_flat;
        end
    end

    wire [3:0] eidx = SW[3:0];
    reg signed [AW-1:0] csel;
    integer gi;
    always @(*) begin
        csel = c_stored[0 +: AW];
        for (gi = 0; gi < 16; gi = gi + 1)
            if (gi == eidx)
                csel = c_stored[gi*AW +: AW];
    end

    wire        neg = csel[AW-1];
    wire [AW-1:0] mag = neg ? (~csel + 1'b1) : csel;
    wire [11:0] m = mag[11:0];
    wire [3:0] huns = (m / 100) % 10;
    wire [3:0] tens = (m / 10)  % 10;
    wire [3:0] ones =  m % 10;

    reg [16:0] refresh;
    always @(posedge CLK100MHZ) refresh <= refresh + 1'b1;
    wire [1:0] dsel = refresh[16:15];

    reg [4:0] digit;
    always @(*) begin
        case (dsel)
            2'd0: digit = ones;
            2'd1: digit = tens;
            2'd2: digit = (huns == 0) ? 5'd10 : huns;
            2'd3: digit = neg ? 5'd11 : 5'd10;
        endcase
    end
    always @(*) begin
        an = 8'b1111_1111;
        an[dsel] = 1'b0;
    end
    always @(*) begin
        case (digit)
            5'd0:  seg = 7'b1000000;
            5'd1:  seg = 7'b1111001;
            5'd2:  seg = 7'b0100100;
            5'd3:  seg = 7'b0110000;
            5'd4:  seg = 7'b0011001;
            5'd5:  seg = 7'b0010010;
            5'd6:  seg = 7'b0000010;
            5'd7:  seg = 7'b1111000;
            5'd8:  seg = 7'b0000000;
            5'd9:  seg = 7'b0010000;
            5'd11: seg = 7'b0111111;
            default: seg = 7'b1111111;
        endcase
    end
    assign dp = 1'b1;
endmodule
