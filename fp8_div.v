
module fp8_div #(
    parameter ITER = 3                 // Goldschmidt passes
) (
    input        clk,
    input        rst_n,
    input        start,
    input        ack,
    input  [7:0] a,
    input  [7:0] b,
    output       valid,
    output [7:0] result
);

    // ---------------- operand capture ----------------
    reg [7:0] a_r, b_r;
    reg       busy;                    // set when an operation is accepted, cleared on ack

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_r  <= 8'd0;
            b_r  <= 8'd0;
            busy <= 1'b0;
        end else begin
            if (start && !busy) begin
                a_r  <= a;
                b_r  <= b;
                busy <= 1'b1;
            end else if (ack) begin
                busy <= 1'b0;
            end
        end
    end

    // ---------------- control <-> datapath ----------------
    wire load, step, norm_en, denorm_en, round_en, out_en;
    wire is_special, underflow;

    fp8_div_ctrl #(.ITER(ITER)) u_ctrl (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (start),
        .ack       (ack),
        .is_special(is_special),
        .underflow (underflow),
        .load      (load),
        .step      (step),
        .norm_en   (norm_en),
        .denorm_en (denorm_en),
        .round_en  (round_en),
        .out_en    (out_en),
        .valid     (valid)
    );

    fp8_div_dp u_dp (
        .clk       (clk),
        .rst_n     (rst_n),
        .a         (a_r),
        .b         (b_r),
        .load      (load),
        .step      (step),
        .norm_en   (norm_en),
        .denorm_en (denorm_en),
        .round_en  (round_en),
        .out_en    (out_en),
        .is_special(is_special),
        .underflow (underflow),
        .result    (result)
    );

endmodule