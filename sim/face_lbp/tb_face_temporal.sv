`timescale 1ns/1ps
// Result-boundary injection validates temporal policy, not face accuracy.
module tb_face_temporal;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,en=1;wire found;
 reg [8:0] xx,yy;reg [7:0] ss,vv=6;reg detected;
 face_video_position #(.RESULT_TTL_CYCLES(64)) dut(.clk(clk),.rst_n(rst_n),.enable(en),
 .sof(1'b0),.eol(1'b0),.de(1'b0),.rgb(24'd0),.found(found));
 task result;input integer x,y,size;input hit;
 begin
  @(negedge clk);xx=x;yy=y;ss=size;detected=hit;
  force dut.core_result=1;force dut.core_found=detected;
  force dut.cx=xx;force dut.cy=yy;force dut.ts=ss;
  force dut.core_votes=vv;
  @(negedge clk);release dut.core_result;release dut.core_found;release dut.cx;release dut.cy;release dut.ts;release dut.core_votes;
 end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  result(40,40,32,1);if(found)$fatal(1,"single-frame false positive accepted");
  vv=0;result(42,41,32,1);if(found)$fatal(1,"template bridge confirmed a new face without a second classifier hit");vv=6;
  result(44,42,32,1);if(!found)$fatal(1,"consistent face not confirmed");
  vv=0;result(45,42,32,1);if(!found)$fatal(1,"established face bridge rejected");vv=6;
  result(120,40,32,1);if(found)$fatal(1,"jump accepted immediately");
  result(120,40,32,1);if(!found)$fatal(1,"new stable face not confirmed");
  result(0,0,0,0);if(found)$fatal(1,"negative detection held");
  result(120,40,32,1);repeat(70)@(negedge clk);
  result(120,40,32,1);if(found)$fatal(1,"stale pending result confirmed");
  result(120,40,32,1);if(!found)$fatal(1,"confirmation after expiry");
  en=0;repeat(3)@(negedge clk);en=1;
  result(120,40,32,1);if(found)$fatal(1,"mode reset did not clear history");
  $display("PASS tb_face_temporal: single positive, confirmation, jump, loss, expiry, mode reset");$finish;
 end
endmodule
