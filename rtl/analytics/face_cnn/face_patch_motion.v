// Local gradient matcher for sparse-detector frame-to-frame assistance.
// 576-byte ROI + frozen 64-byte patch; never accesses CNN activation RAM.
// Scale/pose changes are left to CNN. Ambiguity/loss stops updates.
module face_patch_motion #(parameter W=160,H=90,MAX_ERROR=1800,MIN_GAP=64)(
 input wire clk,rst_n,enable,seed_valid,frame_start,frame_end,frame_error,sample_valid,
 input wire [7:0] seed_x,seed_y,sample_x,sample_y,gray,
 output reg result_valid,found,output reg [7:0] center_x,center_y,
 output wire busy,output reg [31:0] compute_cycles,
 output reg [15:0] best_error,input wire adaptive_seed);
 localparam IDLE=0,CAPTURE=1,BEGIN_SEARCH=2,READ=3,WAIT_READ=4,ACCUM=5,NEXT=6,DECIDE=7,SEED_SELECT=8,SEED_READ=9,SEED_WAIT=10,SEED_STORE=11;
 reg [3:0] state;
 (* ram_style="dram" *) reg [7:0] roi[0:575];
 (* ram_style="dram" *) reg [7:0] tpl[0:63];
 reg pending,seeded,acquiring,use_adaptive_seed;
 reg [7:0] pending_x,pending_y,origin_x,origin_y;
 reg [4:0] cx,cy,bx,by;
 reg [5:0] pixel;
 reg [9:0] read_addr;
 reg [7:0] rq,tq,prev_r,prev_t;
 reg [15:0] score,best,second,energy;
 reg [9:0] captured;
 wire signed [8:0] dg_r=$signed({1'b0,rq})-$signed({1'b0,prev_r});
 wire signed [8:0] dg_t=$signed({1'b0,tq})-$signed({1'b0,prev_t});
 wire signed [9:0] delta=$signed(dg_r)-$signed(dg_t);
 wire [9:0] error=delta<0?-delta:delta;
 wire [15:0] required_gap=(best>>3)>MIN_GAP?(best>>3):MIN_GAP;
 wire [8:0] texture=dg_t<0?-dg_t:dg_t;
 wire [8:0] seed_texture=dg_r<0?-dg_r:dg_r;
 wire in_roi=sample_x>=origin_x&&sample_x<origin_x+24&&sample_y>=origin_y&&sample_y<origin_y+24;
 wire [7:0] dx=sample_x-origin_x,dy=sample_y-origin_y;
 wire [9:0] write_addr=({2'b0,dy}<<4)+({2'b0,dy}<<3)+dx;
 assign busy=state!=IDLE;
 function [7:0] clamp_x;input [7:0] v;begin clamp_x=v<12?12:v>W-12?W-12:v;end endfunction
 function [7:0] clamp_y;input [7:0] v;begin clamp_y=v<12?12:v>H-12?H-12:v;end endfunction
 always @(posedge clk)begin rq<=roi[read_addr];tq<=tpl[pixel];end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;pending<=0;seeded<=0;acquiring<=0;use_adaptive_seed<=0;pending_x<=0;pending_y<=0;
   origin_x<=0;origin_y<=0;cx<=0;cy<=0;bx<=0;by<=0;pixel<=0;read_addr<=0;
   prev_r<=0;prev_t<=0;score<=0;best<=0;second<=0;energy<=0;captured<=0;
   result_valid<=0;found<=0;center_x<=0;center_y<=0;compute_cycles<=0;best_error<=0;
  end else begin
   result_valid<=0;
   if(seed_valid)begin pending<=1;pending_x<=clamp_x(seed_x);pending_y<=clamp_y(seed_y);end
   if(state>=BEGIN_SEARCH)compute_cycles<=compute_cycles+1'b1;
   if(!enable||frame_error)begin state<=IDLE;found<=0;seeded<=0;if(!enable)pending<=0;end
   else if(frame_start&&state==CAPTURE)begin state<=IDLE;found<=0;seeded<=0;end
   else case(state)
    IDLE:if(frame_start&&(seed_valid||pending||seeded))begin
     acquiring<=seed_valid||pending;use_adaptive_seed<=adaptive_seed===1'b1;
     origin_x<=(seed_valid?clamp_x(seed_x):pending?pending_x:clamp_x(center_x))-12;
     origin_y<=(seed_valid?clamp_y(seed_y):pending?pending_y:clamp_y(center_y))-12;
     if(seed_valid||pending)begin center_x<=seed_valid?clamp_x(seed_x):pending_x;center_y<=seed_valid?clamp_y(seed_y):pending_y;pending<=0;end
     captured<=0;state<=CAPTURE;
    end
    CAPTURE:begin
     if(sample_valid&&in_roi)begin
      roi[write_addr]<=gray;captured<=captured+1'b1;
      if(acquiring&&dx>=8&&dx<16&&dy>=8&&dy<16)tpl[((dy-8)<<3)+(dx-8)]<=gray;
     end
     if(frame_end||(sample_valid&&in_roi&&captured==575))begin
      // Finish once the ROI is complete; malformed captures cannot be matched.
      if(captured+(sample_valid&&in_roi)!=576)begin state<=IDLE;seeded<=0;found<=0;end
      else if(acquiring&&!use_adaptive_seed)begin seeded<=1;state<=IDLE;found<=1;result_valid<=1;best_error<=0;compute_cycles<=0;end
      else begin state<=BEGIN_SEARCH;compute_cycles<=0;end
     end
    end
    BEGIN_SEARCH:begin cx<=0;cy<=0;bx<=8;by<=8;best<=acquiring?0:65535;second<=65535;score<=0;pixel<=0;energy<=0;state<=READ;end
    READ:begin read_addr<=((cy+{2'b0,pixel[5:3]})<<4)+((cy+{2'b0,pixel[5:3]})<<3)+cx+pixel[2:0];state<=WAIT_READ;end
    WAIT_READ:state<=ACCUM;
    ACCUM:begin
     prev_r<=rq;prev_t<=tq;
     if(pixel[2:0]!=0)begin score<=score+(acquiring?seed_texture:error);if(cx==0&&cy==0)energy<=energy+texture;end
     if(pixel==63)state<=NEXT;else begin pixel<=pixel+1'b1;state<=READ;end
    end
    NEXT:begin
     if(acquiring)begin if(score>best)begin best<=score;bx<=cx;by<=cy;end end
     else if(score<best)begin second<=best;best<=score;bx<=cx;by<=cy;end
     else if(score<second)second<=score;
     score<=0;pixel<=0;
     if(cx==16&&cy==16)state<=acquiring?SEED_SELECT:DECIDE;
     else begin if(cx==16)begin cx<=0;cy<=cy+(acquiring?5'd8:5'd1);end else cx<=cx+(acquiring?5'd8:5'd1);state<=READ;end
    end
    SEED_SELECT:begin cx<=bx;cy<=by;pixel<=0;state<=SEED_READ;end
    SEED_READ:begin read_addr<=((cy+{2'b0,pixel[5:3]})<<4)+((cy+{2'b0,pixel[5:3]})<<3)+cx+pixel[2:0];state<=SEED_WAIT;end
    SEED_WAIT:state<=SEED_STORE;
    SEED_STORE:begin
     tpl[pixel]<=rq;
     if(pixel==63)begin
      center_x<=origin_x+bx+4;center_y<=origin_y+by+4;acquiring<=0;
      seeded<=best>=400;found<=best>=400;result_valid<=1;best_error<=0;state<=IDLE;
     end else begin pixel<=pixel+1'b1;state<=SEED_READ;end
    end
    DECIDE:begin
     result_valid<=1;best_error<=best;
     found<=energy>=400&&best<=MAX_ERROR&&{1'b0,second}>={1'b0,best}+{1'b0,required_gap};
     if(energy>=400&&best<=MAX_ERROR&&{1'b0,second}>={1'b0,best}+{1'b0,required_gap})begin center_x<=origin_x+bx+4;center_y<=origin_y+by+4;end
     else seeded<=0; // Stop on ambiguity; CNN must reacquire.
     state<=IDLE;
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
