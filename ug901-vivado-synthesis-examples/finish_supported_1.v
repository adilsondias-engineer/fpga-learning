//
// Supported use of $finish for design rule checking
//
// finish_supported_1.v
//
module finish_supported_1 (clk, di, do);

  parameter integer WIDTH   = 4;
  parameter         DEVICE  = "virtex6";
  
  input                  clk;
  input      [WIDTH-1:0] di;
  output reg [WIDTH-1:0] do;
  
initial
 begin
  if (DEVICE != "virtex6")
   begin
    $display ("DRC ERROR: Unsupported device family: %s.", DEVICE);
    $finish;
   end
  if (WIDTH < 8)
   begin
    $display ("DRC ERROR: This module not tested for data width: %d. Minimum allowed width is 8.", WIDTH);
    $finish;
   end
 end
 
always @(posedge clk)
 begin
  do <= di;
 end
 
endmodule
