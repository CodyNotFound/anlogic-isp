// One registered video stage. Commit box changes at SOF to avoid torn boxes.
module face_position_overlay(
    input wire clk,rst_n,enable,
    input wire vsync,hsync,de,sof,eol,
    input wire [23:0] rgb,
    input wire found,
    input wire [11:0] box_x,box_y,box_size,center_x,center_y,
    output reg out_vsync,out_hsync,out_de,out_sof,out_eol,
    output reg [23:0] out_rgb
);
    reg [11:0] x,y;
    reg display_found;
    reg [11:0] bx,by,bs,cx,cy;
    wire [11:0] px=sof ? 12'd0 : x, py=sof ? 12'd0 : y;
    wire active=enable && (sof ? found : display_found);
    wire [11:0] left=sof ? box_x : bx, top=sof ? box_y : by;
    wire [11:0] size=sof ? box_size : bs;
    wire [11:0] mid_x=sof ? center_x : cx, mid_y=sof ? center_y : cy;
    wire [12:0] right={1'b0,left}+{1'b0,size}, bottom={1'b0,top}+{1'b0,size};
    wire inside_x=px>=left && {1'b0,px}<right;
    wire inside_y=py>=top && {1'b0,py}<bottom;
    wire border=inside_x && inside_y &&
        (px-left<2 || right-{1'b0,px}<=2 || py-top<2 || bottom-{1'b0,py}<=2);
    wire crosshair=(px==mid_x && py+7>=mid_y && py<=mid_y+7) ||
                   (py==mid_y && px+7>=mid_x && px<=mid_x+7);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            x<=0;y<=0;display_found<=0;bx<=0;by<=0;bs<=0;cx<=0;cy<=0;
            out_vsync<=0;out_hsync<=0;out_de<=0;out_sof<=0;out_eol<=0;out_rgb<=0;
        end else begin
            out_vsync<=vsync;out_hsync<=hsync;out_de<=de;out_sof<=sof;out_eol<=eol;
            out_rgb<=de ? (active && crosshair ? 24'hff4040 :
                          active && border ? 24'h00ff40 : rgb) : 24'd0;
            if(!enable) display_found<=0;
            if(sof) begin
                x<=0;y<=0;display_found<=enable && found;
                bx<=box_x;by<=box_y;bs<=box_size;cx<=center_x;cy<=center_y;
            end
            if(de) begin
                if(eol) begin x<=0;y<=py+1'b1;end
                else begin x<=px+1'b1;y<=py;end
            end
        end
    end
endmodule
