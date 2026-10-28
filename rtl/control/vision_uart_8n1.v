// Full-duplex UART. One clock domain, midpoint sampling, no FIFO/BRAM/DSP.
module vision_uart_8n1 #(parameter CLK_HZ=75000000,BAUD=115200)(
 input wire clk,rst_n,rx,input wire tx_valid,input wire[7:0]tx_data,
 output wire tx_ready,output wire tx,output reg rx_valid,rx_error,output reg[7:0]rx_data);
 localparam BIT_TICKS=(CLK_HZ+BAUD/2)/BAUD;
 localparam CW=BIT_TICKS<2?1:$clog2(BIT_TICKS);
 (* async_reg="true" *) reg[1:0]rx_sync;
 reg[CW-1:0]rx_count,tx_count;reg[2:0]rx_state,rx_bit;
 reg[7:0]rx_shift;reg[9:0]tx_shift;reg[3:0]tx_left;
 assign tx_ready=tx_left==0;assign tx=tx_left==0?1'b1:tx_shift[0];
 initial if(BIT_TICKS<4)$error("UART requires >=4 clocks per bit");
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin rx_sync<=3;rx_count<=0;rx_state<=0;rx_bit<=0;rx_shift<=0;rx_data<=0;rx_valid<=0;rx_error<=0;end
  else begin
   rx_sync<={rx_sync[0],rx};rx_valid<=0;rx_error<=0;
   case(rx_state)
    0:if(!rx_sync[1])begin rx_count<=BIT_TICKS/2-1;rx_state<=1;end
    1:if(rx_count!=0)rx_count<=rx_count-1'b1;
      else if(rx_sync[1])rx_state<=0;else begin rx_count<=BIT_TICKS-1;rx_bit<=0;rx_state<=2;end
    2:if(rx_count!=0)rx_count<=rx_count-1'b1;
      else begin rx_shift[rx_bit]<=rx_sync[1];rx_count<=BIT_TICKS-1;if(rx_bit==7)rx_state<=3;else rx_bit<=rx_bit+1'b1;end
    3:if(rx_count!=0)rx_count<=rx_count-1'b1;
      else if(rx_sync[1])begin rx_data<=rx_shift;rx_valid<=1;rx_state<=0;end
      else begin rx_error<=1;rx_state<=4;end
    default:if(rx_sync[1])rx_state<=0;
   endcase
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin tx_count<=0;tx_shift<=10'h3ff;tx_left<=0;end
  else if(tx_left==0)begin
   if(tx_valid)begin tx_shift<={1'b1,tx_data,1'b0};tx_left<=10;tx_count<=BIT_TICKS-1;end
  end else if(tx_count!=0)tx_count<=tx_count-1'b1;
  else begin tx_count<=BIT_TICKS-1;tx_left<=tx_left-1'b1;tx_shift<={1'b1,tx_shift[9:1]};end
 end
endmodule
