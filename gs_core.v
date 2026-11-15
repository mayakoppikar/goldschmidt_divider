
module gs_core #(
    parameter CORRECTION = 1
) (
    input        clk,
    input        rst_n,
    input        load,
    input        step,
    input        correct,
    input        bypass,
    input  [3:0] sig_a,
    input  [3:0] sig_b,
    output [8:0] n_q
);

    reg  [8:0] n_reg, d_reg;
    wire [8:0] f;               // F = 2 - D
    wire [8:0] n_next, d_next;
    wire [8:0] n_fix;           // N after the exact remainder correction


    assign f = ~d_reg + 9'd1;

    fx_mul u_mul_n (.a(n_reg), .b(f), .p(n_next));
    fx_mul u_mul_d (.a(d_reg), .b(f), .p(d_next));

    // ---------------- exact remainder correction (optional) ----------------
    generate
        if (CORRECTION) begin : g_corr
            wire [12:0]        prod = n_reg * sig_b;                 // N * sig_b, at most 7665
            wire signed [14:0] rem  = $signed({3'b000, sig_a, 8'b00000000})
                                    - $signed({2'b00, prod});        // sig_a*256 - N*sig_b
            wire signed [14:0] b1   = $signed({11'b00000000000, sig_b});
            wire signed [14:0] b2   = b1 <<< 1;

            reg  [8:0]         n_corr;
            reg  signed [14:0] rem_f;                                // remainder after correction

            always @(*) begin
                if (rem < 0) begin
                    n_corr = n_reg - 9'd1;   rem_f = rem + b1;
                end else if (rem < b1) begin
                    n_corr = n_reg;          rem_f = rem;
                end else if (rem < b2) begin
                    n_corr = n_reg + 9'd1;   rem_f = rem - b1;
                end else begin
                    n_corr = n_reg + 9'd2;   rem_f = rem - b2;
                end
            end

            wire sticky = (rem_f != 0);
            assign n_fix = {n_corr[8:1], n_corr[0] | sticky};        // sticky jammed into bit 0
        end else begin : g_nocorr
            assign n_fix = n_reg;                                    // no correction hardware
        end
    endgenerate

    // ---------------- registers ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            n_reg <= 9'd0;
            d_reg <= 9'd0;
        end else if (load) begin
            n_reg <= bypass ? {sig_a, 5'b00000}        // exact quotient sig_a / 8
                            : {1'b0, sig_a, 4'b0000};  // sig_a / 2
            d_reg <= {1'b0, sig_b, 4'b0000};
        end else if (correct && CORRECTION) begin
            n_reg <= n_fix;
        end else if (step) begin
            n_reg <= n_next;
            d_reg <= d_next;
        end
    end

    assign n_q = n_reg;

endmodule
