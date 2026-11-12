module fp8_pack (
    input                    sign,
    input  signed [5:0]      exp_in,
    input  [2:0]             frac_in,
    input                    force_nan,
    input                    force_zero,
    output reg [7:0]         result
);

    wire overflow = (exp_in > 6'sd15) || ((exp_in == 6'sd15) && (frac_in == 3'b111));
    wire neg_exp  = exp_in[5];     // exp_in < 0

    always @(*) begin
        if (force_nan)
            result = 8'h7F;
        else if (force_zero)
            result = {sign, 7'b0000000};
        else if (overflow)
            result = 8'h7F;
        else if (neg_exp)
            result = {sign, 7'b0000000};
        else
            result = {sign, exp_in[3:0], frac_in};
    end

endmodule