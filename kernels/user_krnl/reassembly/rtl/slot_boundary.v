`timescale 1ns / 1ps

// The static side of one reconfigurable slot: requests from the scheduler go
// to the cell, responses from the cell go to the output switch, both with
// credit flow control (slot_credit.v).  Between this module and the cell are
// PIPE_LEN register stages each way, for data and valid as for the credits
// coming back, so a cell can be several clock regions or an SLR away; nothing
// on that path depends on anything coming back in the same cycle.
//
//   scheduler -> source -> PIPE_LEN -> cell -> PIPE_LEN -> sink -> switch
//                  ^---- PIPE_LEN ----/  \---- PIPE_LEN ----/
//                        credits               credits
//
// The cell's reset is this slot's, not the design's: it is held while the slot
// is decoupled, so a module that has just been loaded starts with an empty
// FIFO and all its credits, and it travels to the cell through PIPE_LEN stages
// as the data does.  The credit ends here stay in reset for STRETCH cycles
// longer.  By then the cell is out of reset, and whatever the cell drove while
// it was being reconfigured has left the pipes from it and been dropped, so
// both sides start over with the counts they agree on.
//
// While the slot is decoupled no request is taken: one for this slot waits in
// the scheduler.  A request already on its way to the cell when the slot is
// decoupled is lost, as is a response from the cell not yet taken, so a slot
// should be idle when it is reconfigured.
module slot_boundary #(
    parameter integer DATA_W   = 545,
    parameter integer PIPE_LEN = 16     // at most 29 with the default CREDITS
) (
    input  wire              clk,
    input  wire              rst,
    input  wire              decouple,

    // requests from the scheduler
    input  wire [DATA_W-1:0] s_axis_tdata,
    input  wire              s_axis_tvalid,
    output wire              s_axis_tready,
    input  wire              s_axis_tlast,

    // responses to the output switch
    output wire [DATA_W-1:0] m_axis_tdata,
    output wire              m_axis_tvalid,
    input  wire              m_axis_tready,
    output wire              m_axis_tlast,

    // the cell
    output wire              cell_rst,
    output wire [DATA_W-1:0] cell_s_tdata,
    output wire              cell_s_tvalid,
    output wire              cell_s_tlast,
    input  wire              cell_s_credit,
    input  wire [DATA_W-1:0] cell_m_tdata,
    input  wire              cell_m_tvalid,
    input  wire              cell_m_tlast,
    output wire              cell_m_credit
);

    // longer than the reset's trip to the cell and the pipe back from it
    localparam integer STRETCH = 2 * PIPE_LEN + 8;
    localparam integer SW = $clog2(STRETCH + 1);

    reg          hold = 1'b1;
    reg [SW-1:0] stretch_cnt = STRETCH;
    reg          ends_rst = 1'b1;

    always @(posedge clk) begin
        hold <= rst || decouple;
        if (hold) begin
            stretch_cnt <= STRETCH;
        end else if (stretch_cnt != {SW{1'b0}}) begin
            stretch_cnt <= stretch_cnt - 1'b1;
        end
        ends_rst <= hold || stretch_cnt != {SW{1'b0}};
    end

    slot_pipe #(
        .WIDTH(1),
        .LENGTH(PIPE_LEN),
        .INIT(1'b1)
    ) rst_pipe_inst (
        .clk(clk),
        .in(hold),
        .out(cell_rst)
    );

    // ---- requests ----
    wire [DATA_W-1:0] req_tdata;
    wire              req_tvalid;
    wire              req_tlast;
    wire              req_credit;

    slot_credit_source #(
        .DATA_W(DATA_W)
    ) source_inst (
        .clk(clk),
        .rst(ends_rst),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .out_tdata(req_tdata),
        .out_tvalid(req_tvalid),
        .out_tlast(req_tlast),
        .in_credit(req_credit)
    );

    slot_pipe #(
        .WIDTH(DATA_W + 2),
        .LENGTH(PIPE_LEN)
    ) req_pipe_inst (
        .clk(clk),
        .in({req_tvalid, req_tlast, req_tdata}),
        .out({cell_s_tvalid, cell_s_tlast, cell_s_tdata})
    );

    slot_pipe #(
        .WIDTH(1),
        .LENGTH(PIPE_LEN)
    ) req_credit_pipe_inst (
        .clk(clk),
        .in(cell_s_credit),
        .out(req_credit)
    );

    // ---- responses ----
    wire [DATA_W-1:0] resp_tdata;
    wire              resp_tvalid;
    wire              resp_tlast;
    wire              resp_credit;

    slot_pipe #(
        .WIDTH(DATA_W + 2),
        .LENGTH(PIPE_LEN)
    ) resp_pipe_inst (
        .clk(clk),
        .in({cell_m_tvalid, cell_m_tlast, cell_m_tdata}),
        .out({resp_tvalid, resp_tlast, resp_tdata})
    );

    slot_credit_sink #(
        .DATA_W(DATA_W)
    ) sink_inst (
        .clk(clk),
        .rst(ends_rst),
        .in_tdata(resp_tdata),
        .in_tvalid(resp_tvalid),
        .in_tlast(resp_tlast),
        .out_credit(resp_credit),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast)
    );

    slot_pipe #(
        .WIDTH(1),
        .LENGTH(PIPE_LEN)
    ) resp_credit_pipe_inst (
        .clk(clk),
        .in(resp_credit),
        .out(cell_m_credit)
    );

endmodule
