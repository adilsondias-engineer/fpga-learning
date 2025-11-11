// 3-D Ram Inference Example (Simple Dual port) 
// File:rams_sdp_3d.sv
module rams_sdp_3d #(
                     parameter NUM_RAMS = 2,
                               A_WID    = 10,
                               D_WID    = 32
                    )
                   (
                    input clka, 
                    input clkb,
                    input [NUM_RAMS-1:0] wea,
                    input [NUM_RAMS-1:0] ena,
                    input [NUM_RAMS-1:0] enb,
                    input [A_WID-1:0] addra [NUM_RAMS-1:0],
                    input [A_WID-1:0] addrb [NUM_RAMS-1:0],
                    input [D_WID-1:0] dina [NUM_RAMS-1:0],
                    output reg [D_WID-1:0] doutb [NUM_RAMS-1:0]
                   );

reg [D_WID-1:0] mem [NUM_RAMS-1:0][2**A_WID-1:0];
// PORT_A
genvar i;
generate
 for(i=0;i<NUM_RAMS;i=i+1)
 begin:port_a_ops
  always @ (posedge clka)
  begin
   if (ena[i]) begin
    if(wea[i])
    begin
     mem[i][addra[i]] <= dina[i];
    end
   end 
  end
 end
endgenerate

//PORT_B
generate
 for(i=0;i<NUM_RAMS;i=i+1)
 begin:port_b_ops
  always @ (posedge clkb)
  begin
   if (enb[i]) 
    doutb[i] <= mem[i][addrb[i]]; 
  end
 end
endgenerate

endmodule          

