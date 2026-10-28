// Fixed-camera block-luma frame difference. Previous pixels use idle CNN RAM.
// Sparse noise: adjacent-change support + density + two-frame confirmation.
(* dsp_style="no" *) module vision_motion_diff #(
 parameter WIDTH=160,HEIGHT=90,DIFF_TH=12,MIN_CHANGED=8,MIN_PAIRS=6,MAX_JUMP=32
)(input wire clk,rst_n,enable,reseed,suppress,frame_start,sample_valid,frame_end,frame_error,
 input wire [7:0] sample_x,sample_y,gray,
 output reg result_valid,found,initialized,output reg [2:0] status,
 output reg [7:0] box_x,box_y,box_w,box_h,center_x,center_y,
 output reg [14:0] changed_pixels,output wire [31:0] compute_cycles,
 output wire shared_write_en,output wire [14:0] shared_write_addr,shared_read_addr,
 output wire [7:0] shared_write_data,input wire [7:0] shared_read_data);
 localparam N=WIDTH*HEIGHT,CW=$clog2(WIDTH*HEIGHT*4+3);
 reg [CW-1:0] work_cycles;
 assign compute_cycles={{(32-CW){1'b0}},work_cycles};
 initial if(WIDTH>256||HEIGHT>256||N>=32768)$error("Motion geometry exceeds shared-byte arena or coordinate ports");
 localparam IDLE=0,CAPTURE=1,WAIT1=2,WAIT2=3,COMPARE=4,WRITE=5,FINAL=6,DECIDE=7;
 reg [2:0] state;reg suppressed_d,previous_candidate,left_changed,saved_last;
 reg [7:0] saved_gray,saved_x,saved_y,next_x,next_y,lo_x,hi_x,lo_y,hi_y,last_cx,last_cy;
 reg [14:0] index,saved_index,changed_count,pair_count;
 reg [7:0] candidate_w,candidate_h;reg [15:0] candidate_area;
 (* ram_style="dram" *) reg row_changed[0:WIDTH-1];
 wire [7:0] difference=saved_gray>shared_read_data?saved_gray-shared_read_data:shared_read_data-saved_gray;
 wire changed=initialized&&difference>=DIFF_TH;
 wire up_changed=saved_y!=0&&row_changed[saved_x];
 wire supported=changed&&((saved_x!=0&&left_changed)||up_changed);
 wire [7:0] support_x=(saved_x!=0&&left_changed)?saved_x-1'b1:saved_x;
 wire [7:0] support_y=up_changed?saved_y-1'b1:saved_y;
 wire [8:0] mid_x={1'b0,lo_x}+{1'b0,hi_x},mid_y={1'b0,lo_y}+{1'b0,hi_y};
 wire [7:0] proposed_x=mid_x[8:1],proposed_y=mid_y[8:1];
 wire [7:0] jump_x=proposed_x>last_cx?proposed_x-last_cx:last_cx-proposed_x;
 wire [7:0] jump_y=proposed_y>last_cy?proposed_y-last_cy:last_cy-proposed_y;
 wire candidate=pair_count>=MIN_PAIRS&&changed_count>=MIN_CHANGED&&({5'd0,changed_count}<<4)>={4'd0,candidate_area};
 assign shared_write_en=enable&&!suppress&&!frame_error&&!reseed&&state==WRITE;
 assign shared_write_addr=saved_index;assign shared_read_addr=saved_index;assign shared_write_data=saved_gray;
 always @(posedge clk)if(state==COMPARE)row_changed[saved_x]<=changed;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;result_valid<=0;found<=0;initialized<=0;status<=0;suppressed_d<=0;previous_candidate<=0;left_changed<=0;saved_last<=0;
   saved_gray<=0;saved_x<=0;saved_y<=0;next_x<=0;next_y<=0;lo_x<=0;hi_x<=0;lo_y<=0;hi_y<=0;last_cx<=0;last_cy<=0;
   index<=0;saved_index<=0;changed_count<=0;pair_count<=0;candidate_w<=0;candidate_h<=0;candidate_area<=0;
   box_x<=0;box_y<=0;box_w<=0;box_h<=0;center_x<=0;center_y<=0;changed_pixels<=0;work_cycles<=0;
  end else begin
   result_valid<=0;suppressed_d<=suppress;
   if(!enable||reseed)begin state<=IDLE;found<=0;initialized<=0;status<=0;previous_candidate<=0;end
   else if(suppress)begin state<=IDLE;found<=0;initialized<=0;status<=4;previous_candidate<=0;result_valid<=!suppressed_d;end
   else if(frame_error||(sample_valid&&state!=CAPTURE)||
           (sample_valid&&(sample_x!=next_x||sample_y!=next_y||frame_end!=(index==N-1))))begin
    state<=IDLE;found<=0;initialized<=0;status<=5;previous_candidate<=0;result_valid<=1;
   end else if(frame_start)begin
    if(state!=IDLE)begin initialized<=0;previous_candidate<=0;found<=0;end
    state<=CAPTURE;next_x<=0;next_y<=0;index<=0;changed_count<=0;pair_count<=0;left_changed<=0;
    lo_x<=WIDTH-1;hi_x<=0;lo_y<=HEIGHT-1;hi_y<=0;work_cycles<=0;
   end else begin
    if(state!=IDLE&&state!=CAPTURE)work_cycles<=work_cycles+1'b1;
    case(state)
     CAPTURE:if(sample_valid)begin
      saved_gray<=gray;saved_x<=sample_x;saved_y<=sample_y;saved_index<=index;saved_last<=frame_end;
      if(next_x==WIDTH-1)begin next_x<=0;next_y<=next_y+1'b1;end else next_x<=next_x+1'b1;
      index<=index+1'b1;state<=WAIT1;
     end
     WAIT1:state<=WAIT2;
     WAIT2:state<=COMPARE;
     COMPARE:begin
      left_changed<=changed;
      if(changed)changed_count<=changed_count+1'b1;
      if(supported)begin
       pair_count<=pair_count+1'b1;
       if(support_x<lo_x)lo_x<=support_x;if(saved_x>hi_x)hi_x<=saved_x;
       if(support_y<lo_y)lo_y<=support_y;if(saved_y>hi_y)hi_y<=saved_y;
      end
      state<=WRITE;
     end
     WRITE:state<=saved_last?FINAL:CAPTURE;
     FINAL:begin candidate_w<=hi_x-lo_x+1'b1;candidate_h<=hi_y-lo_y+1'b1;
      candidate_area<=(hi_x-lo_x+8'd1)*(hi_y-lo_y+8'd1);state<=DECIDE;end
     DECIDE:begin
      result_valid<=1;state<=IDLE;changed_pixels<=changed_count;found<=0;
      if(!initialized)begin initialized<=1;status<=0;previous_candidate<=0;end
      else if(changed_count>N*3/8)begin status<=3;previous_candidate<=0;end
      else if(candidate)begin
       previous_candidate<=1;last_cx<=proposed_x;last_cy<=proposed_y;
       if(previous_candidate&&jump_x<=MAX_JUMP&&jump_y<=MAX_JUMP)begin
        found<=1;status<=2;box_x<=lo_x;box_y<=lo_y;box_w<=candidate_w;box_h<=candidate_h;center_x<=proposed_x;center_y<=proposed_y;
       end else status<=1;
      end else begin status<=1;previous_candidate<=0;end
     end
     default:begin end
    endcase
   end
  end
 end
endmodule
