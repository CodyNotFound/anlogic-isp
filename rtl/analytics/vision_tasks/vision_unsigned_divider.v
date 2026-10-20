// Restoring unsigned division, one bit per clock. Used between video frames.
module vision_unsigned_divider #(parameter W=24)(
    input wire clk,rst_n,start,
    input wire [W-1:0] numerator,denominator,
    output reg busy,done,
    output reg [W-1:0] quotient
);
    reg [W-1:0] dividend,divisor,q;
    reg [W:0] remainder;
    reg [$clog2(W+1)-1:0] count;
    wire [W:0] trial={remainder[W-1:0],dividend[W-1]};
    wire ge=trial>={1'b0,divisor};
    wire [W-1:0] next_q={q[W-2:0],ge};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin busy<=0;done<=0;quotient<=0;dividend<=0;divisor<=0;q<=0;remainder<=0;count<=0;end
        else begin
            done<=0;
            if(start && !busy)begin
                if(denominator==0)begin quotient<={W{1'b1}};done<=1;end
                else begin dividend<=numerator;divisor<=denominator;q<=0;remainder<=0;count<=W;busy<=1;end
            end else if(busy)begin
                remainder<=ge ? trial-{1'b0,divisor} : trial;
                dividend<={dividend[W-2:0],1'b0};q<=next_q;count<=count-1'b1;
                if(count==1)begin quotient<=next_q;busy<=0;done<=1;end
            end
        end
    end
endmodule
