// Complete 55-operation position-only YuNet integer program, shared four-DSP MAC.
// Alias-aware 64KiB arena, three original source rows and a per-pixel cache.
// Four interleaved banks permit four channel reads per convolution beat.
// Depthwise/single-channel layers use lane0, avoiding multi-port RAM replication.
module yunet_network #(
 parameter integer CHANNEL_PREFETCH=1,PIXEL_PREFETCH=1,PROGRAM_DEPTH=55,WEIGHT_DEPTH=12373,BIAS_DEPTH=1524,
 parameter PROGRAM_FILE="rtl/analytics/face_cnn/program.hex",
 parameter W0_FILE="rtl/analytics/face_cnn/weights0.hex",W1_FILE="rtl/analytics/face_cnn/weights1.hex",
 parameter W2_FILE="rtl/analytics/face_cnn/weights2.hex",W3_FILE="rtl/analytics/face_cnn/weights3.hex",
 parameter BIAS_FILE="rtl/analytics/face_cnn/bias.hex",SHIFT_FILE="rtl/analytics/face_cnn/shift.hex"
)(input wire clk,rst_n,start,
 input wire load_valid,input wire [16:0] load_address,input wire [7:0] load_data,
 input wire [16:0] read_address,output wire [7:0] read_data,
 output wire busy,output reg done,operation_done,output reg [5:0] operation_index,
 output reg [31:0] cycles,output wire [31:0] read_word);
 localparam IDLE=0,CONFIG_WAIT=1,CONFIG=2,INIT=3,META=4,DOT_START=5,
  CONV_READ=6,CONV_WAIT=7,CONV_FEED=8,CONV_RESULT=9,NEXT_OUTPUT=10,
  MISC_READ=11,MISC_WAIT=12,MISC_EVAL=13,ROW_PREP=14,ROW_READ=15,ROW_WAIT=16,ROW_WRITE=17,
  PIXEL_READ=18,PIXEL_WAIT=19,PIXEL_WRITE=20,MISC_QUANT=21;
 reg beat_prefetched;reg [4:0] state;assign busy=state!=IDLE;
 (* ram_style="bram" *) reg [7:0] fm0[0:16383],fm1[0:16383],fm2[0:16383],fm3[0:16383];
 (* ram_style="dram" *) reg [7:0] cache0[0:1919];
 (* ram_style="bram" *) reg [7:0] cache1[0:1919],cache2[0:1919],cache3[0:1919];
 reg [12:0] cache_read_address;
 (* ram_style="dram" *) reg [7:0] pixel0[0:15],pixel1[0:15],pixel2[0:15],pixel3[0:15];
 reg [7:0] cq0,cq1,cq2,cq3,pq0,pq1,pq2,pq3;
 (* ram_style="bram" *) reg signed [7:0] wm0[0:WEIGHT_DEPTH-1],wm1[0:WEIGHT_DEPTH-1],wm2[0:WEIGHT_DEPTH-1],wm3[0:WEIGHT_DEPTH-1];
 (* ram_style="dram" *) reg [159:0] program_rom[0:PROGRAM_DEPTH-1];
 (* ram_style="dram" *) reg [15:0] biases[0:BIAS_DEPTH-1];
 (* ram_style="dram" *) reg [2:0] shifts[0:BIAS_DEPTH-1];
 `include "yunet_rom_unpack.vh"
 initial begin
  $readmemh(PROGRAM_FILE,program_rom);$readmemh(W0_FILE,wm0);$readmemh(W1_FILE,wm1);$readmemh(W2_FILE,wm2);$readmemh(W3_FILE,wm3);
  $readmemh({BIAS_FILE,".lo16"},biases);$readmemh({SHIFT_FILE,".code3"},shifts);
 end
 reg [159:0] instruction;reg [3:0] opcode;
 reg [16:0] src_base,src2_base,dst_base;
 reg [7:0] iw,ih,ow,oh;reg [6:0] ci,co;
 reg kernel3,stride2,pad1,depthwise,relu,input_unsigned;
 reg in_place,reverse_order,row_ready,pixel_ready;
 reg [2:0] row_valid;reg [7:0] row_tag[0:2];
 reg [1:0] prep_row,fill_slot;reg [7:0] fill_y;reg [11:0] fill_offset;reg [6:0] pixel_offset;
 reg [15:0] weight_base;reg [10:0] bias_base;reg signed [6:0] shift1,shift2;
 reg [7:0] ox,oy;reg [6:0] oc,ic;reg [1:0] kx,ky,misc_step;
 reg [2:0] cshift;reg [16:0] operand_address,weight_address;
 reg pad_q;reg [1:0] a_bank_q,w_bank_q;
 reg [7:0] aq0,aq1,aq2,aq3;reg signed [7:0] wq0,wq1,wq2,wq3;
 reg signed [31:0] bias_q;reg signed [6:0] shift_q;
 reg signed [7:0] misc_temp;reg signed [9:0] misc_sum_q;reg misc_half_q;
 reg write_pending;reg [16:0] write_address;reg [7:0] write_data;
 function [15:0] multiply8;
 input [7:0] a,b;reg [15:0] aa;
 // The generated 160x96 graph has only these six row widths. A general
 // eight-term shift/add multiplier created a 21-level path into the BRAM.
 // Each supported width has exactly two terms and needs one carry chain.
 begin aa={8'b0,a};case(b)
  8'd160:multiply8=(aa<<7)+(aa<<5);8'd80:multiply8=(aa<<6)+(aa<<4);
  8'd40:multiply8=(aa<<5)+(aa<<3);8'd20:multiply8=(aa<<4)+(aa<<2);
  8'd10:multiply8=(aa<<3)+(aa<<1);8'd5:multiply8=(aa<<2)+aa;
  default:multiply8=0;
 endcase end
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
 function [1:0] modulo3;
 input [7:0] a;reg [3:0] s;
 begin s={2'b0,a[1:0]}+{2'b0,a[3:2]}+{2'b0,a[5:4]}+{2'b0,a[7:6]};
 modulo3=s>=12?0:s>=9?s-9:s>=6?s-6:s>=3?s-3:s;end
 endfunction
 wire signed [9:0] prep_y=$signed({2'b0,oy}<<stride2)+$signed({8'b0,prep_row})-$signed({9'b0,pad1});
 wire [1:0] prep_slot=modulo3(prep_y[7:0]);
 wire [12:0] row_bytes={5'd0,iw}<<cshift;
 wire [12:0] fill_cache_addr=({11'd0,fill_slot}<<11)+({11'd0,fill_slot}<<9)+fill_offset;
 wire [1:0] sample_slot=modulo3(sample_y[7:0]);
 wire [12:0] cache_addr=padding?13'd0:({11'd0,sample_slot}<<11)+({11'd0,sample_slot}<<9)+({5'd0,sample_x[7:0]}<<cshift)+channel;
 wire row_filling=state==ROW_READ||state==ROW_WAIT||state==ROW_WRITE;
 wire pixel_filling=state==PIXEL_READ||state==PIXEL_WAIT||state==PIXEL_WRITE;
 wire [16:0] fill_address=feature_index(src_base,fill_y,8'd0,iw,7'd0,cshift)+fill_offset;
 wire [16:0] pixel_address=feature_index(src_base,oy,ox,iw,7'd0,cshift)+pixel_offset;
 wire [16:0] calculated_address=row_filling?fill_address:pixel_filling?pixel_address:
  opcode==1?(in_place?17'd0:conv_addr):misc_addr;
 wire [16:0] memory_address=busy?operand_address:read_address;
 wire use_row=opcode==1&&in_place&&kernel3;
 wire use_pixel=opcode==1&&in_place&&!kernel3;
 wire [7:0] a0=use_row?cq0:use_pixel?pq0:aq0,a1=use_row?cq1:use_pixel?pq1:aq1;
 wire [7:0] a2=use_row?cq2:use_pixel?pq2:aq2,a3=use_row?cq3:use_pixel?pq3:aq3;
 wire [7:0] selected_a=a_bank_q==0?a0:a_bank_q==1?a1:a_bank_q==2?a2:a3;
 wire [7:0] selected_memory_a=a_bank_q==0?aq0:a_bank_q==1?aq1:a_bank_q==2?aq2:aq3;
 wire signed [7:0] selected_w=w_bank_q==0?wq0:w_bank_q==1?wq1:w_bank_q==2?wq2:wq3;
 wire signed [8:0] first_a=input_unsigned?$signed({1'b0,selected_a}):$signed({selected_a[7],selected_a});
 wire [35:0] dot_a=pad_q?36'd0:single_lane?{27'd0,first_a}:
  {input_unsigned?{1'b0,a3}:{a3[7],a3},input_unsigned?{1'b0,a2}:{a2[7],a2},input_unsigned?{1'b0,a1}:{a1[7],a1},input_unsigned?{1'b0,a0}:{a0[7],a0}};
 wire [31:0] dot_w=single_lane?{24'd0,selected_w}:{wq3,wq2,wq1,wq0};
 wire dot_ready,dot_in_ready,dot_valid;wire signed [31:0] dot_acc;wire signed [7:0] dot_value;
 yunet_dot4 #(.MODEL_SHIFT(1)) mac(.clk(clk),.rst_n(rst_n),.start(state==DOT_START),.bias(bias_q),.shift(shift_q),.relu(relu),.ready(dot_ready),
  .in_valid(state==CONV_FEED),.in_ready(dot_in_ready),.in_last(last_tap),.activations(dot_a),.weights(dot_w),
  .out_valid(dot_valid),.out_ready(state==CONV_RESULT),.accumulator(dot_acc),.value(dot_value));
 reg [1:0] debug_bank;
 assign read_word={aq3,aq2,aq1,aq0};
 assign read_data=debug_bank==0?aq0:debug_bank==1?aq1:debug_bank==2?aq2:aq3;
 wire prefetch_beat=state==CONV_FEED&&dot_in_ready&&
  ((PIXEL_PREFETCH&&use_pixel&&!last_tap)||(CHANNEL_PREFETCH&&!last_ic));
 always @(posedge clk)begin
  operand_address<=CHANNEL_PREFETCH&&prefetch_beat&&!in_place?conv_addr+17'd4:calculated_address;
  // 1x1 in-place pixels already have a one-cycle cache read. Prefetch the
  // next four weights when a beat is accepted, avoiding a redundant WAIT.
  weight_address<=prefetch_beat?conv_weight+17'd4:conv_weight;
  instruction<=program_rom[operation_index];bias_q<=unpack_model_bias(bias_base+oc,biases[bias_base+oc]);shift_q<=unpack_model_shift(bias_base+oc,shifts[bias_base+oc]);
  aq0<=fm0[memory_address[15:2]];aq1<=fm1[memory_address[15:2]];aq2<=fm2[memory_address[15:2]];aq3<=fm3[memory_address[15:2]];
  wq0<=wm0[weight_address[15:2]];wq1<=wm1[weight_address[15:2]];wq2<=wm2[weight_address[15:2]];wq3<=wm3[weight_address[15:2]];
  // READ captures the address; WAIT reads RAM; FEED consumes its registered data.
  cache_read_address<=CHANNEL_PREFETCH&&prefetch_beat&&use_row?cache_addr+13'd4:cache_addr;
  cq0<=cache0[cache_read_address[12:2]];cq1<=cache1[cache_read_address[12:2]];cq2<=cache2[cache_read_address[12:2]];cq3<=cache3[cache_read_address[12:2]];
  pq0<=pixel0[ic[5:2]];pq1<=pixel1[ic[5:2]];pq2<=pixel2[ic[5:2]];pq3<=pixel3[ic[5:2]];
  if(state==ROW_WRITE)begin cache0[fill_cache_addr[12:2]]<=aq0;cache1[fill_cache_addr[12:2]]<=aq1;cache2[fill_cache_addr[12:2]]<=aq2;cache3[fill_cache_addr[12:2]]<=aq3;end
  if(state==PIXEL_WRITE)begin pixel0[pixel_offset[5:2]]<=aq0;pixel1[pixel_offset[5:2]]<=aq1;pixel2[pixel_offset[5:2]]<=aq2;pixel3[pixel_offset[5:2]]<=aq3;end
  debug_bank<=read_address[1:0];
  if(!busy&&load_valid)begin
   case(load_address[1:0])0:fm0[load_address[15:2]]<=load_data;1:fm1[load_address[15:2]]<=load_data;2:fm2[load_address[15:2]]<=load_data;3:fm3[load_address[15:2]]<=load_data;endcase
  end else if(write_pending)begin
   case(write_address[1:0])0:fm0[write_address[15:2]]<=write_data;1:fm1[write_address[15:2]]<=write_data;2:fm2[write_address[15:2]]<=write_data;3:fm3[write_address[15:2]]<=write_data;endcase
  end
 end
 function signed [7:0] quantize_misc;
 input signed [9:0] v;input half;reg signed [10:0] q;
 begin q={{1{v[9]}},v};if(half)q=(q+11'sd1)>>>1;quantize_misc=q>127?8'sd127:q< -128?-8'sd128:q[7:0];end
 endfunction
 wire signed [7:0] misc_a=$signed(selected_memory_a);
 wire signed [7:0] pool_max=misc_step==0||misc_a>misc_temp?misc_a:misc_temp;
 // The fixed exported graph has zero shifts for pool/resize and shifts 0/1
 // for Add. The exporter checks this contract; no 64-bit variable barrel
 // shifter is needed on a BRAM-read -> output-write timing path.
 wire align_half=shift1[0]||shift2[0];
 wire signed [9:0] extended_a={{2{misc_temp[7]}},misc_temp},extended_b={{2{misc_a[7]}},misc_a};
 wire signed [9:0] aligned_a=align_half&&!shift1[0]?extended_a<<<1:extended_a;
 wire signed [9:0] aligned_b=align_half&&!shift2[0]?extended_b<<<1:extended_b;
 wire [16:0] output_address=feature_index(dst_base,oy,ox,ow,oc,channel_shift(co));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   beat_prefetched<=0;state<=IDLE;done<=0;operation_done<=0;operation_index<=0;cycles<=0;
   opcode<=0;src_base<=0;src2_base<=0;dst_base<=0;iw<=0;ih<=0;ow<=0;oh<=0;ci<=0;co<=0;
   kernel3<=0;stride2<=0;pad1<=0;depthwise<=0;relu<=0;input_unsigned<=0;weight_base<=0;bias_base<=0;shift1<=0;shift2<=0;
   in_place<=0;reverse_order<=0;row_ready<=0;pixel_ready<=0;row_valid<=0;prep_row<=0;fill_slot<=0;fill_y<=0;fill_offset<=0;pixel_offset<=0;
   ox<=0;oy<=0;oc<=0;ic<=0;kx<=0;ky<=0;misc_step<=0;cshift<=0;pad_q<=0;a_bank_q<=0;w_bank_q<=0;
   misc_temp<=0;misc_sum_q<=0;misc_half_q<=0;write_pending<=0;write_address<=0;write_data<=0;
  end else begin
   done<=0;operation_done<=0;write_pending<=0;
   if(busy)cycles<=cycles+1'b1;
   if(state==CONV_READ)beat_prefetched<=0;else if(state==CONV_FEED&&dot_in_ready)beat_prefetched<=!last_ic;
   case(state)
    IDLE:if(start)begin operation_index<=0;cycles<=0;state<=CONFIG_WAIT;end
    CONFIG_WAIT:state<=CONFIG;
    CONFIG:begin
     opcode<=instruction[3:0];src_base<=instruction[20:4];src2_base<=instruction[37:21];dst_base<=instruction[54:38];
     iw<=instruction[62:55];ih<=instruction[70:63];ow<=instruction[78:71];oh<=instruction[86:79];ci<=instruction[93:87];co<=instruction[100:94];
     kernel3<=instruction[101];stride2<=instruction[102];pad1<=instruction[103];depthwise<=instruction[104];relu<=instruction[105];
     weight_base<=instruction[121:106];bias_base<=instruction[132:122];shift1<=instruction[139:133];shift2<=instruction[146:140];input_unsigned<=instruction[147];
     in_place<=instruction[148];reverse_order<=instruction[149];row_ready<=0;pixel_ready<=0;row_valid<=0;
     cshift<=channel_shift(instruction[93:87]);ox<=instruction[149]?instruction[78:71]-1'b1:8'd0;oy<=instruction[149]?instruction[86:79]-1'b1:8'd0;oc<=0;state<=INIT;
    end
    INIT:begin
     ic<=0;kx<=0;ky<=0;misc_step<=0;
     if(opcode==1&&in_place&&kernel3&&!row_ready)begin prep_row<=0;state<=ROW_PREP;end
     else if(opcode==1&&in_place&&!kernel3&&!pixel_ready)begin pixel_offset<=0;state<=PIXEL_READ;end
     else state<=opcode==1?META:MISC_READ;
    end
    ROW_PREP:begin
     if(prep_row==3)begin row_ready<=1;state<=INIT;end
     else if(prep_y<0||prep_y>=$signed({2'b0,ih})||(row_valid[prep_slot]&&row_tag[prep_slot]==prep_y[7:0]))prep_row<=prep_row+1'b1;
     else begin fill_slot<=prep_slot;fill_y<=prep_y[7:0];fill_offset<=0;state<=ROW_READ;end
    end
    ROW_READ:state<=ROW_WAIT;
    ROW_WAIT:state<=ROW_WRITE;
    ROW_WRITE:begin
     if({1'b0,fill_offset}+13'd4>=row_bytes)begin row_valid[fill_slot]<=1;row_tag[fill_slot]<=fill_y;prep_row<=prep_row+1'b1;state<=ROW_PREP;end
     else begin fill_offset<=fill_offset+12'd4;state<=ROW_READ;end
    end
    PIXEL_READ:state<=PIXEL_WAIT;
    PIXEL_WAIT:state<=PIXEL_WRITE;
    PIXEL_WRITE:begin
     if(pixel_offset+7'd4>=ci)begin pixel_ready<=1;state<=INIT;end
     else begin pixel_offset<=pixel_offset+7'd4;state<=PIXEL_READ;end
    end
    META:state<=DOT_START;
    DOT_START:if(dot_ready)state<=CONV_READ;
    CONV_READ:begin pad_q<=padding;a_bank_q<=conv_addr[1:0];w_bank_q<=conv_weight[1:0];state<=((PIXEL_PREFETCH&&use_pixel)||(CHANNEL_PREFETCH&&beat_prefetched))?CONV_FEED:CONV_WAIT;end
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
      misc_sum_q<=opcode==2?{{2{pool_max[7]}},pool_max}:opcode==4?aligned_a+aligned_b:extended_b;
      misc_half_q<=opcode==4&&align_half;
      state<=MISC_QUANT;
     end
    end
    MISC_QUANT:begin
     write_pending<=1;write_address<=output_address;write_data<=quantize_misc(misc_sum_q,misc_half_q);state<=NEXT_OUTPUT;
    end
    NEXT_OUTPUT:begin
     if(oc==co-1)begin
      oc<=0;pixel_ready<=0;
      if(reverse_order?ox==0:ox==ow-1)begin
       ox<=reverse_order?ow-1'b1:8'd0;row_ready<=0;
       if(reverse_order?oy==0:oy==oh-1)begin
        operation_done<=1;
        if(operation_index==PROGRAM_DEPTH-1)begin state<=IDLE;done<=1;end
        else begin operation_index<=operation_index+1'b1;state<=CONFIG_WAIT;end
       end else begin oy<=reverse_order?oy-1'b1:oy+1'b1;state<=INIT;end
      end else begin ox<=reverse_order?ox-1'b1:ox+1'b1;state<=INIT;end
     end else begin oc<=oc+1'b1;state<=INIT;end
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
