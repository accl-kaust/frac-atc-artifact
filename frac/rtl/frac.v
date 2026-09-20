`resetall
`timescale 1ns / 1ps
`default_nettype none

module frac (
    input wire        free_run_clk,
    input wire        hbm_ref_clk,
    output wire       hbm_cattrip,
    input wire        qsfp0_refclk_n,
    input wire        qsfp0_refclk_p,
    input wire [3:0]  qsfp0_rx_n,
    input wire [3:0]  qsfp0_rx_p,
    output wire [3:0] qsfp0_tx_n,
    output wire [3:0] qsfp0_tx_p,
    input wire        sys_clk_n,
    input wire        sys_clk_p,
    input wire        sys_rst,
    input wire        sys_rstn
);

wire clk;
wire sys_clk_ibufg;
wire mmcm_clkfb;
wire mmcm_locked;
wire hbm_apb_clk;
wire rstn;
wire rst;
wire hbm_apb_rstn;
wire hbm_apb_rst;

assign rstn = ~rst;
assign hbm_apb_rstn = ~hbm_apb_rst;

wire cmac_axis_rx_tvalid;
wire cmac_axis_rx_tready;
wire cmac_axis_rx_tlast;
wire [63:0] cmac_axis_rx_tkeep;
wire [511:0] cmac_axis_rx_tdata;

wire cmac_axis_tx_tvalid;
wire cmac_axis_tx_tready;
wire cmac_axis_tx_tlast;
wire [63:0] cmac_axis_tx_tkeep;
wire [511:0] cmac_axis_tx_tdata;

wire m_axis_udp_rx_tvalid;
wire  m_axis_udp_rx_tready;
wire  m_axis_udp_rx_tlast;
wire [63:0]  m_axis_udp_rx_tkeep;
wire [511:0]  m_axis_udp_rx_tdata;

wire s_axis_udp_tx_tvalid;
wire s_axis_udp_tx_tready;
wire s_axis_udp_tx_tlast;
wire [63:0] s_axis_udp_tx_tkeep;
wire [511:0] s_axis_udp_tx_tdata;

wire m_axis_udp_rx_meta_tvalid;
wire  m_axis_udp_rx_meta_tready;
wire  m_axis_udp_rx_meta_tlast;
wire [31:0]  m_axis_udp_rx_meta_tkeep;
wire [255:0]  m_axis_udp_rx_meta_tdata;

wire s_axis_udp_tx_meta_tvalid;
wire s_axis_udp_tx_meta_tready;
wire s_axis_udp_tx_meta_tlast;
wire [31:0] s_axis_udp_tx_meta_tkeep;
wire [255:0] s_axis_udp_tx_meta_tdata;

wire s_axis_tcp_listen_port_tvalid;
wire s_axis_tcp_listen_port_tready;
wire s_axis_tcp_listen_port_tlast;
wire [1:0] s_axis_tcp_listen_port_tkeep;
wire [15:0] s_axis_tcp_listen_port_tdata;

wire m_axis_tcp_port_status_tvalid;
wire  m_axis_tcp_port_status_tready;
wire  m_axis_tcp_port_status_tlast;
wire [7:0]  m_axis_tcp_port_status_tdata;

wire s_axis_tcp_open_connection_tvalid;
wire s_axis_tcp_open_connection_tready;
wire s_axis_tcp_open_connection_tlast;
wire [7:0] s_axis_tcp_open_connection_tkeep;
wire [63:0] s_axis_tcp_open_connection_tdata;

wire m_axis_tcp_open_status_tvalid;
wire m_axis_tcp_open_status_tready;
wire m_axis_tcp_open_status_tlast;
wire [15:0] m_axis_tcp_open_status_tkeep;
wire [127:0] m_axis_tcp_open_status_tdata;

wire s_axis_tcp_close_connection_tvalid;
wire s_axis_tcp_close_connection_tready;
wire s_axis_tcp_close_connection_tlast;
wire [1:0] s_axis_tcp_close_connection_tkeep;
wire [15:0] s_axis_tcp_close_connection_tdata;

wire m_axis_tcp_notification_tvalid;
wire  m_axis_tcp_notification_tready;
wire  m_axis_tcp_notification_tlast;
wire [15:0] m_axis_tcp_notification_tkeep;
wire [127:0]  m_axis_tcp_notification_tdata;

wire s_axis_tcp_read_pkg_tvalid;
wire s_axis_tcp_read_pkg_tready;
wire s_axis_tcp_read_pkg_tlast;
wire [3:0] s_axis_tcp_read_pkg_tkeep;
wire [31:0] s_axis_tcp_read_pkg_tdata;

wire m_axis_tcp_rx_meta_tvalid;
wire  m_axis_tcp_rx_meta_tready;
wire  m_axis_tcp_rx_meta_tlast;
wire [1:0] m_axis_tcp_rx_meta_tkeep;
wire [15:0]  m_axis_tcp_rx_meta_tdata;

wire m_axis_tcp_rx_data_tvalid;
wire  m_axis_tcp_rx_data_tready;
wire  m_axis_tcp_rx_data_tlast;
wire [63:0] m_axis_tcp_rx_data_tkeep;
wire [511:0]  m_axis_tcp_rx_data_tdata;

wire s_axis_tcp_tx_meta_tvalid;
wire  s_axis_tcp_tx_meta_tready;
wire  s_axis_tcp_tx_meta_tlast;
wire [3:0] s_axis_tcp_tx_meta_tkeep;
wire [31:0]  s_axis_tcp_tx_meta_tdata;

wire s_axis_tcp_tx_data_tvalid;
wire  s_axis_tcp_tx_data_tready;
wire  s_axis_tcp_tx_data_tlast;
wire [63:0] s_axis_tcp_tx_data_tkeep;
wire [511:0]  s_axis_tcp_tx_data_tdata;

wire m_axis_tcp_tx_status_tvalid;
wire  m_axis_tcp_tx_status_tready;
wire  m_axis_tcp_tx_status_tlast;
wire [7:0] m_axis_tcp_tx_status_tkeep;
wire [63:0]  m_axis_tcp_tx_status_tdata;

wire m_axis_tcp_open_status_wconv_tvalid;
wire m_axis_tcp_open_status_wconv_tready;
wire m_axis_tcp_open_status_wconv_tlast;
wire [3:0] m_axis_tcp_open_status_wconv_tkeep;
wire [31:0] m_axis_tcp_open_status_wconv_tdata;

wire        m00_axi_awvalid;
wire        m00_axi_awready;
wire [63:0] m00_axi_awaddr;
wire [7:0]  m00_axi_awlen;
wire        m00_axi_wvalid;
wire        m00_axi_wready;
wire [511:0] m00_axi_wdata;
wire [63:0]  m00_axi_wstrb;
wire         m00_axi_wlast;
wire         m00_axi_bvalid;
wire         m00_axi_bready;
wire         m00_axi_arvalid;
wire         m00_axi_arready;
wire [63:0]  m00_axi_araddr;
wire [7:0]   m00_axi_arlen;
wire         m00_axi_rvalid;
wire         m00_axi_rready;
wire [511:0] m00_axi_rdata;
wire         m00_axi_rlast;

wire         m01_axi_awvalid;
wire         m01_axi_awready;
wire [63:0]  m01_axi_awaddr;
wire [7:0]   m01_axi_awlen;
wire         m01_axi_wvalid;
wire         m01_axi_wready;
wire [511:0] m01_axi_wdata;
wire [63:0]  m01_axi_wstrb;
wire         m01_axi_wlast;
wire         m01_axi_bvalid;
wire         m01_axi_bready;
wire         m01_axi_arvalid;
wire         m01_axi_arready;
wire [63:0]  m01_axi_araddr;
wire [7:0]   m01_axi_arlen;
wire         m01_axi_rvalid;
wire         m01_axi_rready;
wire [511:0] m01_axi_rdata;
wire         m01_axi_rlast;

wire [32:0]  reconf_axi_awaddr;
wire [1:0]   reconf_axi_awburst;
wire [5:0]   reconf_axi_awid;
wire [7:0]   reconf_axi_awlen;
wire [2:0]   reconf_axi_awsize;
wire         reconf_axi_awvalid;
wire         reconf_axi_awready;
wire [255:0] reconf_axi_wdata;
wire [31:0]  reconf_axi_wstrb;
wire [31:0]  reconf_axi_wdata_parity;
wire         reconf_axi_wlast;
wire         reconf_axi_wvalid;
wire         reconf_axi_wready;
wire [5:0]   reconf_axi_bid;
wire [1:0]   reconf_axi_bresp;
wire         reconf_axi_bvalid;
wire         reconf_axi_bready;
wire [32:0]  reconf_axi_araddr;
wire [1:0]   reconf_axi_arburst;
wire [5:0]   reconf_axi_arid;
wire [7:0]   reconf_axi_arlen;
wire [2:0]   reconf_axi_arsize;
wire         reconf_axi_arvalid;
wire         reconf_axi_arready;
wire [5:0]   reconf_axi_rid;
wire [255:0] reconf_axi_rdata;
wire [31:0]  reconf_axi_rdata_parity;
wire [1:0]   reconf_axi_rresp;
wire         reconf_axi_rlast;
wire         reconf_axi_rvalid;
wire         reconf_axi_rready;

IBUFGDS #(
   .DIFF_TERM("FALSE"),
   .IBUF_LOW_PWR("FALSE")
)
clk_100mhz_0_ibufg_inst (
   .O   (sys_clk_ibufg),
   .I   (sys_clk_p),
   .IB  (sys_clk_n)
);

MMCME4_BASE #(
    .BANDWIDTH("OPTIMIZED"),
    .CLKOUT0_DIVIDE_F(6),
    .CLKOUT0_DUTY_CYCLE(0.5),
    .CLKOUT0_PHASE(0),
    .CLKOUT1_DIVIDE(24),
    .CLKOUT1_DUTY_CYCLE(0.5),
    .CLKOUT1_PHASE(0),
    .CLKOUT2_DIVIDE(1),
    .CLKOUT2_DUTY_CYCLE(0.5),
    .CLKOUT2_PHASE(0),
    .CLKOUT3_DIVIDE(1),
    .CLKOUT3_DUTY_CYCLE(0.5),
    .CLKOUT3_PHASE(0),
    .CLKOUT4_DIVIDE(1),
    .CLKOUT4_DUTY_CYCLE(0.5),
    .CLKOUT4_PHASE(0),
    .CLKOUT5_DIVIDE(1),
    .CLKOUT5_DUTY_CYCLE(0.5),
    .CLKOUT5_PHASE(0),
    .CLKOUT6_DIVIDE(1),
    .CLKOUT6_DUTY_CYCLE(0.5),
    .CLKOUT6_PHASE(0),
    .CLKFBOUT_MULT_F(12),
    .CLKFBOUT_PHASE(0),
    .DIVCLK_DIVIDE(1),
    .REF_JITTER1(0.010),
    .CLKIN1_PERIOD(10.000),
    .STARTUP_WAIT("FALSE"),
    .CLKOUT4_CASCADE("FALSE")
)
main_clk_mmcm_inst (
    .CLKIN1(sys_clk_ibufg),
    .CLKFBIN(mmcm_clkfb),
    .RST(sys_rst),
    .PWRDWN(1'b0),
    .CLKOUT0(clk),
    .CLKOUT0B(),
    .CLKOUT1(hbm_apb_clk),
    .CLKOUT1B(),
    .CLKOUT2(),
    .CLKOUT2B(),
    .CLKOUT3(),
    .CLKOUT3B(),
    .CLKOUT4(),
    .CLKOUT5(),
    .CLKOUT6(),
    .CLKFBOUT(mmcm_clkfb),
    .CLKFBOUTB(),
    .LOCKED(mmcm_locked)
);

// clk_wiz_0 clk_wiz_0_inst (
//     .clk_in1_n(sys_clk_n),
//     .clk_in1_p(sys_clk_p),
//     .clk_out1(clk),
//     .clk_out2(hbm_apb_clk),
//     .locked(mmcm_locked),
//     .reset(sys_rst)
// );

sync_reset #(
    .N(4)
)
sync_reset_sysclk_inst (
    .clk(clk),
    .rst(~mmcm_locked),
    .out(rst)
);


sync_reset #(
    .N(4)
)
sync_reset_hbmapb_inst (
    .clk(hbm_apb_clk),
    .rst(~mmcm_locked),
    .out(hbm_apb_rst)
);

cmac_krnl #(
    .C_S_AXI_CONTROL_ADDR_WIDTH(12),
    .C_S_AXI_CONTROL_DATA_WIDTH(32),
    .C_AXIS_NET_RX_TDATA_WIDTH(512),
    .C_AXIS_NET_TX_TDATA_WIDTH(512)
) cmac_krnl_inst (
    .ap_clk(clk),
    .ap_rst_n(rstn),
    .axis_net_rx_tvalid(cmac_axis_rx_tvalid),
    .axis_net_rx_tready(cmac_axis_rx_tready),
    .axis_net_rx_tdata(cmac_axis_rx_tdata),
    .axis_net_rx_tkeep(cmac_axis_rx_tkeep),
    .axis_net_rx_tlast(cmac_axis_rx_tlast),
    .axis_net_tx_tvalid(cmac_axis_tx_tvalid),
    .axis_net_tx_tready(cmac_axis_tx_tready),
    .axis_net_tx_tdata(cmac_axis_tx_tdata),
    .axis_net_tx_tkeep(cmac_axis_tx_tkeep),
    .axis_net_tx_tlast(cmac_axis_tx_tlast),
    .clk_gt_freerun(free_run_clk),
    .gt_rxp_in(qsfp0_rx_p),
    .gt_rxn_in(qsfp0_rx_n),
    .gt_txp_out(qsfp0_tx_p),
    .gt_txn_out(qsfp0_tx_n),
    .gt_refclk0_p(qsfp0_refclk_p),
    .gt_refclk0_n(qsfp0_refclk_n)
);

network_krnl #(
    .C_S_AXI_CONTROL_ADDR_WIDTH(12),
    .C_S_AXI_CONTROL_DATA_WIDTH(32),
    .C_M00_AXI_ADDR_WIDTH(64),
    .C_M00_AXI_DATA_WIDTH(512),
    .C_M01_AXI_ADDR_WIDTH(64),
    .C_M01_AXI_DATA_WIDTH(512),
    .C_M_AXIS_UDP_RX_TDATA_WIDTH(512),
    .C_S_AXIS_UDP_TX_TDATA_WIDTH(512),
    .C_M_AXIS_UDP_RX_META_TDATA_WIDTH(256),
    .C_S_AXIS_UDP_TX_META_TDATA_WIDTH(256),
    .C_S_AXIS_TCP_LISTEN_PORT_TDATA_WIDTH(16),
    .C_M_AXIS_TCP_PORT_STATUS_TDATA_WIDTH(8),
    .C_S_AXIS_TCP_OPEN_CONNECTION_TDATA_WIDTH(64),
    .C_M_AXIS_TCP_OPEN_STATUS_TDATA_WIDTH(128),
    .C_S_AXIS_TCP_CLOSE_CONNECTION_TDATA_WIDTH(16),
    .C_M_AXIS_TCP_NOTIFICATION_TDATA_WIDTH(128),
    .C_S_AXIS_TCP_READ_PKG_TDATA_WIDTH(32),
    .C_M_AXIS_TCP_RX_META_TDATA_WIDTH(16),
    .C_M_AXIS_TCP_RX_DATA_TDATA_WIDTH(512),
    .C_S_AXIS_TCP_TX_META_TDATA_WIDTH(32),
    .C_S_AXIS_TCP_TX_DATA_TDATA_WIDTH(512),
    .C_M_AXIS_TCP_TX_STATUS_TDATA_WIDTH(64),
    .C_AXIS_NET_TX_TDATA_WIDTH(512),
    .C_AXIS_NET_RX_TDATA_WIDTH(512)
) network_krnl_inst (
    .ap_clk(clk),
    .ap_rst_n(rstn),
    .m00_axi_awvalid(m00_axi_awvalid),
    .m00_axi_awready(m00_axi_awready),
    .m00_axi_awaddr(m00_axi_awaddr),
    .m00_axi_awlen(m00_axi_awlen),
    .m00_axi_wvalid(m00_axi_wvalid),
    .m00_axi_wready(m00_axi_wready),
    .m00_axi_wdata(m00_axi_wdata),
    .m00_axi_wstrb(m00_axi_wstrb),
    .m00_axi_wlast(m00_axi_wlast),
    .m00_axi_bvalid(m00_axi_bvalid),
    .m00_axi_bready(m00_axi_bready),
    .m00_axi_arvalid(m00_axi_arvalid),
    .m00_axi_arready(m00_axi_arready),
    .m00_axi_araddr(m00_axi_araddr),
    .m00_axi_arlen(m00_axi_arlen),
    .m00_axi_rvalid(m00_axi_rvalid),
    .m00_axi_rready(m00_axi_rready),
    .m00_axi_rdata(m00_axi_rdata),
    .m00_axi_rlast(m00_axi_rlast),
    .m01_axi_awvalid(m01_axi_awvalid),
    .m01_axi_awready(m01_axi_awready),
    .m01_axi_awaddr(m01_axi_awaddr),
    .m01_axi_awlen(m01_axi_awlen),
    .m01_axi_wvalid(m01_axi_wvalid),
    .m01_axi_wready(m01_axi_wready),
    .m01_axi_wdata(m01_axi_wdata),
    .m01_axi_wstrb(m01_axi_wstrb),
    .m01_axi_wlast(m01_axi_wlast),
    .m01_axi_bvalid(m01_axi_bvalid),
    .m01_axi_bready(m01_axi_bready),
    .m01_axi_arvalid(m01_axi_arvalid),
    .m01_axi_arready(m01_axi_arready),
    .m01_axi_araddr(m01_axi_araddr),
    .m01_axi_arlen(m01_axi_arlen),
    .m01_axi_rvalid(m01_axi_rvalid),
    .m01_axi_rready(m01_axi_rready),
    .m01_axi_rdata(m01_axi_rdata),
    .m01_axi_rlast(m01_axi_rlast),
    .m_axis_udp_rx_tvalid(m_axis_udp_rx_tvalid),
    .m_axis_udp_rx_tready(m_axis_udp_rx_tready),
    .m_axis_udp_rx_tdata(m_axis_udp_rx_tdata),
    .m_axis_udp_rx_tkeep(m_axis_udp_rx_tkeep),
    .m_axis_udp_rx_tlast(m_axis_udp_rx_tlast),
    .s_axis_udp_tx_tvalid(s_axis_udp_tx_tvalid),
    .s_axis_udp_tx_tready(s_axis_udp_tx_tready),
    .s_axis_udp_tx_tdata(s_axis_udp_tx_tdata),
    .s_axis_udp_tx_tkeep(s_axis_udp_tx_tkeep),
    .s_axis_udp_tx_tlast(s_axis_udp_tx_tlast),
    .m_axis_udp_rx_meta_tvalid(m_axis_udp_rx_meta_tvalid),
    .m_axis_udp_rx_meta_tready(m_axis_udp_rx_meta_tready),
    .m_axis_udp_rx_meta_tdata(m_axis_udp_rx_meta_tdata),
    .m_axis_udp_rx_meta_tkeep(m_axis_udp_rx_meta_tkeep),
    .m_axis_udp_rx_meta_tlast(m_axis_udp_rx_meta_tlast),
    .s_axis_udp_tx_meta_tvalid(s_axis_udp_tx_meta_tvalid),
    .s_axis_udp_tx_meta_tready(s_axis_udp_tx_meta_tready),
    .s_axis_udp_tx_meta_tdata(s_axis_udp_tx_meta_tdata),
    .s_axis_udp_tx_meta_tkeep(s_axis_udp_tx_meta_tkeep),
    .s_axis_udp_tx_meta_tlast(s_axis_udp_tx_meta_tlast),
    .s_axis_tcp_listen_port_tvalid(s_axis_tcp_listen_port_tvalid),
    .s_axis_tcp_listen_port_tready(s_axis_tcp_listen_port_tready),
    .s_axis_tcp_listen_port_tdata(s_axis_tcp_listen_port_tdata),
    .s_axis_tcp_listen_port_tkeep(s_axis_tcp_listen_port_tkeep),
    .s_axis_tcp_listen_port_tlast(s_axis_tcp_listen_port_tlast),
    .m_axis_tcp_port_status_tvalid(m_axis_tcp_port_status_tvalid),
    .m_axis_tcp_port_status_tready(m_axis_tcp_port_status_tready),
    .m_axis_tcp_port_status_tdata(m_axis_tcp_port_status_tdata),
    .m_axis_tcp_port_status_tlast(m_axis_tcp_port_status_tlast),
    .s_axis_tcp_open_connection_tvalid(s_axis_tcp_open_connection_tvalid),
    .s_axis_tcp_open_connection_tready(s_axis_tcp_open_connection_tready),
    .s_axis_tcp_open_connection_tdata(s_axis_tcp_open_connection_tdata),
    .s_axis_tcp_open_connection_tkeep(s_axis_tcp_open_connection_tkeep),
    .s_axis_tcp_open_connection_tlast(s_axis_tcp_open_connection_tlast),
    .m_axis_tcp_open_status_tvalid(m_axis_tcp_open_status_tvalid),
    .m_axis_tcp_open_status_tready(m_axis_tcp_open_status_tready),
    .m_axis_tcp_open_status_tdata(m_axis_tcp_open_status_tdata),
    .m_axis_tcp_open_status_tkeep(m_axis_tcp_open_status_tkeep),
    .m_axis_tcp_open_status_tlast(m_axis_tcp_open_status_tlast),
    .s_axis_tcp_close_connection_tvalid(s_axis_tcp_close_connection_tvalid),
    .s_axis_tcp_close_connection_tready(s_axis_tcp_close_connection_tready),
    .s_axis_tcp_close_connection_tdata(s_axis_tcp_close_connection_tdata),
    .s_axis_tcp_close_connection_tkeep(s_axis_tcp_close_connection_tkeep),
    .s_axis_tcp_close_connection_tlast(s_axis_tcp_close_connection_tlast),
    .m_axis_tcp_notification_tvalid(m_axis_tcp_notification_tvalid),
    .m_axis_tcp_notification_tready(m_axis_tcp_notification_tready),
    .m_axis_tcp_notification_tdata(m_axis_tcp_notification_tdata),
    .m_axis_tcp_notification_tkeep(m_axis_tcp_notification_tkeep),
    .m_axis_tcp_notification_tlast(m_axis_tcp_notification_tlast),
    .s_axis_tcp_read_pkg_tvalid(s_axis_tcp_read_pkg_tvalid),
    .s_axis_tcp_read_pkg_tready(s_axis_tcp_read_pkg_tready),
    .s_axis_tcp_read_pkg_tdata(s_axis_tcp_read_pkg_tdata),
    .s_axis_tcp_read_pkg_tkeep(s_axis_tcp_read_pkg_tkeep),
    .s_axis_tcp_read_pkg_tlast(s_axis_tcp_read_pkg_tlast),
    .m_axis_tcp_rx_meta_tvalid(m_axis_tcp_rx_meta_tvalid),
    .m_axis_tcp_rx_meta_tready(m_axis_tcp_rx_meta_tready),
    .m_axis_tcp_rx_meta_tdata(m_axis_tcp_rx_meta_tdata),
    .m_axis_tcp_rx_meta_tkeep(m_axis_tcp_rx_meta_tkeep),
    .m_axis_tcp_rx_meta_tlast(m_axis_tcp_rx_meta_tlast),
    .m_axis_tcp_rx_data_tvalid(m_axis_tcp_rx_data_tvalid),
    .m_axis_tcp_rx_data_tready(m_axis_tcp_rx_data_tready),
    .m_axis_tcp_rx_data_tdata(m_axis_tcp_rx_data_tdata),
    .m_axis_tcp_rx_data_tkeep(m_axis_tcp_rx_data_tkeep),
    .m_axis_tcp_rx_data_tlast(m_axis_tcp_rx_data_tlast),
    .s_axis_tcp_tx_meta_tvalid(s_axis_tcp_tx_meta_tvalid),
    .s_axis_tcp_tx_meta_tready(s_axis_tcp_tx_meta_tready),
    .s_axis_tcp_tx_meta_tdata(s_axis_tcp_tx_meta_tdata),
    .s_axis_tcp_tx_meta_tkeep(s_axis_tcp_tx_meta_tkeep),
    .s_axis_tcp_tx_meta_tlast(s_axis_tcp_tx_meta_tlast),
    .s_axis_tcp_tx_data_tvalid(s_axis_tcp_tx_data_tvalid),
    .s_axis_tcp_tx_data_tready(s_axis_tcp_tx_data_tready),
    .s_axis_tcp_tx_data_tdata(s_axis_tcp_tx_data_tdata),
    .s_axis_tcp_tx_data_tkeep(s_axis_tcp_tx_data_tkeep),
    .s_axis_tcp_tx_data_tlast(s_axis_tcp_tx_data_tlast),
    .m_axis_tcp_tx_status_tvalid(m_axis_tcp_tx_status_tvalid),
    .m_axis_tcp_tx_status_tready(m_axis_tcp_tx_status_tready),
    .m_axis_tcp_tx_status_tdata(m_axis_tcp_tx_status_tdata),
    .m_axis_tcp_tx_status_tkeep(m_axis_tcp_tx_status_tkeep),
    .m_axis_tcp_tx_status_tlast(m_axis_tcp_tx_status_tlast),
    .axis_net_tx_tvalid(cmac_axis_tx_tvalid),
    .axis_net_tx_tready(cmac_axis_tx_tready),
    .axis_net_tx_tdata(cmac_axis_tx_tdata),
    .axis_net_tx_tkeep(cmac_axis_tx_tkeep),
    .axis_net_tx_tlast(cmac_axis_tx_tlast),
    .axis_net_rx_tvalid(cmac_axis_rx_tvalid),
    .axis_net_rx_tready(cmac_axis_rx_tready),
    .axis_net_rx_tdata(cmac_axis_rx_tdata),
    .axis_net_rx_tkeep(cmac_axis_rx_tkeep),
    .axis_net_rx_tlast(cmac_axis_rx_tlast),
    .s_axi_control_awvalid(),
    .s_axi_control_awready(),
    .s_axi_control_awaddr(),
    .s_axi_control_wvalid(),
    .s_axi_control_wready(),
    .s_axi_control_wdata(),
    .s_axi_control_wstrb(),
    .s_axi_control_arvalid(),
    .s_axi_control_arready(),
    .s_axi_control_araddr(),
    .s_axi_control_rvalid(),
    .s_axi_control_rready(),
    .s_axi_control_rdata(),
    .s_axi_control_rresp(),
    .s_axi_control_bvalid(),
    .s_axi_control_bready(),
    .s_axi_control_bresp(),
    .interrupt()
);

user_krnl #(
    .C_S_AXI_CONTROL_ADDR_WIDTH(12),
    .C_S_AXI_CONTROL_DATA_WIDTH(32),
    .C_M00_AXI_ADDR_WIDTH(64),
    .C_M00_AXI_DATA_WIDTH(512),
    .C_M01_AXI_ADDR_WIDTH(64),
    .C_M01_AXI_DATA_WIDTH(512),
    .C_S_AXIS_UDP_RX_TDATA_WIDTH(512),
    .C_M_AXIS_UDP_TX_TDATA_WIDTH(512),
    .C_S_AXIS_UDP_RX_META_TDATA_WIDTH(256),
    .C_M_AXIS_UDP_TX_META_TDATA_WIDTH(256),
    .C_M_AXIS_TCP_LISTEN_PORT_TDATA_WIDTH(16),
    .C_S_AXIS_TCP_PORT_STATUS_TDATA_WIDTH(8),
    .C_M_AXIS_TCP_OPEN_CONNECTION_TDATA_WIDTH(64),
    .C_S_AXIS_TCP_OPEN_STATUS_TDATA_WIDTH(32),
    .C_M_AXIS_TCP_CLOSE_CONNECTION_TDATA_WIDTH(16),
    .C_S_AXIS_TCP_NOTIFICATION_TDATA_WIDTH(128),
    .C_M_AXIS_TCP_READ_PKG_TDATA_WIDTH(32),
    .C_S_AXIS_TCP_RX_META_TDATA_WIDTH(16),
    .C_S_AXIS_TCP_RX_DATA_TDATA_WIDTH(512),
    .C_M_AXIS_TCP_TX_META_TDATA_WIDTH(32),
    .C_M_AXIS_TCP_TX_DATA_TDATA_WIDTH(512),
    .C_S_AXIS_TCP_TX_STATUS_TDATA_WIDTH(64)
) user_krnl_inst (
    .ap_clk(clk),
    .ap_rst_n(rstn),
    .s_axis_udp_rx_tvalid(m_axis_udp_rx_tvalid),
    .s_axis_udp_rx_tready(m_axis_udp_rx_tready),
    .s_axis_udp_rx_tdata(m_axis_udp_rx_tdata),
    .s_axis_udp_rx_tkeep(m_axis_udp_rx_tkeep),
    .s_axis_udp_rx_tlast(m_axis_udp_rx_tlast),
    .m_axis_udp_tx_tvalid(s_axis_udp_tx_tvalid),
    .m_axis_udp_tx_tready(s_axis_udp_tx_tready),
    .m_axis_udp_tx_tdata(s_axis_udp_tx_tdata),
    .m_axis_udp_tx_tkeep(s_axis_udp_tx_tkeep),
    .m_axis_udp_tx_tlast(s_axis_udp_tx_tlast),
    .s_axis_udp_rx_meta_tvalid(m_axis_udp_rx_meta_tvalid),
    .s_axis_udp_rx_meta_tready(m_axis_udp_rx_meta_tready),
    .s_axis_udp_rx_meta_tdata(m_axis_udp_rx_meta_tdata),
    .s_axis_udp_rx_meta_tkeep(m_axis_udp_rx_meta_tkeep),
    .s_axis_udp_rx_meta_tlast(m_axis_udp_rx_meta_tlast),
    .m_axis_udp_tx_meta_tvalid(s_axis_udp_tx_meta_tvalid),
    .m_axis_udp_tx_meta_tready(s_axis_udp_tx_meta_tready),
    .m_axis_udp_tx_meta_tdata(s_axis_udp_tx_meta_tdata),
    .m_axis_udp_tx_meta_tkeep(s_axis_udp_tx_meta_tkeep),
    .m_axis_udp_tx_meta_tlast(s_axis_udp_tx_meta_tlast),
    .m_axis_tcp_listen_port_tvalid(s_axis_tcp_listen_port_tvalid),
    .m_axis_tcp_listen_port_tready(s_axis_tcp_listen_port_tready),
    .m_axis_tcp_listen_port_tdata(s_axis_tcp_listen_port_tdata),
    .m_axis_tcp_listen_port_tkeep(s_axis_tcp_listen_port_tkeep),
    .m_axis_tcp_listen_port_tlast(s_axis_tcp_listen_port_tlast),
    .s_axis_tcp_port_status_tvalid(m_axis_tcp_port_status_tvalid),
    .s_axis_tcp_port_status_tready(m_axis_tcp_port_status_tready),
    .s_axis_tcp_port_status_tdata(m_axis_tcp_port_status_tdata),
    .s_axis_tcp_port_status_tlast(m_axis_tcp_port_status_tlast),
    .m_axis_tcp_open_connection_tvalid(s_axis_tcp_open_connection_tvalid),
    .m_axis_tcp_open_connection_tready(s_axis_tcp_open_connection_tready),
    .m_axis_tcp_open_connection_tdata(s_axis_tcp_open_connection_tdata),
    .m_axis_tcp_open_connection_tkeep(s_axis_tcp_open_connection_tkeep),
    .m_axis_tcp_open_connection_tlast(s_axis_tcp_open_connection_tlast),
    .s_axis_tcp_open_status_tvalid(m_axis_tcp_open_status_wconv_tvalid),
    .s_axis_tcp_open_status_tready(m_axis_tcp_open_status_wconv_tready),
    .s_axis_tcp_open_status_tdata(m_axis_tcp_open_status_wconv_tdata),
    .s_axis_tcp_open_status_tkeep(m_axis_tcp_open_status_wconv_tkeep),
    .s_axis_tcp_open_status_tlast(m_axis_tcp_open_status_wconv_tlast),
    .m_axis_tcp_close_connection_tvalid(s_axis_tcp_close_connection_tvalid),
    .m_axis_tcp_close_connection_tready(s_axis_tcp_close_connection_tready),
    .m_axis_tcp_close_connection_tdata(s_axis_tcp_close_connection_tdata),
    .m_axis_tcp_close_connection_tkeep(s_axis_tcp_close_connection_tkeep),
    .m_axis_tcp_close_connection_tlast(s_axis_tcp_close_connection_tlast),
    .s_axis_tcp_notification_tvalid(m_axis_tcp_notification_tvalid),
    .s_axis_tcp_notification_tready(m_axis_tcp_notification_tready),
    .s_axis_tcp_notification_tdata(m_axis_tcp_notification_tdata),
    .s_axis_tcp_notification_tkeep(m_axis_tcp_notification_tkeep),
    .s_axis_tcp_notification_tlast(m_axis_tcp_notification_tlast),
    .m_axis_tcp_read_pkg_tvalid(s_axis_tcp_read_pkg_tvalid),
    .m_axis_tcp_read_pkg_tready(s_axis_tcp_read_pkg_tready),
    .m_axis_tcp_read_pkg_tdata(s_axis_tcp_read_pkg_tdata),
    .m_axis_tcp_read_pkg_tkeep(s_axis_tcp_read_pkg_tkeep),
    .m_axis_tcp_read_pkg_tlast(s_axis_tcp_read_pkg_tlast),
    .s_axis_tcp_rx_meta_tvalid(m_axis_tcp_rx_meta_tvalid),
    .s_axis_tcp_rx_meta_tready(m_axis_tcp_rx_meta_tready),
    .s_axis_tcp_rx_meta_tdata(m_axis_tcp_rx_meta_tdata),
    .s_axis_tcp_rx_meta_tkeep(m_axis_tcp_rx_meta_tkeep),
    .s_axis_tcp_rx_meta_tlast(m_axis_tcp_rx_meta_tlast),
    .s_axis_tcp_rx_data_tvalid(m_axis_tcp_rx_data_tvalid),
    .s_axis_tcp_rx_data_tready(m_axis_tcp_rx_data_tready),
    .s_axis_tcp_rx_data_tdata(m_axis_tcp_rx_data_tdata),
    .s_axis_tcp_rx_data_tkeep(m_axis_tcp_rx_data_tkeep),
    .s_axis_tcp_rx_data_tlast(m_axis_tcp_rx_data_tlast),
    .m_axis_tcp_tx_meta_tvalid(s_axis_tcp_tx_meta_tvalid),
    .m_axis_tcp_tx_meta_tready(s_axis_tcp_tx_meta_tready),
    .m_axis_tcp_tx_meta_tdata(s_axis_tcp_tx_meta_tdata),
    .m_axis_tcp_tx_meta_tkeep(s_axis_tcp_tx_meta_tkeep),
    .m_axis_tcp_tx_meta_tlast(s_axis_tcp_tx_meta_tlast),
    .m_axis_tcp_tx_data_tvalid(s_axis_tcp_tx_data_tvalid),
    .m_axis_tcp_tx_data_tready(s_axis_tcp_tx_data_tready),
    .m_axis_tcp_tx_data_tdata(s_axis_tcp_tx_data_tdata),
    .m_axis_tcp_tx_data_tkeep(s_axis_tcp_tx_data_tkeep),
    .m_axis_tcp_tx_data_tlast(s_axis_tcp_tx_data_tlast),
    .s_axis_tcp_tx_status_tvalid(m_axis_tcp_tx_status_tvalid),
    .s_axis_tcp_tx_status_tready(m_axis_tcp_tx_status_tready),
    .s_axis_tcp_tx_status_tdata(m_axis_tcp_tx_status_tdata),
    .s_axis_tcp_tx_status_tkeep(m_axis_tcp_tx_status_tkeep),
    .s_axis_tcp_tx_status_tlast(m_axis_tcp_tx_status_tlast),
    .m_axi_reconf_awaddr(reconf_axi_awaddr),
    .m_axi_reconf_awburst(reconf_axi_awburst),
    .m_axi_reconf_awid(reconf_axi_awid),
    .m_axi_reconf_awlen(reconf_axi_awlen),
    .m_axi_reconf_awsize(reconf_axi_awsize),
    .m_axi_reconf_awvalid(reconf_axi_awvalid),
    .m_axi_reconf_awready(reconf_axi_awready),
    .m_axi_reconf_wdata(reconf_axi_wdata),
    .m_axi_reconf_wstrb(reconf_axi_wstrb),
    .m_axi_reconf_wdata_parity(reconf_axi_wdata_parity),
    .m_axi_reconf_wlast(reconf_axi_wlast),
    .m_axi_reconf_wvalid(reconf_axi_wvalid),
    .m_axi_reconf_wready(reconf_axi_wready),
    .m_axi_reconf_bid(reconf_axi_bid),
    .m_axi_reconf_bresp(reconf_axi_bresp),
    .m_axi_reconf_bvalid(reconf_axi_bvalid),
    .m_axi_reconf_bready(reconf_axi_bready),
    .m_axi_reconf_araddr(reconf_axi_araddr),
    .m_axi_reconf_arburst(reconf_axi_arburst),
    .m_axi_reconf_arid(reconf_axi_arid),
    .m_axi_reconf_arlen(reconf_axi_arlen),
    .m_axi_reconf_arsize(reconf_axi_arsize),
    .m_axi_reconf_arvalid(reconf_axi_arvalid),
    .m_axi_reconf_arready(reconf_axi_arready),
    .m_axi_reconf_rid(reconf_axi_rid),
    .m_axi_reconf_rdata(reconf_axi_rdata),
    .m_axi_reconf_rdata_parity(reconf_axi_rdata_parity),
    .m_axi_reconf_rresp(reconf_axi_rresp),
    .m_axi_reconf_rlast(reconf_axi_rlast),
    .m_axi_reconf_rvalid(reconf_axi_rvalid),
    .m_axi_reconf_rready(reconf_axi_rready),
    .s_axi_control_awvalid(),
    .s_axi_control_awready(),
    .s_axi_control_awaddr(),
    .s_axi_control_wvalid(),
    .s_axi_control_wready(),
    .s_axi_control_wdata(),
    .s_axi_control_wstrb(),
    .s_axi_control_arvalid(),
    .s_axi_control_arready(),
    .s_axi_control_araddr(),
    .s_axi_control_rvalid(),
    .s_axi_control_rready(),
    .s_axi_control_rdata(),
    .s_axi_control_rresp(),
    .s_axi_control_bvalid(),
    .s_axi_control_bready(),
    .s_axi_control_bresp(),
    .interrupt()
);

axis_tcp_stat_width_conv tcp_open_status_width_conv_inst (
  .aclk(clk),
  .aresetn(rstn),
  .s_axis_tvalid(m_axis_tcp_open_status_tvalid),
  .s_axis_tready(m_axis_tcp_open_status_tready),
  .s_axis_tdata(m_axis_tcp_open_status_tdata),
  .s_axis_tkeep(m_axis_tcp_open_status_tkeep),
  .s_axis_tlast(m_axis_tcp_open_status_tlast),
  .m_axis_tvalid(m_axis_tcp_open_status_wconv_tvalid),
  .m_axis_tready(m_axis_tcp_open_status_wconv_tready),
  .m_axis_tdata(m_axis_tcp_open_status_wconv_tdata),
  .m_axis_tkeep(m_axis_tcp_open_status_wconv_tkeep),
  .m_axis_tlast(m_axis_tcp_open_status_wconv_tlast)
);

frac_hbm frac_hbm_inst (
    .hbm_ref_clk(hbm_ref_clk),
    .hbm_clk(clk),
    .hbm_rstn(rstn),
    .apb_0_clk(hbm_apb_clk),
    .apb_rstn(hbm_apb_rstn),
    .hbm_cattrip(hbm_cattrip),

    .m00_axi_araddr(m00_axi_araddr),
    .m00_axi_arlen(m00_axi_arlen),
    .m00_axi_arready(m00_axi_arready),
    .m00_axi_arvalid(m00_axi_arvalid),
    .m00_axi_awaddr(m00_axi_awaddr),
    .m00_axi_awlen(m00_axi_awlen),
    .m00_axi_awready(m00_axi_awready),
    .m00_axi_awvalid(m00_axi_awvalid),
    .m00_axi_bready(m00_axi_bready),
    .m00_axi_bvalid(m00_axi_bvalid),
    .m00_axi_rdata(m00_axi_rdata),
    .m00_axi_rlast(m00_axi_rlast),
    .m00_axi_rready(m00_axi_rready),
    .m00_axi_rvalid(m00_axi_rvalid),
    .m00_axi_wdata(m00_axi_wdata),
    .m00_axi_wlast(m00_axi_wlast),
    .m00_axi_wready(m00_axi_wready),
    .m00_axi_wstrb(m00_axi_wstrb),
    .m00_axi_wvalid(m00_axi_wvalid),
    .m01_axi_araddr(m01_axi_araddr),
    .m01_axi_arlen(m01_axi_arlen),
    .m01_axi_arready(m01_axi_arready),
    .m01_axi_arvalid(m01_axi_arvalid),
    .m01_axi_awaddr(m01_axi_awaddr),
    .m01_axi_awlen(m01_axi_awlen),
    .m01_axi_awready(m01_axi_awready),
    .m01_axi_awvalid(m01_axi_awvalid),
    .m01_axi_bready(m01_axi_bready),
    .m01_axi_bvalid(m01_axi_bvalid),
    .m01_axi_rdata(m01_axi_rdata),
    .m01_axi_rlast(m01_axi_rlast),
    .m01_axi_rready(m01_axi_rready),
    .m01_axi_rvalid(m01_axi_rvalid),
    .m01_axi_wdata(m01_axi_wdata),
    .m01_axi_wlast(m01_axi_wlast),
    .m01_axi_wready(m01_axi_wready),
    .m01_axi_wstrb(m01_axi_wstrb),
    .m01_axi_wvalid(m01_axi_wvalid),
    .reconf_axi_awaddr(reconf_axi_awaddr),
    .reconf_axi_awburst(reconf_axi_awburst),
    .reconf_axi_awid(reconf_axi_awid),
    .reconf_axi_awlen(reconf_axi_awlen),
    .reconf_axi_awsize(reconf_axi_awsize),
    .reconf_axi_awvalid(reconf_axi_awvalid),
    .reconf_axi_awready(reconf_axi_awready),
    .reconf_axi_wdata(reconf_axi_wdata),
    .reconf_axi_wstrb(reconf_axi_wstrb),
    .reconf_axi_wdata_parity(reconf_axi_wdata_parity),
    .reconf_axi_wlast(reconf_axi_wlast),
    .reconf_axi_wvalid(reconf_axi_wvalid),
    .reconf_axi_wready(reconf_axi_wready),
    .reconf_axi_bid(reconf_axi_bid),
    .reconf_axi_bresp(reconf_axi_bresp),
    .reconf_axi_bvalid(reconf_axi_bvalid),
    .reconf_axi_bready(reconf_axi_bready),
    .reconf_axi_araddr(reconf_axi_araddr),
    .reconf_axi_arburst(reconf_axi_arburst),
    .reconf_axi_arid(reconf_axi_arid),
    .reconf_axi_arlen(reconf_axi_arlen),
    .reconf_axi_arsize(reconf_axi_arsize),
    .reconf_axi_arvalid(reconf_axi_arvalid),
    .reconf_axi_arready(reconf_axi_arready),
    .reconf_axi_rid(reconf_axi_rid),
    .reconf_axi_rdata(reconf_axi_rdata),
    .reconf_axi_rdata_parity(reconf_axi_rdata_parity),
    .reconf_axi_rresp(reconf_axi_rresp),
    .reconf_axi_rlast(reconf_axi_rlast),
    .reconf_axi_rvalid(reconf_axi_rvalid),
    .reconf_axi_rready(reconf_axi_rready)
);

endmodule

`resetall
