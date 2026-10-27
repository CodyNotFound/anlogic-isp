// Frozen bilinear templates: 0,+/-6,+/-12,+/-18 deg, optional two scale banks.
// Optional bounded recovery retries only the last local neighborhood; K4 reselects.
(* dsp_style="no" *) module vision_sad_tracker #(
 parameter WIDTH=160,HEIGHT=90,RADIUS=8,MIN_TEXTURE=1024,MAX_SAD=6144,MIN_GAP=256,ROTATION_ENABLE=1,SCALE_ENABLE=0,RECOVERY_FRAMES=0,EXTERNAL_FRAME=0
)(input wire clk,rst_n,reseed,frame_start,sample_valid,frame_end,input wire [7:0] gray,
 output reg result_valid,found,output reg [7:0] center_x,center_y,quality,
 output reg [17:0] best_sad,second_sad,output wire busy,output reg [31:0] compute_cycles,output wire [1:0] lost_stage,
 output wire shared_write_en,output wire [13:0] shared_write_addr,shared_read_addr,
 output wire [7:0] shared_write_data,input wire [7:0] shared_read_data);
 localparam IDLE=0,CAPTURE=1,INIT=2,WA=3,RA=4,WB=5,RB=6,DONE=7,NEXT=8,PEAK=9,PWAIT=10,PREAD=11,DECIDE=12,
 COORD=13,ADDR=14,W0=15,R0=16,W1=17,R1=18,W2=19,R2=20,W3=21,R3=22,STORE=23,SEEDED=24,REDPAIR=25,REDMID=26,REDROOT=27;
 localparam LANES=SCALE_ENABLE?9:(ROTATION_ENABLE?7:1);
 localparam PAIRS=SCALE_ENABLE?8:4,MIDS=SCALE_ENABLE?4:2;
 localparam LAST_BANK=LANES-1;
 reg [4:0] state;
 reg pending,point_b;
 reg [2:0] missed_frames;
 reg [13:0] capture_addr,read_addr,pixel_addr;
 (* ram_style="bram" *) reg [7:0] frame[0:WIDTH*HEIGHT-1];
 (* ram_style="bram" *) reg [17:0] scores[0:(2*RADIUS+1)*(2*RADIUS+1)-1];
 reg [7:0] frame_storage_q,a,idx,p0,p1,p2,seed_value;
 wire [7:0] frame_q=EXTERNAL_FRAME?shared_read_data:frame_storage_q;
 assign shared_write_en=EXTERNAL_FRAME&&state==CAPTURE&&sample_valid;
 assign shared_write_addr=capture_addr;assign shared_read_addr=read_addr;assign shared_write_data=gray;
 reg [3:0] bank,best_bank;
 reg [17:0] score_q,energy,best,second;
 reg [17:0] lane_sad[0:LANES-1],pair_score[0:PAIRS-1],mid_score[0:MIDS-1],root_score[0:1];
 reg [3:0] pair_bank[0:PAIRS-1],mid_bank[0:MIDS-1],root_bank[0:1];
 wire [LANES*10-1:0] lane_error;
 integer lane,j;
 reg [8:0] candidate_index,peak_index;
 reg [7:0] lx,rx,ty,by,cx,cy,bx,byy,px,py;
 reg signed [9:0] cosine,sine;
 reg signed [14:0] qx,qy;
 reg [3:0] fx,fy;
 wire signed [5:0] dx=$signed({2'b0,idx[3:0]})-6'sd8+(point_b?6'sd1:6'sd0);
 wire signed [5:0] dy=$signed({2'b0,idx[7:4]})-6'sd8;
 wire signed [15:0] xc=dx*cosine,ys=dy*sine,xs=dx*sine,yc=dy*cosine;
 wire signed [16:0] sx=$signed(WIDTH/2)+($signed(qx)>>>8),sy=$signed(HEIGHT/2)+($signed(qy)>>>8);
 wire signed [8:0] grad=$signed({1'b0,frame_q})-$signed({1'b0,a});
 wire signed [8:0] sg=$signed({1'b0,seed_value})-$signed({1'b0,a});
 wire [8:0] texture=sg[8]?-sg:sg;
 wire [17:0] final_score=SCALE_ENABLE?(root_score[0]<=root_score[1]?root_score[0]:root_score[1]):(mid_score[0]<=mid_score[1]?mid_score[0]:mid_score[1]);
 wire [3:0] final_bank=SCALE_ENABLE?(root_score[0]<=root_score[1]?root_bank[0]:root_bank[1]):(mid_score[0]<=mid_score[1]?mid_bank[0]:mid_bank[1]);
 wire far_peak=px+2<bx||bx+2<px||py+2<byy||byy+2<py;
 wire [18:0] gap={1'b0,second}-{1'b0,best};
 assign busy=state!=IDLE;
 assign lost_stage=0; // compatibility port; automatic reacquire is disabled
 genvar g;
 generate for(g=0;g<LANES;g=g+1)begin:g_template
  (* ram_style="bram" *) reg signed [8:0] mem[0:255];
  reg signed [8:0] q;
  wire signed [9:0] difference=$signed({grad[8],grad})-$signed({q[8],q});
  assign lane_error[g*10+:10]=difference[9]?-difference:difference;
  always @(posedge clk)begin
   q<=mem[idx];
   if(state==STORE&&point_b&&bank==g)mem[idx]<=sg;
  end
 end endgenerate
 always @*case(bank)
  1:begin cosine=255;sine=27;end 2:begin cosine=255;sine=-27;end
  3:begin cosine=250;sine=53;end 4:begin cosine=250;sine=-53;end
  5:begin cosine=243;sine=79;end 6:begin cosine=243;sine=-79;end
  7:begin cosine=224;sine=0;end 8:begin cosine=288;sine=0;end
  default:begin cosine=256;sine=0;end
 endcase
 function [7:0] bilinear;
 input [7:0] aa,bb,cc,dd;input [3:0] xx,yy;
 reg [12:0] top,bot;reg [17:0] total;
 begin top=aa*(5'd16-{1'b0,xx})+bb*xx;bot=cc*(5'd16-{1'b0,xx})+dd*xx;
 total=top*(5'd16-{1'b0,yy})+bot*yy+18'd128;bilinear=total[15:8];end
 endfunction
 always @(posedge clk)begin
  score_q<=scores[peak_index];
  if(state==DONE)scores[candidate_index]<=final_score;
 end
 generate if(!EXTERNAL_FRAME)begin: local_frame
  always @(posedge clk)begin
   frame_storage_q<=frame[read_addr];
   if(state==CAPTURE&&sample_valid)frame[capture_addr]<=gray;
  end
 end endgenerate
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;pending<=1;point_b<=0;missed_frames<=0;capture_addr<=0;read_addr<=0;pixel_addr<=0;
   a<=0;idx<=0;bank<=0;best_bank<=0;
   p0<=0;p1<=0;p2<=0;seed_value<=0;qx<=0;qy<=0;fx<=0;fy<=0;
   energy<=0;best<=0;second<=0;candidate_index<=0;peak_index<=0;
   for(lane=0;lane<LANES;lane=lane+1)lane_sad[lane]<=0;
   for(j=0;j<PAIRS;j=j+1)begin pair_score[j]<=0;pair_bank[j]<=0;end
   for(j=0;j<MIDS;j=j+1)begin mid_score[j]<=0;mid_bank[j]<=0;end
   for(j=0;j<2;j=j+1)begin root_score[j]<=0;root_bank[j]<=0;end
   lx<=0;rx<=0;ty<=0;by<=0;cx<=0;cy<=0;bx<=0;byy<=0;px<=0;py<=0;
   result_valid<=0;found<=0;center_x<=WIDTH/2;center_y<=HEIGHT/2;quality<=0;best_sad<=0;second_sad<=0;compute_cycles<=0;
  end else begin
   result_valid<=0;if(state>CAPTURE)compute_cycles<=compute_cycles+1'b1;
   if(reseed)begin state<=IDLE;pending<=1;found<=0;quality<=0;missed_frames<=0;end
   else case(state)
    IDLE:if(frame_start&&(pending||found||(missed_frames!=0 && missed_frames<=RECOVERY_FRAMES)))begin state<=CAPTURE;capture_addr<=0;end
    CAPTURE:if(sample_valid)begin
     if(capture_addr==WIDTH*HEIGHT-1&&frame_end)begin state<=INIT;compute_cycles<=0;end else capture_addr<=capture_addr+1'b1;
    end
    INIT:begin
     for(lane=0;lane<LANES;lane=lane+1)lane_sad[lane]<=0;
     energy<=0;idx<=0;bank<=0;candidate_index<=0;best<=18'h3ffff;second<=18'h3ffff;
     if(pending)begin point_b<=0;state<=COORD;end else begin
      lx<=center_x<8+RADIUS?0:center_x-8-RADIUS;rx<=center_x+RADIUS>WIDTH-9?WIDTH-17:center_x-8+RADIUS;
      ty<=center_y<8+RADIUS?0:center_y-8-RADIUS;by<=center_y+RADIUS>HEIGHT-8?HEIGHT-16:center_y-8+RADIUS;
      cx<=center_x<8+RADIUS?0:center_x-8-RADIUS;cy<=center_y<8+RADIUS?0:center_y-8-RADIUS;
      pixel_addr<=(center_y<8+RADIUS?0:center_y-8-RADIUS)*WIDTH+(center_x<8+RADIUS?0:center_x-8-RADIUS);
      read_addr<=(center_y<8+RADIUS?0:center_y-8-RADIUS)*WIDTH+(center_x<8+RADIUS?0:center_x-8-RADIUS);state<=WA;
     end
    end
    COORD:begin qx<=xc+ys;qy<=yc-xs;state<=ADDR;end
    ADDR:begin read_addr<=sy*WIDTH+sx;fx<=qx[7:4];fy<=qy[7:4];state<=W0;end
    W0:state<=R0;
    R0:begin p0<=frame_q;read_addr<=read_addr+1'b1;state<=W1;end
    W1:state<=R1;
    R1:begin p1<=frame_q;read_addr<=read_addr+WIDTH-1;state<=W2;end
    W2:state<=R2;
    R2:begin p2<=frame_q;read_addr<=read_addr+1'b1;state<=W3;end
    W3:state<=R3;
    R3:begin seed_value<=bilinear(p0,p1,p2,frame_q,fx,fy);state<=STORE;end
    STORE:begin
     if(!point_b)begin a<=seed_value;point_b<=1;state<=COORD;end else begin
      if(bank==0)energy<=energy+texture;point_b<=0;
      if(idx!=255)begin idx<=idx+1'b1;state<=COORD;end
      else if(bank!=LAST_BANK)begin bank<=bank+1'b1;idx<=0;state<=COORD;end else state<=SEEDED;
     end
    end
    SEEDED:begin pending<=0;found<=energy>=MIN_TEXTURE;quality<=energy>=MIN_TEXTURE?255:0;
     center_x<=WIDTH/2;center_y<=HEIGHT/2;best_sad<=0;second_sad<=0;result_valid<=1;state<=IDLE;end
    WA:state<=RA;
    RA:begin a<=frame_q;read_addr<=pixel_addr+1'b1;state<=WB;end
    WB:state<=RB;
    RB:begin
     for(lane=0;lane<LANES;lane=lane+1)lane_sad[lane]<=lane_sad[lane]+lane_error[lane*10+:10];
     if(idx==255)state<=REDPAIR;else begin
     idx<=idx+1'b1;pixel_addr<=pixel_addr+(idx[3:0]==15?WIDTH-15:1);read_addr<=pixel_addr+(idx[3:0]==15?WIDTH-15:1);state<=WA;
    end end
    REDPAIR:begin
     for(j=0;j<PAIRS;j=j+1)begin
      if(2*j+1<LANES)begin
       pair_score[j]<=lane_sad[2*j]<=lane_sad[2*j+1]?lane_sad[2*j]:lane_sad[2*j+1];
       pair_bank[j]<=lane_sad[2*j]<=lane_sad[2*j+1]?2*j:2*j+1;
      end else if(2*j<LANES)begin pair_score[j]<=lane_sad[2*j];pair_bank[j]<=2*j;end
      else begin pair_score[j]<=18'h3ffff;pair_bank[j]<=0;end
     end
     state<=REDMID;
    end
    REDMID:begin
     for(j=0;j<MIDS;j=j+1)begin
      mid_score[j]<=pair_score[2*j]<=pair_score[2*j+1]?pair_score[2*j]:pair_score[2*j+1];
      mid_bank[j]<=pair_score[2*j]<=pair_score[2*j+1]?pair_bank[2*j]:pair_bank[2*j+1];
     end state<=SCALE_ENABLE?REDROOT:DONE;
    end
    REDROOT:begin
     for(j=0;j<2;j=j+1)begin
      root_score[j]<=mid_score[2*j]<=mid_score[2*j+1]?mid_score[2*j]:mid_score[2*j+1];
      root_bank[j]<=mid_score[2*j]<=mid_score[2*j+1]?mid_bank[2*j]:mid_bank[2*j+1];
     end state<=DONE;
    end
    DONE:begin
     if(final_score<best)begin best<=final_score;bx<=cx;byy<=cy;best_bank<=final_bank;end state<=NEXT;
    end
    NEXT:begin
     if(cx==rx&&cy==by)state<=PEAK;else begin
      candidate_index<=candidate_index+1'b1;idx<=0;
      for(lane=0;lane<LANES;lane=lane+1)lane_sad[lane]<=0;
      if(cx==rx)begin cx<=lx;cy<=cy+1'b1;pixel_addr<=(cy+1'b1)*WIDTH+lx;read_addr<=(cy+1'b1)*WIDTH+lx;end
      else begin cx<=cx+1'b1;pixel_addr<=cy*WIDTH+cx+1'b1;read_addr<=cy*WIDTH+cx+1'b1;end state<=WA;
     end
    end
    PEAK:begin peak_index<=0;px<=lx;py<=ty;state<=PWAIT;end
    PWAIT:state<=PREAD;
    PREAD:begin
     if(far_peak&&score_q<second)second<=score_q;
     if(peak_index==candidate_index)state<=DECIDE;else begin peak_index<=peak_index+1'b1;
      if(px==rx)begin px<=lx;py<=py+1'b1;end else px<=px+1'b1;state<=PWAIT;end
    end
    DECIDE:begin
     found<=best<=MAX_SAD&&second>=best+MIN_GAP;
     quality<=(best>MAX_SAD||second<best+MIN_GAP)?0:(gap>4095?255:gap[11:4]);
     if(best<=MAX_SAD&&second>=best+MIN_GAP)begin center_x<=bx+8;center_y<=byy+8;missed_frames<=0;end
     else if(RECOVERY_FRAMES!=0 && missed_frames<=RECOVERY_FRAMES)missed_frames<=missed_frames+1'b1;
     best_sad<=best;second_sad<=second;result_valid<=1;state<=IDLE;
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
