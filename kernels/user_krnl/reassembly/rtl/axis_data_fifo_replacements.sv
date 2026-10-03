`timescale 1ns / 1ps

// scheduler.v's request queues and its output FIFO, which set DEPTH
// themselves (scheduler.v QUEUE_DEPTH and OUTPUT_DEPTH, both 4096 as upstream).
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
    // Upstream offrac's depth, 16384 lines (axis_data_fifo_1 in its
    // gen_ip.tcl).  Every request that arrives whole in one segment waits
    // here for its slot, whatever its connection, so the depth is how much of
    // that load is held before the TOE is pushed back on: 512 lines held
    // eight 4 KB requests, 16384 hold 256.  584 x 16384 is 9.57 Mbit, as much
    // as the four request queues together.  It was 16384 before (80b24fc) and
    // went back to 512 (8b8ab93) when a build missed static timing by TNS
    // -344 ns -- beside a half-finished scheduler, so not by itself -- so
    // static timing is the number to watch.
    axis_fifo_taxi #(.DATA_WIDTH(584), .DEPTH(16384)) fifo_inst (
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
