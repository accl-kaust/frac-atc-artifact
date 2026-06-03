`resetall
`timescale 1ns / 1ps
`default_nettype none


module offrac_hbm (
    input wire          hbm_ref_clk,
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
    output wire         m01_axi_rlast

);


wire hbm_cattrip_0;

assign hbm_cattrip = hbm_cattrip_0;

wire hbm_rst = ~hbm_rstn;

wire vio_hbm_start;
wire vio_hbm_clear;
wire [32:0] vio_hbm_base_addr;
wire [15:0] vio_hbm_word_count;
wire [1:0] vio_hbm_pattern_select;

wire [3:0] hbm_dbg_state;
wire hbm_dbg_busy;
wire hbm_dbg_done;
wire hbm_dbg_pass;
wire hbm_dbg_fail;
wire hbm_dbg_bresp_error;
wire hbm_dbg_rresp_error;
wire hbm_dbg_rlast_error;
wire [31:0] hbm_dbg_write_count;
wire [31:0] hbm_dbg_read_count;
wire [32:0] hbm_dbg_current_addr;
wire [32:0] hbm_dbg_first_bad_addr;
wire [255:0] hbm_dbg_expected_data;
wire [255:0] hbm_dbg_observed_data;
wire [31:0] hbm_dbg_expected_low = hbm_dbg_expected_data[31:0];
wire [31:0] hbm_dbg_observed_low = hbm_dbg_observed_data[31:0];

wire [32:0] hbm_dbg_awaddr;
wire [1:0] hbm_dbg_awburst;
wire [5:0] hbm_dbg_awid;
wire [3:0] hbm_dbg_awlen;
wire [2:0] hbm_dbg_awsize;
wire hbm_dbg_awvalid;
wire hbm_dbg_awready;
wire [255:0] hbm_dbg_wdata;
wire [31:0] hbm_dbg_wstrb;
wire [31:0] hbm_dbg_wdata_parity;
wire hbm_dbg_wlast;
wire hbm_dbg_wvalid;
wire hbm_dbg_wready;
wire [5:0] hbm_dbg_bid;
wire [1:0] hbm_dbg_bresp;
wire hbm_dbg_bvalid;
wire hbm_dbg_bready;
wire [32:0] hbm_dbg_araddr;
wire [1:0] hbm_dbg_arburst;
wire [5:0] hbm_dbg_arid;
wire [3:0] hbm_dbg_arlen;
wire [2:0] hbm_dbg_arsize;
wire hbm_dbg_arvalid;
wire hbm_dbg_arready;
wire [5:0] hbm_dbg_rid;
wire [255:0] hbm_dbg_rdata;
wire [31:0] hbm_dbg_rdata_parity;
wire [1:0] hbm_dbg_rresp;
wire hbm_dbg_rlast;
wire hbm_dbg_rvalid;
wire hbm_dbg_rready;

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

axi_dwidth_conv m00_axi_dwidth_conv_inst (
    .s_axi_aclk(hbm_clk),
    .s_axi_aresetn(hbm_rstn),

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

    .s_axi_araddr(m00_axi_araddr),
    .s_axi_arburst({1'b0,1'b1}),
    .s_axi_arcache({1'b0,1'b0,1'b1,1'b1}),
    .s_axi_arlen(m00_axi_arlen),
    .s_axi_arlock(1'b0),
    .s_axi_arprot({1'b0,1'b0,1'b0}),
    .s_axi_arqos({1'b0,1'b0,1'b0,1'b0}),
    .s_axi_arready(m00_axi_arready),
    .s_axi_arregion({1'b0,1'b0,1'b0,1'b0}),
    .s_axi_arsize({1'b1,1'b1,1'b0}),
    .s_axi_arvalid(m00_axi_arvalid),
    .s_axi_awaddr(m00_axi_awaddr),
    .s_axi_awburst({1'b0,1'b1}),
    .s_axi_awcache({1'b0,1'b0,1'b1,1'b1}),
    .s_axi_awlen(m00_axi_awlen),
    .s_axi_awlock(1'b0),
    .s_axi_awprot({1'b0,1'b0,1'b0}),
    .s_axi_awqos({1'b0,1'b0,1'b0,1'b0}),
    .s_axi_awready(m00_axi_awready),
    .s_axi_awregion({1'b0,1'b0,1'b0,1'b0}),
    .s_axi_awsize({1'b1,1'b1,1'b0}),
    .s_axi_awvalid(m00_axi_awvalid),
    .s_axi_bready(m00_axi_bready),
    .s_axi_bvalid(m00_axi_bvalid),
    .s_axi_rdata(m00_axi_rdata),
    .s_axi_rlast(m00_axi_rlast),
    .s_axi_rready(m00_axi_rready),
    .s_axi_rvalid(m00_axi_rvalid),
    .s_axi_wdata(m00_axi_wdata),
    .s_axi_wlast(m00_axi_wlast),
    .s_axi_wready(m00_axi_wready),
    .s_axi_wstrb(m00_axi_wstrb),
    .s_axi_wvalid(m00_axi_wvalid)
);

axi_dwidth_conv m01_axi_dwidth_conv_inst (
    .s_axi_aclk(hbm_clk),
    .s_axi_aresetn(hbm_rstn),

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

    .s_axi_araddr(m01_axi_araddr),
    .s_axi_arburst({1'b0,1'b1}),
    .s_axi_arcache({1'b0,1'b0,1'b1,1'b1}),
    .s_axi_arlen(m01_axi_arlen),
    .s_axi_arlock(1'b0),
    .s_axi_arprot({1'b0,1'b0,1'b0}),
    .s_axi_arqos({1'b0,1'b0,1'b0,1'b0}),
    .s_axi_arready(m01_axi_arready),
    .s_axi_arregion({1'b0,1'b0,1'b0,1'b0}),
    .s_axi_arsize({1'b1,1'b1,1'b0}),
    .s_axi_arvalid(m01_axi_arvalid),
    .s_axi_awaddr(m01_axi_awaddr),
    .s_axi_awburst({1'b0,1'b1}),
    .s_axi_awcache({1'b0,1'b0,1'b1,1'b1}),
    .s_axi_awlen(m01_axi_awlen),
    .s_axi_awlock(1'b0),
    .s_axi_awprot({1'b0,1'b0,1'b0}),
    .s_axi_awqos({1'b0,1'b0,1'b0,1'b0}),
    .s_axi_awready(m01_axi_awready),
    .s_axi_awregion({1'b0,1'b0,1'b0,1'b0}),
    .s_axi_awsize({1'b1,1'b1,1'b0}),
    .s_axi_awvalid(m01_axi_awvalid),
    .s_axi_bready(m01_axi_bready),
    .s_axi_bvalid(m01_axi_bvalid),
    .s_axi_rdata(m01_axi_rdata),
    .s_axi_rlast(m01_axi_rlast),
    .s_axi_rready(m01_axi_rready),
    .s_axi_rvalid(m01_axi_rvalid),
    .s_axi_wdata(m01_axi_wdata),
    .s_axi_wlast(m01_axi_wlast),
    .s_axi_wready(m01_axi_wready),
    .s_axi_wstrb(m01_axi_wstrb),
    .s_axi_wvalid(m01_axi_wvalid)
);

axi_prot_conv m00_axi_prot_conv_int (
    .aclk(hbm_clk),
    .aresetn(hbm_rstn),
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
    .s_axi_araddr(axi_dwidth_converter_0_m_axi_araddr),
    .s_axi_arburst(axi_dwidth_converter_0_m_axi_arburst),
    .s_axi_arcache(axi_dwidth_converter_0_m_axi_arcache),
    .s_axi_arlen(axi_dwidth_converter_0_m_axi_arlen),
    .s_axi_arlock(axi_dwidth_converter_0_m_axi_arlock),
    .s_axi_arprot(axi_dwidth_converter_0_m_axi_arprot),
    .s_axi_arqos(axi_dwidth_converter_0_m_axi_arqos),
    .s_axi_arready(axi_dwidth_converter_0_m_axi_arready),
    .s_axi_arregion(axi_dwidth_converter_0_m_axi_arregion),
    .s_axi_arsize(axi_dwidth_converter_0_m_axi_arsize),
    .s_axi_arvalid(axi_dwidth_converter_0_m_axi_arvalid),
    .s_axi_awaddr(axi_dwidth_converter_0_m_axi_awaddr),
    .s_axi_awburst(axi_dwidth_converter_0_m_axi_awburst),
    .s_axi_awcache(axi_dwidth_converter_0_m_axi_awcache),
    .s_axi_awlen(axi_dwidth_converter_0_m_axi_awlen),
    .s_axi_awlock(axi_dwidth_converter_0_m_axi_awlock),
    .s_axi_awprot(axi_dwidth_converter_0_m_axi_awprot),
    .s_axi_awqos(axi_dwidth_converter_0_m_axi_awqos),
    .s_axi_awready(axi_dwidth_converter_0_m_axi_awready),
    .s_axi_awregion(axi_dwidth_converter_0_m_axi_awregion),
    .s_axi_awsize(axi_dwidth_converter_0_m_axi_awsize),
    .s_axi_awvalid(axi_dwidth_converter_0_m_axi_awvalid),
    .s_axi_bready(axi_dwidth_converter_0_m_axi_bready),
    .s_axi_bresp(axi_dwidth_converter_0_m_axi_bresp),
    .s_axi_bvalid(axi_dwidth_converter_0_m_axi_bvalid),
    .s_axi_rdata(axi_dwidth_converter_0_m_axi_rdata),
    .s_axi_rlast(axi_dwidth_converter_0_m_axi_rlast),
    .s_axi_rready(axi_dwidth_converter_0_m_axi_rready),
    .s_axi_rresp(axi_dwidth_converter_0_m_axi_rresp),
    .s_axi_rvalid(axi_dwidth_converter_0_m_axi_rvalid),
    .s_axi_wdata(axi_dwidth_converter_0_m_axi_wdata),
    .s_axi_wlast(axi_dwidth_converter_0_m_axi_wlast),
    .s_axi_wready(axi_dwidth_converter_0_m_axi_wready),
    .s_axi_wstrb(axi_dwidth_converter_0_m_axi_wstrb),
    .s_axi_wvalid(axi_dwidth_converter_0_m_axi_wvalid)
);


axi_prot_conv m01_axi_prot_conv_inst(
    .aclk(hbm_clk),
    .aresetn(hbm_rstn),

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
    .s_axi_araddr(axi_dwidth_converter_1_m_axi_araddr),
    .s_axi_arburst(axi_dwidth_converter_1_m_axi_arburst),
    .s_axi_arcache(axi_dwidth_converter_1_m_axi_arcache),
    .s_axi_arlen(axi_dwidth_converter_1_m_axi_arlen),
    .s_axi_arlock(axi_dwidth_converter_1_m_axi_arlock),
    .s_axi_arprot(axi_dwidth_converter_1_m_axi_arprot),
    .s_axi_arqos(axi_dwidth_converter_1_m_axi_arqos),
    .s_axi_arready(axi_dwidth_converter_1_m_axi_arready),
    .s_axi_arregion(axi_dwidth_converter_1_m_axi_arregion),
    .s_axi_arsize(axi_dwidth_converter_1_m_axi_arsize),
    .s_axi_arvalid(axi_dwidth_converter_1_m_axi_arvalid),
    .s_axi_awaddr(axi_dwidth_converter_1_m_axi_awaddr),
    .s_axi_awburst(axi_dwidth_converter_1_m_axi_awburst),
    .s_axi_awcache(axi_dwidth_converter_1_m_axi_awcache),
    .s_axi_awlen(axi_dwidth_converter_1_m_axi_awlen),
    .s_axi_awlock(axi_dwidth_converter_1_m_axi_awlock),
    .s_axi_awprot(axi_dwidth_converter_1_m_axi_awprot),
    .s_axi_awqos(axi_dwidth_converter_1_m_axi_awqos),
    .s_axi_awready(axi_dwidth_converter_1_m_axi_awready),
    .s_axi_awregion(axi_dwidth_converter_1_m_axi_awregion),
    .s_axi_awsize(axi_dwidth_converter_1_m_axi_awsize),
    .s_axi_awvalid(axi_dwidth_converter_1_m_axi_awvalid),
    .s_axi_bready(axi_dwidth_converter_1_m_axi_bready),
    .s_axi_bresp(axi_dwidth_converter_1_m_axi_bresp),
    .s_axi_bvalid(axi_dwidth_converter_1_m_axi_bvalid),
    .s_axi_rdata(axi_dwidth_converter_1_m_axi_rdata),
    .s_axi_rlast(axi_dwidth_converter_1_m_axi_rlast),
    .s_axi_rready(axi_dwidth_converter_1_m_axi_rready),
    .s_axi_rresp(axi_dwidth_converter_1_m_axi_rresp),
    .s_axi_rvalid(axi_dwidth_converter_1_m_axi_rvalid),
    .s_axi_wdata(axi_dwidth_converter_1_m_axi_wdata),
    .s_axi_wlast(axi_dwidth_converter_1_m_axi_wlast),
    .s_axi_wready(axi_dwidth_converter_1_m_axi_wready),
    .s_axi_wstrb(axi_dwidth_converter_1_m_axi_wstrb),
    .s_axi_wvalid(axi_dwidth_converter_1_m_axi_wvalid)
);


// ila_11 debg_rst_hbm_apb(
//    .clk(apb_0_clk),
//    .probe0(apb_rstn)
// );


// ila_11 debg_rst_hbm_main(
//    .clk(hbm_clk),
//    .probe0(hbm_rstn)
// );

hbm_debug_axi_master hbm_debug_axi_master_inst (
    .clk(hbm_clk),
    .rst(hbm_rst),
    .start(vio_hbm_start),
    .clear(vio_hbm_clear),
    .base_addr(vio_hbm_base_addr),
    .word_count(vio_hbm_word_count),
    .pattern_select(vio_hbm_pattern_select),
    .state(hbm_dbg_state),
    .busy(hbm_dbg_busy),
    .done(hbm_dbg_done),
    .pass(hbm_dbg_pass),
    .fail(hbm_dbg_fail),
    .bresp_error(hbm_dbg_bresp_error),
    .rresp_error(hbm_dbg_rresp_error),
    .rlast_error(hbm_dbg_rlast_error),
    .write_count(hbm_dbg_write_count),
    .read_count(hbm_dbg_read_count),
    .current_addr(hbm_dbg_current_addr),
    .first_bad_addr(hbm_dbg_first_bad_addr),
    .expected_data(hbm_dbg_expected_data),
    .observed_data(hbm_dbg_observed_data),
    .m_axi_awaddr(hbm_dbg_awaddr),
    .m_axi_awburst(hbm_dbg_awburst),
    .m_axi_awid(hbm_dbg_awid),
    .m_axi_awlen(hbm_dbg_awlen),
    .m_axi_awsize(hbm_dbg_awsize),
    .m_axi_awvalid(hbm_dbg_awvalid),
    .m_axi_awready(hbm_dbg_awready),
    .m_axi_wdata(hbm_dbg_wdata),
    .m_axi_wstrb(hbm_dbg_wstrb),
    .m_axi_wdata_parity(hbm_dbg_wdata_parity),
    .m_axi_wlast(hbm_dbg_wlast),
    .m_axi_wvalid(hbm_dbg_wvalid),
    .m_axi_wready(hbm_dbg_wready),
    .m_axi_bid(hbm_dbg_bid),
    .m_axi_bresp(hbm_dbg_bresp),
    .m_axi_bvalid(hbm_dbg_bvalid),
    .m_axi_bready(hbm_dbg_bready),
    .m_axi_araddr(hbm_dbg_araddr),
    .m_axi_arburst(hbm_dbg_arburst),
    .m_axi_arid(hbm_dbg_arid),
    .m_axi_arlen(hbm_dbg_arlen),
    .m_axi_arsize(hbm_dbg_arsize),
    .m_axi_arvalid(hbm_dbg_arvalid),
    .m_axi_arready(hbm_dbg_arready),
    .m_axi_rid(hbm_dbg_rid),
    .m_axi_rdata(hbm_dbg_rdata),
    .m_axi_rresp(hbm_dbg_rresp),
    .m_axi_rlast(hbm_dbg_rlast),
    .m_axi_rvalid(hbm_dbg_rvalid),
    .m_axi_rready(hbm_dbg_rready)
);

vio_hbm_debug vio_hbm_debug_inst (
    .clk(hbm_clk),
    .probe_in0(hbm_dbg_busy),
    .probe_in1(hbm_dbg_done),
    .probe_in2(hbm_dbg_pass),
    .probe_in3(hbm_dbg_fail),
    .probe_in4(hbm_dbg_state),
    .probe_in5(hbm_dbg_write_count),
    .probe_in6(hbm_dbg_read_count),
    .probe_in7(hbm_dbg_first_bad_addr),
    .probe_in8(hbm_dbg_bresp_error),
    .probe_in9(hbm_dbg_rresp_error),
    .probe_in10(hbm_dbg_rlast_error),
    .probe_in11(hbm_dbg_expected_low),
    .probe_in12(hbm_dbg_observed_low),
    .probe_out0(vio_hbm_start),
    .probe_out1(vio_hbm_clear),
    .probe_out2(vio_hbm_base_addr),
    .probe_out3(vio_hbm_word_count),
    .probe_out4(vio_hbm_pattern_select)
);

ila_hbm_debug ila_hbm_debug_inst (
    .clk(hbm_clk),
    .probe0(hbm_dbg_state),
    .probe1(hbm_dbg_awvalid),
    .probe2(hbm_dbg_awready),
    .probe3(hbm_dbg_wvalid),
    .probe4(hbm_dbg_wready),
    .probe5(hbm_dbg_bvalid),
    .probe6(hbm_dbg_bready),
    .probe7(hbm_dbg_bresp),
    .probe8(hbm_dbg_arvalid),
    .probe9(hbm_dbg_arready),
    .probe10(hbm_dbg_rvalid),
    .probe11(hbm_dbg_rready),
    .probe12(hbm_dbg_rresp),
    .probe13(hbm_dbg_rlast),
    .probe14(hbm_dbg_current_addr),
    .probe15(hbm_dbg_write_count),
    .probe16(hbm_dbg_read_count),
    .probe17(hbm_dbg_expected_data),
    .probe18(hbm_dbg_observed_data),
    .probe19(hbm_dbg_fail),
    .probe20(hbm_dbg_done),
    .probe21(hbm_cattrip),
    .probe22(vio_hbm_start)
);

hbm_0 hbm_0_inst(
    .APB_0_PWDATA(32'd0),
    .APB_0_PADDR(22'd0),
    .APB_0_PCLK(apb_0_clk),
    .APB_0_PENABLE(1'b0),
    .APB_0_PRESET_N(apb_rstn),
    .APB_0_PSEL(1'b0),
    .APB_0_PWRITE(1'b0),

    .AXI_00_ACLK(hbm_clk),
    .AXI_00_ARESET_N(hbm_rstn),

    .AXI_01_ACLK(hbm_clk),
    .AXI_01_ARESET_N(hbm_rstn),

    .AXI_02_ACLK(hbm_clk),
    .AXI_02_ARESET_N(hbm_rstn),

    .HBM_REF_CLK_0(hbm_ref_clk),

    .AXI_00_ARADDR(axi_protocol_convert_1_m_axi_araddr[32:0]),
    .AXI_00_ARBURST(axi_protocol_convert_1_m_axi_arburst),
    .AXI_00_ARID({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
    .AXI_00_ARLEN(axi_protocol_convert_1_m_axi_arlen),
    .AXI_00_ARREADY(axi_protocol_convert_1_m_axi_arready),
    .AXI_00_ARSIZE(axi_protocol_convert_1_m_axi_arsize),
    .AXI_00_ARVALID(axi_protocol_convert_1_m_axi_arvalid),
    .AXI_00_AWADDR(axi_protocol_convert_1_m_axi_awaddr[32:0]),
    .AXI_00_AWBURST(axi_protocol_convert_1_m_axi_awburst),
    .AXI_00_AWID({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
    .AXI_00_AWLEN(axi_protocol_convert_1_m_axi_awlen),
    .AXI_00_AWREADY(axi_protocol_convert_1_m_axi_awready),
    .AXI_00_AWSIZE(axi_protocol_convert_1_m_axi_awsize),
    .AXI_00_AWVALID(axi_protocol_convert_1_m_axi_awvalid),
    .AXI_00_BREADY(axi_protocol_convert_1_m_axi_bready),
    .AXI_00_BRESP(axi_protocol_convert_1_m_axi_bresp),
    .AXI_00_BVALID(axi_protocol_convert_1_m_axi_bvalid),
    .AXI_00_RDATA(axi_protocol_convert_1_m_axi_rdata),
    .AXI_00_RLAST(axi_protocol_convert_1_m_axi_rlast),
    .AXI_00_RREADY(axi_protocol_convert_1_m_axi_rready),
    .AXI_00_RRESP(axi_protocol_convert_1_m_axi_rresp),
    .AXI_00_RVALID(axi_protocol_convert_1_m_axi_rvalid),
    .AXI_00_WDATA(axi_protocol_convert_1_m_axi_wdata),
    .AXI_00_WDATA_PARITY({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
    .AXI_00_WLAST(axi_protocol_convert_1_m_axi_wlast),
    .AXI_00_WREADY(axi_protocol_convert_1_m_axi_wready),
    .AXI_00_WSTRB(axi_protocol_convert_1_m_axi_wstrb),
    .AXI_00_WVALID(axi_protocol_convert_1_m_axi_wvalid),

    .AXI_01_ARADDR(hbm_dbg_araddr),
    .AXI_01_ARBURST(hbm_dbg_arburst),
    .AXI_01_ARID(hbm_dbg_arid),
    .AXI_01_ARLEN(hbm_dbg_arlen),
    .AXI_01_ARREADY(hbm_dbg_arready),
    .AXI_01_ARSIZE(hbm_dbg_arsize),
    .AXI_01_ARVALID(hbm_dbg_arvalid),
    .AXI_01_AWADDR(hbm_dbg_awaddr),
    .AXI_01_AWBURST(hbm_dbg_awburst),
    .AXI_01_AWID(hbm_dbg_awid),
    .AXI_01_AWLEN(hbm_dbg_awlen),
    .AXI_01_AWREADY(hbm_dbg_awready),
    .AXI_01_AWSIZE(hbm_dbg_awsize),
    .AXI_01_AWVALID(hbm_dbg_awvalid),
    .AXI_01_BID(hbm_dbg_bid),
    .AXI_01_BREADY(hbm_dbg_bready),
    .AXI_01_BRESP(hbm_dbg_bresp),
    .AXI_01_BVALID(hbm_dbg_bvalid),
    .AXI_01_RDATA(hbm_dbg_rdata),
    .AXI_01_RDATA_PARITY(hbm_dbg_rdata_parity),
    .AXI_01_RID(hbm_dbg_rid),
    .AXI_01_RLAST(hbm_dbg_rlast),
    .AXI_01_RREADY(hbm_dbg_rready),
    .AXI_01_RRESP(hbm_dbg_rresp),
    .AXI_01_RVALID(hbm_dbg_rvalid),
    .AXI_01_WDATA(hbm_dbg_wdata),
    .AXI_01_WDATA_PARITY(hbm_dbg_wdata_parity),
    .AXI_01_WLAST(hbm_dbg_wlast),
    .AXI_01_WREADY(hbm_dbg_wready),
    .AXI_01_WSTRB(hbm_dbg_wstrb),
    .AXI_01_WVALID(hbm_dbg_wvalid),

    .AXI_02_ARADDR(axi_protocol_convert_0_m_axi_araddr[32:0]),
    .AXI_02_ARBURST(axi_protocol_convert_0_m_axi_arburst),
    .AXI_02_ARID({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
    .AXI_02_ARLEN(axi_protocol_convert_0_m_axi_arlen),
    .AXI_02_ARREADY(axi_protocol_convert_0_m_axi_arready),
    .AXI_02_ARSIZE(axi_protocol_convert_0_m_axi_arsize),
    .AXI_02_ARVALID(axi_protocol_convert_0_m_axi_arvalid),
    .AXI_02_AWADDR(axi_protocol_convert_0_m_axi_awaddr[32:0]),
    .AXI_02_AWBURST(axi_protocol_convert_0_m_axi_awburst),
    .AXI_02_AWID({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
    .AXI_02_AWLEN(axi_protocol_convert_0_m_axi_awlen),
    .AXI_02_AWREADY(axi_protocol_convert_0_m_axi_awready),
    .AXI_02_AWSIZE(axi_protocol_convert_0_m_axi_awsize),
    .AXI_02_AWVALID(axi_protocol_convert_0_m_axi_awvalid),
    .AXI_02_BREADY(axi_protocol_convert_0_m_axi_bready),
    .AXI_02_BRESP(axi_protocol_convert_0_m_axi_bresp),
    .AXI_02_BVALID(axi_protocol_convert_0_m_axi_bvalid),
    .AXI_02_RDATA(axi_protocol_convert_0_m_axi_rdata),
    .AXI_02_RLAST(axi_protocol_convert_0_m_axi_rlast),
    .AXI_02_RREADY(axi_protocol_convert_0_m_axi_rready),
    .AXI_02_RRESP(axi_protocol_convert_0_m_axi_rresp),
    .AXI_02_RVALID(axi_protocol_convert_0_m_axi_rvalid),
    .AXI_02_WDATA(axi_protocol_convert_0_m_axi_wdata),
    .AXI_02_WDATA_PARITY({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
    .AXI_02_WLAST(axi_protocol_convert_0_m_axi_wlast),
    .AXI_02_WREADY(axi_protocol_convert_0_m_axi_wready),
    .AXI_02_WSTRB(axi_protocol_convert_0_m_axi_wstrb),
    .AXI_02_WVALID(axi_protocol_convert_0_m_axi_wvalid),

    .APB_0_PRDATA(),
    .APB_0_PREADY(),
    .APB_0_PSLVERR(),
    .apb_complete_0(),

    .DRAM_0_STAT_CATTRIP(hbm_cattrip_0),
    .DRAM_0_STAT_TEMP()
);

endmodule // offrac_hbm

`resetall
