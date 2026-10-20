// Conversion runs on result updates, never in the pixel combinational path.
module vision_bcd(input wire clk,rst_n,start,input wire [19:0] value,output reg [23:0] digits);
    reg [19:0] binary;
    reg [23:0] bcd,adjusted;
    reg [4:0] count;
    reg busy;
    integer i;
    always @*begin
        adjusted=bcd;
        for(i=0;i<6;i=i+1)if(bcd[i*4+:4]>=5)adjusted[i*4+:4]=bcd[i*4+:4]+4'd3;
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin binary<=0;bcd<=0;digits<=0;count<=0;busy<=0;end
        else if(start)begin binary<=value;bcd<=0;count<=0;busy<=1;end
        else if(busy)begin
            binary<={binary[18:0],1'b0};bcd<={adjusted[22:0],binary[19]};count<=count+1'b1;
            if(count==19)begin digits<={adjusted[22:0],binary[19]};busy<=0;end
        end
    end
endmodule
