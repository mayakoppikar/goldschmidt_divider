module fp8_div_ctrl #(
    parameter CORRECTION = 1
) (
    input        clk,
    input        rst_n,
    input        start,
    input        ack,
    input        is_special,
    input        underflow,
    input  [1:0] iters,
    output reg   load,
    output reg   step,
    output reg   corr_en,
    output reg   norm_en,
    output reg   denorm_en,
    output reg   round_en,
    output reg   out_en,
    output reg   valid
);

    localparam [3:0] S_IDLE    = 4'd0,
                     S_UNPACK  = 4'd1,
                     S_ITERATE = 4'd2,
                     S_NORM    = 4'd3,   // NORMALIZE
                     S_DENORM  = 4'd4,   // DENORMALIZE
                     S_ROUND   = 4'd5,
                     S_PACK    = 4'd6,
                     S_SPECIAL = 4'd7,   // OUTPUT_SPECIAL
                     S_DONE    = 4'd8,
                     S_CORRECT = 4'd9;

    reg [3:0] state, next_state;
    reg [3:0] cnt;                       // pass counter

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                   cnt <= 4'd0;
        else if (state == S_UNPACK)   cnt <= 4'd0;
        else if (state == S_ITERATE)  cnt <= cnt + 4'd1;
    end

    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:    if (start) next_state = S_UNPACK;
            S_UNPACK:  if (is_special)         next_state = S_SPECIAL;
                       else if (iters == 2'd0) next_state = S_NORM;      // bypass: exact, no passes
                       else                    next_state = S_ITERATE;
            S_ITERATE: if ((cnt + 4'd1) == {2'b00, iters})                // last pass
                           next_state = CORRECTION ? S_CORRECT : S_NORM;
            S_CORRECT: next_state = S_NORM;
            S_NORM:    next_state = underflow ? S_DENORM : S_ROUND;
            S_DENORM:  next_state = S_ROUND;
            S_ROUND:   next_state = S_PACK;
            S_PACK:    next_state = S_DONE;
            S_SPECIAL: next_state = S_DONE;
            S_DONE:    if (ack) next_state = S_IDLE;
            default:   next_state = S_IDLE;
        endcase
    end

    always @(*) begin
        load      = 1'b0;
        step      = 1'b0;
        corr_en   = 1'b0;
        norm_en   = 1'b0;
        denorm_en = 1'b0;
        round_en  = 1'b0;
        out_en    = 1'b0;
        valid     = 1'b0;
        case (state)
            S_UNPACK:  load      = 1'b1;
            S_ITERATE: step      = 1'b1;
            S_CORRECT: corr_en   = 1'b1;
            S_NORM:    norm_en   = 1'b1;
            S_DENORM:  denorm_en = 1'b1;
            S_ROUND:   round_en  = 1'b1;
            S_PACK:    out_en    = 1'b1;
            S_SPECIAL: out_en    = 1'b1;
            S_DONE:    valid     = 1'b1;
            default: ;
        endcase
    end

endmodule
