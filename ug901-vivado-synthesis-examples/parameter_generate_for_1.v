//
// A shift register description that illustrates the use of parameters and
// generate-for constructs in Verilog
//
// File: parameter_generate_for_1.v
//
module parameter_generate_for_1 (clk, si, so);

parameter SIZE = 8;

input   clk;
input   si;
output  so;

reg [0:SIZE-1]  s;

assign so = s[SIZE-1];

always @ (posedge clk)
 s[0] <= si;

genvar i;
generate
  for (i = 1; i < SIZE; i = i+1)     
  begin : shreg
      always @ (posedge clk)
      begin
          s[i] <= s[i-1];
      end
  end  
endgenerate
  
endmodule
