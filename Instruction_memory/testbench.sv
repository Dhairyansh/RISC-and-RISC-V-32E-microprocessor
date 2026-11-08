`timescale 1ns / 1ps

module instruction_memory_tb;

    // 1. Declare Parameters (matches DUT parameters)
    parameter ADDR_WIDTH = 8;
    parameter DATA_WIDTH = 16;

    // 2. Declare Signals for Connecting to Device Under Test (DUT)
    reg  [ADDR_WIDTH-1:0] pc;          // Driven by testbench (reg type)
    wire [DATA_WIDTH-1:0] instruction; // Observed from memory (wire type)

    // 3. Instantiate the Device Under Test (DUT)
    instruction_memory #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_FILE("program.mem")
    ) dut (
        .pc(pc),
        .instruction(instruction)
    );

    // 4. Test Stimulus Sequence
    initial begin
        // Setup Waveform Dumping for GTKWave
        $dumpfile("instruction_memory_tb.vcd"); // Name of waveform output file
        $dumpvars(0, instruction_memory_tb);   // Dump all signals in this module

        $display("==================================================");
        $display("    TESTBENCH: Instruction Memory Verification    ");
        $display("==================================================");
        $display("PC Address | Fetched Instruction Code");
        $display("-----------|--------------------------");

        // Test Address 0x00
        pc = 8'h00;
        #10; // Wait 10ns for combinational propagation delay
        $display("   0x%02h    |          0x%04h", pc, instruction);

        // Test Address 0x01
        pc = 8'h01;
        #10;
        $display("   0x%02h    |          0x%04h", pc, instruction);

        // Test Address 0x02
        pc = 8'h02;
        #10;
        $display("   0x%02h    |          0x%04h", pc, instruction);

        // Test Address 0x03
        pc = 8'h03;
        #10;
        $display("   0x%02h    |          0x%04h", pc, instruction);

        // Test Address 0x04
        pc = 8'h04;
        #10;
        $display("   0x%02h    |          0x%04h", pc, instruction);

        // Test Boundary Address (255 / 0xFF)
        pc = 8'hFF;
        #10;
        $display("   0x%02h    |          0x%04h (Uninitialized address)", pc, instruction);

        $display("==================================================");
        $finish; // End simulation
    end

endmodule