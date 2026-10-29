// Integer single-face decoder: all anchors, three strides, no rotation retry.
// Frame start is accepted only after the previous result (pipeline drained).
// ROMs match the exported per-head binary scales; Q7 sigmoid, Q4 geometry.
// The seven shift/add score terms intentionally use logic, leaving four DSPs
// for the shared convolution kernel. This block is not an inference engine.
module yunet_decode #(
 parameter SIGMOID_FILE="rtl/analytics/face_cnn/sigmoid.hex",
 parameter OFFSET_FILE="rtl/analytics/face_cnn/offset.hex",
 parameter SIZE_FILE="rtl/analytics/face_cnn/size.hex",
 parameter integer SCORE_THRESHOLD=6815
)(input wire clk,rst_n,frame_start,
 input wire in_valid,in_last,input wire [1:0] level,
 input wire [7:0] grid_x,grid_y,
 input wire [7:0] cls,obj,bx,by,bw,bh,
 output reg result_valid,found,output reg [13:0] score_product,
 output reg [11:0] box_x,box_y,box_size,center_x,center_y);
 (* ram_style="bram" *) reg [6:0] sigmoid_rom[0:1535];
 (* ram_style="bram" *) reg signed [15:0] offset_rom[0:767];
 (* ram_style="bram" *) reg [15:0] size_rom[0:767];
 initial begin $readmemh(SIGMOID_FILE,sigmoid_rom);$readmemh(OFFSET_FILE,offset_rom);$readmemh(SIZE_FILE,size_rom);end
 reg v1,v2,last1,last2;reg [6:0] cp1,op1;
 reg signed [15:0] dx1,dy1;reg [15:0] w1,h1;
 reg [7:0] gx1,gy1;reg [1:0] lev1;
 reg signed [31:0] cx2,cy2;reg [15:0] w2,h2;reg [13:0] score2;
 reg best_valid;reg [13:0] best_score;
 reg [11:0] best_x,best_y,best_size,best_cx,best_cy;
 wire [9:0] clsa={level,cls},obja={level,obj};
 function [13:0] product7;
 input [6:0] a,b;integer i;reg [13:0] s;
 begin s=0;for(i=0;i<7;i=i+1)if(b[i])s=s+({7'b0,a}<<i);product7=s;end
 endfunction
 function [11:0] bound;
 input signed [31:0] a;input [11:0] hi;
 begin bound=a<0?12'd0:a>$signed({1'b0,hi})?hi:a[11:0];end
 endfunction
 wire [11:0] left2=bound((cx2-$signed({17'b0,w2[15:1]}))>>>4,12'd160);
 wire [11:0] right2=bound((cx2+$signed({17'b0,w2[15:1]})+32'sd15)>>>4,12'd160);
 wire [11:0] top2=bound((cy2-$signed({17'b0,h2[15:1]}))>>>4,12'd90);
 wire [11:0] bottom2=bound((cy2+$signed({17'b0,h2[15:1]})+32'sd15)>>>4,12'd90);
 // Clip corners in a separate stage before box geometry and best selection.
 (* syn_preserve=1 *) reg [11:0] left3,right3,top3,bottom3;
 reg v3,last3,domain3;reg [13:0] score3;
 wire [11:0] width3=right3-left3,height3=bottom3-top3;
 wire [11:0] side3=width3>height3?width3:height3;
 wire [11:0] side_cam=side3>90?12'd720:side3<<3;
 wire [11:0] cx_cam=(left3+right3)<<2,cy_cam=(top3+bottom3)<<2;
 wire [11:0] x_cam=bound($signed({1'b0,cx_cam})-$signed({1'b0,side_cam[11:1]}),12'd1280-side_cam);
 wire [11:0] y_cam=bound($signed({1'b0,cy_cam})-$signed({1'b0,side_cam[11:1]}),12'd720-side_cam);
 wire valid3=domain3 && right3>left3 && bottom3>top3;
 wire replace3=valid3&&(!best_valid||score3>best_score);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   v1<=0;v2<=0;v3<=0;last1<=0;last2<=0;last3<=0;domain3<=0;score3<=0;left3<=0;right3<=0;top3<=0;bottom3<=0;cp1<=0;op1<=0;dx1<=0;dy1<=0;w1<=0;h1<=0;gx1<=0;gy1<=0;lev1<=0;
   cx2<=0;cy2<=0;w2<=0;h2<=0;score2<=0;best_valid<=0;best_score<=0;
   best_x<=0;best_y<=0;best_size<=0;best_cx<=0;best_cy<=0;
   result_valid<=0;found<=0;score_product<=0;box_x<=0;box_y<=0;box_size<=0;center_x<=0;center_y<=0;
  end else begin
   result_valid<=0;v1<=in_valid;v2<=v1;v3<=v2;last1<=in_last;last2<=last1;last3<=last2;
   if(frame_start)begin best_valid<=0;best_score<=0;found<=0;end
   if(in_valid)begin
    cp1<=sigmoid_rom[clsa];op1<=sigmoid_rom[11'd768+obja];
    dx1<=offset_rom[{level,bx}];dy1<=offset_rom[{level,by}];
    w1<=size_rom[{level,bw}];h1<=size_rom[{level,bh}];gx1<=grid_x;gy1<=grid_y;lev1<=level;
   end
   if(v1)begin
    score2<=product7(cp1,op1);w2<=w1;h2<=h1;
    cx2<=$signed({1'b0,gx1,7'b0}<<lev1)+{{16{dx1[15]}},dx1};
    cy2<=$signed({1'b0,gy1,7'b0}<<lev1)+{{16{dy1[15]}},dy1};
   end
   if(v2)begin
    left3<=left2;right3<=right2;top3<=top2;bottom3<=bottom2;score3<=score2;
    domain3<=score2>=SCORE_THRESHOLD&&cx2>=0&&cx2<2560&&cy2>=0&&cy2<1440;
   end
   if(v3)begin
    if(replace3)begin best_valid<=1;best_score<=score3;best_x<=x_cam;best_y<=y_cam;best_size<=side_cam;best_cx<=cx_cam;best_cy<=cy_cam;end
    if(last3)begin
     result_valid<=1;found<=replace3||best_valid;
     score_product<=replace3?score3:best_valid?best_score:14'd0;
     box_x<=replace3?x_cam:best_valid?best_x:12'd0;box_y<=replace3?y_cam:best_valid?best_y:12'd0;
     box_size<=replace3?side_cam:best_valid?best_size:12'd0;
     center_x<=replace3?cx_cam:best_valid?best_cx:12'd0;center_y<=replace3?cy_cam:best_valid?best_cy:12'd0;
    end
   end
  end
 end
endmodule
