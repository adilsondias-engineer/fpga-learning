// RAM Inference using Struct in SV(True Dual port) 
// File:rams_tdp_struct.sv
typedef struct packed {
                       logic [3:0] addr;
                       logic [27:0] data;
                      } Packet;

module rams_tdp_struct #(
                         parameter A_WID = 10,
                                   D_WID = 32
                        )
                       (      
                        input clka, 
                        input clkb, 
                        input wea,
                        input web,
                        input ena,
                        input enb,
                        input [A_WID-1:0] addra,
                        input [A_WID-1:0] addrb,
                        input Packet dina, dinb,
                        output Packet douta, doutb
                       );

Packet mem [2**A_WID-1:0];

always @ (posedge clka)
begin
 if (ena) 
  begin
  douta <= mem[addra];
   if(wea)
    mem[addra] <= dina;
 end 
end

always @ (posedge clkb)
begin
 if (enb) 
  begin
  doutb <= mem[addrb];
   if(web)
    mem[addrb] <= dinb;
 end 
end

endmodule
