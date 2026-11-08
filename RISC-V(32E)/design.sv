// ============================================================
// 10-stage, 2-wide in-order superscalar 32-bit CPU (RISC-V RV32I/E)
//
// Supported ISA subset: ADD, SUB, AND, OR, XOR, ADDI, LW, SW
// x0 is hard-wired to zero.
// Byte-addressed memory, PC increments by 4 per instruction.
// ============================================================

// ------------------------------------------------------------
// 1. MEMORIES
// ------------------------------------------------------------
module instruction_memory #(parameter ADDR_WIDTH = 10, DATA_WIDTH = 32)(
    input  wire [31:0] pc,
    output wire [DATA_WIDTH-1:0] instruction
);
    // 256-word instruction memory (1KB)
    reg [DATA_WIDTH-1:0] mem [0:(1<<(ADDR_WIDTH-2))-1];
    integer k;
    initial begin
        // Initialize with RISC-V NOP: ADDI x0, x0, 0 (32'h00000013)
        for (k = 0; k < (1<<(ADDR_WIDTH-2)); k = k + 1) mem[k] = 32'h00000013;
    end
    
    // Word-aligned read (drop lower 2 bits of byte address)
    assign instruction = mem[pc[ADDR_WIDTH-1:2]];
endmodule

module data_memory (
    input  wire        clk,
    input  wire [31:0] addrA, wdataA, input wire weA, reA, output wire [31:0] rdataA,
    input  wire [31:0] addrB, wdataB, input wire weB, reB, output wire [31:0] rdataB
);
    // 256-word data memory (1KB)
    reg [31:0] dmem [0:255];
    integer i;
    initial begin for (i = 0; i < 256; i = i + 1) dmem[i] = 32'd0; end

    // Same-cycle store from lane A to load in lane B
    wire a_to_b = weA && (addrA[9:2] == addrB[9:2]);

    assign rdataA = reA ? dmem[addrA[9:2]] : 32'd0;
    assign rdataB = reB ? (a_to_b ? wdataA : dmem[addrB[9:2]]) : 32'd0;

    always @(posedge clk) begin
        if (weA) dmem[addrA[9:2]] <= wdataA;
        if (weB) dmem[addrB[9:2]] <= wdataB; // B last: wins on same address
    end
endmodule

