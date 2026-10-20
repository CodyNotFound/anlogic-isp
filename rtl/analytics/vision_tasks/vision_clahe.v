// FPGA CLAHE variant: 256x256 video tiles, 32 luma bins, 8x8 RGB-mean
// sampling, clip limit 2x average, uniform excess redistribution, CDF mapping.
// Eight synchronous map copies support luma-bin and spatial interpolation.
// Maps commit only at SOF. Half-strength luma delta preserves RGB differences
// until clipping. This is sampled, 32-bin CLAHE, not bit-equivalent to OpenCV.
module vision_clahe #(parameter WIDTH=1280,HEIGHT=720)(
    input wire clk,rst_n,enable,cancel,
    input wire frame_start,sample_valid,frame_end,
    input wire [7:0] sample_x,sample_y,sample_gray,
    input wire vsync,hsync,de,sof,eol,
    input wire [23:0] rgb,
    output reg out_vsync,out_hsync,out_de,out_sof,out_eol,
    output reg [23:0] out_rgb,
    output reg map_valid,
    output reg [31:0] maps_built
);
    localparam NX=(WIDTH+255)/256,NY=(HEIGHT+255)/256,NT=NX*NY,NB=NT*32;
    localparam SW=WIDTH/8,SH=HEIGHT/8;
    localparam CLEAR=0,WAIT_FRAME=1,HIST=2,HWAIT=3,HADD=4,CLIP_REQ=5,CLIP_WAIT=6,
        CLIP_READ=7,CDF_INIT=8,MAP_REQ=9,MAP_WAIT=10,MAP_READ=11,DIV_WAIT=12,STORE=13;
    reg [3:0] state;
    (* ram_style="bram" *) reg [10:0] histogram[0:511];
    reg [8:0] hist_addr,clear_addr;
    reg [10:0] hist_q;
    reg [13:0] samples;
    reg last_sample;
    reg [3:0] tile;
    reg [4:0] bin;
    reg [14:0] excess;
    reg [11:0] cdf;
    reg active_bank,pending,pending_bank,build_bank;
    reg div_start;
    reg [23:0] numerator,denominator;
    wire div_done,div_busy;
    wire [23:0] quotient;
    function [10:0] population;
        input [3:0] t;
        integer tx,ty,cw,ch;
        begin
            tx=t%NX;ty=t/NX;
            cw=SW-tx*32;ch=SH-ty*32;
            if(cw>32)cw=32;if(ch>32)ch=32;
            population=cw*ch;
        end
    endfunction
    wire [10:0] pop=population(tile);
    wire [10:0] limit=(pop>>4)==0?11'd1:(pop>>4);
    wire [11:0] adjusted={1'b0,hist_q}+(excess>>5)+(bin<excess[4:0]?12'd1:12'd0);
    wire [12:0] next_cdf={1'b0,cdf}+adjusted;
    wire [23:0] scaled_cdf=({11'd0,next_cdf}<<8)-next_cdf;
    vision_unsigned_divider #(.W(24)) divider(.clk(clk),.rst_n(rst_n),.start(div_start),
        .numerator(numerator),.denominator(denominator),.busy(div_busy),.done(div_done),.quotient(quotient));

    // Map address bank bit is fixed, so there are two complete frame mappings.
    (* ram_style="bram" *) reg [7:0] map00[0:1023],map10[0:1023],map01[0:1023],map11[0:1023];
    (* ram_style="bram" *) reg [7:0] low00[0:1023],low10[0:1023],low01[0:1023],low11[0:1023];
    reg [7:0] m00,m10,m01,m11;
    reg [7:0] p00,p10,p01,p11;
    reg [11:0] x,y;
    wire [11:0] px=sof?12'd0:x,py=sof?12'd0:y;
    reg [3:0] gx0,gx1,gy0,gy1;
    reg [7:0] wx,wy;
    reg [11:0] dx,dy;
    wire [9:0] luma={2'd0,rgb[23:16]}+{1'b0,rgb[15:8],1'b0}+{2'd0,rgb[7:0]};
    wire selected_bank=(sof && pending)?pending_bank:active_bank;
    wire selected_valid=map_valid || (sof && pending);
    wire [8:0] addr00=(gy0*NX+gx0)*32+luma[9:5];
    wire [8:0] addr10=(gy0*NX+gx1)*32+luma[9:5];
    wire [8:0] addr01=(gy1*NX+gx0)*32+luma[9:5];
    wire [8:0] addr11=(gy1*NX+gx1)*32+luma[9:5];
    wire [8:0] prev00=luma[9:5]==0?addr00:addr00-1'b1;
    wire [8:0] prev10=luma[9:5]==0?addr10:addr10-1'b1;
    wire [8:0] prev01=luma[9:5]==0?addr01:addr01-1'b1;
    wire [8:0] prev11=luma[9:5]==0?addr11:addr11-1'b1;
    wire [9:0] write_map={build_bank,4'd0,bin}+tile*32;
    always @* begin
        gx0=0;gx1=0;gy0=0;gy1=0;wx=0;wy=0;dx=0;dy=0;
        if(px>=128 && NX>1)begin
            dx=px-128;
            if((dx>>8)>=NX-1)begin gx0=NX-1;gx1=NX-1;end
            else begin gx0=dx>>8;gx1=(dx>>8)+1'b1;wx=dx[7:0];end
        end
        if(py>=128 && NY>1)begin
            dy=py-128;
            if((dy>>8)>=NY-1)begin gy0=NY-1;gy1=NY-1;end
            else begin gy0=dy>>8;gy1=(dy>>8)+1'b1;wy=dy[7:0];end
        end
    end
    // Every RAM output is synchronous and has no reset.
    always @(posedge clk)begin
        hist_q<=histogram[hist_addr];
        if(state==CLEAR)histogram[clear_addr]<=0;
        else if(state==HADD)histogram[hist_addr]<=hist_q+1'b1;
        else if(state==CLIP_READ)histogram[hist_addr]<=hist_q>limit?limit:hist_q;
        m00<=map00[{selected_bank,addr00}];m10<=map10[{selected_bank,addr10}];
        m01<=map01[{selected_bank,addr01}];m11<=map11[{selected_bank,addr11}];
        p00<=low00[{selected_bank,prev00}];p10<=low10[{selected_bank,prev10}];
        p01<=low01[{selected_bank,prev01}];p11<=low11[{selected_bank,prev11}];
        if(state==STORE)begin
            map00[write_map]<=quotient[7:0];map10[write_map]<=quotient[7:0];
            map01[write_map]<=quotient[7:0];map11[write_map]<=quotient[7:0];
            low00[write_map]<=quotient[7:0];low10[write_map]<=quotient[7:0];
            low01[write_map]<=quotient[7:0];low11[write_map]<=quotient[7:0];
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin state<=CLEAR;hist_addr<=0;clear_addr<=0;samples<=0;last_sample<=0;tile<=0;bin<=0;
            excess<=0;cdf<=0;active_bank<=0;pending<=0;pending_bank<=0;build_bank<=1;
            div_start<=0;numerator<=0;denominator<=1;map_valid<=0;maps_built<=0;end
        else begin
            div_start<=0;
            if(sof && pending)begin active_bank<=pending_bank;pending<=0;map_valid<=1;end
            case(state)
                CLEAR:if(clear_addr==NB-1)begin clear_addr<=0;state<=WAIT_FRAME;end else clear_addr<=clear_addr+1'b1;
                WAIT_FRAME:if(enable && frame_start)begin state<=HIST;samples<=0;end
                HIST:if(sample_valid)begin
                    hist_addr<=((sample_y>>5)*NX+(sample_x>>5))*32+(sample_gray>>3);
                    samples<=samples+1'b1;last_sample<=frame_end;state<=HWAIT;
                end
                HWAIT:state<=HADD;
                HADD:if(last_sample)begin
                    if(samples==SW*SH)begin tile<=0;bin<=0;excess<=0;build_bank<=!active_bank;state<=CLIP_REQ;end
                    else begin map_valid<=0;clear_addr<=0;state<=CLEAR;end
                end else state<=HIST;
                CLIP_REQ:begin hist_addr<=tile*32+bin;state<=CLIP_WAIT;end
                CLIP_WAIT:state<=CLIP_READ;
                CLIP_READ:begin
                    if(hist_q>limit)excess<=excess+hist_q-limit;
                    if(bin==31)state<=CDF_INIT;else begin bin<=bin+1'b1;state<=CLIP_REQ;end
                end
                CDF_INIT:begin bin<=0;cdf<=0;state<=MAP_REQ;end
                MAP_REQ:begin hist_addr<=tile*32+bin;state<=MAP_WAIT;end
                MAP_WAIT:state<=MAP_READ;
                MAP_READ:begin
                    cdf<=next_cdf;numerator<=scaled_cdf;denominator<={13'd0,pop};div_start<=1;state<=DIV_WAIT;
                end
                DIV_WAIT:if(div_done)state<=STORE;
                STORE:if(bin==31)begin
                    if(tile==NT-1)begin pending<=1;pending_bank<=build_bank;maps_built<=maps_built+1'b1;clear_addr<=0;state<=CLEAR;end
                    else begin tile<=tile+1'b1;bin<=0;excess<=0;state<=CLIP_REQ;end
                end else begin bin<=bin+1'b1;state<=MAP_REQ;end
                default:state<=CLEAR;
            endcase
            if(!enable || cancel)begin
                map_valid<=0;pending<=0;
                if(cancel || (state!=CLEAR && state!=WAIT_FRAME))begin state<=CLEAR;clear_addr<=0;end
            end
        end
    end

    reg [23:0] rgb0,rgb_bin,rgb1,rgb2;
    reg [7:0] gray0,gray_bin,gray1,gray2,wx0,wy0,wx_bin,wy_bin,wy1;
    reg [5:0] ctl0,ctl_bin,ctl1,ctl2;
    reg [7:0] l00,l10,l01,l11;
    wire [3:0] fraction={1'b0,gray0[2:0]}+4'd1;
    function [7:0] bin_interp;
        input [7:0] lo,hi;input [3:0] f;
        reg signed [13:0] d,total;
        begin
            d=$signed({6'd0,hi})-$signed({6'd0,lo});
            total=$signed({3'd0,lo,3'd0})+14'sd4;
            if(f[0])total=total+d;if(f[1])total=total+(d<<<1);
            if(f[2])total=total+(d<<<2);if(f[3])total=total+(d<<<3);
            bin_interp=total>>>3;
        end
    endfunction
    reg [15:0] ht,hb;
    reg [23:0] vertical;
    wire signed [8:0] dt=$signed({1'b0,l10})-$signed({1'b0,l00});
    wire signed [8:0] db=$signed({1'b0,l11})-$signed({1'b0,l01});
    wire signed [18:0] it=$signed({3'd0,l00,8'd0})+dt*$signed({1'b0,wx_bin});
    wire signed [18:0] ib=$signed({3'd0,l01,8'd0})+db*$signed({1'b0,wx_bin});
    wire signed [16:0] vd=$signed({1'b0,hb})-$signed({1'b0,ht});
    wire signed [25:0] iv=$signed({2'd0,ht,8'd0})+vd*$signed({1'b0,wy1})+26'sd32768;
    wire signed [9:0] delta=($signed({2'd0,vertical[23:16]})-$signed({2'd0,gray2}))>>>1;
    function [7:0] apply_delta;
        input [7:0] channel;input signed [9:0] change;
        reg signed [10:0] value;
        begin value=$signed({3'd0,channel})+change;apply_delta=value<0?0:value>255?255:value[7:0];end
    endfunction
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin x<=0;y<=0;rgb0<=0;rgb_bin<=0;rgb1<=0;rgb2<=0;gray0<=0;gray_bin<=0;gray1<=0;gray2<=0;
            wx0<=0;wy0<=0;wx_bin<=0;wy_bin<=0;wy1<=0;ctl0<=0;ctl_bin<=0;ctl1<=0;ctl2<=0;l00<=0;l10<=0;l01<=0;l11<=0;ht<=0;hb<=0;vertical<=0;
            out_vsync<=0;out_hsync<=0;out_de<=0;out_sof<=0;out_eol<=0;out_rgb<=0;end
        else begin
            if(sof)begin x<=0;y<=0;end
            if(de)begin x<=eol?0:px+1'b1;y<=eol?py+1'b1:py;end
            rgb0<=rgb;gray0<=luma[9:2];wx0<=wx;wy0<=wy;
            ctl0<={enable&&selected_valid,vsync,hsync,de,sof,eol};
            l00<=bin_interp(gray0[7:3]==0?8'd0:p00,m00,fraction);l10<=bin_interp(gray0[7:3]==0?8'd0:p10,m10,fraction);
            l01<=bin_interp(gray0[7:3]==0?8'd0:p01,m01,fraction);l11<=bin_interp(gray0[7:3]==0?8'd0:p11,m11,fraction);
            wx_bin<=wx0;wy_bin<=wy0;rgb_bin<=rgb0;gray_bin<=gray0;ctl_bin<=ctl0;
            ht<=it[15:0];hb<=ib[15:0];wy1<=wy_bin;rgb1<=rgb_bin;gray1<=gray_bin;ctl1<=ctl_bin;
            vertical<=iv[23:0];rgb2<=rgb1;gray2<=gray1;ctl2<=ctl1;
            {out_vsync,out_hsync,out_de,out_sof,out_eol}<=ctl2[4:0];
            out_rgb<=!ctl2[2]?24'd0:!ctl2[5]?rgb2:
                {apply_delta(rgb2[23:16],delta),apply_delta(rgb2[15:8],delta),apply_delta(rgb2[7:0],delta)};
        end
    end
endmodule
