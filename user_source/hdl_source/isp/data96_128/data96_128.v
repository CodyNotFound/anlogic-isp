// MSB-first RGB byte stream. Four accepted 96-bit beats produce three 128-bit
// words. Invalid cycles do not consume input bytes or reset the byte phase.
module data_96bit_to_128bit (
 input wire I_clk,I_rst_n,I_96b_frame_start,I_96b_valid,
 input wire [95:0] I_96b_data,
 output reg O_128b_frame_start,O_128b_valid,output reg [127:0] O_128b_data
);
 reg [95:0] previous;
 reg [1:0] phase;
 wire [1:0] accepted_phase=I_96b_frame_start?2'd0:phase;
 always @(posedge I_clk or negedge I_rst_n)begin
  if(!I_rst_n)begin
   previous<=0;phase<=0;O_128b_frame_start<=0;O_128b_valid<=0;O_128b_data<=0;
  end else begin
   O_128b_frame_start<=I_96b_frame_start;
   O_128b_valid<=0;
   if(I_96b_frame_start)phase<=0;
   if(I_96b_valid)begin
    previous<=I_96b_data;phase<=accepted_phase+1'b1;
    case(accepted_phase)
     0:begin end
     1:begin O_128b_valid<=1;O_128b_data<={previous,I_96b_data[95:64]};end
     2:begin O_128b_valid<=1;O_128b_data<={previous[63:0],I_96b_data[95:32]};end
     3:begin O_128b_valid<=1;O_128b_data<={previous[31:0],I_96b_data};end
    endcase
   end
  end
 end
endmodule
