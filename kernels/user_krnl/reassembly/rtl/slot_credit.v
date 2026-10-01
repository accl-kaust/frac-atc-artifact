`timescale 1ns / 1ps

// Credit flow control for the slot boundary, used on both sides of it: by
// slot_boundary.v in static and by every reconfigurable module's wrapper.
//
// A ready that runs back against 545 bits of data fans out to every data
// register's enable and has to cross the partition pins and, for a cell in
// another SLR, the die boundary in the same cycle.  Credits take it off the
// path.  The sending end starts with as many credits as the receiving end has
// FIFO entries, spends one per beat and gets one back for every beat the
// receiver takes out of its FIFO, so the FIFO cannot overflow and nothing has
// to stop a beat once it is sent.  Data and valid then travel through plain
// register stages with no reset and no enable, each bit its own flop-to-flop
// hop, and the only signal coming back is a one-bit credit pulse.
//
// The receiver keeps going at a beat a cycle as long as CREDITS covers the
// round trip.  A credit spent at cycle 0 can be spent again at 2 * LENGTH + 6,
// LENGTH being the slot_pipe stages each way between the two ends: the
// source's output register, the sink's input register, its FIFO write and
// read, its credit register, the source's credit register and its counter.
// CREDITS = 64 covers up to 29 stages each way.
//
// Both ends of a link use the defaults, so that a module synthesised out of
// context and the static design it is loaded into agree on CREDITS = DEPTH.
// Do not override them on one side only.

// LENGTH register stages with neither reset nor enable.  shreg_extract keeps
// the chain out of SRLs, which would put every stage of a bit into one LUT and
// defeat the point of spreading the stages along the route.  The stages power
// up at INIT.
module slot_pipe #(
    parameter integer WIDTH  = 1,
    parameter integer LENGTH = 1,
    parameter         INIT   = 1'b0
) (
    input  wire             clk,
    input  wire [WIDTH-1:0] in,
    output wire [WIDTH-1:0] out
);

    generate
        if (LENGTH == 0) begin : g_wire
            assign out = in;
        end else if (LENGTH == 1) begin : g_one
            (* shreg_extract = "no" *) reg [WIDTH-1:0] stage = {WIDTH{INIT}};
            always @(posedge clk) begin
                stage <= in;
            end
            assign out = stage;
        end else begin : g_stages
            // stage 0 is the low WIDTH bits, the last stage the high ones
            /* verilator lint_off WIDTHCONCAT */
            (* shreg_extract = "no" *) reg [WIDTH*LENGTH-1:0] stages = {WIDTH*LENGTH{INIT}};
            /* verilator lint_on WIDTHCONCAT */
            always @(posedge clk) begin
                stages <= {stages[WIDTH*(LENGTH-1)-1:0], in};
            end
            assign out = stages[WIDTH*LENGTH-1 -: WIDTH];
        end
    endgenerate

endmodule

// The sending end.  s_axis_tready is a register, whether a credit is left,
// gated by reset.  out_* are registers too, the data loaded every cycle and
// out_tvalid saying whether it is a beat, so the output carries no enable.
// in_credit is registered before it is counted.  In reset no beat goes out
// and credits arriving are dropped; coming out of it the source has CREDITS
// again.
module slot_credit_source #(
    parameter integer DATA_W  = 545,
    parameter integer CREDITS = 64
) (
    input  wire              clk,
    input  wire              rst,

    input  wire [DATA_W-1:0] s_axis_tdata,
    input  wire              s_axis_tvalid,
    output wire              s_axis_tready,
    input  wire              s_axis_tlast,

    output reg  [DATA_W-1:0] out_tdata = {DATA_W{1'b0}},
    output reg               out_tvalid = 1'b0,
    output reg               out_tlast = 1'b0,
    input  wire              in_credit
);

    localparam integer CW = $clog2(CREDITS + 1);
    localparam [CW-1:0] FULL = CREDITS;

    (* shreg_extract = "no" *) reg in_credit_q = 1'b0;
    reg [CW-1:0] credits = FULL;
    reg          credit_left = 1'b0;

    // rst is in here so that the cycle reset rises takes no beat it would drop
    assign s_axis_tready = credit_left && !rst;

    wire          send = s_axis_tvalid && s_axis_tready;
    wire [CW-1:0] credits_next = credits - {{CW-1{1'b0}}, send} + {{CW-1{1'b0}}, in_credit_q};

    always @(posedge clk) begin
        out_tdata <= s_axis_tdata;
        out_tlast <= s_axis_tlast;
        in_credit_q <= in_credit && !rst;
        if (rst) begin
            credits <= FULL;
            credit_left <= 1'b0;
            out_tvalid <= 1'b0;
        end else begin
            credits <= credits_next;
            credit_left <= credits_next != {CW{1'b0}};
            out_tvalid <= send;
        end
    end

`ifdef SIMULATION
    always @(posedge clk) begin
        if (!rst && in_credit_q && credits == FULL && !send) begin
            $fatal(1, "%m: a credit came back with none outstanding");
        end
    end
