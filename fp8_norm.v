module fp8_norm (
    input  [8:0]             n_in,
    input  signed [5:0]      exp_in,
    input                    denorm,
    output reg [8:0]         n_out,
    output reg signed [5:0]  exp_out,
    output                   underflow
);

//normalize
    wire need_shift = ~n_in[8];
    wire [8:0] n_norm   = need_shift ? {n_in[7:0], 1'b0} : n_in;
    wire signed [5:0] exp_norm = need_shift ? (exp_in - 6'sd1) : exp_in;

    assign underflow = ~denorm & (exp_norm <= 6'sd0);

//denorm
    wire signed [5:0] sh_s = 6'sd1 - exp_in;            // right shift amount, >= 1
    wire [5:0] sh = sh_s[5] ? 6'd0 : sh_s[5:0];

    reg [8:0] shifted;
    reg sticky;
    always @(*) begin
        if (sh >= 6'd9) begin                           // everything shifted out
            shifted = 9'd0;
            sticky  = |n_in;
        end else begin
            shifted = n_in >> sh;
            sticky  = |(n_in & ((9'd1 << sh) - 9'd1));  // bits lost by the shift
        end
    end

    always @(*) begin
        if (denorm) begin
            n_out   = {shifted[8:1], shifted[0] | sticky};
            exp_out = 6'sd0;
        end else begin
            n_out   = n_norm;
            exp_out = exp_norm;
        end
    end

endmodule