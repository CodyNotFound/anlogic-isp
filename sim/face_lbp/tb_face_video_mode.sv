`timescale 1ns/1ps
module tb_face_video_mode #(
    parameter integer CASE_START=0,CASE_END=4,
    parameter OUTPUT_DIR="reports/face_lbp"
);
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,enable=0,sof=0,eol=0,de=0;
    reg [23:0] rgb=0;
    wire position_valid,found,busy,stream_error,timeout_error;
    wire [11:0] box_x,box_y,box_size,center_x,center_y;
    wire [31:0] accepted_frames,completed_frames;
    face_video_position dut(.*);
    reg [7:0] image[0:14399];
    reg [23:0] native_rgb[0:921599];
    integer x,y,i,n,fd,case_id,rc,expected_found,ex,ey,ew,votes,ov,features;
    integer sample_count,wait_cycles,render_fd,ix0,iy0,ix1,iy1,intersection,union_area;
    wire ov_vsync,ov_hsync,ov_de,ov_sof,ov_eol;
    wire [23:0] ov_rgb;
    reg render=0;
    face_position_overlay display_box(.clk(clk),.rst_n(rst_n),.enable(enable),
        .vsync(1'b0),.hsync(1'b0),.de(de),.sof(sof),.eol(eol),.rgb(rgb),.found(found),
        .box_x(box_x),.box_y(box_y),.box_size(box_size),.center_x(center_x),.center_y(center_y),
        .out_vsync(ov_vsync),.out_hsync(ov_hsync),.out_de(ov_de),.out_sof(ov_sof),.out_eol(ov_eol),.out_rgb(ov_rgb));
    always @(posedge clk) begin
        #1;if(render && ov_de)$fwrite(render_fd,"%c%c%c",ov_rgb[23:16],ov_rgb[15:8],ov_rgb[7:0]);
    end
    reg checking=0;
    string name;
    // Every downsampled pixel is checked, not just the final target box.
    always @(negedge clk) if(checking && dut.sample_valid) begin
        if(sample_count>=14400 || dut.sample_gray!==image[sample_count])
            $fatal(1,"FAIL downsample %s sample %0d got %0d expected %0d",name,sample_count,dut.sample_gray,image[sample_count]);
        sample_count=sample_count+1;
    end
    task send_frame;
        input integer kind; // 0=replicate fixture, 1=average/rounding probe, 2=busy noise
        integer value,xx,yy;
        begin
            for(yy=0;yy<720;yy=yy+1) begin
                for(xx=0;xx<1280;xx=xx+1) begin
                    @(negedge clk);
                    sof=(xx==0 && yy==0);eol=(xx==1279);de=1;
                    if(kind==1) begin
                        // Distinct RGB; each block sums 64*62+32 -> rounds to 63.
                        value=(yy%8<4) ? 0 : 4;
                        rgb={8'd40,8'd64,8'd80+value[7:0]};
                    end else if(kind==2) rgb=24'hff0080;
                    else if(kind==3) rgb=native_rgb[yy*1280+xx];
                    else begin value=image[(yy/8)*160+xx/8];rgb={3{value[7:0]}};end
                end
                @(negedge clk);de=0;eol=0;sof=0;
                repeat(2) @(negedge clk);
            end
            @(negedge clk);de=0;sof=0;eol=0;
        end
    endtask
    initial begin
        fd=$fopen({OUTPUT_DIR,"/video_mode_rtl.csv"},"w");
        $fdisplay(fd,"name,found,x,y,size,center_x,center_y,samples");
        repeat(4) @(negedge clk);rst_n=1;enable=1;
        // Verify actual RGB->gray, spatial summation and rounding on all blocks.
        name="rgb_average";for(i=0;i<14400;i=i+1)image[i]=63;
        sample_count=0;checking=1;send_frame(1);repeat(5)@(negedge clk);checking=0;
        if(sample_count!=14400)$fatal(1,"FAIL average sample count");
        enable=0;repeat(3)@(negedge clk);enable=1;
        for(case_id=CASE_START;case_id<CASE_END;case_id=case_id+1) begin
            case(case_id) 0:name="photo_left";1:name="photo_right";2:name="fruits_negative";3:name="lena_video";endcase
            if(case_id==3)begin
                $readmemh("sim/face_lbp/lena_video_rgb.hex",native_rgb);
                $readmemh("sim/face_lbp/lena_video_gray.hex",image);
            end else $readmemh({"sim/face_lbp/",name,".hex"},image);
            n=$fopen({"sim/face_lbp/",name,".target"},"r");
            rc=$fscanf(n,"%d %d %d %d %d %d %d",expected_found,ov,ex,ey,ew,votes,features);$fclose(n);
            if(rc!=7)$fatal(1,"FAIL target fixture");
            sample_count=0;checking=1;send_frame(case_id==3?3:0);repeat(5)@(negedge clk);checking=0;
            if(sample_count!=14400)$fatal(1,"FAIL sample count");
            if(case_id==0) begin
                n=accepted_frames;send_frame(2);
                if(accepted_frames!=n)$fatal(1,"FAIL busy frame was captured");
            end
            wait_cycles=0;
            while(!position_valid) begin
                @(negedge clk);wait_cycles=wait_cycles+1;
                if(wait_cycles>70000000)$fatal(1,"FAIL detector timeout");
            end
            // New targets require a second independent captured frame. Keep
            // the first detector result observable, then validate confirmation
            // through the actual RGB sampler and LBP cascade (no forced box).
            if(expected_found && !found)begin
                repeat(5)@(negedge clk);
                send_frame(case_id==3?3:0);
                wait_cycles=0;
                while(!position_valid)begin
                    @(negedge clk);wait_cycles=wait_cycles+1;
                    if(wait_cycles>70000000)$fatal(1,"FAIL confirmation timeout");
                end
            end
            if(found!==expected_found[0])$fatal(1,"FAIL position validity %s",name);
            if(expected_found)begin
                // Local scale restriction may select a neighboring accepted
                // window. Check overlap against the unchanged full-scan box,
                // rather than requiring an incidental first-anchor coordinate.
                ix0=box_x>ex*8?box_x:ex*8;iy0=box_y>ey*8?box_y:ey*8;
                ix1=box_x+box_size<(ex+ew)*8?box_x+box_size:(ex+ew)*8;
                iy1=box_y+box_size<(ey+ew)*8?box_y+box_size:(ey+ew)*8;
                intersection=(ix1>ix0&&iy1>iy0)?(ix1-ix0)*(iy1-iy0):0;
                union_area=box_size*box_size+ew*ew*64-intersection;
                if(intersection*2<union_area)$fatal(1,"FAIL confirmation box IoU < 0.5 %s",name);
                if(center_x!=box_x+box_size/2||center_y!=box_y+box_size/2)$fatal(1,"FAIL center map");
            end
            if(stream_error || timeout_error)$fatal(1,"FAIL unexpected stream error");
            $fdisplay(fd,"%s,%0d,%0d,%0d,%0d,%0d,%0d,%0d",name,found,box_x,box_y,box_size,center_x,center_y,sample_count);
            $display("PASS video mode %s: found=%0d box=%0d,%0d,%0d center=%0d,%0d",name,found,box_x,box_y,box_size,center_x,center_y);
            repeat(4)@(negedge clk);
        end
        // Export the actual registered RTL overlay, rather than redrawing a
        // predicted box in Python. This is simulation output, not a board photo.
        render_fd=$fopen({OUTPUT_DIR,"/lena_video_rtl.ppm"},"wb");
        $fwrite(render_fd,"P6\n1280 720\n255\n");render=1;
        send_frame(3);repeat(3)@(negedge clk);render=0;$fclose(render_fd);
        // Malformed short row aborts capture. Next complete frame can recover.
        @(negedge clk);sof=1;de=1;eol=0;rgb=0;
        @(negedge clk);sof=0;eol=1;
        @(negedge clk);eol=0;de=0;
        repeat(5)@(negedge clk);
        if(!stream_error || found || busy)$fatal(1,"FAIL malformed frame not aborted");
        // Disabling while busy clears stale observations and returns idle.
        @(negedge clk);sof=1;
        @(negedge clk);sof=0;de=1;
        repeat(15)@(negedge clk);enable=0;de=0;
        repeat(4)@(negedge clk);
        if(found || position_valid || busy)$fatal(1,"FAIL mode exit reset");
        $fclose(fd);$display("PASS tb_face_video_mode: RGB averaging, cases %0d..%0d, native RGB input, coordinates, stream abort, exit",CASE_START,CASE_END-1);$finish;
    end
endmodule
