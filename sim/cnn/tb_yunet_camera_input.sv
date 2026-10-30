`timescale 1ns/1ps
module tb_yunet_camera_input;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,enable=0,sof=0,eol=0,de=0;reg [23:0] rgb=0;
 wire valid,start,cap,error;wire[16:0]addr;wire[7:0]data;wire[31:0]accepted;
 reg[23:0]pixels[0:921599];reg[7:0]expected[0:61439];
 integer x,y,n=0,waits=0;
 yunet_rgb_snapshot dut(.clk(clk),.rst_n(rst),.enable(enable),.network_busy(1'b0),.sof(sof),.eol(eol),.de(de),.rgb(rgb),
 .load_valid(valid),.load_address(addr),.load_data(data),.start_network(start),.capturing(cap),.stream_error(error),.accepted_frames(accepted));
 always @(negedge clk)if(rst&&valid)begin
  if(addr!==n||data!==expected[n])$fatal(1,"camera tensor mismatch address%0d expected%0d byte%0d expected%0d",addr,n,data,expected[n]);
  n=n+1;
 end
 initial begin
  $readmemh(".agent/build/camera_input/rgb.hex",pixels);
  $readmemh(".agent/build/camera_input/expected.hex",expected);
  repeat(4)@(negedge clk);rst=1;enable=1;
  for(y=0;y<720;y=y+1)begin
   for(x=0;x<1280;x=x+1)begin
    @(posedge clk);#1;de=1;sof=x==0&&y==0;eol=x==1279;rgb=pixels[y*1280+x];
   end
   @(posedge clk);#1;de=0;sof=0;eol=0;repeat(8)@(posedge clk);
  end
  while(!start)begin @(negedge clk);waits=waits+1;if(waits>5000)$fatal(1,"padding did not finish");end
  if(n!=61440||error||accepted!=1)$fatal(1,"incomplete tensor %0d error%0d accepted%0d",n,error,accepted);
  $display("PASS tb_yunet_camera_input real1280x720RGB rounded8x8 BGR0, all61440bytes, six zero rows");$finish;
 end
 initial begin #20000000;$fatal(1,"watchdog");end
endmodule
