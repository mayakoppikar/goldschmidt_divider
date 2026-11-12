module fp8_div_dp (
    input        clk,
    input        rst_n,
    input  [7:0] a,            // dividend
    input  [7:0] b,            // divisor
    input        load,
    input        step,
    input        norm_en,
    input        denorm_en,
    input        round_en,
    input        out_en,
    output       is_special,
    output       underflow,
    output reg [7:0] result
);

//unpack
    wire              sign_a, sign_b;
    wire signed [4:0] exp_a, exp_b;
    wire [3:0]        sig_a, sig_b;
    wire              nan_a, nan_b, zero_a, zero_b;

    fp8_unpack u_unpack_a (.x(a), .sign(sign_a), .exp_adj(exp_a), .sig(sig_a),
                           .is_nan(nan_a), .is_zero(zero_a));
    fp8_unpack u_unpack_b (.x(b), .sign(sign_b), .exp_adj(exp_b), .sig(sig_b),
                           .is_nan(nan_b), .is_zero(zero_b));

    // sign and provisional exponent of the quotient
    wire              sign_q;
    wire signed [5:0] exp_q;

    fp8_exp_unit u_exp (.sign_a(sign_a), .sign_b(sign_b), .exp_a(exp_a), .exp_b(exp_b),
                        .sign_q(sign_q), .exp_q(exp_q));

//special case
    wire force_nan_c  = nan_a | nan_b | zero_b;
    wire force_zero_c = zero_a & ~force_nan_c;

    assign is_special = force_nan_c | force_zero_c;

    reg              sign_r;
    reg signed [5:0] exp_q_r;
    reg              force_nan_r, force_zero_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sign_r       <= 1'b0;
            exp_q_r      <= 6'sd0;
            force_nan_r  <= 1'b0;
            force_zero_r <= 1'b0;
        end else if (load) begin
            sign_r       <= sign_q;
            exp_q_r      <= exp_q;
            force_nan_r  <= force_nan_c;
            force_zero_r <= force_zero_c;
        end
    end

//gs core
    wire [8:0] n_q;

    gs_core u_core (.clk(clk), .rst_n(rst_n), .load(load), .step(step),
                    .sig_a(sig_a), .sig_b(sig_b), .n_q(n_q));

    reg  [8:0]        n_w;
    reg  signed [5:0] exp_w;

    wire [8:0]        norm_n_in   = denorm_en ? n_w   : n_q;
    wire signed [5:0] norm_exp_in = denorm_en ? exp_w : exp_q_r;
    wire [8:0]        norm_n_out;
    wire signed [5:0] norm_exp_out;

    fp8_norm u_norm (.n_in(norm_n_in), .exp_in(norm_exp_in), .denorm(denorm_en),
                     .n_out(norm_n_out), .exp_out(norm_exp_out), .underflow(underflow));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            n_w   <= 9'd0;
            exp_w <= 6'sd0;
        end else if (norm_en || denorm_en) begin
            n_w   <= norm_n_out;
            exp_w <= norm_exp_out;
        end
    end

//round
    reg  [2:0]        frac_r;
    reg  signed [5:0] exp_r;
    wire [2:0]        round_frac;
    wire signed [5:0] round_exp;

    fp8_round u_round (.n_in(n_w), .exp_in(exp_w), .frac_out(round_frac), .exp_out(round_exp));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frac_r <= 3'd0;
            exp_r  <= 6'sd0;
        end else if (round_en) begin
            frac_r <= round_frac;
            exp_r  <= round_exp;
        end
    end

//pack
    wire [7:0] packed_result;

    fp8_pack u_pack (.sign(sign_r), .exp_in(exp_r), .frac_in(frac_r),
                     .force_nan(force_nan_r), .force_zero(force_zero_r),
                     .result(packed_result));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            result <= 8'd0;
        else if (out_en)
            result <= packed_result;
    end

endmodule