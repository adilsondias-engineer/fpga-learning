// Verilog tasks 
// tasks_1.v
//
module tasks_1 (A, B, CIN, S, COUT);
input [3:0] A, B;
input CIN;
output [3:0] S;
output COUT;
reg [3:0] S;
reg COUT;
reg [1:0] S0, S1, S2, S3;

task ADD;
input A, B, CIN;
output [1:0] C;
reg [1:0] C;
reg S, COUT;
  begin
    S = A ^ B ^ CIN;
    COUT = (A&B) | (A&CIN) | (B&CIN);
    C = {COUT, S};
  end
endtask

always @(A or B or CIN)
begin
  ADD (A[0], B[0], CIN, S0);
  ADD (A[1], B[1], S0[1], S1);
  ADD (A[2], B[2], S1[1], S2);
  ADD (A[3], B[3], S2[1], S3);
  S = {S3[0], S2[0], S1[0], S0[0]};
  COUT = S3[1];
end

endmodule
