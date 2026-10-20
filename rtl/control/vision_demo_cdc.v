// Slow control bus, not an event/data stream. The debounced source holds each
// value for >=10ms; the destination requires >=8 destination clocks of hold.
// Two synchronizer registers followed by three equal samples reject short
// inter-bit skew values. The input-to-meta datapath is bounded to one dst clock.
module vision_demo_cdc(input wire clk,rst_n,input wire [3:0] async_demo,output reg [3:0] demo);
    (* async_reg="true",allow_backward_retiming=0,allow_forward_retiming=0 *) reg [3:0] meta,sync;
    reg [3:0] candidate;
    reg [1:0] stable;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin meta<=4'h5;sync<=4'h5;candidate<=4'h5;stable<=0;demo<=4'h5;end
        else begin
            meta<=async_demo;sync<=meta;
            if(sync!=candidate)begin candidate<=sync;stable<=0;end
            else if(stable!=3)begin
                stable<=stable+1'b1;
                if(stable==2 && (!candidate[3] || candidate[2:0]<=5))demo<=candidate;
            end
        end
    end
endmodule
