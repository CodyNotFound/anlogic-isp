// Complete 55-operation position-only YuNet integer program, shared four-DSP MAC.
// Baseline stores full feature maps in a 128KiB arena; NOT yet camera-integrated.
// Four interleaved banks permit four channel reads per convolution beat.
// Depthwise/single-channel layers use lane0, avoiding multi-port RAM replication.
module yunet_network #(
 parameter integer PROGRAM_DEPTH=55,WEIGHT_DEPTH=12373,BIAS_DEPTH=1524,
 parameter PROGRAM_FILE="rtl/analytics/face_cnn/program.hex",
 parameter W0_FILE="rtl/analytics/face_cnn/weights0.hex",W1_FILE="rtl/analytics/face_cnn/weights1.hex",
 parameter W2_FILE="rtl/analytics/face_cnn/weights2.hex",W3_FILE="rtl/analytics/face_cnn/weights3.hex",
 parameter BIAS_FILE="rtl/analytics/face_cnn/bias.hex",SHIFT_FILE="rtl/analytics/face_cnn/shift.hex"
)(input wire clk,rst_n,start,
 input wire load_valid,input wire [16:0] load_address,input wire [7:0] load_data,
 input wire [16:0] read_address,output wire [7:0] read_data,
 output wire busy,output reg done,operation_done,output reg [5:0] operation_index,
 output reg [31:0] cycles);
 localparam IDLE=0,CONFIG_WAIT=1,CONFIG=2,INIT=3,META=4,DOT_START=5,
  CONV_READ=6,CONV_WAIT=7,CONV_FEED=8,CONV_RESULT=9,NEXT_OUTPUT=10,
  MISC_READ=11,MISC_WAIT=12,MISC_EVAL=13;
 reg [3:0] state;assign busy=state!=IDLE;
 (* ram_style="bram" *) reg [7:0] fm0[0:32767],fm1[0:32767],fm2[0:32767],fm3[0:32767];
 (* ram_style="bram" *) reg signed [7:0] wm0[0:WEIGHT_DEPTH-1],wm1[0:WEIGHT_DEPTH-1],wm2[0:WEIGHT_DEPTH-1],wm3[0:WEIGHT_DEPTH-1];
 (* ram_style="bram" *) reg [159:0] program_rom[0:PROGRAM_DEPTH-1];
 (* ram_style="bram" *) reg signed [31:0] biases[0:BIAS_DEPTH-1];
 (* ram_style="bram" *) reg signed [6:0] shifts[0:BIAS_DEPTH-1];
 initial begin
  $readmemh(PROGRAM_FILE,program_rom);$readmemh(W0_FILE,wm0);$readmemh(W1_FILE,wm1);$readmemh(W2_FILE,wm2);$readmemh(W3_FILE,wm3);
  $readmemh(BIAS_FILE,biases);$readmemh(SHIFT_FILE,shifts);
 end
 reg [159:0] instruction;reg [3:0] opcode;
 reg [16:0] src_base,src2_base,dst_base;
 reg [7:0] iw,ih,ow,oh;reg [6:0] ci,co;
 reg kernel3,stride2,pad1,depthwise,relu,input_unsigned;
 reg [15:0] weight_base;reg [10:0] bias_base;reg signed [6:0] shift1,shift2;
 reg [7:0] ox,oy;reg [6:0] oc,ic;reg [1:0] kx,ky,misc_step;
 reg [2:0] cshift;reg [16:0] operand_address,weight_address;
 reg pad_q;reg [1:0] a_bank_q,w_bank_q;
 reg [7:0] aq0,aq1,aq2,aq3;reg signed [7:0] wq0,wq1,wq2,wq3;
 reg signed [31:0] bias_q;reg signed [6:0] shift_q;
 reg signed [31:0] misc_temp;reg write_pending;reg [16:0] write_address;reg [7:0] write_data;
 function [15:0] multiply8;
 input [7:0] a,b;integer i;reg [15:0] s;
 begin s=0;for(i=0;i<8;i=i+1)if(b[i])s=s+({8'b0,a}<<i);multiply8=s;end
 endfunction
 function [2:0] channel_shift;
 input [6:0] c;
 begin case(c)7'd4:channel_shift=2;7'd16:channel_shift=4;7'd32:channel_shift=5;7'd64:channel_shift=6;default:channel_shift=0;endcase end
 endfunction
 function [16:0] feature_index;
 input [16:0] base;input [7:0] yy,xx,width;input [6:0] channel;input [2:0] cs;
 reg [16:0] pixel;
 begin pixel={1'b0,multiply8(yy,width)}+xx;feature_index=base+(pixel<<cs)+channel;end
 endfunction
 wire signed [9:0] sample_x=$signed({2'b0,ox}<<stride2)+$signed({8'b0,kx})-$signed({9'b0,pad1});
 wire signed [9:0] sample_y=$signed({2'b0,oy}<<stride2)+$signed({8'b0,ky})-$signed({9'b0,pad1});
 wire padding=sample_x<0||sample_y<0||sample_x>=$signed({2'b0,iw})||sample_y>=$signed({2'b0,ih});
 wire [6:0] channel=depthwise?oc:ic;
 wire [16:0] conv_addr=feature_index(src_base,sample_y[7:0],sample_x[7:0],iw,channel,cshift);
 wire [3:0] tap=kernel3?({2'b0,ky}<<1)+ky+kx:4'd0;
 wire [16:0] w_offset=depthwise ? (({10'b0,oc}<<3)+oc+tap) :
    (((kernel3?(({10'b0,oc}<<3)+oc):{10'b0,oc})+tap)<<cshift)+ic;
 wire [16:0] conv_weight=weight_base+w_offset;
 wire single_lane=depthwise||ci==1;
 wire last_ic=depthwise||ci==1||ic+7'd4>=ci;
 wire last_tap=last_ic&&(!kernel3||(kx==2&&ky==2));
 wire [7:0] misc_y=opcode==2?(oy<<1)+{7'b0,misc_step[1]}:opcode==3?(oy>>1):oy;
 wire [7:0] misc_x=opcode==2?(ox<<1)+{7'b0,misc_step[0]}:opcode==3?(ox>>1):ox;
 wire [16:0] misc_base=opcode==4&&misc_step==1?src2_base:src_base;
 wire [16:0] misc_addr=feature_index(misc_base,misc_y,misc_x,iw,oc,cshift);
 wire [16:0] memory_address=!busy?read_address:opcode==1?conv_addr:misc_addr;
 wire [7:0] selected_a=a_bank_q==0?aq0:a_bank_q==1?aq1:a_bank_q==2?aq2:aq3;
 wire signed [7:0] selected_w=w_bank_q==0?wq0:w_bank_q==1?wq1:w_bank_q==2?wq2:wq3;
 wire signed [8:0] first_a=input_unsigned?$signed({1'b0,selected_a}):$signed({selected_a[7],selected_a});
 wire [35:0] dot_a=pad_q?36'd0:single_lane?{27'd0,first_a}:
  {input_unsigned?{1'b0,aq3}:{aq3[7],aq3},input_unsigned?{1'b0,aq2}:{aq2[7],aq2},input_unsigned?{1'b0,aq1}:{aq1[7],aq1},input_unsigned?{1'b0,aq0}:{aq0[7],aq0}};
 wire [31:0] dot_w=single_lane?{24'd0,selected_w}:{wq3,wq2,wq1,wq0};
 wire dot_ready,dot_in_ready,dot_valid;wire signed [31:0] dot_acc;wire signed [7:0] dot_value;
 yunet_dot4 mac(.clk(clk),.rst_n(rst_n),.start(state==DOT_START),.bias(bias_q),.shift(shift_q),.relu(relu),.ready(dot_ready),
  .in_valid(state==CONV_FEED),.in_ready(dot_in_ready),.in_last(last_tap),.activations(dot_a),.weights(dot_w),
  .out_valid(dot_valid),.out_ready(state==CONV_RESULT),.accumulator(dot_acc),.value(dot_value));
 reg [1:0] debug_bank;
 assign read_data=debug_bank==0?aq0:debug_bank==1?aq1:debug_bank==2?aq2:aq3;
 always @(posedge clk)begin
  instruction<=program_rom[operation_index];bias_q<=biases[bias_base+oc];shift_q<=shifts[bias_base+oc];
  aq0<=fm0[memory_address[16:2]];aq1<=fm1[memory_address[16:2]];aq2<=fm2[memory_address[16:2]];aq3<=fm3[memory_address[16:2]];
  wq0<=wm0[conv_weight[15:2]];wq1<=wm1[conv_weight[15:2]];wq2<=wm2[conv_weight[15:2]];wq3<=wm3[conv_weight[15:2]];
  debug_bank<=read_address[1:0];
  if(!busy&&load_valid)begin
   case(load_address[1:0])0:fm0[load_address[16:2]]<=load_data;1:fm1[load_address[16:2]]<=load_data;2:fm2[load_address[16:2]]<=load_data;3:fm3[load_address[16:2]]<=load_data;endcase
  end else if(write_pending)begin
   case(write_address[1:0])0:fm0[write_address[16:2]]<=write_data;1:fm1[write_address[16:2]]<=write_data;2:fm2[write_address[16:2]]<=write_data;3:fm3[write_address[16:2]]<=write_data;endcase
  end
 end
 function signed [7:0] quantize;
 input signed [63:0] v;input signed [6:0] s;reg signed [63:0] q;
 begin q=s>0?(v+(64'sd1<<(s-1)))>>>s:v<<<(-s);quantize=q>127?8'sd127:q< -128?-8'sd128:q[7:0];end
 endfunction
 wire signed [31:0] misc_a={{24{selected_a[7]}},selected_a};
 wire signed [31:0] pool_max=misc_step==0||misc_a>misc_temp?misc_a:misc_temp;
 wire signed [6:0] align_shift=shift1>shift2?shift1:shift2;
 wire signed [63:0] aligned_a=$signed({{32{misc_temp[31]}},misc_temp})<<<(align_shift-shift1);
 wire signed [63:0] aligned_b=$signed({{32{misc_a[31]}},misc_a})<<<(align_shift-shift2);
 wire [16:0] output_address=feature_index(dst_base,oy,ox,ow,oc,channel_shift(co));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;done<=0;operation_done<=0;operation_index<=0;cycles<=0;
   opcode<=0;src_base<=0;src2_base<=0;dst_base<=0;iw<=0;ih<=0;ow<=0;oh<=0;ci<=0;co<=0;
   kernel3<=0;stride2<=0;pad1<=0;depthwise<=0;relu<=0;input_unsigned<=0;weight_base<=0;bias_base<=0;shift1<=0;shift2<=0;
   ox<=0;oy<=0;oc<=0;ic<=0;kx<=0;ky<=0;misc_step<=0;cshift<=0;pad_q<=0;a_bank_q<=0;w_bank_q<=0;
   misc_temp<=0;write_pending<=0;write_address<=0;write_data<=0;
  end else begin
   done<=0;operation_done<=0;write_pending<=0;
   if(busy)cycles<=cycles+1'b1;
   case(state)
    IDLE:if(start)begin operation_index<=0;cycles<=0;state<=CONFIG_WAIT;end
    CONFIG_WAIT:state<=CONFIG;
    CONFIG:begin
     opcode<=instruction[3:0];src_base<=instruction[20:4];src2_base<=instruction[37:21];dst_base<=instruction[54:38];
     iw<=instruction[62:55];ih<=instruction[70:63];ow<=instruction[78:71];oh<=instruction[86:79];ci<=instruction[93:87];co<=instruction[100:94];
     kernel3<=instruction[101];stride2<=instruction[102];pad1<=instruction[103];depthwise<=instruction[104];relu<=instruction[105];
     weight_base<=instruction[121:106];bias_base<=instruction[132:122];shift1<=instruction[139:133];shift2<=instruction[146:140];input_unsigned<=instruction[147];
     cshift<=channel_shift(instruction[93:87]);ox<=0;oy<=0;oc<=0;state<=INIT;
    end
    INIT:begin ic<=0;kx<=0;ky<=0;misc_step<=0;state<=opcode==1?META:MISC_READ;end
    META:state<=DOT_START;
    DOT_START:if(dot_ready)state<=CONV_READ;
    CONV_READ:begin pad_q<=padding;a_bank_q<=conv_addr[1:0];w_bank_q<=conv_weight[1:0];state<=CONV_WAIT;end
    CONV_WAIT:state<=CONV_FEED;
    CONV_FEED:if(dot_in_ready)begin
     if(last_tap)state<=CONV_RESULT;
     else begin
      if(last_ic)begin ic<=0;if(kx==2)begin kx<=0;ky<=ky+1'b1;end else kx<=kx+1'b1;end
      else ic<=ic+7'd4;
      state<=CONV_READ;
     end
    end
    CONV_RESULT:if(dot_valid)begin write_pending<=1;write_address<=output_address;write_data<=dot_value;state<=NEXT_OUTPUT;end
    MISC_READ:begin a_bank_q<=misc_addr[1:0];state<=MISC_WAIT;end
    MISC_WAIT:state<=MISC_EVAL;
    MISC_EVAL:begin
     if(opcode==2&&misc_step!=3)begin misc_temp<=pool_max;misc_step<=misc_step+1'b1;state<=MISC_READ;end
     else if(opcode==4&&misc_step==0)begin misc_temp<=misc_a;misc_step<=1;state<=MISC_READ;end
     else begin
      write_pending<=1;write_address<=output_address;
      write_data<=opcode==2?quantize({{32{pool_max[31]}},pool_max},shift1):opcode==4?quantize(aligned_a+aligned_b,align_shift):quantize({{32{misc_a[31]}},misc_a},shift1);
      state<=NEXT_OUTPUT;
     end
    end
    NEXT_OUTPUT:begin
     if(oc==co-1)begin
      oc<=0;
      if(ox==ow-1)begin
       ox<=0;
       if(oy==oh-1)begin
        operation_done<=1;
        if(operation_index==PROGRAM_DEPTH-1)begin state<=IDLE;done<=1;end
        else begin operation_index<=operation_index+1'b1;state<=CONFIG_WAIT;end
       end else begin oy<=oy+1'b1;state<=INIT;end
      end else begin ox<=ox+1'b1;state<=INIT;end
     end else begin oc<=oc+1'b1;state<=INIT;end
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
