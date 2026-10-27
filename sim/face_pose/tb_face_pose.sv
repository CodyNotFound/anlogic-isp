`timescale 1ns/1ps
module tb_face_pose #(parameter REPORT_DIR="reports/face_pose");
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,frame_start=0,pixel_valid=0;reg [7:0] gray=0;
    wire ready,busy,result_valid,target_found;
    wire [7:0] target_x,target_y,target_size,target_votes;
    wire [8:0] target_center_x,target_center_y;
    wire [2:0] target_view;wire [31:0] cycles,feature_count;
    face_pose_snapshot dut(.*);
    reg [7:0] pixels[0:14399],rotated[0:14399];
    string name;
    integer ef,ex,ey,es,ecx,ecy,ev,view,features,views,fd,rc,i,timeout;
    integer sample_count=0,checked_views=0,current_view=-1;
    always @(negedge clk) if(rst_n && dut.core_pixel_valid)begin
        if(current_view!=dut.view)begin
            if(current_view!=-1 && sample_count!=14400)$fatal(1,"FAIL incomplete rotated view");
            current_view=dut.view;sample_count=0;checked_views=checked_views+1;
            $readmemh($sformatf("sim/face_pose/%s_view%0d.hex",name,current_view),rotated);
        end
        if(sample_count>=14400 || dut.core_gray!==rotated[sample_count])
            $fatal(1,"FAIL rotation %s view=%0d pixel=%0d got=%0d expected=%0d",name,current_view,sample_count,dut.core_gray,rotated[sample_count]);
        sample_count=sample_count+1;
    end
    initial begin
        if(!$value$plusargs("CASE=%s",name))$fatal(1,"Need +CASE=<fixture>");
        $readmemh({"sim/face_pose/",name,".hex"},pixels);
        fd=$fopen({"sim/face_pose/",name,".expected"},"r");
        rc=$fscanf(fd,"%d %d %d %d %d %d %d %d %d %d",ef,ex,ey,es,ecx,ecy,ev,view,features,views);$fclose(fd);
        if(rc!=10)$fatal(1,"FAIL expected file");
        repeat(4)@(negedge clk);rst_n=1;
        @(negedge clk);frame_start=1;@(negedge clk);frame_start=0;
        for(i=0;i<14400;i=i+1)begin
            if(i%37==0)begin pixel_valid=0;@(negedge clk);end
            pixel_valid=1;gray=pixels[i];@(negedge clk);
        end
        pixel_valid=0;
        // Busy-frame marker and input noise must not overwrite stored pixels.
        frame_start=1;pixel_valid=1;gray=255;repeat(4)@(negedge clk);frame_start=0;pixel_valid=0;
        timeout=0;
        while(!result_valid)begin
            @(negedge clk);timeout=timeout+1;
            if(timeout>70000000)$fatal(1,"FAIL pose watchdog");
        end
        if(target_found!==ef[0] || target_x!==ex || target_y!==ey || target_size!==es ||
           target_center_x!==ecx || target_center_y!==ecy || target_votes!==ev || target_view!==view || feature_count!==features)
            $fatal(1,"FAIL pose %s found=%0d box=%0d,%0d,%0d center=%0d,%0d votes=%0d view=%0d features=%0d",name,target_found,target_x,target_y,target_size,target_center_x,target_center_y,target_votes,target_view,feature_count);
        if(checked_views!=views || sample_count!=14400 || !ready || busy)$fatal(1,"FAIL view counts or ready");
        fd=$fopen({REPORT_DIR,"/",name,"_rtl.csv"},"w");
        $fdisplay(fd,"name,found,x,y,size,center_x,center_y,votes,view,features,cycles,views");
        $fdisplay(fd,"%s,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",name,target_found,target_x,target_y,target_size,target_center_x,target_center_y,target_votes,target_view,feature_count,cycles,checked_views);$fclose(fd);
        $display("PASS tb_face_pose %s box=%0d,%0d,%0d center=%0d,%0d view=%0d cycles=%0d",name,target_x,target_y,target_size,target_center_x,target_center_y,target_view,cycles);
        // Reset must also cancel an incomplete snapshot and clear all outputs.
        @(negedge clk);frame_start=1;@(negedge clk);frame_start=0;pixel_valid=1;
        repeat(8)@(negedge clk);rst_n=0;pixel_valid=0;@(negedge clk);rst_n=1;@(negedge clk);
        if(!ready || busy || result_valid || target_found)$fatal(1,"FAIL pose reset");
        $finish;
    end
endmodule
