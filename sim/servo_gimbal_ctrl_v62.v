// 50Hz atomic PWM, manual Vim keys and fresh visual-result integration.
// Vertical 1000/2200us are collision points: stay strictly inside them.
module servo_gimbal_ctrl_v62 #(
 parameter integer CLK_HZ=75000000, HOLD_US=2000000, IMG_W=160, IMG_H=90,
 parameter integer H_MIN_US=500,H_MAX_US=2500,V_MIN_US=1050,V_MAX_US=2150,
 parameter integer CENTER_US=1500, STEP_MAX_US=32, AUTO_GAIN_SHIFT=1,
 parameter integer MANUAL_STEP_US=4, MANUAL_FAST_STEP_US=32, MANUAL_ACCEL_FRAMES=10,
 parameter integer H_INVERT=1, V_INVERT=0, AUTO_SLEW_US=8, AUTO_PLAN_US=120000
)(
 input wire clk,rst_n,enable,result_valid,found,
 input wire [7:0] cx,cy,
 input wire manual_mode,input wire [3:0] keys_pressed,
 output reg pwm_h,pwm_v,
 output reg [11:0] pulse_h_us,pulse_v_us,
 output wire [1:0] ctl_state
);
 localparam integer DIV=CLK_HZ/1000000;
 localparam integer DW=(DIV<2)?1:$clog2(DIV);
 reg [DW-1:0] divider;
 reg [14:0] phase_us;
 reg [21:0] age_us;
 reg seen,pending,valid_d;
 reg [11:0] desired_h,desired_v;
 wire plan_active=age_us<AUTO_PLAN_US;
 reg [3:0] held_frames,held_keys;
 wire tick_us=divider==DIV-1;
 wire boundary=tick_us && phase_us==19999;
 wire fresh=result_valid && !valid_d;
 assign ctl_state=!enable||!seen ? 2'd0 : age_us>=HOLD_US ? 2'd3 :
                    (found && age_us<200000 ? 2'd1:2'd2);
 function signed [6:0] correction;
  input [7:0] pos;input integer mid,dead;input integer invert;
  integer err,mag;
  begin
   err=pos-mid;mag=(err<0)?-err:err;
   if(mag<=dead)correction=0;
   else begin
    // Count only error outside the deadband: 1us near center, faster far away.
    mag=(mag-dead+((1<<AUTO_GAIN_SHIFT)-1))>>AUTO_GAIN_SHIFT;
    if(mag<1)mag=1;if(mag>STEP_MAX_US)mag=STEP_MAX_US;
    correction=((err<0)^invert)?-mag:mag;
   end
  end
 endfunction
 function [11:0] clamp;
  input integer value,lo,hi;
  begin clamp=value<lo?lo:value>hi?hi:value;end
 endfunction
 function [11:0] approach;
  input [11:0] current,target;
  integer delta;
  begin delta=$signed({1'b0,target})-$signed({1'b0,current});
   if(delta>AUTO_SLEW_US)delta=AUTO_SLEW_US;
   if(delta < -AUTO_SLEW_US)delta=-AUTO_SLEW_US;
   approach=current+delta;
  end
 endfunction
 integer dh,dv;
 wire [6:0] manual_step=(keys_pressed==held_keys && held_frames>=MANUAL_ACCEL_FRAMES)?MANUAL_FAST_STEP_US:MANUAL_STEP_US;
 always @* begin
  // [3:0] = K4(h left), K3(j down), K2(k up), K1(l right).
  dh=(keys_pressed[3]?manual_step:0)-(keys_pressed[0]?manual_step:0);
  if(!H_INVERT)dh=-dh;
  dv=(keys_pressed[2]?manual_step:0)-(keys_pressed[1]?manual_step:0);
  if(V_INVERT)dv=-dv;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin
   divider<=0;phase_us<=0;pwm_h<=0;pwm_v<=0;
   pulse_h_us<=CENTER_US;pulse_v_us<=CENTER_US;
   age_us<=0;seen<=0;pending<=0;valid_d<=0;desired_h<=CENTER_US;desired_v<=CENTER_US;
   held_frames<=0;held_keys<=0;
  end else begin
   valid_d<=result_valid;
   // Release or direction changes restore fine control before another PWM tick.
   if(!manual_mode || keys_pressed!=held_keys)begin held_frames<=0;held_keys<=keys_pressed;end
   else if(boundary && |keys_pressed && held_frames<MANUAL_ACCEL_FRAMES)held_frames<=held_frames+1'b1;
   if(tick_us)begin
    divider<=0;
    if(phase_us==19999)begin
     phase_us<=0;pwm_h<=1;pwm_v<=1;
     // Commands change only at the beginning of a whole 20ms PWM period.
     if(manual_mode)begin
      pulse_h_us<=clamp($signed({1'b0,pulse_h_us})+dh,H_MIN_US,H_MAX_US);
      pulse_v_us<=clamp($signed({1'b0,pulse_v_us})+dv,V_MIN_US,V_MAX_US);
     end else if(enable && seen)begin
      // Loss holds the last pulse indefinitely. Only a fresh accepted target
      // or an explicit manual command may move the axes; timeout never homes.
      if(plan_active && pending && found)begin
       pulse_h_us<=approach(pulse_h_us,desired_h);
       pulse_v_us<=approach(pulse_v_us,desired_v);
      end
     end
    end else begin
     phase_us<=phase_us+1'b1;
     if(phase_us+1'b1==pulse_h_us)pwm_h<=0;
     if(phase_us+1'b1==pulse_v_us)pwm_v<=0;
    end
    if(seen && age_us<HOLD_US+1)age_us<=age_us+1'b1;
   end else divider<=divider+1'b1;
   // A fresh result creates one bounded endpoint, not a repeated velocity.
   if(boundary && pulse_h_us==desired_h && pulse_v_us==desired_v)pending<=0;
   if(!found)pending<=0;
   if(!enable || manual_mode)begin seen<=0;pending<=0;age_us<=0;end
   else if(fresh && found && cx<IMG_W && cy<IMG_H)begin
    seen<=1;age_us<=0;pending<=1;
    desired_h<=clamp($signed({1'b0,pulse_h_us})+correction(cx,IMG_W/2,8,H_INVERT),H_MIN_US,H_MAX_US);
    desired_v<=clamp($signed({1'b0,pulse_v_us})+correction(cy,IMG_H/2,6,V_INVERT),V_MIN_US,V_MAX_US);
   end
  end
 end
endmodule
