`timescale 1ns/1ps
// Full 720p application with the actual font/logo contents. Result interfaces
// are injected here: this is composition validation, not recognition evidence.
module tb_vision_task_osd #(parameter MODE=12,OUTPUT_FILE="reports/vision_tasks/full_osd_rtl.ppm");
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,de=0,sof=0,eol=0,update=0;
 wire vs,hs,od;wire [23:0] pixel;wire rd;wire [7:0] stat;wire toggle;wire [3:0] demo;
 vision_pipeline #(.ENABLE_OSD(1),.FACE_WEAK_FILE("rtl/analytics/face_lbp/human_weak.hex"),
  .FACE_STAGE_FILE("rtl/analytics/face_lbp/human_stage.hex"),.FACE_GEOMETRY_FILE("rtl/analytics/face_lbp/human_geometry.hex")) dut(
  clk,rst_n,4'b1111,4'b1111,sof,eol,de,sof,eol,4'd0,24'h102030,rd,vs,hs,od,pixel,stat,toggle,demo,,,,,);
 wire rv,rh,rde,rs,re;wire [23:0] ref_pixel;
 vision_task_hud #(.WIDTH(1280),.HEIGHT(720)) reference_hud(clk,rst_n,MODE[3:0],1'b1,update,1'b1,1'b1,1'b0,2'd0,
  12'd576,12'd296,12'd128,12'd128,12'd640,12'd360,(MODE==14?20'd30464:20'd123),
  sof,eol,de,sof,eol,24'h102030,rv,rh,rde,rs,re,ref_pixel,1'b0,1'b0);
 reg [23:0] reference_pixels[0:921599];
 reg [23:0] logo_palette[0:255];
 initial $readmemh("sim/logo_pal.hex",logo_palette);
 integer x,y,ref_count=0,count=0,starts=0,white=0,logo=0,f,ox,oy;reg checking=0;
 always @(posedge clk)begin
  #1;
  if(checking&&rde)begin reference_pixels[ref_count]=ref_pixel;ref_count=ref_count+1;end
  if(checking&&od)begin
   ox=count%1280;oy=count/1280;
   if((^pixel)===1'bx)$fatal(1,"unknown composed pixel");
   if(dut.mixer_sof)starts=starts+1;
   if(vs!==(count==0)||hs!==(ox==1279))$fatal(1,"composed qualifier alignment");
   if(ox>=200&&ox<584&&oy>=48&&oy<84)begin
    if(pixel!==reference_pixels[count])$fatal(1,"task HUD overwritten/misaligned at %0d,%0d got%h expected%h",ox,oy,pixel,reference_pixels[count]);
    if(pixel==24'hf0ffff)white=white+1;
   end
   if(ox>=24&&ox<170&&oy>=24&&oy<118&&(pixel==logo_palette[1]||pixel==logo_palette[2]))logo=logo+1;
   $fwrite(f,"%c%c%c",pixel[23:16],pixel[15:8],pixel[7:0]);count=count+1;
  end
 end
 initial begin
  repeat(4)@(negedge clk);rst_n=1;repeat(400)@(negedge clk);
  force dut.u_mode_ctrl.mode=MODE;force dut.u_mode_ctrl.demo_active=0;
  force dut.u_tasks.tf=1;force dut.u_tasks.tx=80;force dut.u_tasks.ty=45;force dut.u_tasks.tq=123;force dut.u_tasks.age=0;
  force dut.u_tasks.picking=0;force dut.u_tasks.rf=1;force dut.u_tasks.rc=1;force dut.u_tasks.ro=0;
  force dut.u_tasks.rx=72;force dut.u_tasks.ry=37;force dut.u_tasks.rw=16;force dut.u_tasks.rh=16;
  force dut.u_tasks.rcx=80;force dut.u_tasks.rcy=45;force dut.u_tasks.ra=476;
  force dut.u_tasks.tv=1;force dut.u_tasks.rv=1;update=1;@(negedge clk);force dut.u_tasks.tv=0;force dut.u_tasks.rv=0;update=0;repeat(30)@(negedge clk);
  f=$fopen(OUTPUT_FILE,"wb");$fwrite(f,"P6\n1280 720\n255\n");checking=1;
  for(y=0;y<720;y=y+1)begin
   for(x=0;x<1280;x=x+1)begin @(negedge clk);de=1;sof=x==0&&y==0;eol=x==1279;end
   @(negedge clk);de=0;sof=0;eol=0;repeat(16)@(negedge clk);
  end
  repeat(40)@(negedge clk);checking=0;$fclose(f);
  if(count!=921600||ref_count!=921600||starts!=1||white<100||logo<100)$fatal(1,"composed counts pixels%0d ref%0d SOF%0d text%0d logo%0d",count,ref_count,starts,white,logo);
  $display("PASS tb_vision_task_osd: 921600 pixels, actual logo/font, task text unobscured, complete timing; injected interface only");$finish;
 end
 initial begin #30000000;$fatal(1,"composed OSD timeout");end
endmodule

module osd_font_bram(input wire I_clk,input wire [7:0] I_char,input wire [3:0] I_row,output wire [15:0] O_row_bits);
 reg [15:0] mem[0:2047];reg [6:0] char_idx;
 always @*begin
  if(I_char>=8'h30&&I_char<=8'h39)char_idx={3'b000,I_char[3:0]};
  else if(I_char>=8'h41&&I_char<=8'h5a)char_idx={2'b00,I_char[4:0]}+7'd9;
  else if(I_char==8'h3a)char_idx=36;else if(I_char==8'h2d)char_idx=37;else if(I_char==8'h2e)char_idx=38;
  else if(I_char>=8'h80&&I_char<=8'hce)char_idx={1'b0,I_char[6:0]}+7'd40;else char_idx=39;
 end
 initial $readmemh("sim/osd_font_rom.hex",mem);
 assign O_row_bits=mem[{char_idx,I_row}];
endmodule
module logo_rom_bram(input wire I_clk,input wire [13:0] I_addr,output reg [7:0] O_idx,output reg [23:0] O_rgb);
 reg [7:0] idx[0:16383];reg [23:0] pal[0:255];
 initial begin $readmemh("sim/logo_idx.hex",idx);$readmemh("sim/logo_pal.hex",pal);end
 always @(posedge I_clk)begin O_idx<=idx[I_addr];O_rgb<=pal[O_idx];end
endmodule
