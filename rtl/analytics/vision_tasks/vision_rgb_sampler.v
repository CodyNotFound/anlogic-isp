// Unstalled video -> rounded RGB block means. Synchronous column RAM reads.
// Consumers accept a whole frame or skip it; malformed/stalled frames cancel it.
module vision_rgb_sampler #(
    parameter WIDTH=1280,HEIGHT=720,SHIFT=3,
    parameter STALL_CYCLES=5000000
)(
    input wire clk,rst_n,enable,sof,eol,de,
    input wire [23:0] rgb,
    output reg frame_start,sample_valid,frame_end,frame_error,
    output reg [7:0] sample_x,sample_y,
    output reg [23:0] sample_rgb,
    output wire [7:0] sample_gray
);
    localparam SW=WIDTH>>SHIFT;
    localparam MASK=(1<<SHIFT)-1;
    reg [11:0] x,y;
    wire [11:0] px=sof?12'd0:x,py=sof?12'd0:y;
    reg capturing;
    reg [23:0] stall;
    reg [10:0] hr,hg,hb;
    (* ram_style="bram" *) reg [13:0] cr[0:SW-1],cg[0:SW-1],cb[0:SW-1];
    reg [13:0] qr,qg,qb;
    wire [10:0] rr=((px&MASK)==0?11'd0:hr)+{3'd0,rgb[23:16]};
    wire [10:0] rg=((px&MASK)==0?11'd0:hg)+{3'd0,rgb[15:8]};
    wire [10:0] rb=((px&MASK)==0?11'd0:hb)+{3'd0,rgb[7:0]};
    wire [14:0] sr={1'b0,((py&MASK)==0?14'd0:qr)}+rr;
    wire [14:0] sg={1'b0,((py&MASK)==0?14'd0:qg)}+rg;
    wire [14:0] sb={1'b0,((py&MASK)==0?14'd0:qb)}+rb;
    wire [14:0] ar=sr+(1<<(2*SHIFT-1)),ag=sg+(1<<(2*SHIFT-1)),ab=sb+(1<<(2*SHIFT-1));
    wire bad=de && (px>=WIDTH || py>=HEIGHT || eol!=(px==WIDTH-1));
    wire active=capturing || (sof && enable);
    wire [9:0] gy={2'd0,sample_rgb[23:16]}+{1'b0,sample_rgb[15:8],1'b0}+{2'd0,sample_rgb[7:0]};
    assign sample_gray=gy[9:2];
    always @(posedge clk)begin
        qr<=cr[px>>SHIFT];qg<=cg[px>>SHIFT];qb<=cb[px>>SHIFT];
        if(enable && active && de && !bad && (px&MASK)==MASK)begin
            cr[px>>SHIFT]<=sr[13:0];cg[px>>SHIFT]<=sg[13:0];cb[px>>SHIFT]<=sb[13:0];
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin x<=0;y<=0;capturing<=0;stall<=0;hr<=0;hg<=0;hb<=0;
            frame_start<=0;sample_valid<=0;frame_end<=0;frame_error<=0;sample_x<=0;sample_y<=0;sample_rgb<=0;end
        else begin
            frame_start<=0;sample_valid<=0;frame_end<=0;frame_error<=0;
            if(sof)begin x<=0;y<=0;end
            if(de)begin x<=eol?0:px+1'b1;y<=eol?py+1'b1:py;end
            if(!enable)begin capturing<=0;stall<=0;end
            else begin
                if(sof)begin capturing<=1;frame_start<=1;hr<=0;hg<=0;hb<=0;stall<=0;end
                if(capturing)stall<=stall+1'b1;
                if(de && active && !bad)begin
                    stall<=0;hr<=((px&MASK)==MASK)?0:rr;hg<=((px&MASK)==MASK)?0:rg;hb<=((px&MASK)==MASK)?0:rb;
                    if((px&MASK)==MASK && (py&MASK)==MASK)begin
                        sample_valid<=1;sample_x<=px>>SHIFT;sample_y<=py>>SHIFT;
                        sample_rgb<={ar[2*SHIFT+:8],ag[2*SHIFT+:8],ab[2*SHIFT+:8]};
                        if(px==WIDTH-1 && py==HEIGHT-1)begin frame_end<=1;capturing<=0;end
                    end
                end
                if(bad || (sof && capturing) || (capturing && stall>=STALL_CYCLES-1))begin
                    frame_error<=1;capturing<=0;frame_start<=0;sample_valid<=0;frame_end<=0;
                end
            end
        end
    end
endmodule
