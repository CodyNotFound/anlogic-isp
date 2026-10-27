`timescale 1ns/1ps
module tb_face_lbp #(
    parameter CASES_FILE="sim/face_lbp/cases.txt",
    parameter OUTPUT_FILE="reports/face_lbp/rtl_results.csv"
);
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,frame_start=0,pixel_valid=0,model_select=0;
    reg [7:0] gray=0;
    wire ready,busy,done,candidate_valid;
    wire [7:0] box_x,box_y,box_size;
    wire [8:0] center_x,center_y;
    wire [31:0] cycles,feature_count;
    face_lbp_core dut(.search_enable(1'b0),.search_x0(8'd0),.search_y0(8'd0),.search_x1(8'd0),.search_y1(8'd0),.search_scale_lo(4'd0),.search_scale_hi(4'd0),.*);
    wire result_valid,target_found,overflow;
    wire [7:0] target_x,target_y,target_size,target_votes;
    wire [8:0] target_center_x,target_center_y;
    wire accepted_start=frame_start && ready;
    face_candidate_select selector(.clk(clk),.rst_n(rst_n),.frame_start(accepted_start),.frame_done(done),
        .candidate_valid(candidate_valid),.box_x(box_x),.box_y(box_y),.box_size(box_size),
        .result_valid(result_valid),.target_found(target_found),.overflow(overflow),
        .target_x(target_x),.target_y(target_y),.target_size(target_size),.target_votes(target_votes),
        .target_center_x(target_center_x),.target_center_y(target_center_y));
    reg [7:0] pixels[0:14399];
    string name,filename;
    integer cases,case_index,model,count,received,fd,fc,fo,rc,i,x,y,w;
    integer cycle_timeout;
    integer ft,efound,eoverflow,ex,ey,ew,evotes,efeatures;
    bit checking=0;
    always @(negedge clk) if(checking && candidate_valid) begin
        rc=$fscanf(fd,"%d %d %d",x,y,w);
        if(rc!=3 || received>=count) $fatal(1,"FAIL extra candidate %s",name);
        if(box_x!==x || box_y!==y || box_size!==w)
            $fatal(1,"FAIL %s candidate %0d actual %0d %0d %0d expected %0d %0d %0d",name,received,box_x,box_y,box_size,x,y,w);
        if(center_x!==x+w/2 || center_y!==y+w/2) $fatal(1,"FAIL center");
        received=received+1;
    end
    initial begin
        fo=$fopen(OUTPUT_FILE,"w");
        $fdisplay(fo,"name,model,candidates,cycles,features,found,x,y,size,votes");
        fc=$fopen(CASES_FILE,"r");
        if(!fc || !fo) $fatal(1,"FAIL open fixture files; run from repo root");
        rc=$fscanf(fc,"%d",cases);
        repeat(3) @(negedge clk);
        rst_n=1;
        for(case_index=0;case_index<cases;case_index=case_index+1) begin
            rc=$fscanf(fc,"%s %d",name,model);
            if(rc!=2) $fatal(1,"FAIL cases manifest");
            filename={"sim/face_lbp/",name,".hex"};$readmemh(filename,pixels);
            filename={"sim/face_lbp/",name,".expected"};fd=$fopen(filename,"r");
            if(!fd) $fatal(1,"FAIL expected file");
            rc=$fscanf(fd,"%d",count);received=0;checking=1;
            ft=$fopen({"sim/face_lbp/",name,".target"},"r");
            rc=$fscanf(ft,"%d %d %d %d %d %d %d",efound,eoverflow,ex,ey,ew,evotes,efeatures);
            if(rc!=7) $fatal(1,"FAIL target fixture");
            $fclose(ft);
            @(negedge clk);
            if(!ready) $fatal(1,"FAIL ready");
            frame_start=1;model_select=model;
            @(negedge clk);frame_start=0;
            for(i=0;i<14400;i=i+1) begin
                // Exercise gaps in valid, including row and integral boundaries.
                if(i%37==0) begin pixel_valid=0;@(negedge clk);end
                pixel_valid=1;gray=pixels[i];@(negedge clk);
            end
            pixel_valid=0;
            // A new frame while busy must NOT corrupt the current snapshot.
            frame_start=1;model_select=1-model;
            @(negedge clk);frame_start=0;
            cycle_timeout=0;
            while(!done) begin
                @(negedge clk);cycle_timeout=cycle_timeout+1;
                if(cycle_timeout>50000000) $fatal(1,"FAIL watchdog %s",name);
            end
            checking=0;
            if(received!=count) $fatal(1,"FAIL missing candidates %s actual=%0d expected=%0d",name,received,count);
            if(!ready || busy) $fatal(1,"FAIL done/ready");
            while(!result_valid) @(negedge clk);
            if(!result_valid || target_found!==efound[0] || overflow!==eoverflow[0] || target_x!==ex || target_y!==ey || target_size!==ew || target_votes!==evotes || feature_count!==efeatures)
                $fatal(1,"FAIL selector/features %s got found=%0d box=%0d,%0d,%0d votes=%0d",name,target_found,target_x,target_y,target_size,target_votes);
            $display("PASS %s model=%0d candidates=%0d cycles=%0d features=%0d target=%0d (%0d,%0d,%0d) votes=%0d",name,model,received,cycles,feature_count,target_found,target_x,target_y,target_size,target_votes);
            $fdisplay(fo,"%s,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",name,model,received,cycles,feature_count,target_found,target_x,target_y,target_size,target_votes);
            $fclose(fd);
        end
        // Reset must immediately cancel a partially captured frame.
        @(negedge clk);frame_start=1;
        @(negedge clk);frame_start=0;pixel_valid=1;gray=255;
        repeat(9) @(negedge clk);
        rst_n=0;pixel_valid=0;
        @(negedge clk);rst_n=1;
        @(negedge clk);
        if(!ready || busy || done || candidate_valid) $fatal(1,"FAIL reset abort");
        $fclose(fc);$fclose(fo);
        $display("PASS ALL LBP RTL fixtures, gaps, busy-frame rejection, reset");
        $finish;
    end
endmodule
