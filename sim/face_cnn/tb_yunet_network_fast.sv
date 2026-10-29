`timescale 1ns/1ps
module tb_yunet_network_fast;
 reg clk=0,io_clk=0;always #3.333 clk=~clk;initial begin #1.1;forever #6.667 io_clk=~io_clk;end
 reg rst=0,start=0,load=0;reg [16:0] la=0,ra=0;reg [7:0] ld=0;
 wire [7:0] rd;wire busy,done,opdone;wire [5:0] opidx;wire [31:0] cycles;
 yunet_network #(.DUAL_CLOCK(1)) dut(.clk(clk),.io_clk(io_clk),.rst_n(rst),.start(start),.load_valid(load),.load_address(la),.load_data(ld),.read_address(ra),.read_data(rd),.busy(busy),.done(done),.operation_done(opdone),.operation_index(opidx),.cycles(cycles),.read_word());
 reg [7:0] input_pixels[0:61439],expected[0:65535],actual;
 integer fd,rc,base,count,i,op=0,total=0;string path;
 integer next_progress=1000000;
 always @(posedge clk)if(rst&&cycles>=next_progress)begin $display("PROGRESS cycles%0d op%0d state%0d x%0d y%0d oc%0d",cycles,op,dut.state,dut.ox,dut.oy,dut.oc);next_progress=next_progress+1000000;end
 always @(posedge clk)begin
  #1;
  if(rst&&opdone)begin
   rc=$fscanf(fd,"%d %d\n",base,count);if(rc!=2)$fatal(1,"missing op metadata");
   path=$sformatf("sim/face_cnn/data/network_reference/op_%02d.hex",op);
   $readmemh(path,expected,0,count-1);
   for(i=0;i<count;i=i+1)begin
    case((base+i)%4)
     0:actual=dut.fm0[(base+i)/4];1:actual=dut.fm1[(base+i)/4];
     2:actual=dut.fm2[(base+i)/4];3:actual=dut.fm3[(base+i)/4];
    endcase
    if(actual!==expected[i])$fatal(1,"YuNet op%0d byte%0d address%0d got%h want%h cycle%0d",op,i,base+i,actual,expected[i],cycles);
   end
   total=total+count;$display("PASS YuNet operation%0d exact_bytes%0d cycles%0d",op,count,cycles);op=op+1;
  end
 end
 reg [16:0] aq_address_trace,wq_address_trace;reg [12:0] cq_address_trace;
 always @(posedge clk)begin
  aq_address_trace<=dut.core_port_address;wq_address_trace<=dut.weight_address;cq_address_trace<=dut.cache_read_address;
  if(rst)begin
   if(dut.state==8&&dut.dot_in_ready&&wq_address_trace[15:2]!==dut.conv_weight[15:2])$fatal(1,"weight address mismatch cycle%0d got%0d expected%0d",cycles,wq_address_trace,dut.conv_weight);
   if(dut.state==8 && dut.dot_in_ready && !dut.padding)begin
    if(!dut.use_row&&!dut.use_pixel && aq_address_trace[16:2]!==dut.conv_addr[16:2])$fatal(1,"conv read mismatch cycle%0d got%0d expected%0d",cycles,aq_address_trace,dut.conv_addr);
    if(dut.use_row && cq_address_trace[12:2]!==dut.cache_addr[12:2])$fatal(1,"cache read mismatch cycle%0d",cycles);
   end
   if(dut.state==13 && aq_address_trace[16:2]!==dut.misc_addr[16:2])$fatal(1,"misc read mismatch cycle%0d",cycles);
   if(dut.state==17 && aq_address_trace[16:2]!==dut.fill_address[16:2])$fatal(1,"row read mismatch cycle%0d",cycles);
   if(dut.state==20 && aq_address_trace[16:2]!==dut.pixel_address[16:2])$fatal(1,"pixel read mismatch cycle%0d",cycles);
   if(dut.write_pending && dut.write_address!==dut.feature_index(dut.dst_base,dut.oy,dut.ox,dut.ow,dut.oc,dut.channel_shift(dut.co)))$fatal(1,"write address mismatch cycle%0d",cycles);
  end
 end
 initial begin
  $readmemh("sim/face_cnn/data/network_reference/input.hex",input_pixels);
  fd=$fopen("sim/face_cnn/data/network_reference/op_checks.txt","r");if(!fd)$fatal(1,"missing op checks");
  repeat(5)@(negedge io_clk);rst=1;
  for(integer j=0;j<61440;j=j+1)begin load=1;la=j;ld=input_pixels[j];@(negedge io_clk);end
  load=0;start=1;@(negedge clk);start=0;
  wait(done);@(negedge clk);
  if(op!=55)$fatal(1,"incomplete graph %0d",op);
  $display("PASS tb_yunet_network_fast: all 55 operations, %0d exact activation bytes, %0d cycles; actual image to actual heads",total,cycles);$finish;
 end
 initial begin #500000000;$fatal(1,"network watchdog");end
endmodule
