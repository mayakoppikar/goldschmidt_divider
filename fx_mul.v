module fx_mul (
    input  [8:0] a,
    input  [8:0] b,
    output [8:0] p
);

    wire [17:0] full = a * b;   
    assign p = full[16:8];      // truncate to Q1.8

endmodule