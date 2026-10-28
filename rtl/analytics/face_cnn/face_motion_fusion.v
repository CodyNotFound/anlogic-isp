// Resource candidate: CNN centers are multiples of four pixels, sizes of eight.
// Store exact detector coordinates in these native units, not wider pixel offsets.
(* dsp_style="no" *) module face_motion_fusion #(
 parameter WIDTH=1280,HEIGHT=720,MAX_UNCONFIRMED_FRAMES=45,MAX_CORRECTION=64
)(input wire clk,rst_n,enable,clear,capture_start,cnn_valid,cnn_found,
 input wire [11:0] cnn_cx,cnn_cy,cnn_size,
 input wire frame_start,frame_end,frame_error,sample_valid,
 input wire [7:0] sample_x,sample_y,gray,
 output reg result_valid,found,output wire [11:0] box_x,box_y,box_size,center_x,center_y,
 output wire fast_source,output wire [31:0] match_cycles,
 output reg [15:0] accepted_corrections,rejected_corrections);
 wire active_reset=rst_n&&enable&&!clear;
 reg confirmed,live,seed_valid,awaiting_seed,suspended;
 reg [7:0] seed_x,seed_y,last_patch_x,last_patch_y;
 reg [5:0] age;
 reg [15:0] frame_id,match_frame,capture_frame;
 reg [7:0] generation,capture_generation;
 reg capture_seen,capture_anchor;
 reg [8:0] xq,yq;reg [7:0] capture_px,capture_py;
 reg [6:0] sizeq,wanted_size;
 reg signed [5:0] correction_x,correction_y;
 wire pv,pf,pbusy;wire [7:0] px,py;wire [15:0] patch_error;
 assign fast_source=live&&confirmed&&age<MAX_UNCONFIRMED_FRAMES;
 face_patch_motion #(.W(WIDTH/8),.H(HEIGHT/8)) patch(
  .clk(clk),.rst_n(active_reset),.enable(confirmed&&age<MAX_UNCONFIRMED_FRAMES),
  .seed_valid(seed_valid),.seed_x(seed_x),.seed_y(seed_y),.adaptive_seed(wanted_size>=32),
  .frame_start(frame_start),.frame_end(frame_end),.frame_error(frame_error),
  .sample_valid(sample_valid),.sample_x(sample_x),.sample_y(sample_y),.gray(gray),
  .result_valid(pv),.found(pf),.center_x(px),.center_y(py),.busy(pbusy),
  .compute_cycles(match_cycles),.best_error(patch_error));
 function [7:0] seed_clamp;input [11:0] p;input integer hi;begin
  seed_clamp=(p>>3)<12?12:(p>>3)>hi-12?hi-12:p>>3;end endfunction
 function signed [5:0] step;input signed [5:0] e;begin step=e>2?2:e< -2?-2:e;end endfunction
 function [8:0] bound;input signed [10:0] v;input [8:0] hi;begin bound=v<0?0:v>$signed({2'b0,hi})?hi:v;end endfunction
 wire signed [8:0] dx=$signed({1'b0,px})-$signed({1'b0,last_patch_x});
 wire signed [8:0] dy=$signed({1'b0,py})-$signed({1'b0,last_patch_y});
 wire [8:0] nx=awaiting_seed?xq:bound($signed({2'b0,xq})+($signed({{2{dx[8]}},dx})<<<1)+step(correction_x),WIDTH/4-1);
 wire [8:0] ny=awaiting_seed?yq:bound($signed({2'b0,yq})+($signed({{2{dy[8]}},dy})<<<1)+step(correction_y),HEIGHT/4-1);
 wire [6:0] ns=sizeq<wanted_size?sizeq+1'b1:sizeq>wanted_size?sizeq-1'b1:sizeq;
 // Transport old detections by MATCHER displacement only. Including earlier
 // CNN corrections in this displacement would apply a correction twice.
 wire signed [8:0] transport_x=$signed({1'b0,last_patch_x})-$signed({1'b0,capture_px});
 wire signed [8:0] transport_y=$signed({1'b0,last_patch_y})-$signed({1'b0,capture_py});
 wire signed [10:0] ex=$signed({2'b0,cnn_cx[10:2]})+($signed({{2{transport_x[8]}},transport_x})<<<1)-$signed({2'b0,xq});
 wire signed [10:0] ey=$signed({2'b0,cnn_cy[10:2]})+($signed({{2{transport_y[8]}},transport_y})<<<1)-$signed({2'b0,yq});
 wire associated=ex<=MAX_CORRECTION/4&&ex>=-MAX_CORRECTION/4&&ey<=MAX_CORRECTION/4&&ey>=-MAX_CORRECTION/4;
 wire [6:0] cs=cnn_size<32?4:cnn_size>HEIGHT?HEIGHT/8:cnn_size[9:3];
 wire valid_cnn=cnn_cx<WIDTH&&cnn_cy<HEIGHT&&cnn_size!=0;
 assign center_x={1'b0,xq,2'b0};assign center_y={1'b0,yq,2'b0};assign box_size={2'b0,sizeq,3'b0};
 wire [8:0] max_left=WIDTH/4-{sizeq,1'b0},max_top=HEIGHT/4-{sizeq,1'b0};
 wire [8:0] left=bound($signed({2'b0,xq})-$signed({4'b0,sizeq}),max_left);
 wire [8:0] top=bound($signed({2'b0,yq})-$signed({4'b0,sizeq}),max_top);
 assign box_x={1'b0,left,2'b0};assign box_y={1'b0,top,2'b0};
 wire expiry=frame_start&&(confirmed||found)&&age>=MAX_UNCONFIRMED_FRAMES-1;
 always @(posedge clk or negedge active_reset)begin
  if(!active_reset)begin
   confirmed<=0;live<=0;seed_valid<=0;awaiting_seed<=0;suspended<=0;
   seed_x<=0;seed_y<=0;last_patch_x<=0;last_patch_y<=0;age<=0;frame_id<=0;match_frame<=0;capture_frame<=0;
   generation<=0;capture_generation<=0;capture_seen<=0;capture_anchor<=0;
   xq<=0;yq<=0;capture_px<=0;capture_py<=0;sizeq<=4;wanted_size<=4;correction_x<=0;correction_y<=0;
   result_valid<=0;found<=0;accepted_corrections<=0;rejected_corrections<=0;
  end else begin
   result_valid<=0;seed_valid<=0;
   if(frame_start)begin
    frame_id<=frame_id+1'b1;if(!pbusy)match_frame<=frame_id+1'b1;
    if((confirmed||found)&&age<MAX_UNCONFIRMED_FRAMES)age<=age+1'b1;
    if(expiry)begin confirmed<=0;live<=0;found<=0;result_valid<=1;generation<=generation+1'b1;end
   end
   if(capture_start)begin capture_frame<=frame_id+1'b1;capture_generation<=generation;capture_seen<=1;capture_anchor<=0;end
   if(pv&&!expiry)begin
    result_valid<=1;
    if(pf)begin
     live<=1;found<=1;xq<=nx;yq<=ny;sizeq<=ns;awaiting_seed<=0;
     correction_x<=awaiting_seed?0:correction_x-step(correction_x);
     correction_y<=awaiting_seed?0:correction_y-step(correction_y);
     last_patch_x<=px;last_patch_y<=py;
     if(capture_seen&&match_frame==capture_frame&&capture_generation==generation)begin
      capture_anchor<=1;capture_px<=px;capture_py<=py;
     end
    end else begin
     live<=0;confirmed<=0;found<=0;generation<=generation+1'b1;
     if(awaiting_seed)suspended<=1;awaiting_seed<=0;
    end
   end
   if(cnn_valid&&capture_seen&&!(pv&&!pf)&&!frame_error)begin
    if(!capture_start)capture_seen<=0;
    if(capture_generation==generation)begin
     if(suspended)begin
      result_valid<=1;found<=cnn_found&&valid_cnn;age<=0;
      if(cnn_found&&valid_cnn)begin xq<=cnn_cx[10:2];yq<=cnn_cy[10:2];sizeq<=cs;end
     end else if(cnn_found&&valid_cnn)begin
      if(live&&capture_anchor)begin
       if(associated)begin
        correction_x<=ex[5:0];correction_y<=ey[5:0];wanted_size<=cs;
        confirmed<=1;age<=0;accepted_corrections<=accepted_corrections+1'b1;
       end else rejected_corrections<=rejected_corrections+1'b1;
      end else if(!live)begin
       xq<=cnn_cx[10:2];yq<=cnn_cy[10:2];sizeq<=cs;wanted_size<=cs;
       seed_x<=seed_clamp(cnn_cx,WIDTH/8);seed_y<=seed_clamp(cnn_cy,HEIGHT/8);seed_valid<=1;
       correction_x<=0;correction_y<=0;awaiting_seed<=1;confirmed<=1;age<=0;found<=1;result_valid<=1;
      end
     end
    end
   end
   if(frame_error)begin found<=0;live<=0;confirmed<=0;result_valid<=1;generation<=generation+1'b1;end
  end
 end
endmodule
