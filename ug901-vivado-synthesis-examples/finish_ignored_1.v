//
// Ignored use of $finish for simulation purposes only
//
// finish_ignored_1.v
//
module finish_ignored_1 (clk, di, do);

  input            clk;
  input      [3:0] di;
  output reg [3:0] do;
  
initial
 begin
  do = 4'b0;
 end
 
always @(posedge clk)
 begin
  if (di < 4'b1100)
    do <= di;
  else
   begin
    $display("%t, di value %d should not be more than 11", $time, di);
    $finish;
   end
 end
 
endmodule
