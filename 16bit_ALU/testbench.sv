// Code your testbench here
// or browse Examples
// ============================================================
// Testbench for alu16 (16-bit Behavioral ALU)
// ============================================================
`timescale 1ns / 1ps

module alu16_tb;

    reg  [15:0] A, B;
    reg  [3:0]  opcode;
    wire [15:0] result;
    wire        zero, carry, overflow, negative;

    integer errors = 0;
    integer tests  = 0;

    // DUT instantiation
    alu16 dut (
        .A(A),
        .B(B),
        .opcode(opcode),
        .result(result),
        .zero(zero),
        .carry(carry),
        .overflow(overflow),
        .negative(negative)
    );

    // Task to apply inputs, wait, and check against expected result
    task run_check;
        input [15:0] a_in;
        input [15:0] b_in;
        input [3:0]  op_in;
        input [15:0] expected;
        input [127:0] name; // string label for the op
        begin
            A = a_in; B = b_in; opcode = op_in;
            #5;
            tests = tests + 1;
            if (result !== expected) begin
                errors = errors + 1;
                $display("FAIL [%0s] A=%h B=%h op=%b => result=%h expected=%h",
                          name, a_in, b_in, op_in, result, expected);
            end else begin
                $display("PASS [%0s] A=%h B=%h op=%b => result=%h (zero=%b carry=%b ovf=%b neg=%b)",
                          name, a_in, b_in, op_in, result, zero, carry, overflow, negative);
            end
        end
    endtask

    initial begin
        $display("---------------------------------------------------");
        $display(" Starting alu16 testbench");
        $display("---------------------------------------------------");

        // ADD
        run_check(16'h0005, 16'h0003, 4'b0000, 16'h0008, "ADD");
        run_check(16'hFFFF, 16'h0001, 4'b0000, 16'h0000, "ADD_carry"); // carry out, zero result

        // SUB
        run_check(16'h0008, 16'h0003, 4'b0001, 16'h0005, "SUB");
        run_check(16'h0000, 16'h0001, 4'b0001, 16'hFFFF, "SUB_borrow");

        // AND / OR / XOR / NOR / NOT
        run_check(16'hFF00, 16'h0FF0, 4'b0010, 16'h0F00, "AND");
        run_check(16'hFF00, 16'h0FF0, 4'b0011, 16'hFFF0, "OR");
        run_check(16'hFF00, 16'h0FF0, 4'b0100, 16'hF0F0, "XOR");
        run_check(16'h0000, 16'h0000, 4'b0101, 16'hFFFF, "NOR");
        run_check(16'h00FF, 16'h0000, 4'b0110, 16'hFF00, "NOT");

        // Shifts
        run_check(16'h0001, 16'h0004, 4'b0111, 16'h0010, "SLL");
        run_check(16'h0010, 16'h0004, 4'b1000, 16'h0001, "SRL");
        run_check(16'hFFF0, 16'h0004, 4'b1001, 16'hFFFF, "SRA_negative");

        // Comparisons
        run_check(16'hFFFF, 16'h0001, 4'b1010, 16'h0001, "SLT_signed(-1<1)");
        run_check(16'hFFFF, 16'h0001, 4'b1011, 16'h0000, "SLTU(0xFFFF<1? no)");

        // MUL
        run_check(16'h0003, 16'h0004, 4'b1100, 16'h000C, "MUL");
        run_check(16'hFFFF, 16'h0002, 4'b1100, 16'hFFFE, "MUL_wrap");

        // INC / DEC / PASS
        run_check(16'h0009, 16'h0000, 4'b1101, 16'h000A, "INC");
        run_check(16'h0009, 16'h0000, 4'b1110, 16'h0008, "DEC");
        run_check(16'hABCD, 16'h0000, 4'b1111, 16'hABCD, "PASS");

        $display("---------------------------------------------------");
        if (errors == 0)
            $display(" ALL %0d TESTS PASSED", tests);
        else
            $display(" %0d / %0d TESTS FAILED", errors, tests);
        $display("---------------------------------------------------");

        $finish;
    end

endmodule