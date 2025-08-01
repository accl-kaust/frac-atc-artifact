`resetall
`timescale 1ns / 1ps
`default_nettype none

module offrac_top (
    input wire clk_100mhz_0_p,
    input wire clk_100mhz_0_n,

    input wire clk_100mhz_1_p,
    input wire clk_100mhz_1_n,

    input wire qsfp0_mgt_refclk_1_p,
    input wire qsfp0_mgt_refclk_1_n,

    input wire [3:0] qsfp0_rx_p,
    input wire [3:0] qsfp0_rx_n,
    output wire [3:0] qsfp0_tx_p,
    output wire [3:0] qsfp0_tx_n,

    output wire  qsfp0_refclk_oe_b,
    output wire  qsfp0_refclk_fs,

    input  wire [3:0]   msp_gpio,
    output wire         msp_uart_txd,
    input  wire         msp_uart_rxd

);

assign qsfp0_refclk_oe_b = 1'b0;
assign qsfp0_refclk_fs = 1'b0;

wire qsfp0_gtpowergood;

assign qsfp0_gtpowergood = 1'b1;

wire clk_100mhz_0_ibufg;
wire clk_100mhz_1_ibufg;

wire qsfp0_mgt_refclk_1;
wire qsfp0_mgt_refclk_1_int;
wire qsfp0_mgt_refclk_1_bufg;

wire rst;
wire rstn;

wire clk_50mhz_mmcm_out;
wire clk_50mhz_int;
wire clk_125mhz_int;
wire clk_125mhz_mmcm_out;

wire mmcm_locked;
wire mmcm_clkfb;
wire mmcm_rst;
wire rst_50mhz_int;
wire rst_125mhz_int;

assign mmcm_rst = rst;



wire [63:0] m00_axi_araddr;
wire [7:0]  m00_axi_arlen;
wire        m00_axi_arready;
wire        m00_axi_arvalid;
wire [63:0] m00_axi_awaddr;
wire [7:0]  m00_axi_awlen;
wire        m00_axi_awready;
wire        m00_axi_awvalid;
wire        m00_axi_bready;
wire        m00_axi_bvalid;
wire [511:0] m00_axi_rdata;
wire         m00_axi_rlast;
wire         m00_axi_rready;
wire         m00_axi_rvalid;
wire [511:0] m00_axi_wdata;
wire         m00_axi_wlast;
wire         m00_axi_wready;
wire [63:0]  m00_axi_wstrb;
wire         m00_axi_wvalid;
wire [63:0]  m01_axi_araddr;
wire [7:0]   m01_axi_arlen;
wire         m01_axi_arready;
wire         m01_axi_arvalid;
wire [63:0]  m01_axi_awaddr;
wire [7:0]   m01_axi_awlen;
wire         m01_axi_awready;
wire         m01_axi_awvalid;
wire         m01_axi_bready;
wire         m01_axi_bvalid;
wire [511:0] m01_axi_rdata;
wire         m01_axi_rlast;
wire         m01_axi_rready;
wire         m01_axi_rvalid;
wire [511:0] m01_axi_wdata;
wire         m01_axi_wlast;
wire         m01_axi_wready;
wire [63:0]  m01_axi_wstrb;
wire         m01_axi_wvalid;

// IBUFDS_GTE4 ibufds_gte4_qsfp0_mgt_refclk_1_inst (
//     .I     (qsfp0_mgt_refclk_1_p),
//     .IB    (qsfp0_mgt_refclk_1_n),
//     .CEB   (1'b0),
//     .O     (qsfp0_mgt_refclk_1),
//     .ODIV2 (qsfp0_mgt_refclk_1_int)
// );

// BUFG_GT bufg_gt_qsfp0_mgt_refclk_1_inst (
//     .CE      (qsfp0_gtpowergood),
//     .CEMASK  (1'b1),
//     .CLR     (1'b0),
//     .CLRMASK (1'b1),
//     .DIV     (3'd0),
//     .I       (qsfp0_mgt_refclk_1_int),
//     .O       (qsfp0_mgt_refclk_1_bufg)
// );

IBUFGDS #(
   .DIFF_TERM("FALSE"),
   .IBUF_LOW_PWR("FALSE")
)
clk_100mhz_0_ibufg_inst (
   .O   (clk_100mhz_0_ibufg),
   .I   (clk_100mhz_0_p),
   .IB  (clk_100mhz_0_n)
);

MMCME4_BASE #(
    .BANDWIDTH("OPTIMIZED"),
    .CLKOUT0_DIVIDE_F(8),
    .CLKOUT0_DUTY_CYCLE(0.5),
    .CLKOUT0_PHASE(0),
    .CLKOUT1_DIVIDE(20),
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
    .CLKFBOUT_MULT_F(10),
    .CLKFBOUT_PHASE(0),
    .DIVCLK_DIVIDE(1),
    .REF_JITTER1(0.010),
    .CLKIN1_PERIOD(10.000),
    .STARTUP_WAIT("FALSE"),
    .CLKOUT4_CASCADE("FALSE")
)
clk_mmcm_inst (
    .CLKIN1(clk_100mhz_0_ibufg),
    .CLKFBIN(mmcm_clkfb),
    .RST(mmcm_rst),
    .PWRDWN(1'b0),
    .CLKOUT0(clk_125mhz_mmcm_out),
    .CLKOUT0B(),
    .CLKOUT1(clk_50mhz_mmcm_out),
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

BUFG
clk_50mhz_bufg_inst (
    .I(clk_50mhz_mmcm_out),
    .O(clk_50mhz_int)
);

BUFG
clk_125mhz_bufg_inst (
    .I(clk_125mhz_mmcm_out),
    .O(clk_125mhz_int)
);

sync_reset #(
    .N(4)
)
sync_reset_50mhz_inst (
    .clk(clk_50mhz_int),
    .rst(~mmcm_locked),
    .out(rst_50mhz_int)
);

sync_reset #(
    .N(4)
)
sync_reset_125mhz_inst (
    .clk(clk_125mhz_int),
    .rst(~mmcm_locked),
    .out(rst_125mhz_int)
);

reset_gen(
    .clk(clk_100mhz_0_ibufg),
    .rst_out(rst),
    .rstn_out(rstn)
);

// ila_11 debg_rst(
//    .clk(clk_100mhz_0_ibufg),
//    .probe0(rst)
// );

offrac offrac_inst
    (
    .free_run_clk(clk_50mhz_int),
    .qsfp0_refclk_n(qsfp0_mgt_refclk_1_n),
    .qsfp0_refclk_p(qsfp0_mgt_refclk_1_p),
    .qsfp0_rx_n(qsfp0_rx_n),
    .qsfp0_rx_p(qsfp0_rx_p),
    .qsfp0_tx_n(qsfp0_tx_n),
    .qsfp0_tx_p(qsfp0_tx_p),
    .sys_clk_n(clk_100mhz_1_n),
    .sys_clk_p(clk_100mhz_1_p),
    .sys_rst(rst_50mhz_int),
    .sys_rstn(!rst_50mhz_int)
);

endmodule

`resetall
