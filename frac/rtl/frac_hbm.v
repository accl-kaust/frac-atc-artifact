`resetall
`timescale 1ns / 1ps
`default_nettype none


// The three AXI masters -- the TCP stack's m00 (TX buffer) and m01 (RX buffer,
// idle with RX_DDR_BYPASS) and the reconfiguration controller -- are on
// s_axi_clk, the 200 MHz design clock. The HBM AXI ports, and the width and
// protocol converters in front of them, are on hbm_clk, 400 MHz, and each
// master crosses over in an AXI clock converter.
//
// The crossing is at 512 bits, before the 512->256 width converter, so an HBM
// port carries 256 b x 400 MHz = 12.8 GB/s, the whole 512 b x 200 MHz stream.
// With everything on the 200 MHz clock the port was 6.4 GB/s = 51.2 Gbps, and
// that capped the TCP stack's transmit rate: it writes a copy of every byte it
// sends into the TX buffer for retransmission.
module frac_hbm (
    input wire          hbm_ref_clk,
    input wire          s_axi_clk,
    input wire          s_axi_rstn,
    input wire          hbm_clk,
    input wire          hbm_rstn,
    input wire          apb_0_clk,
    input wire          apb_rstn,
    output wire         hbm_cattrip,

    input wire          m00_axi_awvalid,
    output wire         m00_axi_awready,
    input wire [63:0]   m00_axi_awaddr,
    input wire [7:0]    m00_axi_awlen,
    input wire          m00_axi_wvalid,
    output wire         m00_axi_wready,
    input wire [511:0]  m00_axi_wdata,
    input wire [63:0]   m00_axi_wstrb,
    input wire          m00_axi_wlast,
    output wire         m00_axi_bvalid,
    input wire          m00_axi_bready,
    input wire          m00_axi_arvalid,
    output wire         m00_axi_arready,
    input wire [63:0]   m00_axi_araddr,
    input wire [7:0]    m00_axi_arlen,
    output wire         m00_axi_rvalid,
    input wire          m00_axi_rready,
    output wire [511:0] m00_axi_rdata,
    output wire         m00_axi_rlast,

    input wire          m01_axi_awvalid,
    output wire         m01_axi_awready,
    input wire [63:0]   m01_axi_awaddr,
    input wire [7:0]    m01_axi_awlen,
    input wire          m01_axi_wvalid,
    output wire         m01_axi_wready,
    input wire [511:0]  m01_axi_wdata,
    input wire [63:0]   m01_axi_wstrb,
    input wire          m01_axi_wlast,
    output wire         m01_axi_bvalid,
    input wire          m01_axi_bready,
    input wire          m01_axi_arvalid,
    output wire         m01_axi_arready,
    input wire [63:0]   m01_axi_araddr,
    input wire [7:0]    m01_axi_arlen,
    output wire         m01_axi_rvalid,
    input wire          m01_axi_rready,
    output wire [511:0] m01_axi_rdata,
    output wire         m01_axi_rlast,

    input wire [32:0]   reconf_axi_awaddr,
    input wire [1:0]    reconf_axi_awburst,
    input wire [5:0]    reconf_axi_awid,
    input wire [7:0]    reconf_axi_awlen,
    input wire [2:0]    reconf_axi_awsize,
    input wire          reconf_axi_awvalid,
    output wire         reconf_axi_awready,
    input wire [255:0]  reconf_axi_wdata,
    input wire [31:0]   reconf_axi_wstrb,
    input wire [31:0]   reconf_axi_wdata_parity,
    input wire          reconf_axi_wlast,
    input wire          reconf_axi_wvalid,
    output wire         reconf_axi_wready,
    output wire [5:0]   reconf_axi_bid,
    output wire [1:0]   reconf_axi_bresp,
    output wire         reconf_axi_bvalid,
    input wire          reconf_axi_bready,
    input wire [32:0]   reconf_axi_araddr,
    input wire [1:0]    reconf_axi_arburst,
    input wire [5:0]    reconf_axi_arid,
    input wire [7:0]    reconf_axi_arlen,
    input wire [2:0]    reconf_axi_arsize,
    input wire          reconf_axi_arvalid,
    output wire         reconf_axi_arready,
    output wire [5:0]   reconf_axi_rid,
    output wire [255:0] reconf_axi_rdata,
    output wire [31:0]  reconf_axi_rdata_parity,
    output wire [1:0]   reconf_axi_rresp,
    output wire         reconf_axi_rlast,
    output wire         reconf_axi_rvalid,
    input wire          reconf_axi_rready

);


wire hbm_cattrip_0;

assign hbm_cattrip = hbm_cattrip_0;

// The HBM-side reset, registered once more for each IP it resets. Straight
// from its synchronizer, one flop reached into every converter and slice,
// and at 400 MHz that net missed on routing alone. A flop per IP can sit
// beside the IP; KEEP stops synthesis merging the copies back into one.
(* keep = "true" *) reg m00_cc_rstn  = 1'b0;
(* keep = "true" *) reg m00_rsr_rstn = 1'b0;
(* keep = "true" *) reg m00_dw_rstn  = 1'b0;
(* keep = "true" *) reg m00_rsb_rstn = 1'b0;
(* keep = "true" *) reg m00_pc_rstn  = 1'b0;
(* keep = "true" *) reg m00_rsh_rstn = 1'b0;
(* keep = "true" *) reg m01_cc_rstn  = 1'b0;
(* keep = "true" *) reg m01_rsr_rstn = 1'b0;
(* keep = "true" *) reg m01_dw_rstn  = 1'b0;
(* keep = "true" *) reg m01_rsb_rstn = 1'b0;
(* keep = "true" *) reg m01_pc_rstn  = 1'b0;
(* keep = "true" *) reg m01_rsh_rstn = 1'b0;
(* keep = "true" *) reg reconf_cc_rstn = 1'b0;
(* keep = "true" *) reg hbm_port_rstn  = 1'b0;

always @(posedge hbm_clk) begin
    m00_cc_rstn    <= hbm_rstn;
    m00_rsr_rstn   <= hbm_rstn;
    m00_dw_rstn    <= hbm_rstn;
    m00_rsb_rstn   <= hbm_rstn;
    m00_pc_rstn    <= hbm_rstn;
    m00_rsh_rstn   <= hbm_rstn;
    m01_cc_rstn    <= hbm_rstn;
    m01_rsr_rstn   <= hbm_rstn;
    m01_dw_rstn    <= hbm_rstn;
    m01_rsb_rstn   <= hbm_rstn;
    m01_pc_rstn    <= hbm_rstn;
    m01_rsh_rstn   <= hbm_rstn;
    reconf_cc_rstn <= hbm_rstn;
    hbm_port_rstn  <= hbm_rstn;
end

wire [63:0]axi_dwidth_converter_0_m_axi_araddr;
wire [1:0] axi_dwidth_converter_0_m_axi_arburst;
wire [3:0] axi_dwidth_converter_0_m_axi_arcache;
wire [7:0] axi_dwidth_converter_0_m_axi_arlen;
wire [0:0] axi_dwidth_converter_0_m_axi_arlock;
wire [2:0] axi_dwidth_converter_0_m_axi_arprot;
wire [3:0] axi_dwidth_converter_0_m_axi_arqos;
wire       axi_dwidth_converter_0_m_axi_arready;
wire [3:0] axi_dwidth_converter_0_m_axi_arregion;
wire [2:0] axi_dwidth_converter_0_m_axi_arsize;
wire       axi_dwidth_converter_0_m_axi_arvalid;
wire [63:0] axi_dwidth_converter_0_m_axi_awaddr;
wire [1:0]  axi_dwidth_converter_0_m_axi_awburst;
wire [3:0]  axi_dwidth_converter_0_m_axi_awcache;
wire [7:0]  axi_dwidth_converter_0_m_axi_awlen;
wire [0:0]  axi_dwidth_converter_0_m_axi_awlock;
wire [2:0]  axi_dwidth_converter_0_m_axi_awprot;
wire [3:0]  axi_dwidth_converter_0_m_axi_awqos;
wire        axi_dwidth_converter_0_m_axi_awready;
wire [3:0]  axi_dwidth_converter_0_m_axi_awregion;
wire [2:0]  axi_dwidth_converter_0_m_axi_awsize;
wire        axi_dwidth_converter_0_m_axi_awvalid;
wire        axi_dwidth_converter_0_m_axi_bready;
wire [1:0]  axi_dwidth_converter_0_m_axi_bresp;
wire        axi_dwidth_converter_0_m_axi_bvalid;
wire [255:0] axi_dwidth_converter_0_m_axi_rdata;
wire         axi_dwidth_converter_0_m_axi_rlast;
wire         axi_dwidth_converter_0_m_axi_rready;
wire [1:0]   axi_dwidth_converter_0_m_axi_rresp;
wire         axi_dwidth_converter_0_m_axi_rvalid;
wire [255:0] axi_dwidth_converter_0_m_axi_wdata;
wire         axi_dwidth_converter_0_m_axi_wlast;
wire         axi_dwidth_converter_0_m_axi_wready;
wire [31:0]  axi_dwidth_converter_0_m_axi_wstrb;
wire         axi_dwidth_converter_0_m_axi_wvalid;
wire [63:0]  axi_dwidth_converter_1_m_axi_araddr;
wire [1:0]   axi_dwidth_converter_1_m_axi_arburst;
wire [3:0]   axi_dwidth_converter_1_m_axi_arcache;
wire [7:0]   axi_dwidth_converter_1_m_axi_arlen;
wire [0:0]   axi_dwidth_converter_1_m_axi_arlock;
wire [2:0]   axi_dwidth_converter_1_m_axi_arprot;
wire [3:0]   axi_dwidth_converter_1_m_axi_arqos;
wire         axi_dwidth_converter_1_m_axi_arready;
wire [3:0]   axi_dwidth_converter_1_m_axi_arregion;
wire [2:0]   axi_dwidth_converter_1_m_axi_arsize;
wire         axi_dwidth_converter_1_m_axi_arvalid;
wire [63:0]  axi_dwidth_converter_1_m_axi_awaddr;
wire [1:0]   axi_dwidth_converter_1_m_axi_awburst;
wire [3:0]   axi_dwidth_converter_1_m_axi_awcache;
wire [7:0]   axi_dwidth_converter_1_m_axi_awlen;
wire [0:0]   axi_dwidth_converter_1_m_axi_awlock;
wire [2:0]   axi_dwidth_converter_1_m_axi_awprot;
wire [3:0]   axi_dwidth_converter_1_m_axi_awqos;
wire         axi_dwidth_converter_1_m_axi_awready;
wire [3:0]   axi_dwidth_converter_1_m_axi_awregion;
wire [2:0]   axi_dwidth_converter_1_m_axi_awsize;
wire         axi_dwidth_converter_1_m_axi_awvalid;
wire         axi_dwidth_converter_1_m_axi_bready;
wire [1:0]   axi_dwidth_converter_1_m_axi_bresp;
wire         axi_dwidth_converter_1_m_axi_bvalid;
wire [255:0] axi_dwidth_converter_1_m_axi_rdata;
wire         axi_dwidth_converter_1_m_axi_rlast;
wire         axi_dwidth_converter_1_m_axi_rready;
wire [1:0]   axi_dwidth_converter_1_m_axi_rresp;
wire         axi_dwidth_converter_1_m_axi_rvalid;
wire [255:0] axi_dwidth_converter_1_m_axi_wdata;
wire         axi_dwidth_converter_1_m_axi_wlast;
wire         axi_dwidth_converter_1_m_axi_wready;
wire [31:0]  axi_dwidth_converter_1_m_axi_wstrb;
wire         axi_dwidth_converter_1_m_axi_wvalid;
wire [63:0]  axi_protocol_convert_0_m_axi_araddr;
wire [1:0]   axi_protocol_convert_0_m_axi_arburst;
wire [3:0]   axi_protocol_convert_0_m_axi_arlen;
wire         axi_protocol_convert_0_m_axi_arready;
wire [2:0]   axi_protocol_convert_0_m_axi_arsize;
wire         axi_protocol_convert_0_m_axi_arvalid;
wire [63:0]  axi_protocol_convert_0_m_axi_awaddr;
wire [1:0]   axi_protocol_convert_0_m_axi_awburst;
wire [3:0]   axi_protocol_convert_0_m_axi_awlen;
wire         axi_protocol_convert_0_m_axi_awready;
wire [2:0]   axi_protocol_convert_0_m_axi_awsize;
wire         axi_protocol_convert_0_m_axi_awvalid;
wire         axi_protocol_convert_0_m_axi_bready;
wire [1:0]   axi_protocol_convert_0_m_axi_bresp;
wire         axi_protocol_convert_0_m_axi_bvalid;
wire [255:0] axi_protocol_convert_0_m_axi_rdata;
wire         axi_protocol_convert_0_m_axi_rlast;
wire         axi_protocol_convert_0_m_axi_rready;
wire [1:0]   axi_protocol_convert_0_m_axi_rresp;
wire         axi_protocol_convert_0_m_axi_rvalid;
wire [255:0] axi_protocol_convert_0_m_axi_wdata;
wire         axi_protocol_convert_0_m_axi_wlast;
wire         axi_protocol_convert_0_m_axi_wready;
wire [31:0]  axi_protocol_convert_0_m_axi_wstrb;
wire         axi_protocol_convert_0_m_axi_wvalid;
wire [63:0]  axi_protocol_convert_1_m_axi_araddr;
wire [1:0]   axi_protocol_convert_1_m_axi_arburst;
wire [3:0]   axi_protocol_convert_1_m_axi_arlen;
wire         axi_protocol_convert_1_m_axi_arready;
wire [2:0]   axi_protocol_convert_1_m_axi_arsize;
wire         axi_protocol_convert_1_m_axi_arvalid;
wire [63:0]  axi_protocol_convert_1_m_axi_awaddr;
wire [1:0]   axi_protocol_convert_1_m_axi_awburst;
wire [3:0]   axi_protocol_convert_1_m_axi_awlen;
wire         axi_protocol_convert_1_m_axi_awready;
wire [2:0]   axi_protocol_convert_1_m_axi_awsize;
wire         axi_protocol_convert_1_m_axi_awvalid;
wire         axi_protocol_convert_1_m_axi_bready;
wire [1:0]   axi_protocol_convert_1_m_axi_bresp;
wire         axi_protocol_convert_1_m_axi_bvalid;
wire [255:0] axi_protocol_convert_1_m_axi_rdata;
wire         axi_protocol_convert_1_m_axi_rlast;
wire         axi_protocol_convert_1_m_axi_rready;
wire [1:0]   axi_protocol_convert_1_m_axi_rresp;
wire         axi_protocol_convert_1_m_axi_rvalid;
wire [255:0] axi_protocol_convert_1_m_axi_wdata;
wire         axi_protocol_convert_1_m_axi_wlast;
wire         axi_protocol_convert_1_m_axi_wready;
wire [31:0]  axi_protocol_convert_1_m_axi_wstrb;
wire         axi_protocol_convert_1_m_axi_wvalid;
wire [31:0]  axis_dwidth_converter_0_m_axis_tdata;
wire [3:0]   axis_dwidth_converter_0_m_axis_tkeep;
wire         axis_dwidth_converter_0_m_axis_tlast;
wire         axis_dwidth_converter_0_m_axis_tready;
wire         axis_dwidth_converter_0_m_axis_tvalid;

// m00 and m01 on hbm_clk, between the clock and the width converters
wire [63:0]  m00_cc_awaddr,  m01_cc_awaddr;
wire [7:0]   m00_cc_awlen,   m01_cc_awlen;
wire [2:0]   m00_cc_awsize,  m01_cc_awsize;
wire [1:0]   m00_cc_awburst, m01_cc_awburst;
wire [0:0]   m00_cc_awlock,  m01_cc_awlock;
wire [3:0]   m00_cc_awcache, m01_cc_awcache;
wire [2:0]   m00_cc_awprot,  m01_cc_awprot;
wire [3:0]   m00_cc_awregion, m01_cc_awregion;
wire [3:0]   m00_cc_awqos,   m01_cc_awqos;
wire         m00_cc_awvalid, m01_cc_awvalid;
wire         m00_cc_awready, m01_cc_awready;
wire [511:0] m00_cc_wdata,   m01_cc_wdata;
wire [63:0]  m00_cc_wstrb,   m01_cc_wstrb;
wire         m00_cc_wlast,   m01_cc_wlast;
wire         m00_cc_wvalid,  m01_cc_wvalid;
wire         m00_cc_wready,  m01_cc_wready;
wire [1:0]   m00_cc_bresp,   m01_cc_bresp;
wire         m00_cc_bvalid,  m01_cc_bvalid;
wire         m00_cc_bready,  m01_cc_bready;
wire [63:0]  m00_cc_araddr,  m01_cc_araddr;
wire [7:0]   m00_cc_arlen,   m01_cc_arlen;
wire [2:0]   m00_cc_arsize,  m01_cc_arsize;
wire [1:0]   m00_cc_arburst, m01_cc_arburst;
wire [0:0]   m00_cc_arlock,  m01_cc_arlock;
wire [3:0]   m00_cc_arcache, m01_cc_arcache;
wire [2:0]   m00_cc_arprot,  m01_cc_arprot;
wire [3:0]   m00_cc_arregion, m01_cc_arregion;
wire [3:0]   m00_cc_arqos,   m01_cc_arqos;
wire         m00_cc_arvalid, m01_cc_arvalid;
wire         m00_cc_arready, m01_cc_arready;
wire [511:0] m00_cc_rdata,   m01_cc_rdata;
wire [1:0]   m00_cc_rresp,   m01_cc_rresp;
wire         m00_cc_rlast,   m01_cc_rlast;
wire         m00_cc_rvalid,  m01_cc_rvalid;
wire         m00_cc_rready,  m01_cc_rready;

axi_clock_conv_512 m00_axi_clock_conv_inst (
    .s_axi_aclk(s_axi_clk),
    .s_axi_aresetn(s_axi_rstn),

    .s_axi_awaddr(m00_axi_awaddr),
    .s_axi_awlen(m00_axi_awlen),
    .s_axi_awsize({1'b1,1'b1,1'b0}),
    .s_axi_awburst({1'b0,1'b1}),
    .s_axi_awlock(1'b0),
    .s_axi_awcache({1'b0,1'b0,1'b1,1'b1}),
    .s_axi_awprot({1'b0,1'b0,1'b0}),
    .s_axi_awregion({1'b0,1'b0,1'b0,1'b0}),
    .s_axi_awqos({1'b0,1'b0,1'b0,1'b0}),
    .s_axi_awvalid(m00_axi_awvalid),
    .s_axi_awready(m00_axi_awready),
    .s_axi_wdata(m00_axi_wdata),
    .s_axi_wstrb(m00_axi_wstrb),
    .s_axi_wlast(m00_axi_wlast),
    .s_axi_wvalid(m00_axi_wvalid),
    .s_axi_wready(m00_axi_wready),
    .s_axi_bresp(),
    .s_axi_bvalid(m00_axi_bvalid),
    .s_axi_bready(m00_axi_bready),
    .s_axi_araddr(m00_axi_araddr),
    .s_axi_arlen(m00_axi_arlen),
    .s_axi_arsize({1'b1,1'b1,1'b0}),
    .s_axi_arburst({1'b0,1'b1}),
    .s_axi_arlock(1'b0),
    .s_axi_arcache({1'b0,1'b0,1'b1,1'b1}),
    .s_axi_arprot({1'b0,1'b0,1'b0}),
    .s_axi_arregion({1'b0,1'b0,1'b0,1'b0}),
    .s_axi_arqos({1'b0,1'b0,1'b0,1'b0}),
    .s_axi_arvalid(m00_axi_arvalid),
    .s_axi_arready(m00_axi_arready),
    .s_axi_rdata(m00_axi_rdata),
    .s_axi_rresp(),
    .s_axi_rlast(m00_axi_rlast),
    .s_axi_rvalid(m00_axi_rvalid),
    .s_axi_rready(m00_axi_rready),

    .m_axi_aclk(hbm_clk),
    .m_axi_aresetn(m00_cc_rstn),

    .m_axi_awaddr(m00_cc_awaddr),
    .m_axi_awlen(m00_cc_awlen),
    .m_axi_awsize(m00_cc_awsize),
    .m_axi_awburst(m00_cc_awburst),
    .m_axi_awlock(m00_cc_awlock),
    .m_axi_awcache(m00_cc_awcache),
    .m_axi_awprot(m00_cc_awprot),
    .m_axi_awregion(m00_cc_awregion),
    .m_axi_awqos(m00_cc_awqos),
    .m_axi_awvalid(m00_cc_awvalid),
    .m_axi_awready(m00_cc_awready),
    .m_axi_wdata(m00_cc_wdata),
    .m_axi_wstrb(m00_cc_wstrb),
    .m_axi_wlast(m00_cc_wlast),
    .m_axi_wvalid(m00_cc_wvalid),
    .m_axi_wready(m00_cc_wready),
    .m_axi_bresp(m00_cc_bresp),
    .m_axi_bvalid(m00_cc_bvalid),
    .m_axi_bready(m00_cc_bready),
    .m_axi_araddr(m00_cc_araddr),
    .m_axi_arlen(m00_cc_arlen),
    .m_axi_arsize(m00_cc_arsize),
    .m_axi_arburst(m00_cc_arburst),
    .m_axi_arlock(m00_cc_arlock),
    .m_axi_arcache(m00_cc_arcache),
    .m_axi_arprot(m00_cc_arprot),
    .m_axi_arregion(m00_cc_arregion),
    .m_axi_arqos(m00_cc_arqos),
    .m_axi_arvalid(m00_cc_arvalid),
    .m_axi_arready(m00_cc_arready),
    .m_axi_rdata(m00_cc_rdata),
    .m_axi_rresp(m00_cc_rresp),
    .m_axi_rlast(m00_cc_rlast),
    .m_axi_rvalid(m00_cc_rvalid),
    .m_axi_rready(m00_cc_rready)
);

axi_clock_conv_512 m01_axi_clock_conv_inst (
    .s_axi_aclk(s_axi_clk),
    .s_axi_aresetn(s_axi_rstn),

    .s_axi_awaddr(m01_axi_awaddr),
    .s_axi_awlen(m01_axi_awlen),
    .s_axi_awsize({1'b1,1'b1,1'b0}),
    .s_axi_awburst({1'b0,1'b1}),
    .s_axi_awlock(1'b0),
    .s_axi_awcache({1'b0,1'b0,1'b1,1'b1}),
    .s_axi_awprot({1'b0,1'b0,1'b0}),
    .s_axi_awregion({1'b0,1'b0,1'b0,1'b0}),
    .s_axi_awqos({1'b0,1'b0,1'b0,1'b0}),
    .s_axi_awvalid(m01_axi_awvalid),
    .s_axi_awready(m01_axi_awready),
    .s_axi_wdata(m01_axi_wdata),
    .s_axi_wstrb(m01_axi_wstrb),
    .s_axi_wlast(m01_axi_wlast),
    .s_axi_wvalid(m01_axi_wvalid),
    .s_axi_wready(m01_axi_wready),
    .s_axi_bresp(),
    .s_axi_bvalid(m01_axi_bvalid),
    .s_axi_bready(m01_axi_bready),
    .s_axi_araddr(m01_axi_araddr),
    .s_axi_arlen(m01_axi_arlen),
    .s_axi_arsize({1'b1,1'b1,1'b0}),
    .s_axi_arburst({1'b0,1'b1}),
    .s_axi_arlock(1'b0),
    .s_axi_arcache({1'b0,1'b0,1'b1,1'b1}),
    .s_axi_arprot({1'b0,1'b0,1'b0}),
    .s_axi_arregion({1'b0,1'b0,1'b0,1'b0}),
    .s_axi_arqos({1'b0,1'b0,1'b0,1'b0}),
    .s_axi_arvalid(m01_axi_arvalid),
    .s_axi_arready(m01_axi_arready),
    .s_axi_rdata(m01_axi_rdata),
    .s_axi_rresp(),
    .s_axi_rlast(m01_axi_rlast),
    .s_axi_rvalid(m01_axi_rvalid),
    .s_axi_rready(m01_axi_rready),

    .m_axi_aclk(hbm_clk),
    .m_axi_aresetn(m01_cc_rstn),

    .m_axi_awaddr(m01_cc_awaddr),
    .m_axi_awlen(m01_cc_awlen),
    .m_axi_awsize(m01_cc_awsize),
    .m_axi_awburst(m01_cc_awburst),
    .m_axi_awlock(m01_cc_awlock),
    .m_axi_awcache(m01_cc_awcache),
    .m_axi_awprot(m01_cc_awprot),
    .m_axi_awregion(m01_cc_awregion),
    .m_axi_awqos(m01_cc_awqos),
    .m_axi_awvalid(m01_cc_awvalid),
    .m_axi_awready(m01_cc_awready),
    .m_axi_wdata(m01_cc_wdata),
    .m_axi_wstrb(m01_cc_wstrb),
    .m_axi_wlast(m01_cc_wlast),
    .m_axi_wvalid(m01_cc_wvalid),
    .m_axi_wready(m01_cc_wready),
    .m_axi_bresp(m01_cc_bresp),
    .m_axi_bvalid(m01_cc_bvalid),
    .m_axi_bready(m01_cc_bready),
    .m_axi_araddr(m01_cc_araddr),
    .m_axi_arlen(m01_cc_arlen),
    .m_axi_arsize(m01_cc_arsize),
    .m_axi_arburst(m01_cc_arburst),
    .m_axi_arlock(m01_cc_arlock),
    .m_axi_arcache(m01_cc_arcache),
    .m_axi_arprot(m01_cc_arprot),
    .m_axi_arregion(m01_cc_arregion),
    .m_axi_arqos(m01_cc_arqos),
    .m_axi_arvalid(m01_cc_arvalid),
    .m_axi_arready(m01_cc_arready),
    .m_axi_rdata(m01_cc_rdata),
    .m_axi_rresp(m01_cc_rresp),
    .m_axi_rlast(m01_cc_rlast),
    .m_axi_rvalid(m01_cc_rvalid),
    .m_axi_rready(m01_cc_rready)
);

// Read-channel register slices between each clock converter and its width
// converter: the clock converter's read FIFO write enable fans out to every
// LUTRAM of the 512-bit FIFO (about 600 loads), and at 400 MHz it could not
// also carry the width converter's read logic in front of it. The other
// channels pass straight through.
wire [63:0]    m00_rsc_awaddr;
wire [7:0]     m00_rsc_awlen;
wire [2:0]     m00_rsc_awsize;
wire [1:0]     m00_rsc_awburst;
wire           m00_rsc_awlock;
wire [3:0]     m00_rsc_awcache;
wire [2:0]     m00_rsc_awprot;
wire [3:0]     m00_rsc_awregion;
wire [3:0]     m00_rsc_awqos;
wire           m00_rsc_awvalid;
wire           m00_rsc_awready;
wire [511:0]   m00_rsc_wdata;
wire [63:0]    m00_rsc_wstrb;
wire           m00_rsc_wlast;
wire           m00_rsc_wvalid;
wire           m00_rsc_wready;
wire [1:0]     m00_rsc_bresp;
wire           m00_rsc_bvalid;
wire           m00_rsc_bready;
wire [63:0]    m00_rsc_araddr;
wire [7:0]     m00_rsc_arlen;
wire [2:0]     m00_rsc_arsize;
wire [1:0]     m00_rsc_arburst;
wire           m00_rsc_arlock;
wire [3:0]     m00_rsc_arcache;
wire [2:0]     m00_rsc_arprot;
wire [3:0]     m00_rsc_arregion;
wire [3:0]     m00_rsc_arqos;
wire           m00_rsc_arvalid;
wire           m00_rsc_arready;
wire [511:0]   m00_rsc_rdata;
wire [1:0]     m00_rsc_rresp;
wire           m00_rsc_rlast;
wire           m00_rsc_rvalid;
wire           m00_rsc_rready;
wire [63:0]    m01_rsc_awaddr;
wire [7:0]     m01_rsc_awlen;
wire [2:0]     m01_rsc_awsize;
wire [1:0]     m01_rsc_awburst;
wire           m01_rsc_awlock;
wire [3:0]     m01_rsc_awcache;
wire [2:0]     m01_rsc_awprot;
wire [3:0]     m01_rsc_awregion;
wire [3:0]     m01_rsc_awqos;
wire           m01_rsc_awvalid;
wire           m01_rsc_awready;
wire [511:0]   m01_rsc_wdata;
wire [63:0]    m01_rsc_wstrb;
wire           m01_rsc_wlast;
wire           m01_rsc_wvalid;
wire           m01_rsc_wready;
wire [1:0]     m01_rsc_bresp;
wire           m01_rsc_bvalid;
wire           m01_rsc_bready;
wire [63:0]    m01_rsc_araddr;
wire [7:0]     m01_rsc_arlen;
wire [2:0]     m01_rsc_arsize;
wire [1:0]     m01_rsc_arburst;
wire           m01_rsc_arlock;
wire [3:0]     m01_rsc_arcache;
wire [2:0]     m01_rsc_arprot;
wire [3:0]     m01_rsc_arregion;
wire [3:0]     m01_rsc_arqos;
wire           m01_rsc_arvalid;
wire           m01_rsc_arready;
wire [511:0]   m01_rsc_rdata;
wire [1:0]     m01_rsc_rresp;
wire           m01_rsc_rlast;
wire           m01_rsc_rvalid;
wire           m01_rsc_rready;

axi_reg_slice_512_r m00_axi_reg_slice_r_inst (
    .aclk(hbm_clk),
    .aresetn(m00_rsr_rstn),

    .s_axi_awaddr(m00_cc_awaddr),
    .s_axi_awlen(m00_cc_awlen),
    .s_axi_awsize(m00_cc_awsize),
    .s_axi_awburst(m00_cc_awburst),
    .s_axi_awlock(m00_cc_awlock),
    .s_axi_awcache(m00_cc_awcache),
    .s_axi_awprot(m00_cc_awprot),
    .s_axi_awregion(m00_cc_awregion),
    .s_axi_awqos(m00_cc_awqos),
    .s_axi_awvalid(m00_cc_awvalid),
    .s_axi_awready(m00_cc_awready),
    .s_axi_wdata(m00_cc_wdata),
    .s_axi_wstrb(m00_cc_wstrb),
    .s_axi_wlast(m00_cc_wlast),
    .s_axi_wvalid(m00_cc_wvalid),
    .s_axi_wready(m00_cc_wready),
    .s_axi_bresp(m00_cc_bresp),
    .s_axi_bvalid(m00_cc_bvalid),
    .s_axi_bready(m00_cc_bready),
    .s_axi_araddr(m00_cc_araddr),
    .s_axi_arlen(m00_cc_arlen),
    .s_axi_arsize(m00_cc_arsize),
    .s_axi_arburst(m00_cc_arburst),
    .s_axi_arlock(m00_cc_arlock),
    .s_axi_arcache(m00_cc_arcache),
    .s_axi_arprot(m00_cc_arprot),
    .s_axi_arregion(m00_cc_arregion),
    .s_axi_arqos(m00_cc_arqos),
    .s_axi_arvalid(m00_cc_arvalid),
    .s_axi_arready(m00_cc_arready),
    .s_axi_rdata(m00_cc_rdata),
    .s_axi_rresp(m00_cc_rresp),
    .s_axi_rlast(m00_cc_rlast),
    .s_axi_rvalid(m00_cc_rvalid),
    .s_axi_rready(m00_cc_rready),

    .m_axi_awaddr(m00_rsc_awaddr),
    .m_axi_awlen(m00_rsc_awlen),
    .m_axi_awsize(m00_rsc_awsize),
    .m_axi_awburst(m00_rsc_awburst),
    .m_axi_awlock(m00_rsc_awlock),
    .m_axi_awcache(m00_rsc_awcache),
    .m_axi_awprot(m00_rsc_awprot),
    .m_axi_awregion(m00_rsc_awregion),
    .m_axi_awqos(m00_rsc_awqos),
    .m_axi_awvalid(m00_rsc_awvalid),
    .m_axi_awready(m00_rsc_awready),
    .m_axi_wdata(m00_rsc_wdata),
    .m_axi_wstrb(m00_rsc_wstrb),
    .m_axi_wlast(m00_rsc_wlast),
    .m_axi_wvalid(m00_rsc_wvalid),
    .m_axi_wready(m00_rsc_wready),
    .m_axi_bresp(m00_rsc_bresp),
    .m_axi_bvalid(m00_rsc_bvalid),
    .m_axi_bready(m00_rsc_bready),
    .m_axi_araddr(m00_rsc_araddr),
    .m_axi_arlen(m00_rsc_arlen),
    .m_axi_arsize(m00_rsc_arsize),
    .m_axi_arburst(m00_rsc_arburst),
    .m_axi_arlock(m00_rsc_arlock),
    .m_axi_arcache(m00_rsc_arcache),
    .m_axi_arprot(m00_rsc_arprot),
    .m_axi_arregion(m00_rsc_arregion),
    .m_axi_arqos(m00_rsc_arqos),
    .m_axi_arvalid(m00_rsc_arvalid),
    .m_axi_arready(m00_rsc_arready),
    .m_axi_rdata(m00_rsc_rdata),
    .m_axi_rresp(m00_rsc_rresp),
    .m_axi_rlast(m00_rsc_rlast),
    .m_axi_rvalid(m00_rsc_rvalid),
    .m_axi_rready(m00_rsc_rready)
);

axi_reg_slice_512_r m01_axi_reg_slice_r_inst (
    .aclk(hbm_clk),
    .aresetn(m01_rsr_rstn),

    .s_axi_awaddr(m01_cc_awaddr),
    .s_axi_awlen(m01_cc_awlen),
    .s_axi_awsize(m01_cc_awsize),
    .s_axi_awburst(m01_cc_awburst),
    .s_axi_awlock(m01_cc_awlock),
    .s_axi_awcache(m01_cc_awcache),
    .s_axi_awprot(m01_cc_awprot),
    .s_axi_awregion(m01_cc_awregion),
    .s_axi_awqos(m01_cc_awqos),
    .s_axi_awvalid(m01_cc_awvalid),
    .s_axi_awready(m01_cc_awready),
    .s_axi_wdata(m01_cc_wdata),
    .s_axi_wstrb(m01_cc_wstrb),
    .s_axi_wlast(m01_cc_wlast),
    .s_axi_wvalid(m01_cc_wvalid),
    .s_axi_wready(m01_cc_wready),
    .s_axi_bresp(m01_cc_bresp),
    .s_axi_bvalid(m01_cc_bvalid),
    .s_axi_bready(m01_cc_bready),
    .s_axi_araddr(m01_cc_araddr),
    .s_axi_arlen(m01_cc_arlen),
    .s_axi_arsize(m01_cc_arsize),
    .s_axi_arburst(m01_cc_arburst),
    .s_axi_arlock(m01_cc_arlock),
    .s_axi_arcache(m01_cc_arcache),
    .s_axi_arprot(m01_cc_arprot),
    .s_axi_arregion(m01_cc_arregion),
    .s_axi_arqos(m01_cc_arqos),
    .s_axi_arvalid(m01_cc_arvalid),
    .s_axi_arready(m01_cc_arready),
    .s_axi_rdata(m01_cc_rdata),
    .s_axi_rresp(m01_cc_rresp),
    .s_axi_rlast(m01_cc_rlast),
    .s_axi_rvalid(m01_cc_rvalid),
    .s_axi_rready(m01_cc_rready),

    .m_axi_awaddr(m01_rsc_awaddr),
    .m_axi_awlen(m01_rsc_awlen),
    .m_axi_awsize(m01_rsc_awsize),
    .m_axi_awburst(m01_rsc_awburst),
    .m_axi_awlock(m01_rsc_awlock),
    .m_axi_awcache(m01_rsc_awcache),
    .m_axi_awprot(m01_rsc_awprot),
    .m_axi_awregion(m01_rsc_awregion),
    .m_axi_awqos(m01_rsc_awqos),
    .m_axi_awvalid(m01_rsc_awvalid),
    .m_axi_awready(m01_rsc_awready),
    .m_axi_wdata(m01_rsc_wdata),
    .m_axi_wstrb(m01_rsc_wstrb),
    .m_axi_wlast(m01_rsc_wlast),
    .m_axi_wvalid(m01_rsc_wvalid),
    .m_axi_wready(m01_rsc_wready),
    .m_axi_bresp(m01_rsc_bresp),
    .m_axi_bvalid(m01_rsc_bvalid),
    .m_axi_bready(m01_rsc_bready),
    .m_axi_araddr(m01_rsc_araddr),
    .m_axi_arlen(m01_rsc_arlen),
    .m_axi_arsize(m01_rsc_arsize),
    .m_axi_arburst(m01_rsc_arburst),
    .m_axi_arlock(m01_rsc_arlock),
    .m_axi_arcache(m01_rsc_arcache),
    .m_axi_arprot(m01_rsc_arprot),
    .m_axi_arregion(m01_rsc_arregion),
    .m_axi_arqos(m01_rsc_arqos),
    .m_axi_arvalid(m01_rsc_arvalid),
    .m_axi_arready(m01_rsc_arready),
    .m_axi_rdata(m01_rsc_rdata),
    .m_axi_rresp(m01_rsc_rresp),
    .m_axi_rlast(m01_rsc_rlast),
    .m_axi_rvalid(m01_rsc_rvalid),
    .m_axi_rready(m01_rsc_rready)
);

axi_dwidth_conv m00_axi_dwidth_conv_inst (
    .s_axi_aclk(hbm_clk),
    .s_axi_aresetn(m00_dw_rstn),

    .m_axi_araddr(axi_dwidth_converter_0_m_axi_araddr),
    .m_axi_arburst(axi_dwidth_converter_0_m_axi_arburst),
    .m_axi_arcache(axi_dwidth_converter_0_m_axi_arcache),
    .m_axi_arlen(axi_dwidth_converter_0_m_axi_arlen),
    .m_axi_arlock(axi_dwidth_converter_0_m_axi_arlock),
    .m_axi_arprot(axi_dwidth_converter_0_m_axi_arprot),
    .m_axi_arqos(axi_dwidth_converter_0_m_axi_arqos),
    .m_axi_arready(axi_dwidth_converter_0_m_axi_arready),
    .m_axi_arregion(axi_dwidth_converter_0_m_axi_arregion),
    .m_axi_arsize(axi_dwidth_converter_0_m_axi_arsize),
    .m_axi_arvalid(axi_dwidth_converter_0_m_axi_arvalid),
    .m_axi_awaddr(axi_dwidth_converter_0_m_axi_awaddr),
    .m_axi_awburst(axi_dwidth_converter_0_m_axi_awburst),
    .m_axi_awcache(axi_dwidth_converter_0_m_axi_awcache),
    .m_axi_awlen(axi_dwidth_converter_0_m_axi_awlen),
    .m_axi_awlock(axi_dwidth_converter_0_m_axi_awlock),
    .m_axi_awprot(axi_dwidth_converter_0_m_axi_awprot),
    .m_axi_awqos(axi_dwidth_converter_0_m_axi_awqos),
    .m_axi_awready(axi_dwidth_converter_0_m_axi_awready),
    .m_axi_awregion(axi_dwidth_converter_0_m_axi_awregion),
    .m_axi_awsize(axi_dwidth_converter_0_m_axi_awsize),
    .m_axi_awvalid(axi_dwidth_converter_0_m_axi_awvalid),
    .m_axi_bready(axi_dwidth_converter_0_m_axi_bready),
    .m_axi_bresp(axi_dwidth_converter_0_m_axi_bresp),
    .m_axi_bvalid(axi_dwidth_converter_0_m_axi_bvalid),
    .m_axi_rdata(axi_dwidth_converter_0_m_axi_rdata),
    .m_axi_rlast(axi_dwidth_converter_0_m_axi_rlast),
    .m_axi_rready(axi_dwidth_converter_0_m_axi_rready),
    .m_axi_rresp(axi_dwidth_converter_0_m_axi_rresp),
    .m_axi_rvalid(axi_dwidth_converter_0_m_axi_rvalid),
    .m_axi_wdata(axi_dwidth_converter_0_m_axi_wdata),
    .m_axi_wlast(axi_dwidth_converter_0_m_axi_wlast),
    .m_axi_wready(axi_dwidth_converter_0_m_axi_wready),
    .m_axi_wstrb(axi_dwidth_converter_0_m_axi_wstrb),
    .m_axi_wvalid(axi_dwidth_converter_0_m_axi_wvalid),

    .s_axi_araddr(m00_rsc_araddr),
    .s_axi_arburst(m00_rsc_arburst),
    .s_axi_arcache(m00_rsc_arcache),
    .s_axi_arlen(m00_rsc_arlen),
    .s_axi_arlock(m00_rsc_arlock),
    .s_axi_arprot(m00_rsc_arprot),
    .s_axi_arqos(m00_rsc_arqos),
    .s_axi_arready(m00_rsc_arready),
    .s_axi_arregion(m00_rsc_arregion),
    .s_axi_arsize(m00_rsc_arsize),
    .s_axi_arvalid(m00_rsc_arvalid),
    .s_axi_awaddr(m00_rsc_awaddr),
    .s_axi_awburst(m00_rsc_awburst),
    .s_axi_awcache(m00_rsc_awcache),
    .s_axi_awlen(m00_rsc_awlen),
    .s_axi_awlock(m00_rsc_awlock),
    .s_axi_awprot(m00_rsc_awprot),
    .s_axi_awqos(m00_rsc_awqos),
    .s_axi_awready(m00_rsc_awready),
    .s_axi_awregion(m00_rsc_awregion),
    .s_axi_awsize(m00_rsc_awsize),
    .s_axi_awvalid(m00_rsc_awvalid),
    .s_axi_bready(m00_rsc_bready),
    .s_axi_bresp(m00_rsc_bresp),
    .s_axi_bvalid(m00_rsc_bvalid),
    .s_axi_rdata(m00_rsc_rdata),
    .s_axi_rlast(m00_rsc_rlast),
    .s_axi_rready(m00_rsc_rready),
    .s_axi_rresp(m00_rsc_rresp),
    .s_axi_rvalid(m00_rsc_rvalid),
    .s_axi_wdata(m00_rsc_wdata),
    .s_axi_wlast(m00_rsc_wlast),
    .s_axi_wready(m00_rsc_wready),
    .s_axi_wstrb(m00_rsc_wstrb),
    .s_axi_wvalid(m00_rsc_wvalid)
);

axi_dwidth_conv m01_axi_dwidth_conv_inst (
    .s_axi_aclk(hbm_clk),
    .s_axi_aresetn(m01_dw_rstn),

    .m_axi_araddr(axi_dwidth_converter_1_m_axi_araddr),
    .m_axi_arburst(axi_dwidth_converter_1_m_axi_arburst),
    .m_axi_arcache(axi_dwidth_converter_1_m_axi_arcache),
    .m_axi_arlen(axi_dwidth_converter_1_m_axi_arlen),
    .m_axi_arlock(axi_dwidth_converter_1_m_axi_arlock),
    .m_axi_arprot(axi_dwidth_converter_1_m_axi_arprot),
    .m_axi_arqos(axi_dwidth_converter_1_m_axi_arqos),
    .m_axi_arready(axi_dwidth_converter_1_m_axi_arready),
    .m_axi_arregion(axi_dwidth_converter_1_m_axi_arregion),
    .m_axi_arsize(axi_dwidth_converter_1_m_axi_arsize),
    .m_axi_arvalid(axi_dwidth_converter_1_m_axi_arvalid),
    .m_axi_awaddr(axi_dwidth_converter_1_m_axi_awaddr),
    .m_axi_awburst(axi_dwidth_converter_1_m_axi_awburst),
    .m_axi_awcache(axi_dwidth_converter_1_m_axi_awcache),
    .m_axi_awlen(axi_dwidth_converter_1_m_axi_awlen),
    .m_axi_awlock(axi_dwidth_converter_1_m_axi_awlock),
    .m_axi_awprot(axi_dwidth_converter_1_m_axi_awprot),
    .m_axi_awqos(axi_dwidth_converter_1_m_axi_awqos),
    .m_axi_awready(axi_dwidth_converter_1_m_axi_awready),
    .m_axi_awregion(axi_dwidth_converter_1_m_axi_awregion),
    .m_axi_awsize(axi_dwidth_converter_1_m_axi_awsize),
    .m_axi_awvalid(axi_dwidth_converter_1_m_axi_awvalid),
    .m_axi_bready(axi_dwidth_converter_1_m_axi_bready),
    .m_axi_bresp(axi_dwidth_converter_1_m_axi_bresp),
    .m_axi_bvalid(axi_dwidth_converter_1_m_axi_bvalid),
    .m_axi_rdata(axi_dwidth_converter_1_m_axi_rdata),
    .m_axi_rlast(axi_dwidth_converter_1_m_axi_rlast),
    .m_axi_rready(axi_dwidth_converter_1_m_axi_rready),
    .m_axi_rresp(axi_dwidth_converter_1_m_axi_rresp),
    .m_axi_rvalid(axi_dwidth_converter_1_m_axi_rvalid),
    .m_axi_wdata(axi_dwidth_converter_1_m_axi_wdata),
    .m_axi_wlast(axi_dwidth_converter_1_m_axi_wlast),
    .m_axi_wready(axi_dwidth_converter_1_m_axi_wready),
    .m_axi_wstrb(axi_dwidth_converter_1_m_axi_wstrb),
    .m_axi_wvalid(axi_dwidth_converter_1_m_axi_wvalid),

    .s_axi_araddr(m01_rsc_araddr),
    .s_axi_arburst(m01_rsc_arburst),
    .s_axi_arcache(m01_rsc_arcache),
    .s_axi_arlen(m01_rsc_arlen),
    .s_axi_arlock(m01_rsc_arlock),
    .s_axi_arprot(m01_rsc_arprot),
    .s_axi_arqos(m01_rsc_arqos),
    .s_axi_arready(m01_rsc_arready),
    .s_axi_arregion(m01_rsc_arregion),
    .s_axi_arsize(m01_rsc_arsize),
    .s_axi_arvalid(m01_rsc_arvalid),
    .s_axi_awaddr(m01_rsc_awaddr),
    .s_axi_awburst(m01_rsc_awburst),
    .s_axi_awcache(m01_rsc_awcache),
    .s_axi_awlen(m01_rsc_awlen),
    .s_axi_awlock(m01_rsc_awlock),
    .s_axi_awprot(m01_rsc_awprot),
    .s_axi_awqos(m01_rsc_awqos),
    .s_axi_awready(m01_rsc_awready),
    .s_axi_awregion(m01_rsc_awregion),
    .s_axi_awsize(m01_rsc_awsize),
    .s_axi_awvalid(m01_rsc_awvalid),
    .s_axi_bready(m01_rsc_bready),
    .s_axi_bresp(m01_rsc_bresp),
    .s_axi_bvalid(m01_rsc_bvalid),
    .s_axi_rdata(m01_rsc_rdata),
    .s_axi_rlast(m01_rsc_rlast),
    .s_axi_rready(m01_rsc_rready),
    .s_axi_rresp(m01_rsc_rresp),
    .s_axi_rvalid(m01_rsc_rvalid),
    .s_axi_wdata(m01_rsc_wdata),
    .s_axi_wlast(m01_rsc_wlast),
    .s_axi_wready(m01_rsc_wready),
    .s_axi_wstrb(m01_rsc_wstrb),
    .s_axi_wvalid(m01_rsc_wvalid)
);

// Register slices between each width converter and its protocol converter,
// so each converter's logic sits between flops. With only the slices at the
// HBM ports, the width converter's read ready chained through the protocol
// converter into the port's slice, and at 400 MHz that path missed by
// 0.17 ns: the TX buffer's datamover sits mid-SLR0, the port at its
// bottom-left corner, and the converters are strung out between the two.
wire [63:0]    m00_rsb_awaddr;
wire [7:0]     m00_rsb_awlen;
wire [2:0]     m00_rsb_awsize;
wire [1:0]     m00_rsb_awburst;
wire           m00_rsb_awlock;
wire [3:0]     m00_rsb_awcache;
wire [2:0]     m00_rsb_awprot;
wire [3:0]     m00_rsb_awregion;
wire [3:0]     m00_rsb_awqos;
wire           m00_rsb_awvalid;
wire           m00_rsb_awready;
wire [255:0]   m00_rsb_wdata;
wire [31:0]    m00_rsb_wstrb;
wire           m00_rsb_wlast;
wire           m00_rsb_wvalid;
wire           m00_rsb_wready;
wire [1:0]     m00_rsb_bresp;
wire           m00_rsb_bvalid;
wire           m00_rsb_bready;
wire [63:0]    m00_rsb_araddr;
wire [7:0]     m00_rsb_arlen;
wire [2:0]     m00_rsb_arsize;
wire [1:0]     m00_rsb_arburst;
wire           m00_rsb_arlock;
wire [3:0]     m00_rsb_arcache;
wire [2:0]     m00_rsb_arprot;
wire [3:0]     m00_rsb_arregion;
wire [3:0]     m00_rsb_arqos;
wire           m00_rsb_arvalid;
wire           m00_rsb_arready;
wire [255:0]   m00_rsb_rdata;
wire [1:0]     m00_rsb_rresp;
wire           m00_rsb_rlast;
wire           m00_rsb_rvalid;
wire           m00_rsb_rready;
wire [63:0]    m01_rsb_awaddr;
wire [7:0]     m01_rsb_awlen;
wire [2:0]     m01_rsb_awsize;
wire [1:0]     m01_rsb_awburst;
wire           m01_rsb_awlock;
wire [3:0]     m01_rsb_awcache;
wire [2:0]     m01_rsb_awprot;
wire [3:0]     m01_rsb_awregion;
wire [3:0]     m01_rsb_awqos;
wire           m01_rsb_awvalid;
wire           m01_rsb_awready;
wire [255:0]   m01_rsb_wdata;
wire [31:0]    m01_rsb_wstrb;
wire           m01_rsb_wlast;
wire           m01_rsb_wvalid;
wire           m01_rsb_wready;
wire [1:0]     m01_rsb_bresp;
wire           m01_rsb_bvalid;
wire           m01_rsb_bready;
wire [63:0]    m01_rsb_araddr;
wire [7:0]     m01_rsb_arlen;
wire [2:0]     m01_rsb_arsize;
wire [1:0]     m01_rsb_arburst;
wire           m01_rsb_arlock;
wire [3:0]     m01_rsb_arcache;
wire [2:0]     m01_rsb_arprot;
wire [3:0]     m01_rsb_arregion;
wire [3:0]     m01_rsb_arqos;
wire           m01_rsb_arvalid;
wire           m01_rsb_arready;
wire [255:0]   m01_rsb_rdata;
wire [1:0]     m01_rsb_rresp;
wire           m01_rsb_rlast;
wire           m01_rsb_rvalid;
wire           m01_rsb_rready;

axi_reg_slice_256 m00_axi_reg_slice_256_inst (
    .aclk(hbm_clk),
    .aresetn(m00_rsb_rstn),

    .s_axi_awaddr(axi_dwidth_converter_0_m_axi_awaddr),
    .s_axi_awlen(axi_dwidth_converter_0_m_axi_awlen),
    .s_axi_awsize(axi_dwidth_converter_0_m_axi_awsize),
    .s_axi_awburst(axi_dwidth_converter_0_m_axi_awburst),
    .s_axi_awlock(axi_dwidth_converter_0_m_axi_awlock),
    .s_axi_awcache(axi_dwidth_converter_0_m_axi_awcache),
    .s_axi_awprot(axi_dwidth_converter_0_m_axi_awprot),
    .s_axi_awregion(axi_dwidth_converter_0_m_axi_awregion),
    .s_axi_awqos(axi_dwidth_converter_0_m_axi_awqos),
    .s_axi_awvalid(axi_dwidth_converter_0_m_axi_awvalid),
    .s_axi_awready(axi_dwidth_converter_0_m_axi_awready),
    .s_axi_wdata(axi_dwidth_converter_0_m_axi_wdata),
    .s_axi_wstrb(axi_dwidth_converter_0_m_axi_wstrb),
    .s_axi_wlast(axi_dwidth_converter_0_m_axi_wlast),
    .s_axi_wvalid(axi_dwidth_converter_0_m_axi_wvalid),
    .s_axi_wready(axi_dwidth_converter_0_m_axi_wready),
    .s_axi_bresp(axi_dwidth_converter_0_m_axi_bresp),
    .s_axi_bvalid(axi_dwidth_converter_0_m_axi_bvalid),
    .s_axi_bready(axi_dwidth_converter_0_m_axi_bready),
    .s_axi_araddr(axi_dwidth_converter_0_m_axi_araddr),
    .s_axi_arlen(axi_dwidth_converter_0_m_axi_arlen),
    .s_axi_arsize(axi_dwidth_converter_0_m_axi_arsize),
    .s_axi_arburst(axi_dwidth_converter_0_m_axi_arburst),
    .s_axi_arlock(axi_dwidth_converter_0_m_axi_arlock),
    .s_axi_arcache(axi_dwidth_converter_0_m_axi_arcache),
    .s_axi_arprot(axi_dwidth_converter_0_m_axi_arprot),
    .s_axi_arregion(axi_dwidth_converter_0_m_axi_arregion),
    .s_axi_arqos(axi_dwidth_converter_0_m_axi_arqos),
    .s_axi_arvalid(axi_dwidth_converter_0_m_axi_arvalid),
    .s_axi_arready(axi_dwidth_converter_0_m_axi_arready),
    .s_axi_rdata(axi_dwidth_converter_0_m_axi_rdata),
    .s_axi_rresp(axi_dwidth_converter_0_m_axi_rresp),
    .s_axi_rlast(axi_dwidth_converter_0_m_axi_rlast),
    .s_axi_rvalid(axi_dwidth_converter_0_m_axi_rvalid),
    .s_axi_rready(axi_dwidth_converter_0_m_axi_rready),

    .m_axi_awaddr(m00_rsb_awaddr),
    .m_axi_awlen(m00_rsb_awlen),
    .m_axi_awsize(m00_rsb_awsize),
    .m_axi_awburst(m00_rsb_awburst),
    .m_axi_awlock(m00_rsb_awlock),
    .m_axi_awcache(m00_rsb_awcache),
    .m_axi_awprot(m00_rsb_awprot),
    .m_axi_awregion(m00_rsb_awregion),
    .m_axi_awqos(m00_rsb_awqos),
    .m_axi_awvalid(m00_rsb_awvalid),
    .m_axi_awready(m00_rsb_awready),
    .m_axi_wdata(m00_rsb_wdata),
    .m_axi_wstrb(m00_rsb_wstrb),
    .m_axi_wlast(m00_rsb_wlast),
    .m_axi_wvalid(m00_rsb_wvalid),
    .m_axi_wready(m00_rsb_wready),
    .m_axi_bresp(m00_rsb_bresp),
    .m_axi_bvalid(m00_rsb_bvalid),
    .m_axi_bready(m00_rsb_bready),
    .m_axi_araddr(m00_rsb_araddr),
    .m_axi_arlen(m00_rsb_arlen),
    .m_axi_arsize(m00_rsb_arsize),
    .m_axi_arburst(m00_rsb_arburst),
    .m_axi_arlock(m00_rsb_arlock),
    .m_axi_arcache(m00_rsb_arcache),
    .m_axi_arprot(m00_rsb_arprot),
    .m_axi_arregion(m00_rsb_arregion),
    .m_axi_arqos(m00_rsb_arqos),
    .m_axi_arvalid(m00_rsb_arvalid),
    .m_axi_arready(m00_rsb_arready),
    .m_axi_rdata(m00_rsb_rdata),
    .m_axi_rresp(m00_rsb_rresp),
    .m_axi_rlast(m00_rsb_rlast),
    .m_axi_rvalid(m00_rsb_rvalid),
    .m_axi_rready(m00_rsb_rready)
);

axi_reg_slice_256 m01_axi_reg_slice_256_inst (
    .aclk(hbm_clk),
    .aresetn(m01_rsb_rstn),

    .s_axi_awaddr(axi_dwidth_converter_1_m_axi_awaddr),
    .s_axi_awlen(axi_dwidth_converter_1_m_axi_awlen),
    .s_axi_awsize(axi_dwidth_converter_1_m_axi_awsize),
    .s_axi_awburst(axi_dwidth_converter_1_m_axi_awburst),
    .s_axi_awlock(axi_dwidth_converter_1_m_axi_awlock),
    .s_axi_awcache(axi_dwidth_converter_1_m_axi_awcache),
    .s_axi_awprot(axi_dwidth_converter_1_m_axi_awprot),
    .s_axi_awregion(axi_dwidth_converter_1_m_axi_awregion),
    .s_axi_awqos(axi_dwidth_converter_1_m_axi_awqos),
    .s_axi_awvalid(axi_dwidth_converter_1_m_axi_awvalid),
    .s_axi_awready(axi_dwidth_converter_1_m_axi_awready),
    .s_axi_wdata(axi_dwidth_converter_1_m_axi_wdata),
    .s_axi_wstrb(axi_dwidth_converter_1_m_axi_wstrb),
    .s_axi_wlast(axi_dwidth_converter_1_m_axi_wlast),
    .s_axi_wvalid(axi_dwidth_converter_1_m_axi_wvalid),
    .s_axi_wready(axi_dwidth_converter_1_m_axi_wready),
    .s_axi_bresp(axi_dwidth_converter_1_m_axi_bresp),
    .s_axi_bvalid(axi_dwidth_converter_1_m_axi_bvalid),
    .s_axi_bready(axi_dwidth_converter_1_m_axi_bready),
    .s_axi_araddr(axi_dwidth_converter_1_m_axi_araddr),
    .s_axi_arlen(axi_dwidth_converter_1_m_axi_arlen),
    .s_axi_arsize(axi_dwidth_converter_1_m_axi_arsize),
    .s_axi_arburst(axi_dwidth_converter_1_m_axi_arburst),
    .s_axi_arlock(axi_dwidth_converter_1_m_axi_arlock),
    .s_axi_arcache(axi_dwidth_converter_1_m_axi_arcache),
    .s_axi_arprot(axi_dwidth_converter_1_m_axi_arprot),
    .s_axi_arregion(axi_dwidth_converter_1_m_axi_arregion),
    .s_axi_arqos(axi_dwidth_converter_1_m_axi_arqos),
    .s_axi_arvalid(axi_dwidth_converter_1_m_axi_arvalid),
    .s_axi_arready(axi_dwidth_converter_1_m_axi_arready),
    .s_axi_rdata(axi_dwidth_converter_1_m_axi_rdata),
    .s_axi_rresp(axi_dwidth_converter_1_m_axi_rresp),
    .s_axi_rlast(axi_dwidth_converter_1_m_axi_rlast),
    .s_axi_rvalid(axi_dwidth_converter_1_m_axi_rvalid),
    .s_axi_rready(axi_dwidth_converter_1_m_axi_rready),

    .m_axi_awaddr(m01_rsb_awaddr),
    .m_axi_awlen(m01_rsb_awlen),
    .m_axi_awsize(m01_rsb_awsize),
    .m_axi_awburst(m01_rsb_awburst),
    .m_axi_awlock(m01_rsb_awlock),
    .m_axi_awcache(m01_rsb_awcache),
    .m_axi_awprot(m01_rsb_awprot),
    .m_axi_awregion(m01_rsb_awregion),
    .m_axi_awqos(m01_rsb_awqos),
    .m_axi_awvalid(m01_rsb_awvalid),
    .m_axi_awready(m01_rsb_awready),
    .m_axi_wdata(m01_rsb_wdata),
    .m_axi_wstrb(m01_rsb_wstrb),
    .m_axi_wlast(m01_rsb_wlast),
    .m_axi_wvalid(m01_rsb_wvalid),
    .m_axi_wready(m01_rsb_wready),
    .m_axi_bresp(m01_rsb_bresp),
    .m_axi_bvalid(m01_rsb_bvalid),
    .m_axi_bready(m01_rsb_bready),
    .m_axi_araddr(m01_rsb_araddr),
    .m_axi_arlen(m01_rsb_arlen),
    .m_axi_arsize(m01_rsb_arsize),
    .m_axi_arburst(m01_rsb_arburst),
    .m_axi_arlock(m01_rsb_arlock),
    .m_axi_arcache(m01_rsb_arcache),
    .m_axi_arprot(m01_rsb_arprot),
    .m_axi_arregion(m01_rsb_arregion),
    .m_axi_arqos(m01_rsb_arqos),
    .m_axi_arvalid(m01_rsb_arvalid),
    .m_axi_arready(m01_rsb_arready),
    .m_axi_rdata(m01_rsb_rdata),
    .m_axi_rresp(m01_rsb_rresp),
    .m_axi_rlast(m01_rsb_rlast),
    .m_axi_rvalid(m01_rsb_rvalid),
    .m_axi_rready(m01_rsb_rready)
);

axi_prot_conv m00_axi_prot_conv_int (
    .aclk(hbm_clk),
    .aresetn(m00_pc_rstn),
    .m_axi_araddr(axi_protocol_convert_0_m_axi_araddr),
    .m_axi_arburst(axi_protocol_convert_0_m_axi_arburst),
    .m_axi_arlen(axi_protocol_convert_0_m_axi_arlen),
    .m_axi_arready(axi_protocol_convert_0_m_axi_arready),
    .m_axi_arsize(axi_protocol_convert_0_m_axi_arsize),
    .m_axi_arvalid(axi_protocol_convert_0_m_axi_arvalid),
    .m_axi_awaddr(axi_protocol_convert_0_m_axi_awaddr),
    .m_axi_awburst(axi_protocol_convert_0_m_axi_awburst),
    .m_axi_awlen(axi_protocol_convert_0_m_axi_awlen),
    .m_axi_awready(axi_protocol_convert_0_m_axi_awready),
    .m_axi_awsize(axi_protocol_convert_0_m_axi_awsize),
    .m_axi_awvalid(axi_protocol_convert_0_m_axi_awvalid),
    .m_axi_bready(axi_protocol_convert_0_m_axi_bready),
    .m_axi_bresp(axi_protocol_convert_0_m_axi_bresp),
    .m_axi_bvalid(axi_protocol_convert_0_m_axi_bvalid),
    .m_axi_rdata(axi_protocol_convert_0_m_axi_rdata),
    .m_axi_rlast(axi_protocol_convert_0_m_axi_rlast),
    .m_axi_rready(axi_protocol_convert_0_m_axi_rready),
    .m_axi_rresp(axi_protocol_convert_0_m_axi_rresp),
    .m_axi_rvalid(axi_protocol_convert_0_m_axi_rvalid),
    .m_axi_wdata(axi_protocol_convert_0_m_axi_wdata),
    .m_axi_wlast(axi_protocol_convert_0_m_axi_wlast),
    .m_axi_wready(axi_protocol_convert_0_m_axi_wready),
    .m_axi_wstrb(axi_protocol_convert_0_m_axi_wstrb),
    .m_axi_wvalid(axi_protocol_convert_0_m_axi_wvalid),
    .s_axi_araddr(m00_rsb_araddr),
    .s_axi_arburst(m00_rsb_arburst),
    .s_axi_arcache(m00_rsb_arcache),
    .s_axi_arlen(m00_rsb_arlen),
    .s_axi_arlock(m00_rsb_arlock),
    .s_axi_arprot(m00_rsb_arprot),
    .s_axi_arqos(m00_rsb_arqos),
    .s_axi_arready(m00_rsb_arready),
    .s_axi_arregion(m00_rsb_arregion),
    .s_axi_arsize(m00_rsb_arsize),
    .s_axi_arvalid(m00_rsb_arvalid),
    .s_axi_awaddr(m00_rsb_awaddr),
    .s_axi_awburst(m00_rsb_awburst),
    .s_axi_awcache(m00_rsb_awcache),
    .s_axi_awlen(m00_rsb_awlen),
    .s_axi_awlock(m00_rsb_awlock),
    .s_axi_awprot(m00_rsb_awprot),
    .s_axi_awqos(m00_rsb_awqos),
    .s_axi_awready(m00_rsb_awready),
    .s_axi_awregion(m00_rsb_awregion),
    .s_axi_awsize(m00_rsb_awsize),
    .s_axi_awvalid(m00_rsb_awvalid),
    .s_axi_bready(m00_rsb_bready),
    .s_axi_bresp(m00_rsb_bresp),
    .s_axi_bvalid(m00_rsb_bvalid),
    .s_axi_rdata(m00_rsb_rdata),
    .s_axi_rlast(m00_rsb_rlast),
    .s_axi_rready(m00_rsb_rready),
    .s_axi_rresp(m00_rsb_rresp),
    .s_axi_rvalid(m00_rsb_rvalid),
    .s_axi_wdata(m00_rsb_wdata),
    .s_axi_wlast(m00_rsb_wlast),
    .s_axi_wready(m00_rsb_wready),
    .s_axi_wstrb(m00_rsb_wstrb),
    .s_axi_wvalid(m00_rsb_wvalid)
);


axi_prot_conv m01_axi_prot_conv_inst(
    .aclk(hbm_clk),
    .aresetn(m01_pc_rstn),

    .m_axi_araddr(axi_protocol_convert_1_m_axi_araddr),
    .m_axi_arburst(axi_protocol_convert_1_m_axi_arburst),
    .m_axi_arlen(axi_protocol_convert_1_m_axi_arlen),
    .m_axi_arready(axi_protocol_convert_1_m_axi_arready),
    .m_axi_arsize(axi_protocol_convert_1_m_axi_arsize),
    .m_axi_arvalid(axi_protocol_convert_1_m_axi_arvalid),
    .m_axi_awaddr(axi_protocol_convert_1_m_axi_awaddr),
    .m_axi_awburst(axi_protocol_convert_1_m_axi_awburst),
    .m_axi_awlen(axi_protocol_convert_1_m_axi_awlen),
    .m_axi_awready(axi_protocol_convert_1_m_axi_awready),
    .m_axi_awsize(axi_protocol_convert_1_m_axi_awsize),
    .m_axi_awvalid(axi_protocol_convert_1_m_axi_awvalid),
    .m_axi_bready(axi_protocol_convert_1_m_axi_bready),
    .m_axi_bresp(axi_protocol_convert_1_m_axi_bresp),
    .m_axi_bvalid(axi_protocol_convert_1_m_axi_bvalid),
    .m_axi_rdata(axi_protocol_convert_1_m_axi_rdata),
    .m_axi_rlast(axi_protocol_convert_1_m_axi_rlast),
    .m_axi_rready(axi_protocol_convert_1_m_axi_rready),
    .m_axi_rresp(axi_protocol_convert_1_m_axi_rresp),
    .m_axi_rvalid(axi_protocol_convert_1_m_axi_rvalid),
    .m_axi_wdata(axi_protocol_convert_1_m_axi_wdata),
    .m_axi_wlast(axi_protocol_convert_1_m_axi_wlast),
    .m_axi_wready(axi_protocol_convert_1_m_axi_wready),
    .m_axi_wstrb(axi_protocol_convert_1_m_axi_wstrb),
    .m_axi_wvalid(axi_protocol_convert_1_m_axi_wvalid),
    .s_axi_araddr(m01_rsb_araddr),
    .s_axi_arburst(m01_rsb_arburst),
    .s_axi_arcache(m01_rsb_arcache),
    .s_axi_arlen(m01_rsb_arlen),
    .s_axi_arlock(m01_rsb_arlock),
    .s_axi_arprot(m01_rsb_arprot),
    .s_axi_arqos(m01_rsb_arqos),
    .s_axi_arready(m01_rsb_arready),
    .s_axi_arregion(m01_rsb_arregion),
    .s_axi_arsize(m01_rsb_arsize),
    .s_axi_arvalid(m01_rsb_arvalid),
    .s_axi_awaddr(m01_rsb_awaddr),
    .s_axi_awburst(m01_rsb_awburst),
    .s_axi_awcache(m01_rsb_awcache),
    .s_axi_awlen(m01_rsb_awlen),
    .s_axi_awlock(m01_rsb_awlock),
    .s_axi_awprot(m01_rsb_awprot),
    .s_axi_awqos(m01_rsb_awqos),
    .s_axi_awready(m01_rsb_awready),
    .s_axi_awregion(m01_rsb_awregion),
    .s_axi_awsize(m01_rsb_awsize),
    .s_axi_awvalid(m01_rsb_awvalid),
    .s_axi_bready(m01_rsb_bready),
    .s_axi_bresp(m01_rsb_bresp),
    .s_axi_bvalid(m01_rsb_bvalid),
    .s_axi_rdata(m01_rsb_rdata),
    .s_axi_rlast(m01_rsb_rlast),
    .s_axi_rready(m01_rsb_rready),
    .s_axi_rresp(m01_rsb_rresp),
    .s_axi_rvalid(m01_rsb_rvalid),
    .s_axi_wdata(m01_rsb_wdata),
    .s_axi_wlast(m01_rsb_wlast),
    .s_axi_wready(m01_rsb_wready),
    .s_axi_wstrb(m01_rsb_wstrb),
    .s_axi_wvalid(m01_rsb_wvalid)
);


// Register slices between each protocol converter and its HBM port. The
// HBM's AXI outputs arrive late -- about 0.6 ns clock-to-out on RVALID, a
// route out of the hard block and 0.2 ns of clock skew -- and at 400 MHz
// that left no room for the protocol and width converters' logic between
// the port and the clock converter's FIFO. Every channel is fully
// registered, ready included, so the port only ever sees a flop.
wire [32:0]    m00_hbm_awaddr;
wire [3:0]     m00_hbm_awlen;
wire [2:0]     m00_hbm_awsize;
wire [1:0]     m00_hbm_awburst;
wire           m00_hbm_awvalid;
wire           m00_hbm_awready;
wire [255:0]   m00_hbm_wdata;
wire [31:0]    m00_hbm_wstrb;
wire           m00_hbm_wlast;
wire           m00_hbm_wvalid;
wire           m00_hbm_wready;
wire [1:0]     m00_hbm_bresp;
wire           m00_hbm_bvalid;
wire           m00_hbm_bready;
wire [32:0]    m00_hbm_araddr;
wire [3:0]     m00_hbm_arlen;
wire [2:0]     m00_hbm_arsize;
wire [1:0]     m00_hbm_arburst;
wire           m00_hbm_arvalid;
wire           m00_hbm_arready;
wire [255:0]   m00_hbm_rdata;
wire [1:0]     m00_hbm_rresp;
wire           m00_hbm_rlast;
wire           m00_hbm_rvalid;
wire           m00_hbm_rready;
wire [32:0]    m01_hbm_awaddr;
wire [3:0]     m01_hbm_awlen;
wire [2:0]     m01_hbm_awsize;
wire [1:0]     m01_hbm_awburst;
wire           m01_hbm_awvalid;
wire           m01_hbm_awready;
wire [255:0]   m01_hbm_wdata;
wire [31:0]    m01_hbm_wstrb;
wire           m01_hbm_wlast;
wire           m01_hbm_wvalid;
wire           m01_hbm_wready;
wire [1:0]     m01_hbm_bresp;
wire           m01_hbm_bvalid;
wire           m01_hbm_bready;
wire [32:0]    m01_hbm_araddr;
wire [3:0]     m01_hbm_arlen;
wire [2:0]     m01_hbm_arsize;
wire [1:0]     m01_hbm_arburst;
wire           m01_hbm_arvalid;
wire           m01_hbm_arready;
wire [255:0]   m01_hbm_rdata;
wire [1:0]     m01_hbm_rresp;
wire           m01_hbm_rlast;
wire           m01_hbm_rvalid;
wire           m01_hbm_rready;

axi_reg_slice_hbm m00_axi_reg_slice_hbm_inst (
    .aclk(hbm_clk),
    .aresetn(m00_rsh_rstn),

    .s_axi_awaddr(axi_protocol_convert_0_m_axi_awaddr[32:0]),
    .s_axi_awlen(axi_protocol_convert_0_m_axi_awlen),
    .s_axi_awsize(axi_protocol_convert_0_m_axi_awsize),
    .s_axi_awburst(axi_protocol_convert_0_m_axi_awburst),
    .s_axi_awlock(2'b00),
    .s_axi_awcache(4'b0011),
    .s_axi_awprot(3'b000),
    .s_axi_awqos(4'b0000),
    .s_axi_awvalid(axi_protocol_convert_0_m_axi_awvalid),
    .s_axi_awready(axi_protocol_convert_0_m_axi_awready),
    .s_axi_wdata(axi_protocol_convert_0_m_axi_wdata),
    .s_axi_wstrb(axi_protocol_convert_0_m_axi_wstrb),
    .s_axi_wlast(axi_protocol_convert_0_m_axi_wlast),
    .s_axi_wvalid(axi_protocol_convert_0_m_axi_wvalid),
    .s_axi_wready(axi_protocol_convert_0_m_axi_wready),
    .s_axi_bresp(axi_protocol_convert_0_m_axi_bresp),
    .s_axi_bvalid(axi_protocol_convert_0_m_axi_bvalid),
    .s_axi_bready(axi_protocol_convert_0_m_axi_bready),
    .s_axi_araddr(axi_protocol_convert_0_m_axi_araddr[32:0]),
    .s_axi_arlen(axi_protocol_convert_0_m_axi_arlen),
    .s_axi_arsize(axi_protocol_convert_0_m_axi_arsize),
    .s_axi_arburst(axi_protocol_convert_0_m_axi_arburst),
    .s_axi_arlock(2'b00),
    .s_axi_arcache(4'b0011),
    .s_axi_arprot(3'b000),
    .s_axi_arqos(4'b0000),
    .s_axi_arvalid(axi_protocol_convert_0_m_axi_arvalid),
    .s_axi_arready(axi_protocol_convert_0_m_axi_arready),
    .s_axi_rdata(axi_protocol_convert_0_m_axi_rdata),
    .s_axi_rresp(axi_protocol_convert_0_m_axi_rresp),
    .s_axi_rlast(axi_protocol_convert_0_m_axi_rlast),
    .s_axi_rvalid(axi_protocol_convert_0_m_axi_rvalid),
    .s_axi_rready(axi_protocol_convert_0_m_axi_rready),

    .m_axi_awaddr(m00_hbm_awaddr),
    .m_axi_awlen(m00_hbm_awlen),
    .m_axi_awsize(m00_hbm_awsize),
    .m_axi_awburst(m00_hbm_awburst),
    .m_axi_awlock(),
    .m_axi_awcache(),
    .m_axi_awprot(),
    .m_axi_awqos(),
    .m_axi_awvalid(m00_hbm_awvalid),
    .m_axi_awready(m00_hbm_awready),
    .m_axi_wdata(m00_hbm_wdata),
    .m_axi_wstrb(m00_hbm_wstrb),
    .m_axi_wlast(m00_hbm_wlast),
    .m_axi_wvalid(m00_hbm_wvalid),
    .m_axi_wready(m00_hbm_wready),
    .m_axi_bresp(m00_hbm_bresp),
    .m_axi_bvalid(m00_hbm_bvalid),
    .m_axi_bready(m00_hbm_bready),
    .m_axi_araddr(m00_hbm_araddr),
    .m_axi_arlen(m00_hbm_arlen),
    .m_axi_arsize(m00_hbm_arsize),
    .m_axi_arburst(m00_hbm_arburst),
    .m_axi_arlock(),
    .m_axi_arcache(),
    .m_axi_arprot(),
    .m_axi_arqos(),
    .m_axi_arvalid(m00_hbm_arvalid),
    .m_axi_arready(m00_hbm_arready),
    .m_axi_rdata(m00_hbm_rdata),
    .m_axi_rresp(m00_hbm_rresp),
    .m_axi_rlast(m00_hbm_rlast),
    .m_axi_rvalid(m00_hbm_rvalid),
    .m_axi_rready(m00_hbm_rready)
);

axi_reg_slice_hbm m01_axi_reg_slice_hbm_inst (
    .aclk(hbm_clk),
    .aresetn(m01_rsh_rstn),

    .s_axi_awaddr(axi_protocol_convert_1_m_axi_awaddr[32:0]),
    .s_axi_awlen(axi_protocol_convert_1_m_axi_awlen),
    .s_axi_awsize(axi_protocol_convert_1_m_axi_awsize),
    .s_axi_awburst(axi_protocol_convert_1_m_axi_awburst),
    .s_axi_awlock(2'b00),
    .s_axi_awcache(4'b0011),
    .s_axi_awprot(3'b000),
    .s_axi_awqos(4'b0000),
    .s_axi_awvalid(axi_protocol_convert_1_m_axi_awvalid),
    .s_axi_awready(axi_protocol_convert_1_m_axi_awready),
    .s_axi_wdata(axi_protocol_convert_1_m_axi_wdata),
    .s_axi_wstrb(axi_protocol_convert_1_m_axi_wstrb),
    .s_axi_wlast(axi_protocol_convert_1_m_axi_wlast),
    .s_axi_wvalid(axi_protocol_convert_1_m_axi_wvalid),
    .s_axi_wready(axi_protocol_convert_1_m_axi_wready),
    .s_axi_bresp(axi_protocol_convert_1_m_axi_bresp),
    .s_axi_bvalid(axi_protocol_convert_1_m_axi_bvalid),
    .s_axi_bready(axi_protocol_convert_1_m_axi_bready),
    .s_axi_araddr(axi_protocol_convert_1_m_axi_araddr[32:0]),
    .s_axi_arlen(axi_protocol_convert_1_m_axi_arlen),
    .s_axi_arsize(axi_protocol_convert_1_m_axi_arsize),
    .s_axi_arburst(axi_protocol_convert_1_m_axi_arburst),
    .s_axi_arlock(2'b00),
    .s_axi_arcache(4'b0011),
    .s_axi_arprot(3'b000),
    .s_axi_arqos(4'b0000),
    .s_axi_arvalid(axi_protocol_convert_1_m_axi_arvalid),
    .s_axi_arready(axi_protocol_convert_1_m_axi_arready),
    .s_axi_rdata(axi_protocol_convert_1_m_axi_rdata),
    .s_axi_rresp(axi_protocol_convert_1_m_axi_rresp),
    .s_axi_rlast(axi_protocol_convert_1_m_axi_rlast),
    .s_axi_rvalid(axi_protocol_convert_1_m_axi_rvalid),
    .s_axi_rready(axi_protocol_convert_1_m_axi_rready),

    .m_axi_awaddr(m01_hbm_awaddr),
    .m_axi_awlen(m01_hbm_awlen),
    .m_axi_awsize(m01_hbm_awsize),
    .m_axi_awburst(m01_hbm_awburst),
    .m_axi_awlock(),
    .m_axi_awcache(),
    .m_axi_awprot(),
    .m_axi_awqos(),
    .m_axi_awvalid(m01_hbm_awvalid),
    .m_axi_awready(m01_hbm_awready),
    .m_axi_wdata(m01_hbm_wdata),
    .m_axi_wstrb(m01_hbm_wstrb),
    .m_axi_wlast(m01_hbm_wlast),
    .m_axi_wvalid(m01_hbm_wvalid),
    .m_axi_wready(m01_hbm_wready),
    .m_axi_bresp(m01_hbm_bresp),
    .m_axi_bvalid(m01_hbm_bvalid),
    .m_axi_bready(m01_hbm_bready),
    .m_axi_araddr(m01_hbm_araddr),
    .m_axi_arlen(m01_hbm_arlen),
    .m_axi_arsize(m01_hbm_arsize),
    .m_axi_arburst(m01_hbm_arburst),
    .m_axi_arlock(),
    .m_axi_arcache(),
    .m_axi_arprot(),
    .m_axi_arqos(),
    .m_axi_arvalid(m01_hbm_arvalid),
    .m_axi_arready(m01_hbm_arready),
    .m_axi_rdata(m01_hbm_rdata),
    .m_axi_rresp(m01_hbm_rresp),
    .m_axi_rlast(m01_hbm_rlast),
    .m_axi_rvalid(m01_hbm_rvalid),
    .m_axi_rready(m01_hbm_rready)
);

// reconfctrl's master on hbm_clk
wire [5:0]   reconf_cc_awid;
wire [32:0]  reconf_cc_awaddr;
wire [7:0]   reconf_cc_awlen;
wire [2:0]   reconf_cc_awsize;
wire [1:0]   reconf_cc_awburst;
wire         reconf_cc_awvalid;
wire         reconf_cc_awready;
wire [255:0] reconf_cc_wdata;
wire [31:0]  reconf_cc_wstrb;
wire         reconf_cc_wlast;
wire         reconf_cc_wvalid;
wire         reconf_cc_wready;
wire [5:0]   reconf_cc_bid;
wire [1:0]   reconf_cc_bresp;
wire         reconf_cc_bvalid;
wire         reconf_cc_bready;
wire [5:0]   reconf_cc_arid;
wire [32:0]  reconf_cc_araddr;
wire [7:0]   reconf_cc_arlen;
wire [2:0]   reconf_cc_arsize;
wire [1:0]   reconf_cc_arburst;
wire         reconf_cc_arvalid;
wire         reconf_cc_arready;
wire [5:0]   reconf_cc_rid;
wire [255:0] reconf_cc_rdata;
wire [1:0]   reconf_cc_rresp;
wire         reconf_cc_rlast;
wire         reconf_cc_rvalid;
wire         reconf_cc_rready;

// Parity is off in the HBM (hbm_0.tcl leaves the MC parity options at their
// false default), reconfctrl drives zeros and ignores what comes back, so the
// parity signals do not cross.
assign reconf_axi_rdata_parity = {32{1'b0}};

axi_clock_conv_reconf reconf_axi_clock_conv_inst (
    .s_axi_aclk(s_axi_clk),
    .s_axi_aresetn(s_axi_rstn),

    .s_axi_awid(reconf_axi_awid),
    .s_axi_awaddr(reconf_axi_awaddr),
    .s_axi_awlen(reconf_axi_awlen),
    .s_axi_awsize(reconf_axi_awsize),
    .s_axi_awburst(reconf_axi_awburst),
    .s_axi_awlock(1'b0),
    .s_axi_awcache({1'b0,1'b0,1'b1,1'b1}),
    .s_axi_awprot({1'b0,1'b0,1'b0}),
    .s_axi_awregion({1'b0,1'b0,1'b0,1'b0}),
    .s_axi_awqos({1'b0,1'b0,1'b0,1'b0}),
    .s_axi_awvalid(reconf_axi_awvalid),
    .s_axi_awready(reconf_axi_awready),
    .s_axi_wdata(reconf_axi_wdata),
    .s_axi_wstrb(reconf_axi_wstrb),
    .s_axi_wlast(reconf_axi_wlast),
    .s_axi_wvalid(reconf_axi_wvalid),
    .s_axi_wready(reconf_axi_wready),
    .s_axi_bid(reconf_axi_bid),
    .s_axi_bresp(reconf_axi_bresp),
    .s_axi_bvalid(reconf_axi_bvalid),
    .s_axi_bready(reconf_axi_bready),
    .s_axi_arid(reconf_axi_arid),
    .s_axi_araddr(reconf_axi_araddr),
    .s_axi_arlen(reconf_axi_arlen),
    .s_axi_arsize(reconf_axi_arsize),
    .s_axi_arburst(reconf_axi_arburst),
    .s_axi_arlock(1'b0),
    .s_axi_arcache({1'b0,1'b0,1'b1,1'b1}),
    .s_axi_arprot({1'b0,1'b0,1'b0}),
    .s_axi_arregion({1'b0,1'b0,1'b0,1'b0}),
    .s_axi_arqos({1'b0,1'b0,1'b0,1'b0}),
    .s_axi_arvalid(reconf_axi_arvalid),
    .s_axi_arready(reconf_axi_arready),
    .s_axi_rid(reconf_axi_rid),
    .s_axi_rdata(reconf_axi_rdata),
    .s_axi_rresp(reconf_axi_rresp),
    .s_axi_rlast(reconf_axi_rlast),
    .s_axi_rvalid(reconf_axi_rvalid),
    .s_axi_rready(reconf_axi_rready),

    .m_axi_aclk(hbm_clk),
    .m_axi_aresetn(reconf_cc_rstn),

    .m_axi_awid(reconf_cc_awid),
    .m_axi_awaddr(reconf_cc_awaddr),
    .m_axi_awlen(reconf_cc_awlen),
    .m_axi_awsize(reconf_cc_awsize),
    .m_axi_awburst(reconf_cc_awburst),
    .m_axi_awlock(),
    .m_axi_awcache(),
    .m_axi_awprot(),
    .m_axi_awregion(),
    .m_axi_awqos(),
    .m_axi_awvalid(reconf_cc_awvalid),
    .m_axi_awready(reconf_cc_awready),
    .m_axi_wdata(reconf_cc_wdata),
    .m_axi_wstrb(reconf_cc_wstrb),
    .m_axi_wlast(reconf_cc_wlast),
    .m_axi_wvalid(reconf_cc_wvalid),
    .m_axi_wready(reconf_cc_wready),
    .m_axi_bid(reconf_cc_bid),
    .m_axi_bresp(reconf_cc_bresp),
    .m_axi_bvalid(reconf_cc_bvalid),
    .m_axi_bready(reconf_cc_bready),
    .m_axi_arid(reconf_cc_arid),
    .m_axi_araddr(reconf_cc_araddr),
    .m_axi_arlen(reconf_cc_arlen),
    .m_axi_arsize(reconf_cc_arsize),
    .m_axi_arburst(reconf_cc_arburst),
    .m_axi_arlock(),
    .m_axi_arcache(),
    .m_axi_arprot(),
    .m_axi_arregion(),
    .m_axi_arqos(),
    .m_axi_arvalid(reconf_cc_arvalid),
    .m_axi_arready(reconf_cc_arready),
    .m_axi_rid(reconf_cc_rid),
    .m_axi_rdata(reconf_cc_rdata),
    .m_axi_rresp(reconf_cc_rresp),
    .m_axi_rlast(reconf_cc_rlast),
    .m_axi_rvalid(reconf_cc_rvalid),
    .m_axi_rready(reconf_cc_rready)
);

hbm_0 hbm_0_inst(
    .APB_0_PCLK(apb_0_clk),
    .APB_0_PRESET_N(apb_rstn),

    .AXI_00_ACLK(hbm_clk),
    .AXI_00_ARESET_N(hbm_port_rstn),

    .AXI_01_ACLK(hbm_clk),
    .AXI_01_ARESET_N(hbm_port_rstn),

    .AXI_02_ACLK(hbm_clk),
    .AXI_02_ARESET_N(hbm_port_rstn),

    .HBM_REF_CLK_0(hbm_ref_clk),

    .AXI_00_ARADDR(m01_hbm_araddr),
    .AXI_00_ARBURST(m01_hbm_arburst),
    .AXI_00_ARID({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
    .AXI_00_ARLEN(m01_hbm_arlen),
    .AXI_00_ARREADY(m01_hbm_arready),
    .AXI_00_ARSIZE(m01_hbm_arsize),
    .AXI_00_ARVALID(m01_hbm_arvalid),
    .AXI_00_AWADDR(m01_hbm_awaddr),
    .AXI_00_AWBURST(m01_hbm_awburst),
    .AXI_00_AWID({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
    .AXI_00_AWLEN(m01_hbm_awlen),
    .AXI_00_AWREADY(m01_hbm_awready),
    .AXI_00_AWSIZE(m01_hbm_awsize),
    .AXI_00_AWVALID(m01_hbm_awvalid),
    .AXI_00_BREADY(m01_hbm_bready),
    .AXI_00_BRESP(m01_hbm_bresp),
    .AXI_00_BVALID(m01_hbm_bvalid),
    .AXI_00_RDATA(m01_hbm_rdata),
    .AXI_00_RLAST(m01_hbm_rlast),
    .AXI_00_RREADY(m01_hbm_rready),
    .AXI_00_RRESP(m01_hbm_rresp),
    .AXI_00_RVALID(m01_hbm_rvalid),
    .AXI_00_WDATA(m01_hbm_wdata),
    .AXI_00_WDATA_PARITY({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
    .AXI_00_WLAST(m01_hbm_wlast),
    .AXI_00_WREADY(m01_hbm_wready),
    .AXI_00_WSTRB(m01_hbm_wstrb),
    .AXI_00_WVALID(m01_hbm_wvalid),

    .AXI_01_ARADDR(reconf_cc_araddr),
    .AXI_01_ARBURST(reconf_cc_arburst),
    .AXI_01_ARID(reconf_cc_arid),
    .AXI_01_ARLEN(reconf_cc_arlen[3:0]),
    .AXI_01_ARREADY(reconf_cc_arready),
    .AXI_01_ARSIZE(reconf_cc_arsize),
    .AXI_01_ARVALID(reconf_cc_arvalid),
    .AXI_01_AWADDR(reconf_cc_awaddr),
    .AXI_01_AWBURST(reconf_cc_awburst),
    .AXI_01_AWID(reconf_cc_awid),
    .AXI_01_AWLEN(reconf_cc_awlen[3:0]),
    .AXI_01_AWREADY(reconf_cc_awready),
    .AXI_01_AWSIZE(reconf_cc_awsize),
    .AXI_01_AWVALID(reconf_cc_awvalid),
    .AXI_01_BID(reconf_cc_bid),
    .AXI_01_BREADY(reconf_cc_bready),
    .AXI_01_BRESP(reconf_cc_bresp),
    .AXI_01_BVALID(reconf_cc_bvalid),
    .AXI_01_RDATA(reconf_cc_rdata),
    .AXI_01_RDATA_PARITY(),
    .AXI_01_RID(reconf_cc_rid),
    .AXI_01_RLAST(reconf_cc_rlast),
    .AXI_01_RREADY(reconf_cc_rready),
    .AXI_01_RRESP(reconf_cc_rresp),
    .AXI_01_RVALID(reconf_cc_rvalid),
    .AXI_01_WDATA(reconf_cc_wdata),
    .AXI_01_WDATA_PARITY({32{1'b0}}),
    .AXI_01_WLAST(reconf_cc_wlast),
    .AXI_01_WREADY(reconf_cc_wready),
    .AXI_01_WSTRB(reconf_cc_wstrb),
    .AXI_01_WVALID(reconf_cc_wvalid),

    .AXI_02_ARADDR(m00_hbm_araddr),
    .AXI_02_ARBURST(m00_hbm_arburst),
    .AXI_02_ARID({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
    .AXI_02_ARLEN(m00_hbm_arlen),
    .AXI_02_ARREADY(m00_hbm_arready),
    .AXI_02_ARSIZE(m00_hbm_arsize),
    .AXI_02_ARVALID(m00_hbm_arvalid),
    .AXI_02_AWADDR(m00_hbm_awaddr),
    .AXI_02_AWBURST(m00_hbm_awburst),
    .AXI_02_AWID({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
    .AXI_02_AWLEN(m00_hbm_awlen),
    .AXI_02_AWREADY(m00_hbm_awready),
    .AXI_02_AWSIZE(m00_hbm_awsize),
    .AXI_02_AWVALID(m00_hbm_awvalid),
    .AXI_02_BREADY(m00_hbm_bready),
    .AXI_02_BRESP(m00_hbm_bresp),
    .AXI_02_BVALID(m00_hbm_bvalid),
    .AXI_02_RDATA(m00_hbm_rdata),
    .AXI_02_RLAST(m00_hbm_rlast),
    .AXI_02_RREADY(m00_hbm_rready),
    .AXI_02_RRESP(m00_hbm_rresp),
    .AXI_02_RVALID(m00_hbm_rvalid),
    .AXI_02_WDATA(m00_hbm_wdata),
    .AXI_02_WDATA_PARITY({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
    .AXI_02_WLAST(m00_hbm_wlast),
    .AXI_02_WREADY(m00_hbm_wready),
    .AXI_02_WSTRB(m00_hbm_wstrb),
    .AXI_02_WVALID(m00_hbm_wvalid),

    .apb_complete_0(),

    .DRAM_0_STAT_CATTRIP(hbm_cattrip_0),
    .DRAM_0_STAT_TEMP()
);

endmodule // frac_hbm

`resetall
