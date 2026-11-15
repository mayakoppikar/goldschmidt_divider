`timescale 1ns/1ps
// tb_fp8_div_flags: self-checking testbench for fp8_div with selectable EARLY_EXIT and
// CORRECTION flags. The same testbench checks all four configurations; change the two
// parameters (generics) to select one.
//
//   EARLY_EXIT = 0, CORRECTION = 0 : fixed 3 passes, no correction (baseline)
//   EARLY_EXIT = 0, CORRECTION = 1 : fixed 3 passes, exact remainder correction
//   EARLY_EXIT = 1, CORRECTION = 0 : passes set by the divisor, power-of-two bypass
//   EARLY_EXIT = 1, CORRECTION = 1 : both
//
// Every one of the 65,536 (a, b) pairs is checked, plus a few verbose directed cases.
// For each vector it checks:
//   1. result   : CORRECTION = 1 must equal the correctly rounded quotient (MAX_ULP = 0);
//                 CORRECTION = 0 must be within MAX_ULP = 1 step of it.
//   2. passes   : number of Goldschmidt passes actually run (counts the `step` pulses)
//                 3 if EARLY_EXIT = 0; otherwise 0 (power-of-two divisor 1.000),
//                 3 (1.125 to 1.375), 2 (1.5 to 1.75), 1 (1.875). 0 for special inputs.
//   3. latency  : cycles from start to valid =
//                 special inputs: 2
//                 otherwise: passes + 4, + 1 if CORRECTION and passes > 0, + 1 if the
//                 result needed DENORMALIZE (counted from the denorm_en pulse, 0 or 1).
// Prints PASS if no vector fails any check, otherwise FAIL, plus statistics.
//
// Vivado: add all design .v files as Design Sources and this file as the Simulation Source
// (top). To change the flags before launching:
//   set_property generic {EARLY_EXIT=0 CORRECTION=1} [get_filesets sim_1]
//   launch_simulation ; run all
// To run all four configurations in a row from the Tcl console:
//   foreach cfg {{0 0} {0 1} {1 0} {1 1}} {
//     set_property generic "EARLY_EXIT=[lindex $cfg 0] CORRECTION=[lindex $cfg 1]" [get_filesets sim_1]
//     launch_simulation ; run all ; close_sim
//   }
module tb_fp8_div_flags;

    parameter EARLY_EXIT   = 1;
    parameter CORRECTION   = 1;
    parameter MAX_ULP      = CORRECTION ? 0 : 1;  // allowed result error in steps
    parameter SHOW_FAILS   = 20;                  // failing vectors to print
    parameter TRACE_FIRST  = 3;                   // vectors with an FSM trace printed
    parameter TIMEOUT      = 100;                 // cycles to wait for valid

    reg        clk   = 1'b0;
    reg        rst_n = 1'b0;
    reg        start = 1'b0;
    reg        ack   = 1'b0;
    reg  [7:0] a     = 8'd0;
    reg  [7:0] b     = 8'd0;
    wire       valid;
    wire [7:0] result;

    fp8_div #(.EARLY_EXIT(EARLY_EXIT), .CORRECTION(CORRECTION)) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .ack(ack),
        .a(a), .b(b), .valid(valid), .result(result)
    );

    always #5 clk = ~clk;          // 10 ns clock

    // ------------------------------------------------------------------
    // Golden model: correctly rounded quotient (round to nearest even,
    // overflow -> NaN 0x7F, NaN operand or divide by zero -> NaN, zero dividend -> zero)
    // ------------------------------------------------------------------
    function real decode_mag;
        input [6:0] c;
        integer ee;
        real    mm;
        begin
            ee = c[6:3];
            mm = c[2:0];
            if (ee == 0) decode_mag = (mm / 8.0) * $pow(2.0, -6.0);
            else         decode_mag = (1.0 + mm / 8.0) * $pow(2.0, ee - 7);
        end
    endfunction

    function [7:0] golden;
        input [7:0] x;
        input [7:0] y;
        integer i, best_i;
        real    q, v, d, best_d;
        reg     s;
        begin
            s = x[7] ^ y[7];
            if (x[6:0] == 7'h7F || y[6:0] == 7'h7F || y[6:0] == 7'h00)
                golden = 8'h7F;
            else if (x[6:0] == 7'h00)
                golden = {s, 7'h00};
            else begin
                q      = decode_mag(x[6:0]) / decode_mag(y[6:0]);
                best_d = 1.0e30;
                best_i = 0;
                for (i = 0; i <= 127; i = i + 1) begin
                    v = decode_mag(i);
                    d = (v > q) ? (v - q) : (q - v);
                    if (d < best_d || (d == best_d && best_i % 2 == 1 && i % 2 == 0)) begin
                        best_d = d;
                        best_i = i;
                    end
                end
                if (best_i == 127) golden = 8'h7F;   // rounds to 480 -> overflow -> NaN
                else               golden = {s, best_i[6:0]};
            end
        end
    endfunction

    // distance in steps (NaN counts as magnitude 0x7F; sign ignored for NaN and for zeros)
    function integer dist;
        input [7:0] g;
        input [7:0] r;
        integer mg, mr;
        begin
            mg = g[6:0];
            mr = r[6:0];
            if (g[6:0] == 7'h7F || r[6:0] == 7'h7F || (mg == 0 && mr == 0))
                dist = (mg > mr) ? (mg - mr) : (mr - mg);
            else if (g[7] != r[7])
                dist = 1000;
            else
                dist = (mg > mr) ? (mg - mr) : (mr - mg);
        end
    endfunction

    // ------------------------------------------------------------------
    // Expected behaviour of the flags
    // ------------------------------------------------------------------
    function is_special;               // NaN or zero operand: skips the divide
        input [7:0] x;
        input [7:0] y;
        begin
            is_special = (x[6:0] == 7'h7F) || (y[6:0] == 7'h7F) ||
                         (y[6:0] == 7'h00) || (x[6:0] == 7'h00);
        end
    endfunction

    function integer exp_passes;       // expected Goldschmidt passes
        input [7:0] x;
        input [7:0] y;
        reg [2:0] m;                   // stored mantissa of the normalized divisor significand
        begin
            if (is_special(x, y)) exp_passes = 0;
            else if (!EARLY_EXIT) exp_passes = 3;
            else begin
                if (y[6:3] == 4'd0) begin          // subnormal divisor: normalized by the unpack block
                    casez (y[2:0])
                        3'b1??:  m = {y[1:0], 1'b0};
                        3'b01?:  m = {y[0], 2'b00};
                        default: m = 3'b000;
                    endcase
                end else
                    m = y[2:0];
                if (m == 3'b000)      exp_passes = 0;   // power-of-two divisor: bypass
                else if (m == 3'b111) exp_passes = 1;
                else if (m[2])        exp_passes = 2;
                else                  exp_passes = 3;
            end
        end
    endfunction

    function integer exp_base_lat;     // expected latency before the optional DENORMALIZE cycle
        input [7:0] x;
        input [7:0] y;
        integer p;
        begin
            p = exp_passes(x, y);
            if (is_special(x, y)) exp_base_lat = 2;
            else                  exp_base_lat = p + 4 + ((CORRECTION && p != 0) ? 1 : 0);
        end
    endfunction

    // ------------------------------------------------------------------
    // Monitoring
    // ------------------------------------------------------------------
    reg     trace = 1'b0;
    integer steps = 0, dcnt = 0;

    function [8*16-1:0] sname;
        input [3:0] s;
        begin
            case (s)
                4'd0:    sname = "IDLE";
                4'd1:    sname = "UNPACK";
                4'd2:    sname = "ITERATE";
                4'd3:    sname = "NORMALIZE";
                4'd4:    sname = "DENORMALIZE";
                4'd5:    sname = "ROUND";
                4'd6:    sname = "PACK";
                4'd7:    sname = "OUTPUT_SPECIAL";
                4'd8:    sname = "DONE";
                4'd9:    sname = "CORRECT";
                default: sname = "???";
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (dut.step)      steps = steps + 1;      // Goldschmidt passes
        if (dut.denorm_en) dcnt  = dcnt + 1;       // DENORMALIZE cycles
    end

    always @(posedge clk) begin
        if (trace)
            $display("    t=%0t  state=%0s  cnt=%0d  iters=%0d  N=%h  D=%h  valid=%b",
                     $time, sname(dut.u_ctrl.state), dut.u_ctrl.cnt, dut.iters,
                     dut.u_dp.u_core.n_reg, dut.u_dp.u_core.d_reg, valid);
    end

    // ------------------------------------------------------------------
    // One division through the start / valid / ack handshake, then check it
    // ------------------------------------------------------------------
    integer vec_idx, n_exact, n_near, n_bad_res, n_bad_pass, n_bad_lat, n_bad_any;
    integer cyc_total, n_timeout;

    task run_vec;
        input [7:0] x;
        input [7:0] y;
        input       verbose;
        integer t, lat, dd, exp_p, exp_l;
        reg [7:0] got, exp_r;
        reg       res_ok, pass_ok, lat_ok;
        begin
            trace = (vec_idx < TRACE_FIRST);
            steps = 0;
            dcnt  = 0;
            if (trace) $display("  --- trace: %h / %h ---", x, y);

            @(posedge clk); #1;
            a = x;  b = y;  start = 1'b1;
            @(posedge clk); #1;
            start = 1'b0;

            lat = -1;  t = 0;
            while (lat < 0 && t < TIMEOUT) begin
                @(posedge clk); #1;
                t = t + 1;
                if (valid) lat = t;
            end
            got = result;
            if (lat < 0) n_timeout = n_timeout + 1;

            exp_r = golden(x, y);
            exp_p = exp_passes(x, y);
            exp_l = exp_base_lat(x, y) + dcnt;

            dd      = dist(exp_r, got);
            res_ok  = (dd <= MAX_ULP);
            pass_ok = (steps == exp_p);
            lat_ok  = (lat == exp_l) && (dcnt <= 1) && !(is_special(x, y) && dcnt != 0);

            if (dd == 0)           n_exact = n_exact + 1;
            else if (res_ok)       n_near  = n_near + 1;
            if (!res_ok)           n_bad_res  = n_bad_res + 1;
            if (!pass_ok)          n_bad_pass = n_bad_pass + 1;
            if (!lat_ok)           n_bad_lat  = n_bad_lat + 1;
            if (!res_ok || !pass_ok || !lat_ok) begin
                n_bad_any = n_bad_any + 1;
                if (n_bad_any <= SHOW_FAILS)
                    $display("FAIL  a=%h b=%h | result got=%h expected=%h (%0d step) | passes got=%0d exp=%0d | cycles got=%0d exp=%0d",
                             x, y, got, exp_r, dd, steps, exp_p, lat, exp_l);
            end
            if (lat > 0) cyc_total = cyc_total + lat;

            if (verbose)
                $display("  %h / %h -> %h (expected %h, %0d step)  passes=%0d  cycles=%0d  %s",
                         x, y, got, exp_r, dd, steps, lat,
                         (res_ok && pass_ok && lat_ok) ? "ok" : "FAIL");

            trace = 1'b0;
            ack   = 1'b1;
            @(posedge clk); #1;
            ack   = 1'b0;
            vec_idx = vec_idx + 1;
        end
    endtask

    // ------------------------------------------------------------------
    // Main
    // ------------------------------------------------------------------
    integer ia, ib;

    initial begin
        vec_idx = 0; n_exact = 0; n_near = 0;
        n_bad_res = 0; n_bad_pass = 0; n_bad_lat = 0; n_bad_any = 0;
        cyc_total = 0; n_timeout = 0;

        $display("=== fp8_div  EARLY_EXIT=%0d  CORRECTION=%0d  (allowed result error: %0d step) ===",
                 EARLY_EXIT, CORRECTION, MAX_ULP);

        #30;  rst_n = 1'b1;  #20;

        $display("--- directed cases ---");
        run_vec(8'h50, 8'h3F, 1);   // 8.0 / 1.875  : needs the correction for exact rounding
        run_vec(8'h4C, 8'h3C, 1);   // 6.0 / 1.5    = 4.0
        run_vec(8'h3E, 8'h38, 1);   // 1.75 / 1.0   : power-of-two divisor
        run_vec(8'h38, 8'h3F, 1);   // 1.0 / 1.875  : 1 pass
        run_vec(8'h7E, 8'h01, 1);   // 448 / minsub : overflow -> NaN
        run_vec(8'h01, 8'h38, 1);   // minsub / 1.0 : DENORMALIZE
        run_vec(8'h38, 8'h00, 1);   // 1 / 0        : NaN

        $display("--- exhaustive: all 65536 operand pairs ---");
        vec_idx = 0;
        n_exact = 0; n_near = 0; n_bad_res = 0; n_bad_pass = 0; n_bad_lat = 0; n_bad_any = 0;
        cyc_total = 0; n_timeout = 0;
        for (ia = 0; ia < 256; ia = ia + 1)
            for (ib = 0; ib < 256; ib = ib + 1)
                run_vec(ia[7:0], ib[7:0], 0);

        #20;
        $display("-----------------------------------------------------------");
        $display("config      : EARLY_EXIT=%0d  CORRECTION=%0d", EARLY_EXIT, CORRECTION);
        $display("vectors     : %0d", vec_idx);
        $display("results     : %0d exact, %0d within %0d step, %0d wrong", n_exact, n_near, MAX_ULP, n_bad_res);
        $display("pass count  : %0d wrong", n_bad_pass);
        $display("latency     : %0d wrong, %0d timeouts", n_bad_lat, n_timeout);
        $display("avg cycles  : %0d.%02d per division", cyc_total / vec_idx, ((cyc_total % vec_idx) * 100) / vec_idx);
        if (n_bad_any == 0 && n_timeout == 0) $display("RESULT: PASS");
        else                                  $display("RESULT: FAIL");
        $finish;
    end

    // watchdog
    initial begin
        #400000000;
        $display("RESULT: FAIL (watchdog timeout)");
        $finish;
    end

endmodule
