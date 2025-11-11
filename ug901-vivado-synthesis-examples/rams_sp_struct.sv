// RAM Inference using Struct in SV (Single Port) 
// File:rams_sp_struct.sv
typedef struct packed {
                       logic [3:0] addr;
                       logic [27:0] data;
                      } Packet;

module rams_sp_struct #(
                        parameter A_WID = 10,
                                  D_WID = 32
                       )
                      (
                       input clk, 
                       input we, 
                       input ena,
                       input [A_WID-1:0] addr,
                       input Packet din,
                       output Packet dout
                      );

Packet mem [2**A_WID-1:0];

always @ (posedge clk)
begin
 if (ena) begin
  dout <= mem[addr];
   if(we)
    mem[addr] <= din;
 end 
end
endmodule
