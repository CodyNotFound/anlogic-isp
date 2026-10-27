// Camera adapter for the complete integer CNN snapshot/position pipeline.
// Standalone integration candidate; the production vision_pipeline still selects
// LBP until the complete CNN resource/timing/accuracy gates have passed.
module face_video_cnn #(
 parameter integer WIDTH=1280,HEIGHT=720,RESULT_TTL_CYCLES=75000000,SHARED_TRACK_FRAME=0,
 parameter PROGRAM_FILE="program.hex",W0_FILE="weights0.hex",W1_FILE="weights1.hex",W2_FILE="weights2.hex",W3_FILE="weights3.hex",
 parameter BIAS_FILE="bias.hex",SHIFT_FILE="shift.hex",SIGMOID_FILE="sigmoid.hex",OFFSET_FILE="offset.hex",SIZE_FILE="size.hex"
)(input wire clk,rst_n,enable,sof,eol,de,input wire [23:0] rgb,
 output reg position_valid,found,output reg [11:0] box_x,box_y,box_size,center_x,center_y,
 output wire busy,output wire stream_error,output reg [31:0] completed_frames,
 input wire shared_enable,shared_write_en,input wire [13:0] shared_write_address,shared_read_address,
 input wire [7:0] shared_write_data,output wire [7:0] shared_read_data);
 wire nn_ready,nn_busy,result,nn_found,capturing,load,start;
 wire [16:0] address;wire [7:0] data;wire [11:0] x,y,size,cx,cy;
 wire [13:0] score;wire [31:0] cycles,accepted;
 reg [26:0] age;
 wire active_reset=rst_n&&enable;
 wire shared_owner=SHARED_TRACK_FRAME&&shared_enable&&!enable;
 assign busy=nn_busy||capturing;
 yunet_rgb_snapshot #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) sampler(.clk(clk),.rst_n(active_reset),.enable(enable),.network_busy(nn_busy),
  .sof(sof),.eol(eol),.de(de),.rgb(rgb),.load_valid(load),.load_address(address),.load_data(data),
  .start_network(start),.capturing(capturing),.stream_error(stream_error),.accepted_frames(accepted));
 yunet_position_snapshot #(.SHARED_TRACK_FRAME(SHARED_TRACK_FRAME),.PROGRAM_FILE(PROGRAM_FILE),.W0_FILE(W0_FILE),.W1_FILE(W1_FILE),.W2_FILE(W2_FILE),.W3_FILE(W3_FILE),.BIAS_FILE(BIAS_FILE),.SHIFT_FILE(SHIFT_FILE),.SIGMOID_FILE(SIGMOID_FILE),.OFFSET_FILE(OFFSET_FILE),.SIZE_FILE(SIZE_FILE)) nn(.clk(clk),.rst_n(active_reset),.start(start),
  .load_valid(shared_owner?shared_write_en:load),.load_address(shared_owner?{3'd0,shared_write_address}:address),.load_data(shared_owner?shared_write_data:data),
  .ready(nn_ready),.busy(nn_busy),.result_valid(result),.found(nn_found),.box_x(x),.box_y(y),.box_size(size),.center_x(cx),.center_y(cy),.score_product(score),.cycles(cycles),
  .external_read_enable(shared_owner),.external_read_address({3'd0,shared_read_address}),.external_read_data(shared_read_data));
 always @(posedge clk or negedge active_reset)begin
  if(!active_reset)begin position_valid<=0;found<=0;box_x<=0;box_y<=0;box_size<=0;center_x<=0;center_y<=0;completed_frames<=0;age<=0;end
  else begin
   position_valid<=0;
   if(found&&age<RESULT_TTL_CYCLES)age<=age+1'b1;
   if(age>=RESULT_TTL_CYCLES-1)found<=0;
   if(result)begin
    position_valid<=1;found<=nn_found;box_x<=x;box_y<=y;box_size<=size;center_x<=cx;center_y<=cy;age<=0;completed_frames<=completed_frames+1'b1;
   end
  end
 end
endmodule
