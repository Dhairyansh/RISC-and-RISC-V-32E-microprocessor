`timescale 1ns / 1ps

module tb_complete;
    reg clk;
    reg reset;

    cpu_superscalar_3stage uut (
        .clk(clk),
        .reset(reset)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        reset = 1;
        $dumpfile("superscalar_3stage.vcd");
        $dumpvars(0, tb_complete);

        #20 reset = 0;
        #150 $finish; 
    end

    initial begin
        $monitor("Time: %0t | PC: %0d \n  [EX Stage] ALU A Res: %h (Write: %b to R%0d) | ALU B Res: %h (Write: %b to R%0d)", 
                 $time, uut.pc, 
                 uut.wb_resA, uut.ex_weA, uut.ex_rdA,
                 uut.wb_resB, uut.ex_weB, uut.ex_rdB);
    end
endmodule