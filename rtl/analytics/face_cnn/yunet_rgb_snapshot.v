// Native camera RGB -> rounded box-average BGR0 input. No video backpressure.
// The 160x90 scene is followed by six zero rows for stride-32 compatibility.
// Supported camera dimensions are 160*2^n by 90*2^m, with >=4 pixels/block row.
module yunet_rgb_snapshot #(
 parameter integer WIDTH=1280,HEIGHT=720,CAPTURE_TIMEOUT=2000000
)(input wire clk,rst_n,enable,network_busy,sof,eol,de,input wire [23:0] rgb,
 output reg load_valid,output reg [16:0] load_address,output reg [7:0] load_data,
 output reg start_network,output wire capturing,output reg stream_error,
 output reg [31:0] accepted_frames);
 localparam SX=WIDTH/160,SY=HEIGHT/90,XS=$clog2(SX),YS=$clog2(SY),SHIFT=XS+YS;
 localparam IDLE=0,CAPTURE=1,PAD=2,START=3,WAIT_BUSY=4;
 reg [2:0] state;assign capturing=state!=IDLE;
 reg [10:0] x,y;wire [10:0] px=sof?11'd0:x,py=sof?11'd0:y;
 wire [7:0] column_index=px<WIDTH?px>>XS:8'd0;
 (* ram_style="bram" *) reg [41:0] columns[0:159];
 reg [41:0] column_q;reg [10:0] hr,hg,hb;
 wire [10:0] rr=((px&(SX-1))==0?11'd0:hr)+{3'd0,rgb[23:16]};
 wire [10:0] rg=((px&(SX-1))==0?11'd0:hg)+{3'd0,rgb[15:8]};
 wire [10:0] rb=((px&(SX-1))==0?11'd0:hb)+{3'd0,rgb[7:0]};
 wire [13:0] br=((py&(SY-1))==0?14'd0:column_q[41:28])+{3'd0,rr};
 wire [13:0] bg=((py&(SY-1))==0?14'd0:column_q[27:14])+{3'd0,rg};
 wire [13:0] bb=((py&(SY-1))==0?14'd0:column_q[13:0])+{3'd0,rb};
 wire [14:0] rounded_r={1'b0,br}+(15'd1<<(SHIFT-1));
 wire [14:0] rounded_g={1'b0,bg}+(15'd1<<(SHIFT-1));
 wire [14:0] rounded_b={1'b0,bb}+(15'd1<<(SHIFT-1));
 wire accept=state==IDLE&&enable&&!network_busy&&sof;
 wire active=state==CAPTURE||accept;
 wire bad_pixel=de&&((eol!=(px==WIDTH-1))||px>=WIDTH||py>=HEIGHT);
 wire sample=active&&de&&!bad_pixel&&(px&(SX-1))==SX-1&&(py&(SY-1))==SY-1;
 reg [2:0] emit_count;reg [23:0] sample_rgb;reg final_sample;
 reg [16:0] cursor;reg [21:0] watchdog;
 always @(posedge clk)begin
  column_q<=columns[column_index];
  if(active&&de&&!bad_pixel&&(px&(SX-1))==SX-1)columns[column_index]<={br,bg,bb};
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;x<=0;y<=0;hr<=0;hg<=0;hb<=0;emit_count<=0;sample_rgb<=0;final_sample<=0;
   cursor<=0;watchdog<=0;load_valid<=0;load_address<=0;load_data<=0;start_network<=0;stream_error<=0;accepted_frames<=0;
  end else begin
   load_valid<=0;start_network<=0;
   if(sof)begin x<=0;y<=0;end
   if(de)begin if(eol)begin x<=0;y<=py+1'b1;end else begin x<=px+1'b1;y<=py;end end
   if(!enable)begin state<=IDLE;emit_count<=0;watchdog<=0;end
   else begin
    if(accept)begin state<=CAPTURE;cursor<=0;final_sample<=0;watchdog<=0;accepted_frames<=accepted_frames+1'b1;end
    if(active)begin
     watchdog<=accept?22'd0:watchdog+1'b1;
     if(de)begin hr<=rr;hg<=rg;hb<=rb;end
     if(emit_count!=0)begin
      load_valid<=1;load_address<=cursor;cursor<=cursor+1'b1;emit_count<=emit_count-1'b1;
      case(emit_count)4:load_data<=sample_rgb[7:0];3:load_data<=sample_rgb[15:8];2:load_data<=sample_rgb[23:16];default:load_data<=0;endcase
      if(emit_count==1&&final_sample)state<=PAD;
     end
     if(sample)begin sample_rgb<={rounded_r[SHIFT+:8],rounded_g[SHIFT+:8],rounded_b[SHIFT+:8]};emit_count<=4;final_sample<=px==WIDTH-1&&py==HEIGHT-1;end
     if(bad_pixel||(sof&&state==CAPTURE)||watchdog>=CAPTURE_TIMEOUT-1)begin
      state<=IDLE;emit_count<=0;load_valid<=0;stream_error<=1;
     end
    end
    if(state==PAD)begin
     load_valid<=1;load_address<=cursor;load_data<=0;cursor<=cursor+1'b1;
     if(cursor==61439)state<=START;
    end
    if(state==START)begin start_network<=1;state<=WAIT_BUSY;end
    if(state==WAIT_BUSY&&network_busy)state<=IDLE;
   end
  end
 end
endmodule
