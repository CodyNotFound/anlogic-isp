// Stable levels for motion; release interlock protects legacy button actions.
module gimbal_button_router #(parameter integer DEBOUNCE_CYCLES=750000)(
 input wire clk,rst_n,manual_mode,input wire [3:0] buttons_n,
 output wire [3:0] keys_pressed,normal_buttons_n
);
 wire [3:0] pressed;
 reg armed;
 vision_switch_ctrl #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) debounce(
  .clk(clk),.rst_n(rst_n),.switches_n(buttons_n),.feature_enable(pressed));
 assign keys_pressed=pressed;
 assign normal_buttons_n=(!manual_mode && armed)?~pressed:4'b1111;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)armed<=0;
  else if(manual_mode)armed<=0;
  else if(pressed==0)armed<=1;
 end
endmodule
