`timescale 1ns / 1ps

// Drop-in replacements for the Xilinx axis_data_fifo IPs of the upstream
// offrac kernel (kernel/user_krnl/offrac_krnl/src/hdl/offrac/gen_ip.tcl),
// built on taxi_axis_fifo.  DEPTH is in beats: axis_fifo_taxi leaves KEEP_EN
// off, so taxi_axis_fifo does not scale it by the byte-lane count.  Depths
// follow gen_ip.tcl:
//
//   axis_data_fifo_0     4096   scheduler queue FIFOs and output FIFO
//   axis_data_fifo_1    16384   scheduler single-packet FIFO
//   axis_data_fifo_2      512   dispatcher
//   axis_data_fifo_3     1024
//   axis_data_fifo_88     512   pkt_receiver notification / metadata
//   axis_data_fifo_513    512   pkt_receiver and pkt_sender payload
//
// b307504 had cut _0 and _1 to 512 beats to make room for the 2x2 cell
// layout.  A multi-segment request sits in a queue FIFO until its declared
// size has arrived, so that also capped a request at 512 beats (32 KB).
// Back at the upstream depths the queue and output FIFOs are 584 x 4096 bits
// (about 2.4 Mbit each, three of them) and the single-packet FIFO is
// 584 x 16384 bits (about 9.6 Mbit); expect them to land in URAM/BRAM inside
// the static pblock.

module axis_data_fifo_0 (
    input  wire         rst,
    input  wire         clk,
    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,
    input  wire [583:0] s_axis_tdata,
    output wire         m_axis_tvalid,
    input  wire         m_axis_tready,
    output wire [583:0] m_axis_tdata
);
    axis_fifo_taxi #(.DATA_WIDTH(584), .DEPTH(4096)) fifo_inst (
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
