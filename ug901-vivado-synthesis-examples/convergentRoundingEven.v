// Convergent rounding(Even) Example which makes use of pattern detect 
// File: convergentRoundingEven.v
module convergentRoundingEven (
                               input clk, 
                               input [23:0] a, 
                               input [15:0] b,
                             output reg signed [23:0] zlast
                              );

reg signed [23:0] areg;
reg signed [15:0] breg;
reg signed [39:0] z1;

reg pattern_detect;   
wire [15:0] pattern = 16'b0000000000000000;
wire [39:0] c = 40'b0000000000000000000000000111111111111111; // 15 ones

wire signed [39:0] multadd;
wire signed [15:0] zero;
reg  signed [39:0] multadd_reg;   

// Convergent Rounding: LSB Correction Technique
// ---------------------------------------------   
// For static convergent rounding, the pattern detector can be used
// to detect the midpoint case. For example, in an 8-bit round, if
// the decimal place is set at 4, the C input should be set to
// 0000.0111.  Round to even rounding should use CARRYIN = "1" and
// check for PATTERN "XXXX.0000" and replace the units place with 0
// if the pattern is matched. See UG193 for more details.

assign multadd = z1 + c + 1'b1;

always @(posedge clk)
begin
 areg  <= a;
 breg  <= b;
 z1    <= areg * breg;
 pattern_detect <= multadd[15:0] == pattern ? 1'b1 : 1'b0;
 multadd_reg <= multadd; 
end

// Unit bit replaced with 0 if pattern is detected
always @(posedge clk)
 zlast <= pattern_detect ? {multadd_reg[39:17],1'b0} : multadd_reg[39:16];
   
endmodule // convergentRoundingEven
