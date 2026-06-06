`timescale 1ns / 1ps

module tb_user_reconf_write_hbm;
    localparam integer BYTE_LANES = 64;
    localparam [15:0] CONN_ID = 16'h6c00;
    localparam [15:0] TCP_PAYLOAD_BYTES = 16'd192;
    localparam [15:0] RESPONSE_BYTES = 16'd64;
    localparam [63:0] HBM_ADDR = 64'h0000_0000_0000_4000;

    reg clk = 1'b0;
    reg rst = 1'b1;

    always #2 clk = ~clk;

    wire        m_axis_open_connection_tvalid;
    reg         m_axis_open_connection_tready = 1'b1;
    wire [47:0] m_axis_open_connection_tdata;
    reg         s_axis_open_status_tvalid = 1'b0;
    wire        s_axis_open_status_tready;
    reg  [23:0] s_axis_open_status_tdata = 24'd0;
    wire        m_axis_close_connection_tvalid;
    reg         m_axis_close_connection_tready = 1'b1;
    wire [15:0] m_axis_close_connection_tdata;
    wire        m_axis_listen_port_tvalid;
    reg         m_axis_listen_port_tready = 1'b1;
    wire [15:0] m_axis_listen_port_tdata;
    reg         s_axis_listen_port_status_tvalid = 1'b0;
    wire        s_axis_listen_port_status_tready;
    reg  [7:0]  s_axis_listen_port_status_tdata = 8'd0;

    reg         s_axis_notifications_tvalid = 1'b0;
    wire        s_axis_notifications_tready;
    reg  [87:0] s_axis_notifications_tdata = 88'd0;
    wire        m_axis_read_package_tvalid;
    reg         m_axis_read_package_tready = 1'b1;
    wire [31:0] m_axis_read_package_tdata;

    wire        m_axis_tx_data_tvalid;
    reg         m_axis_tx_data_tready = 1'b1;
    wire [511:0] m_axis_tx_data_tdata;
    wire [63:0]  m_axis_tx_data_tkeep;
    wire        m_axis_tx_data_tlast;
    wire        m_axis_tx_metadata_tvalid;
    reg         m_axis_tx_metadata_tready = 1'b1;
    wire [31:0] m_axis_tx_metadata_tdata;
    reg         s_axis_tx_status_tvalid = 1'b0;
    wire        s_axis_tx_status_tready;
    reg  [63:0] s_axis_tx_status_tdata = 64'd0;

    reg         s_axis_rx_data_tvalid = 1'b0;
    wire        s_axis_rx_data_tready;
    reg  [511:0] s_axis_rx_data_tdata = 512'd0;
    reg  [63:0]  s_axis_rx_data_tkeep = {64{1'b1}};
    reg          s_axis_rx_data_tlast = 1'b0;
    reg          s_axis_rx_metadata_tvalid = 1'b0;
    wire         s_axis_rx_metadata_tready;
    reg  [15:0]  s_axis_rx_metadata_tdata = 16'd0;

    wire [32:0]  m_axi_awaddr;
    wire [1:0]   m_axi_awburst;
    wire [5:0]   m_axi_awid;
    wire [7:0]   m_axi_awlen;
    wire [2:0]   m_axi_awsize;
    wire         m_axi_awvalid;
    reg          m_axi_awready = 1'b1;
    wire [255:0] m_axi_wdata;
    wire [31:0]  m_axi_wstrb;
    wire [31:0]  m_axi_wdata_parity;
    wire         m_axi_wlast;
    wire         m_axi_wvalid;
    reg          m_axi_wready = 1'b1;
    reg  [5:0]   m_axi_bid = 6'd0;
    reg  [1:0]   m_axi_bresp = 2'd0;
    reg          m_axi_bvalid = 1'b0;
    wire         m_axi_bready;
    wire [32:0]  m_axi_araddr;
    wire [1:0]   m_axi_arburst;
    wire [5:0]   m_axi_arid;
    wire [7:0]   m_axi_arlen;
    wire [2:0]   m_axi_arsize;
    wire         m_axi_arvalid;
    reg          m_axi_arready = 1'b1;
    reg  [5:0]   m_axi_rid = 6'd0;
    reg  [255:0] m_axi_rdata = 256'd0;
    reg  [31:0]  m_axi_rdata_parity = 32'd0;
    reg  [1:0]   m_axi_rresp = 2'd0;
    reg          m_axi_rlast = 1'b1;
    reg          m_axi_rvalid = 1'b0;
    wire         m_axi_rready;

    integer write_count = 0;
    integer response_count = 0;
    reg aw_seen = 1'b0;
    reg [32:0] awaddr_hold = 33'd0;
    reg [511:0] expected_payload;

    tcp_top_loopback #(.IS_SIM(1)) dut (
        .clk(clk),
        .rst(rst),
        .m_axis_open_connection_tvalid(m_axis_open_connection_tvalid),
        .m_axis_open_connection_tready(m_axis_open_connection_tready),
        .m_axis_open_connection_tdata(m_axis_open_connection_tdata),
        .s_axis_open_status_tvalid(s_axis_open_status_tvalid),
        .s_axis_open_status_tready(s_axis_open_status_tready),
        .s_axis_open_status_tdata(s_axis_open_status_tdata),
        .m_axis_close_connection_tvalid(m_axis_close_connection_tvalid),
        .m_axis_close_connection_tready(m_axis_close_connection_tready),
        .m_axis_close_connection_tdata(m_axis_close_connection_tdata),
        .m_axis_listen_port_tvalid(m_axis_listen_port_tvalid),
        .m_axis_listen_port_tready(m_axis_listen_port_tready),
        .m_axis_listen_port_tdata(m_axis_listen_port_tdata),
        .s_axis_listen_port_status_tvalid(s_axis_listen_port_status_tvalid),
        .s_axis_listen_port_status_tready(s_axis_listen_port_status_tready),
        .s_axis_listen_port_status_tdata(s_axis_listen_port_status_tdata),
        .s_axis_notifications_tvalid(s_axis_notifications_tvalid),
        .s_axis_notifications_tready(s_axis_notifications_tready),
        .s_axis_notifications_tdata(s_axis_notifications_tdata),
        .m_axis_read_package_tvalid(m_axis_read_package_tvalid),
        .m_axis_read_package_tready(m_axis_read_package_tready),
        .m_axis_read_package_tdata(m_axis_read_package_tdata),
        .m_axis_tx_data_tvalid(m_axis_tx_data_tvalid),
        .m_axis_tx_data_tready(m_axis_tx_data_tready),
        .m_axis_tx_data_tdata(m_axis_tx_data_tdata),
        .m_axis_tx_data_tkeep(m_axis_tx_data_tkeep),
        .m_axis_tx_data_tlast(m_axis_tx_data_tlast),
        .m_axis_tx_metadata_tvalid(m_axis_tx_metadata_tvalid),
        .m_axis_tx_metadata_tready(m_axis_tx_metadata_tready),
        .m_axis_tx_metadata_tdata(m_axis_tx_metadata_tdata),
        .s_axis_tx_status_tvalid(s_axis_tx_status_tvalid),
        .s_axis_tx_status_tready(s_axis_tx_status_tready),
        .s_axis_tx_status_tdata(s_axis_tx_status_tdata),
        .s_axis_rx_data_tvalid(s_axis_rx_data_tvalid),
        .s_axis_rx_data_tready(s_axis_rx_data_tready),
        .s_axis_rx_data_tdata(s_axis_rx_data_tdata),
        .s_axis_rx_data_tkeep(s_axis_rx_data_tkeep),
        .s_axis_rx_data_tlast(s_axis_rx_data_tlast),
        .s_axis_rx_metadata_tvalid(s_axis_rx_metadata_tvalid),
        .s_axis_rx_metadata_tready(s_axis_rx_metadata_tready),
        .s_axis_rx_metadata_tdata(s_axis_rx_metadata_tdata),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awid(m_axi_awid),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wdata_parity(m_axi_wdata_parity),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bid(m_axi_bid),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arid(m_axi_arid),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rdata_parity(m_axi_rdata_parity),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready)
    );

    function [511:0] hbm_payload_line;
        integer i;
        begin
            hbm_payload_line = 512'd0;
            for (i = 0; i < BYTE_LANES; i = i + 1) begin
                hbm_payload_line[i*8 +: 8] = (8'h40 + i[7:0]);
            end
        end
    endfunction

    function [511:0] request_header_line;
        integer i;
        begin
            request_header_line = 512'd0;
            for (i = 0; i < 56; i = i + 1) begin
                request_header_line[i*8 +: 8] = 8'hff;
            end
            request_header_line[56*8 +: 32] = 32'd128;
            request_header_line[60*8 +: 16] = 16'hffff;
            request_header_line[62*8 +: 16] = 16'h00ab;
        end
    endfunction

    function [511:0] write_hbm_command_line;
        begin
            write_hbm_command_line = 512'd0;
            write_hbm_command_line[0*8 +: 8] = 8'd1;
            write_hbm_command_line[1*8 +: 8] = 8'd0;
            write_hbm_command_line[8*8 +: 64] = HBM_ADDR;
            write_hbm_command_line[16*8 +: 64] = 64'd64;
        end
    endfunction

    task automatic wait_cycles(input integer cycles);
        integer i;
        begin
            for (i = 0; i < cycles; i = i + 1) begin
                @(posedge clk);
            end
        end
    endtask

    task automatic send_notification;
        begin
            s_axis_notifications_tdata = {56'd0, TCP_PAYLOAD_BYTES, CONN_ID};
            s_axis_notifications_tvalid = 1'b1;
            while (!s_axis_notifications_tready) @(posedge clk);
            @(posedge clk);
            s_axis_notifications_tvalid = 1'b0;
            s_axis_notifications_tdata = 88'd0;

            while (!m_axis_read_package_tvalid) @(posedge clk);
            if (m_axis_read_package_tdata !== {TCP_PAYLOAD_BYTES, CONN_ID}) begin
                $fatal(1, "read package mismatch: got %08x expected %08x",
                       m_axis_read_package_tdata, {TCP_PAYLOAD_BYTES, CONN_ID});
            end
        end
    endtask

    task automatic send_rx_beat(input [511:0] data, input last);
        begin
            s_axis_rx_data_tdata = data;
            s_axis_rx_data_tlast = last;
            s_axis_rx_data_tvalid = 1'b1;
            while (!s_axis_rx_data_tready) @(posedge clk);
            @(posedge clk);
            s_axis_rx_data_tvalid = 1'b0;
            s_axis_rx_data_tdata = 512'd0;
            s_axis_rx_data_tlast = 1'b0;
            @(posedge clk);
        end
    endtask

    task automatic send_tx_status_ok;
        begin
            s_axis_tx_status_tdata = 64'd0;
            s_axis_tx_status_tvalid = 1'b1;
            while (!s_axis_tx_status_tready) @(posedge clk);
            @(posedge clk);
            s_axis_tx_status_tvalid = 1'b0;
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            m_axi_bvalid <= 1'b0;
            aw_seen <= 1'b0;
            write_count <= 0;
        end else begin
            if (m_axi_bvalid && m_axi_bready) begin
                m_axi_bvalid <= 1'b0;
            end

            if (m_axi_awvalid && m_axi_awready) begin
                aw_seen <= 1'b1;
                awaddr_hold <= m_axi_awaddr;
            end

            if (m_axi_wvalid && m_axi_wready) begin
                if (!aw_seen && !(m_axi_awvalid && m_axi_awready)) begin
                    $fatal(1, "HBM write data arrived before write address");
                end

                if (write_count == 0) begin
                    if (awaddr_hold !== HBM_ADDR[32:0]) begin
                        $fatal(1, "first HBM write address mismatch: got %h", awaddr_hold);
                    end
                    if (m_axi_wdata !== expected_payload[255:0]) begin
                        $fatal(1, "first HBM write data mismatch: got %h", m_axi_wdata);
                    end
                end else if (write_count == 1) begin
                    if (awaddr_hold !== HBM_ADDR[32:0] + 33'd32) begin
                        $fatal(1, "second HBM write address mismatch: got %h", awaddr_hold);
                    end
                    if (m_axi_wdata !== expected_payload[511:256]) begin
                        $fatal(1, "second HBM write data mismatch: got %h", m_axi_wdata);
                    end
                end else begin
                    $fatal(1, "unexpected extra HBM write %0d", write_count);
                end

                if (m_axi_wstrb !== {32{1'b1}}) begin
                    $fatal(1, "HBM write strobe mismatch: got %h", m_axi_wstrb);
                end

                write_count <= write_count + 1;
                m_axi_bvalid <= 1'b1;
                aw_seen <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst && m_axis_tx_metadata_tvalid && m_axis_tx_metadata_tready) begin
            if (m_axis_tx_metadata_tdata !== {RESPONSE_BYTES, CONN_ID}) begin
                $fatal(1, "response metadata mismatch: got %08x expected %08x",
                       m_axis_tx_metadata_tdata, {RESPONSE_BYTES, CONN_ID});
            end
        end

        if (!rst && m_axis_tx_data_tvalid && m_axis_tx_data_tready) begin
            response_count <= response_count + 1;
            if (m_axis_tx_data_tdata !== 512'd0) begin
                $fatal(1, "WRITE_HBM response payload is not all zero: got %h", m_axis_tx_data_tdata);
            end
            if (m_axis_tx_data_tkeep !== {64{1'b1}}) begin
                $fatal(1, "response keep mismatch: got %h", m_axis_tx_data_tkeep);
            end
            if (!m_axis_tx_data_tlast) begin
                $fatal(1, "response TLAST was not asserted");
            end
        end
    end

    initial begin
        expected_payload = hbm_payload_line();

        wait_cycles(8);
        rst = 1'b0;
        wait_cycles(8);

        send_notification();
        send_rx_beat(request_header_line(), 1'b0);
        send_rx_beat(write_hbm_command_line(), 1'b0);
        send_rx_beat(expected_payload, 1'b1);
        send_tx_status_ok();

        wait_cycles(200);

        if (write_count !== 2) begin
            $fatal(1, "expected two 32B HBM writes, saw %0d", write_count);
        end
        if (response_count !== 1) begin
            $fatal(1, "expected exactly one response, saw %0d", response_count);
        end

        $display("PASS: one WRITE_HBM request produced two HBM writes and one 64B zero response");
        $finish;
    end

    initial begin
        wait_cycles(5000);
        $fatal(1, "timeout waiting for WRITE_HBM response");
    end
endmodule
