`timescale 1ns/1ps
module tb_cpu;
    reg clk = 0, reset = 1;
    cpu_superscalar_10stage dut (.clk(clk), .reset(reset));
    always #5 clk = ~clk;

    function [15:0] R(input [3:0] op, input [2:0] rd, rs1, rs2);
        R = {op, rd, rs1, rs2, 3'b000};
    endfunction
    function [15:0] I(input [3:0] op, input [2:0] rd, rs1, input [5:0] imm);
        I = {op, rd, rs1, imm};
    endfunction

    localparam ADD=4'h0, SUB=4'h1, AND=4'h2, OR=4'h3, XOR=4'h4, ADDI=4'h5, LD=4'hD, ST=4'hE;

    task put(input [7:0] a, input [15:0] w);
        begin dut.imemA.mem[a] = w; dut.imemB.mem[a] = w; end
    endtask

    integer errors = 0;
    task check(input [255:0] name, input [15:0] got, input [15:0] exp);
        if (got !== exp) begin
            $display("FAIL %0s: got %h expected %h", name, got, exp); errors = errors + 1;
        end else $display("ok   %0s = %h", name, got);
    endtask

    initial begin
        put(0,  I(ADDI,1,0,6'd5));        // r1 = 5
        put(1,  I(ADDI,2,0,6'd7));        // r2 = 7
        put(2,  R(ADD, 3,1,2));           // r3 = 12   (RAW on r1,r2 -> stall)
        put(3,  R(SUB, 4,3,1));           // r4 = 7    (B depends on A -> split)
        put(4,  I(ST,  3,0,6'd2));        // mem[2] = r3
        put(5,  I(LD,  5,0,6'd2));        // r5 = mem[2] (same-bundle store->load)
        put(6,  R(XOR, 6,4,5));           // r6 = 7^12 = 11
        put(7,  R(AND, 7,6,3));           // r7 = 11&12 = 8 (split)
        put(8,  R(OR,  1,1,2));           // r1 = 5|7 = 7
        put(9,  I(ADDI,1,1,6'h3F));       // r1 = 7-1 = 6 (split)
        put(10, R(SUB, 2,0,1));           // r2 = 0-6 = FFFA
        #1; // let puts settle before reset releases
        repeat (3) @(posedge clk);
        reset = 0;
        repeat (120) @(posedge clk);
        check("r1", dut.regfile.registers[1], 16'h0006);
        check("r2", dut.regfile.registers[2], 16'hFFFA);
        check("r3", dut.regfile.registers[3], 16'h000C);
        check("r4", dut.regfile.registers[4], 16'h0007);
        check("r5", dut.regfile.registers[5], 16'h000C);
        check("r6", dut.regfile.registers[6], 16'h000B);
        check("r7", dut.regfile.registers[7], 16'h0008);
        check("mem2", dut.dmem.dmem[2], 16'h000C);
        if (errors == 0) $display("ALL TESTS PASSED"); else $display("%0d FAILURES", errors);
        $finish;
    end
endmodule