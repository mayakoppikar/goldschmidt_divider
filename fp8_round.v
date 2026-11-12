module fp8_round (
    input  [8:0] n_in,
    input  signed [5:0] exp_in,
    output [2:0] frac_out,
    output signed [5:0] exp_out
);

    wire [2:0] mant     = n_in[7:5];
    wire guard    = n_in[4];
    wire sticky   = |n_in[3:0];
    wire round_up = guard & (sticky | mant[0]);

    wire [3:0] sum = {1'b0, mant} + {3'b000, round_up};   // sum[3] = carry out
    wire signed [5:0] carry_inc = {5'b00000, sum[3]};

    assign frac_out = sum[2:0];
    assign exp_out  = exp_in + carry_inc;

endmodule