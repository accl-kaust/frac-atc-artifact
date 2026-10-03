`resetall
`timescale 1ns / 1ps
`default_nettype none

// Top-k selection: the core of the top_k reconfigurable module.  top_k.v
// wraps it in the slot boundary's credit ends.
//
// Slot boundary, the same as pattern_slot.v / or_slot.v (the upstream offrac
// workload ports flattened onto one AXI-Stream), in both directions:
//   tdata[544:513] = meta      request: {request_bytes, session}  (meta_TDATA)
//                              response: {resp_bytes, session} (meta_TDATA_out)
//   tdata[512]     = tlast, in-band (the tlast line duplicates it)
//   tdata[511:0]   = payload
// pkt_sender takes the meta of the response beat that carries tlast as the
// TCP tx metadata, so resp_bytes must be the number of bytes in the response.
// The response is always one 64-byte beat, so the meta is {64, session} --
// the constant upstream pkt_logic.v applied to top_k ("All top-k workload has
// 64B content in the packet").  The session is taken from the request's first
// beat; the request size in meta_TDATA[31:16] is not needed here.
//
// A line a cycle.  Inserting a line's 16 values into a sorted array one at a
// time, as this core used to, cost 17 cycles a line; here a line is sorted
// whole and merged whole, so the core keeps up with the slot.  A 4 KB request
// took 5.4 us from its first line in to its response out at 200 MHz, and
// takes 0.41.
//
//   s_axis -> bitonic sort (10 levels, 2 to a register) -> merge into the
//             running top 16 -> ... last line ... -> merge the four -> m_axis
//
// Merging two descending lists a and b into their top 16 is
//   c[i] = max(a[i], b[15-i])                (the 16 largest, bitonic)
// and a bitonic merge of c (4 compare-exchange levels).  That is 5 levels, too
// many for one cycle, and it feeds back: the merged list is what the next line
// merges into.  So there are four running lists, travelling round a ring of
// four registers -- [max, cas 8] -> [cas 4] -> [cas 2] -> [cas 1] -> back -- and
// a sorted line merges into whichever list is at the ring's entry, where every
// list is fully merged again.  Each list comes round every 4 cycles, so a line
// can merge every cycle.  With no line to merge, a list goes round unchanged:
// max(a[i], 0) is a[i] for unsigned values, and a sorted list is a bitonic
// merge's fixed point.
//
// After the request's last line the four lists are merged into one, using the
// same ring: a list arriving at the entry is parked in `park` if that is
// empty, or merged with the one parked there; when one list is left it is the
// result.  That takes at most 12 cycles.
//
// Nothing clears the ring's data.  A flag travels with each list saying
// whether it holds any, and a list without reads as zeros at the entry, so a
// new request starts by clearing four flags rather than 2048 registers.
//
// Values are unsigned.  Fewer than 16 values leave zeros in the result, as the
// old array of zeros did.

module top_k_core #(
    parameter integer AXIS_DATA_W = 512 + 1 + 32,  // {meta, tlast, payload}
    parameter integer KEEP_W      = 1,
    parameter integer TDEST_W     = 1,
    parameter integer TID_W       = 1,
    parameter integer USER_W      = 1,
    parameter integer VALUE_W     = 32,
    parameter integer TOP_K_NUM   = 16                // <= 16: the mask field is 16 bits
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
  localparam integer N          = PAYLOAD_W / VALUE_W;  // 16 values a line
  localparam integer MASK_W     = 16;
  localparam integer RING       = 4;              // registers round the merge ring
  localparam integer SORT_STAGES = 5;             // 10 levels, 2 to a register

  // ---------------------------------------------------------------- input

  reg frame_active;  // a request is in progress at s_axis
  reg input_done;    // its last beat has been taken
  reg resp_valid;

  reg [MASK_W-1:0] kmask;

  reg [TDEST_W-1:0] resp_tdest;
  reg [TID_W-1:0] resp_tid;
  reg [USER_W-1:0] resp_tuser;
  reg [15:0] resp_session;  // meta_TDATA[15:0] of the request's first beat

  // Slot boundary fields (see the header comment).
  wire [PAYLOAD_W-1:0] rx_payload = s_axis_tdata[PAYLOAD_W-1:0];
  wire                 rx_last    = s_axis_tdata[PAYLOAD_W];
  wire [         15:0] rx_session = s_axis_tdata[PAYLOAD_W+1 +: 16];

  // Header line: the fRAC request header writes 0xff over bytes 0-55.
  // Delete this and the `is_header` branch below if the scheduler ever
  // strips the header before the slot sees it.
  wire is_header = (rx_payload[447:0] == {448{1'b1}});

  // one request at a time: from its last beat to its response, take nothing
  assign s_axis_tready = !input_done;

  wire rx_fire = s_axis_tvalid && s_axis_tready;
  wire rx_data = rx_fire && !(!frame_active && is_header);

  // ----------------------------------------------------------------- sort

  // Bitonic sort, descending.  Level (k, j) compare-exchanges i with i ^ j,
  // larger first where i & k is 0, smaller first elsewhere; k = 16 sorts the
  // whole line descending.
  wire [PAYLOAD_W-1:0] lvl [0:10];
  reg  [PAYLOAD_W-1:0] sort_reg [1:SORT_STAGES];
  reg  [SORT_STAGES:1] sort_v;

  top_k_cas #(.K( 2), .J(1), .W(VALUE_W)) l0 (.in(rx_payload),  .out(lvl[1]));
  top_k_cas #(.K( 4), .J(2), .W(VALUE_W)) l1 (.in(lvl[1]),      .out(lvl[2]));
  top_k_cas #(.K( 4), .J(1), .W(VALUE_W)) l2 (.in(sort_reg[1]), .out(lvl[3]));
  top_k_cas #(.K( 8), .J(4), .W(VALUE_W)) l3 (.in(lvl[3]),      .out(lvl[4]));
  top_k_cas #(.K( 8), .J(2), .W(VALUE_W)) l4 (.in(sort_reg[2]), .out(lvl[5]));
  top_k_cas #(.K( 8), .J(1), .W(VALUE_W)) l5 (.in(lvl[5]),      .out(lvl[6]));
  top_k_cas #(.K(16), .J(8), .W(VALUE_W)) l6 (.in(sort_reg[3]), .out(lvl[7]));
  top_k_cas #(.K(16), .J(4), .W(VALUE_W)) l7 (.in(lvl[7]),      .out(lvl[8]));
  top_k_cas #(.K(16), .J(2), .W(VALUE_W)) l8 (.in(sort_reg[4]), .out(lvl[9]));
  top_k_cas #(.K(16), .J(1), .W(VALUE_W)) l9 (.in(lvl[9]),      .out(lvl[10]));

  always @(posedge clk) begin
    sort_reg[1] <= lvl[2];
    sort_reg[2] <= lvl[4];
    sort_reg[3] <= lvl[6];
    sort_reg[4] <= lvl[8];
    sort_reg[5] <= lvl[10];
  end

  wire [PAYLOAD_W-1:0] sorted   = sort_reg[SORT_STAGES];
  wire                 sorted_v = sort_v[SORT_STAGES];

  // ----------------------------------------------------------- merge ring

  // ring[0] is the entry: the list there is fully merged.
  reg  [PAYLOAD_W-1:0] ring [0:RING-1];
  reg  [RING-1:0]      has;      // the list in each register holds values
  reg  [PAYLOAD_W-1:0] park;
  reg                  park_full;
  reg                  reducing; // merging the four lists into one

  // the list at the entry, zeros if it holds none
  wire [PAYLOAD_W-1:0] entry = has[0] ? ring[0] : {PAYLOAD_W{1'b0}};

  // The reduction is done when one list is left and it is back at the entry,
  // or none was ever filled.
  wire                 one_left    = (has == {{(RING-1){1'b0}}, 1'b1});
  wire                 reduce_done = reducing && !park_full && (one_left || (has == {RING{1'b0}}));

  // At the entry: merge a sorted line, or a parked list, or nothing.
  wire                 park_here  = reducing && has[0] && !park_full && !one_left;  // park the list
  wire                 merge_park = reducing && has[0] &&  park_full;  // merge it with the parked one
  wire [PAYLOAD_W-1:0] merge_in   = sorted_v ? sorted : (merge_park ? park : {PAYLOAD_W{1'b0}});

  // c[i] = max(a[i], b[N-1-i]): the 16 largest of both, a bitonic sequence
  reg  [PAYLOAD_W-1:0] top_half;
  integer i;
  always @* begin
    for (i = 0; i < N; i = i + 1) begin
      if (entry[i*VALUE_W +: VALUE_W] > merge_in[(N-1-i)*VALUE_W +: VALUE_W])
        top_half[i*VALUE_W +: VALUE_W] = entry[i*VALUE_W +: VALUE_W];
      else
        top_half[i*VALUE_W +: VALUE_W] = merge_in[(N-1-i)*VALUE_W +: VALUE_W];
    end
  end

  wire [PAYLOAD_W-1:0] m8, m4, m2, m1;
  top_k_cas #(.K(16), .J(8), .W(VALUE_W)) mg8 (.in(top_half), .out(m8));
  top_k_cas #(.K(16), .J(4), .W(VALUE_W)) mg4 (.in(ring[1]),  .out(m4));
  top_k_cas #(.K(16), .J(2), .W(VALUE_W)) mg2 (.in(ring[2]),  .out(m2));
  top_k_cas #(.K(16), .J(1), .W(VALUE_W)) mg1 (.in(ring[3]),  .out(m1));

  // ------------------------------------------------------------- response

  reg [PAYLOAD_W-1:0] resp_data;
  wire resp_fire = resp_valid && m_axis_tready;

  // round the ring, 0 -> 1 -> 2 -> 3 -> 0
  always @(posedge clk) begin
    ring[1] <= m8;
    ring[2] <= m4;
    ring[3] <= m2;
    ring[0] <= m1;
    if (park_here) park <= entry;
  end

  integer j;
  always @(posedge clk) begin
    if (rst) begin
      has          <= {RING{1'b0}};
      park_full    <= 1'b0;
      reducing     <= 1'b0;
      sort_v       <= {SORT_STAGES{1'b0}};
      kmask        <= {MASK_W{1'b1}};
      frame_active <= 1'b0;
      input_done   <= 1'b0;
      resp_valid   <= 1'b0;
      resp_tdest   <= {TDEST_W{1'b0}};
      resp_tid     <= {TID_W{1'b0}};
      resp_tuser   <= {USER_W{1'b0}};
      resp_session <= 16'd0;
    end else begin

      sort_v <= {sort_v[SORT_STAGES-1:1], rx_data};

      if (rx_fire) begin
        if (!frame_active) begin
          resp_tdest   <= s_axis_tdest;
          resp_tid     <= s_axis_tid;
          resp_tuser   <= s_axis_tuser;
          resp_session <= rx_session;
          if (is_header) kmask <= rx_payload[495:480];
        end
        frame_active <= 1'b1;
        if (rx_last) input_done <= 1'b1;
      end

      // The flags go round with their lists.  The list leaving the entry
      // holds values if it did and was not parked, or if a line was merged
      // into it; a parked list's values merge into the next one.
      has <= {has[RING-2:1], (has[0] && !park_here) || sorted_v, has[RING-1]};

      if (park_here) begin
        park_full <= 1'b1;
      end else if (merge_park) begin
        park_full <= 1'b0;
      end

      // every line sorted and merged: reduce the four lists to one
      if (input_done && !reducing && !resp_valid && (sort_v == 0)) reducing <= 1'b1;

      if (reduce_done) begin
        reducing <= 1'b0;
        resp_valid <= 1'b1;
        for (j = 0; j < N; j = j + 1)
          resp_data[j*VALUE_W +: VALUE_W] <= (j < TOP_K_NUM && kmask[j]) ? entry[j*VALUE_W +: VALUE_W]
                                                                         : {VALUE_W{1'b0}};
      end

      // Response accepted: clear down for the next request.
      if (resp_fire) begin
        resp_valid   <= 1'b0;
        frame_active <= 1'b0;
        input_done   <= 1'b0;
        kmask        <= {MASK_W{1'b1}};
        has          <= {RING{1'b0}};
        park_full    <= 1'b0;
      end
    end
  end

`ifdef SIMULATION
  always @(posedge clk) begin
    if (!rst && reducing && sorted_v) begin
      $fatal(1, "%m: a sorted line arrived while the lists were being merged");
    end
  end
