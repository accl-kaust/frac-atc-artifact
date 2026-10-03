`resetall
`timescale 1ns / 1ps
`default_nettype none

// Logit, ln(x / (1 - x)), over a request of IEEE-754 singles: the core of
// the log reconfigurable module.  One response line per data line.  log.v
// wraps it in the slot boundary's credit ends.
//
// Slot boundary, the same as pattern_slot.v / or_slot.v (the upstream offrac
// workload ports flattened onto one AXI-Stream), in both directions:
//   tdata[544:513] = meta      request: {request_bytes, session}  (meta_TDATA)
//                              response: {resp_bytes, session} (meta_TDATA_out)
//   tdata[512]     = tlast, in-band (the tlast line duplicates it)
//   tdata[511:0]   = payload
// meta_TDATA[31:16] is the size of the whole request (the header's
// packet_size, put there by the scheduler; see scheduler.v rx_req_size).
// pkt_sender takes the meta of the response beat that carries tlast as the
// TCP tx metadata, so resp_bytes must be the number of bytes in the response:
// one line per data line, i.e. the request size less the header line when the
// request had one.  Both fields come from the request's meta; nothing is
// counted here, as in pattern_slot.v, which forwards the meta unchanged.
//
// Streaming.  The three cores are one pipeline of 12 + 29 + 23 = 64 cycles
// that takes a value every cycle.  A line's 16 values go in on 16 cycles in a
// row and the next line's follow straight after, so a request of N data lines
// costs 16 N cycles plus the pipeline once.  Taking one line at a time, as
// this core used to, cost 16 + 64 cycles a line: a 4 KB request took 25.8 us
// from its first line in to its last response out at 200 MHz, and takes 5.4.
//
//   s_axis -> in_line -> cur_line -- x --> 1 - x --> x / (1 - x) --> ln --> pack -> out FIFO -> m_axis
//                                     \--> align FIFO --/
//
// in_line holds the next line while cur_line's values are issued, so the
// issue stage never waits for one and s_axis_tready is a register.
//
// Nothing stops a value once it is in the cores -- the last one's result is
// always taken -- so every line's result needs somewhere to go: the output
// FIFO.  A data line is accepted only while fewer than OUT_DEPTH lines are
// between s_axis and m_axis, which is what the FIFO holds, so it cannot
// overflow however long m_axis_tready stays low.  A line spends about 100
// cycles on that path, so OUT_DEPTH 8 keeps a line going in every 16.
//
// Requests follow one another into the cores, so the line being packed may
// belong to an earlier request than the one arriving.  Each data line's
// response meta, tlast and sideband are queued as it is accepted and taken
// when its 16th result is packed.

module log_core #(
    parameter integer AXIS_DATA_W  = 512 + 1 + 32,  // {meta, tlast, payload}
    parameter integer KEEP_W       = 1,
    parameter integer TDEST_W      = 1,
    parameter integer TID_W        = 1,
    parameter integer USER_W       = 1,
    parameter integer VALUE_W      = 32,
    parameter integer ALIGN_DEPTH  = 32,            // > subtractor latency
    parameter integer FLUSH_CYCLES = 128,           // > 12+29+23, the summed core latency
    parameter integer OUT_DEPTH    = 8              // response lines held, a power of two
) (
    input wire clk,
    input wire rst,

    input  wire [AXIS_DATA_W-1:0] s_axis_tdata,
    input  wire [     KEEP_W-1:0] s_axis_tkeep,
    input  wire [     KEEP_W-1:0] s_axis_tstrb,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,
    input  wire                   s_axis_tlast,
    input  wire [    TDEST_W-1:0] s_axis_tdest,
    input  wire [      TID_W-1:0] s_axis_tid,
    input  wire [     USER_W-1:0] s_axis_tuser,

    output wire [AXIS_DATA_W-1:0] m_axis_tdata,
    output wire [     KEEP_W-1:0] m_axis_tkeep,
    output wire [     KEEP_W-1:0] m_axis_tstrb,
    output wire                   m_axis_tvalid,
    input  wire                   m_axis_tready,
    output wire                   m_axis_tlast,
    output wire [    TDEST_W-1:0] m_axis_tdest,
    output wire [      TID_W-1:0] m_axis_tid,
    output wire [     USER_W-1:0] m_axis_tuser
);

  localparam integer PAYLOAD_W      = 512;
  localparam integer LINE_BYTES     = PAYLOAD_W / 8;            // 64
  localparam integer WORDS_PER_LINE = PAYLOAD_W / VALUE_W;      // 16
  localparam integer IDX_W          = $clog2(WORDS_PER_LINE);   // 4
  localparam integer ALIGN_AW       = $clog2(ALIGN_DEPTH);
  localparam integer FLUSH_W        = $clog2(FLUSH_CYCLES + 1);
  localparam integer HELD_W         = $clog2(OUT_DEPTH + 1);
  localparam integer OUTST_W        = $clog2(OUT_DEPTH * WORDS_PER_LINE + 1);
  localparam integer SIDE_W         = 1 + 32 + TDEST_W + TID_W + USER_W;   // {last, meta, tdest, tid, tuser}
  localparam integer OUT_W          = AXIS_DATA_W + TDEST_W + TID_W + USER_W;
  localparam [HELD_W-1:0] HELD_MAX  = OUT_DEPTH;
  localparam [31:0] FP_ONE = 32'h3F800000;  // 1.0f

  // ------------------------------------------------------------- receive

  // Slot boundary fields (see the header comment).
  wire [  PAYLOAD_W-1:0] rx_payload   = s_axis_tdata[PAYLOAD_W-1:0];
  wire                   rx_last      = s_axis_tdata[PAYLOAD_W];
  wire [           15:0] rx_session   = s_axis_tdata[PAYLOAD_W+1 +: 16];
  wire [           15:0] rx_req_bytes = s_axis_tdata[PAYLOAD_W+17 +: 16];

  wire                   is_header = (rx_payload[447:0] == {448{1'b1}});

  reg                    frame_active;  // a request has begun at s_axis and not ended
  reg  [           15:0] req_bytes;     // meta_TDATA[31:16], first beat
  reg  [           15:0] req_session;   // meta_TDATA[15:0], first beat
  reg                    saw_header;    // the request began with a header line
  reg  [    TDEST_W-1:0] req_tdest;
  reg  [      TID_W-1:0] req_tid;
  reg  [     USER_W-1:0] req_tuser;

  reg  [  PAYLOAD_W-1:0] in_line;
  reg                    in_valid;

  reg  [     HELD_W-1:0] held;          // data lines accepted and not yet out of m_axis

  // The floating-point cores are generated with aclk only -- no aresetn (see
  // src/ip/gen_ip.tcl), so they cannot be reset. They are emptied by counting
  // data through instead:
  //   outstanding -- values issued but not yet returned. Results arriving with
  //                  outstanding == 0 are stale (pre-reset) and are dropped.
  //   flush_cnt   -- after reset, refuse new input until the cores have had
  //                  longer than their total latency to empty themselves.
  reg  [    FLUSH_W-1:0] flush_cnt;

  assign s_axis_tready = !in_valid && (held < HELD_MAX) && (flush_cnt == 0);

  wire                   rx_fire  = s_axis_tvalid && s_axis_tready;
  wire                   rx_first = !frame_active;
  wire                   rx_data  = rx_fire && !(rx_first && is_header);

  // A data line's response meta and sideband: the first beat's own, or the
  // ones its request began with.  One response line per data line: the
  // request less its header line.
  wire [           15:0] line_resp_bytes = rx_first ? rx_req_bytes
                                         : req_bytes - (saw_header ? LINE_BYTES[15:0] : 16'd0);
  wire [           15:0] line_session    = rx_first ? rx_session   : req_session;
  wire [    TDEST_W-1:0] line_tdest      = rx_first ? s_axis_tdest : req_tdest;
  wire [      TID_W-1:0] line_tid        = rx_first ? s_axis_tid   : req_tid;
  wire [     USER_W-1:0] line_tuser      = rx_first ? s_axis_tuser : req_tuser;

  // ---------------------------------------------------------------- issue

  reg  [  PAYLOAD_W-1:0] cur_line;
  reg                    cur_valid;     // cur_line's values are being issued
  reg  [      IDX_W-1:0] cur_idx;

  wire [    VALUE_W-1:0] x = cur_line[cur_idx*VALUE_W+:VALUE_W];

  // Both operand channels must accept together, or x and (1-x) desync.
  wire sub_a_ready, sub_b_ready;
  wire issue_fire = cur_valid && sub_a_ready && sub_b_ready;
  wire cur_done   = issue_fire && (cur_idx == {IDX_W{1'b1}});
  wire cur_take   = in_valid && (!cur_valid || cur_done);

  always @(posedge clk) begin
    if (cur_take) cur_line <= in_line;
  end

  // ----------------------------------------------- 1 - x   (Add_Subtract)

  wire sub_res_valid;
  wire [31:0] sub_res_data;
  wire div_a_ready, div_b_ready;
  wire sub_res_ready = div_a_ready && div_b_ready;

  floating_point_0 subtract_inst (
      .aclk                (clk),
      .s_axis_a_tvalid     (issue_fire),
      .s_axis_a_tready     (sub_a_ready),
      .s_axis_a_tdata      (FP_ONE),
      .s_axis_b_tvalid     (issue_fire),
      .s_axis_b_tready     (sub_b_ready),
      .s_axis_b_tdata      (x),
      .m_axis_result_tvalid(sub_res_valid),
      .m_axis_result_tready(sub_res_ready),
      .m_axis_result_tdata (sub_res_data)
  );

  // ------------------------------------- operand alignment (kept on purpose)

  reg [VALUE_W-1:0] align_mem[0:ALIGN_DEPTH-1];
  reg [ALIGN_AW:0] align_wr, align_rd;
  wire [VALUE_W-1:0] x_aligned = align_mem[align_rd[ALIGN_AW-1:0]];

  // Values issued to the subtractor whose results have not come back yet.
  // This is state the packer's `outstanding` counter does not cover: the align
  // FIFO sits at the SUBTRACTOR stage, not the far end of the chain. Resetting
  // align_wr/align_rd is not enough on its own, because a reset taken with
  // values in flight leaves stale results in the subtractor. Each of those
  // asserts sub_res_valid afterwards and would pop the FIFO while align_wr
  // stands still (nothing is being issued during the flush window), leaving
  // align_rd permanently ahead of align_wr -- so every later operand pair is
  // skewed, not just the discarded request's.
  reg [ALIGN_AW:0] sub_pending;
  wire sub_res_take = sub_res_valid && sub_res_ready;
  wire sub_res_real = sub_res_valid && (sub_pending != 0);
  wire align_pop = sub_res_take && (sub_pending != 0);

  always @(posedge clk) begin
    if (rst) begin
      align_wr    <= 0;
      align_rd    <= 0;
      sub_pending <= 0;
    end else begin
      if (issue_fire) begin
        align_mem[align_wr[ALIGN_AW-1:0]] <= x;
        align_wr <= align_wr + 1'b1;
      end
      if (align_pop) align_rd <= align_rd + 1'b1;

      case ({issue_fire, sub_res_take})
        2'b10:   sub_pending <= sub_pending + 1'b1;
        2'b01:   if (sub_pending != 0) sub_pending <= sub_pending - 1'b1;
        default: ;
      endcase
    end
  end

  // ------------------------------------------- x / (1 - x)      (Divide)

  wire div_res_valid, div_res_ready;
  wire [31:0] div_res_data;

  floating_point_1 divide_inst (
      .aclk                (clk),
      .s_axis_a_tvalid     (align_pop),
      .s_axis_a_tready     (div_a_ready),
      .s_axis_a_tdata      (x_aligned),
      .s_axis_b_tvalid     (sub_res_real),
      .s_axis_b_tready     (div_b_ready),
      .s_axis_b_tdata      (sub_res_data),
      .m_axis_result_tvalid(div_res_valid),
      .m_axis_result_tready(div_res_ready),
      .m_axis_result_tdata (div_res_data)
  );

  // ------------------------------------------------ ln(.)    (Logarithm)

  wire log_res_valid;
  wire [31:0] log_res_data;

  floating_point_2 log_inst (
      .aclk                (clk),
      .s_axis_a_tvalid     (div_res_valid),
      .s_axis_a_tready     (div_res_ready),
      .s_axis_a_tdata      (div_res_data),
      .m_axis_result_tvalid(log_res_valid),
      .m_axis_result_tready(1'b1),           // the output FIFO has room, see above
      .m_axis_result_tdata (log_res_data)
  );

  // ----------------------------------------------------------------- pack

  reg  [  PAYLOAD_W-1:0] acc;           // words 0..14 of the line being packed
  reg  [      IDX_W-1:0] pack_idx;
  reg  [    OUTST_W-1:0] outstanding;

  // A result only counts if we are expecting one.
  wire res_take  = log_res_valid && (outstanding != 0);
  wire line_done = res_take && (pack_idx == {IDX_W{1'b1}});

  // per data line, in order: {tlast, response meta, sideband}
  wire               side_valid;
  wire [ SIDE_W-1:0] side_data;

  axis_fifo_taxi #(
      .DATA_WIDTH(SIDE_W),
      .DEPTH     (OUT_DEPTH)
  ) side_fifo_inst (
      .clk          (clk),
      .rst          (rst),
      .s_axis_tvalid(rx_data),
      .s_axis_tready(),
      .s_axis_tdata ({rx_last, line_resp_bytes, line_session, line_tdest, line_tid, line_tuser}),
      .m_axis_tvalid(side_valid),
      .m_axis_tready(line_done),
      .m_axis_tdata (side_data)
  );

  wire                   side_last  = side_data[SIDE_W-1];
  wire [           31:0] side_meta  = side_data[SIDE_W-2 -: 32];
  wire [TDEST_W+TID_W+USER_W-1:0] side_band = side_data[TDEST_W+TID_W+USER_W-1:0];

  // the finished line: word 15 is the result arriving now
  wire [  PAYLOAD_W-1:0] done_payload = {log_res_data, acc[PAYLOAD_W-VALUE_W-1:0]};

  wire                   out_s_ready;
  wire                   out_valid;
  wire [      OUT_W-1:0] out_data;

  // {tdest, tid, tuser, meta_TDATA_out, tlast, payload}
  axis_fifo_taxi #(
      .DATA_WIDTH(OUT_W),
      .DEPTH     (OUT_DEPTH)
  ) out_fifo_inst (
      .clk          (clk),
      .rst          (rst),
      .s_axis_tvalid(line_done),
      .s_axis_tready(out_s_ready),
      .s_axis_tdata ({side_band, side_meta, side_last, done_payload}),
      .m_axis_tvalid(out_valid),
      .m_axis_tready(m_axis_tready),
      .m_axis_tdata (out_data)
  );

  wire out_fire = out_valid && m_axis_tready;

  // ------------------------------------------------------------- control

  always @(posedge clk) begin
    if (rst) begin
      frame_active <= 1'b0;
      req_bytes    <= 16'd0;
      req_session  <= 16'd0;
      saw_header   <= 1'b0;
      req_tdest    <= {TDEST_W{1'b0}};
      req_tid      <= {TID_W{1'b0}};
      req_tuser    <= {USER_W{1'b0}};
      in_valid     <= 1'b0;
      cur_valid    <= 1'b0;
      cur_idx      <= {IDX_W{1'b0}};
      held         <= {HELD_W{1'b0}};
      acc          <= {PAYLOAD_W{1'b0}};
      pack_idx     <= {IDX_W{1'b0}};
      outstanding  <= {OUTST_W{1'b0}};
      flush_cnt    <= FLUSH_CYCLES[FLUSH_W-1:0];
    end else begin

      if (rx_fire) begin
        if (rx_first) begin
          req_bytes   <= rx_req_bytes;
          req_session <= rx_session;
          saw_header  <= is_header;
          req_tdest   <= s_axis_tdest;
          req_tid     <= s_axis_tid;
          req_tuser   <= s_axis_tuser;
        end
        // a header line is consumed here and carries no data; a header with
        // tlast is a whole (empty) request
        frame_active <= !rx_last;
      end

      if (rx_data) begin
        in_valid <= 1'b1;
      end else if (cur_take) begin
        in_valid <= 1'b0;
      end

      if (cur_take) begin
        cur_valid <= 1'b1;
        cur_idx   <= {IDX_W{1'b0}};
      end else if (issue_fire) begin
        cur_idx <= cur_idx + 1'b1;
        if (cur_done) cur_valid <= 1'b0;
      end

      case ({rx_data, out_fire})
        2'b10:   held <= held + 1'b1;
        2'b01:   held <= held - 1'b1;
        default: ;
      endcase

      if (flush_cnt != 0) flush_cnt <= flush_cnt - 1'b1;

      if (res_take) begin
        acc[pack_idx*VALUE_W+:VALUE_W] <= log_res_data;
        pack_idx <= pack_idx + 1'b1;
      end

      case ({issue_fire, res_take})
        2'b10:   outstanding <= outstanding + 1'b1;
        2'b01:   outstanding <= outstanding - 1'b1;
        default: ;
      endcase
    end
  end

  always @(posedge clk) begin
    if (rx_data) in_line <= rx_payload;
  end

`ifdef SIMULATION
  always @(posedge clk) begin
    if (!rst && line_done && !side_valid) begin
      $fatal(1, "%m: a line was packed with no request info queued for it");
    end
    if (!rst && line_done && !out_s_ready) begin
      $fatal(1, "%m: the output FIFO was full when a line was packed");
    end
  end
`endif

  // {meta_TDATA_out, tlast, payload}, and the sideband its request began with
  assign m_axis_tdata  = out_data[AXIS_DATA_W-1:0];
  assign m_axis_tvalid = out_valid;
  assign m_axis_tlast  = out_data[PAYLOAD_W];
  assign m_axis_tkeep  = {KEEP_W{1'b1}};
  assign m_axis_tstrb  = {KEEP_W{1'b1}};
  assign {m_axis_tdest, m_axis_tid, m_axis_tuser} = out_data[OUT_W-1:AXIS_DATA_W];

endmodule

`resetall
