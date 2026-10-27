// Conversion runs on result updates, never in the pixel combinational path.
module vision_bcd #(parameter BIN_W=20,DEC_DIGITS=6)(input wire clk,rst_n,start,input wire [19:0] value,output reg [23:0] digits);
    reg [BIN_W-1:0] binary;
    reg [DEC_DIGITS*4-1:0] bcd,adjusted;
    reg [$clog2(BIN_W)-1:0] count;
    reg busy;
    integer i;
    always @*begin
        adjusted=bcd;
        for(i=0;i<DEC_DIGITS;i=i+1)if(bcd[i*4+:4]>=5)adjusted[i*4+:4]=bcd[i*4+:4]+4'd3;
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin binary<=0;bcd<=0;digits<=0;count<=0;busy<=0;end
        else if(start)begin binary<=value[BIN_W-1:0];bcd<=0;count<=0;busy<=1;end
        else if(busy)begin
            binary<={binary[BIN_W-2:0],1'b0};bcd<={adjusted[DEC_DIGITS*4-2:0],binary[BIN_W-1]};count<=count+1'b1;
            if(count==BIN_W-1)begin digits<={adjusted[DEC_DIGITS*4-2:0],binary[BIN_W-1]};busy<=0;end
        end
    end
endmodule
