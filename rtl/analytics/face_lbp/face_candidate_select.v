// Spatial vote filter. Anchors stay fixed; ties keep the first slot.
// A synchronous packed table and one comparator replace sixteen parallel lanes.
// The cascade takes thousands of clocks per accepted candidate; each update
// takes at most 2*SLOTS+2 clocks. One skid entry covers a following candidate.
// Any queue or table overflow rejects the whole snapshot, never a partial set.
module face_candidate_select #(
    parameter integer SLOTS=16,
    parameter integer MIN_VOTES=3
)(
    input wire clk,rst_n,frame_start,frame_done,candidate_valid,
    input wire [7:0] box_x,box_y,box_size,
    output reg result_valid,target_found,overflow,select_busy,
    output reg [7:0] target_x,target_y,target_size,target_votes,
    output wire [8:0] target_center_x,target_center_y
);
    localparam integer AW=SLOTS<2?1:$clog2(SLOTS);
    localparam IDLE=0,CLEAR=1,MATCH_READ=2,MATCH_CHECK=3,WRITE=4,
               RESULT_READ=5,RESULT_CHECK=6,RESULT_DONE=7;
    reg [2:0] state;
    reg [AW-1:0] index,free_index,write_index;
    reg free_valid,finish_pending,pending_valid;
    reg [23:0] pending_box,active_box;
    reg [31:0] write_word,slot_q;
    reg [31:0] slots[0:SLOTS-1];
    wire memory_write=state==CLEAR || state==WRITE;
    wire [AW-1:0] memory_write_index=state==CLEAR?index:write_index;
    wire [31:0] memory_write_word=state==CLEAR?32'd0:write_word;
    // No asynchronous reset on the table: CLEAR initializes it before capture
    // completes. A shared write port allows FPGA memory inference.
    always @(posedge clk) begin
        slot_q<=slots[index];
        if(memory_write)slots[memory_write_index]<=memory_write_word;
    end
    wire [7:0] ax=active_box[7:0],ay=active_box[15:8],aw=active_box[23:16];
    wire [7:0] sx=slot_q[7:0],sy=slot_q[15:8],sw=slot_q[23:16],sv=slot_q[31:24];
    wire [7:0] dx=ax>sx?ax-sx:sx-ax,dy=ay>sy?ay-sy:sy-ay;
    wire [7:0] dw=aw>sw?aw-sw:sw-aw,small_size=aw<sw?aw:sw;
    wire match_slot=sv!=0 && dx<=(small_size>>2) && dy<=(small_size>>2) && dw<=(small_size>>1);
    reg [7:0] best_votes,best_x,best_y,best_size;
    assign target_center_x={1'b0,target_x}+({1'b0,target_size}>>1);
    assign target_center_y={1'b0,target_y}+({1'b0,target_size}>>1);
    always @* select_busy=state!=IDLE || pending_valid || finish_pending;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;index<=0;free_index<=0;write_index<=0;
            free_valid<=0;finish_pending<=0;pending_valid<=0;
            pending_box<=0;active_box<=0;write_word<=0;
            result_valid<=0;target_found<=0;overflow<=0;
            best_votes<=0;best_x<=0;best_y<=0;best_size<=0;
            target_x<=0;target_y<=0;target_size<=0;target_votes<=0;
        end else begin
            result_valid<=0;
            if(frame_start) begin
                overflow<=0;finish_pending<=0;pending_valid<=0;
                index<=0;state<=CLEAR;
            end else begin
                if(frame_done)finish_pending<=1;
                if(candidate_valid && state!=IDLE)begin
                    if(state==CLEAR || state>=RESULT_READ || pending_valid)overflow<=1;
                    else begin pending_valid<=1;pending_box<={box_size,box_y,box_x};end
                end
                case(state)
                    CLEAR:if(index==SLOTS-1)begin index<=0;state<=IDLE;end else index<=index+1'b1;
                    IDLE:begin
                        if(pending_valid || candidate_valid)begin
                            active_box<=pending_valid?pending_box:{box_size,box_y,box_x};
                            pending_valid<=pending_valid && candidate_valid;
                            if(pending_valid && candidate_valid)pending_box<={box_size,box_y,box_x};
                            index<=0;free_valid<=0;state<=MATCH_READ;
                        end else if(finish_pending || frame_done)begin
                            finish_pending<=0;index<=0;best_votes<=0;
                            best_x<=0;best_y<=0;best_size<=0;state<=RESULT_READ;
                        end
                    end
                    MATCH_READ:state<=MATCH_CHECK;
                    MATCH_CHECK:begin
                        if(sv==0 && !free_valid)begin free_valid<=1;free_index<=index;end
                        if(match_slot)begin
                            write_index<=index;
                            write_word<={sv==255?8'd255:sv+8'd1,slot_q[23:0]};state<=WRITE;
                        end else if(index==SLOTS-1)begin
                            if(free_valid || sv==0)begin
                                write_index<=free_valid?free_index:index;
                                write_word<={8'd1,active_box};state<=WRITE;
                            end else begin overflow<=1;state<=IDLE;end
                        end else begin index<=index+1'b1;state<=MATCH_READ;end
                    end
                    WRITE:state<=IDLE;
                    RESULT_READ:state<=RESULT_CHECK;
                    RESULT_CHECK:begin
                        if(sv>best_votes)begin best_votes<=sv;best_x<=sx;best_y<=sy;best_size<=sw;end
                        if(index==SLOTS-1)state<=RESULT_DONE;
                        else begin index<=index+1'b1;state<=RESULT_READ;end
                    end
                    RESULT_DONE:begin
                        state<=IDLE;result_valid<=1;target_votes<=best_votes;
                        target_found<=!overflow && !candidate_valid && best_votes>=MIN_VOTES;
                        if(!overflow && !candidate_valid && best_votes>=MIN_VOTES)begin
                            target_x<=best_x;target_y<=best_y;target_size<=best_size;
                        end else begin target_x<=0;target_y<=0;target_size<=0;end
                    end
                    default:state<=IDLE;
                endcase
            end
        end
    end
endmodule
