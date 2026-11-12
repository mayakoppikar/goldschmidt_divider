module gs_core (
    input        clk,
    input        rst_n,
    input        load,
    input        step,
    input  [3:0] sig_a,
    input  [3:0] sig_b,
    output [8:0] n_q
);

    reg  [8:0] n_reg, d_reg;
    wire [8:0] f;  // F = 2 - D
    wire [8:0] n_next, d_next;

    assign f = ~d_reg + 9'd1;

    fx_mul mul_N (.a(n_reg), .b(f), .p(n_next));
    fx_mul mul_D (.a(d_reg), .b(f), .p(d_next));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            n_reg <= 9'd0;
            d_reg <= 9'd0;
        end else if (load) begin
            n_reg <= {1'b0, sig_a, 4'b0000};
            d_reg <= {1'b0, sig_b, 4'b0000};
        end else if (step) begin
            n_reg <= n_next;
            d_reg <= d_next;
        end
    end

    assign n_q = n_reg;

endmodule