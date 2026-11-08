`timescale 1ns / 1ps

module register_file_tb;

    // Testbench Signals
    reg         clk;
    reg         reset;
    reg  [2:0]  read_reg1;
    reg  [2:0]  read_reg2;
    reg  [2:0]  write_reg;
    reg  [15:0] write_data;
    reg         reg_write;

    wire [15:0] read_data1;
    wire [15:0] read_data2;

    // Instantiate Device Under Test (DUT)
    register_file dut (
        .clk        (clk),
        .reset      (reset),
        .read_reg1  (read_reg1),
        .read_data1 (read_data1),
        .read_reg2  (read_reg2),
        .read_data2 (read_data2),
        .write_reg  (write_reg),
        .write_data (write_data),
        .reg_write  (reg_write)
    );

    // Clock Generation: 10ns period (100 MHz)
    always #5 clk = ~clk;

    // Test Stimulus Sequence
    initial begin
        // 1. Initialize Signals
        clk        = 0;
        reset      = 1;
        reg_write  = 0;
        write_reg  = 3'b000;
        write_data = 16'h0000;
        read_reg1  = 3'b000;
        read_reg2  = 3'b000;

        // Apply Reset for 2 clock cycles
        #20;
        reset = 0;
        #10;

        // 2. Write 0xABCD into Register R1
        $display("--------------------------------------------------");
      $display("TEST 1: Writing 0xFBCD to R1");
        @(posedge clk);
        write_reg  = 3'b101;     // Target R1
        write_data = 16'hFBCD;   // Value
        reg_write  = 1'b1;       // Enable write

        @(posedge clk);          // Latch write on clock edge
        reg_write  = 1'b0;       // Disable write

        // 3. Write 0x1234 into Register R2
        $display("TEST 2: Writing 0x1234 to R2");
        write_reg  = 3'b010;     // Target R2
        write_data = 16'h1234;   // Value
        reg_write  = 1'b1;       // Enable write

        @(posedge clk);          // Latch write on clock edge
        reg_write  = 1'b0;

        // 4. Read R1 (Port 1) and R2 (Port 2) simultaneously
        #5; // Wait small delay after clock edge
        read_reg1 = 3'b101; // Select R1
        read_reg2 = 3'b010; // Select R2

        #1; // Delay for combinational propagation
        $display("READ RESULTS:");
      $display("R1 Data (Port 1): Expected = 0xFBCD, Actual = 0x%h", read_data1);
        $display("R2 Data (Port 2): Expected = 0x1234, Actual = 0x%h", read_data2);

        // 5. Test R0 Hardwired Zero Protection
        $display("--------------------------------------------------");
        $display("TEST 3: Attempting to write 0xFFFF to R0");
        @(posedge clk);
        write_reg  = 3'b000;     // Target R0
        write_data = 16'hFFFF;   // Attempt value
        reg_write  = 1'b1;

        @(posedge clk);
        reg_write  = 1'b0;

        read_reg1 = 3'b000;      // Read R0
        #1;
        $display("R0 Data (Port 1): Expected = 0x0000, Actual = 0x%h", read_data1);

        $display("--------------------------------------------------");
        $finish;
    end

endmodule