`endif

  // {meta_TDATA_out = {64, session}, tlast, payload}: one beat per request
  assign m_axis_tdata  = {LINE_BYTES[15:0], resp_session, 1'b1, resp_data};
  assign m_axis_tvalid = resp_valid;
  assign m_axis_tlast  = 1'b1;
  assign m_axis_tkeep  = {KEEP_W{1'b1}};
  assign m_axis_tstrb  = {KEEP_W{1'b1}};
  assign m_axis_tdest  = resp_tdest;
  assign m_axis_tid    = resp_tid;
  assign m_axis_tuser  = resp_tuser;

endmodule

// One compare-exchange level of a bitonic network over a line of 16 values:
// i against i ^ J, the larger first where i & K is 0 and the smaller first
// elsewhere.  With K at least the line length every pair puts its larger
// value first, which is the bitonic merge's descending half-cleaner.
module top_k_cas #(
    parameter integer K = 2,
    parameter integer J = 1,
    parameter integer W = 32,
    parameter integer N = 16
) (
    input  wire [N*W-1:0] in,
    output reg  [N*W-1:0] out
);
  integer i;
  always @* begin
    out = in;
    for (i = 0; i < N; i = i + 1) begin
      if ((i ^ J) > i) begin
        if (((i & K) == 0) ? (in[i*W +: W] < in[(i^J)*W +: W])
                           : (in[i*W +: W] > in[(i^J)*W +: W])) begin
          out[i*W +: W]     = in[(i^J)*W +: W];
          out[(i^J)*W +: W] = in[i*W +: W];
        end
      end
    end
  end
endmodule

`resetall
