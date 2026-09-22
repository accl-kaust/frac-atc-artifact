`resetall
`timescale 1ns / 1ps
`default_nettype none

// Logit, ln(x / (1 - x)), over a request of IEEE-754 singles, as a
// reconfigurable-slot module.  One response line per data line.
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

(* DONT_TOUCH = "yes" *)
module log #(
    parameter integer AXIS_DATA_W = 512 + 1 + 32,  // {meta, tlast, payload}
    parameter integer KEEP_W      = 1,
    parameter integer TDEST_W     = 1,
    parameter integer TID_W       = 1,
    parameter integer USER_W      = 1,
    parameter integer VALUE_W     = 32,
    parameter integer ALIGN_DEPTH = 32,                // > subtractor latency
    parameter integer FLUSH_CYCLES = 128        // > 12+29+23, the summed core latency
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

  localparam integer PAYLOAD_W  = 512;
  localparam integer LINE_BYTES = PAYLOAD_W / 8;  // 64
  localparam integer WORDS_PER_LINE = PAYLOAD_W / VALUE_W;  // 16
  localparam integer IDX_W = $clog2(WORDS_PER_LINE);  // 4
  localparam integer ALIGN_AW = $clog2(ALIGN_DEPTH);
  localparam integer FLUSH_W = $clog2(FLUSH_CYCLES + 1);
  localparam [31:0] FP_ONE = 32'h3F800000;  // 1.0f

  // ------------------------------------------------------------ rx / issue

  reg  [  PAYLOAD_W-1:0] line;
  reg  [      IDX_W-1:0] issue_idx;
  reg                    issuing;  // pushing this line's values in
  reg                    awaiting;  // values in flight, results pending
  reg                    line_last;
  reg                    frame_active;
  reg                    resp_valid;

  // The floating-point cores are generated with aclk only -- no aresetn (see
  // src/ip/gen_ip.tcl), so they cannot be reset. They are emptied by counting
  // data through instead:
  //   outstanding -- values issued but not yet returned. Results arriving with
  //                  outstanding == 0 are stale (pre-reset) and are dropped.
  //   flush_cnt   -- after reset, refuse new input until the cores have had
  //                  longer than their total latency to empty themselves.
  reg  [      IDX_W:0] outstanding;
  reg  [  FLUSH_W-1:0] flush_cnt;

  reg  [    TDEST_W-1:0] resp_tdest;
  reg  [      TID_W-1:0] resp_tid;
  reg  [     USER_W-1:0] resp_tuser;
  reg  [           15:0] resp_session;  // meta_TDATA[15:0], first beat
  reg  [           15:0] req_bytes;     // meta_TDATA[31:16], first beat
  reg                    saw_header;    // the request began with a header line

  // Slot boundary fields (see the header comment).
  wire [  PAYLOAD_W-1:0] rx_payload   = s_axis_tdata[PAYLOAD_W-1:0];
  wire                   rx_last      = s_axis_tdata[PAYLOAD_W];
  wire [           15:0] rx_session   = s_axis_tdata[PAYLOAD_W+1 +: 16];
  wire [           15:0] rx_req_bytes = s_axis_tdata[PAYLOAD_W+17 +: 16];

  wire                   is_header = (rx_payload[447:0] == {448{1'b1}});

  // One response line per data line: the request less its header line.
  wire [           15:0] resp_bytes = req_bytes - (saw_header ? LINE_BYTES[15:0] : 16'd0);

  assign s_axis_tready = !issuing && !awaiting && !resp_valid && (flush_cnt == 0);
  wire               rx_fire = s_axis_tvalid && s_axis_tready;

  wire [VALUE_W-1:0] x = line[issue_idx*VALUE_W+:VALUE_W];
  wire               last_val = (issue_idx == {IDX_W{1'b1}});

  // Both operand channels must accept together, or x and (1-x) desync.
  wire sub_a_ready, sub_b_ready;
  wire issue_fire = issuing && sub_a_ready && sub_b_ready;

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
      .m_axis_result_tready(1'b1),           // the packer is always ready
      .m_axis_result_tdata (log_res_data)
  );

  // ----------------------------------------------------------- pack / tx

  reg [  PAYLOAD_W-1:0] acc;
  reg [      IDX_W-1:0] pack_idx;
  reg                   resp_last;

  always @(posedge clk) begin
    if (rst) begin
      line         <= {PAYLOAD_W{1'b0}};
      issue_idx    <= {IDX_W{1'b0}};
      issuing      <= 1'b0;
      awaiting     <= 1'b0;
      line_last    <= 1'b0;
      frame_active <= 1'b0;
      resp_valid   <= 1'b0;
      resp_last    <= 1'b0;
      acc          <= {PAYLOAD_W{1'b0}};
      pack_idx     <= {IDX_W{1'b0}};
      resp_tdest   <= {TDEST_W{1'b0}};
      resp_tid     <= {TID_W{1'b0}};
      resp_tuser   <= {USER_W{1'b0}};
      resp_session <= 16'd0;
      req_bytes    <= 16'd0;
      saw_header   <= 1'b0;
      outstanding  <= 0;
      flush_cnt    <= FLUSH_CYCLES[FLUSH_W-1:0];
    end else begin

      if (rx_fire) begin
        if (!frame_active) begin
          resp_tdest   <= s_axis_tdest;
          resp_tid     <= s_axis_tid;
          resp_tuser   <= s_axis_tuser;
          resp_session <= rx_session;
          req_bytes    <= rx_req_bytes;
          saw_header   <= is_header;
        end
        frame_active <= 1'b1;
        if (!frame_active && is_header) begin
          // configuration line: consumed, carries no data
          frame_active <= !rx_last;
        end else begin
          line      <= rx_payload;
          line_last <= rx_last;
          issue_idx <= {IDX_W{1'b0}};
          issuing   <= 1'b1;
        end
      end

      if (issue_fire) begin
        issue_idx <= issue_idx + 1'b1;
        if (last_val) begin
          issuing  <= 1'b0;
          awaiting <= 1'b1;
        end
      end

      if (flush_cnt != 0) flush_cnt <= flush_cnt - 1'b1;

      // A result only counts if we are expecting one.
      if (log_res_valid && (outstanding != 0)) begin
        acc[pack_idx*VALUE_W+:VALUE_W] <= log_res_data;
        pack_idx <= pack_idx + 1'b1;
        if (pack_idx == {IDX_W{1'b1}}) begin
          resp_valid <= 1'b1;
          resp_last  <= line_last;   // the chain carries no tlast; we know it here
          awaiting   <= 1'b0;
        end
      end

      case ({issue_fire, (log_res_valid && (outstanding != 0))})
        2'b10:   outstanding <= outstanding + 1'b1;
        2'b01:   outstanding <= outstanding - 1'b1;
        default: ;
      endcase

      if (resp_valid && m_axis_tready) begin
        resp_valid <= 1'b0;
        if (resp_last) frame_active <= 1'b0;
      end
    end
  end

  // {meta_TDATA_out, tlast, payload}
  assign m_axis_tdata  = {resp_bytes, resp_session, resp_last, acc};
  assign m_axis_tvalid = resp_valid;
  assign m_axis_tlast  = resp_last;
  assign m_axis_tkeep  = {KEEP_W{1'b1}};
  assign m_axis_tstrb  = {KEEP_W{1'b1}};
  assign m_axis_tdest  = resp_tdest;
  assign m_axis_tid    = resp_tid;
  assign m_axis_tuser  = resp_tuser;

endmodule

`resetall
