`timescale 1ns/1ps
module tb_fp8_div_simple;

    reg        clk;
    reg        rst_n;
    reg        start;
    reg        ack;
    reg  [7:0] a;
    reg  [7:0] b;
    wire       valid;
    wire [7:0] result;

    integer pass_count;
    integer fail_count;

    fp8_div dut (
        .clk   (clk),
        .rst_n (rst_n),
        .start (start),
        .ack   (ack),
        .a     (a),
        .b     (b),
        .valid (valid),
        .result(result)
    );

    // 10 ns clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Apply one division, wait for valid, check the result, then acknowledge.
    task run_test;
        input [8*14-1:0] name;
        input [7:0]      x;
        input [7:0]      y;
        input [7:0]      expected;
        integer          t;
        begin
            @(posedge clk); #1;
            a = x;  b = y;  start = 1'b1;     // pulse start for one clock
            @(posedge clk); #1;
            start = 1'b0;

            t = 0;                            // wait for valid (max 100 cycles)
            while (valid !== 1'b1 && t < 100) begin
                @(posedge clk); #1;
                t = t + 1;
            end

            if (t >= 100) begin
                $display("FAIL  %0s: timeout waiting for valid", name);
                fail_count = fail_count + 1;
            end else if (result === expected) begin
                $display("PASS  %0s: %h / %h = %h", name, x, y, result);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL  %0s: %h / %h  expected %h  got %h", name, x, y, expected, result);
                fail_count = fail_count + 1;
            end

            ack = 1'b1;                       // read result, return to idle
            @(posedge clk); #1;
            ack = 1'b0;
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        rst_n = 1'b0;
        start = 1'b0;
        ack   = 1'b0;
        a     = 8'h00;
        b     = 8'h00;

        // reset for a few clocks
        #30;
        rst_n = 1'b1;
        #20;

        // name            a      b      expected
        run_test("6.0 / 1.5",      8'h4C, 8'h3C, 8'h48);   // 4.0
        run_test("1 / 1",          8'h38, 8'h38, 8'h38);   // 1.0
        run_test("1 / 2",          8'h38, 8'h40, 8'h30);   // 0.5
        run_test("-1 / 1",         8'hB8, 8'h38, 8'hB8);   // -1.0
        run_test("-1 / -1",        8'hB8, 8'hB8, 8'h38);   // 1.0
        run_test("1.5 / 2",        8'h3C, 8'h40, 8'h34);   // 0.75
        run_test("5 / 3",          8'h4A, 8'h44, 8'h3D);   // 1.625 (rounded)
        run_test("3 / 6",          8'h44, 8'h4C, 8'h30);   // 0.5
        run_test("8 / 1",          8'h50, 8'h38, 8'h50);   // 8.0
        run_test("1 / 4",          8'h38, 8'h48, 8'h28);   // 0.25
        run_test("448 / 1",        8'h7E, 8'h38, 8'h7E);   // max finite
        run_test("min norm / 1",   8'h08, 8'h38, 8'h08);   // smallest normal
        run_test("min norm / 2",   8'h08, 8'h40, 8'h04);   // becomes subnormal
        run_test("min sub / 1",    8'h01, 8'h38, 8'h01);   // smallest subnormal
        run_test("min sub / 448",  8'h01, 8'h7E, 8'h00);   // underflow to zero
        run_test("448 / min sub",  8'h7E, 8'h01, 8'h7F);   // overflow -> NaN
        run_test("0 / 1",          8'h00, 8'h38, 8'h00);   // zero
        run_test("-0 / 1",         8'h80, 8'h38, 8'h80);   // negative zero
        run_test("1 / 0",          8'h38, 8'h00, 8'h7F);   // divide by zero -> NaN
        run_test("0 / 0",          8'h00, 8'h00, 8'h7F);   // NaN
        run_test("NaN / 1",        8'h7F, 8'h38, 8'h7F);   // NaN in
        run_test("1 / NaN",        8'h38, 8'h7F, 8'h7F);   // NaN in

        #20;
        $display("------------------------------");
        $display("passed: %0d   failed: %0d", pass_count, fail_count);
        if (fail_count == 0) $display("RESULT: ALL TESTS PASSED");
        else                 $display("RESULT: SOME TESTS FAILED");
        $finish;
    end

endmodule