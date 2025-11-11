// 3-D Ram Inference Example (Single port) 
// File:rams_sp_3d.sv
module rams_sp_3d #(
                     parameter NUM_RAMS = 2,
                               A_WID    = 10,
                               D_WID    = 32
                   )
                   (
                    input clk,
                    input [NUM_RAMS-1:0] we,
                    input [NUM_RAMS-1:0] ena,
                    input [A_WID-1:0] addr [NUM_RAMS-1:0],
                    input [D_WID-1:0] din [NUM_RAMS-1:0],
                    output reg [D_WID-1:0] dout [NUM_RAMS-1:0]
                   );

reg [D_WID-1:0] mem [NUM_RAMS-1:0][2**A_WID-1:0];
genvar i;

generate
for(i=0;i<NUM_RAMS;i=i+1)
begin:u
    always @ (posedge clk)
    begin
        if (ena[i]) begin
            if(we[i])
            begin
                mem[i][addr[i]] <= din[i];
            end
            dout[i] <= mem[i][addr[i]]; 
        end 
    end
end
endgenerate

endmodule   