// ------------------------------------------------------------
// 2. REGISTER FILE (4R / 2W, write-through, x0 = 0)
// ------------------------------------------------------------
module regfile_4R2W (
    input  wire clk, reset,
    input  wire [4:0] rA1, output wire [31:0] dA1,
    input  wire [4:0] rA2, output wire [31:0] dA2,
    input  wire [4:0] rB1, output wire [31:0] dB1,
    input  wire [4:0] rB2, output wire [31:0] dB2,
    input  wire [4:0] wA,  input wire [31:0] wdA, input wire weA,
    input  wire [4:0] wB,  input wire [31:0] wdB, input wire weB
);
    reg [31:0] registers [0:31];
    integer i;

    wire wenA = weA && (wA != 5'b00000);
    wire wenB = weB && (wB != 5'b00000);

    assign dA1 = (rA1 == 5'd0) ? 32'd0 : (wenB && wB == rA1) ? wdB : (wenA && wA == rA1) ? wdA : registers[rA1];
    assign dA2 = (rA2 == 5'd0) ? 32'd0 : (wenB && wB == rA2) ? wdB : (wenA && wA == rA2) ? wdA : registers[rA2];
    assign dB1 = (rB1 == 5'd0) ? 32'd0 : (wenB && wB == rB1) ? wdB : (wenA && wA == rB1) ? wdA : registers[rB1];
    assign dB2 = (rB2 == 5'd0) ? 32'd0 : (wenB && wB == rB2) ? wdB : (wenA && wA == rB2) ? wdA : registers[rB2];

    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 32; i = i + 1) registers[i] <= 32'd0;
        end else begin
            if (wenA) registers[wA] <= wdA;
            if (wenB) registers[wB] <= wdB;
        end
    end
endmodule

// ------------------------------------------------------------
// 3. RISC-V DECODER
// ------------------------------------------------------------
module decoder_rv32 (
    input  wire [31:0] instruction,
    output wire [4:0]  rd, rs1, rs2_sel,
    output reg  [3:0]  alu_opcode,
    output wire [31:0] imm,
    output reg         use_imm, uses_rs1, uses_rs2,
    output reg         reg_write, mem_read, mem_write, is_load
);
    wire [6:0] opcode = instruction[6:0];
    wire [2:0] funct3 = instruction[14:12];
    wire       funct7_5 = instruction[30];
    
    assign rd      = instruction[11:7];
    assign rs1     = instruction[19:15];
    assign rs2_sel = instruction[24:20];

    // Immediate extraction
    wire [31:0] imm_I = {{20{instruction[31]}}, instruction[31:20]};
    wire [31:0] imm_S = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
    assign imm = (opcode == 7'h23) ? imm_S : imm_I;

    // ALU Constants mapped for internal use
    localparam ALU_ADD = 4'd0, ALU_SUB = 4'd1, ALU_AND = 4'd2, ALU_OR = 4'd3, ALU_XOR = 4'd4;

    always @(*) begin
        reg_write = 0; mem_read = 0; mem_write = 0; is_load = 0;
        use_imm = 0; uses_rs1 = 0; uses_rs2 = 0;
        alu_opcode = ALU_ADD; // default

        case (opcode)
            7'h33: begin // R-type (ALU)
                reg_write = 1; uses_rs1 = 1; uses_rs2 = 1;
                case (funct3)
                    3'b000: alu_opcode = funct7_5 ? ALU_SUB : ALU_ADD;
                    3'b100: alu_opcode = ALU_XOR;
                    3'b110: alu_opcode = ALU_OR;
                    3'b111: alu_opcode = ALU_AND;
                    default: alu_opcode = ALU_ADD;
                endcase
            end
            7'h13: begin // I-type (ALU Immediate)
                reg_write = 1; uses_rs1 = 1; use_imm = 1;
                case (funct3)
                    3'b000: alu_opcode = ALU_ADD; // ADDI
                    3'b100: alu_opcode = ALU_XOR; // XORI
                    3'b110: alu_opcode = ALU_OR;  // ORI
                    3'b111: alu_opcode = ALU_AND; // ANDI
                    default: alu_opcode = ALU_ADD;
                endcase
            end
            7'h03: begin // LOAD
                reg_write = 1; mem_read = 1; is_load = 1;
                uses_rs1 = 1; use_imm = 1;
            end
            7'h23: begin // STORE
                mem_write = 1; uses_rs1 = 1; uses_rs2 = 1; use_imm = 1;
            end
            default: ; 
        endcase
    end
endmodule

// ------------------------------------------------------------
// 4. ALU
// ------------------------------------------------------------
module alu32 (input wire [31:0] A, B, input wire [3:0] opcode, output reg [31:0] result);
    always @(*) begin
        case (opcode)
            4'd0: result = A + B;
            4'd1: result = A - B;
            4'd2: result = A & B;
            4'd3: result = A | B;
            4'd4: result = A ^ B;
            default: result = 32'd0;
        endcase
    end
endmodule

// ------------------------------------------------------------
// 5. TOP LEVEL (RV32E Superscalar)
// ------------------------------------------------------------
module cpu_rv32e_superscalar_10stage (input wire clk, reset);

    localparam [31:0] NOP = 32'h00000013; // ADDI x0, x0, 0

    // RAW dependency check
    function dep(input [4:0] src, input used, input [4:0] rd, input we);
        dep = used && we && (rd != 5'd0) && (rd == src);
    endfunction

    wire stall, split;

    // ================= STAGE 1 (IF1): PC =================
    reg  [31:0] pc;
    reg  [31:0] if2_pc, id1_pc;
    wire [31:0] pc_p4 = pc + 32'd4;

    always @(posedge clk) begin
        if (reset)       pc <= 32'd0;
        else if (stall)  pc <= pc;
        else if (split)  pc <= id1_pc + 32'd4; // replay lane B
        else             pc <= pc + 32'd8;     // normal 2-wide advance
    end

    // ================= STAGE 2 (IF2) =================
    wire [31:0] fetch_A, fetch_B;
    instruction_memory #(10,32) imemA (.pc(pc),    .instruction(fetch_A));
    instruction_memory #(10,32) imemB (.pc(pc_p4), .instruction(fetch_B));

    reg [31:0] if2_instA, if2_instB;
    always @(posedge clk) begin
        if (reset || split) begin
            if2_instA <= NOP; if2_instB <= NOP; if2_pc <= 32'd0;
        end else if (!stall) begin
            if2_instA <= fetch_A; if2_instB <= fetch_B; if2_pc <= pc;
        end
    end

    // ================= STAGE 3 (ID1) =================
    wire [31:0] d_instA = split ? NOP : if2_instA;
    wire [31:0] d_instB = split ? NOP : if2_instB;

    wire [4:0]  dec_rdA, dec_rs1A, dec_rs2A, dec_rdB, dec_rs1B, dec_rs2B;
    wire [3:0]  dec_aluA, dec_aluB;
    wire [31:0] dec_immA, dec_immB;
    wire dec_uiA, dec_u1A, dec_u2A, dec_weA, dec_mrA, dec_mwA, dec_ldA;
    wire dec_uiB, dec_u1B, dec_u2B, dec_weB, dec_mrB, dec_mwB, dec_ldB;

    decoder_rv32 decA (.instruction(d_instA), .rd(dec_rdA), .rs1(dec_rs1A), .rs2_sel(dec_rs2A),
                       .alu_opcode(dec_aluA), .imm(dec_immA), .use_imm(dec_uiA),
                       .uses_rs1(dec_u1A), .uses_rs2(dec_u2A), .reg_write(dec_weA),
                       .mem_read(dec_mrA), .mem_write(dec_mwA), .is_load(dec_ldA));
    decoder_rv32 decB (.instruction(d_instB), .rd(dec_rdB), .rs1(dec_rs1B), .rs2_sel(dec_rs2B),
                       .alu_opcode(dec_aluB), .imm(dec_immB), .use_imm(dec_uiB),
                       .uses_rs1(dec_u1B), .uses_rs2(dec_u2B), .reg_write(dec_weB),
                       .mem_read(dec_mrB), .mem_write(dec_mwB), .is_load(dec_ldB));

    reg [3:0]  id1_aluA, id1_aluB;
    reg [4:0]  id1_rdA, id1_rs1A, id1_rs2A, id1_rdB, id1_rs1B, id1_rs2B;
    reg [31:0] id1_immA, id1_immB;
    reg id1_uiA, id1_u1A, id1_u2A, id1_weA, id1_mrA, id1_mwA, id1_ldA;
    reg id1_uiB, id1_u1B, id1_u2B, id1_weB, id1_mrB, id1_mwB, id1_ldB;

    always @(posedge clk) begin
        if (reset) begin
            id1_weA<=0; id1_mrA<=0; id1_mwA<=0; id1_ldA<=0; id1_u1A<=0; id1_u2A<=0; id1_uiA<=0;
            id1_weB<=0; id1_mrB<=0; id1_mwB<=0; id1_ldB<=0; id1_u1B<=0; id1_u2B<=0; id1_uiB<=0;
            id1_pc<=32'd0;
        end else if (!stall) begin
            id1_aluA<=dec_aluA; id1_rdA<=dec_rdA; id1_rs1A<=dec_rs1A; id1_rs2A<=dec_rs2A; id1_immA<=dec_immA;
            id1_uiA<=dec_uiA; id1_u1A<=dec_u1A; id1_u2A<=dec_u2A; id1_weA<=dec_weA; id1_mrA<=dec_mrA; id1_mwA<=dec_mwA; id1_ldA<=dec_ldA;
            
            id1_aluB<=dec_aluB; id1_rdB<=dec_rdB; id1_rs1B<=dec_rs1B; id1_rs2B<=dec_rs2B; id1_immB<=dec_immB;
            id1_uiB<=dec_uiB; id1_u1B<=dec_u1B; id1_u2B<=dec_u2B; id1_weB<=dec_weB; id1_mrB<=dec_mrB; id1_mwB<=dec_mwB; id1_ldB<=dec_ldB;
            id1_pc<=if2_pc;
        end
    end

    // ================= STAGE 4 (ID2) =================
    wire [31:0] rf_r1A, rf_r2A, rf_r1B, rf_r2B;
    wire [31:0] wb_resA, wb_resB;
    wire        wb_weA, wb_weB;
    wire [4:0]  wb_rdA, wb_rdB;

    regfile_4R2W regfile (
        .clk(clk), .reset(reset),
        .rA1(id1_rs1A), .dA1(rf_r1A), .rA2(id1_rs2A), .dA2(rf_r2A),
        .rB1(id1_rs1B), .dB1(rf_r1B), .rB2(id1_rs2B), .dB2(rf_r2B),
        .wA(wb_rdA), .wdA(wb_resA), .weA(wb_weA),
        .wB(wb_rdB), .wdB(wb_resB), .weB(wb_weB)
    );

    reg [31:0] id2_r1A, id2_r2A, id2_r1B, id2_r2B, id2_immA, id2_immB;
    reg [3:0]  id2_aluA, id2_aluB;
    reg [4:0]  id2_rdA, id2_rdB;
    reg id2_uiA, id2_weA, id2_mrA, id2_mwA, id2_ldA;
    reg id2_uiB, id2_weB, id2_mrB, id2_mwB, id2_ldB;

    // Hazard checks against in-flight producers
    reg ex1_weA, ex1_weB, ex2_weA, ex2_weB, ex3_weA, ex3_weB, mem1_weA, mem1_weB;
    reg [4:0] ex1_rdA, ex1_rdB, ex2_rdA, ex2_rdB, ex3_rdA, ex3_rdB, mem1_rdA, mem1_rdB;

    `define HZ(src, used) ( \
          dep(src, used, id2_rdA,  id2_weA)  | dep(src, used, id2_rdB,  id2_weB)  \
        | dep(src, used, ex1_rdA,  ex1_weA)  | dep(src, used, ex1_rdB,  ex1_weB)  \
        | dep(src, used, ex2_rdA,  ex2_weA)  | dep(src, used, ex2_rdB,  ex2_weB)  \
        | dep(src, used, ex3_rdA,  ex3_weA)  | dep(src, used, ex3_rdB,  ex3_weB)  \
        | dep(src, used, mem1_rdA, mem1_weA) | dep(src, used, mem1_rdB, mem1_weB) )

    assign stall = `HZ(id1_rs1A, id1_u1A) | `HZ(id1_rs2A, id1_u2A)
                 | `HZ(id1_rs1B, id1_u1B) | `HZ(id1_rs2B, id1_u2B);

    assign split = !stall & ( dep(id1_rs1B, id1_u1B, id1_rdA, id1_weA)
                            | dep(id1_rs2B, id1_u2B, id1_rdA, id1_weA) );

    always @(posedge clk) begin
        if (reset) begin
            id2_weA<=0; id2_mrA<=0; id2_mwA<=0; id2_ldA<=0;
            id2_weB<=0; id2_mrB<=0; id2_mwB<=0; id2_ldB<=0;
        end else begin
            if (stall) begin
                id2_weA<=0; id2_mrA<=0; id2_mwA<=0; id2_ldA<=0;
            end else begin
                id2_r1A<=rf_r1A; id2_r2A<=rf_r2A; id2_aluA<=id1_aluA; id2_rdA<=id1_rdA; id2_immA<=id1_immA; id2_uiA<=id1_uiA;
                id2_weA<=id1_weA; id2_mrA<=id1_mrA; id2_mwA<=id1_mwA; id2_ldA<=id1_ldA;
            end
            if (stall || split) begin
                id2_weB<=0; id2_mrB<=0; id2_mwB<=0; id2_ldB<=0;
            end else begin
                id2_r1B<=rf_r1B; id2_r2B<=rf_r2B; id2_aluB<=id1_aluB; id2_rdB<=id1_rdB; id2_immB<=id1_immB; id2_uiB<=id1_uiB;
                id2_weB<=id1_weB; id2_mrB<=id1_mrB; id2_mwB<=id1_mwB; id2_ldB<=id1_ldB;
            end
        end
    end

    // ================= STAGE 5 (EX1) =================
    wire [31:0] opB_A = id2_uiA ? id2_immA : id2_r2A;
    wire [31:0] opB_B = id2_uiB ? id2_immB : id2_r2B;
    wire [31:0] alu_outA, alu_outB;
    alu32 aluA (.A(id2_r1A), .B(opB_A), .opcode(id2_aluA), .result(alu_outA));
    alu32 aluB (.A(id2_r1B), .B(opB_B), .opcode(id2_aluB), .result(alu_outB));

    reg [31:0] ex1_aluA, ex1_r2A, ex1_aluB, ex1_r2B;
    reg ex1_mrA, ex1_mwA, ex1_ldA, ex1_mrB, ex1_mwB, ex1_ldB;

    always @(posedge clk) begin
        if (reset) begin
            ex1_weA<=0; ex1_mrA<=0; ex1_mwA<=0; ex1_ldA<=0;
            ex1_weB<=0; ex1_mrB<=0; ex1_mwB<=0; ex1_ldB<=0;
        end else begin
            ex1_aluA<=alu_outA; ex1_r2A<=id2_r2A; ex1_rdA<=id2_rdA; ex1_weA<=id2_weA; ex1_mrA<=id2_mrA; ex1_mwA<=id2_mwA; ex1_ldA<=id2_ldA;
            ex1_aluB<=alu_outB; ex1_r2B<=id2_r2B; ex1_rdB<=id2_rdB; ex1_weB<=id2_weB; ex1_mrB<=id2_mrB; ex1_mwB<=id2_mwB; ex1_ldB<=id2_ldB;
        end
    end

    // ================= STAGE 6 (EX2) =================
    reg [31:0] ex2_aluA, ex2_r2A, ex2_aluB, ex2_r2B;
    reg ex2_mrA, ex2_mwA, ex2_ldA, ex2_mrB, ex2_mwB, ex2_ldB;
    always @(posedge clk) begin
        if (reset) begin
            ex2_weA<=0; ex2_mrA<=0; ex2_mwA<=0; ex2_ldA<=0;
            ex2_weB<=0; ex2_mrB<=0; ex2_mwB<=0; ex2_ldB<=0;
        end else begin
            ex2_aluA<=ex1_aluA; ex2_r2A<=ex1_r2A; ex2_rdA<=ex1_rdA; ex2_weA<=ex1_weA; ex2_mrA<=ex1_mrA; ex2_mwA<=ex1_mwA; ex2_ldA<=ex1_ldA;
            ex2_aluB<=ex1_aluB; ex2_r2B<=ex1_r2B; ex2_rdB<=ex1_rdB; ex2_weB<=ex1_weB; ex2_mrB<=ex1_mrB; ex2_mwB<=ex1_mwB; ex2_ldB<=ex1_ldB;
        end
    end

    // ================= STAGE 7 (EX3) =================
    reg [31:0] ex3_aluA, ex3_r2A, ex3_aluB, ex3_r2B;
    reg ex3_mrA, ex3_mwA, ex3_ldA, ex3_mrB, ex3_mwB, ex3_ldB;
    always @(posedge clk) begin
        if (reset) begin
            ex3_weA<=0; ex3_mrA<=0; ex3_mwA<=0; ex3_ldA<=0;
            ex3_weB<=0; ex3_mrB<=0; ex3_mwB<=0; ex3_ldB<=0;
        end else begin
            ex3_aluA<=ex2_aluA; ex3_r2A<=ex2_r2A; ex3_rdA<=ex2_rdA; ex3_weA<=ex2_weA; ex3_mrA<=ex2_mrA; ex3_mwA<=ex2_mwA; ex3_ldA<=ex2_ldA;
            ex3_aluB<=ex2_aluB; ex3_r2B<=ex2_r2B; ex3_rdB<=ex2_rdB; ex3_weB<=ex2_weB; ex3_mrB<=ex2_mrB; ex3_mwB<=ex2_mwB; ex3_ldB<=ex2_ldB;
        end
    end

    // ================= STAGE 8 (MEM1) =================
    reg [31:0] mem1_aluA, mem1_r2A, mem1_aluB, mem1_r2B;
    reg mem1_mrA, mem1_mwA, mem1_ldA, mem1_mrB, mem1_mwB, mem1_ldB;
    always @(posedge clk) begin
        if (reset) begin
            mem1_weA<=0; mem1_mrA<=0; mem1_mwA<=0; mem1_ldA<=0;
            mem1_weB<=0; mem1_mrB<=0; mem1_mwB<=0; mem1_ldB<=0;
        end else begin
            mem1_aluA<=ex3_aluA; mem1_r2A<=ex3_r2A; mem1_rdA<=ex3_rdA; mem1_weA<=ex3_weA; mem1_mrA<=ex3_mrA; mem1_mwA<=ex3_mwA; mem1_ldA<=ex3_ldA;
            mem1_aluB<=ex3_aluB; mem1_r2B<=ex3_r2B; mem1_rdB<=ex3_rdB; mem1_weB<=ex3_weB; mem1_mrB<=ex3_mrB; mem1_mwB<=ex3_mwB; mem1_ldB<=ex3_ldB;
        end
    end

    // ================= STAGE 9 (MEM2) =================
    wire [31:0] dmem_outA, dmem_outB;
    data_memory dmem (
        .clk(clk),
        .addrA(mem1_aluA), .wdataA(mem1_r2A), .weA(mem1_mwA), .reA(mem1_mrA), .rdataA(dmem_outA),
        .addrB(mem1_aluB), .wdataB(mem1_r2B), .weB(mem1_mwB), .reB(mem1_mrB), .rdataB(dmem_outB)
    );

    reg [31:0] mem2_aluA, mem2_memA, mem2_aluB, mem2_memB;
    reg        mem2_ldA, mem2_ldB, mem2_weA, mem2_weB;
    reg [4:0]  mem2_rdA, mem2_rdB;

    always @(posedge clk) begin
        if (reset) begin
            mem2_weA<=0; mem2_weB<=0; mem2_ldA<=0; mem2_ldB<=0;
        end else begin
            mem2_aluA<=mem1_aluA; mem2_memA<=dmem_outA; mem2_rdA<=mem1_rdA; mem2_weA<=mem1_weA; mem2_ldA<=mem1_ldA;
            mem2_aluB<=mem1_aluB; mem2_memB<=dmem_outB; mem2_rdB<=mem1_rdB; mem2_weB<=mem1_weB; mem2_ldB<=mem1_ldB;
        end
    end

    // ================= STAGE 10 (WB) =================
    assign wb_resA = mem2_ldA ? mem2_memA : mem2_aluA;
    assign wb_resB = mem2_ldB ? mem2_memB : mem2_aluB;
    assign wb_weA  = mem2_weA;
    assign wb_weB  = mem2_weB;
    assign wb_rdA  = mem2_rdA;
    assign wb_rdB  = mem2_rdB;

endmodule