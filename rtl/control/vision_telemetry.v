// Off-pixel-path formatting: one shared serial BCD engine for X, Y and time.
// Modes0..10: application SOF cycles in 0.0001ms units; other modes: task ms.
// Neither quantity includes sensor exposure or upstream DDR transport.
module vision_telemetry #(parameter CLK_HZ=75000000,WIDTH=1280,HEIGHT=720)(
 input wire clk,rst_n,input wire [3:0] mode,input wire found,compute_valid,
 input wire [11:0] x,y,input wire [31:0] compute_cycles,
 output reg [3:0] packet_mode,output reg packet_found,packet_compute_valid,packet_tick,
 output reg [15:0] x_digits,y_digits,ms_digits
);
 localparam CYCLES_PER_MS=CLK_HZ/1000;
 reg [2:0] state;reg [4:0] wait_count;
 reg [3:0] saved_mode;reg saved_found,saved_compute_valid;
 reg [11:0] saved_x,saved_y;reg [13:0] milliseconds;
 reg [32:0] remaining;reg [15:0] staged_x,staged_y;
 wire start=state==2||state==4||state==6;
 wire [19:0] value=state==2?{8'd0,saved_x}:state==4?{8'd0,saved_y}:{6'd0,milliseconds};
 wire [23:0] digits;
 vision_bcd #(.BIN_W(14),.DEC_DIGITS(4)) convert(clk,rst_n,start,value,digits);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=0;wait_count<=0;saved_mode<=0;saved_found<=0;saved_compute_valid<=0;saved_x<=0;saved_y<=0;
   milliseconds<=0;remaining<=0;staged_x<=0;staged_y<=0;packet_mode<=0;packet_found<=0;packet_compute_valid<=0;
   x_digits<=0;y_digits<=0;ms_digits<=0;packet_tick<=0;
  end else begin
   packet_tick<=0;
   case(state)
    0:begin saved_mode<=mode;saved_found<=found&&x<WIDTH&&y<HEIGHT;saved_compute_valid<=compute_valid;
     saved_x<=x;saved_y<=y;remaining<=!compute_valid?33'd0:mode<11?({1'b0,compute_cycles}<<1)+7:{1'b0,compute_cycles}+CYCLES_PER_MS/2;
     milliseconds<=0;state<=1;end
    1:if(remaining>=(saved_mode<11?CYCLES_PER_MS/5000:CYCLES_PER_MS)&&milliseconds<9999)begin remaining<=remaining-(saved_mode<11?CYCLES_PER_MS/5000:CYCLES_PER_MS);milliseconds<=milliseconds+1'b1;end
      else state<=2;
    2,4,6:begin wait_count<=0;state<=state+1'b1;end
    3:if(wait_count==20)begin staged_x<=digits[15:0];state<=4;end else wait_count<=wait_count+1'b1;
    5:if(wait_count==20)begin staged_y<=digits[15:0];state<=6;end else wait_count<=wait_count+1'b1;
    7:if(wait_count==20)begin
      x_digits<=staged_x;y_digits<=staged_y;ms_digits<=digits[15:0];packet_mode<=saved_mode;
      packet_found<=saved_found;packet_compute_valid<=saved_compute_valid;packet_tick<=1;state<=0;
     end else wait_count<=wait_count+1'b1;
   endcase
  end
 end
endmodule
