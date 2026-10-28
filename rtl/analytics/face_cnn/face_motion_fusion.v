// Sparse CNN + independent local matching. All ports share the pixel clock.
// Associate the CNN snapshot with the actual patch result from THAT frame.
// Correction = CNN(old) - patch(old); current = patch(now) + correction.
// No velocity prediction, interpolated boxes, or CNN arena sharing.
(* dsp_style="no" *) module face_motion_fusion #(
 parameter WIDTH=1280,HEIGHT=720,MAX_UNCONFIRMED_FRAMES=45,MAX_CORRECTION=64
)(input wire clk,rst_n,enable,clear,capture_start,cnn_valid,cnn_found,
 input wire [11:0] cnn_cx,cnn_cy,cnn_size,
 input wire frame_start,frame_end,frame_error,sample_valid,
 input wire [7:0] sample_x,sample_y,gray,
 output reg result_valid,found,output reg [11:0] box_x,box_y,box_size,center_x,center_y,
 output wire fast_source,output wire [31:0] match_cycles,
 output reg [15:0] accepted_corrections,rejected_corrections);
 wire active_reset=rst_n&&enable&&!clear;
 reg confirmed,live,seed_valid,awaiting_seed;
 reg [11:0] bootstrap_x,bootstrap_y;
 reg [7:0] seed_x,seed_y;
 reg [5:0] confirm_age;
 reg [15:0] frame_id,match_frame,capture_frame;
 reg [7:0] generation,capture_generation;
 reg capture_seen,capture_anchor;
 reg [7:0] capture_x,capture_y;
 reg signed [13:0] offset_x,offset_y,wanted_x,wanted_y;
 reg [11:0] wanted_size;
 wire patch_valid,patch_found,patch_busy;
 wire [7:0] patch_x,patch_y;
 wire [15:0] patch_error;
 assign fast_source=live&&confirmed&&confirm_age<MAX_UNCONFIRMED_FRAMES;
 face_patch_motion #(.W(WIDTH/8),.H(HEIGHT/8)) patch(
  .clk(clk),.rst_n(active_reset),.enable(confirmed&&confirm_age<MAX_UNCONFIRMED_FRAMES),
  .seed_valid(seed_valid),.seed_x(seed_x),.seed_y(seed_y),
  .frame_start(frame_start),.frame_end(frame_end),.frame_error(frame_error),
  .sample_valid(sample_valid),.sample_x(sample_x),.sample_y(sample_y),.gray(gray),
  .result_valid(patch_valid),.found(patch_found),.center_x(patch_x),.center_y(patch_y),
  .busy(patch_busy),.compute_cycles(match_cycles),.best_error(patch_error),.adaptive_seed(wanted_size>=256));
 function [7:0] seed_clamp;input [11:0] p;input integer hi;begin
  seed_clamp=(p>>3)<12?12:(p>>3)>hi-12?hi-12:p>>3;
 end endfunction
 function signed [13:0] approach_offset;
 input signed [13:0] a,b;reg signed [14:0] delta;
 begin delta=$signed(b)-$signed(a);approach_offset=delta>8?a+14'sd8:delta< -8?a-14'sd8:b;end
 endfunction
 function [11:0] approach_size;input [11:0] a,b;begin
  approach_size=b>a+8?a+8:a>b+8?a-8:b;
 end endfunction
 function [11:0] bound;input signed [14:0] v;input integer hi;
 begin bound=v<0?0:v>hi?hi:v;end endfunction
 wire signed [13:0] corrected_x=$signed({2'b0,cnn_cx})-$signed({3'b0,capture_x,3'b0});
 wire signed [13:0] corrected_y=$signed({2'b0,cnn_cy})-$signed({3'b0,capture_y,3'b0});
 wire signed [14:0] change_x=$signed(corrected_x)-$signed(offset_x);
 wire signed [14:0] change_y=$signed(corrected_y)-$signed(offset_y);
 wire associated=change_x<=MAX_CORRECTION&&change_x>=-MAX_CORRECTION&&change_y<=MAX_CORRECTION&&change_y>=-MAX_CORRECTION;
 wire signed [13:0] next_ox=approach_offset(offset_x,wanted_x),next_oy=approach_offset(offset_y,wanted_y);
 wire [11:0] next_size=approach_size(box_size,wanted_size);
 wire [11:0] next_cx=awaiting_seed?bootstrap_x:bound($signed({4'b0,patch_x,3'b0})+$signed(next_ox),WIDTH-1);
 wire [11:0] next_cy=awaiting_seed?bootstrap_y:bound($signed({4'b0,patch_y,3'b0})+$signed(next_oy),HEIGHT-1);
 wire [11:0] next_bx=bound($signed({3'b0,next_cx})-$signed({3'b0,next_size[11:1]}),WIDTH-next_size);
 wire [11:0] next_by=bound($signed({3'b0,next_cy})-$signed({3'b0,next_size[11:1]}),HEIGHT-next_size);
 wire [11:0] valid_size=cnn_size<32?32:cnn_size>HEIGHT?HEIGHT:cnn_size;
 always @(posedge clk or negedge active_reset)begin
  if(!active_reset)begin
   confirmed<=0;live<=0;seed_valid<=0;awaiting_seed<=0;bootstrap_x<=0;bootstrap_y<=0;seed_x<=0;seed_y<=0;confirm_age<=0;
   frame_id<=0;match_frame<=0;capture_frame<=0;generation<=0;capture_generation<=0;
   capture_seen<=0;capture_anchor<=0;capture_x<=0;capture_y<=0;
   offset_x<=0;offset_y<=0;wanted_x<=0;wanted_y<=0;wanted_size<=32;
   result_valid<=0;found<=0;box_x<=0;box_y<=0;box_size<=32;center_x<=0;center_y<=0;
   accepted_corrections<=0;rejected_corrections<=0;
  end else begin
   result_valid<=0;seed_valid<=0;
   if(frame_start)begin
    frame_id<=frame_id+1'b1;
    if(!patch_busy)match_frame<=frame_id+1'b1;
    if(confirmed&&confirm_age<MAX_UNCONFIRMED_FRAMES)confirm_age<=confirm_age+1'b1;
    if(confirmed&&confirm_age>=MAX_UNCONFIRMED_FRAMES-1)begin
     confirmed<=0;live<=0;found<=0;result_valid<=1;generation<=generation+1'b1;
    end
   end
   if(capture_start)begin
    // Raw video SOF precedes the sampler's registered frame_start by one cycle.
    capture_frame<=frame_id+1'b1;capture_generation<=generation;
    capture_seen<=1;capture_anchor<=0;
   end
   if(patch_valid&&!(frame_start&&confirmed&&confirm_age>=MAX_UNCONFIRMED_FRAMES-1))begin
    result_valid<=1;
    if(patch_found)begin
     live<=1;found<=1;offset_x<=next_ox;offset_y<=next_oy;box_size<=next_size;
     if(awaiting_seed)begin
      offset_x<=$signed({2'b0,bootstrap_x})-$signed({3'b0,patch_x,3'b0});
      offset_y<=$signed({2'b0,bootstrap_y})-$signed({3'b0,patch_y,3'b0});
      wanted_x<=$signed({2'b0,bootstrap_x})-$signed({3'b0,patch_x,3'b0});
      wanted_y<=$signed({2'b0,bootstrap_y})-$signed({3'b0,patch_y,3'b0});
      awaiting_seed<=0;
     end
     center_x<=next_cx;center_y<=next_cy;box_x<=next_bx;box_y<=next_by;
     if(capture_seen&&match_frame==capture_frame&&capture_generation==generation)begin
      capture_anchor<=1;capture_x<=patch_x;capture_y<=patch_y;
     end
    end else begin live<=0;confirmed<=0;found<=0;generation<=generation+1'b1;end
   end
   if(cnn_valid&&capture_seen&&!(patch_valid&&!patch_found)&&!frame_error)begin
    if(!capture_start)capture_seen<=0;
    if(cnn_found&&capture_generation==generation)begin
     if(live&&capture_anchor)begin
      if(associated)begin
       wanted_x<=corrected_x;wanted_y<=corrected_y;wanted_size<=valid_size;
       confirmed<=1;confirm_age<=0;accepted_corrections<=accepted_corrections+1'b1;
      end else rejected_corrections<=rejected_corrections+1'b1;
     end else if(!live)begin
      awaiting_seed<=1;bootstrap_x<=cnn_cx;bootstrap_y<=cnn_cy;
      seed_x<=seed_clamp(cnn_cx,WIDTH/8);seed_y<=seed_clamp(cnn_cy,HEIGHT/8);seed_valid<=1;
      offset_x<=$signed({2'b0,cnn_cx})-$signed({3'b0,seed_clamp(cnn_cx,WIDTH/8),3'b0});
      offset_y<=$signed({2'b0,cnn_cy})-$signed({3'b0,seed_clamp(cnn_cy,HEIGHT/8),3'b0});
      wanted_x<=$signed({2'b0,cnn_cx})-$signed({3'b0,seed_clamp(cnn_cx,WIDTH/8),3'b0});
      wanted_y<=$signed({2'b0,cnn_cy})-$signed({3'b0,seed_clamp(cnn_cy,HEIGHT/8),3'b0});
      wanted_size<=valid_size;box_size<=valid_size;confirmed<=1;confirm_age<=0;
     end
    end
   end
   if(frame_error)begin found<=0;live<=0;confirmed<=0;result_valid<=1;generation<=generation+1'b1;end
  end
 end
endmodule
