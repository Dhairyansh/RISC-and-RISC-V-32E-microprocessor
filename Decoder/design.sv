// ============================================================
// 1. INSTRUCTION MEMORY
// ============================================================
module instruction_memory #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 16
)(
    input  wire [ADDR_WIDTH-1:0] pc,
    output wire [DATA_WIDTH-1:0] instruction
);
    reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

    initial begin
        // Inline memory initialization for self-containment
        integer i;
        for (i = 0; i < (1<<ADDR_WIDTH); i = i + 1) mem[i] = 16'hF000; // PASS (NOP)
        
        // Example program
        mem[0] = 16'h0248; // ADD R1, R1, R0
        mem[1] = 16'h1488; // SUB R2, R1, R1 
        mem[2] = 16'h26C8; // AND R3, R1, R1
        mem[3] = 16'h0800; // ADD R4, R0, R0
    end

    assign instruction = mem[pc];
endmodule

// ============================================================
// 2. 4-READ / 2-WRITE REGISTER FILE
// ============================================================
module regfile_4R2W (
    input  wire        clk,
    input  wire        reset,
    
    input  wire [2:0]  rA1, output wire [15:0] dA1,
    input  wire [2:0]  rA2, output wire [15:0] dA2,
    
    input  wire [2:0]  rB1, output wire [15:0] dB1,
    input  wire [2:0]  rB2, output wire [15:0] dB2,
    
    input  wire [2:0]  wA, input wire [15:0] wdA, input wire weA,
    input  wire [2:0]  wB, input wire [15:0] wdB, input wire weB
);
    reg [15:0] registers [0:7];
    integer i;

    assign dA1 = (rA1 == 3'b000) ? 16'h0000 : registers[rA1];
    assign dA2 = (rA2 == 3'b000) ? 16'h0000 : registers[rA2];
    assign dB1 = (rB1 == 3'b000) ? 16'h0000 : registers[rB1];
    assign dB2 = (rB2 == 3'b000) ? 16'h0000 : registers[rB2];

    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 8; i = i + 1) registers[i] <= 16'h0000;
        end else begin
            if (weB && (wB != 3'b000)) registers[wB] <= wdB;
            if (weA && (wA != 3'b000)) registers[wA] <= wdA;
        end
    end
endmodule

// ============================================================
// 3. INSTRUCTION DECODER
// ============================================================
module decoder (
    input wire [15:0] instruction,
    output wire [3:0] opcode,
    output wire [2:0] rd,
    output wire [2:0] rs1,
    output wire [2:0] rs2,
    output wire [3:0] alu_opcode,
    output reg        reg_write
);
    assign opcode = instruction[15:12];
    assign rd  = instruction[11:9];
    assign rs1 = instruction[8:6];
    assign rs2 = instruction[5:3];
    assign alu_opcode = opcode;

    always @(*) begin
        case (opcode)
            4'b0000, 4'b0001, 4'b0010, 4'b0011, 4'b0100, 4'b0101, 
            4'b0110, 4'b0111, 4'b1000, 4'b1001, 4'b1010, 4'b1011, 
            4'b1100, 4'b1101, 4'b1110, 4'b1111: reg_write = 1'b1;
            default: reg_write = 1'b0;
        endcase
    end
endmodule

// ============================================================
// 4. 16-BIT ALU
// ============================================================
module alu16 (
    input  wire [15:0] A,
    input  wire [15:0] B,
    input  wire [3:0]  opcode,
    output reg  [15:0] result,
    output reg          zero,
    output reg          carry,
    output reg          overflow,
    output reg          negative
);
    reg [16:0] temp;

    always @(*) begin
        temp     = 17'd0;
        result   = 16'd0;
        carry    = 1'b0;
        overflow = 1'b0;

        case (opcode)
            4'b0000: begin temp = {1'b0, A} + {1'b0, B}; result = temp[15:0]; carry = temp[16]; overflow = (A[15] == B[15]) && (result[15] != A[15]); end
            4'b0001: begin temp = {1'b0, A} - {1'b0, B}; result = temp[15:0]; carry = temp[16]; overflow = (A[15] != B[15]) && (result[15] != A[15]); end
            4'b0010: result = A & B;
            4'b0011: result = A | B;
            4'b0100: result = A ^ B;
            4'b0101: result = ~(A | B);
            4'b0110: result = ~A;
            4'b0111: result = A << B[3:0];
            4'b1000: result = A >> B[3:0];
            4'b1001: result = $signed(A) >>> B[3:0];
            4'b1010: result = ($signed(A) < $signed(B)) ? 16'd1 : 16'd0;
            4'b1011: result = (A < B) ? 16'd1 : 16'd0;
            4'b1100: result = (A * B) & 16'hFFFF;
            4'b1101: result = A + 16'd1;
            4'b1110: result = A - 16'd1;
            4'b1111: result = A;
            default: result = 16'd0;
        endcase

        zero     = (result == 16'd0);
        negative = result[15];
    end
endmodule

// ============================================================
// 5. TOP LEVEL: 3-STAGE SUPERSCALAR CPU
// ============================================================
module cpu_superscalar_3stage (
    input wire clk,
    input wire reset
);

    // ---------------------------------------------------------
    // STAGE 1: INSTRUCTION FETCH (IF)
    // ---------------------------------------------------------
    reg [7:0] pc;
    wire [15:0] fetch_inst_A, fetch_inst_B;

    always @(posedge clk) begin
        if (reset) pc <= 8'd0;
        else       pc <= pc + 2; 
    end

    instruction_memory #(8, 16) imemA (.pc(pc),   .instruction(fetch_inst_A));
    instruction_memory #(8, 16) imemB (.pc(pc+1), .instruction(fetch_inst_B));

    // Pipeline Register: IF/ID
    reg [15:0] if_id_inst_A, if_id_inst_B;
    
    always @(posedge clk) begin
        if (reset) begin
            if_id_inst_A <= 16'hF000;
            if_id_inst_B <= 16'hF000;
        end else begin
            if_id_inst_A <= fetch_inst_A;
            if_id_inst_B <= fetch_inst_B;
        end
    end

    // ---------------------------------------------------------
    // STAGE 2: INSTRUCTION DECODE & REG READ (ID)
    // ---------------------------------------------------------
    wire [3:0] id_opA, id_opB, id_alu_opA, id_alu_opB;
    wire [2:0] id_rdA, id_rs1A, id_rs2A, id_rdB, id_rs1B, id_rs2B;
    wire id_weA, id_weB;

    decoder decA (.instruction(if_id_inst_A), .opcode(id_opA), .rd(id_rdA), .rs1(id_rs1A), .rs2(id_rs2A), .alu_opcode(id_alu_opA), .reg_write(id_weA));
    decoder decB (.instruction(if_id_inst_B), .opcode(id_opB), .rd(id_rdB), .rs1(id_rs1B), .rs2(id_rs2B), .alu_opcode(id_alu_opB), .reg_write(id_weB));

    wire [15:0] id_rdata1A, id_rdata2A, id_rdata1B, id_rdata2B;
    wire [15:0] wb_resA, wb_resB;
    wire ex_weA, ex_weB;
    wire [2:0] ex_rdA, ex_rdB;

    regfile_4R2W regfile (
        .clk(clk), .reset(reset),
        .rA1(id_rs1A), .dA1(id_rdata1A), .rA2(id_rs2A), .dA2(id_rdata2A),
        .rB1(id_rs1B), .dB1(id_rdata1B), .rB2(id_rs2B), .dB2(id_rdata2B),
        .wA(ex_rdA),   .wdA(wb_resA),    .weA(ex_weA),
        .wB(ex_rdB),   .wdB(wb_resB),    .weB(ex_weB)
    );

    // Pipeline Register: ID/EX
    reg [15:0] ex_rdata1A, ex_rdata2A, ex_rdata1B, ex_rdata2B;
    reg [3:0]  ex_alu_opA, ex_alu_opB;
    reg        ex_weA_reg, ex_weB_reg;
    reg [2:0]  ex_rdA_reg, ex_rdB_reg;

    always @(posedge clk) begin
        if (reset) begin
            ex_weA_reg <= 0; ex_weB_reg <= 0;
            ex_alu_opA <= 4'hF; ex_alu_opB <= 4'hF;
        end else begin
            ex_rdata1A <= id_rdata1A; ex_rdata2A <= id_rdata2A;
            ex_rdata1B <= id_rdata1B; ex_rdata2B <= id_rdata2B;
            ex_alu_opA <= id_alu_opA; ex_alu_opB <= id_alu_opB;
            ex_weA_reg <= id_weA;     ex_weB_reg <= id_weB;
            ex_rdA_reg <= id_rdA;     ex_rdB_reg <= id_rdB;
        end
    end

    // ---------------------------------------------------------
    // STAGE 3: EXECUTE & WRITEBACK (EX/WB)
    // ---------------------------------------------------------
    assign ex_weA = ex_weA_reg;
    assign ex_weB = ex_weB_reg;
    assign ex_rdA = ex_rdA_reg;
    assign ex_rdB = ex_rdB_reg;

    wire zA, cA, ovA, nA;
    wire zB, cB, ovB, nB;

    alu16 aluA (.A(ex_rdata1A), .B(ex_rdata2A), .opcode(ex_alu_opA), .result(wb_resA), .zero(zA), .carry(cA), .overflow(ovA), .negative(nA));
    alu16 aluB (.A(ex_rdata1B), .B(ex_rdata2B), .opcode(ex_alu_opB), .result(wb_resB), .zero(zB), .carry(cB), .overflow(ovB), .negative(nB));

endmodule