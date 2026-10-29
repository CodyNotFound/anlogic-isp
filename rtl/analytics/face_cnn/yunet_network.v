// Complete 55-operation position-only YuNet integer program, shared four-DSP MAC.
// Alias-aware 64KiB arena, three original source rows and a per-pixel cache.
// Four interleaved banks permit four channel reads per convolution beat.
// Depthwise/single-channel layers use lane0, avoiding multi-port RAM replication.
module yunet_network #(
 parameter integer DUAL_CLOCK=0,CHANNEL_PREFETCH=1,PIXEL_PREFETCH=1,PROGRAM_DEPTH=55,WEIGHT_DEPTH=12373,BIAS_DEPTH=1524,
 parameter PROGRAM_FILE="rtl/analytics/face_cnn/program.hex",
 parameter W0_FILE="rtl/analytics/face_cnn/weights0.hex",W1_FILE="rtl/analytics/face_cnn/weights1.hex",
 parameter W2_FILE="rtl/analytics/face_cnn/weights2.hex",W3_FILE="rtl/analytics/face_cnn/weights3.hex",
 parameter BIAS_FILE="rtl/analytics/face_cnn/bias.hex",SHIFT_FILE="rtl/analytics/face_cnn/shift.hex"
)(input wire clk,io_clk,rst_n,start,
 input wire load_valid,input wire [16:0] load_address,input wire [7:0] load_data,
 input wire [16:0] read_address,output wire [7:0] read_data,
 output wire busy,output reg done,operation_done,output reg [5:0] operation_index,
 output reg [31:0] cycles,output wire [31:0] read_word);
 localparam IDLE=0,CONFIG_WAIT=1,CONFIG=2,INIT=3,META=4,DOT_START=5,
  CONV_READ=6,CONV_WAIT=7,CONV_FEED=8,CONV_RESULT=9,NEXT_OUTPUT=10,
  MISC_READ=11,MISC_WAIT=12,MISC_EVAL=13,ROW_PREP=14,ROW_READ=15,ROW_WAIT=16,ROW_WRITE=17,
  PIXEL_READ=18,PIXEL_WAIT=19,PIXEL_WRITE=20,MISC_QUANT=21,ROW_SLOT=22,ROW_DECIDE=23,
  DW_BIAS=24,DW_DRAIN=25,PW_BIAS=26;
 reg beat_prefetched;reg [4:0] state;assign busy=state!=IDLE;
 (* ram_style="bram" *) reg [7:0] fm0[0:16383],fm1[0:16383],fm2[0:16383],fm3[0:16383];
 (* ram_style="bram" *) reg [7:0] cache0[0:1919];
 (* ram_style="bram" *) reg [7:0] cache1[0:1919],cache2[0:1919],cache3[0:1919];
 reg [12:0] cache_read_address;reg prefetch_sel_q;
 (* ram_style="dram" *) reg [7:0] pixel0[0:15],pixel1[0:15],pixel2[0:15],pixel3[0:15];
 reg [7:0] cq0,cq1,cq2,cq3,pq0,pq1,pq2,pq3;
 (* ram_style="bram" *) reg signed [7:0] wm0[0:WEIGHT_DEPTH-1],wm1[0:WEIGHT_DEPTH-1],wm2[0:WEIGHT_DEPTH-1],wm3[0:WEIGHT_DEPTH-1];
 (* ram_style="dram" *) reg [159:0] program_rom[0:PROGRAM_DEPTH-1];
 (* ram_style="dram" *) reg [15:0] biases[0:BIAS_DEPTH-1];
 `include "yunet_rom_unpack.vh"
 (* ram_style="dram" *) reg [MODEL_SHIFT_BITS-1:0] shifts[0:BIAS_DEPTH-1];
 initial begin
  $readmemh(PROGRAM_FILE,program_rom);$readmemh(W0_FILE,wm0);$readmemh(W1_FILE,wm1);$readmemh(W2_FILE,wm2);$readmemh(W3_FILE,wm3);
  $readmemh({BIAS_FILE,".lo16"},biases);$readmemh({SHIFT_FILE,".packed"},shifts);
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
 reg [2:0] cshift;reg [16:0] operand_address;
 (* syn_preserve=1 *) reg [16:0] weight_address;
 reg pad_q;reg [1:0] a_bank_q,w_bank_q;
 reg [7:0] aq0,aq1,aq2,aq3;reg signed [7:0] wq0,wq1,wq2,wq3;
 reg signed [31:0] bias_q;reg signed [6:0] shift_q;
 reg signed [7:0] misc_temp;reg signed [9:0] misc_sum_q;reg misc_half_q;
 reg write_pending;reg [16:0] write_address;
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
 // Full 8x8 products map to spare DSPs; all exported dimensions fit 8 bits.
 function [15:0] geometry_product;
 input [7:0] a,b;
 begin geometry_product=a*b;end
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
 reg [16:0] conv_pixel_r,misc_pixel_r,fill_pixel_r,pixel_pixel_r,out_pixel_r;
 reg [16:0] conv_base_r,misc_base_r,fill_base_r,pixel_base_r,out_base_r;
 reg [7:0] misc_y_r,misc_x_r;
 reg [1:0] cache_slot_r;reg [7:0] cache_x_r;reg [2:0] cache_cs_r;reg [12:0] cache_base_r;
 reg [1:0] address_wait;
 reg signed [9:0] prep_y_q;reg [1:0] prep_slot_q;
 wire [16:0] conv_fast=conv_base_r|{10'd0,channel};
 wire [6:0] next_channel=channel+7'd4;
 wire [16:0] conv_prefetch=conv_base_r|{10'd0,next_channel};

 // Depthwise lanes: four adjacent output channels share one beat. The lane
 // products drain into four network-side accumulators, so the four physical
 // multipliers stay fully occupied without extra DSPs or bank replication.
 reg dw_active,dw_relu_q,dw_stop_q;reg [2:0] co_shift_q;reg [1:0] dw_load_step;reg [2:0] dw_drain;
 // check_yunet_dw_bounds.py proves every prefix for the installed ROM.
 reg signed [17:0] dw_bias0,dw_bias1,dw_bias2,dw_bias3,dw_sum0,dw_sum1,dw_sum2,dw_sum3;
 reg signed [6:0] dw_shift0,dw_shift1,dw_shift2,dw_shift3;
 reg signed [7:0] dw_val0,dw_val1,dw_val2,dw_val3;
 reg [3:0] write_we;reg [7:0] write_data0,write_data1,write_data2,write_data3;
 // Pointwise pairs: a second MAC consumes the same activations against the
 // adjacent output channel's weights, read through the weight banks' second
 // port (address = primary + ci, no relayout of the weight ROM).
 reg misc_vector;reg signed [7:0] misc_temp1,misc_temp2,misc_temp3;
 reg signed [9:0] misc_sum1,misc_sum2,misc_sum3;
 reg pw8_active;reg signed [31:0] pw_bias_q;reg signed [6:0] pw_shift_q;reg [10:0] dw_bias_addr,bias_addr_q;
 // All convolution variants use one metadata read address. The normal MAC
 // reloads its primary bias in META before DOT_START; DW/PW setup owns this
 // port only while explicitly loading its additional channels.
 wire [10:0] metadata_address=(state==DW_BIAS||state==PW_BIAS)?dw_bias_addr:bias_addr_q;
 wire signed [31:0] metadata_bias=unpack_model_bias(metadata_address,biases[metadata_address]);
 wire signed [6:0] metadata_shift=unpack_model_shift(metadata_address,shifts[metadata_address]);
 reg [16:0] weight_address2;reg signed [7:0] wq0b,wq1b,wq2b,wq3b;
 wire [3:0] tap=kernel3?({2'b0,ky}<<1)+ky+kx:4'd0;
 // Depthwise ROM words hold [tap][oc]: four adjacent channels of one tap
 // occupy the four weight banks of a single word, matching the arena banks.
 wire [16:0] w_offset=depthwise ? (({14'b0,tap}<<co_shift_q)+{10'b0,oc}) :
    (((kernel3?(({10'b0,oc}<<3)+oc):{10'b0,oc})+tap)<<cshift)+ic;
 wire [16:0] conv_weight=weight_base+w_offset;
 reg [16:0] weight_row_r,weight_scale_r,weight_base_r,tap_scale_r,tap_base_r;
 wire [6:0] prefetched_ic=ic+7'd4;

 reg single_lane,one_beat;reg [6:0] last_channel;
 // Shared two-stage quantizer: select/round, then shift/clip.
 // This breaks the former channel-select -> add -> barrel -> clamp path.
 reg signed [18:0] dw_rounded;
 reg [4:0] dw_quant_shift_q;
 wire signed [17:0] dw_quant_sum=dw_drain==2?dw_sum0:dw_drain==3?dw_sum1:dw_drain==4?dw_sum2:dw_sum3;
 wire signed [6:0] dw_quant_shift=dw_drain==2?dw_shift0:dw_drain==3?dw_shift1:dw_drain==4?dw_shift2:dw_shift3;
 // For every signed 18-bit accumulator, a rounded right shift >=18 is zero.
 wire signed [18:0] dw_rounding=(dw_quant_shift==0||dw_quant_shift>=18)?19'sd0:(19'sd1<<(dw_quant_shift[4:0]-1'b1));
 wire signed [18:0] dw_shifted=dw_rounded>>>dw_quant_shift_q;
 wire signed [7:0] dw_quant_value=(dw_relu_q&&dw_shifted<0)?8'sd0:dw_shifted>127?8'sd127:dw_shifted< -128?-8'sd128:dw_shifted[7:0];
 wire last_ic=single_lane||dw_active||ic==last_channel;
 wire dw8_done=(dw_active||misc_vector)?oc+7'd4>=co:pw8_active?oc+7'd2>=co:oc==co-1;
 wire last_tap=last_ic&&(!kernel3||(kx==2&&ky==2));
 // Calculate the next kernel position during WAIT/FEED when the current
 // tap is already in RAM output registers. This hides address stages on
 // depthwise and other non-prefetched final channel beats.
 reg tap_early,tap_prefetched;
 wire look_ahead=one_beat&&kernel3&&!(kx==2&&ky==2)&&(state==CONV_WAIT||(state==CONV_FEED&&tap_early));
 wire [1:0] address_kx=look_ahead?(kx==2?2'd0:kx+1'b1):kx;
 wire [1:0] address_ky=look_ahead?(kx==2?ky+1'b1:ky):ky;
 wire signed [9:0] pipeline_x=$signed({2'b0,ox}<<stride2)+$signed({8'b0,address_kx})-$signed({9'b0,pad1});
 wire signed [9:0] pipeline_y=$signed({2'b0,oy}<<stride2)+$signed({8'b0,address_ky})-$signed({9'b0,pad1});
 wire [3:0] pipeline_tap=kernel3?({2'b0,address_ky}<<1)+address_ky+address_kx:4'd0;
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
 wire [12:0] cache_addr=padding?13'd0:cache_base_r|{6'd0,channel};
 wire row_filling=state==ROW_READ||state==ROW_WAIT||state==ROW_WRITE;
 wire pixel_filling=state==PIXEL_READ||state==PIXEL_WAIT||state==PIXEL_WRITE;
 wire [16:0] fill_address=feature_index(src_base,fill_y,8'd0,iw,7'd0,cshift)+fill_offset;
 wire [16:0] pixel_address=feature_index(src_base,oy,ox,iw,7'd0,cshift)+pixel_offset;
 wire [16:0] calculated_address=row_filling?fill_base_r+fill_offset:pixel_filling?pixel_base_r|{10'd0,pixel_offset}:
  opcode==1?(in_place?17'd0:conv_fast):misc_base_r|{10'd0,oc};
 wire [16:0] memory_address=DUAL_CLOCK?operand_address:busy?operand_address:read_address;
 wire use_row=opcode==1&&in_place&&kernel3;
 wire use_pixel=opcode==1&&in_place&&!kernel3;
 wire [7:0] a0=use_row?cq0:use_pixel?pq0:aq0,a1=use_row?cq1:use_pixel?pq1:aq1;
 wire [7:0] a2=use_row?cq2:use_pixel?pq2:aq2,a3=use_row?cq3:use_pixel?pq3:aq3;
 wire [7:0] selected_a=a_bank_q==0?a0:a_bank_q==1?a1:a_bank_q==2?a2:a3;
 wire [7:0] selected_memory_a=a_bank_q==0?aq0:a_bank_q==1?aq1:a_bank_q==2?aq2:aq3;
 wire signed [7:0] selected_w=w_bank_q==0?wq0:w_bank_q==1?wq1:w_bank_q==2?wq2:wq3;
 wire signed [8:0] first_a=input_unsigned?$signed({1'b0,selected_a}):$signed({selected_a[7],selected_a});
 wire solo=single_lane&&!dw_active;
 wire [35:0] dot_a=pad_q?36'd0:solo?{27'd0,first_a}:
  {input_unsigned?{1'b0,a3}:{a3[7],a3},input_unsigned?{1'b0,a2}:{a2[7],a2},input_unsigned?{1'b0,a1}:{a1[7],a1},input_unsigned?{1'b0,a0}:{a0[7],a0}};
 wire [31:0] dot_w=solo?{24'd0,selected_w}:{wq3,wq2,wq1,wq0};
 wire dot_ready,dot_in_ready,dot_valid;wire signed [31:0] dot_acc;wire signed [7:0] dot_value;
 wire dw_p_valid;wire signed [16:0] dw_p0,dw_p1,dw_p2,dw_p3;
 wire dot_ready2,dot_in_ready2,dot_valid2;wire signed [31:0] dot_acc2;wire signed [7:0] dot_value2;
 yunet_dot4 #(.MODEL_SHIFT(1),.FAST_PIPELINE(1),.ACC_BITS(20)) mac2(.clk(clk),.rst_n(rst_n),.start(state==DOT_START&&pw8_active),.bias(pw_bias_q),.shift(pw_shift_q),.relu(relu),.ready(dot_ready2),
  .in_valid(state==CONV_FEED&&pw8_active),.in_ready(dot_in_ready2),.in_last(last_tap),
  .activations(dot_a),.weights({wq3b,wq2b,wq1b,wq0b}),.dw_mode(1'b0),.dw_stop(1'b0),
  .dw_p_valid(),.dw_p0(),.dw_p1(),.dw_p2(),.dw_p3(),
  .out_valid(dot_valid2),.out_ready(state==CONV_RESULT),.accumulator(dot_acc2),.value(dot_value2));
 yunet_dot4 #(.MODEL_SHIFT(1),.FAST_PIPELINE(1),.ACC_BITS(20)) mac(.clk(clk),.rst_n(rst_n),.start(state==DOT_START||(state==DW_BIAS&&dw_load_step==3&&dot_ready)),.bias(bias_q),.shift(shift_q),.relu(relu),.ready(dot_ready),
  .in_valid(state==CONV_FEED),.in_ready(dot_in_ready),.in_last(last_tap&&!dw_active),
  .activations(dot_a),.weights(dot_w),.dw_mode(dw_active),.dw_stop(dw_stop_q),
  .dw_p_valid(dw_p_valid),.dw_p0(dw_p0),.dw_p1(dw_p1),.dw_p2(dw_p2),.dw_p3(dw_p3),
  .out_valid(dot_valid),.out_ready(state==CONV_RESULT),.accumulator(dot_acc),.value(dot_value));
 reg [1:0] debug_bank;
 reg [7:0] io_q0,io_q1,io_q2,io_q3;
 wire [16:0] core_port_address=write_pending?write_address:operand_address;
 wire [16:0] io_port_address=load_valid?load_address:read_address;
 wire [31:0] io_word={io_q3,io_q2,io_q1,io_q0};
 assign read_word=DUAL_CLOCK?io_word:{aq3,aq2,aq1,aq0};
 assign read_data=DUAL_CLOCK?(debug_bank==0?io_q0:debug_bank==1?io_q1:debug_bank==2?io_q2:io_q3):
  (debug_bank==0?aq0:debug_bank==1?aq1:debug_bank==2?aq2:aq3);
 wire prefetch_beat=state==CONV_FEED&&dot_in_ready&&
  ((PIXEL_PREFETCH&&use_pixel&&!last_tap)||(CHANNEL_PREFETCH&&!last_ic));
 // Spatial address arithmetic is pipelined; channel prefetch cadence is retained.
 // Read states wait only when geometry or the source tensor changes.
 // All stages use ordinary single-cycle timing constraints.
 always @(posedge clk)begin
  conv_pixel_r<={1'b0,geometry_product(pipeline_y[7:0],iw)}+pipeline_x[7:0];
  misc_y_r<=misc_y;misc_x_r<=misc_x;
  misc_pixel_r<={1'b0,geometry_product(misc_y_r,iw)}+misc_x_r;
  fill_pixel_r<={1'b0,geometry_product(fill_y,iw)};
  pixel_pixel_r<={1'b0,geometry_product(oy,iw)}+ox;
  out_pixel_r<={1'b0,geometry_product(oy,ow)}+ox;
  weight_row_r<=depthwise?{10'd0,oc}:(kernel3?({10'd0,oc}<<3)+oc:{10'd0,oc});
  weight_scale_r<=depthwise?weight_row_r:weight_row_r<<cshift;
  weight_base_r<=weight_base+weight_scale_r;
  tap_scale_r<=depthwise?({13'd0,pipeline_tap}<<co_shift_q):({13'd0,pipeline_tap}<<cshift);
  tap_base_r<=weight_base_r+tap_scale_r;

  conv_base_r<=src_base+(conv_pixel_r<<cshift);
  misc_base_r<=misc_base+(misc_pixel_r<<cshift);
  fill_base_r<=src_base+(fill_pixel_r<<cshift);
  pixel_base_r<=src_base+(pixel_pixel_r<<cshift);
  out_base_r<=dst_base+(out_pixel_r<<channel_shift(co));
  cache_slot_r<=modulo3(pipeline_y[7:0]);cache_x_r<=pipeline_x[7:0];cache_cs_r<=cshift;
  cache_base_r<=({11'd0,cache_slot_r}<<11)+({11'd0,cache_slot_r}<<9)+({5'd0,cache_x_r}<<cache_cs_r);
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin address_wait<=0;tap_early<=0;tap_prefetched<=0;end
  else begin
   if(state==CONV_WAIT)tap_early<=one_beat&&kernel3&&!(kx==2&&ky==2);
   else if(state==CONV_READ)tap_early<=0;
   if(state==CONV_FEED&&dot_in_ready)tap_prefetched<=tap_early&&kernel3&&!(kx==2&&ky==2);
   else if(state==CONV_READ)tap_prefetched<=0;
  if((state==ROW_READ&&fill_offset==0)||(state==PIXEL_READ&&pixel_offset==0)||state==MISC_READ||(state==CONV_READ&&!beat_prefetched))begin
   if(address_wait!=(state==MISC_READ?2'd3:2'd2))address_wait<=address_wait+1'b1;
  end else address_wait<=0;
  end
 end
 always @(posedge clk)begin
  operand_address<=CHANNEL_PREFETCH&&prefetch_beat&&!in_place?conv_prefetch:calculated_address;
  // 1x1 in-place pixels already have a one-cycle cache read. Prefetch the
  // next four weights when a beat is accepted, avoiding a redundant WAIT.
  weight_address<=tap_base_r+(prefetch_beat?{10'd0,prefetched_ic}:{10'd0,ic});
 weight_address2<=tap_base_r+(prefetch_beat?{10'd0,prefetched_ic}:{10'd0,ic})+{10'd0,ci};
  instruction<=program_rom[operation_index];bias_addr_q<=bias_base+oc;
 bias_q<=metadata_bias;shift_q<=metadata_shift;
  wq0<=wm0[weight_address[15:2]];wq1<=wm1[weight_address[15:2]];wq2<=wm2[weight_address[15:2]];wq3<=wm3[weight_address[15:2]];
 wq0b<=wm0[weight_address2[15:2]];wq1b<=wm1[weight_address2[15:2]];wq2b<=wm2[weight_address2[15:2]];wq3b<=wm3[weight_address2[15:2]];
  // READ captures the address; WAIT reads RAM; FEED consumes its registered data.
  prefetch_sel_q<=CHANNEL_PREFETCH&&prefetch_beat&&use_row;
  cache_read_address<=padding?13'd0:cache_base_r|{6'd0,prefetch_sel_q?next_channel:channel};
  cq0<=cache0[cache_read_address[12:2]];cq1<=cache1[cache_read_address[12:2]];cq2<=cache2[cache_read_address[12:2]];cq3<=cache3[cache_read_address[12:2]];
  pq0<=pixel0[ic[5:2]];pq1<=pixel1[ic[5:2]];pq2<=pixel2[ic[5:2]];pq3<=pixel3[ic[5:2]];
  if(state==ROW_WRITE)begin cache0[fill_cache_addr[12:2]]<=aq0;cache1[fill_cache_addr[12:2]]<=aq1;cache2[fill_cache_addr[12:2]]<=aq2;cache3[fill_cache_addr[12:2]]<=aq3;end
  if(state==PIXEL_WRITE)begin pixel0[pixel_offset[5:2]]<=aq0;pixel1[pixel_offset[5:2]]<=aq1;pixel2[pixel_offset[5:2]]<=aq2;pixel3[pixel_offset[5:2]]<=aq3;end
 end
 // Port A belongs to compute; port B belongs to snapshot/head/template I/O.
 // The wrapper grants writes only while idle. No pixel or head bus crosses
 // through synchronizer flops, and each read retains one-clock latency.
 generate if(DUAL_CLOCK)begin: g_dual_arena
  always @(posedge clk)begin
   if(write_we[0])fm0[core_port_address[15:2]]<=write_data0;
   else aq0<=fm0[core_port_address[15:2]];
   if(write_we[1])fm1[core_port_address[15:2]]<=write_data1;
   else aq1<=fm1[core_port_address[15:2]];
   if(write_we[2])fm2[core_port_address[15:2]]<=write_data2;
   else aq2<=fm2[core_port_address[15:2]];
   if(write_we[3])fm3[core_port_address[15:2]]<=write_data3;
   else aq3<=fm3[core_port_address[15:2]];
  end
  always @(posedge io_clk)begin
   debug_bank<=read_address[1:0];
   if(load_valid&&load_address[1:0]==2'd0)fm0[io_port_address[15:2]]<=load_data;
   else io_q0<=fm0[io_port_address[15:2]];
   if(load_valid&&load_address[1:0]==2'd1)fm1[io_port_address[15:2]]<=load_data;
   else io_q1<=fm1[io_port_address[15:2]];
   if(load_valid&&load_address[1:0]==2'd2)fm2[io_port_address[15:2]]<=load_data;
   else io_q2<=fm2[io_port_address[15:2]];
   if(load_valid&&load_address[1:0]==2'd3)fm3[io_port_address[15:2]]<=load_data;
   else io_q3<=fm3[io_port_address[15:2]];
  end
 end else begin: g_single_arena
  always @(posedge clk)begin
   aq0<=fm0[memory_address[15:2]];aq1<=fm1[memory_address[15:2]];aq2<=fm2[memory_address[15:2]];aq3<=fm3[memory_address[15:2]];
  debug_bank<=read_address[1:0];
  if(!busy&&load_valid)begin
   case(load_address[1:0])0:fm0[load_address[15:2]]<=load_data;1:fm1[load_address[15:2]]<=load_data;2:fm2[load_address[15:2]]<=load_data;3:fm3[load_address[15:2]]<=load_data;endcase
  end else if(write_pending)begin
   if(write_we[0])fm0[write_address[15:2]]<=write_data0;
   if(write_we[1])fm1[write_address[15:2]]<=write_data1;
   if(write_we[2])fm2[write_address[15:2]]<=write_data2;
   if(write_we[3])fm3[write_address[15:2]]<=write_data3;
  end
  end
 end endgenerate
 function signed [7:0] quantize_misc;
 input signed [9:0] v;input half;reg signed [10:0] q;
 begin q={{1{v[9]}},v};if(half)q=(q+11'sd1)>>>1;quantize_misc=q>127?8'sd127:q< -128?-8'sd128:q[7:0];end
 endfunction
 wire signed [7:0] misc_a=$signed(selected_memory_a);
 wire signed [7:0] pool_max=misc_step==0||misc_a>misc_temp?misc_a:misc_temp;
 // The fixed exported graph has zero shifts for pool/resize and shifts 0/1
 // for Add. The exporter checks this contract; no 64-bit variable barrel
 // shifter is needed on a BRAM-read -> output-write timing path.
 // Every arena read already returns four adjacent channels. Pool/Resize/Add
 // can consume the full word without additional RAM ports or DSPs.
 function signed [9:0] vector_add;
 input signed [7:0] first,second;input half,first_shift,second_shift;
 reg signed [9:0] aa,bb;
 begin aa={{2{first[7]}},first};bb={{2{second[7]}},second};
 if(half&&!first_shift)aa=aa<<<1;
 if(half&&!second_shift)bb=bb<<<1;
 vector_add=aa+bb;end endfunction
 wire signed [7:0] pool_vec0=(misc_step==0||$signed(aq0)>misc_temp)?$signed(aq0):misc_temp;
 wire signed [7:0] pool_vec1=(misc_step==0||$signed(aq1)>misc_temp1)?$signed(aq1):misc_temp1;
 wire signed [7:0] pool_vec2=(misc_step==0||$signed(aq2)>misc_temp2)?$signed(aq2):misc_temp2;
 wire signed [7:0] pool_vec3=(misc_step==0||$signed(aq3)>misc_temp3)?$signed(aq3):misc_temp3;
 wire align_half=shift1[0]||shift2[0];
 wire signed [9:0] extended_a={{2{misc_temp[7]}},misc_temp},extended_b={{2{misc_a[7]}},misc_a};
 wire signed [9:0] aligned_a=align_half&&!shift1[0]?extended_a<<<1:extended_a;
 wire signed [9:0] aligned_b=align_half&&!shift2[0]?extended_b<<<1:extended_b;
 wire [16:0] output_address=out_base_r|{10'd0,oc};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   prep_y_q<=0;prep_slot_q<=0;single_lane<=0;one_beat<=0;last_channel<=0;
   beat_prefetched<=0;state<=IDLE;done<=0;operation_done<=0;operation_index<=0;cycles<=0;
   opcode<=0;src_base<=0;src2_base<=0;dst_base<=0;iw<=0;ih<=0;ow<=0;oh<=0;ci<=0;co<=0;
   kernel3<=0;stride2<=0;pad1<=0;depthwise<=0;relu<=0;input_unsigned<=0;weight_base<=0;bias_base<=0;shift1<=0;shift2<=0;
   in_place<=0;reverse_order<=0;row_ready<=0;pixel_ready<=0;row_valid<=0;prep_row<=0;fill_slot<=0;fill_y<=0;fill_offset<=0;pixel_offset<=0;
   ox<=0;oy<=0;oc<=0;ic<=0;kx<=0;ky<=0;misc_step<=0;cshift<=0;pad_q<=0;a_bank_q<=0;w_bank_q<=0;
   misc_temp<=0;misc_sum_q<=0;misc_half_q<=0;write_pending<=0;write_address<=0;write_we<=0;
   write_data0<=0;write_data1<=0;write_data2<=0;write_data3<=0;
   dw_active<=0;dw_relu_q<=0;dw_stop_q<=0;co_shift_q<=0;dw_load_step<=0;dw_drain<=0;dw_rounded<=0;dw_quant_shift_q<=0;
   misc_vector<=0;misc_temp1<=0;misc_temp2<=0;misc_temp3<=0;misc_sum1<=0;misc_sum2<=0;misc_sum3<=0;
   pw8_active<=0;pw_bias_q<=0;pw_shift_q<=0;dw_bias_addr<=0;
   dw_bias0<=0;dw_bias1<=0;dw_bias2<=0;dw_bias3<=0;dw_sum0<=0;dw_sum1<=0;dw_sum2<=0;dw_sum3<=0;
   dw_shift0<=0;dw_shift1<=0;dw_shift2<=0;dw_shift3<=0;dw_val0<=0;dw_val1<=0;dw_val2<=0;dw_val3<=0;
  end else begin
   done<=0;operation_done<=0;write_pending<=0;write_we<=0;dw_stop_q<=0;
   if(dw_p_valid)begin
    dw_sum0<=dw_sum0+$signed({dw_p0[16],dw_p0});dw_sum1<=dw_sum1+$signed({dw_p1[16],dw_p1});
    dw_sum2<=dw_sum2+$signed({dw_p2[16],dw_p2});dw_sum3<=dw_sum3+$signed({dw_p3[16],dw_p3});
   end
   if(busy)cycles<=cycles+1'b1;
   if(state==CONV_READ)beat_prefetched<=0;else if(state==CONV_FEED&&dot_in_ready)beat_prefetched<=!last_ic;
   case(state)
    IDLE:if(start)begin operation_index<=0;cycles<=0;state<=CONFIG_WAIT;end
    CONFIG_WAIT:state<=CONFIG;
    CONFIG:begin
     single_lane<=instruction[93:87]==1;
     one_beat<=instruction[104]||instruction[93:87]<=4;last_channel<=instruction[93:87]-7'd4;
     dw_active<=instruction[104];dw_relu_q<=instruction[105];
     misc_vector<=instruction[3:0]>=2&&instruction[3:0]<=4&&instruction[100:94]>=4&&
      instruction[95:94]==0&&instruction[93:87]==instruction[100:94]&&
      instruction[5:4]==0&&instruction[39:38]==0&&(instruction[3:0]!=4||instruction[22:21]==0);
     pw8_active<=instruction[3:0]==1&&!instruction[101]&&!instruction[104]&&instruction[93:87]>=7'd16&&instruction[100:94]>=7'd2;
     case(instruction[100:94])7'd4:co_shift_q<=3'd2;7'd16:co_shift_q<=3'd4;7'd32:co_shift_q<=3'd5;7'd64:co_shift_q<=3'd6;default:co_shift_q<=3'd0;endcase
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
     else if(opcode==1&&dw_active)begin dw_load_step<=0;dw_bias_addr<=bias_base+oc;state<=DW_BIAS;end
     else if(opcode==1&&pw8_active)begin dw_bias_addr<=bias_base+oc+7'd1;state<=PW_BIAS;end
     else state<=opcode==1?META:MISC_READ;
    end
    ROW_PREP:begin
     if(prep_row==3)begin row_ready<=1;state<=INIT;end
     else begin prep_y_q<=prep_y;state<=ROW_SLOT;end
    end
    ROW_SLOT:begin prep_slot_q<=modulo3(prep_y_q[7:0]);state<=ROW_DECIDE;end
    ROW_DECIDE:begin
     if(prep_y_q<0||prep_y_q>=$signed({2'b0,ih})||(row_valid[prep_slot_q]&&row_tag[prep_slot_q]==prep_y_q[7:0]))begin prep_row<=prep_row+1'b1;state<=ROW_PREP;end
     else begin fill_slot<=prep_slot_q;fill_y<=prep_y_q[7:0];fill_offset<=0;state<=ROW_READ;end
    end
    ROW_READ:if(fill_offset!=0||address_wait==2)state<=ROW_WAIT;
    ROW_WAIT:state<=ROW_WRITE;
    ROW_WRITE:begin
     if({1'b0,fill_offset}+13'd4>=row_bytes)begin row_valid[fill_slot]<=1;row_tag[fill_slot]<=fill_y;prep_row<=prep_row+1'b1;state<=ROW_PREP;end
     else begin fill_offset<=fill_offset+12'd4;state<=ROW_READ;end
    end
    PIXEL_READ:if(pixel_offset!=0||address_wait==2)state<=PIXEL_WAIT;
    PIXEL_WAIT:state<=PIXEL_WRITE;
    PIXEL_WRITE:begin
     if(pixel_offset+7'd4>=ci)begin pixel_ready<=1;state<=INIT;end
     else begin pixel_offset<=pixel_offset+7'd4;state<=PIXEL_READ;end
    end
    DW_BIAS:begin
     // One DRAM port: the address was precomputed at INIT and now just
     // increments, keeping the DRAM->unpack->register path short.
     case(dw_load_step)
      0:begin dw_bias0<=metadata_bias;dw_shift0<=metadata_shift;end
      1:begin dw_bias1<=metadata_bias;dw_shift1<=metadata_shift;end
      2:begin dw_bias2<=metadata_bias;dw_shift2<=metadata_shift;end
      3:begin dw_bias3<=metadata_bias;dw_shift3<=metadata_shift;end
     endcase
     dw_bias_addr<=dw_bias_addr+1'b1;
     if(dw_load_step==3)begin
      if(dot_ready)begin
       dw_sum0<=dw_bias0;dw_sum1<=dw_bias1;dw_sum2<=dw_bias2;dw_sum3<=metadata_bias;
       state<=CONV_READ;
      end else dw_bias_addr<=dw_bias_addr;
     end else dw_load_step<=dw_load_step+1'b1;
    end
    META:begin
     if(dw_active)begin
      dw_sum0<=dw_bias0;dw_sum1<=dw_bias1;dw_sum2<=dw_bias2;dw_sum3<=dw_bias3;
     end
     state<=DOT_START;
    end
    DOT_START:if(dot_ready)state<=CONV_READ;
    CONV_READ:if(tap_prefetched||beat_prefetched||address_wait==2)begin pad_q<=padding;a_bank_q<=conv_addr[1:0];w_bank_q<=conv_weight[1:0];state<=((PIXEL_PREFETCH&&use_pixel)||(CHANNEL_PREFETCH&&beat_prefetched))?CONV_FEED:CONV_WAIT;end
    CONV_WAIT:state<=CONV_FEED;
    CONV_FEED:if(dot_in_ready)begin
     if(last_tap)begin dw_drain<=0;state<=dw_active?DW_DRAIN:CONV_RESULT;end
     else begin
      if(last_ic)begin ic<=0;if(kx==2)begin kx<=0;ky<=ky+1'b1;end else kx<=kx+1'b1;end
      else ic<=ic+7'd4;
      state<=CONV_READ;
     end
    end
    CONV_RESULT:if(dot_valid&&(!pw8_active||dot_valid2))begin
     write_pending<=1;write_address<=output_address;
     if(pw8_active)begin
      write_we<=(4'b0001<<output_address[1:0])|(4'b0001<<((output_address[1:0]==2'd3)?2'd0:output_address[1:0]+1'b1));
      case(output_address[1:0])
       0:begin write_data0<=dot_value;write_data1<=dot_value2;write_data2<=dot_value;write_data3<=dot_value2;end
       1:begin write_data0<=dot_value;write_data1<=dot_value;write_data2<=dot_value2;write_data3<=dot_value2;end
       2:begin write_data0<=dot_value2;write_data1<=dot_value;write_data2<=dot_value;write_data3<=dot_value2;end
       3:begin write_data0<=dot_value2;write_data1<=dot_value2;write_data2<=dot_value;write_data3<=dot_value;end
      endcase
     end else begin
      write_we<=4'b0001<<output_address[1:0];
      write_data0<=dot_value;write_data1<=dot_value;write_data2<=dot_value;write_data3<=dot_value;
     end
     state<=NEXT_OUTPUT;end
    DW_DRAIN:begin
     if(dw_drain<6)dw_drain<=dw_drain+1'b1;
     if(dw_drain>=2&&dw_drain<=5)begin
      dw_rounded<=dw_quant_shift>=18?19'sd0:$signed({dw_quant_sum[17],dw_quant_sum})+dw_rounding;
      dw_quant_shift_q<=dw_quant_shift>=18?5'd0:dw_quant_shift[4:0];
     end
     case(dw_drain)
      3:dw_val0<=dw_quant_value;
      4:dw_val1<=dw_quant_value;
      5:dw_val2<=dw_quant_value;
      6:begin
       write_pending<=1;write_we<=4'b1111;write_address<=output_address;
       write_data0<=dw_val0;write_data1<=dw_val1;
       write_data2<=dw_val2;write_data3<=dw_quant_value;
       dw_stop_q<=1;state<=NEXT_OUTPUT;
      end
     endcase
    end
    PW_BIAS:begin
     pw_bias_q<=metadata_bias;
     pw_shift_q<=metadata_shift;
     state<=META;
    end
    MISC_READ:if(address_wait==3)begin a_bank_q<=misc_addr[1:0];state<=MISC_WAIT;end
    MISC_WAIT:state<=MISC_EVAL;
    MISC_EVAL:begin
     if(misc_vector)begin
      if(opcode==2&&misc_step!=3)begin
       misc_temp<=pool_vec0;
       misc_temp1<=pool_vec1;
       misc_temp2<=pool_vec2;
       misc_temp3<=pool_vec3;
       misc_step<=misc_step+1'b1;state<=MISC_READ;
      end else if(opcode==4&&misc_step==0)begin
       misc_temp<=aq0;
       misc_temp1<=aq1;
       misc_temp2<=aq2;
       misc_temp3<=aq3;
       misc_step<=1;state<=MISC_READ;
      end else begin
       misc_sum_q<=opcode==2?{{2{pool_vec0[7]}},pool_vec0}:opcode==4?vector_add(misc_temp,$signed(aq0),align_half,shift1[0],shift2[0]):{{2{aq0[7]}},aq0};
       misc_sum1<=opcode==2?{{2{pool_vec1[7]}},pool_vec1}:opcode==4?vector_add(misc_temp1,$signed(aq1),align_half,shift1[0],shift2[0]):{{2{aq1[7]}},aq1};
       misc_sum2<=opcode==2?{{2{pool_vec2[7]}},pool_vec2}:opcode==4?vector_add(misc_temp2,$signed(aq2),align_half,shift1[0],shift2[0]):{{2{aq2[7]}},aq2};
       misc_sum3<=opcode==2?{{2{pool_vec3[7]}},pool_vec3}:opcode==4?vector_add(misc_temp3,$signed(aq3),align_half,shift1[0],shift2[0]):{{2{aq3[7]}},aq3};
       misc_half_q<=opcode==4&&align_half;state<=MISC_QUANT;
      end
     end else begin
     if(opcode==2&&misc_step!=3)begin misc_temp<=pool_max;misc_step<=misc_step+1'b1;state<=MISC_READ;end
     else if(opcode==4&&misc_step==0)begin misc_temp<=misc_a;misc_step<=1;state<=MISC_READ;end
     else begin
      misc_sum_q<=opcode==2?{{2{pool_max[7]}},pool_max}:opcode==4?aligned_a+aligned_b:extended_b;
      misc_half_q<=opcode==4&&align_half;
      state<=MISC_QUANT;
     end
     end
    end
    MISC_QUANT:begin
     write_pending<=1;write_we<=misc_vector?4'b1111:4'b0001<<output_address[1:0];
     write_data0<=quantize_misc(misc_sum_q,misc_half_q);write_data1<=misc_vector?quantize_misc(misc_sum1,misc_half_q):quantize_misc(misc_sum_q,misc_half_q);
     write_data2<=misc_vector?quantize_misc(misc_sum2,misc_half_q):quantize_misc(misc_sum_q,misc_half_q);write_data3<=misc_vector?quantize_misc(misc_sum3,misc_half_q):quantize_misc(misc_sum_q,misc_half_q);
     write_address<=output_address;state<=NEXT_OUTPUT;
    end
    NEXT_OUTPUT:begin
     if(dw8_done)begin
      oc<=0;pixel_ready<=0;
      if(reverse_order?ox==0:ox==ow-1)begin
       ox<=reverse_order?ow-1'b1:8'd0;row_ready<=0;
       if(reverse_order?oy==0:oy==oh-1)begin
        operation_done<=1;
        if(operation_index==PROGRAM_DEPTH-1)begin state<=IDLE;done<=1;end
        else begin operation_index<=operation_index+1'b1;state<=CONFIG_WAIT;end
       end else begin oy<=reverse_order?oy-1'b1:oy+1'b1;state<=INIT;end
      end else begin ox<=reverse_order?ox-1'b1:ox+1'b1;state<=INIT;end
     end else begin oc<=(dw_active||misc_vector)?oc+7'd4:pw8_active?oc+7'd2:oc+1'b1;state<=INIT;end
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
