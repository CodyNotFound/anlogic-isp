// Task information is drawn before the existing logo/mode OSD. Numeric values
// are source-image coordinates and segmented pixel area, not class scores.
(* dsp_style="no" *) module vision_task_hud # (parameter WIDTH=1280,HEIGHT=720,TEXT_ENABLE=1)(
    input wire clk,rst_n,
    input wire [3:0] mode,
    input wire enable,result_valid,found,calibrated,overflow,
    input wire [1:0] lost,
    input wire [11:0] box_x,box_y,box_w,box_h,center_x,center_y,
    input wire [19:0] metric,
    input wire vsync,hsync,de,sof,eol,
    input wire [23:0] rgb,
    output reg out_vsync,out_hsync,out_de,out_sof,out_eol,
    output reg [23:0] out_rgb,
    input wire pick_pending,manual_mode
);
    wire [23:0] x_digits,y_digits,m_digits;
    vision_bcd xconv(.clk(clk),.rst_n(rst_n),.start(result_valid),.value({8'd0,center_x}),.digits(x_digits));
    vision_bcd yconv(.clk(clk),.rst_n(rst_n),.start(result_valid),.value({8'd0,center_y}),.digits(y_digits));
    vision_bcd mconv(.clk(clk),.rst_n(rst_n),.start(result_valid),.value(metric),.digits(m_digits));
    reg [11:0] x,y,bx,by,bw,bh,cx,cy;
    reg df,dc,derr;
    reg [23:0] xd,yd,md;
    // Production OSD reserves x16..178 for logo/CNT/FPS. Small standalone
    // fixtures have no legacy sidebar; keep their compact layout.
    localparam LEFT=(WIDTH>=800)?200:24;
    wire [11:0] px=sof?12'd0:x,py=sof?12'd0:y;
    wire f=sof?found:df,c=sof?calibrated:dc,err=sof?overflow:derr;
    wire [11:0] left=sof?box_x:bx,top=sof?box_y:by,ww=sof?box_w:bw,hh=sof?box_h:bh;
    wire [11:0] midx=sof?center_x:cx,midy=sof?center_y:cy;
    wire [12:0] right={1'b0,left}+ww,bottom={1'b0,top}+hh;
    wire within_box=px>=left && {1'b0,px}<right && py>=top && {1'b0,py}<bottom;
    wire border=f && within_box && (px-left<3 || right-px<=3 || py-top<3 || bottom-py<=3);
    wire crosshair=f && ((px+1>=midx && px<=midx+1 && py+7>=midy && py<=midy+7)||(py+1>=midy && py<=midy+1 && px+7>=midx && px<=midx+7));
    wire reticle=mode!=15&&(!f || mode==14) && ((px==WIDTH/2 && py+12>=HEIGHT/2 && py<=HEIGHT/2+12)||
        (py==HEIGHT/2 && px+12>=WIDTH/2 && px<=WIDTH/2+12));
    wire sample_box=mode==14 && px>=WIDTH/2-8 && px<WIDTH/2+16 && py>=HEIGHT/2-8 && py<HEIGHT/2+16 &&
        (px==WIDTH/2-8 || px==WIDTH/2+15 || py==HEIGHT/2-8 || py==HEIGHT/2+15);
    reg [7:0] character;
    reg [191:0] header;
    integer slot,col,row;
    reg panel;
    wire [11:0] text_x=px-LEFT;
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
            "K":glyph=35'b10001_10010_10100_11000_10100_10010_10001;
            "L":glyph=35'b10000_10000_10000_10000_10000_10000_11111;
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
            "M":glyph=35'b10001_11011_10101_10101_10001_10001_10001;
            "H":glyph=35'b10001_10001_10001_11111_10001_10001_10001;
            default:glyph=0;
        endcase end
    endfunction
    always @*begin
        if(mode==12)header=f?"TRACK LOCK              ":"TRACK LOST K4 PICK      ";
        else if(manual_mode)header="REGION SW4 OFF K4 PICK  ";
        else if(pick_pending)header="REGION SAMPLING CENTER  ";
        else if(err)header="REGION OVERFLOW K4 PICK ";
        else if(!c)header="REGION SAMPLE BAD K4 TRY";
        else header=f?"REGION FOUND            ":"REGION SEARCH           ";
        slot=0;col=0;row=0;character=0;
        panel=TEXT_ENABLE && px>=LEFT && px<LEFT+24*16 && py>=48 && py<84;
        if(panel)begin
            slot=text_x[8:4];col=text_x[3:1];
            if(py<62)begin row=(py-48)/2;character=header>>(8*(23-slot));end
            else if(py>=68 && py<82)begin
                row=(py-68)/2;
                case(slot)
                    0:character="X";1:character=":";
                    2,3,4,5:character="0"+((xd>>((5-slot)*4))&15);
                    7:character="Y";8:character=":";
                    9,10,11,12:character="0"+((yd>>((12-slot)*4))&15);
                    14:character=mode==12?"Q":"A";15:character=":";
                    16,17,18,19,20,21:character="0"+((md>>((21-slot)*4))&15);
                    default:character=" ";
                endcase
            end
        end
    end
    reg [7:0] char_a;
    reg [2:0] row_a,col_a;
    reg [23:0] rgb_a;
    reg [4:0] ctl_a;
    reg enable_a,panel_a,cross_a,border_a,reticle_a;
    reg enable_f;
    wire [34:0] font_bits=glyph(char_a);
    wire [5:0] font_index=6'd34-{row_a,2'd0}-{3'd0,row_a}-{3'd0,col_a};
    wire text_bit=col_a<5 && row_a<7 && font_bits[font_index];
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin x<=0;y<=0;bx<=0;by<=0;bw<=0;bh<=0;cx<=0;cy<=0;df<=0;dc<=0;derr<=0;xd<=0;yd<=0;md<=0;
            char_a<=0;row_a<=0;col_a<=0;rgb_a<=0;ctl_a<=0;enable_a<=0;enable_f<=0;panel_a<=0;cross_a<=0;border_a<=0;reticle_a<=0;
            out_vsync<=0;out_hsync<=0;out_de<=0;out_sof<=0;out_eol<=0;out_rgb<=0;end
        else begin
            if(sof)begin
                enable_f<=enable;
                x<=0;y<=0;df<=found;dc<=calibrated;derr<=overflow;
                bx<=box_x;by<=box_y;bw<=box_w;bh<=box_h;cx<=center_x;cy<=center_y;
                xd<=x_digits;yd<=y_digits;md<=m_digits;
            end
            if(de)begin x<=eol?0:px+1'b1;y<=eol?py+1'b1:py;end
            char_a<=character;row_a<=row[2:0];col_a<=col[2:0];rgb_a<=rgb;ctl_a<={vsync,hsync,de,sof,eol};
            enable_a<=sof?enable:enable_f;panel_a<=panel;cross_a<=crosshair;border_a<=border;reticle_a<=reticle || sample_box;
            {out_vsync,out_hsync,out_de,out_sof,out_eol}<=ctl_a;
            if(!ctl_a[2])out_rgb<=0;
            else if(!enable_a)out_rgb<=rgb_a;
            else if(panel_a)out_rgb<=text_bit?24'hf0ffff:{2'b0,rgb_a[23:18],2'b0,rgb_a[15:10],2'b0,rgb_a[7:2]};
            else if(cross_a)out_rgb<=24'hff4040;
            else if(border_a)out_rgb<=24'h00ff40;
            else if(reticle_a)out_rgb<=24'hffff40;
            else out_rgb<=rgb_a;
        end
    end
endmodule
