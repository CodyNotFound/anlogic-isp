// Four-clock, one RGB pixel/clock cel renderer. Causal 3x3 RGB+Y window.
// Gaussian smoothing in low-gradient areas, luminance posterization, ink lines.
// Two synchronous line memories; borders replicate the available first sample.
// Output at (x,y) depicts (max(x-1,0),max(y-1,0)); ink and color share that center.
module pixel_cartoon #(
 parameter integer IMG_WIDTH=1280,IMG_HEIGHT=720,
 parameter integer SMOOTH_TH=24,INK_TH=40,INK_DARK_TH=56,INK_SOLID_TH=80,
 parameter integer SHADE_SHIFT=5,EXTRA_EFFECTS=0
)(input wire clk,rst_n,frame_start,line_end,de,input wire [23:0] pixel_in,
 output reg [23:0] pixel_out,output reg out_de,out_sof,out_eol,output reg [23:0] edge_out,output reg[23:0] sharpen_out,blur_out,emboss_out);
 localparam AW=IMG_WIDTH<2?1:$clog2(IMG_WIDTH);
 reg [AW-1:0] x;reg [10:0] y;
 wire [AW-1:0] rx=frame_start?0:x;
 wire [10:0] ry=frame_start?0:y;
 reg [23:0] input_prev1,input_prev2;
 function [7:0] median3;
 input [7:0] a,b,c;
 begin median3=a>b?(b>c?b:(a>c?c:a)):(a>c?a:(b>c?c:b));end
 endfunction
 wire [23:0] h1=rx==0?pixel_in:input_prev1;
 wire [23:0] h2=rx<2?h1:input_prev2;
 wire [23:0] filtered={median3(h2[23:16],h1[23:16],pixel_in[23:16]),median3(h2[15:8],h1[15:8],pixel_in[15:8]),median3(h2[7:0],h1[7:0],pixel_in[7:0])};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin input_prev1<=0;input_prev2<=0;end
  else if(de)begin input_prev2<=h1;input_prev1<=pixel_in;end
 end
 wire [7:0] raw_y={2'b0,filtered[23:18]}+{1'b0,filtered[15:9]}+{2'b0,filtered[7:2]};
 (* ram_style="bram" *) reg [31:0] row1[0:IMG_WIDTH-1],row2[0:IMG_WIDTH-1];
 reg [31:0] q1,q2,s1_pixel;
 reg [AW-1:0] s1_x;reg [10:0] s1_y;
 reg d1,f1,l1,d2,f2,l2,d3,f3,l3;
 always @(posedge clk)begin
  q1<=row1[rx];q2<=row2[rx];
  if(de)row1[rx]<={raw_y,filtered};
  // One-cycle delayed write uses the corresponding synchronous old-row data.
  if(d1)row2[s1_x]<=q1;
 end
 reg [31:0] th1,th2,mh1,mh2,bh1,bh2;
 wire [31:0] mn=s1_y==0?s1_pixel:q1;
 wire [31:0] tn=s1_y<2?mn:q2;
 wire [31:0] bn=s1_pixel;
 wire [31:0] t1=s1_x==0?tn:th1,m1=s1_x==0?mn:mh1,b1=s1_x==0?bn:bh1;
 wire [31:0] t2=s1_x<2?t1:th2,m2=s1_x<2?m1:mh2,b2=s1_x<2?b1:bh2;
 // All spatial modes use this existing RGB/Y window. Only strong blur
 // needs one additional RGB row for its vertical recursive state.
 // Sum the eight neighbors directly: the old ninth-sample sum followed
 // by subtracting the center adds an avoidable carry chain after line RAM.
 wire [8:0] yp0={1'b0,t2[31:24]}+{1'b0,t1[31:24]};
 wire [8:0] yp1={1'b0,tn[31:24]}+{1'b0,m2[31:24]};
 wire [8:0] yp2={1'b0,mn[31:24]}+{1'b0,b2[31:24]};
 wire [8:0] yp3={1'b0,b1[31:24]}+{1'b0,bn[31:24]};
 wire [9:0] yh0={1'b0,yp0}+{1'b0,yp1},yh1={1'b0,yp2}+{1'b0,yp3};
 wire [10:0] neighbor_sum={1'b0,yh0}+{1'b0,yh1};
 wire [11:0] neighbor_y={4'd0,neighbor_sum[10:3]};
 wire signed[11:0] detail_y=$signed({4'd0,m1[31:24]})-$signed(neighbor_y);
 wire signed[11:0] sharp_delta=(detail_y>6||detail_y< -6)?(detail_y<<<2):12'sd0;
 wire signed[11:0] emboss_d=$signed({4'd0,m1[31:24]})-$signed({4'd0,t2[31:24]});
 wire signed[11:0] emboss_y=12'sd128+((emboss_d>6||emboss_d< -6)?emboss_d:12'sd0);
 function[7:0] clip_y;input signed[11:0] value;begin clip_y=value<0?0:value>255?255:value[7:0];end endfunction
 (* ram_style="bram" *) reg[23:0] blur_row[0:IMG_WIDTH-1];
 reg[23:0] blur_q,blur_horizontal,blur_h1,sharp2,sharp3,blur2,blur3;
 reg[7:0]emboss2,emboss3;
 function[7:0] iir8;input[7:0]current,previous;reg[9:0]sum;
 begin sum={2'd0,current}+{2'd0,previous}+{1'd0,previous,1'd0}+10'd2;iir8=sum[9:2];end endfunction
 wire[23:0] blur_h=rx==0?filtered:{iir8(filtered[23:16],blur_horizontal[23:16]),iir8(filtered[15:8],blur_horizontal[15:8]),iir8(filtered[7:0],blur_horizontal[7:0])};
 wire[23:0] blur_v=s1_y==0?blur_h1:{iir8(blur_h1[23:16],blur_q[23:16]),iir8(blur_h1[15:8],blur_q[15:8]),iir8(blur_h1[7:0],blur_q[7:0])};
 always @(posedge clk)if(EXTRA_EFFECTS)begin
  blur_q<=blur_row[rx];if(d1)blur_row[s1_x]<=blur_v;
 end
 function [11:0] gauss;
 input [7:0] a,b,c,d,e,f,g,h,i;
 reg [9:0] corners,sides;
 begin corners={2'd0,a}+{2'd0,c}+{2'd0,g}+{2'd0,i};
 sides={2'd0,b}+{2'd0,d}+{2'd0,f}+{2'd0,h};
 gauss={2'd0,corners}+{1'd0,sides,1'd0}+{2'd0,e,2'd0}+12'd8;end
 endfunction
 wire signed [8:0] dx0=$signed({1'b0,tn[31:24]})-$signed({1'b0,t2[31:24]});
 wire signed [8:0] dx1=$signed({1'b0,mn[31:24]})-$signed({1'b0,m2[31:24]});
 wire signed [8:0] dx2=$signed({1'b0,bn[31:24]})-$signed({1'b0,b2[31:24]});
 wire signed [8:0] dy0=$signed({1'b0,b2[31:24]})-$signed({1'b0,t2[31:24]});
 wire signed [8:0] dy1=$signed({1'b0,b1[31:24]})-$signed({1'b0,t1[31:24]});
 wire signed [8:0] dy2=$signed({1'b0,bn[31:24]})-$signed({1'b0,tn[31:24]});
 function signed [12:0] scharr;
 input signed [8:0] a,b,c;
 reg signed [12:0] aa,bb,cc;
 begin aa={{4{a[8]}},a};bb={{4{b[8]}},b};cc={{4{c[8]}},c};
 scharr=(aa<<<1)+aa+(bb<<<3)+(bb<<<1)+(cc<<<1)+cc;end
 endfunction
 function [7:0] absdiff;
 input [7:0] a,b;begin absdiff=a>b?a-b:b-a;end
 endfunction
 function [9:0] rgb_distance;
 input [23:0] a,b;
 begin rgb_distance={2'd0,absdiff(a[23:16],b[23:16])}+{2'd0,absdiff(a[15:8],b[15:8])}+{2'd0,absdiff(a[7:0],b[7:0])};end
 endfunction
 reg [10:0] color_gradient2;
 reg signed [12:0] gx2,gy2;
 reg [11:0] r2,g2,b2sum;
 reg [23:0] center2,color3;
 reg [9:0] strength3;
 wire [12:0] ax=gx2[12]?-gx2:gx2,ay=gy2[12]?-gy2:gy2;
 wire [13:0] mag={1'b0,ax}+{1'b0,ay};
 wire [9:0] luma_strength=mag[13:4];
 wire [9:0] color_strength={1'b0,color_gradient2[10:2]};
 wire [9:0] strength=luma_strength>color_strength?luma_strength:color_strength;
 wire [7:0] sy3={2'b0,color3[23:18]}+{1'b0,color3[15:9]}+{2'b0,color3[7:2]};
 wire [8:0] rounded_y={1'b0,sy3}+(9'd1<<(SHADE_SHIFT-1));
 wire [8:0] band_y=(rounded_y>>SHADE_SHIFT)<<SHADE_SHIFT;
 wire [7:0] quant_y=band_y>255?8'd255:band_y[7:0];
 wire signed [9:0] shade_delta=$signed({2'd0,quant_y})-$signed({2'd0,sy3});
 function [7:0] shade;
 input [7:0] c;input signed [9:0] delta;
 reg signed [10:0] value;
 begin value=$signed({3'd0,c})+delta;
 shade=value<0?8'd0:value>255?8'd255:value[7:0];end
 endfunction
 wire [9:0] ink_noise_allowance=sy3<64?10'd12:10'd0;
 wire [23:0] shaded={shade(color3[23:16],shade_delta),shade(color3[15:8],shade_delta),shade(color3[7:0],shade_delta)};
 // Mode07 shares the same centered RGB/Y window. Relative threshold plus a
 // dark noise floor, with dim weak contours instead of one hard 80-level cut.
 wire [9:0] edge_threshold=sy3<96?10'd20:10'd10+{7'd0,sy3[7:5]};
 wire [7:0] edge_level=strength3>=80?8'd255:strength3>=40?8'd192:
     strength3>=20?8'd112:strength3>=edge_threshold?8'd64:
     8'd0;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   x<=0;y<=0;s1_x<=0;s1_y<=0;s1_pixel<=0;
   d1<=0;f1<=0;l1<=0;d2<=0;f2<=0;l2<=0;d3<=0;f3<=0;l3<=0;
   th1<=0;th2<=0;mh1<=0;mh2<=0;bh1<=0;bh2<=0;
   gx2<=0;gy2<=0;color_gradient2<=0;r2<=0;g2<=0;b2sum<=0;center2<=0;color3<=0;strength3<=0;
   pixel_out<=0;edge_out<=0;sharpen_out<=0;blur_out<=0;emboss_out<=0;blur_horizontal<=0;blur_h1<=0;sharp2<=0;sharp3<=0;emboss2<=0;emboss3<=0;blur2<=0;blur3<=0;out_de<=0;out_sof<=0;out_eol<=0;
  end else begin
   if(EXTRA_EFFECTS&&de)begin blur_horizontal<=blur_h;blur_h1<=blur_h;end
   d1<=de;f1<=frame_start;l1<=line_end;s1_x<=rx;s1_y<=ry;s1_pixel<={raw_y,filtered};
   if(frame_start)begin
    x<=de&&!line_end?1:0;y<=de&&line_end?1:0;
   end else if(de)begin
    if(line_end || x==IMG_WIDTH-1)begin x<=0;y<=y==IMG_HEIGHT-1?0:y+1'b1;end
    else x<=x+1'b1;
   end
   d2<=d1;f2<=f1;l2<=l1;
   if(d1)begin
    if(EXTRA_EFFECTS)begin sharp2<={clip_y($signed({4'd0,m1[23:16]})+sharp_delta),clip_y($signed({4'd0,m1[15:8]})+sharp_delta),clip_y($signed({4'd0,m1[7:0]})+sharp_delta)};emboss2<=clip_y(emboss_y);blur2<=blur_v;end
    r2<=gauss(t2[23:16],t1[23:16],tn[23:16],m2[23:16],m1[23:16],mn[23:16],b2[23:16],b1[23:16],bn[23:16]);
    g2<=gauss(t2[15:8],t1[15:8],tn[15:8],m2[15:8],m1[15:8],mn[15:8],b2[15:8],b1[15:8],bn[15:8]);
    b2sum<=gauss(t2[7:0],t1[7:0],tn[7:0],m2[7:0],m1[7:0],mn[7:0],b2[7:0],b1[7:0],bn[7:0]);
    color_gradient2<={1'b0,rgb_distance(mn[23:0],m2[23:0])}+{1'b0,rgb_distance(b1[23:0],t1[23:0])};
    center2<=m1[23:0];gx2<=scharr(dx0,dx1,dx2);gy2<=scharr(dy0,dy1,dy2);
    th2<=t1;th1<=tn;mh2<=m1;mh1<=mn;bh2<=b1;bh1<=bn;
   end
   d3<=d2;f3<=f2;l3<=l2;
   if(d2)begin
    if(EXTRA_EFFECTS)begin sharp3<=sharp2;emboss3<=emboss2;blur3<=blur2;end
    strength3<=strength;color3<=strength<=SMOOTH_TH?{r2[11:4],g2[11:4],b2sum[11:4]}:center2;
   end
   out_de<=d3;out_sof<=f3;out_eol<=l3;
   sharpen_out<=EXTRA_EFFECTS&&d3?sharp3:24'd0;
   emboss_out<=EXTRA_EFFECTS&&d3?{emboss3,emboss3,emboss3}:24'd0;
   blur_out<=EXTRA_EFFECTS&&d3?blur3:24'd0;
   edge_out<=d3?{edge_level,edge_level,edge_level}:24'd0;
   if(!d3)pixel_out<=0;
   else if(strength3>=INK_SOLID_TH+ink_noise_allowance)pixel_out<=24'h101018;
   else if(strength3>=INK_DARK_TH+ink_noise_allowance)pixel_out<={2'd0,shaded[23:18],2'd0,shaded[15:10],2'd0,shaded[7:2]};
   else if(strength3>=INK_TH+ink_noise_allowance)pixel_out<={1'd0,shaded[23:17],1'd0,shaded[15:9],1'd0,shaded[7:1]};
   else pixel_out<=shaded;
  end
 end
endmodule
