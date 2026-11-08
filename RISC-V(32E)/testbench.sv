`timescale 1ns/1ps
module tb_cpu_rv32e;
    reg clk = 0, reset = 1;
    
    // Updated DUT instantiation for a 32-bit RISC-V processor
    cpu_rv32e_superscalar_10stage dut (.clk(clk), .reset(reset));
    
    always #5 clk = ~clk;

    // Standard RISC-V 32-bit Instruction Encoding Functions
    // R-type: funct7 | rs2 | rs1 | funct3 | rd | opcode
    function [31:0] R_type(input [6:0] op, input [2:0] f3, input [6:0] f7, input [4:0] rd, rs1, rs2);
        R_type = {f7, rs2, rs1, f3, rd, op};
    endfunction

    // I-type: imm[11:0] | rs1 | funct3 | rd | opcode
    function [31:0] I_type(input [6:0] op, input [2:0] f3, input [4:0] rd, rs1, input [11:0] imm);
        I_type = {imm, rs1, f3, rd, op};
    endfunction

    // S-type: imm[11:5] | rs2 | rs1 | funct3 | imm[4:0] | opcode
    function [31:0] S_type(input [6:0] op, input [2:0] f3, input [4:0] rs1, rs2, input [11:0] imm);
        S_type = {imm[11:5], rs2, rs1, f3, imm[4:0], op};
    endfunction

    // RISC-V Standard Opcodes
    localparam OP_ALU  = 7'h33; // 0110011
    localparam OP_ALUI = 7'h13; // 0010011
    localparam OP_LOAD = 7'h03; // 0000011
    localparam OP_STORE= 7'h23; // 0100011

    // 32-bit data width for the instruction memory loader
    task put(input [31:0] a, input [31:0] w);
        begin dut.imemA.mem[a/4] = w; dut.imemB.mem[a/4] = w; end // Assuming word-aligned addressing in DUT's memory array
    endtask

    integer errors = 0;
    task check(input [255:0] name, input [31:0] got, input [31:0] exp);
        if (got !== exp) begin
            $display("FAIL %0s: got %h expected %h", name, got, exp); errors = errors + 1;
        end else $display("ok   %0s = %h", name, got);
    endtask

    initial begin
        // RISC-V Assembly Program (x1=10, x2=14)
        
        // 0: ADDI x1, x0, 10
      put(0,  I_type(OP_ALUI, 3'b000, 1, 0, 12'd10));  
        
        // 4: ADDI x2, x0, 14
        put(4,  I_type(OP_ALUI, 3'b000, 2, 0, 12'd14));  
        
        // 8: ADD x3, x1, x2 -> x3 = 24
        put(8,  R_type(OP_ALU,  3'b000, 7'b0000000, 3, 1, 2)); 
        
        // 12: SUB x4, x3, x1 -> x4 = 14
        put(12, R_type(OP_ALU,  3'b000, 7'b0100000, 4, 3, 1)); 
        
        // 16: SW x3, 8(x0) -> mem[8] = x3. (Offset 8 is word index 2 in byte-addressed memory)
        put(16, S_type(OP_STORE,3'b010, 0, 3, 12'd8)); 
        
        // 20: LW x5, 8(x0) -> x5 = mem[8] (24)
        put(20, I_type(OP_LOAD, 3'b010, 5, 0, 12'd8)); 
        
        // 24: XOR x6, x4, x5 -> x6 = 14 ^ 24 = 22
        put(24, R_type(OP_ALU,  3'b100, 7'b0000000, 6, 4, 5)); 
        
        // 28: AND x7, x6, x3 -> x7 = 22 & 24 = 16
        put(28, R_type(OP_ALU,  3'b111, 7'b0000000, 7, 6, 3)); 
        
        // 32: OR x1, x1, x2 -> x1 = 10 | 14 = 14
        put(32, R_type(OP_ALU,  3'b110, 7'b0000000, 1, 1, 2)); 
        
        // 36: ADDI x1, x1, -1 -> x1 = 13 (12'hFFF is -1 in 12-bit two's complement)
        put(36, I_type(OP_ALUI, 3'b000, 1, 1, 12'hFFF)); 
        
        // 40: SUB x2, x0, x1 -> x2 = 0 - 13 = -13
        put(40, R_type(OP_ALU,  3'b000, 7'b0100000, 2, 0, 1)); 

        #1; 
        repeat (3) @(posedge clk);
        reset = 0;
        repeat (120) @(posedge clk);
        
        // 32-bit Hexadecimal Checks
        check("x1", dut.regfile.registers[1], 32'h0000000D); // 13
        check("x2", dut.regfile.registers[2], 32'hFFFFFFF3); // -13
        check("x3", dut.regfile.registers[3], 32'h00000018); // 24
        check("x4", dut.regfile.registers[4], 32'h0000000E); // 14
        check("x5", dut.regfile.registers[5], 32'h00000018); // 24
        check("x6", dut.regfile.registers[6], 32'h00000016); // 22
        check("x7", dut.regfile.registers[7], 32'h00000010); // 16
        
        // Checking word address 2 (byte address 8)
        check("mem8", dut.dmem.dmem[2], 32'h00000018); 
        
        if (errors == 0) $display("ALL TESTS PASSED"); else $display("%0d FAILURES", errors);
        $finish;
    end
endmodule