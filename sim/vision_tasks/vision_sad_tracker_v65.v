// Frozen bilinear templates: 0,+/-6,+/-12,+/-18 deg, optional two scale banks.
// Optional tiled full-frame reacquisition reuses the same bounded score arena.
// Recovery needs a stricter score and a second-frame local confirmation; K4 reselects.
(* dsp_style="no" *) module vision_sad_tracker_v65 #(
 parameter WIDTH=160,HEIGHT=90,RADIUS=8,MIN_TEXTURE=1024,MAX_SAD=6144,MIN_GAP=256,ROTATION_ENABLE=1,SCALE_ENABLE=0,RECOVERY_FRAMES=0,REACQUIRE_ENABLE=0,EXTERNAL_FRAME=0,EXTERNAL_TEMPLATES=0,EXTERNAL_SCORES=0
)(input wire clk,rst_n,reseed,frame_start,sample_valid,frame_end,input wire [7:0] gray,
 output reg result_valid,found,output reg [7:0] center_x,center_y,quality,
 output reg [17:0] best_sad,second_sad,output wire busy,output wire [31:0] compute_cycles,output wire [1:0] lost_stage,
 output wire shared_write_en,output wire [14:0] shared_write_addr,shared_read_addr,
 output wire [7:0] shared_write_data,input wire [7:0] shared_read_data,input wire [31:0] shared_read_word);
 localparam IDLE=0,CAPTURE=1,INIT=2,WA=3,RA=4,WB=5,RB=6,DONE=7,NEXT=8,PEAK=9,PWAIT=10,PREAD=11,DECIDE=12,
 COORD=13,ADDR=14,W0=15,R0=16,W1=17,R1=18,W2=19,R2=20,W3=21,R3=22,STORE=23,SEEDED=24,REDPAIR=25,REDMID=26,REDROOT=27,INTERP=28,TPL_WAIT=29,TPL_CAPTURE=30,TPL_ACCUM=31,TPL_WRITE_HI=32,SCORE_WRITE=33;
 localparam WORK_BITS=$clog2((2*RADIUS+1)*(2*RADIUS+1)*5000+100000);
 reg[WORK_BITS-1:0] work_count;assign compute_cycles=work_count;
 localparam LANES=SCALE_ENABLE?9:(ROTATION_ENABLE?7:1);
 localparam PAIRS=SCALE_ENABLE?8:4,MIDS=SCALE_ENABLE?4:2;
 localparam LAST_BANK=LANES-1;
 localparam SCORE_BASE=(WIDTH*HEIGHT+3)/4*4;
 localparam SCORE_BYTES=((2*RADIUS+1)*(2*RADIUS+1)*3+3)/4*4;
 localparam TEMPLATE_BASE=SCORE_BASE+SCORE_BYTES;
 localparam TEMPLATE_WORDS=(LANES+1)/2,TEMPLATE_STRIDE=TEMPLATE_WORDS*4;
 initial begin
  if((EXTERNAL_TEMPLATES||EXTERNAL_SCORES)&&!EXTERNAL_FRAME)$error("Shared template/score storage requires external frame");
  if(EXTERNAL_TEMPLATES&&TEMPLATE_BASE+256*TEMPLATE_STRIDE>32768)$error("Shared tracker arena exceeds address port");
 end
 reg [5:0] state;
 reg [2:0] template_word;
 reg [1:0] score_byte;
 reg [7:0] score_lo_byte,score_mid_byte;
 reg signed [8:0] search_gradient;
 reg pending,point_b;
 reg [2:0] missed_frames;
 reg recovering,verify_pending;
 reg [7:0] scan_x,scan_y,verify_x,verify_y;
 wire [7:0] search_x=verify_pending?verify_x:center_x;
 wire [7:0] search_y=verify_pending?verify_y:center_y;

 reg [13:0] capture_addr,read_addr,pixel_addr;
 (* ram_style="bram" *) reg [7:0] frame[0:WIDTH*HEIGHT-1];
 (* ram_style="dram" *) reg [17:0] scores[0:(2*RADIUS+1)*(2*RADIUS+1)-1];
 reg [7:0] frame_storage_q,a,idx,p0,p1,p2,seed_value;
 reg [11:0] seed_top,seed_bottom;
 // Horizontal interpolation is <=255*16=4080. Preserve the original single
 // final rounding; the extra INTERP clock only affects template acquisition.
 wire [7:0] frame_q=EXTERNAL_FRAME?shared_read_data:frame_storage_q;

 reg [3:0] bank,best_bank;
 reg [17:0] score_storage_q,energy,best,second;
 wire [17:0] score_q=EXTERNAL_SCORES?{shared_read_data[1:0],score_mid_byte,score_lo_byte}:score_storage_q;
 reg [17:0] lane_sad[0:LANES-1],pair_score[0:PAIRS-1],mid_score[0:MIDS-1],root_score[0:1];
 reg [3:0] pair_bank[0:PAIRS-1],mid_bank[0:MIDS-1],root_bank[0:1];
 wire [LANES*10-1:0] lane_error;
 integer lane,j;
 reg [8:0] candidate_index,peak_index;
 reg [7:0] lx,rx,ty,by,cx,cy,bx,byy,px,py;
 wire match_ok=best<=MAX_SAD&&second>=best+MIN_GAP;
 wire recovery_ok=match_ok&&best<=MAX_SAD/2;
 wire verify_near=bx+8<=verify_x+4&&verify_x<=bx+12&&byy+8<=verify_y+4&&verify_y<=byy+12;
 reg signed [14:0] qx,qy;
 reg [3:0] fx,fy;
 wire [16:0] seed_blend=seed_top*(5'd16-{1'b0,fy})+seed_bottom*fy+17'd128;
 wire signed [5:0] dx=$signed({2'b0,idx[3:0]})-6'sd8+(point_b?6'sd1:6'sd0);
 wire signed [5:0] dy=$signed({2'b0,idx[7:4]})-6'sd8;
 function signed [15:0] rotate_cos;
 input signed [5:0] d;input [3:0] b;reg signed [15:0] q;
 begin q={{10{d[5]}},d};case(b)
  1,2:rotate_cos=(q<<<8)-q;
  3,4:rotate_cos=(q<<<8)-(q<<<2)-(q<<<1);
  5,6:rotate_cos=(q<<<8)-(q<<<3)-(q<<<2)-q;
  7:rotate_cos=(q<<<8)-(q<<<5);
  8:rotate_cos=(q<<<8)+(q<<<5);
  default:rotate_cos=q<<<8;
 endcase end endfunction
 function signed [15:0] rotate_sin;
 input signed [5:0] d;input [3:0] b;reg signed [15:0] q,v;
 begin q={{10{d[5]}},d};case(b)
  1,2:v=(q<<<5)-(q<<<2)-q;
  3,4:v=(q<<<6)-(q<<<3)-(q<<<1)-q;
  5,6:v=(q<<<6)+(q<<<4)-q;
  default:v=0;
 endcase rotate_sin=(b==2||b==4||b==6)?-v:v;end endfunction
 wire signed [15:0] xc=rotate_cos(dx,bank),ys=rotate_sin(dy,bank),xs=rotate_sin(dx,bank),yc=rotate_cos(dy,bank);
 wire signed [16:0] sx=$signed(WIDTH/2)+($signed(qx)>>>8),sy=$signed(HEIGHT/2)+($signed(qy)>>>8);
 wire signed [8:0] grad=$signed({1'b0,frame_q})-$signed({1'b0,a});
 wire signed [8:0] scoring_gradient=EXTERNAL_TEMPLATES?search_gradient:grad;
 wire signed [8:0] sg=$signed({1'b0,seed_value})-$signed({1'b0,a});
 wire [8:0] texture=sg[8]?-sg:sg;
 wire [17:0] final_score=SCALE_ENABLE?(root_score[0]<=root_score[1]?root_score[0]:root_score[1]):(mid_score[0]<=mid_score[1]?mid_score[0]:mid_score[1]);
 wire [3:0] final_bank=SCALE_ENABLE?(root_score[0]<=root_score[1]?root_bank[0]:root_bank[1]):(mid_score[0]<=mid_score[1]?mid_bank[0]:mid_bank[1]);
 wire far_peak=px+2<bx||bx+2<px||py+2<byy||byy+2<py;
 wire [18:0] gap={1'b0,second}-{1'b0,best};
 // One byte write port, existing four-bank word read. Mode 12 exclusively
 // owns this arena; FACE reloads its full image before inference resumes.
 wire tpl_low=EXTERNAL_TEMPLATES&&state==STORE&&point_b;
 wire tpl_high=EXTERNAL_TEMPLATES&&state==TPL_WRITE_HI;
 wire score_first=EXTERNAL_SCORES&&state==DONE;
 wire score_more=EXTERNAL_SCORES&&state==SCORE_WRITE;
 wire tpl_read=EXTERNAL_TEMPLATES&&(state==TPL_WAIT||state==TPL_CAPTURE);
 wire score_read=EXTERNAL_SCORES&&(state==PEAK||state==PWAIT||state==PREAD);
 wire [14:0] template_row=TEMPLATE_BASE+idx*TEMPLATE_STRIDE;
 wire [14:0] template_write=template_row+({11'd0,bank}<<1)+tpl_high;
 wire [14:0] score_write=SCORE_BASE+({6'd0,candidate_index}<<1)+candidate_index+(score_first?2'd0:score_byte);
 wire [14:0] score_read_addr=SCORE_BASE+({6'd0,peak_index}<<1)+peak_index+score_byte;
 assign shared_write_en=(EXTERNAL_FRAME&&state==CAPTURE&&sample_valid)||tpl_low||tpl_high||score_first||score_more;
 assign shared_write_addr=(tpl_low||tpl_high)?template_write:(score_first||score_more)?score_write:{1'b0,capture_addr};
 assign shared_write_data=(tpl_low||tpl_high)?(tpl_high?{7'd0,sg[8]}:sg[7:0]):
  (score_first||score_more)?(score_first?final_score[7:0]:score_byte==1?final_score[15:8]:{6'd0,final_score[17:16]}):gray;
 assign shared_read_addr=tpl_read?template_row+({12'd0,template_word}<<2):score_read?score_read_addr:{1'b0,read_addr};
 assign busy=state!=IDLE;
 assign lost_stage=REACQUIRE_ENABLE&&recovering?(verify_pending?2'd1:2'd3):2'd0;
 genvar g;
 generate for(g=0;g<LANES;g=g+1)begin:g_template
  (* ram_style="dram" *) reg signed [8:0] mem[0:255];
  reg signed [8:0] local_q,shared_q;
  wire signed [8:0] q=EXTERNAL_TEMPLATES?shared_q:local_q;
  wire signed [9:0] difference=$signed({scoring_gradient[8],scoring_gradient})-$signed({q[8],q});
  assign lane_error[g*10+:10]=difference[9]?-difference:difference;
  always @(posedge clk)begin
   if(!EXTERNAL_TEMPLATES)begin
    local_q<=mem[idx];if(state==STORE&&point_b&&bank==g)mem[idx]<=sg;
   end else if(state==TPL_CAPTURE&&template_word==g/2)
    shared_q<=shared_read_word[(g%2)*16+:9];
  end
 end endgenerate
 function [7:0] bilinear;
 input [7:0] aa,bb,cc,dd;input [3:0] xx,yy;
 reg [12:0] top,bot;reg [17:0] total;
 begin top=aa*(5'd16-{1'b0,xx})+bb*xx;bot=cc*(5'd16-{1'b0,xx})+dd*xx;
 total=top*(5'd16-{1'b0,yy})+bot*yy+18'd128;bilinear=total[15:8];end
 endfunction
 generate if(!EXTERNAL_SCORES)begin: local_scores
  always @(posedge clk)begin
   score_storage_q<=scores[peak_index];if(state==DONE)scores[candidate_index]<=final_score;
  end
 end endgenerate
 generate if(!EXTERNAL_FRAME)begin: local_frame
  always @(posedge clk)begin
   frame_storage_q<=frame[read_addr];
   if(state==CAPTURE&&sample_valid)frame[capture_addr]<=gray;
  end
 end endgenerate
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;pending<=1;point_b<=0;missed_frames<=0;recovering<=0;verify_pending<=0;scan_x<=0;scan_y<=0;verify_x<=0;verify_y<=0;capture_addr<=0;read_addr<=0;pixel_addr<=0;
   a<=0;idx<=0;bank<=0;best_bank<=0;
   template_word<=0;score_byte<=0;score_lo_byte<=0;score_mid_byte<=0;search_gradient<=0;
   p0<=0;p1<=0;p2<=0;seed_value<=0;seed_top<=0;seed_bottom<=0;qx<=0;qy<=0;fx<=0;fy<=0;
   energy<=0;best<=0;second<=0;candidate_index<=0;peak_index<=0;
   for(lane=0;lane<LANES;lane=lane+1)lane_sad[lane]<=0;
   for(j=0;j<PAIRS;j=j+1)begin pair_score[j]<=0;pair_bank[j]<=0;end
   for(j=0;j<MIDS;j=j+1)begin mid_score[j]<=0;mid_bank[j]<=0;end
   for(j=0;j<2;j=j+1)begin root_score[j]<=0;root_bank[j]<=0;end
   lx<=0;rx<=0;ty<=0;by<=0;cx<=0;cy<=0;bx<=0;byy<=0;px<=0;py<=0;
   result_valid<=0;found<=0;center_x<=WIDTH/2;center_y<=HEIGHT/2;quality<=0;best_sad<=0;second_sad<=0;work_count<=0;
  end else begin
   result_valid<=0;if(state>CAPTURE)work_count<=work_count+1'b1;
   if(reseed)begin state<=IDLE;pending<=1;found<=0;quality<=0;missed_frames<=0;recovering<=0;verify_pending<=0;scan_x<=0;scan_y<=0;end
   else case(state)
    IDLE:if(frame_start&&(pending||found||(REACQUIRE_ENABLE&&recovering)||(missed_frames!=0 && missed_frames<=RECOVERY_FRAMES)))begin state<=CAPTURE;capture_addr<=0;end
    CAPTURE:if(sample_valid)begin
     if(capture_addr==WIDTH*HEIGHT-1&&frame_end)begin state<=INIT;work_count<=0;end else capture_addr<=capture_addr+1'b1;
    end
    INIT:begin
     for(lane=0;lane<LANES;lane=lane+1)lane_sad[lane]<=0;
     energy<=0;idx<=0;bank<=0;candidate_index<=0;best<=18'h3ffff;second<=18'h3ffff;
     if(pending)begin point_b<=0;state<=COORD;end else if(REACQUIRE_ENABLE&&recovering&&!verify_pending)begin
      lx<=scan_x;rx<=scan_x+2*RADIUS>WIDTH-17?WIDTH-17:scan_x+2*RADIUS;
      ty<=scan_y;by<=scan_y+2*RADIUS>HEIGHT-16?HEIGHT-16:scan_y+2*RADIUS;
      cx<=scan_x;cy<=scan_y;pixel_addr<=scan_y*WIDTH+scan_x;read_addr<=scan_y*WIDTH+scan_x;state<=WA;
     end else begin
      lx<=search_x<8+RADIUS?0:search_x-8-RADIUS;rx<=search_x+RADIUS>WIDTH-9?WIDTH-17:search_x-8+RADIUS;
      ty<=search_y<8+RADIUS?0:search_y-8-RADIUS;by<=search_y+RADIUS>HEIGHT-8?HEIGHT-16:search_y-8+RADIUS;
      cx<=search_x<8+RADIUS?0:search_x-8-RADIUS;cy<=search_y<8+RADIUS?0:search_y-8-RADIUS;
      pixel_addr<=(search_y<8+RADIUS?0:search_y-8-RADIUS)*WIDTH+(search_x<8+RADIUS?0:search_x-8-RADIUS);
      read_addr<=(search_y<8+RADIUS?0:search_y-8-RADIUS)*WIDTH+(search_x<8+RADIUS?0:search_x-8-RADIUS);state<=WA;
     end
    end
    COORD:begin qx<=xc+ys;qy<=yc-xs;state<=ADDR;end
    ADDR:begin read_addr<=sy*WIDTH+sx;fx<=qx[7:4];fy<=qy[7:4];state<=W0;end
    W0:state<=R0;
    R0:begin p0<=frame_q;read_addr<=read_addr+1'b1;state<=W1;end
    W1:state<=R1;
    R1:begin p1<=frame_q;seed_top<=p0*(5'd16-{1'b0,fx})+frame_q*fx;read_addr<=read_addr+WIDTH-1;state<=W2;end
    W2:state<=R2;
    R2:begin p2<=frame_q;read_addr<=read_addr+1'b1;state<=W3;end
    W3:state<=R3;
    R3:begin seed_bottom<=p2*(5'd16-{1'b0,fx})+frame_q*fx;state<=INTERP;end
    INTERP:begin seed_value<=seed_blend[15:8];state<=STORE;end
    STORE,TPL_WRITE_HI:begin
     if(state==STORE&&!point_b)begin a<=seed_value;point_b<=1;state<=COORD;end
     else if(state==STORE&&EXTERNAL_TEMPLATES)state<=TPL_WRITE_HI;
     else begin
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
    RB,TPL_ACCUM:begin
     if(state==RB&&EXTERNAL_TEMPLATES)begin search_gradient<=grad;template_word<=0;state<=TPL_WAIT;end
     else begin
      for(lane=0;lane<LANES;lane=lane+1)lane_sad[lane]<=lane_sad[lane]+lane_error[lane*10+:10];
      if(idx==255)state<=REDPAIR;else begin
       idx<=idx+1'b1;pixel_addr<=pixel_addr+(idx[3:0]==15?WIDTH-15:1);read_addr<=pixel_addr+(idx[3:0]==15?WIDTH-15:1);state<=WA;
      end
     end
    end
    TPL_WAIT:state<=TPL_CAPTURE;
    TPL_CAPTURE:begin
     if(template_word==TEMPLATE_WORDS-1)state<=TPL_ACCUM;
     else begin template_word<=template_word+1'b1;state<=TPL_WAIT;end
    end
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
     if(final_score<best)begin best<=final_score;bx<=cx;byy<=cy;best_bank<=final_bank;end
     if(EXTERNAL_SCORES)begin score_byte<=1;state<=SCORE_WRITE;end else state<=NEXT;
    end
    SCORE_WRITE:if(score_byte==2)state<=NEXT;else score_byte<=score_byte+1'b1;
    NEXT:begin
     if(cx==rx&&cy==by)state<=PEAK;else begin
      candidate_index<=candidate_index+1'b1;idx<=0;
      for(lane=0;lane<LANES;lane=lane+1)lane_sad[lane]<=0;
      if(cx==rx)begin cx<=lx;cy<=cy+1'b1;pixel_addr<=(cy+1'b1)*WIDTH+lx;read_addr<=(cy+1'b1)*WIDTH+lx;end
      else begin cx<=cx+1'b1;pixel_addr<=cy*WIDTH+cx+1'b1;read_addr<=cy*WIDTH+cx+1'b1;end state<=WA;
     end
    end
    PEAK:begin peak_index<=0;px<=lx;py<=ty;score_byte<=0;state<=PWAIT;end
    PWAIT:state<=PREAD;
    PREAD:begin
     if(EXTERNAL_SCORES&&score_byte!=2)begin
      if(score_byte==0)score_lo_byte<=shared_read_data;else score_mid_byte<=shared_read_data;
      score_byte<=score_byte+1'b1;state<=PWAIT;
     end else begin
      score_byte<=0;
      if(far_peak&&score_q<second)second<=score_q;
      if(peak_index==candidate_index)state<=DECIDE;else begin peak_index<=peak_index+1'b1;
       if(px==rx)begin px<=lx;py<=py+1'b1;end else px<=px+1'b1;state<=PWAIT;end
     end
    end
    DECIDE:begin
     found<=0;quality<=0;
     if(REACQUIRE_ENABLE&&recovering)begin
      if(recovery_ok&&(!verify_pending||verify_near))begin
       if(!verify_pending)begin verify_pending<=1;verify_x<=bx+8;verify_y<=byy+8;end
       else begin
        found<=1;recovering<=0;verify_pending<=0;missed_frames<=0;
        center_x<=bx+8;center_y<=byy+8;quality<=gap>4095?255:gap[11:4];
       end
      end else begin
       verify_pending<=0;
       if(scan_x+2*RADIUS>=WIDTH-17)begin
        scan_x<=0;scan_y<=scan_y+2*RADIUS>=HEIGHT-16?0:scan_y+2*RADIUS+1;
       end else scan_x<=scan_x+2*RADIUS+1;
      end
     end else if(match_ok)begin
      found<=1;center_x<=bx+8;center_y<=byy+8;missed_frames<=0;quality<=gap>4095?255:gap[11:4];
     end else begin
      if(REACQUIRE_ENABLE)begin recovering<=1;verify_pending<=0;scan_x<=0;scan_y<=0;end
      if(RECOVERY_FRAMES!=0&&missed_frames<=RECOVERY_FRAMES)missed_frames<=missed_frames+1'b1;
     end
     best_sad<=best;second_sad<=second;result_valid<=1;state<=IDLE;
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
