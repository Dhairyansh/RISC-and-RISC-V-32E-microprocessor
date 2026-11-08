// Code your design here
// ============================================================
// 16-bit ALU (Behavioral Verilog)
// ============================================================
// Opcodes:
//   4'b0000 : ADD   -> A + B
//   4'b0001 : SUB   -> A - B
//   4'b0010 : AND   -> A & B
//   4'b0011 : OR    -> A | B
//   4'b0100 : XOR   -> A ^ B
//   4'b0101 : NOR   -> ~(A | B)
//   4'b0110 : NOT   -> ~A
//   4'b0111 : SLL   -> A << B[3:0]   (logical left shift)
//   4'b1000 : SRL   -> A >> B[3:0]   (logical right shift)
//   4'b1001 : SRA   -> A >>> B[3:0]  (arithmetic right shift)
//   4'b1010 : SLT   -> (signed A < signed B) ? 1 : 0
//   4'b1011 : SLTU  -> (unsigned A < unsigned B) ? 1 : 0
//   4'b1100 : MUL   -> lower 16 bits of A * B
//   4'b1101 : INC   -> A + 1
//   4'b1110 : DEC   -> A - 1
//   4'b1111 : PASS  -> A
//
// Flags:
//   zero     : result == 0
//   carry    : carry-out of ADD/SUB (borrow for SUB)
//   overflow : signed overflow for ADD/SUB
//   negative : result[15] (MSB of result)
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

    // Wider temp to catch carry-out from add/sub
    reg [16:0] temp;

    always @(*) begin
        // defaults
        temp     = 17'd0;
        result   = 16'd0;
        carry    = 1'b0;
        overflow = 1'b0;

        case (opcode)
            4'b0000: begin // ADD
                temp     = {1'b0, A} + {1'b0, B};
                result   = temp[15:0];
                carry    = temp[16];
                overflow = (A[15] == B[15]) && (result[15] != A[15]);
            end

            4'b0001: begin // SUB
                temp     = {1'b0, A} - {1'b0, B};
                result   = temp[15:0];
                carry    = temp[16]; // borrow flag
                overflow = (A[15] != B[15]) && (result[15] != A[15]);
            end

            4'b0010: result = A & B;                    // AND
            4'b0011: result = A | B;                    // OR
            4'b0100: result = A ^ B;                     // XOR
            4'b0101: result = ~(A | B);                  // NOR
            4'b0110: result = ~A;                         // NOT
            4'b0111: result = A << B[3:0];               // SLL
            4'b1000: result = A >> B[3:0];               // SRL
            4'b1001: result = $signed(A) >>> B[3:0];      // SRA
            4'b1010: result = ($signed(A) < $signed(B)) ? 16'd1 : 16'd0; // SLT
            4'b1011: result = (A < B) ? 16'd1 : 16'd0;    // SLTU
            4'b1100: result = (A * B) & 16'hFFFF;         // MUL (lower 16 bits)
            4'b1101: result = A + 16'd1;                  // INC
            4'b1110: result = A - 16'd1;                  // DEC
            4'b1111: result = A;                          // PASS
            default: result = 16'd0;
        endcase

        zero     = (result == 16'd0);
        negative = result[15];
    end

endmodule