module irig_timestamp (
	                   input             clk,
                       input             irig,
	                   input             irig_d0,
	                   input             irig_d1,
	                   input             irig_mark,
	                   output            pps,
                       output reg [5:0]  ts_second,
                       output reg [5:0]  ts_minute,
                       output reg [4:0]  ts_hour,
                       output reg [8:0]  ts_day,
                       output reg [6:0]  ts_year, 
	                   output reg [16:0] ts_sec_day,
	                   input             rst
                       );

    // State machine states
    localparam ST_UNLOCKED = 4'd0,
      ST_PRELOCK  = 4'b1,
      ST_START    = 4'd2,
      ST_SECOND   = 4'd3,
      ST_MINUTE   = 4'd4,
      ST_HOUR     = 4'd5,
      ST_DAY      = 4'd6,
      ST_DAY2     = 4'd7,
      ST_YEAR     = 4'd8,
      ST_UNUSED1  = 4'd9,
      ST_UNUSED2  = 4'd10,
      ST_SEC_DAY  = 4'd11,
      ST_SEC_DAY2 = 4'd12;

    // Timestamp selection for BCD decoding
    localparam TS_SELECT_SECOND = 5'b00001,
      TS_SELECT_MINUTE = 5'b00010,
      TS_SELECT_HOUR = 5'b00100,
      TS_SELECT_DAY = 5'b01000,
      TS_SELECT_YEAR = 5'b10000;

    // PPS generation
    reg                       pps_en, pps_en_dly;

    // Current and next state machine state
    reg [3:0]                 state, next_state;

    // Count IRIG bits within a state (100/sec)
    reg [3:0]                 irig_cnt;

    // Timestamp generation logic
    reg                       ts_reset;
    reg [16:0]                ts_sec_day_mask;

    // BCD decoding inputs
    reg [2:0]                 bcd_bit_idx;
    reg [1:0]                 bcd_digit_idx;
    reg                       bcd_bit;

    // PPS signal is generated by gating the IRIG signal
    // during the start marker.  Technically this should be a
    // negedge-registered signal, but it is directly
    // generated from the change in the IRIG signal so should
    // be set up.
    assign pps = irig & pps_en_dly;

    // Registers
    always @(posedge clk) begin
	    if (rst) begin
		    state <= ST_UNLOCKED;
            pps_en_dly <= 1'b0;
            irig_cnt <= 4'b0;
            ts_sec_day <= 17'b0;
        end
	    else begin
		    state <= next_state;
            pps_en_dly <= pps_en;

            // Count the IRIG bits received between every MARK
            if (irig_mark)
              irig_cnt <= 4'b0;
            else 
              irig_cnt <= irig_cnt + (irig_d0 | irig_d1);

            // Reset all the timestamp outputs
            if (ts_reset) begin
                ts_sec_day <= 17'b0;
            end
            else begin
                ts_sec_day = ts_sec_day | ts_sec_day_mask;
            end            
        end
    end

    // Accumulate the decoded BCD timestamp values    
    bcd_accumulator ba1(.bcd_bit_idx(bcd_bit_idx),
                        .bcd_digit_idx(bcd_digit_idx),
                        .bcd_bit(bcd_bit),
                        .ts_select(ts_select),
                        .clk(clk),
                        .accum_rst(ts_reset | rst)
                        .ts_second(ts_second),
                        .ts_minute(ts_minute),
                        .ts_hour(ts_hour),
                        .ts_day(ts_day),
                        .ts_year(ts_year));

    // IRIG decoding state machine
    // FIX ME add checks that cause loss of lock
    always @(*) begin
        next_state = state;
        pps_en = 1'b0;
        ts_reset = 1'b0;
        ts_sec_day_mask = 17'b0;
        ts_select = 5'b0;
	    case (state)
	      ST_UNLOCKED: begin
		      if (irig_mark)
			    next_state = ST_PRELOCK;
	      end
          ST_PRELOCK: begin
		      if (irig_mark)
			    next_state = ST_SECOND;
		      else if (irig_d0 || irig_d1)
			    next_state = ST_UNLOCKED;          
          end
	      ST_START: begin              
              pps_en = 1'b1;
		      if (irig_mark) begin
                  ts_reset = 1'b1;
				  next_state = ST_SECOND;
              end
	      end
	      ST_SECOND: begin
              ts_select = TS_SELECT_SECOND;
              bcd_bit_idx = (irig_cnt > 4'd4) ? irig_cnt-4'd5 : irig_cnt;
              bcd_digit_idx = (irig_cnt > 4'd4) ? 2'b1 : 2'b0;
              bcd_bit = irig_d1 && !(irig_cnt == 4'd4);                

		      if (irig_mark)
			    next_state = ST_MINUTE;
	      end
	      ST_MINUTE: begin
              ts_select = TS_SELECT_MINUTE;
              bcd_bit_idx = (irig_cnt > 4'd4) ? irig_cnt-4'd5 : irig_cnt;
              bcd_digit_idx = (irig_cnt > 4'd4) ? 2'b1 : 2'b0;
              bcd_bit = irig_d1 && !(irig_cnt == 4'd4) && !(irig_cnt == 4'd8);

		      if (irig_mark)
			    next_state = ST_HOUR;
	      end		
	      ST_HOUR: begin
              ts_select = TS_SELECT_HOUR;
              bcd_bit_idx = (irig_cnt > 4'd4) ? irig_cnt-4'd5 : irig_cnt;
              bcd_digit_idx = (irig_cnt > 4'd4) ? 2'b1 : 2'b0;
              bcd_bit = irig_d1 && !(irig_cnt == 4'd4) && !(irig_cnt >= 4'd8);

		      if (irig_mark)
			    next_state = ST_DAY;
	      end
	      ST_DAY: begin
              ts_select = TS_SELECT_DAY;
              bcd_bit_idx = (irig_cnt > 4'd4) ? irig_cnt-4'd5 : irig_cnt;
              bcd_digit_idx = (irig_cnt > 4'd4) ? 2'b1 : 2'b0;
              bcd_bit = irig_d1 && !(irig_cnt == 4'd4);

		      if (irig_mark)
			    next_state = ST_DAY2;
	      end
	      ST_DAY2: begin
              ts_select = TS_SELECT_DAY;
              bcd_bit_idx = irig_cnt;
              bcd_digit_idx = 2'b3;
              bcd_bit = irig_d1 && !(irig_cnt > 4'd1);

		      if (irig_mark)
			    next_state = ST_YEAR;
	      end
	      ST_YEAR: begin
              ts_select = TS_SELECT_YEAR;
              bcd_bit_idx = (irig_cnt > 4'd4) ? irig_cnt-4'd5 : irig_cnt;
              bcd_digit_idx = (irig_cnt > 4'd4) ? 2'b1 : 2'b0;
              bcd_bit = irig_d1 && !(irig_cnt == 4'd4);

		      if (irig_mark)
			    next_state = ST_UNUSED1;
	      end
	      ST_UNUSED1: begin
		      if (irig_mark)
			    next_state = ST_UNUSED2;
	      end
	      ST_UNUSED2: begin
		      if (irig_mark)
			    next_state = ST_SEC_DAY;
	      end
	      ST_SEC_DAY: begin
              ts_sec_day_mask = irig_d1 << irig_cnt;
		      if (irig_mark)
			    next_state = ST_SEC_DAY2;
	      end
	      ST_SEC_DAY2: begin
              ts_sec_day_mask = irig_d1 << (irig_cnt+9);
		      if (irig_mark) begin
			      next_state = ST_START;
                  pps_en = 1'b1;
              end
	      end
	    endcase
    end
    
endmodule
