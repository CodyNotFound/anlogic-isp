`timescale 1ns/1ps
// Native 1280x720 RGB protocol -> real sampler -> full CNN -> PWM controller.
// Only the source photograph is synthetic stimulus; no detection is injected.
module tb_yunet_native_v64;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,en=0,sof=0,eol=0,de=0;reg [23:0] rgb=0;
 wire rv,found,busy,error,capture;wire [11:0] x,y,size,cx,cy;wire [31:0] completed;
 face_video_cnn #(.SHARED_TRACK_FRAME(1),.PROGRAM_FILE("rtl/analytics/face_cnn/program.hex"),
  .W0_FILE("rtl/analytics/face_cnn/weights0.hex"),.W1_FILE("rtl/analytics/face_cnn/weights1.hex"),.W2_FILE("rtl/analytics/face_cnn/weights2.hex"),.W3_FILE("rtl/analytics/face_cnn/weights3.hex"),
  .BIAS_FILE("rtl/analytics/face_cnn/bias.hex"),.SHIFT_FILE("rtl/analytics/face_cnn/shift.hex"),
  .SIGMOID_FILE("rtl/analytics/face_cnn/sigmoid.hex"),.OFFSET_FILE("rtl/analytics/face_cnn/offset.hex"),.SIZE_FILE("rtl/analytics/face_cnn/size.hex")) face(
  .clk(clk),.rst_n(rst),.enable(en),.sof(sof),.eol(eol),.de(de),.rgb(rgb),.position_valid(rv),.found(found),
  .box_x(x),.box_y(y),.box_size(size),.center_x(cx),.center_y(cy),.busy(busy),.stream_error(error),.completed_frames(completed),.shared_enable(1'b0),.shared_write_en(1'b0),.shared_write_address(15'd0),.shared_read_address(15'd0),.shared_write_data(8'd0),.shared_read_data(),.shared_read_word(),.inference_cycles(),.capture_started(capture));
 wire ph,pv;wire [11:0] h,v;wire [1:0] state;
 servo_gimbal_ctrl #(.CLK_HZ(1000000)) servo(.clk(clk),.rst_n(rst),.enable(en),.result_valid(rv),.found(found),.cx(cx[10:3]),.cy(cy[10:3]),
  .manual_mode(1'b0),.keys_pressed(4'b0),.pwm_h(ph),.pwm_v(pv),.pulse_h_us(h),.pulse_v_us(v),.ctl_state(state),.slow_source(1'b1),.capture_valid(capture));
 reg [7:0] pixels[0:61439];integer ix,iy,index,fd,rc,score,ex,ey,ez,ecx,ecy;
 initial begin
  $readmemh("reports/yunet_v48/native_shift.hex",pixels);
  fd=$fopen("reports/yunet_v48/native_expected.txt","r");rc=$fscanf(fd,"%d %d %d %d %d %d",score,ex,ey,ez,ecx,ecy);if(rc!=6)$fatal(1,"native expectation missing");
  repeat(5)@(negedge clk);rst=1;en=1;repeat(20)@(negedge clk);
  for(iy=0;iy<720;iy=iy+1)begin
   for(ix=0;ix<1280;ix=ix+1)begin
    @(negedge clk);de=1;sof=ix==0&&iy==0;eol=ix==1279;index=((iy>>3)*160+(ix>>3))*4;
    rgb={pixels[index+2],pixels[index+1],pixels[index]};
   end
   @(negedge clk);de=0;sof=0;eol=0;repeat(8)@(negedge clk);
  end
  wait(rv);@(negedge clk);
  if(!found||error||x!==ex||y!==ey||size!==ez||cx!==ecx||cy!==ecy||completed!=1)
   $fatal(1,"native real detector output wrong: found%0d error%0d box%0d,%0d,%0d center%0d,%0d",found,error,x,y,size,cx,cy);
  // cx=936 => cell117, error37, deadband8, gain/2 => 15us, H reversed.
  if(ecx!=936||ecy!=404)$fatal(1,"update independent expected correction after fixture change");
  wait(h==1434);@(negedge clk);
  if(h!=1434||v!=1504)$fatal(1,"actual detector did not drive the correct PWM command %0d/%0d",h,v);
  repeat(400000)@(negedge clk);
  if(h!=1434||v!=1504)$fatal(1,"stale detection repeated a motion command");
  $display("PASS tb_yunet_native_v64: 921600 native RGB pixels -> averaging -> actual full CNN -> center936,404 -> horizontal1434us, vertical1504us; stale result holds");$finish;
 end
 initial begin #700000000;$fatal(1,"native gimbal watchdog");end
endmodule
