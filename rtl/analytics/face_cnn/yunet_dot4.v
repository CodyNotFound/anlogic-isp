// Four physical signed multipliers, shared by all YuNet convolutions.
// 9-bit activations cover both unsigned camera BGR (0..255) and signed int8 maps.
// The scheduler supplies flattened OHWI products, padding and unused lanes = 0.
// Accept one four-product beat per clock; the last beat drains before publication.
// No floating point, vendor simulator primitive, or CPU classifier is required.
module yunet_dot4 #(parameter MODEL_SHIFT=0,FAST_PIPELINE=0)(
 input wire clk,rst_n,
 input wire start,input wire signed [31:0] bias,
 input wire signed [6:0] shift,input wire relu,
 output wire ready,
 input wire in_valid,output wire in_ready,input wire in_last,
 input wire [35:0] activations,input wire [31:0] weights,
 output reg out_valid,input wire out_ready,
 output reg signed [31:0] accumulator,
 output reg signed [7:0] value
);
 reg busy,closing,p_valid,p_last;
 reg signed [6:0] shift_q;reg relu_q;
 reg signed [31:0] sum;
 reg signed [16:0] p0,p1,p2,p3;
 wire signed [18:0] pair_sum={{2{p0[16]}},p0}+{{2{p1[16]}},p1}+{{2{p2[16]}},p2}+{{2{p3[16]}},p3};
 wire signed [31:0] next_sum=sum+{{13{pair_sum[18]}},pair_sum};
 assign ready=!busy;
 assign in_ready=busy&&!closing&&!out_valid;
 function signed [7:0] requant;
 input signed [31:0] a;input signed [6:0] s;input r;
 reg signed [63:0] wide;
 begin
  wide={{32{a[31]}},a};
  if(s>0)wide=(wide+(64'sd1<<(s-1)))>>>s;
  else if(s<0)wide=wide<<<(-s);
  requant=(r&&wide<0)?8'sd0:wide>127?8'sd127:wide< -128?-8'sd128:wide[7:0];
 end
 endfunction
 // The exported graph supports right shifts 0..31; zero is explicit. 33 bits retain
 // exact rounding for every signed-int32 accumulator without a 64-bit shifter.
 function signed [7:0] requant_model;
 input signed [31:0] a;input signed [6:0] s;input r;
 reg signed [32:0] q;
 begin
  if(s==0) q=$signed({a[31],a});
  else q=($signed({a[31],a})+(33'sd1<<(s[4:0]-1)))>>>s[4:0];
  requant_model=(r&&q<0)?8'sd0:q>127?8'sd127:q< -128?-8'sd128:q[7:0];
 end endfunction
 generate if(FAST_PIPELINE&&MODEL_SHIFT)begin: g_fast
  wire signed [17:0] pair01=$signed({p0[16],p0})+$signed({p1[16],p1});
  wire signed [17:0] pair23=$signed({p2[16],p2})+$signed({p3[16],p3});
  wire signed [18:0] products=$signed({pair01[17],pair01})+$signed({pair23[17],pair23});
  reg signed [18:0] beat;reg beat_valid,beat_last;
  reg [35:0] input_a;reg [31:0] input_w;reg input_valid,input_last;
  reg round_valid,shift_valid,clip_valid;
  reg signed [32:0] rounding,rounded,shifted;
  wire signed [31:0] accumulated=sum+{{13{beat[18]}},beat};
  always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin
    busy<=0;closing<=0;p_valid<=0;p_last<=0;shift_q<=0;relu_q<=0;
    sum<=0;p0<=0;p1<=0;p2<=0;p3<=0;out_valid<=0;accumulator<=0;value<=0;
    beat<=0;beat_valid<=0;beat_last<=0;round_valid<=0;shift_valid<=0;clip_valid<=0;
    rounding<=0;rounded<=0;shifted<=0;input_a<=0;input_w<=0;input_valid<=0;input_last<=0;
   end else begin
    input_valid<=0;p_valid<=input_valid;beat_valid<=p_valid;round_valid<=0;shift_valid<=round_valid;clip_valid<=shift_valid;
    if(start&&ready)begin
     busy<=1;closing<=0;sum<=bias;shift_q<=shift;relu_q<=relu;
     rounding<=shift==0?33'sd0:33'sd1<<(shift[4:0]-1'b1);
    end
    if(in_valid&&in_ready)begin
     input_a<=activations;input_w<=weights;input_valid<=1;input_last<=in_last;
     if(in_last)closing<=1;
    end
    if(input_valid)begin
     p0<=$signed(input_a[8:0])*$signed(input_w[7:0]);
     p1<=$signed(input_a[17:9])*$signed(input_w[15:8]);
     p2<=$signed(input_a[26:18])*$signed(input_w[23:16]);
     p3<=$signed(input_a[35:27])*$signed(input_w[31:24]);
     p_last<=input_last;
    end
    if(p_valid)begin beat<=products;beat_last<=p_last;end
    if(beat_valid)begin
     sum<=accumulated;
     if(beat_last)begin accumulator<=accumulated;round_valid<=1;end
    end
    if(round_valid)rounded<=$signed({sum[31],sum})+rounding;
    if(shift_valid)shifted<=rounded>>>shift_q[4:0];
    if(clip_valid)begin value<=(relu_q&&shifted<0)?8'sd0:shifted>127?8'sd127:shifted< -128?-8'sd128:shifted[7:0];out_valid<=1;end
    if(out_valid&&out_ready)begin out_valid<=0;busy<=0;closing<=0;end
   end
  end
 end else begin: g_original
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   busy<=0;closing<=0;p_valid<=0;p_last<=0;shift_q<=0;relu_q<=0;
   sum<=0;p0<=0;p1<=0;p2<=0;p3<=0;out_valid<=0;accumulator<=0;value<=0;
  end else begin
   p_valid<=0;
   if(start&&ready)begin busy<=1;closing<=0;sum<=bias;shift_q<=shift;relu_q<=relu;end
   if(in_valid&&in_ready)begin
    p0<=$signed(activations[8:0])*$signed(weights[7:0]);
    p1<=$signed(activations[17:9])*$signed(weights[15:8]);
    p2<=$signed(activations[26:18])*$signed(weights[23:16]);
    p3<=$signed(activations[35:27])*$signed(weights[31:24]);
    p_valid<=1;p_last<=in_last;if(in_last)closing<=1;
   end
   if(p_valid)begin
    sum<=next_sum;
    if(p_last)begin accumulator<=next_sum;value<=MODEL_SHIFT?requant_model(next_sum,shift_q,relu_q):requant(next_sum,shift_q,relu_q);out_valid<=1;end
   end
   if(out_valid&&out_ready)begin out_valid<=0;busy<=0;closing<=0;end
  end
 end
 end endgenerate
endmodule
