module fp8_exp_unit (
    input                    sign_a,
    input                    sign_b,
    input  signed [4:0]      exp_a,
    input  signed [4:0]      exp_b,
    output                   sign_q,
    output signed [5:0]      exp_q
);
 
    // Signextended to 6 bits so the subtraction cant  overflow
    wire signed [5:0] exp_a_ext = {exp_a[4], exp_a};
    wire signed [5:0] exp_b_ext = {exp_b[4], exp_b};
 
    assign sign_q = sign_a ^ sign_b;
    assign exp_q  = exp_a_ext - exp_b_ext + 6'sd7;
 
endmodule
 