`endif

endmodule

// The receiving end.  Its inputs are registered with no enable, the valid
// gated by reset, and every beat that arrives is written into a DEPTH-entry
// FIFO, which the source's credits keep from overflowing.  The FIFO's output
// is a register, and each beat moved into it from the FIFO's memory sends a
// credit back on out_credit, a register.  In reset the FIFO empties and
// arriving beats are dropped.  DEPTH must be a power of two.
module slot_credit_sink #(
    parameter integer DATA_W = 545,
    parameter integer DEPTH  = 64
) (
    input  wire              clk,
    input  wire              rst,

    input  wire [DATA_W-1:0] in_tdata,
    input  wire              in_tvalid,
    input  wire              in_tlast,
    output reg               out_credit = 1'b0,

    output reg  [DATA_W-1:0] m_axis_tdata = {DATA_W{1'b0}},
    output reg               m_axis_tvalid = 1'b0,
    input  wire              m_axis_tready,
    output reg               m_axis_tlast = 1'b0
);

    localparam integer AW = $clog2(DEPTH);

    (* shreg_extract = "no" *) reg [DATA_W-1:0] in_tdata_q = {DATA_W{1'b0}};
    (* shreg_extract = "no" *) reg              in_tlast_q = 1'b0;
    (* shreg_extract = "no" *) reg              in_tvalid_q = 1'b0;

    // {tlast, tdata}; distributed RAM, read into the output register
    (* ram_style = "distributed" *) reg [DATA_W:0] mem [0:DEPTH-1];
    reg [AW:0] wr_ptr = {AW+1{1'b0}};
    reg [AW:0] rd_ptr = {AW+1{1'b0}};

    wire empty = wr_ptr == rd_ptr;
    wire load  = !empty && (!m_axis_tvalid || m_axis_tready);

    always @(posedge clk) begin
        in_tdata_q  <= in_tdata;
        in_tlast_q  <= in_tlast;
        in_tvalid_q <= in_tvalid && !rst;
        if (in_tvalid_q) begin
            mem[wr_ptr[AW-1:0]] <= {in_tlast_q, in_tdata_q};
        end
        if (load) begin
            {m_axis_tlast, m_axis_tdata} <= mem[rd_ptr[AW-1:0]];
        end
        if (rst) begin
            wr_ptr <= {AW+1{1'b0}};
            rd_ptr <= {AW+1{1'b0}};
            m_axis_tvalid <= 1'b0;
            out_credit <= 1'b0;
        end else begin
            if (in_tvalid_q) begin
                wr_ptr <= wr_ptr + 1'b1;
            end
            if (load) begin
                rd_ptr <= rd_ptr + 1'b1;
                m_axis_tvalid <= 1'b1;
            end else if (m_axis_tready) begin
                m_axis_tvalid <= 1'b0;
            end
            out_credit <= load;
        end
    end

`ifdef SIMULATION
    always @(posedge clk) begin
        if (!rst && in_tvalid_q && (wr_ptr - rd_ptr) == DEPTH) begin
            $fatal(1, "%m: a beat arrived with the FIFO full");
        end
    end
`endif

endmodule
