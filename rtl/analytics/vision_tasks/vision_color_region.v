// Picked chroma direction is invariant to uniform gain and neutral highlights.
// Low-chroma picks retain a luminance gate. Majority + exact 4-connected fill.
// Loss retains the color, expands the local search, then requires two unique
// consistent global candidates before reacquisition. Ambiguity never steers.
(* dsp_style="no" *) module vision_color_region #(
    parameter WIDTH=160,HEIGHT=90,MIN_AREA=12,MAX_AREA=WIDTH*HEIGHT/2,
    parameter QUEUE_CAPACITY=WIDTH*HEIGHT,
    parameter ASSOCIATION=1,MAX_STEP=16
)(
    input wire clk,rst_n,reseed,frame_start,sample_valid,frame_end,
    input wire [7:0] sample_x,sample_y,
    input wire [23:0] rgb,
    output reg result_valid,calibrated,found,overflow,
    output reg [7:0] box_x,box_y,box_w,box_h,center_x,center_y,
    output reg [14:0] area,
    output wire busy,
    output reg [31:0] compute_cycles,output wire pick_pending,input wire frame_abort
);
    localparam N=WIDTH*HEIGHT;
    localparam IDLE=0,CAPTURE=1,CALIBRATE=2,CLEAN_REQ=3,CLEAN_WAIT=4,CLEAN_READ=5,CLEAN_STORE=6,
        SCAN_REQ=7,SCAN_WAIT=8,SCAN_CHECK=9,POP_REQ=10,POP_WAIT=11,POP=12,
        NEIGH_REQ=13,NEIGH_WAIT=14,NEIGH_CHECK=15,NODE_DONE=16,COMP_DONE=17,
        SCAN_NEXT=18,FINAL=19,DIV_X=20,DIV_Y_START=21,DIV_Y=22,
        CAL_R=23,CAL_B=24,CAL_Y=25,CAL_U=26,CAL_V=27,DRAIN=28;
    reg [4:0] state;
    reg seed_pending,seeding;
    reg [13:0] capture_addr,scan_addr,raw_addr,work_addr,queue_addr;
    (* ram_style="bram" *) reg raw_mask[0:N-1],work_mask[0:N-1];
    localparam QDEPTH=1<<$clog2(QUEUE_CAPACITY);
    (* ram_style="bram" *) reg [14:0] queue[0:QDEPTH-1];
    reg raw_q,work_q;
    reg [14:0] queue_q,head,tail;
    reg [7:0] scan_x,scan_y,cur_x,cur_y;
    reg [3:0] tap,count9;
    reg [1:0] neighbor;
    reg [11:0] sum_r,sum_g,sum_b;
    reg [3:0] seed_count;
    reg signed [8:0] seed_rg,seed_bg,min_rg,max_rg,min_bg,max_bg;
    reg [8:0] tolerance;
    wire signed [8:0] rg=$signed({1'b0,rgb[23:16]})-$signed({1'b0,rgb[15:8]});
    wire signed [8:0] bg=$signed({1'b0,rgb[7:0]})-$signed({1'b0,rgb[15:8]});
    wire signed [9:0] dr=$signed({rg[8],rg})-$signed({seed_rg[8],seed_rg});
    wire signed [9:0] db=$signed({bg[8],bg})-$signed({seed_bg[8],seed_bg});
    wire [9:0] adr=dr[9]?-dr:dr,adb=db[9]?-db:db;
    wire [10:0] distance={1'b0,adr}+{1'b0,adb};
    wire [9:0] luma={2'd0,rgb[23:16]}+{1'b0,rgb[15:8],1'b0}+{2'd0,rgb[7:0]};
    reg seed_neutral;
    reg [9:0] seed_luma;
    wire [13:0] patch_luma={2'b0,sum_r}+{1'b0,sum_g,1'b0}+{2'b0,sum_b};
    wire [9:0] luma_delta=luma>=seed_luma?luma-seed_luma:seed_luma-luma;
    reg signed [4:0] seed_u,seed_v;
    wire [8:0] arg=rg[8]?-rg:rg,abg=bg[8]?-bg:bg;
    wire [8:0] chroma=arg>abg?arg:abg;
    reg signed [8:0] f_rg,f_bg;
    reg [8:0] f_chroma;
    reg f_guard,f_neutral,f_valid,g_guard,g_neutral,g_valid;
    reg [13:0] f_addr,g_addr,g_abs_r,g_abs_b;
    reg [9:0] g_limit;
    // Signed five-bit coefficients, implemented without DSPs. Q3 hue cone.
    wire signed [13:0] hue_r=($signed({{5{f_rg[8]}},f_rg})<<<3)-seed_u*$signed({1'b0,f_chroma});
    wire signed [13:0] hue_b=($signed({{5{f_bg[8]}},f_bg})<<<3)-seed_v*$signed({1'b0,f_chroma});
    wire [13:0] ahr=hue_r[13]?-hue_r:hue_r,ahb=hue_b[13]?-hue_b:hue_b;
    wire [14:0] hue_error={1'b0,g_abs_r}+{1'b0,g_abs_b};
    wire selected=seed_neutral?g_neutral:(g_guard && hue_error<={5'd0,g_limit});
    assign pick_pending=seed_pending || (state==CAPTURE && seeding) || state==CALIBRATE;
    wire seed_pixel=sample_x>=WIDTH/2-1 && sample_x<=WIDTH/2+1 && sample_y>=HEIGHT/2-1 && sample_y<=HEIGHT/2+1;
    wire signed [12:0] sr=$signed({1'b0,sum_r})-$signed({1'b0,sum_g});
    wire signed [12:0] sb=$signed({1'b0,sum_b})-$signed({1'b0,sum_g});
    wire [12:0] asr=sr[12]?-sr:sr,asb=sb[12]?-sb:sb;
    wire [12:0] seed_chroma=asr>asb?asr:asb;
    wire [11:0] spread=24+($signed({max_rg[8],max_rg})-$signed({min_rg[8],min_rg}))+
                                  ($signed({max_bg[8],max_bg})-$signed({min_bg[8],min_bg}));
    reg signed [9:0] clean_x,clean_y,nx,ny;
    wire clean_valid=clean_x>=0 && clean_x<WIDTH && clean_y>=0 && clean_y<HEIGHT;
    wire neighbor_valid=nx>=0 && nx<WIDTH && ny>=0 && ny<HEIGHT;
    wire [13:0] neighbor_addr=ny*WIDTH+nx;
    wire queue_seed=state==SCAN_CHECK && work_q;
    wire queue_push=state==NEIGH_CHECK && neighbor_valid && work_q && tail<QUEUE_CAPACITY;
    wire [13:0] queue_write_addr=queue_seed?14'd0:tail[13:0];
    wire [14:0] queue_write_data=queue_seed?{scan_y[6:0],scan_x}:{ny[6:0],nx[7:0]};
    always @* begin
        clean_x=$signed({2'd0,scan_x});clean_y=$signed({2'd0,scan_y});
        case(tap)
            0:begin clean_x=clean_x-1;clean_y=clean_y-1;end
            1:clean_y=clean_y-1;
            2:begin clean_x=clean_x+1;clean_y=clean_y-1;end
            3:clean_x=clean_x-1;
            5:clean_x=clean_x+1;
            6:begin clean_x=clean_x-1;clean_y=clean_y+1;end
            7:clean_y=clean_y+1;
            8:begin clean_x=clean_x+1;clean_y=clean_y+1;end
            default:begin end
        endcase
        nx=$signed({2'd0,cur_x});ny=$signed({2'd0,cur_y});
        case(neighbor)0:nx=nx-1;1:nx=nx+1;2:ny=ny-1;3:ny=ny+1;endcase
    end
    reg [14:0] component_count,best_count;
    reg [7:0] min_x,min_y,max_x,max_y,best_min_x,best_min_y,best_max_x,best_max_y;
    reg locked,component_seed,best_ambiguous;
    reg [3:0] lost_frames;
    reg reacq_pending;
    reg [7:0] reacq_x,reacq_y;
    reg [14:0] reacq_area;
    wire global_reacq=locked && lost_frames>=3;
    wire [8:0] search_step=MAX_STEP+({5'd0,lost_frames}>6?9'd48:({5'd0,lost_frames}<<3));
    reg [14:0] locked_area;
    reg [8:0] best_distance;
    wire [8:0] midpoint_x=({1'b0,min_x}+{1'b0,max_x})>>1;
    wire [8:0] midpoint_y=({1'b0,min_y}+{1'b0,max_y})>>1;
    wire [8:0] delta_x=midpoint_x>=center_x?midpoint_x-center_x:center_x-midpoint_x;
    wire [8:0] delta_y=midpoint_y>=center_y?midpoint_y-center_y:center_y-midpoint_y;
    wire [9:0] association_distance={1'b0,delta_x}+{1'b0,delta_y};
    wire association_ok=!ASSOCIATION || (!locked?component_seed:
        ((global_reacq || (delta_x<=search_step && delta_y<=search_step)) &&
         {2'b0,component_count}>=({2'b0,locked_area}>>2) &&
         {2'b0,component_count}<=({2'b0,locked_area}<<2)));
    wire [8:0] best_mid_x=({1'b0,best_min_x}+{1'b0,best_max_x})>>1;
    wire [8:0] best_mid_y=({1'b0,best_min_y}+{1'b0,best_max_y})>>1;
    wire [8:0] reacq_dx=best_mid_x>=reacq_x?best_mid_x-reacq_x:reacq_x-best_mid_x;
    wire [8:0] reacq_dy=best_mid_y>=reacq_y?best_mid_y-reacq_y:reacq_y-best_mid_y;
    wire reacq_consistent=reacq_pending && reacq_dx<=MAX_STEP && reacq_dy<=MAX_STEP &&
        {1'b0,best_count}>=({1'b0,reacq_area}>>1) && {1'b0,best_count}<=({1'b0,reacq_area}<<1);
    reg [23:0] sum_x,sum_y,best_sum_x,best_sum_y;
    reg div_start;
    reg [23:0] numerator,denominator;
    wire div_done;
    wire [23:0] quotient;
    vision_unsigned_divider #(.W(24)) divider(.clk(clk),.rst_n(rst_n),.start(div_start),
        .numerator(numerator),.denominator(denominator),.busy(),.done(div_done),.quotient(quotient));
    assign busy=state!=IDLE;
    // Three timing stages: RGB differences/chroma; hue products/residuals;
    // residual sum/comparison and RAM write. One input sample per clock.
    // The delayed valid/address travel with the same pixel across both cuts.
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            f_rg<=0;f_bg<=0;f_chroma<=0;f_guard<=0;f_neutral<=0;f_valid<=0;f_addr<=0;
            g_abs_r<=0;g_abs_b<=0;g_guard<=0;g_neutral<=0;g_valid<=0;g_addr<=0;g_limit<=0;
        end else begin
            f_rg<=rg;f_bg<=bg;f_chroma<=chroma;f_addr<=capture_addr;
            f_guard<=luma>=64 && luma<=980 && chroma>=12 && {5'd0,chroma}>={4'd0,luma[9:4]};
            f_neutral<=luma>=64 && luma<=980 && distance<=tolerance && luma_delta<=128;
            f_valid<=state==CAPTURE && sample_valid && !seeding && !reseed && !frame_abort;
            g_abs_r<=ahr;g_abs_b<=ahb;g_addr<=f_addr;g_guard<=f_guard;g_neutral<=f_neutral;
            g_limit<=({1'b0,f_chroma}<<1)+10'd48;
            g_valid<=f_valid && !reseed && !frame_abort;
        end
    end
    always @(posedge clk)begin
        raw_q<=raw_mask[raw_addr];work_q<=work_mask[work_addr];queue_q<=queue[queue_addr];
        if(g_valid && !reseed && !frame_abort)raw_mask[g_addr]<=selected;
        if(state==CLEAN_STORE)work_mask[scan_addr]<=count9>=5;
        else if(state==SCAN_CHECK && work_q)work_mask[scan_addr]<=0;
        else if(state==NEIGH_CHECK && neighbor_valid && work_q && tail<QUEUE_CAPACITY)work_mask[neighbor_addr]<=0;
        // One physical write port. A separate constant-address assignment for
        // queue[0] makes TD expand this large queue into flip-flops.
        if(queue_seed || queue_push)queue[queue_write_addr]<=queue_write_data;
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin state<=IDLE;seed_pending<=1;seeding<=0;capture_addr<=0;scan_addr<=0;raw_addr<=0;work_addr<=0;queue_addr<=0;
            seed_neutral<=0;seed_luma<=0;locked<=0;locked_area<=0;
            seed_u<=0;seed_v<=0;lost_frames<=0;reacq_pending<=0;reacq_x<=0;reacq_y<=0;reacq_area<=0;
            component_seed<=0;best_distance<=511;best_ambiguous<=0;
            head<=0;tail<=0;scan_x<=0;scan_y<=0;cur_x<=0;cur_y<=0;tap<=0;count9<=0;neighbor<=0;
            sum_r<=0;sum_g<=0;sum_b<=0;seed_count<=0;seed_rg<=0;seed_bg<=0;min_rg<=255;min_bg<=255;max_rg<=-255;max_bg<=-255;tolerance<=24;
            component_count<=0;best_count<=0;sum_x<=0;sum_y<=0;best_sum_x<=0;best_sum_y<=0;
            min_x<=0;min_y<=0;max_x<=0;max_y<=0;best_min_x<=0;best_min_y<=0;best_max_x<=0;best_max_y<=0;
            div_start<=0;numerator<=0;denominator<=1;result_valid<=0;calibrated<=0;found<=0;overflow<=0;
            box_x<=0;box_y<=0;box_w<=0;box_h<=0;center_x<=0;center_y<=0;area<=0;compute_cycles<=0;end
        else begin
            result_valid<=0;div_start<=0;
            if(state>CAPTURE)compute_cycles<=compute_cycles+1'b1;
            if(reseed)begin state<=IDLE;seed_pending<=1;calibrated<=0;found<=0;area<=0;overflow<=0;locked<=0;lost_frames<=0;reacq_pending<=0;end
            else if(frame_abort)begin
                // Drop a partial image, retain the selected color and pose.
                state<=IDLE;found<=0;area<=0;overflow<=0;result_valid<=1;reacq_pending<=0;
                if(locked)lost_frames<=3;
            end else case(state)
                IDLE:if(frame_start && (seed_pending || calibrated))begin
                    state<=CAPTURE;capture_addr<=0;seeding<=seed_pending;overflow<=0;sum_r<=0;sum_g<=0;sum_b<=0;seed_count<=0;
                    min_rg<=255;min_bg<=255;max_rg<=-255;max_bg<=-255;
                end
                CAPTURE:if(sample_valid)begin
                    if(seeding && seed_pixel)begin
                        sum_r<=sum_r+rgb[23:16];sum_g<=sum_g+rgb[15:8];sum_b<=sum_b+rgb[7:0];seed_count<=seed_count+1'b1;
                        if(rg<min_rg)min_rg<=rg;if(rg>max_rg)max_rg<=rg;
                        if(bg<min_bg)min_bg<=bg;if(bg>max_bg)max_bg<=bg;
                    end
                    if(capture_addr==N-1 && frame_end)begin
                        compute_cycles<=0;
                        if(seeding)state<=CALIBRATE;
                        else begin scan_addr<=0;scan_x<=0;scan_y<=0;tap<=0;count9<=0;best_count<=0;best_distance<=511;best_ambiguous<=0;state<=DRAIN;end
                    end else capture_addr<=capture_addr+1'b1;
                end
                CALIBRATE:begin
                    // Reuse the existing centroid divider for calibration.
                    // Signed chroma means truncate toward zero, as before.
                    // No three parallel /9 networks on the hardware datapath.
                    seed_neutral<=asr+asb<360;tolerance<=spread>96?96:spread;
                    numerator<={11'd0,asr};denominator<=24'd9;div_start<=1;
                    found<=0;area<=0;state<=CAL_R;
                end
                CAL_R:if(div_done)begin
                    seed_rg<=sr[12]?-$signed(quotient[8:0]):$signed(quotient[8:0]);
                    numerator<={11'd0,asb};div_start<=1;state<=CAL_B;
                end
                CAL_B:if(div_done)begin
                    seed_bg<=sb[12]?-$signed(quotient[8:0]):$signed(quotient[8:0]);
                    numerator<={10'd0,patch_luma};div_start<=1;state<=CAL_Y;
                end
                CAL_Y:if(div_done)begin
                    seed_luma<=quotient[9:0];
                    // Reject mixed foreground/background picks rather than
                    // silently broadening the color gate to the whole scene.
                    if(seed_neutral)begin
                        seed_pending<=0;calibrated<=seed_count==9 && patch_luma>=576 && patch_luma<=8820 && spread<=120;
                        result_valid<=1;state<=IDLE;
                    end else begin
                        numerator<=({11'd0,asr}<<3)+{12'd0,seed_chroma[12:1]};
                        denominator<={11'd0,seed_chroma};div_start<=1;state<=CAL_U;
                    end
                end
                CAL_U:if(div_done)begin
                    seed_u<=sr[12]?-$signed(quotient[4:0]):$signed(quotient[4:0]);
                    numerator<=({11'd0,asb}<<3)+{12'd0,seed_chroma[12:1]};div_start<=1;state<=CAL_V;
                end
                CAL_V:if(div_done)begin
                    seed_v<=sb[12]?-$signed(quotient[4:0]):$signed(quotient[4:0]);seed_pending<=0;
                    calibrated<=seed_count==9 && patch_luma>=576 && patch_luma<=8820 && spread<=120;
                    result_valid<=1;state<=IDLE;
                end
                DRAIN:state<=CLEAN_REQ; // finish the last two mask writes first
                CLEAN_REQ:begin raw_addr<=clean_valid?clean_y*WIDTH+clean_x:0;state<=CLEAN_WAIT;end
                CLEAN_WAIT:state<=CLEAN_READ;
                CLEAN_READ:begin
                    count9<=count9+(clean_valid && raw_q?1'b1:1'b0);
                    if(tap==8)state<=CLEAN_STORE;else begin tap<=tap+1'b1;state<=CLEAN_REQ;end
                end
                CLEAN_STORE:begin
                    tap<=0;count9<=0;
                    if(scan_addr==N-1)begin scan_addr<=0;scan_x<=0;scan_y<=0;state<=SCAN_REQ;end
                    else begin
                        scan_addr<=scan_addr+1'b1;
                        if(scan_x==WIDTH-1)begin scan_x<=0;scan_y<=scan_y+1'b1;end else scan_x<=scan_x+1'b1;
                        state<=CLEAN_REQ;
                    end
                end
                SCAN_REQ:begin work_addr<=scan_addr;state<=SCAN_WAIT;end
                SCAN_WAIT:state<=SCAN_CHECK;
                SCAN_CHECK:if(work_q)begin
                    head<=0;tail<=1;component_count<=0;component_seed<=0;sum_x<=0;sum_y<=0;min_x<=255;min_y<=255;max_x<=0;max_y<=0;state<=POP_REQ;
                end else state<=SCAN_NEXT;
                POP_REQ:begin queue_addr<=head[13:0];state<=POP_WAIT;end
                POP_WAIT:state<=POP;
                POP:begin
                    if(queue_q[7:0]>=WIDTH/2-1 && queue_q[7:0]<=WIDTH/2+1 &&
                       queue_q[14:8]>=HEIGHT/2-1 && queue_q[14:8]<=HEIGHT/2+1)component_seed<=1;
                    cur_x<=queue_q[7:0];cur_y<={1'b0,queue_q[14:8]};head<=head+1'b1;
                    component_count<=component_count+1'b1;sum_x<=sum_x+queue_q[7:0];sum_y<=sum_y+queue_q[14:8];
                    if(queue_q[7:0]<min_x)min_x<=queue_q[7:0];if(queue_q[7:0]>max_x)max_x<=queue_q[7:0];
                    if(queue_q[14:8]<min_y)min_y<=queue_q[14:8];if(queue_q[14:8]>max_y)max_y<=queue_q[14:8];
                    neighbor<=0;state<=NEIGH_REQ;
                end
                NEIGH_REQ:begin work_addr<=neighbor_valid?neighbor_addr:0;state<=NEIGH_WAIT;end
                NEIGH_WAIT:state<=NEIGH_CHECK;
                NEIGH_CHECK:begin
                    if(neighbor_valid && work_q)begin
                        if(tail>=QUEUE_CAPACITY)begin overflow<=1;found<=0;area<=0;result_valid<=1;state<=IDLE;reacq_pending<=0;
                            if(locked && lost_frames<15)lost_frames<=lost_frames+1'b1;end
                        else begin tail<=tail+1'b1;if(neighbor==3)state<=NODE_DONE;else begin neighbor<=neighbor+1'b1;state<=NEIGH_REQ;end end
                    end else if(neighbor==3)state<=NODE_DONE;
                    else begin neighbor<=neighbor+1'b1;state<=NEIGH_REQ;end
                end
                NODE_DONE:state<=head==tail?COMP_DONE:POP_REQ;
                COMP_DONE:begin
                    if(component_count>=MIN_AREA && component_count<=MAX_AREA && association_ok)begin
                        if(best_count==0 || (ASSOCIATION && locked?association_distance<best_distance:component_count>best_count))begin
                            best_count<=component_count;best_sum_x<=sum_x;best_sum_y<=sum_y;
                            best_min_x<=min_x;best_min_y<=min_y;best_max_x<=max_x;best_max_y<=max_y;
                            best_distance<=association_distance[8:0];
                            best_ambiguous<=ASSOCIATION && locked && best_count!=0 &&
                                (global_reacq || best_distance<=association_distance+4);
                        end else if(ASSOCIATION && locked && (global_reacq || association_distance<=best_distance+4))best_ambiguous<=1;
                    end
                    state<=SCAN_NEXT;
                end
                SCAN_NEXT:if(scan_addr==N-1)state<=FINAL;
                else begin
                    scan_addr<=scan_addr+1'b1;
                    if(scan_x==WIDTH-1)begin scan_x<=0;scan_y<=scan_y+1'b1;end else scan_x<=scan_x+1'b1;
                    state<=SCAN_REQ;
                end
                FINAL:if(best_count==0 || best_ambiguous)begin
                    found<=0;area<=0;result_valid<=1;state<=IDLE;reacq_pending<=0;
                    if(locked && lost_frames<15)lost_frames<=lost_frames+1'b1;
                end else if(ASSOCIATION && global_reacq && !reacq_consistent)begin
                    // Remember a candidate without publishing a steering target.
                    found<=0;area<=0;result_valid<=1;state<=IDLE;reacq_pending<=1;
                    reacq_x<=best_mid_x[7:0];reacq_y<=best_mid_y[7:0];reacq_area<=best_count;
                end else begin numerator<=best_sum_x;denominator<={9'd0,best_count};div_start<=1;state<=DIV_X;end
                DIV_X:if(div_done)begin center_x<=quotient[7:0];state<=DIV_Y_START;end
                DIV_Y_START:begin numerator<=best_sum_y;div_start<=1;state<=DIV_Y;end
                DIV_Y:if(div_done)begin
                    center_y<=quotient[7:0];found<=1;area<=best_count;locked<=1;locked_area<=best_count;
                    lost_frames<=0;reacq_pending<=0;
                    box_x<=best_min_x;box_y<=best_min_y;box_w<=best_max_x-best_min_x+1'b1;box_h<=best_max_y-best_min_y+1'b1;
                    result_valid<=1;state<=IDLE;
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
