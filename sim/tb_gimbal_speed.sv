`timescale 1ns/1ps
// Compare command travel with the archived v37 controller, not a servo plant.
module tb_gimbal_speed;
 reg clk=0,rst=0,en=0,valid=0,manual=0;
 reg [3:0] keys=0;
 always #5 clk=~clk;
 wire [11:0] old_h,new_h,old_v,new_v;
 servo_gimbal_v37_baseline #(.CLK_HZ(1000000)) old_ctrl(
  clk,rst,en,valid,1'b1,8'd159,8'd89,manual,keys,,,old_h,old_v,);
 servo_gimbal_ctrl #(.CLK_HZ(1000000)) new_ctrl(
  clk,rst,en,valid,1'b1,8'd159,8'd89,manual,keys,,,new_h,new_v,);
 integer elapsed,old_time,new_time,rate,period,f;
 task reset;
 begin
  rst=0;valid=0;en=0;manual=0;keys=0;
  repeat(4)@(negedge clk);rst=1;old_time=0;new_time=0;
 end endtask
 initial begin
  f=$fopen("reports/gimbal/v38_final/speed_measurements.csv","w");
  $fwrite(f,"case,result_hz,old_command_travel_us,new_command_travel_us\n");
  reset;manual=1;keys=8;elapsed=0;
  while(!old_time && elapsed<3000000)begin
   @(negedge clk);elapsed=elapsed+1;
   if(new_h>=2000 && !new_time)new_time=elapsed;
   if(old_h>=2000 && !old_time)old_time=elapsed;
  end
  if(old_time!=2500000 || new_time!=500000)$fatal(1,"manual travel %0d/%0d",old_time,new_time);
  $fwrite(f,"manual_1500_to_2000,50,%0d,%0d\n",old_time,new_time);
  for(rate=10;rate<=50;rate=rate+20)begin
   reset;en=1;period=1000000/rate;elapsed=0;
   while(!old_time && elapsed<13000000)begin
    valid=elapsed%period==0;
    @(negedge clk);elapsed=elapsed+1;
    if(new_h<=1000 && !new_time)new_time=elapsed;
    if(old_h<=1000 && !old_time)old_time=elapsed;
   end
   if(!old_time || !new_time || new_time*7>old_time)$fatal(1,"auto speed rate %0d times %0d/%0d",rate,old_time,new_time);
   // Stop packets: the command must not continue integrating a stale target.
   valid=0;repeat(2)@(negedge clk);
   $fwrite(f,"auto_1500_to_1000,%0d,%0d,%0d\n",rate,old_time,new_time);
  end
  $fclose(f);$display("PASS tb_gimbal_speed: archived v37 comparison; manual acceleration and 10/30/50Hz result streams");$finish;
 end
 initial begin #240000000;$fatal(1,"speed benchmark timeout");end
endmodule
