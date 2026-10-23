// Always-visible command position and physical K4..K1 / SW4..SW1 legend.
// Raster qualifiers and RGB are registered together. No servo feedback implied.
(* dsp_style="no" *) module gimbal_osd #(parameter WIDTH=1280,HEIGHT=720,ENABLE=1)(
 input wire clk,rst_n,
 input wire [3:0] features,mode,input wire demo_active,
 input wire [1:0] ctl_state,input wire [11:0] pulse_h,pulse_v,
 input wire [23:0] h_digits,v_digits,
 input wire vsync,hsync,de,sof,input wire [23:0] rgb,
 output reg out_vsync,out_hsync,out_de,output reg [23:0] out_rgb,output reg out_sof
);
 localparam PX=WIDTH-400,PY=HEIGHT-56,BX=WIDTH-128,BY=HEIGHT-184;
 reg [11:0] x,y,ph,pv;
 reg [3:0] sw,md;reg demo;reg [1:0] state;
 reg [23:0] hd,vd;
 wire [11:0] px=sof?12'd0:x,py=sof?12'd0:y;
 reg [95:0] text;
 reg [7:0] ch;
 reg [34:0] bits;
 reg panel,hit,marker,border;
 reg [23:0] color;
 integer group,lx,ly,slot,col,row,mx,my;
    function [34:0] glyph;
        input [7:0] ch;
        begin case(ch)
            "0":glyph=35'b01110_10001_10011_10101_11001_10001_01110;
            "1":glyph=35'b00100_01100_00100_00100_00100_00100_01110;
            "2":glyph=35'b01110_10001_00001_00010_00100_01000_11111;
            "3":glyph=35'b11110_00001_00001_01110_00001_00001_11110;
            "4":glyph=35'b00010_00110_01010_10010_11111_00010_00010;
            "5":glyph=35'b11111_10000_10000_11110_00001_00001_11110;
            "6":glyph=35'b01110_10000_10000_11110_10001_10001_01110;
            "7":glyph=35'b11111_00001_00010_00100_01000_01000_01000;
            "8":glyph=35'b01110_10001_10001_01110_10001_10001_01110;
            "9":glyph=35'b01110_10001_10001_01111_00001_00001_01110;
            "A":glyph=35'b01110_10001_10001_11111_10001_10001_10001;
            "C":glyph=35'b01110_10001_10000_10000_10000_10001_01110;
            "D":glyph=35'b11110_10001_10001_10001_10001_10001_11110;
            "E":glyph=35'b11111_10000_10000_11110_10000_10000_11111;
            "F":glyph=35'b11111_10000_10000_11110_10000_10000_10000;
            "G":glyph=35'b01110_10001_10000_10111_10001_10001_01110;
            "I":glyph=35'b01110_00100_00100_00100_00100_00100_01110;
            "K","k":glyph=35'b10001_10010_10100_11000_10100_10010_10001;
            "L","l":glyph=35'b10000_10000_10000_10000_10000_10000_11111;
            "N":glyph=35'b10001_11001_11001_10101_10011_10011_10001;
            "O":glyph=35'b01110_10001_10001_10001_10001_10001_01110;
            "P":glyph=35'b11110_10001_10001_11110_10000_10000_10000;
            "Q":glyph=35'b01110_10001_10001_10001_10101_10010_01101;
            "R":glyph=35'b11110_10001_10001_11110_10100_10010_10001;
            "S":glyph=35'b01111_10000_10000_01110_00001_00001_11110;
            "T":glyph=35'b11111_00100_00100_00100_00100_00100_00100;
            "U":glyph=35'b10001_10001_10001_10001_10001_10001_01110;
            "V":glyph=35'b10001_10001_10001_10001_10001_01010_00100;
            "W":glyph=35'b10001_10001_10001_10101_10101_11011_10001;
            "X":glyph=35'b10001_10001_01010_00100_01010_10001_10001;
            "Y":glyph=35'b10001_10001_01010_00100_00100_00100_00100;
            ":":glyph=35'b00000_00100_00100_00000_00100_00100_00000;
            "B":glyph=35'b11110_10001_10001_11110_10001_10001_11110;
            "H","h":glyph=35'b10001_10001_10001_11111_10001_10001_10001;
            "J","j":glyph=35'b00111_00010_00010_00010_10010_10010_01100;
            "M":glyph=35'b10001_11011_10101_10101_10001_10001_10001;
            default:glyph=0;
        endcase end
    endfunction

 always @*begin
  panel=0;hit=0;marker=0;border=0;text=0;ch=0;bits=0;color=24'hffffff;
  group=0;lx=0;ly=0;slot=0;col=0;row=0;
  mx=BX+24+((2500-ph)>>5);my=BY+24+((pv-500)>>5);
  if(px>=PX && px<PX+384 && py>=PY && py<PY+40)begin
   panel=1;group=px<PX+96?0:px<PX+192?1:px<PX+288?2:3;lx=(px-PX)-group*96;ly=py-PY;
   if(ly<16)begin
    case(group)
     0:text=sw[3]?"SW4 MAN ON  ":"SW4 MAN OFF ";
     1:text=sw[2]?"SW3 AUTO ON ":"SW3 AUTO OFF";
     2:text=sw[1]?"SW2 AE ON   ":"SW2 AE OFF  ";
     3:text=sw[0]?"SW1 AB ON   ":"SW1 AB OFF  ";
    endcase
    color=sw[3-group]?24'h60ff90:24'hc0c0c0;
   end else if(ly>=20 && ly<36)begin
    ly=ly-20;
    if(sw[3])case(group)
     0:text="K4 h LEFT   ";1:text="K3 j DOWN   ";2:text="K2 k UP     ";3:text="K1 l RIGHT  ";
    endcase
    else case(group)
     0:text=(md==12 || md==14)?"K4 PICK     ":"K4 NONE     ";
     1:text="K3 NONE     ";
     2:text="K2 PREV MODE";
     3:text="K1 NEXT MODE";
    endcase
   end else text=0;
   slot=lx>>3;col=lx&7;row=ly>>1;
   if(slot<12 && row<7 && col<5)begin ch=text>>(8*(11-slot));hit=1;end
  end
  if(px>=BX && px<BX+112 && py>=BY && py<BY+112)begin
   panel=1;lx=px-BX;ly=py-BY;text=0;
   if(ly>=4 && ly<18)begin
    case(state)
     1:text="AUTO AWB ON ";2:text="HOLD AWB ON ";3:text="LOST AWB ON ";default:text="IDLE AWB ON ";
    endcase
    if(sw[3])text="MAN AWB ON  ";
    slot=lx>>3;col=lx&7;row=(ly-4)>>1;
   end else if(ly>=94 && ly<108)begin
    slot=lx>>3;col=lx&7;row=(ly-94)>>1;
    text="H0000 V0000 ";
    text[87:80]="0"+hd[15:12];text[79:72]="0"+hd[11:8];text[71:64]="0"+hd[7:4];text[63:56]="0"+hd[3:0];
    text[39:32]="0"+vd[15:12];text[31:24]="0"+vd[11:8];text[23:16]="0"+vd[7:4];text[15:8]="0"+vd[3:0];
   end
   if(text!=0 && slot<12 && row<7 && col<5)begin ch=text>>(8*(11-slot));hit=1;end
   border=(lx==23||lx==88) && ly>=23 && ly<=88 || (ly==23||ly==88) && lx>=23 && lx<=88;
   if((lx==55 && ly>=24 && ly<88)||(ly==55 && lx>=24 && lx<88))border=1;
   // Safe vertical software range 1050..2150us inside a full 500..2500 scale.
   if((ly==41||ly==75)&&lx>=24&&lx<88)border=1;
   marker=(px+2>=mx && px<=mx+2 && py+2>=my && py<=my+2);
   if(marker)begin
    hit=1;color=sw[3]?24'h30e0ff:state==1?24'h60ff90:state==2?24'hffff40:24'hffb050;
    if(ph==500||ph==2500||pv==1050||pv==2150)color=24'hff4040;
   end else if(border)begin hit=1;color=24'h606870;end
  end
 end
 reg r_panel,r_text,r_override,r_vs,r_hs,r_de,r_sof;
 reg [7:0] r_char;reg [2:0] r_row,r_col;
 reg [23:0] r_rgb,r_color;
 wire [34:0] r_bits=glyph(r_char);
 wire text_pixel=r_text && r_bits[34-r_row*5-r_col];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   x<=0;y<=0;ph<=1500;pv<=1500;sw<=0;md<=0;demo<=0;state<=0;hd<=24'h001500;vd<=24'h001500;
   out_vsync<=0;out_hsync<=0;out_de<=0;out_rgb<=0;out_sof<=0;
   r_panel<=0;r_text<=0;r_override<=0;r_vs<=0;r_hs<=0;r_de<=0;r_sof<=0;
   r_char<=0;r_row<=0;r_col<=0;r_rgb<=0;r_color<=0;
  end else begin
   if(sof)begin
    x<=de?1:0;y<=0;ph<=pulse_h;pv<=pulse_v;sw<=features;md<=mode;demo<=demo_active;
    state<=ctl_state;hd<=h_digits;vd<=v_digits;
   end else if(de)begin
    if(x==WIDTH-1)begin x<=0;y<=y==HEIGHT-1?0:y+1'b1;end else x<=x+1'b1;
   end
   r_vs<=vsync;r_hs<=hsync;r_de<=de;r_sof<=sof;r_rgb<=rgb;
   r_panel<=panel;r_text<=hit && !marker && !border;r_override<=marker||border;
   r_char<=ch;r_row<=row[2:0];r_col<=col[2:0];r_color<=color;
   out_vsync<=r_vs;out_hsync<=r_hs;out_de<=r_de;out_sof<=r_sof;
   if(ENABLE && WIDTH>=800 && HEIGHT>=400 && r_de && r_panel)
    out_rgb<=(r_override||text_pixel)?r_color:{2'b0,r_rgb[23:18],2'b0,r_rgb[15:10],2'b0,r_rgb[7:2]};
   else out_rgb<=r_rgb;
  end
 end
endmodule
