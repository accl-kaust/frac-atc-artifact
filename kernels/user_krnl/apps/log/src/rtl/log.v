`resetall
`timescale 1ns / 1ps
`default_nettype none (* DONT_TOUCH = "yes" *)
module log #(
    parameter integer AXIS_DATA_W = 512,
    parameter integer KEEP_W      = AXIS_DATA_W / 8,
    parameter integer TDEST_W     = 3,
    parameter integer TID_W       = 4,
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

  localparam integer WORDS_PER_LINE = AXIS_DATA_W / VALUE_W;  // 16
  localparam integer IDX_W = $clog2(WORDS_PER_LINE);  // 4
  localparam integer ALIGN_AW = $clog2(ALIGN_DEPTH);
  localparam integer FLUSH_W = $clog2(FLUSH_CYCLES + 1);
  localparam [31:0] FP_ONE = 32'h3F800000;  // 1.0f

  // ------------------------------------------------------------ rx / issue

  reg  [AXIS_DATA_W-1:0] line;
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

  wire                   is_header = (s_axis_tdata[447:0] == {448{1'b1}});

  assign s_axis_tready = !issuing && !awaiting && !resp_valid && (flush_cnt == 0);
  wire               rx_fire = s_axis_tvalid && s_axis_tready;

  wire [VALUE_W-1:0] x = line[issue_idx*VALUE_W+:VALUE_W];
  wire               last_val = (issue_idx == {IDX_W{1'b1}});

  // Both operand channels must accept together, or x and (1-x) desync.
  wire sub_a_ready, sub_b_ready;
  wire issue_fire = issuing && sub_a_ready && sub_b_ready;

  // ----------------------------------------------- 1 - x   (Add_Subtract)

  wire sub_res_valid, sub_res_last;
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
      .s_axis_b_tlast      (last_val && line_last),
      .m_axis_result_tvalid(sub_res_valid),
      .m_axis_result_tready(sub_res_ready),
      .m_axis_result_tdata (sub_res_data),
      .m_axis_result_tlast (sub_res_last)
  );

  // ------------------------------------- operand alignment (kept on purpose)

  reg [VALUE_W-1:0] align_mem[0:ALIGN_DEPTH-1];
  reg [ALIGN_AW:0] align_wr, align_rd;
  wire               align_pop = sub_res_valid && sub_res_ready;
  wire [VALUE_W-1:0] x_aligned = align_mem[align_rd[ALIGN_AW-1:0]];

  always @(posedge clk) begin
    if (rst) begin
      align_wr <= 0;
      align_rd <= 0;
    end else begin
      if (issue_fire) begin
        align_mem[align_wr[ALIGN_AW-1:0]] <= x;
        align_wr <= align_wr + 1'b1;
      end
      if (align_pop) align_rd <= align_rd + 1'b1;
    end
  end

  // ------------------------------------------- x / (1 - x)      (Divide)

  wire div_res_valid, div_res_ready, div_res_last;
  wire [31:0] div_res_data;

  floating_point_1 divide_inst (
      .aclk                (clk),
      .s_axis_a_tvalid     (sub_res_valid && sub_res_ready),
      .s_axis_a_tready     (div_a_ready),
      .s_axis_a_tdata      (x_aligned),
      .s_axis_b_tvalid     (sub_res_valid),
      .s_axis_b_tready     (div_b_ready),
      .s_axis_b_tdata      (sub_res_data),
      .s_axis_b_tlast      (sub_res_last),
      .m_axis_result_tvalid(div_res_valid),
      .m_axis_result_tready(div_res_ready),
      .m_axis_result_tdata (div_res_data),
      .m_axis_result_tlast (div_res_last)
  );

  // ------------------------------------------------ ln(.)    (Logarithm)

  wire log_res_valid, log_res_last;
  wire [31:0] log_res_data;

  floating_point_2 log_inst (
      .aclk                (clk),
      .s_axis_a_tvalid     (div_res_valid),
      .s_axis_a_tready     (div_res_ready),
      .s_axis_a_tdata      (div_res_data),
      .s_axis_a_tlast      (div_res_last),
      .m_axis_result_tvalid(log_res_valid),
      .m_axis_result_tready(1'b1),           // the packer is always ready
      .m_axis_result_tdata (log_res_data),
      .m_axis_result_tlast (log_res_last)
  );

  // ----------------------------------------------------------- pack / tx

  reg [AXIS_DATA_W-1:0] acc;
  reg [      IDX_W-1:0] pack_idx;
  reg                   resp_last;

  always @(posedge clk) begin
    if (rst) begin
      line         <= {AXIS_DATA_W{1'b0}};
      issue_idx    <= {IDX_W{1'b0}};
      issuing      <= 1'b0;
      awaiting     <= 1'b0;
      line_last    <= 1'b0;
      frame_active <= 1'b0;
      resp_valid   <= 1'b0;
      resp_last    <= 1'b0;
      acc          <= {AXIS_DATA_W{1'b0}};
      pack_idx     <= {IDX_W{1'b0}};
      resp_tdest   <= {TDEST_W{1'b0}};
      resp_tid     <= {TID_W{1'b0}};
      resp_tuser   <= {USER_W{1'b0}};
      outstanding  <= 0;
      flush_cnt    <= FLUSH_CYCLES[FLUSH_W-1:0];
    end else begin

      if (rx_fire) begin
        if (!frame_active) begin
          resp_tdest <= s_axis_tdest;
          resp_tid   <= s_axis_tid;
          resp_tuser <= s_axis_tuser;
        end
        frame_active <= 1'b1;
        if (!frame_active && is_header) begin
          // configuration line: consumed, carries no data
          frame_active <= !s_axis_tlast;
        end else begin
          line      <= s_axis_tdata;
          line_last <= s_axis_tlast;
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
          resp_last  <= log_res_last;
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
