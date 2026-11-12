module fp8_unpack (
    input  [7:0] x,
    output sign,
    output reg signed [4:0] exp_adj,
    output reg [3:0] sig,
    output is_nan,
    output is_zero
);
//f is mantissa exp_adj is biased exp
    wire [3:0] e = x[6:3];
    wire [2:0] f = x[2:0];

    assign sign = x[7];
    assign is_nan  = (e == 4'b1111) && (f == 3'b111);
    assign is_zero = (x[6:0] == 7'b0);

    always @(*) begin
        if (e != 4'b0000) begin // normal number
            exp_adj = {1'b0, e};
            sig     = {1'b1, f};
        end else begin // subnormal or zero
            casez (f)
                3'b1??:  begin exp_adj =  5'sd0; sig = {1'b1, f[1:0], 1'b0}; end
                3'b01?:  begin exp_adj = -5'sd1; sig = {1'b1, f[0],   2'b00}; end
                3'b001:  begin exp_adj = -5'sd2; sig = 4'b1000;               end
                default: begin exp_adj =  5'sd0; sig = 4'b0000;               end
            endcase
        end
    end
endmodule