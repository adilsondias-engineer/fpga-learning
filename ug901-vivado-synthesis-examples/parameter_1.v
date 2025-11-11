// A Verilog parameter allows to control the width of an instantitated
// block describing register logic
//
// 
// File:parameter_1.v
//
module myreg (clk, clken, d, q);

    parameter SIZE = 1;

    input                  clk, clken;
    input      [SIZE-1:0]  d;
    output reg [SIZE-1:0]  q;
    
 always @(posedge clk)
    begin
        if (clken)
            q <= d;
    end
 
endmodule

module parameter_1 (clk, clken, di, do);

    parameter SIZE = 8;

    input                  clk, clken;
    input      [SIZE-1:0]  di;
    output     [SIZE-1:0]  do;

    myreg #8 inst_reg (clk, clken, di, do);

endmodule