`resetall
`timescale 1ns / 1ps
`default_nettype none

module hbm_debug_axi_master #(
    parameter ADDR_WIDTH = 33,
    parameter DATA_WIDTH = 256,
    parameter STRB_WIDTH = (DATA_WIDTH/8)
) (
    input wire clk,
    input wire rst,

    input wire start,
    input wire clear,
    input wire [ADDR_WIDTH-1:0] base_addr,
    input wire [15:0] word_count,
    input wire [1:0] pattern_select,

    output wire [3:0] state,
    output reg busy,
    output reg done,
    output wire pass,
    output reg fail,
    output reg bresp_error,
    output reg rresp_error,
    output reg rlast_error,
    output reg [31:0] write_count,
    output reg [31:0] read_count,
    output reg [ADDR_WIDTH-1:0] current_addr,
    output reg [ADDR_WIDTH-1:0] first_bad_addr,
    output reg [DATA_WIDTH-1:0] expected_data,
    output reg [DATA_WIDTH-1:0] observed_data,

    output reg [ADDR_WIDTH-1:0] m_axi_awaddr,
    output wire [1:0] m_axi_awburst,
    output wire [5:0] m_axi_awid,
    output wire [3:0] m_axi_awlen,
    output wire [2:0] m_axi_awsize,
    output reg m_axi_awvalid,
    input wire m_axi_awready,

    output reg [DATA_WIDTH-1:0] m_axi_wdata,
    output wire [STRB_WIDTH-1:0] m_axi_wstrb,
    output wire [STRB_WIDTH-1:0] m_axi_wdata_parity,
    output reg m_axi_wlast,
    output reg m_axi_wvalid,
    input wire m_axi_wready,

    input wire [5:0] m_axi_bid,
    input wire [1:0] m_axi_bresp,
    input wire m_axi_bvalid,
    output reg m_axi_bready,

    output reg [ADDR_WIDTH-1:0] m_axi_araddr,
    output wire [1:0] m_axi_arburst,
    output wire [5:0] m_axi_arid,
    output wire [3:0] m_axi_arlen,
    output wire [2:0] m_axi_arsize,
    output reg m_axi_arvalid,
    input wire m_axi_arready,

    input wire [5:0] m_axi_rid,
    input wire [DATA_WIDTH-1:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp,
    input wire m_axi_rlast,
    input wire m_axi_rvalid,
    output reg m_axi_rready
);

localparam [3:0]
    STATE_IDLE       = 4'd0,
    STATE_WRITE_ADDR = 4'd1,
    STATE_WRITE_DATA = 4'd2,
    STATE_WRITE_RESP = 4'd3,
    STATE_READ_ADDR  = 4'd4,
    STATE_READ_DATA  = 4'd5,
    STATE_DONE       = 4'd6;

localparam [ADDR_WIDTH-1:0] ADDR_INCR = {{ADDR_WIDTH-6{1'b0}}, 6'd32};

reg [3:0] state_reg = STATE_IDLE;
reg [31:0] total_words_reg = 32'd0;
reg [31:0] word_index_reg = 32'd0;
reg [1:0] pattern_select_reg = 2'd0;
reg start_reg = 1'b0;

wire start_edge = start && !start_reg;
wire [31:0] requested_words = word_count == 16'd0 ? 32'd1 : {16'd0, word_count};
wire last_word = word_index_reg + 32'd1 >= total_words_reg;

assign state = state_reg;
assign pass = done && !fail;

assign m_axi_awid = 6'd0;
assign m_axi_awlen = 4'd0;
assign m_axi_awsize = 3'd5;
assign m_axi_awburst = 2'b01;
assign m_axi_wstrb = {STRB_WIDTH{1'b1}};
assign m_axi_wdata_parity = {STRB_WIDTH{1'b0}};
assign m_axi_arid = 6'd0;
assign m_axi_arlen = 4'd0;
assign m_axi_arsize = 3'd5;
assign m_axi_arburst = 2'b01;

function [DATA_WIDTH-1:0] build_pattern;
    input [ADDR_WIDTH-1:0] addr;
    input [31:0] index;
    input [1:0] pattern;
    reg [31:0] seed;
begin
    seed = addr[31:0] ^ index ^ 32'h5a5a_0000;
    case (pattern)
        2'd0: build_pattern = {8{seed}};
        2'd1: build_pattern = {DATA_WIDTH{1'b0}};
        2'd2: build_pattern = {DATA_WIDTH{1'b1}};
        default: build_pattern = {
            seed ^ 32'hf0f0_f0f0,
            seed + 32'd7,
            seed ^ 32'h0f0f_0f0f,
            seed + 32'd5,
            seed ^ 32'ha5a5_a5a5,
            seed + 32'd3,
            seed ^ 32'h3c3c_3c3c,
            seed + 32'd1
        };
    endcase
end
endfunction

always @(posedge clk) begin
    start_reg <= start;

    if (rst) begin
        state_reg <= STATE_IDLE;
        busy <= 1'b0;
        done <= 1'b0;
        fail <= 1'b0;
        bresp_error <= 1'b0;
        rresp_error <= 1'b0;
        rlast_error <= 1'b0;
        write_count <= 32'd0;
        read_count <= 32'd0;
        current_addr <= {ADDR_WIDTH{1'b0}};
        first_bad_addr <= {ADDR_WIDTH{1'b0}};
        expected_data <= {DATA_WIDTH{1'b0}};
        observed_data <= {DATA_WIDTH{1'b0}};
        total_words_reg <= 32'd0;
        word_index_reg <= 32'd0;
        pattern_select_reg <= 2'd0;
        m_axi_awaddr <= {ADDR_WIDTH{1'b0}};
        m_axi_awvalid <= 1'b0;
        m_axi_wdata <= {DATA_WIDTH{1'b0}};
        m_axi_wlast <= 1'b0;
        m_axi_wvalid <= 1'b0;
        m_axi_bready <= 1'b0;
        m_axi_araddr <= {ADDR_WIDTH{1'b0}};
        m_axi_arvalid <= 1'b0;
        m_axi_rready <= 1'b0;
    end else if (clear) begin
        state_reg <= STATE_IDLE;
        busy <= 1'b0;
        done <= 1'b0;
        fail <= 1'b0;
        bresp_error <= 1'b0;
        rresp_error <= 1'b0;
        rlast_error <= 1'b0;
        write_count <= 32'd0;
        read_count <= 32'd0;
        current_addr <= {ADDR_WIDTH{1'b0}};
        first_bad_addr <= {ADDR_WIDTH{1'b0}};
        expected_data <= {DATA_WIDTH{1'b0}};
        observed_data <= {DATA_WIDTH{1'b0}};
        total_words_reg <= 32'd0;
        word_index_reg <= 32'd0;
        pattern_select_reg <= 2'd0;
        m_axi_awvalid <= 1'b0;
        m_axi_wlast <= 1'b0;
        m_axi_wvalid <= 1'b0;
        m_axi_bready <= 1'b0;
        m_axi_arvalid <= 1'b0;
        m_axi_rready <= 1'b0;
    end else begin
        case (state_reg)
            STATE_IDLE: begin
                busy <= 1'b0;
                m_axi_awvalid <= 1'b0;
                m_axi_wvalid <= 1'b0;
                m_axi_wlast <= 1'b0;
                m_axi_bready <= 1'b0;
                m_axi_arvalid <= 1'b0;
                m_axi_rready <= 1'b0;

                if (start_edge) begin
                    busy <= 1'b1;
                    done <= 1'b0;
                    fail <= 1'b0;
                    bresp_error <= 1'b0;
                    rresp_error <= 1'b0;
                    rlast_error <= 1'b0;
                    write_count <= 32'd0;
                    read_count <= 32'd0;
                    first_bad_addr <= {ADDR_WIDTH{1'b0}};
                    observed_data <= {DATA_WIDTH{1'b0}};
                    total_words_reg <= requested_words;
                    word_index_reg <= 32'd0;
                    pattern_select_reg <= pattern_select;
                    current_addr <= {base_addr[ADDR_WIDTH-1:5], 5'd0};
                    expected_data <= build_pattern({base_addr[ADDR_WIDTH-1:5], 5'd0}, 32'd0, pattern_select);
                    state_reg <= STATE_WRITE_ADDR;
                end
            end

            STATE_WRITE_ADDR: begin
                m_axi_awaddr <= current_addr;
                m_axi_awvalid <= 1'b1;

                if (m_axi_awvalid && m_axi_awready) begin
                    m_axi_awvalid <= 1'b0;
                    m_axi_wdata <= build_pattern(current_addr, word_index_reg, pattern_select_reg);
                    expected_data <= build_pattern(current_addr, word_index_reg, pattern_select_reg);
                    m_axi_wlast <= 1'b1;
                    m_axi_wvalid <= 1'b1;
                    state_reg <= STATE_WRITE_DATA;
                end
            end

            STATE_WRITE_DATA: begin
                if (m_axi_wvalid && m_axi_wready) begin
                    m_axi_wvalid <= 1'b0;
                    m_axi_wlast <= 1'b0;
                    m_axi_bready <= 1'b1;
                    state_reg <= STATE_WRITE_RESP;
                end
            end

            STATE_WRITE_RESP: begin
                if (m_axi_bvalid && m_axi_bready) begin
                    m_axi_bready <= 1'b0;
                    write_count <= write_count + 32'd1;

                    if (m_axi_bresp != 2'b00) begin
                        fail <= 1'b1;
                        bresp_error <= 1'b1;
                        first_bad_addr <= current_addr;
                        busy <= 1'b0;
                        done <= 1'b1;
                        state_reg <= STATE_DONE;
                    end else if (last_word) begin
                        word_index_reg <= 32'd0;
                        current_addr <= {base_addr[ADDR_WIDTH-1:5], 5'd0};
                        state_reg <= STATE_READ_ADDR;
                    end else begin
                        word_index_reg <= word_index_reg + 32'd1;
                        current_addr <= current_addr + ADDR_INCR;
                        state_reg <= STATE_WRITE_ADDR;
                    end
                end
            end

            STATE_READ_ADDR: begin
                m_axi_araddr <= current_addr;
                m_axi_arvalid <= 1'b1;

                if (m_axi_arvalid && m_axi_arready) begin
                    m_axi_arvalid <= 1'b0;
                    expected_data <= build_pattern(current_addr, word_index_reg, pattern_select_reg);
                    m_axi_rready <= 1'b1;
                    state_reg <= STATE_READ_DATA;
                end
            end

            STATE_READ_DATA: begin
                if (m_axi_rvalid && m_axi_rready) begin
                    m_axi_rready <= 1'b0;
                    read_count <= read_count + 32'd1;
                    observed_data <= m_axi_rdata;
                    expected_data <= build_pattern(current_addr, word_index_reg, pattern_select_reg);

                    if (m_axi_rresp != 2'b00 || !m_axi_rlast || m_axi_rdata != build_pattern(current_addr, word_index_reg, pattern_select_reg)) begin
                        fail <= 1'b1;
                        rresp_error <= m_axi_rresp != 2'b00;
                        rlast_error <= !m_axi_rlast;
                        first_bad_addr <= current_addr;
                        busy <= 1'b0;
                        done <= 1'b1;
                        state_reg <= STATE_DONE;
                    end else if (last_word) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        state_reg <= STATE_DONE;
                    end else begin
                        word_index_reg <= word_index_reg + 32'd1;
                        current_addr <= current_addr + ADDR_INCR;
                        state_reg <= STATE_READ_ADDR;
                    end
                end
            end

            STATE_DONE: begin
                busy <= 1'b0;
                m_axi_awvalid <= 1'b0;
                m_axi_wvalid <= 1'b0;
                m_axi_wlast <= 1'b0;
                m_axi_bready <= 1'b0;
                m_axi_arvalid <= 1'b0;
                m_axi_rready <= 1'b0;

                if (start_edge) begin
                    done <= 1'b0;
                    fail <= 1'b0;
                    bresp_error <= 1'b0;
                    rresp_error <= 1'b0;
                    rlast_error <= 1'b0;
                    write_count <= 32'd0;
                    read_count <= 32'd0;
                    first_bad_addr <= {ADDR_WIDTH{1'b0}};
                    observed_data <= {DATA_WIDTH{1'b0}};
                    total_words_reg <= requested_words;
                    word_index_reg <= 32'd0;
                    pattern_select_reg <= pattern_select;
                    current_addr <= {base_addr[ADDR_WIDTH-1:5], 5'd0};
                    expected_data <= build_pattern({base_addr[ADDR_WIDTH-1:5], 5'd0}, 32'd0, pattern_select);
                    busy <= 1'b1;
                    state_reg <= STATE_WRITE_ADDR;
                end
            end

            default: begin
                state_reg <= STATE_IDLE;
            end
        endcase
    end
end

endmodule

`resetall
