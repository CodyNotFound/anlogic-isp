// Project HMI v1 contract: raw six-byte commands, native ASCII state writes.
// Screen graphics/text remain on the screen; no image RAM or Chinese UART text.
module hmi_control_link #(parameter CLK_HZ=75000000,BAUD=115200)(
 input wire clk,rst_n,rx,input wire[3:0]physical_features,mode,
 input wire target_found,compute_valid,input wire[3:0]task_status,input wire[1:0]ctl_state,
 input wire[15:0]x_digits,y_digits,h_digits,v_digits,ms_digits,input wire[7:0]fps_digits,
 output wire tx,output wire[3:0]features,output reg mode_set,output reg[3:0]mode_value,
 output reg action,output reg[3:0]keys);
 localparam MS_TICKS=CLK_HZ/1000,MW=MS_TICKS<2?1:$clog2(MS_TICKS);
 reg[MW-1:0]ms_count;wire ms_tick=ms_count==MS_TICKS-1;
 reg[3:0]desired,physical_prev;wire[3:0]changed=physical_features^physical_prev;
 assign features={desired[3]||physical_features[3],desired[2:0]};
 wire manual_mode=features[3];
 wire received,rx_error,tx_ready;wire[7:0]received_data,tx_data;
 wire tx_valid;
 vision_uart_8n1 #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) uart(clk,rst_n,rx,tx_valid,tx_data,tx_ready,tx,received,rx_error,received_data);
 reg[2:0]parse;reg[7:0]op,arg,check;reg[3:0]gap_ms;
 wire command=received&&parse==5&&received_data==8'h0d&&check==(8'hff^op^arg);
 reg[7:0]lease_ms;reg request_state;
 function[3:0]safe_keys;input[3:0]value;begin
 safe_keys=value;if(value[3]&&value[0])begin safe_keys[3]=0;safe_keys[0]=0;end
 if(value[2]&&value[1])begin safe_keys[2]=0;safe_keys[1]=0;end
 end endfunction
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)ms_count<=0;else if(ms_tick)ms_count<=0;else ms_count<=ms_count+1'b1;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin parse<=0;op<=0;arg<=0;check<=0;gap_ms<=0;end
  else begin
   if(ms_tick&&parse!=0)begin if(gap_ms==9)begin parse<=0;gap_ms<=0;end else gap_ms<=gap_ms+1'b1;end
   if(rx_error)begin parse<=0;gap_ms<=0;end
   if(received)begin
    gap_ms<=0;
    case(parse)
     0:if(received_data==8'ha5)parse<=1;
     1:if(received_data==8'h5a)parse<=2;else parse<=(received_data==8'ha5) ? 3'd1 : 3'd0;
     2:begin op<=received_data;parse<=3;end
     3:begin arg<=received_data;parse<=4;end
     4:begin check<=received_data;parse<=5;end
     default:parse<=(received_data==8'ha5) ? 3'd1 : 3'd0;
    endcase
   end
  end
 end
 integer i;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin desired<=0;physical_prev<=0;mode_set<=0;mode_value<=0;action<=0;keys<=0;lease_ms<=0;request_state<=0;end
  else begin
   physical_prev<=physical_features;mode_set<=0;action<=0;request_state<=0;
   for(i=0;i<4;i=i+1)if(changed[i])desired[i]<=physical_features[i];
   if(!manual_mode)begin keys<=0;lease_ms<=0;end
   else if(ms_tick&&lease_ms!=0)begin lease_ms<=lease_ms-1'b1;if(lease_ms==1)keys<=0;end
   if(command)case(op)
    8'h01:if(arg==0)request_state<=1;
    8'h10:if(arg<16&&arg!=13)begin mode_value<=arg[3:0];mode_set<=1;end
    8'h11:if(arg<2&&!changed[0])desired[0]<=arg[0];
    8'h12:if(arg<2&&!changed[1])desired[1]<=arg[0];
    8'h13:if(arg<2&&!changed[2])desired[2]<=arg[0];
    8'h14:if(arg<2&&!changed[3])desired[3]<=arg[0];
    8'h15:if(arg==0&&!manual_mode&&(mode==12||mode==14||mode==15))action<=1;
    8'h16:if(arg<16&&manual_mode)begin keys<=safe_keys(arg[3:0]);lease_ms<=arg==0?0:250;end
    default:begin end
   endcase
  end
 end
 // Four-digit values reuse the existing off-pixel formatting engines.
 function[15:0]small_bcd;input[3:0]value;begin small_bcd=value>=10?16'h0010+(value-10):{12'd0,value};end endfunction
 reg[3:0]ui_state;
 always @*begin
  if(manual_mode)ui_state=4;else if(!features[2])ui_state=5;else if(target_found)ui_state=1;
  else if(task_status==3)ui_state=6;else if(task_status==4||task_status==5)ui_state=7;
  else if(mode==12&&task_status==6)ui_state=2;else ui_state=ctl_state==0?0:3;
 end
 reg[207:0]snapshot;reg[7:0]sequence_bcd;reg[6:0]period_ms;
 reg running,pending;reg[3:0]field;reg[4:0]index;
 wire[15:0]digits=snapshot>>(field*16);
 reg[3:0]digit;
 always @*case(index)
  12:digit=digits[15:12];13:digit=digits[11:8];14:digit=digits[7:4];default:digit=digits[3:0];
 endcase
 reg[7:0]byte_value;
 always @*begin
  case(index)
   0:byte_value="m";1:byte_value="a";2:byte_value="i";3:byte_value="n";
   4,7:byte_value=".";5,8:byte_value="v";6:byte_value="A"+field;
   9:byte_value="a";10:byte_value="l";11:byte_value="=";
   12,13,14,15:byte_value="0"+digit;
   default:byte_value=8'hff;
  endcase
 end
 assign tx_valid=running;assign tx_data=byte_value;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin snapshot<=0;sequence_bcd<=0;period_ms<=0;running<=0;pending<=1;field<=0;index<=0;end
  else begin
   if(ms_tick&&period_ms<99)period_ms<=period_ms+1'b1;
   if(request_state)pending<=1;
   if(!running&&(period_ms==99||pending))begin
    snapshot<={{8'd0,sequence_bcd},{15'd0,physical_features[3]},{8'd0,fps_digits},{15'd0,compute_valid},{15'd0,target_found},ms_digits,v_digits,h_digits,y_digits,x_digits,{12'd0,ui_state},small_bcd(features),small_bcd(mode)};
    if(sequence_bcd[3:0]==9)sequence_bcd<=sequence_bcd[7:4]==9?0:{sequence_bcd[7:4]+4'd1,4'd0};else sequence_bcd<=sequence_bcd+1'b1;
    running<=1;pending<=0;period_ms<=0;field<=0;index<=0;
   end else if(running&&tx_ready)begin
    if(index==18)begin index<=0;if(field==12)begin running<=0;field<=0;end else field<=field+1'b1;end
    else index<=index+1'b1;
   end
  end
 end
endmodule
