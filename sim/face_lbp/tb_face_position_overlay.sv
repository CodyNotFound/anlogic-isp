`timescale 1ns/1ps
module tb_face_position_overlay;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,enable=1,vsync=0,hsync=0,de=0,sof=0,eol=0,found=1;
    reg [23:0] rgb=24'h102030;
    reg [11:0] box_x=16,box_y=8,box_size=24,center_x=28,center_y=20;
    wire out_vsync,out_hsync,out_de,out_sof,out_eol;wire [23:0] out_rgb;
    face_position_overlay dut(.*);
    integer frame,x,y,green,red;reg border,crosshair;reg [23:0] expected;
    initial begin
        repeat(3)@(negedge clk);rst_n=1;
        for(frame=0;frame<3;frame=frame+1) begin
            green=0;red=0;
            for(y=0;y<48;y=y+1) for(x=0;x<64;x=x+1) begin
                @(negedge clk);de=1;sof=(x==0&&y==0);eol=(x==63);vsync=sof;hsync=eol;
                // Results arriving mid-frame must wait until next SOF.
                if(frame==0 && x==40 && y==0)begin box_x=40;center_x=52;end
                if(frame==2 && x==0 && y==0) enable=0;
                border=x>=(frame==0?16:40)&&x<(frame==0?40:64)&&y>=8&&y<32&&
                    (x<(frame==0?18:42)||x>=(frame==0?38:62)||y<10||y>=30);
                crosshair=(x==(frame==0?28:52)&&y>=13&&y<=27)||(y==20&&x>=(frame==0?21:45)&&x<=(frame==0?35:59));
                expected=frame==2 ? rgb : crosshair ? 24'hff4040 : border ? 24'h00ff40 : rgb;
                @(posedge clk);#1;
                if(out_rgb!==expected || out_de!==de || out_sof!==sof || out_eol!==eol || out_vsync!==vsync || out_hsync!==hsync)
                    $fatal(1,"FAIL overlay frame=%0d pixel=%0d,%0d actual=%h expected=%h",frame,x,y,out_rgb,expected);
                if(out_rgb==24'h00ff40)green=green+1;if(out_rgb==24'hff4040)red=red+1;
            end
            if(frame<2 && (green==0 || red!=29))$fatal(1,"FAIL box/cross count");
            @(negedge clk);de=0;sof=0;eol=0;@(posedge clk);#1;
            if(out_de || out_rgb!==0)$fatal(1,"FAIL blanking");
        end
        $display("PASS tb_face_position_overlay 9216 pixels: box, center, frame atomicity, exit and all timing qualifiers");$finish;
    end
endmodule
