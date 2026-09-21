`resetall
`timescale 1ns / 1ps
`default_nettype none

//
// norm
//
// Min-max normalisation over a request of IEEE-754 single-precision values,
// as a reconfigurable-slot module. Same interface as or_slot / pattern_slot.
//
//     y = (x - min) / (max - min)        min, max taken over the whole request
//
// This is inherently TWO PASS: nothing can be normalised until every value has
// been seen. Pass 1 scans for min/max while the request is received; pass 2
// replays it through subtract and divide.
//
// Flattened from Normalization_workload -> packet_parser_normalization (plus
// six FIFOs / buffers). Four were boundary FIFOs decoupling the workload from
// the shared broadcast bus that fanned every beat to every workload; routing
// now happens upstream, so the slot just drops s_axis_tready when busy.
//
// What is kept, and why:
//   * linebuf  -- the request replay buffer. Essential: pass 2 cannot start
//                 until pass 1 has finished, so the request must be held.
//                 (Was parser fifo_final_inst.)
//   * nothing else. The old axis_pipeline_register aligned (x-min) against
//     (max-min) at the divider, but (max-min) is a per-request CONSTANT, so it
//     lives in a register and needs no alignment at all.
//
// Two IP simplifications relative to the original:
//   * Max_comparator x2 replaced by a combinational IEEE-754 ordering trick
//     (below). The originals sat inside a running-min/max feedback loop with
//     3-cycle latency, which is what forced the parsed_max_1/2/3 delay chains,
//     the input_norm_ready handshaking and the sub_*_valid pulse stretching.
//     Combinational compare makes the scan 1 value/cycle and deletes all of it.
//   * floating_point_0 x2 collapsed to x1. Both uses are "a - min": the range
//     is max - min and each element is x - min, so one core with a muxed `a`
//     serves both phases.
// Remaining IP: floating_point_0 (Add_Subtract), floating_point_3 (Divide).
//
// Request format: 16 x 32-bit values per 512-bit line, little-endian word
// order; s_axis_tlast marks the final line. A leading all-ones header line is
// consumed and ignored, as before.
// Response: one beat per input line, y[i] in word i.
//
// NOTE: the original packed results in REVERSE word order (it left-shifted the
// accumulator and inserted at [31:0]). This emits y[i] in word i.
//
(* DONT_TOUCH = "yes" *)
module norm #(
    parameter integer AXIS_DATA_W = 512,
    parameter integer KEEP_W      = AXIS_DATA_W/8,
    parameter integer TDEST_W     = 3,
    parameter integer TID_W       = 4,
    parameter integer USER_W      = 1,
    parameter integer VALUE_W     = 32,
    parameter integer MAX_LINES   = 256,        // request replay depth, in lines
    parameter integer FLUSH_CYCLES = 128       // > 12+29, the summed core latency
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

    localparam integer WORDS_PER_LINE = AXIS_DATA_W / VALUE_W;    // 16
    localparam integer IDX_W          = $clog2(WORDS_PER_LINE);   // 4
    localparam integer LINE_AW        = $clog2(MAX_LINES);
    localparam [LINE_AW:0] LINE_LIMIT = MAX_LINES[LINE_AW:0];   // sized
    localparam integer FLUSH_W        = $clog2(FLUSH_CYCLES + 1);

    localparam [1:0] ST_RX = 2'd0, ST_RANGE = 2'd1, ST_NORM = 2'd2;

    // IEEE-754 total ordering: map a float to an unsigned key whose magnitude
    // order matches the float's numeric order, so a plain unsigned compare
    // works for both signs. (NaN is not handled, as before.)
    function [31:0] fkey(input [31:0] f);
        fkey = f[31] ? ~f : (f | 32'h8000_0000);
    endfunction

    reg [1:0]             state;
    // NOTE: this infers as DISTRIBUTED RAM, ~2300 LUTs of norm's ~5100. It does
    // not reach block RAM because `hold` is driven from two sources (the RX
    // path and this array), so it is not a clean RAM output register; a
    // ram_style="block" attribute alone does not change that. Giving the array
    // its own output register and muxing after it would move it to ~4 RAMB36.
    reg [AXIS_DATA_W-1:0] linebuf [0:MAX_LINES-1];
    reg [AXIS_DATA_W-1:0] hold;            // line being scanned / replayed
    reg [LINE_AW:0]       nlines;
    reg                   frame_active, last_seen;

    reg                   scanning;
    reg [IDX_W-1:0]       scan_idx;

    reg [31:0]            max_val, min_val, max_key, min_key, range;
    reg                   range_issued;

    reg [LINE_AW:0]       rep_line;
    reg [IDX_W-1:0]       rep_idx;
    reg                   rep_loaded, issuing;

    reg [AXIS_DATA_W-1:0] acc;
    reg [IDX_W-1:0]       pack_idx;
    reg                   resp_valid, resp_last;

    // floating_point_0/3 are generated with aclk only -- no aresetn (see
    // src/ip/gen_ip.tcl), so they cannot be reset. They are emptied by counting
    // data through instead:
    //   outstanding -- values issued to the divide path but not yet returned.
    //                  A result arriving with outstanding == 0 is stale
    //                  (pre-reset) and is dropped.
    //   flush_cnt   -- after reset, refuse new input until the cores have had
    //                  longer than their total latency to empty themselves.
    reg [IDX_W:0]         outstanding;
    reg [FLUSH_W-1:0]     flush_cnt;

    reg [TDEST_W-1:0]     resp_tdest;
    reg [TID_W-1:0]       resp_tid;
    reg [USER_W-1:0]      resp_tuser;

    wire is_header = (s_axis_tdata[447:0] == {448{1'b1}});
    assign s_axis_tready = (state == ST_RX) && !scanning && (nlines < LINE_LIMIT)
                       && (flush_cnt == 0);
    wire rx_fire = s_axis_tvalid && s_axis_tready;

    wire [31:0] scan_x = hold[scan_idx*VALUE_W +: VALUE_W];
    wire [31:0] norm_x = hold[rep_idx *VALUE_W +: VALUE_W];

    // ------------------------------------------------- subtract (shared core)

    wire        sub_a_ready, sub_b_ready;
    wire        sub_res_valid;
    wire [31:0] sub_res_data;
    wire        div_a_ready, div_b_ready;
    wire        sub_res_ready = div_a_ready && div_b_ready;

    wire        sub_issue = ((state == ST_RANGE) && !range_issued)
                         || ((state == ST_NORM)  && issuing && rep_loaded);
    wire        sub_fire   = sub_issue && sub_a_ready && sub_b_ready;
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

    wire sub_to_div = sub_res_valid && (state == ST_NORM);

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
      .m_axis_result_tready (1'b1),           // the packer is always ready
      .m_axis_result_tdata  (div_res_data)
    );

    // ------------------------------------------------------------------ fsm

    always @(posedge clk) begin
        if (rst) begin
            state <= ST_RX; nlines <= 0; frame_active <= 1'b0; last_seen <= 1'b0;
            scanning <= 1'b0; scan_idx <= 0;
            max_key <= 32'h0000_0000; min_key <= 32'hFFFF_FFFF;
            max_val <= 32'h0; min_val <= 32'h0; range <= 32'h0; range_issued <= 1'b0;
            rep_line <= 0; rep_idx <= 0; rep_loaded <= 1'b0; issuing <= 1'b0;
            acc <= 0; pack_idx <= 0; resp_valid <= 1'b0; resp_last <= 1'b0;
            resp_tdest <= 0; resp_tid <= 0; resp_tuser <= 0;
            outstanding <= 0; flush_cnt <= FLUSH_CYCLES[FLUSH_W-1:0];
        end else begin

            // ---- pass 1: receive and scan -------------------------------
            if (rx_fire) begin
                if (!frame_active) begin
                    resp_tdest <= s_axis_tdest;
                    resp_tid   <= s_axis_tid;
                    resp_tuser <= s_axis_tuser;
                end
                frame_active <= 1'b1;
                if (!frame_active && is_header) begin
                    frame_active <= !s_axis_tlast;
                end else begin
                    linebuf[nlines[LINE_AW-1:0]] <= s_axis_tdata;
                    hold      <= s_axis_tdata;
                    nlines    <= nlines + 1'b1;
                    last_seen <= s_axis_tlast;
                    scan_idx  <= 0;
                    scanning  <= 1'b1;
                end
            end

            if (scanning) begin
                if (fkey(scan_x) > max_key) begin max_key <= fkey(scan_x); max_val <= scan_x; end
                if (fkey(scan_x) < min_key) begin min_key <= fkey(scan_x); min_val <= scan_x; end
                scan_idx <= scan_idx + 1'b1;
                if (scan_idx == {IDX_W{1'b1}}) begin
                    scanning <= 1'b0;
                    if (last_seen) begin
                        state        <= ST_RANGE;
                        range_issued <= 1'b0;
                    end
                end
            end

            // ---- compute max - min --------------------------------------
            if (state == ST_RANGE) begin
                if (sub_fire) range_issued <= 1'b1;
                if (sub_res_valid) begin
                    range      <= sub_res_data;
                    state      <= ST_NORM;
                    rep_line   <= 0;
                    rep_idx    <= 0;
                    rep_loaded <= 1'b0;
                    issuing    <= 1'b1;
                    pack_idx   <= 0;
                end
            end

            // ---- pass 2: replay and normalise ---------------------------
            if (state == ST_NORM) begin
                if (issuing && !rep_loaded) begin
                    hold       <= linebuf[rep_line[LINE_AW-1:0]];
                    rep_loaded <= 1'b1;
                end else if (sub_fire) begin
                    rep_idx <= rep_idx + 1'b1;
                    if (rep_idx == {IDX_W{1'b1}}) issuing <= 1'b0;
                end
            end

            if (flush_cnt != 0) flush_cnt <= flush_cnt - 1'b1;

            // A result only counts if we are expecting one.
            if (div_res_valid && (outstanding != 0)) begin
                acc[pack_idx*VALUE_W +: VALUE_W] <= div_res_data;
                pack_idx <= pack_idx + 1'b1;
                if (pack_idx == {IDX_W{1'b1}}) begin
                    resp_valid <= 1'b1;
                    resp_last  <= (rep_line == nlines - 1'b1);
                end
            end

            case ({(sub_fire && (state == ST_NORM)), (div_res_valid && (outstanding != 0))})
                2'b10:   outstanding <= outstanding + 1'b1;
                2'b01:   outstanding <= outstanding - 1'b1;
                default: ;
            endcase

            if (resp_valid && m_axis_tready) begin
                resp_valid <= 1'b0;
                if (resp_last) begin
                    state        <= ST_RX;
                    nlines       <= 0;
                    frame_active <= 1'b0;
                    last_seen    <= 1'b0;
                    max_key      <= 32'h0000_0000;
                    min_key      <= 32'hFFFF_FFFF;
                end else begin
                    rep_line   <= rep_line + 1'b1;
                    rep_idx    <= 0;
                    rep_loaded <= 1'b0;
                    issuing    <= 1'b1;
                end
            end
        end
    end

    assign m_axis_tdata  = acc;
    assign m_axis_tvalid = resp_valid;
    assign m_axis_tlast  = resp_last;
    assign m_axis_tkeep  = {KEEP_W{1'b1}};
    assign m_axis_tstrb  = {KEEP_W{1'b1}};
    assign m_axis_tdest  = resp_tdest;
    assign m_axis_tid    = resp_tid;
    assign m_axis_tuser  = resp_tuser;

endmodule

`resetall
