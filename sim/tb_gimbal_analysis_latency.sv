`timescale 1ns/1ps
// Production analysis dimensions; compute cycles exclude capture/frame waiting.
module tb_gimbal_analysis_latency #(parameter CSV_FILE="reports/gimbal/v38_final/analysis_latency.csv");
 reg clk=0,rst=0,fs=0,sv=0,fe=0;
 reg [7:0] x=0,y=0,gray=0;reg [23:0] rgb=0;
 always #5 clk=~clk;
 wire tr,tf,tbusy,rr,rc,rf,ro,rbusy;
 wire [31:0] tc,cc;
 reg gt=0,gr=0;reg [31:0] saved_t,saved_r;
 integer frame_no,i,j,f,waits,mx,my;
 vision_sad_tracker tracker(.clk(clk),.rst_n(rst),.reseed(1'b0),.frame_start(fs),
  .sample_valid(sv),.frame_end(fe),.gray(gray),.result_valid(tr),.found(tf),
  .busy(tbusy),.compute_cycles(tc));
 vision_color_region region(.clk(clk),.rst_n(rst),.reseed(1'b0),.frame_abort(1'b0),.frame_start(fs),
  .sample_valid(sv),.frame_end(fe),.sample_x(x),.sample_y(y),.rgb(rgb),
  .result_valid(rr),.calibrated(rc),.found(rf),.overflow(ro),.busy(rbusy),.compute_cycles(cc));
 always @(negedge clk)begin
  if(tr)begin gt=1;saved_t=tc;end
  if(rr)begin gr=1;saved_r=cc;end
 end
 initial begin
  f=$fopen(CSV_FILE,"w");
  $fwrite(f,"frame,tracker_found,region_found,tracker_compute_cycles,region_compute_cycles,tracker_ms_at_75MHz,region_ms_at_75MHz\n");
  repeat(4)@(negedge clk);rst=1;repeat(4)@(negedge clk);
  for(frame_no=0;frame_no<2;frame_no=frame_no+1)begin
   gt=0;gr=0;mx=80+6*frame_no;my=45+2*frame_no;
   fs=1;@(negedge clk);fs=0;
   for(j=0;j<90;j=j+1)for(i=0;i<160;i=i+1)begin
    x=i;y=j;sv=1;fe=i==159&&j==89;
    if(i>=mx-12 && i<mx+12 && j>=my-12 && j<my+12)begin
     gray=((i-mx+12)*73^(j-my+12)*151^((i-mx+12)*(j-my+12)*19))&255;rgb=24'h967d73;
    end else begin gray=40;rgb=24'he6e6e6;end
    @(negedge clk);
   end
   sv=0;fe=0;waits=0;
   while(!(gt&&gr)&&waits<2000000)begin @(negedge clk);waits=waits+1;end
   if(!(gt&&gr)||!tf||!rc||ro||(frame_no==1&&!rf))$fatal(1,"production analyzer result frame %0d t=%0d r=%0d",frame_no,tf,rf);
   $fwrite(f,"%0d,%0d,%0d,%0d,%0d,%f,%f\n",frame_no,tf,rf,saved_t,saved_r,saved_t/75000.0,saved_r/75000.0);
   repeat(8)@(negedge clk);
  end
  $fclose(f);$display("PASS tb_gimbal_analysis_latency: 160x90 production cores, real seed/move, compute cycles exclude capture");$finish;
 end
 initial begin #45000000;$fatal(1,"analysis latency timeout");end
endmodule
