module instruction_memory #(
    parameter ADDR_WIDTH = 8,        // 2^8 = 256 instruction locations
    parameter DATA_WIDTH = 16,       // 16-bit instruction words
    parameter MEM_FILE   = "program.mem" // Initial memory file
)(
    input  wire [ADDR_WIDTH-1:0] pc,         // Program Counter input address
    output wire [DATA_WIDTH-1:0] instruction // Output machine code word
);

    // Memory array declaration: 256 entries of 16-bit words
    reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

    // Initialize memory contents at simulation start
    initial begin
        // Zero-initialize memory array
        integer i;
        for (i = 0; i < (1<<ADDR_WIDTH); i = i + 1) begin
            mem[i] = {DATA_WIDTH{1'b0}};
        end

        // Load binary program into memory if file exists
        $readmemh(MEM_FILE, mem);
    end

    // COMBINATIONAL READ LOGIC
    // Output changes immediately when pc changes
    assign instruction = mem[pc];

endmodule