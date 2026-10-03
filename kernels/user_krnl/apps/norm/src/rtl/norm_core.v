`resetall
`timescale 1ns / 1ps
`default_nettype none

//
// norm_core
//
// Min-max normalisation over a request of IEEE-754 single-precision values:
// the core of the norm reconfigurable module.  norm.v wraps it in the slot
// boundary's credit ends.  Same interface as or_slot / pattern_slot.
//
//     y = (x - min) / (max - min)        min, max taken over the whole request
//
// This is inherently TWO PASS: nothing can be normalised until every value has
// been seen. Pass 1 scans for min/max while the request is received; pass 2
// replays it through subtract and divide.
//
// Pass 1 takes a line every cycle.  Each line's 16 values go through a
// min/max tree -- pairs, then fours, eights and the line, two levels to a
// register -- into the running min and max, so the scan keeps up with the
// slot and is over three cycles after the last line arrives.
//
// Pass 2 streams.  The line buffer is read a line ahead of the one being
// issued, so the subtractor gets a value every cycle, and (max - min) goes
// into it the cycle before the first one: its result is back a cycle before
// the first (x - min) reaches the divider.  A request of N data lines costs
// about N + 16 N cycles plus the cores' latency once, where scanning a value
// per cycle and replaying a line at a time cost 17 + 60 cycles a line: a 4 KB
// request took 24.3 us from its first line in to its last response out at
// 200 MHz, and takes 5.6.
//
// What is kept, and why:
//   * linebuf  -- the request replay buffer. Essential: pass 2 cannot start
//                 until pass 1 has finished, so the request must be held.
//                 (Was parser fifo_final_inst.)  A block RAM, read through
//                 its own two registers.
//   * the output FIFO -- nothing stops a value once it is in the cores, so
//                 every line's result needs somewhere to go.  A line is
//                 replayed only while fewer than OUT_DEPTH lines are between
//                 the replay and m_axis, which is what the FIFO holds, so it
//                 cannot overflow however long m_axis_tready stays low.
//   * nothing else. The old axis_pipeline_register aligned (x-min) against
//     (max-min) at the divider, but (max-min) is a per-request CONSTANT, so it
//     lives in a register and needs no alignment at all.
//
// Two IP simplifications relative to the original:
//   * Max_comparator x2 replaced by an IEEE-754 ordering trick (below). The
//     originals sat inside a running-min/max feedback loop with 3-cycle
//     latency, which is what forced the parsed_max_1/2/3 delay chains, the
//     input_norm_ready handshaking and the sub_*_valid pulse stretching, and
//     held the scan to a value every 4 cycles.
//   * floating_point_0 x2 collapsed to x1. Both uses are "a - min": the range
//     is max - min and each element is x - min, so one core with a muxed `a`
//     serves both phases.
// Remaining IP: floating_point_0 (Add_Subtract), floating_point_3 (Divide).
//
// One request at a time: the next is taken once this one's last line has
// been normalised.
//
// Request format: 16 x 32-bit values per 512-bit line, little-endian word
// order; tlast marks the final line. A leading all-ones header line is
// consumed and ignored, as before.
// Response: one beat per input line, y[i] in word i.
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
// NOTE: the original packed results in REVERSE word order (it left-shifted the
// accumulator and inserted at [31:0]). This emits y[i] in word i.
//
module norm_core #(
    parameter integer AXIS_DATA_W  = 512 + 1 + 32,  // {meta, tlast, payload}
    parameter integer KEEP_W       = 1,
    parameter integer TDEST_W      = 1,
    parameter integer TID_W        = 1,
    parameter integer USER_W       = 1,
    parameter integer VALUE_W      = 32,
    parameter integer MAX_LINES    = 256,           // request replay depth, in lines
    parameter integer FLUSH_CYCLES = 128,           // > 12+29, the summed core latency
    parameter integer OUT_DEPTH    = 8              // response lines held, a power of two
) (
    input  wire                   clk,
    input  wire                   rst,

    input  wire [AXIS_DATA_W-1:0] s_axis_tdata,
    input  wire [KEEP_W-1:0]      s_axis_tkeep,
    input  wire [KEEP_W-1:0]      s_axis_tstrb,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,
    input  wire                   s_axis_tlast,
    input  wire [TDEST_W-1:0]     s_axis_tdest,
    input  wire [TID_W-1:0]       s_axis_tid,
    input  wire [USER_W-1:0]      s_axis_tuser,

    output wire [AXIS_DATA_W-1:0] m_axis_tdata,
    output wire [KEEP_W-1:0]      m_axis_tkeep,
    output wire [KEEP_W-1:0]      m_axis_tstrb,
    output wire                   m_axis_tvalid,
    input  wire                   m_axis_tready,
    output wire                   m_axis_tlast,
    output wire [TDEST_W-1:0]     m_axis_tdest,
    output wire [TID_W-1:0]       m_axis_tid,
    output wire [USER_W-1:0]      m_axis_tuser
);

    localparam integer PAYLOAD_W      = 512;
    localparam integer LINE_BYTES     = PAYLOAD_W / 8;            // 64
    localparam integer WORDS_PER_LINE = PAYLOAD_W / VALUE_W;      // 16
    localparam integer IDX_W          = $clog2(WORDS_PER_LINE);   // 4
    localparam integer LINE_AW        = $clog2(MAX_LINES);
    localparam [LINE_AW:0] LINE_LIMIT = MAX_LINES[LINE_AW:0];   // sized
    localparam integer FLUSH_W        = $clog2(FLUSH_CYCLES + 1);
    localparam integer HELD_W         = $clog2(OUT_DEPTH + 1);
    localparam integer OUTST_W        = $clog2(OUT_DEPTH * WORDS_PER_LINE + 1);
    localparam integer OUT_W          = AXIS_DATA_W + TDEST_W + TID_W + USER_W;
    localparam [HELD_W-1:0] HELD_MAX  = OUT_DEPTH;

    localparam [1:0] ST_RX = 2'd0, ST_RANGE = 2'd1, ST_NORM = 2'd2;

    // IEEE-754 total ordering: map a float to an unsigned key whose magnitude
    // order matches the float's numeric order, so a plain unsigned compare
    // works for both signs. (NaN is not handled, as before.)  The map is a
    // bijection, so the tree carries keys only and fval maps the winners back.
    function [31:0] fkey(input [31:0] f);
        fkey = f[31] ? ~f : (f | 32'h8000_0000);
    endfunction

    function [31:0] fval(input [31:0] k);
        fval = k[31] ? (k & 32'h7FFF_FFFF) : ~k;
    endfunction

    reg [1:0]             state;
    // The replay buffer is a block RAM, read through its own two registers:
    // rd_data (the RAM's output latch) and rd_line (its output register).
    // Nothing else drives either, which is what lets it leave distributed RAM.
    // As distributed RAM it was ~2300 LUTs of norm's ~5100, and its read, a
    // mux across four banks into `hold`, was the RM's slowest path.
    (* ram_style = "block" *)
    reg [PAYLOAD_W-1:0]   linebuf [0:MAX_LINES-1];
    reg [PAYLOAD_W-1:0]   rd_data, rd_line;
    reg                   d_valid;         // rd_data holds the next line to replay
    reg                   l_valid;         // rd_line's values are being issued
    reg [LINE_AW:0]       rd_addr;         // next line to read out of linebuf
    reg [IDX_W-1:0]       rep_idx;

    reg [LINE_AW:0]       nlines;
    reg                   frame_active, last_seen;

    reg [31:0]            max_key, min_key, range;
    reg                   range_pending;   // max - min is in the subtractor

    reg [PAYLOAD_W-1:0]   acc;             // words 0..14 of the line being packed
    reg [IDX_W-1:0]       pack_idx;
    reg [LINE_AW:0]       pack_lines;      // lines of this request packed
    reg [HELD_W-1:0]      held;            // lines replayed and not yet out of m_axis

    // floating_point_0/3 are generated with aclk only -- no aresetn (see
    // src/ip/gen_ip.tcl), so they cannot be reset. They are emptied by counting
    // data through instead:
    //   outstanding -- values issued to the divide path but not yet returned.
    //                  A result arriving with outstanding == 0 is stale
    //                  (pre-reset) and is dropped.
    //   flush_cnt   -- after reset, refuse new input until the cores have had
    //                  longer than their total latency to empty themselves.
    reg [OUTST_W-1:0]     outstanding;
    reg [FLUSH_W-1:0]     flush_cnt;

    reg [TDEST_W-1:0]     resp_tdest;
    reg [TID_W-1:0]       resp_tid;
    reg [USER_W-1:0]      resp_tuser;
    reg [15:0]            resp_session;    // meta_TDATA[15:0], first beat
    reg [15:0]            req_bytes;       // meta_TDATA[31:16], first beat
    reg                   saw_header;      // the request began with a header line

    // Slot boundary fields (see the header comment).
    wire [PAYLOAD_W-1:0]  rx_payload   = s_axis_tdata[PAYLOAD_W-1:0];
    wire                  rx_last      = s_axis_tdata[PAYLOAD_W];
    wire [15:0]           rx_session   = s_axis_tdata[PAYLOAD_W+1 +: 16];
    wire [15:0]           rx_req_bytes = s_axis_tdata[PAYLOAD_W+17 +: 16];

    wire is_header = (rx_payload[447:0] == {448{1'b1}});

    // One response line per data line: the request less its header line.
    wire [15:0] resp_bytes = req_bytes - (saw_header ? LINE_BYTES[15:0] : 16'd0);
    assign s_axis_tready = (state == ST_RX) && !last_seen && (nlines < LINE_LIMIT)
                       && (flush_cnt == 0);
    wire rx_fire = s_axis_tvalid && s_axis_tready;
    // A data line is written as it arrives; the header line is not kept.
    wire rx_data = rx_fire && (frame_active || !is_header);

    // ------------------------------------------------------- min/max tree

    // t0: the line's keys; t1: max and min of each four; t2: of the line
    reg [31:0] t0_key [0:WORDS_PER_LINE-1];
    reg [31:0] t1_max [0:3];
    reg [31:0] t1_min [0:3];
    reg [31:0] t2_max, t2_min;
    reg        t0_v, t1_v, t2_v;
    reg        t0_last, t1_last, t2_last;

    // a pair: one compare gives both its max and its min
    reg [31:0] p_max [0:7];
    reg [31:0] p_min [0:7];
    reg [31:0] q_max [0:3];
    reg [31:0] q_min [0:3];
    reg [31:0] h_max [0:1];
    reg [31:0] h_min [0:1];
    integer i;

    always @* begin
        for (i = 0; i < 8; i = i + 1) begin
            if (t0_key[2*i] > t0_key[2*i+1]) begin
                p_max[i] = t0_key[2*i];   p_min[i] = t0_key[2*i+1];
            end else begin
                p_max[i] = t0_key[2*i+1]; p_min[i] = t0_key[2*i];
            end
        end
        for (i = 0; i < 4; i = i + 1) begin
            q_max[i] = (p_max[2*i] > p_max[2*i+1]) ? p_max[2*i] : p_max[2*i+1];
            q_min[i] = (p_min[2*i] < p_min[2*i+1]) ? p_min[2*i] : p_min[2*i+1];
        end
        for (i = 0; i < 2; i = i + 1) begin
            h_max[i] = (t1_max[2*i] > t1_max[2*i+1]) ? t1_max[2*i] : t1_max[2*i+1];
            h_min[i] = (t1_min[2*i] < t1_min[2*i+1]) ? t1_min[2*i] : t1_min[2*i+1];
        end
    end

    always @(posedge clk) begin
        for (i = 0; i < WORDS_PER_LINE; i = i + 1)
            t0_key[i] <= fkey(rx_payload[i*VALUE_W +: VALUE_W]);
        for (i = 0; i < 4; i = i + 1) begin
            t1_max[i] <= q_max[i];
            t1_min[i] <= q_min[i];
        end
        t2_max <= (h_max[0] > h_max[1]) ? h_max[0] : h_max[1];
        t2_min <= (h_min[0] < h_min[1]) ? h_min[0] : h_min[1];
        t0_last <= rx_last;
        t1_last <= t0_last;
        t2_last <= t1_last;
    end

    wire [31:0] max_val = fval(max_key);
    wire [31:0] min_val = fval(min_key);

    // --------------------------------------------------------- replay buffer

    wire        sub_a_ready, sub_b_ready;
    wire        norm_issue = (state == ST_NORM) && l_valid;
    wire        norm_fire  = norm_issue && sub_a_ready && sub_b_ready;
    wire        l_done     = norm_fire && (rep_idx == {IDX_W{1'b1}});
    // a line starts its replay only if its result will have room
    wire        move       = d_valid && (!l_valid || l_done) && (held < HELD_MAX);
    wire        rd_en      = ((state == ST_RANGE) || (state == ST_NORM))
                          && (rd_addr != nlines) && (!d_valid || move);

    always @(posedge clk) begin
        if (rx_data) linebuf[nlines[LINE_AW-1:0]] <= rx_payload;
        if (rd_en)   rd_data <= linebuf[rd_addr[LINE_AW-1:0]];
        if (move)    rd_line <= rd_data;
    end

    wire [31:0] norm_x = rd_line[rep_idx*VALUE_W +: VALUE_W];

    // ------------------------------------------------- subtract (shared core)

    wire        sub_res_valid;
    wire [31:0] sub_res_data;
    wire        div_a_ready, div_b_ready;
    wire        sub_res_ready = div_a_ready && div_b_ready;

    wire        sub_issue = (state == ST_RANGE) || norm_issue;
    wire        range_fire = (state == ST_RANGE) && sub_a_ready && sub_b_ready;
    wire [31:0] sub_a      = (state == ST_RANGE) ? max_val : norm_x;

    floating_point_0 sub_inst (
      .aclk                 (clk),
      .s_axis_a_tvalid      (sub_issue),
      .s_axis_a_tready      (sub_a_ready),
      .s_axis_a_tdata       (sub_a),
      .s_axis_b_tvalid      (sub_issue),
      .s_axis_b_tready      (sub_b_ready),
      .s_axis_b_tdata       (min_val),
      .m_axis_result_tvalid (sub_res_valid),
      .m_axis_result_tready (sub_res_ready),
      .m_axis_result_tdata  (sub_res_data)
    );

    // The first result after the range was issued is the range; the rest are
    // the request's (x - min), in order.
    wire range_back = sub_res_valid && range_pending;
    wire sub_to_div = sub_res_valid && !range_pending && (state == ST_NORM);

    // ------------------------------------ divide by the per-request constant

    wire        div_res_valid;
    wire [31:0] div_res_data;

    floating_point_3 div_inst (
      .aclk                 (clk),
      .s_axis_a_tvalid      (sub_to_div),
      .s_axis_a_tready      (div_a_ready),
      .s_axis_a_tdata       (sub_res_data),
      .s_axis_b_tvalid      (sub_to_div),
      .s_axis_b_tready      (div_b_ready),
      .s_axis_b_tdata       (range),
      .m_axis_result_tvalid (div_res_valid),
      .m_axis_result_tready (1'b1),           // the output FIFO has room, see above
      .m_axis_result_tdata  (div_res_data)
    );

    // ------------------------------------------------------------------ pack

    // A result only counts if we are expecting one.
    wire res_take  = div_res_valid && (outstanding != 0);
    wire line_done = res_take && (pack_idx == {IDX_W{1'b1}});
    wire line_last = (pack_lines == nlines - 1'b1);

    wire [PAYLOAD_W-1:0] done_payload = {div_res_data, acc[PAYLOAD_W-VALUE_W-1:0]};

    wire             out_s_ready;
    wire             out_valid;
    wire [OUT_W-1:0] out_data;

    // {tdest, tid, tuser, meta_TDATA_out, tlast, payload}
    axis_fifo_taxi #(
        .DATA_WIDTH(OUT_W),
        .DEPTH     (OUT_DEPTH)
    ) out_fifo_inst (
        .clk          (clk),
        .rst          (rst),
        .s_axis_tvalid(line_done),
        .s_axis_tready(out_s_ready),
        .s_axis_tdata ({resp_tdest, resp_tid, resp_tuser, resp_bytes, resp_session,
                        line_last, done_payload}),
        .m_axis_tvalid(out_valid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tdata (out_data)
    );

    wire out_fire = out_valid && m_axis_tready;

    // ------------------------------------------------------------------ fsm

    always @(posedge clk) begin
        if (rst) begin
            state <= ST_RX; nlines <= 0; frame_active <= 1'b0; last_seen <= 1'b0;
            t0_v <= 1'b0; t1_v <= 1'b0; t2_v <= 1'b0;
            max_key <= 32'h0000_0000; min_key <= 32'hFFFF_FFFF;
            range <= 32'h0; range_pending <= 1'b0;
            d_valid <= 1'b0; l_valid <= 1'b0; rd_addr <= 0; rep_idx <= 0;
            acc <= 0; pack_idx <= 0; pack_lines <= 0; held <= 0;
            resp_tdest <= 0; resp_tid <= 0; resp_tuser <= 0;
            resp_session <= 16'd0; req_bytes <= 16'd0; saw_header <= 1'b0;
            outstanding <= 0; flush_cnt <= FLUSH_CYCLES[FLUSH_W-1:0];
        end else begin

            // ---- pass 1: receive and scan -------------------------------
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
                    frame_active <= !rx_last;
                end else begin
                    nlines    <= nlines + 1'b1;
                    last_seen <= rx_last;
                end
            end

            t0_v <= rx_data;
            t1_v <= t0_v;
            t2_v <= t1_v;
            if (t2_v) begin
                if (t2_max > max_key) max_key <= t2_max;
                if (t2_min < min_key) min_key <= t2_min;
                if (t2_last) state <= ST_RANGE;
            end

            // ---- max - min, then pass 2: replay and normalise -----------
            if (range_fire) begin
                range_pending <= 1'b1;
                state         <= ST_NORM;
            end
            if (range_back) begin
                range         <= sub_res_data;
                range_pending <= 1'b0;
            end

            if (rd_en) rd_addr <= rd_addr + 1'b1;
            if (rd_en)       d_valid <= 1'b1;
            else if (move)   d_valid <= 1'b0;

            if (move) begin
                l_valid <= 1'b1;
                rep_idx <= 0;
            end else if (norm_fire) begin
                rep_idx <= rep_idx + 1'b1;
                if (l_done) l_valid <= 1'b0;
            end

            case ({move, out_fire})
                2'b10:   held <= held + 1'b1;
                2'b01:   held <= held - 1'b1;
                default: ;
            endcase

            if (flush_cnt != 0) flush_cnt <= flush_cnt - 1'b1;

            if (res_take) begin
                acc[pack_idx*VALUE_W +: VALUE_W] <= div_res_data;
                pack_idx <= pack_idx + 1'b1;
            end

            case ({norm_fire, res_take})
                2'b10:   outstanding <= outstanding + 1'b1;
                2'b01:   outstanding <= outstanding - 1'b1;
                default: ;
            endcase

            // the request's last line normalised: ready for the next one
            if (line_done) begin
                pack_lines <= pack_lines + 1'b1;
                if (line_last) begin
                    state        <= ST_RX;
                    nlines       <= 0;
                    frame_active <= 1'b0;
                    last_seen    <= 1'b0;
                    max_key      <= 32'h0000_0000;
                    min_key      <= 32'hFFFF_FFFF;
                    rd_addr      <= 0;
                    pack_lines   <= 0;
                end
            end
        end
    end

`ifdef SIMULATION
    always @(posedge clk) begin
        if (!rst && line_done && !out_s_ready) begin
            $fatal(1, "%m: the output FIFO was full when a line was packed");
        end
        if (!rst && range_back && (state != ST_NORM)) begin
            $fatal(1, "%m: max - min came back outside pass 2");
        end
    end
`endif

    // {meta_TDATA_out, tlast, payload}, and the sideband of the request's
    // first beat
    assign m_axis_tdata  = out_data[AXIS_DATA_W-1:0];
    assign m_axis_tvalid = out_valid;
    assign m_axis_tlast  = out_data[PAYLOAD_W];
    assign m_axis_tkeep  = {KEEP_W{1'b1}};
    assign m_axis_tstrb  = {KEEP_W{1'b1}};
    assign {m_axis_tdest, m_axis_tid, m_axis_tuser} = out_data[OUT_W-1:AXIS_DATA_W];

endmodule

`resetall
