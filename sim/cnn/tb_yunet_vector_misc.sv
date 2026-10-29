`timescale 1ns/1ps
module tb_yunet_vector_misc;
 reg clk=0;always #3.333 clk=~clk;
 reg rst=0,start=0,load=0;reg[16:0]la=0;reg[7:0]ld=0;wire busy,done;
 yunet_network #(.PROGRAM_DEPTH(1),.PROGRAM_FILE("sim/cnn/data/misc_program.hex")) dut(.clk(clk),.io_clk(clk),.rst_n(rst),.start(start),.load_valid(load),.load_address(la),.load_data(ld),.read_address(17'd0),.read_data(),.busy(busy),.done(done),.operation_done(),.operation_index(),.cycles(),.read_word());
 reg[7:0]a[0:511],b[0:511],expected[0:511],actual;
 reg[159:0]ins;integer seed=291004,t,kind,src,dst,iw,ih,ow,oh,s1,s2,half,i,x,y,c,j,xx,yy,v,m,n,steps,channels,total=0;
 function integer signed8;input[7:0]v;begin signed8=v[7]?v-256:v;end endfunction
 initial begin
  for(t=0;t<112;t=t+1)begin
   kind=2+t%3;channels=t%7==0?1:4;src=0;dst=t%2==0?2048:src;
   // Match production aliasing: pooling/Add may overwrite; Resize has a separate destination.
   if(kind==3||channels==1)dst=2048;
   iw=kind==3?5:10;ih=iw;ow=kind==2?5:10;oh=ow;
   s1=(t/3)%2;s2=(t/6)%2;if(kind!=4)begin s1=0;s2=0;end
   half=s1||s2;
   for(i=0;i<512;i=i+1)begin a[i]=$random(seed);b[i]=$random(seed);end
   for(y=0;y<oh;y=y+1)for(x=0;x<ow;x=x+1)for(c=0;c<channels;c=c+1)begin
    if(kind==2)begin
     m=-128;for(yy=0;yy<2;yy=yy+1)for(xx=0;xx<2;xx=xx+1)begin
      v=signed8(a[((2*y+yy)*iw+2*x+xx)*channels+c]);if(v>m)m=v;
     end
    end else if(kind==3)m=signed8(a[((y/2)*iw+x/2)*channels+c]);
    else begin
     j=(y*iw+x)*channels+c;
     m=(signed8(a[j])<<(half&&!s1))+(signed8(b[j])<<(half&&!s2));
     if(half)m=(m+1)>>>1;
     if(m>127)m=127;if(m< -128)m=-128;
    end
    expected[(y*ow+x)*channels+c]=m;
   end
   rst=0;load=0;start=0;repeat(4)@(negedge clk);
   ins=0;ins[3:0]=kind;ins[20:4]=src;ins[37:21]=1024+src;ins[54:38]=dst;
   ins[62:55]=iw;ins[70:63]=ih;ins[78:71]=ow;ins[86:79]=oh;ins[93:87]=channels;ins[100:94]=channels;
   ins[139:133]=s1;ins[146:140]=s2;ins[149]=kind==3&&t%2==1;
   dut.program_rom[0]=ins;rst=1;
   for(i=0;i<iw*ih*channels;i=i+1)begin load=1;la=src+i;ld=a[i];@(negedge clk);end
   if(kind==4)for(i=0;i<iw*ih*channels;i=i+1)begin load=1;la=1024+src+i;ld=b[i];@(negedge clk);end
   load=0;start=1;@(negedge clk);start=0;steps=0;
   while(!done&&steps<20000)begin @(negedge clk);steps=steps+1;end
   if(!done)$fatal(1,"misc watchdog t%0d kind%0d",t,kind);
   for(i=0;i<ow*oh*channels;i=i+1)begin
    case((dst+i)%4)
     0:actual=dut.fm0[(dst+i)/4];1:actual=dut.fm1[(dst+i)/4];2:actual=dut.fm2[(dst+i)/4];3:actual=dut.fm3[(dst+i)/4];
    endcase
    if(actual!==expected[i])$fatal(1,"misc mismatch t%0d kind%0d byte%0d got%h expected%h src%0d dst%0d",t,kind,i,actual,expected[i],src,dst);
    total=total+1;
   end
  end
  $display("PASS tb_yunet_vector_misc: 112 randomized pool/resize/add graphs, %0d exact bytes, in-place/reverse, all Add shifts and single-channel scalar fallback",total);$finish;
 end
 initial begin #100000000;$fatal(1,"vector misc watchdog");end
endmodule