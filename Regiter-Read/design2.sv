module register_file (
    input  wire        clk,        // System Clock
    input  wire        reset,      // Active-high synchronous reset
    
    // Read Port 1 (Combinational)
    input  wire [2:0]  read_reg1,  // 3-bit address for Read Register 1
    output wire [15:0] read_data1, // 16-bit output data for Read Port 1
    
    // Read Port 2 (Combinational)
    input  wire [2:0]  read_reg2,  // 3-bit address for Read Register 2
    output wire [15:0] read_data2, // 16-bit output data for Read Port 2
    
    // Write Port (Synchronous)
    input  wire [2:0]  write_reg,  // 3-bit address for Write Register
    input  wire [15:0] write_data, // 16-bit data to be written
    input  wire        reg_write   // Write enable control signal (1 = Write)
);

    // Declare the Register Memory Array: 8 registers, each 16 bits wide
    reg [15:0] registers [0:7];
    
    integer i; // Variable used in for-loop during reset

    // Register R0 is hardwired to 16'h0000 (standard RISC convention).
  assign read_data1 = (read_reg1 == 3'b000) ? 16'h0000 : registers[read_reg1];
  assign read_data2 = (read_reg2 == 3'b000) ? 16'h0000 : registers[read_reg2];

    // Register updates happen strictly on the rising edge of the clock.
    always @(posedge clk) begin
        if (reset) begin
            // Clear all registers to zero on reset
            for (i = 0; i < 8; i = i + 1) begin
                registers[i] <= 16'h0000;
            end
        end 
        else if (reg_write && (write_reg != 3'b000)) begin
            // Write data to targeted register (prevent writing to R0)
            registers[write_reg] <= write_data;
        end
    end

endmodule