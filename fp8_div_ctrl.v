// fp8_div_ctrl: 9-state FSM and pass counter for the FP8 Goldschmidt divider.
// Moore outputs: each enable is high for the whole state and the datapath latches
// at the end of that cycle.
//
//   IDLE              wait for start
//   UNPACK            load = 1; is_special -> OUTPUT_SPECIAL;
//                     iters == 0 (power-of-two divisor) -> NORMALIZE_RESULT;
//                     otherwise -> ITERATE
//   ITERATE           step = 1, repeated `iters` times (pass counter)
//   NORMALIZE_RESULT  norm_en = 1; underflow -> DENORMALIZE, else -> ROUND
//   DENORMALIZE       denorm_en = 1
//   ROUND             round_en = 1
//   PACK              out_en = 1
//   OUTPUT_SPECIAL    out_en = 1 (fp8_pack forces NaN or zero)
//   DONE              valid = 1, hold until ack
//
// iters (0..3) comes from fp8_div_dp and depends only on the divisor significand:
//   0 = power-of-two divisor (bypass), 1, 2 or 3 Goldschmidt passes.
// Latency start -> DONE (normal path): UNPACK 1 + iters + NORMALIZE 1 + ROUND 1 + PACK 1
//   = iters + 4 cycles; +1 if DENORMALIZE; special cases take 2.
module fp8_div_ctrl (
    input        clk,
    input        rst_n,
    input        start,
    input        ack,
    input        is_special,
    input        underflow,
    input  [1:0] iters,
    output reg   load,
    output reg   step,
    output reg   norm_en,
    output reg   denorm_en,
    output reg   round_en,
    output reg   out_en,
    output reg   valid
);

    localparam [3:0] S_IDLE    = 4'd0,
                     S_UNPACK  = 4'd1,
                     S_ITERATE = 4'd2,
                     S_NORM    = 4'd3,   // NORMALIZE_RESULT
                     S_DENORM  = 4'd4,   // DENORMALIZE
                     S_ROUND   = 4'd5,
                     S_PACK    = 4'd6,
                     S_SPECIAL = 4'd7,   // OUTPUT_SPECIAL
                     S_DONE    = 4'd8;

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
                       else if (iters == 2'd0) next_state = S_NORM;      // bypass: no passes
                       else                    next_state = S_ITERATE;
            S_ITERATE: if ((cnt + 4'd1) == {2'b00, iters}) next_state = S_NORM;  // last pass
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
        norm_en   = 1'b0;
        denorm_en = 1'b0;
        round_en  = 1'b0;
        out_en    = 1'b0;
        valid     = 1'b0;
        case (state)
            S_UNPACK:  load      = 1'b1;
            S_ITERATE: step      = 1'b1;
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
