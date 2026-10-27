// Debounced level controller for the four HX1P35A slide switches.
// The board switches are active-low because the pins use pull-ups. Unlike a
// push button, a switch is represented as a stable level and must not create
// a one-shot event.
module vision_switch_ctrl #(
    parameter integer DEBOUNCE_CYCLES = 750000,SAMPLE_CYCLES=1
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [3:0] switches_n,
    output wire [3:0] feature_enable
);
    localparam integer TICK=(SAMPLE_CYCLES>1&&DEBOUNCE_CYCLES>=SAMPLE_CYCLES*2)?SAMPLE_CYCLES:1;
    localparam integer STEPS=TICK==1?DEBOUNCE_CYCLES:(DEBOUNCE_CYCLES+TICK-1)/TICK+1;
    localparam integer CW=STEPS<2?1:$clog2(STEPS);
    localparam integer TW=TICK<2?1:$clog2(TICK);
    reg[TW-1:0] sample_count;
    wire sample_tick=sample_count==TICK-1;
    always @(posedge clk or negedge rst_n)begin
     if(!rst_n)sample_count<=0;
     else if(sample_tick)sample_count<=0;else sample_count<=sample_count+1'b1;
    end

    reg [3:0] sync1;
    reg [3:0] sync2;
    reg [3:0] stable;
    reg [CW-1:0] count0;
    reg [CW-1:0] count1;
    reg [CW-1:0] count2;
    reg [CW-1:0] count3;

    assign feature_enable = ~stable;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync1  <= 4'b1111;
            sync2  <= 4'b1111;
            stable <= 4'b1111;
            count0 <= {CW{1'b0}};
            count1 <= {CW{1'b0}};
            count2 <= {CW{1'b0}};
            count3 <= {CW{1'b0}};
        end else begin
            sync1 <= switches_n;
            sync2 <= sync1;

            if (sync2[0] != stable[0]) begin
              if(sample_tick)begin
                if (count0 == STEPS - 1) begin
                    stable[0] <= sync2[0];
                    count0 <= 0;
                end else count0 <= count0 + 1'b1;
            end
            end else count0 <= 0;

            if (sync2[1] != stable[1]) begin
              if(sample_tick)begin
                if (count1 == STEPS - 1) begin
                    stable[1] <= sync2[1];
                    count1 <= 0;
                end else count1 <= count1 + 1'b1;
            end
            end else count1 <= 0;

            if (sync2[2] != stable[2]) begin
              if(sample_tick)begin
                if (count2 == STEPS - 1) begin
                    stable[2] <= sync2[2];
                    count2 <= 0;
                end else count2 <= count2 + 1'b1;
            end
            end else count2 <= 0;

            if (sync2[3] != stable[3]) begin
              if(sample_tick)begin
                if (count3 == STEPS - 1) begin
                    stable[3] <= sync2[3];
                    count3 <= 0;
                end else count3 <= count3 + 1'b1;
            end
            end else count3 <= 0;
        end
    end
endmodule
