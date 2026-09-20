`timescale 1ns/1ps
// Testbench for log. Uses tb/fp_stubs.v in place of the Xilinx cores.
//   iverilog -g2012 -s tb_log -o tb.vvp tb/tb_log.v tb/fp_stubs.v src/rtl/log.v && vvp tb.vvp
module tb_log;
    localparam [31:0] FP_ONE = 32'h3F800000;

    reg clk=0, rst=1; always #5 clk = ~clk;
    reg  [511:0] s_tdata; reg s_tvalid=0, s_tlast=0; wire s_tready;
    wire [511:0] m_tdata; wire m_tvalid, m_tlast; reg m_tready=1;

    log dut (.clk(clk), .rst(rst),
        .s_axis_tdata(s_tdata), .s_axis_tkeep({64{1'b1}}), .s_axis_tstrb({64{1'b1}}),
        .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready), .s_axis_tlast(s_tlast),
        .s_axis_tdest(3'd6), .s_axis_tid(4'd3), .s_axis_tuser(1'b1),
        .m_axis_tdata(m_tdata), .m_axis_tkeep(), .m_axis_tstrb(),
        .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready), .m_axis_tlast(m_tlast),
        .m_axis_tdest(), .m_axis_tid(), .m_axis_tuser());

    // reference model of the stub chain
    function [31:0] expect_f(input [31:0] x);
        reg [31:0] sub;
        begin
            sub = FP_ONE - x;
            expect_f = {x[15:0], sub[15:0]} ^ 32'hA5A5A5A5;
        end
    endfunction

    reg [511:0] beats [0:1]; reg beat_last [0:1];
    reg [511:0] captured; reg cap_last; reg cap_v=0;
    integer nbeat=0, errors=0, i, b;
    reg [511:0] hdr, ln;
    reg [31:0] vals [0:31];

    always @(posedge clk) if (m_tvalid && m_tready) begin
        beats[nbeat] <= m_tdata; beat_last[nbeat] <= m_tlast; nbeat <= nbeat + 1;
    end

    task send(input [511:0] d, input last);
    begin @(negedge clk); while(!s_tready) @(negedge clk);
          s_tdata=d; s_tvalid=1; s_tlast=last; @(negedge clk); s_tvalid=0; s_tlast=0; end
    endtask

    initial begin
        for (i=0;i<32;i=i+1) vals[i] = 32'h3E000000 + (i*32'h00110011) + i;
        hdr = 512'd0; hdr[447:0] = {448{1'b1}}; hdr[495:480] = 16'hffff;

        repeat(4) @(negedge clk); rst=0; repeat(2) @(negedge clk);

        send(hdr, 1'b0);
        for (i=0;i<16;i=i+1) ln[i*32 +: 32] = vals[i];
        send(ln, 1'b0);
        for (i=0;i<16;i=i+1) ln[i*32 +: 32] = vals[16+i];
        send(ln, 1'b1);

        wait (nbeat == 2); repeat(2) @(posedge clk); #1;

        $display("TEST  logit chain, 2 lines x 16 values, header consumed");
        for (b=0;b<2;b=b+1) begin
            for (i=0;i<16;i=i+1) begin
                if (beats[b][i*32 +: 32] !== expect_f(vals[b*16+i])) begin
                    $display("  FAIL beat %0d word %2d: got %h want %h (x=%h)",
                             b, i, beats[b][i*32 +: 32], expect_f(vals[b*16+i]), vals[b*16+i]);
                    errors = errors + 1;
                end
            end
        end
        $display("  beat0 word0  = %h  (x=%h)", beats[0][31:0],    vals[0]);
        $display("  beat1 word15 = %h  (x=%h)", beats[1][511:480], vals[31]);
        if (beat_last[0] !== 1'b0) begin $display("  FAIL beat0 tlast should be 0"); errors=errors+1; end
        if (beat_last[1] !== 1'b1) begin $display("  FAIL beat1 tlast should be 1"); errors=errors+1; end
        $display("  tlast: beat0=%0d beat1=%0d", beat_last[0], beat_last[1]);

        if (errors==0) $display("\nPASS: word order natural, operands aligned, tlast correct");
        else           $display("\nFAIL: %0d errors", errors);
        $finish;
    end
    initial begin #200000; $display("TIMEOUT (nbeat=%0d)", nbeat); $finish; end
endmodule
