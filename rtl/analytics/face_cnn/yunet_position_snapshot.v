// Byte-loaded BGR0 160x96 snapshot -> complete integer CNN -> face location.
// All inference and output decoding execute in RTL. No host decision is used.
// A camera adapter may load while ready; start only after all 61,440 bytes.
module yunet_position_snapshot #(
 parameter PROGRAM_FILE="rtl/analytics/face_cnn/program.hex",
 parameter W0_FILE="rtl/analytics/face_cnn/weights0.hex",W1_FILE="rtl/analytics/face_cnn/weights1.hex",
 parameter W2_FILE="rtl/analytics/face_cnn/weights2.hex",W3_FILE="rtl/analytics/face_cnn/weights3.hex",
 parameter BIAS_FILE="rtl/analytics/face_cnn/bias.hex",SHIFT_FILE="rtl/analytics/face_cnn/shift.hex",
 parameter SIGMOID_FILE="rtl/analytics/face_cnn/sigmoid.hex",OFFSET_FILE="rtl/analytics/face_cnn/offset.hex",SIZE_FILE="rtl/analytics/face_cnn/size.hex"
)(input wire clk,rst_n,start,load_valid,input wire [16:0] load_address,input wire [7:0] load_data,
 output wire ready,busy,output reg result_valid,found,
 output reg [11:0] box_x,box_y,box_size,center_x,center_y,
 output reg [13:0] score_product,output wire [31:0] cycles);
 `include "yunet_heads.vh"
 localparam IDLE=0,RUN=1,FRAME=2,ADDRESS=3,WAIT_READ=4,CAPTURE=5,SEND=6,WAIT_RESULT=7;
 reg [2:0] state;reg [1:0] level;reg [7:0] gx,gy;reg [2:0] field;
 reg [7:0] cls,obj,bx,by,bw,bh;reg [16:0] address;
 wire [7:0] data;wire nn_busy,nn_done,nn_op_done;wire [5:0] nn_op;
 wire decoded,decode_found;wire [13:0] decode_score;wire [11:0] dx,dy,ds,dcx,dcy;
 wire last_anchor=(level==2&&gx==4&&gy==2);
 assign ready=state==IDLE;assign busy=state!=IDLE;
 yunet_network #(.PROGRAM_FILE(PROGRAM_FILE),.W0_FILE(W0_FILE),.W1_FILE(W1_FILE),.W2_FILE(W2_FILE),.W3_FILE(W3_FILE),.BIAS_FILE(BIAS_FILE),.SHIFT_FILE(SHIFT_FILE)) network(
  .clk(clk),.rst_n(rst_n),.start(start&&ready),.load_valid(load_valid&&ready),.load_address(load_address),.load_data(load_data),
  .read_address(address),.read_data(data),.busy(nn_busy),.done(nn_done),.operation_done(nn_op_done),.operation_index(nn_op),.cycles(cycles));
 yunet_decode #(.SIGMOID_FILE(SIGMOID_FILE),.OFFSET_FILE(OFFSET_FILE),.SIZE_FILE(SIZE_FILE)) decoder(
  .clk(clk),.rst_n(rst_n),.frame_start(state==FRAME),.in_valid(state==SEND),.in_last(last_anchor),.level(level),.grid_x(gx),.grid_y(gy),
  .cls(cls),.obj(obj),.bx(bx),.by(by),.bw(bw),.bh(bh),.result_valid(decoded),.found(decode_found),.score_product(decode_score),
  .box_x(dx),.box_y(dy),.box_size(ds),.center_x(dcx),.center_y(dcy));
 function [16:0] cls_base;input [1:0] l;
 begin cls_base=l==0?HEAD_CLS_8:l==1?HEAD_CLS_16:HEAD_CLS_32;end endfunction
 function [16:0] obj_base;input [1:0] l;
 begin obj_base=l==0?HEAD_OBJ_8:l==1?HEAD_OBJ_16:HEAD_OBJ_32;end endfunction
 function [16:0] bbox_base;input [1:0] l;
 begin bbox_base=l==0?HEAD_BBOX_8:l==1?HEAD_BBOX_16:HEAD_BBOX_32;end endfunction
 // Row widths are 20,10,5. Constant shift/add avoids address DSPs.
 wire [16:0] anchor=level==0?({9'b0,gy}<<4)+({9'b0,gy}<<2)+gx:
  level==1?({9'b0,gy}<<3)+({9'b0,gy}<<1)+gx:({9'b0,gy}<<2)+gy+gx;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;level<=0;gx<=0;gy<=0;field<=0;address<=0;cls<=0;obj<=0;bx<=0;by<=0;bw<=0;bh<=0;
   result_valid<=0;found<=0;box_x<=0;box_y<=0;box_size<=0;center_x<=0;center_y<=0;score_product<=0;
  end else begin
   result_valid<=0;
   case(state)
    IDLE:if(start)begin state<=RUN;found<=0;end
    RUN:if(nn_done)begin level<=0;gx<=0;gy<=0;field<=0;state<=FRAME;end
    FRAME:state<=ADDRESS;
    ADDRESS:begin
     address<=field==0?cls_base(level)+anchor:field==1?obj_base(level)+anchor:bbox_base(level)+(anchor<<2)+field-2;
     state<=WAIT_READ;
    end
    WAIT_READ:state<=CAPTURE;
    CAPTURE:begin
     case(field)0:cls<=data;1:obj<=data;2:bx<=data;3:by<=data;4:bw<=data;5:bh<=data;endcase
     if(field==5)begin field<=0;state<=SEND;end else begin field<=field+1'b1;state<=ADDRESS;end
    end
    SEND:begin
     if(last_anchor)state<=WAIT_RESULT;
     else begin
      if((level==0&&gx==19)||(level==1&&gx==9)||(level==2&&gx==4))begin
       gx<=0;if((level==0&&gy==11)||(level==1&&gy==5))begin gy<=0;level<=level+1'b1;end else gy<=gy+1'b1;
      end else gx<=gx+1'b1;
      state<=ADDRESS;
     end
    end
    WAIT_RESULT:if(decoded)begin
     result_valid<=1;found<=decode_found;score_product<=decode_score;
     box_x<=dx;box_y<=dy;box_size<=ds;center_x<=dcx;center_y<=dcy;state<=IDLE;
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
