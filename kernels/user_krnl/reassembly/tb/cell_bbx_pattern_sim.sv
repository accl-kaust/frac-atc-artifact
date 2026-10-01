`resetall
`timescale 1ns / 1ps
`default_nettype none

// Simulation stand-in for the PR cells.  The static design instantiates the
// blackbox cell_bbx (reconfctrl/rtl/cell_bbx.sv); here it resolves to the real
// RM tops from apps/, so the bench verifies the RTL that is synthesised into
// the slots: c00 and c02 are pattern_slot (echo), c01 and c03 or_slot.  Which
// one an instance stands for follows from its name, as pkt_logic.v names them
// c00_bbx_inst to c03_bbx_inst.  Both RMs are instantiated and the one that
// is not selected is held idle: it gets no beats and no credits.
//
// in_beats counts the request beats the cell has been sent, so a test can
// tell which of two echoing cells a request went to.
module cell_bbx #(
    parameter int AXIS_DATA_W = 512 + 1 + 32
) (
    input  wire                   clk,
    input  wire                   rst,

    input  wire [AXIS_DATA_W-1:0] s_axis_tdata,
    input  wire                   s_axis_tvalid,
    input  wire                   s_axis_tlast,
    output wire                   s_axis_credit,

    output wire [AXIS_DATA_W-1:0] m_axis_tdata,
    output wire                   m_axis_tvalid,
    output wire                   m_axis_tlast,
    input  wire                   m_axis_credit
);

    reg is_or_slot = 1'b0;

    initial begin
        string inst_name;

        inst_name = $sformatf("%m");
        for (int i = 0; i + 12 <= inst_name.len(); i++) begin
            if (inst_name.substr(i, i + 11) == "c01_bbx_inst" || inst_name.substr(i, i + 11) == "c03_bbx_inst") begin
                is_or_slot = 1'b1;
            end
        end
    end

    integer in_beats = 0;

    always @(posedge clk) begin
        if (s_axis_tvalid) begin
            in_beats <= in_beats + 1;
        end
    end

    wire                   echo_s_credit, or_s_credit;
    wire [AXIS_DATA_W-1:0] echo_m_tdata,  or_m_tdata;
    wire                   echo_m_tvalid, or_m_tvalid;
    wire                   echo_m_tlast,  or_m_tlast;

    pattern_slot #(
        .AXIS_DATA_W(AXIS_DATA_W)
    ) echo_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid && !is_or_slot),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_credit(echo_s_credit),
        .m_axis_tdata(echo_m_tdata),
        .m_axis_tvalid(echo_m_tvalid),
        .m_axis_tlast(echo_m_tlast),
        .m_axis_credit(m_axis_credit && !is_or_slot)
    );

    or_slot #(
        .AXIS_DATA_W(AXIS_DATA_W)
    ) or_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid && is_or_slot),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_credit(or_s_credit),
        .m_axis_tdata(or_m_tdata),
        .m_axis_tvalid(or_m_tvalid),
        .m_axis_tlast(or_m_tlast),
        .m_axis_credit(m_axis_credit && is_or_slot)
    );

    assign s_axis_credit = is_or_slot ? or_s_credit   : echo_s_credit;
    assign m_axis_tdata  = is_or_slot ? or_m_tdata    : echo_m_tdata;
    assign m_axis_tvalid = is_or_slot ? or_m_tvalid   : echo_m_tvalid;
    assign m_axis_tlast  = is_or_slot ? or_m_tlast    : echo_m_tlast;

endmodule

`resetall
