// All analytics observe clean ISP pixels; video never waits for analytics.
module vision_task_suite #(parameter WIDTH=1280,HEIGHT=720,RESULT_TTL=15000000,HUD_TEXT_ENABLE=1,SHARED_TRACK_FRAME=0)(
    input wire clk,rst_n,enabled,action,
    input wire [3:0] mode,
    input wire source_sof,source_eol,source_de,
    input wire [23:0] source_rgb,
    input wire vsync,hsync,de,sof,eol,
    input wire [23:0] rgb,
    output wire out_vsync,out_hsync,out_de,out_sof,out_eol,
    output wire [23:0] out_rgb,
    output wire target_valid,target_found,output wire [7:0] target_x,target_y,
    input wire manual_mode,osd_enable,
    output wire [3:0] hud_status,
    output wire shared_write_en,output wire [14:0] shared_write_addr,shared_read_addr,
    output wire [7:0] shared_write_data,input wire [7:0] shared_read_data,input wire [31:0] shared_read_word,output wire [31:0] target_compute_cycles
);
    wire tracking=enabled && mode==12,region=enabled && mode==14;
    wire fs,sv,fe,abort;
    wire [7:0] sx,sy,gray;
    wire [23:0] srgb;
    vision_rgb_sampler #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) sampler(
        .clk(clk),.rst_n(rst_n),.enable(tracking||region),.sof(source_sof),.eol(source_eol),.de(source_de),.rgb(source_rgb),
        .frame_start(fs),.sample_valid(sv),.frame_end(fe),.frame_error(abort),.sample_x(sx),.sample_y(sy),.sample_rgb(srgb),.sample_gray(gray));
    wire tv,tf,rv,rf,rc,ro,picking;wire [31:0] tracker_cycles,region_cycles;
    assign target_compute_cycles=tracking?tracker_cycles:region?region_cycles:32'd0;
    wire [7:0] tx,ty,tq,rx,ry,rw,rh,rcx,rcy;
    wire [14:0] ra;
    wire [1:0] t_lost;
    wire twrite,rwrite;wire [14:0] twaddr,traddr;wire [14:0] rwaddr,rraddr;
    wire [7:0] twdata,rwdata;
    assign shared_write_en=tracking?twrite:region?rwrite:1'b0;
    assign shared_write_addr=tracking?twaddr:rwaddr;
    assign shared_read_addr=tracking?traddr:rraddr;
    assign shared_write_data=tracking?twdata:rwdata;
    vision_sad_tracker #(.WIDTH(WIDTH/8),.HEIGHT(HEIGHT/8),.SCALE_ENABLE(1),.RECOVERY_FRAMES(3),.EXTERNAL_FRAME(SHARED_TRACK_FRAME),.EXTERNAL_TEMPLATES(SHARED_TRACK_FRAME),.EXTERNAL_SCORES(SHARED_TRACK_FRAME)) tracker(
        .clk(clk),.rst_n(rst_n&&tracking&&!abort),.reseed(action),.frame_start(fs),.sample_valid(sv),.frame_end(fe),.gray(gray),
        .result_valid(tv),.found(tf),.center_x(tx),.center_y(ty),.quality(tq),.best_sad(),.second_sad(),.busy(),.compute_cycles(tracker_cycles),
        .lost_stage(t_lost),.shared_write_en(twrite),.shared_write_addr(twaddr),
        .shared_read_addr(traddr),.shared_write_data(twdata),.shared_read_data(shared_read_data),.shared_read_word(shared_read_word));
    vision_color_region #(.WIDTH(WIDTH/8),.HEIGHT(HEIGHT/8),.EXTERNAL_QUEUE(SHARED_TRACK_FRAME)) segmenter(
        .clk(clk),.rst_n(rst_n&&region),.reseed(action),.frame_start(fs),.sample_valid(sv),.frame_end(fe),.frame_abort(abort),
        .sample_x(sx),.sample_y(sy),.rgb(srgb),.result_valid(rv),.calibrated(rc),.found(rf),.overflow(ro),
        .box_x(rx),.box_y(ry),.box_w(rw),.box_h(rh),.center_x(rcx),.center_y(rcy),.area(ra),.busy(),.compute_cycles(region_cycles),.pick_pending(picking),
        .shared_write_en(rwrite),.shared_write_addr(rwaddr),.shared_read_addr(rraddr),.shared_write_data(rwdata),.shared_read_data(shared_read_data));
    reg [23:0] age;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)age<=RESULT_TTL;
        else if(!(tracking||region)||abort||action)age<=RESULT_TTL;
        else if(tv||rv)age<=0;
        else if(age<RESULT_TTL)age<=age+1'b1;
    end
    wire valid=age<RESULT_TTL;
    // Compact compositor status. These are states, not classifier confidence.
    assign hud_status=tracking ? (valid&&tf ? 4'd1 : t_lost!=0 ? 4'd6 : 4'd2) :
        region ? (manual_mode ? 4'd7 : picking ? 4'd3 : ro ? 4'd5 : !rc ? 4'd4 :
                  valid&&rf ? 4'd1 : 4'd2) : 4'd0;
    assign target_valid=(tracking && tv) || (region && rv);
    assign target_found=!abort && !action && (tracking?((valid || tv) && tf):region && (valid || rv) && rc && rf && !ro);
    assign target_x=tracking?tx:rcx;assign target_y=tracking?ty:rcy;
    wire [11:0] bx=tracking?{1'b0,tx-8'd8,3'd0}:{1'b0,rx,3'd0};
    wire [11:0] by=tracking?{1'b0,ty-8'd8,3'd0}:{1'b0,ry,3'd0};
    wire cv,ch,cd,cs,ce;
    wire [23:0] cp;
    // Local histogram enhancement retired from the application. Preserve the
    // standalone reference module for historical comparisons, not runtime use.
    assign {cv,ch,cd,cs,ce,cp}={vsync,hsync,de,sof,eol,rgb};
    vision_task_hud #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.TEXT_ENABLE(HUD_TEXT_ENABLE)) hud(
        .clk(clk),.rst_n(rst_n),.mode(mode),.enable((tracking||region)&&osd_enable),.result_valid(tv||rv),
        .found(valid&&(tracking?tf:rf)),.calibrated(tracking?1'b1:rc),.overflow(region&&ro),
        .lost(tracking?t_lost:2'd0),
        .box_x(bx),.box_y(by),.box_w(tracking?12'd128:{1'b0,rw,3'd0}),.box_h(tracking?12'd128:{1'b0,rh,3'd0}),
        .center_x(tracking?{1'b0,tx,3'd0}:{1'b0,rcx,3'd0}),.center_y(tracking?{1'b0,ty,3'd0}:{1'b0,rcy,3'd0}),
        .metric(tracking?{12'd0,tq}:{ra[13:0],6'd0}),
        .vsync(cv),.hsync(ch),.de(cd),.sof(cs),.eol(ce),.rgb(cp),
        .out_vsync(out_vsync),.out_hsync(out_hsync),.out_de(out_de),.out_sof(out_sof),.out_eol(out_eol),.out_rgb(out_rgb),
        .pick_pending(region && picking),.manual_mode(manual_mode));
endmodule
