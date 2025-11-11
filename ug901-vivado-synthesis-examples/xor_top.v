//
// Example for Mapping XOR into DSP block (for DSP48E2 block)
// File: xor_top.v (Top module is xor_top)
//-------------------------------------------------------   

// xor_tree_reduce - sub module used in top
(* dont_touch = "true", use_dsp48 = "logic" *)
module xor_tree_reduce #(parameter SIZE = 96)
             (
              input  clk, [SIZE-1:0] a,
             output reg o 
            );

reg [SIZE-1:0] areg;

always @(posedge clk)
 areg <= a;

always @(posedge clk)   
 o <=  ^areg;

endmodule // xor_tree_reduce

// xor_bitwise - sub module used in top
(* dont_touch = "true", use_dsp48 = "logic" *)
module xor_bitwise #(parameter SIZE = 48)
             (
              input  clk, [SIZE-1:0] a, b,
             output reg [SIZE-1:0] o 
             );

reg [SIZE-1:0] areg, breg;

always @(posedge clk)
begin
 areg <= a;
 breg <= b;
 o <= areg ^ breg;
end

endmodule // xor_bitwise

// xor_top - top level module
module xor_top #(parameter SIZE1 = 96, SIZE2 = 48)
            (
             input clk, [SIZE2-1:0] ain, bin, [SIZE1-1:0] reduce,
             output [SIZE2-1:0] bitwise,
            output single
            );

xor_tree_reduce #(SIZE1) U1 (clk, reduce, single);
xor_bitwise #(SIZE2) U2 (clk, ain, bin, bitwise);

endmodule // xor_top 
