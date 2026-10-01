`timescale 1ns / 1ps

// scheduler.v's request queues and its output FIFO.  The queues set DEPTH
// themselves (scheduler.v QUEUE_DEPTH); the output FIFO keeps the default.
module axis_data_fifo_0 #(
    parameter integer DEPTH = 512
) (
    input  wire         rst,
    input  wire         clk,
    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,
    input  wire [583:0] s_axis_tdata,
    output wire         m_axis_tvalid,
    input  wire         m_axis_tready,
    output wire [583:0] m_axis_tdata
);
    axis_fifo_taxi #(.DATA_WIDTH(584), .DEPTH(DEPTH)) fifo_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tdata(s_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tdata(m_axis_tdata)
    );
endmodule

module axis_data_fifo_1 (
    input  wire         rst,
    input  wire         clk,
    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,
    input  wire [583:0] s_axis_tdata,
    output wire         m_axis_tvalid,
    input  wire         m_axis_tready,
    output wire [583:0] m_axis_tdata
);
    // scheduler.v's fifo_inst_single, the single-packet FIFO, and the only
    // instance of this module.
    //
    // Back to 512. At 16384 this one FIFO is 584 x 16384 = 9.57 Mbit, which is
    // 79 % of all FIFO memory in this kernel -- everything else together is
    // 2.6 Mbit -- and it sits in scheduler.v alongside the queue and output
    // FIFOs, competing with the reworked scheduler for placement. 512 beats
    // does cap a request at 512 beats (32 KB), which is the tradeoff being
    // measured here.
    axis_fifo_taxi #(.DATA_WIDTH(584), .DEPTH(512)) fifo_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tdata(s_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tdata(m_axis_tdata)
    );
endmodule

module axis_data_fifo_2 (
    input  wire         rst,
    input  wire         clk,
    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,
    input  wire [599:0] s_axis_tdata,
    output wire         m_axis_tvalid,
    input  wire         m_axis_tready,
    output wire [599:0] m_axis_tdata
);
    axis_fifo_taxi #(.DATA_WIDTH(600), .DEPTH(512)) fifo_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tdata(s_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tdata(m_axis_tdata)
    );
endmodule

module axis_data_fifo_3 (
    input  wire         rst,
    input  wire         clk,
    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,
    input  wire [551:0] s_axis_tdata,
    output wire         m_axis_tvalid,
    input  wire         m_axis_tready,
    output wire [551:0] m_axis_tdata
);
    axis_fifo_taxi #(.DATA_WIDTH(552), .DEPTH(1024)) fifo_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tdata(s_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tdata(m_axis_tdata)
    );
endmodule

module axis_data_fifo_16 (
    input  wire        rst,
    input  wire        clk,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire [15:0] s_axis_tdata,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire [15:0] m_axis_tdata
);
    axis_fifo_taxi #(.DATA_WIDTH(16), .DEPTH(64)) fifo_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tdata(s_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tdata(m_axis_tdata)
    );
endmodule

module axis_data_fifo_32 (
    input  wire        rst,
    input  wire        clk,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire [31:0] s_axis_tdata,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire [31:0] m_axis_tdata
);
    axis_fifo_taxi #(.DATA_WIDTH(32), .DEPTH(512)) fifo_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tdata(s_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tdata(m_axis_tdata)
    );
endmodule

module axis_data_fifo_32_long (
    input  wire        rst,
    input  wire        clk,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire [47:0] s_axis_tdata,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire [47:0] m_axis_tdata
);
    axis_fifo_taxi #(.DATA_WIDTH(48), .DEPTH(16384)) fifo_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tdata(s_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tdata(m_axis_tdata)
    );
endmodule

module axis_data_fifo_40 (
    input  wire        rst,
    input  wire        clk,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire [39:0] s_axis_tdata,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire [39:0] m_axis_tdata
);
    axis_fifo_taxi #(.DATA_WIDTH(40), .DEPTH(8192)) fifo_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tdata(s_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tdata(m_axis_tdata)
    );
endmodule

module axis_data_fifo_88 (
    input  wire        rst,
    input  wire        clk,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire [87:0] s_axis_tdata,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire [87:0] m_axis_tdata
);
    axis_fifo_taxi #(.DATA_WIDTH(88), .DEPTH(512)) fifo_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tdata(s_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tdata(m_axis_tdata)
    );
endmodule

module axis_data_fifo_513 (
    input  wire         rst,
    input  wire         clk,
    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,
    input  wire [519:0] s_axis_tdata,
    output wire         m_axis_tvalid,
    input  wire         m_axis_tready,
    output wire [519:0] m_axis_tdata
);
    axis_fifo_taxi #(.DATA_WIDTH(520), .DEPTH(512)) fifo_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tdata(s_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tdata(m_axis_tdata)
    );
endmodule
