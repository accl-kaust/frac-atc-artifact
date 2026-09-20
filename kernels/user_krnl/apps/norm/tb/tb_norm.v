`timescale 1ns/1ps
// Testbench for norm. Uses tb/fp_stubs.v in place of the Xilinx cores.
//   iverilog -g2012 -s tb_norm -o tb.vvp tb/tb_norm.v tb/fp_stubs.v src/rtl/norm.v && vvp tb.vvp
module tb_norm;
    reg clk=0, rst=1; always #5 clk = ~clk;
    reg  [511:0] s_tdata; reg s_tvalid=0, s_tlast=0; wire s_tready;
    wire [511:0] m_tdata; wire m_tvalid, m_tlast; reg m_tready=1;

    norm dut (.clk(clk), .rst(rst),
        .s_axis_tdata(s_tdata), .s_axis_tkeep({64{1'b1}}), .s_axis_tstrb({64{1'b1}}),
        .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready), .s_axis_tlast(s_tlast),
        .s_axis_tdest(3'd2), .s_axis_tid(4'd7), .s_axis_tuser(1'b0),
        .m_axis_tdata(m_tdata), .m_axis_tkeep(), .m_axis_tstrb(),
        .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready), .m_axis_tlast(m_tlast),
        .m_axis_tdest(), .m_axis_tid(), .m_axis_tuser());

    // same IEEE-754 ordering key the DUT uses
    function [31:0] fkey(input [31:0] f); fkey = f[31] ? ~f : (f | 32'h80000000); endfunction

    reg [511:0] beats [0:1]; reg beat_last [0:1];
    integer nbeat=0, errors=0, i, b;
    reg [31:0] vals [0:31];
    reg [31:0] vmin, vmax, vrange, expect_w;
    reg [511:0] hdr, ln;

    always @(posedge clk) if (m_tvalid && m_tready) begin
        beats[nbeat] <= m_tdata; beat_last[nbeat] <= m_tlast; nbeat <= nbeat + 1; end

    task send(input [511:0] d, input last);
    begin @(negedge clk); while(!s_tready) @(negedge clk);
          s_tdata=d; s_tvalid=1; s_tlast=last; @(negedge clk); s_tvalid=0; s_tlast=0; end
    endtask

    initial begin
        // mixed-sign IEEE-754 values, so the ordering trick is actually exercised
        vals[0]=32'h3F800000; vals[1]=32'hBF800000; vals[2]=32'h40000000; vals[3]=32'hC0000000;
        vals[4]=32'h3F000000; vals[5]=32'hBF000000; vals[6]=32'h3E800000; vals[7]=32'hBE800000;
        vals[8]=32'h40400000; vals[9]=32'hC0400000; vals[10]=32'h3DCCCCCD;vals[11]=32'hBDCCCCCD;
        vals[12]=32'h41200000;vals[13]=32'hC1200000;vals[14]=32'h00000000;vals[15]=32'h3F400000;
        for (i=16;i<32;i=i+1) vals[i] = vals[i-16] ^ 32'h00000001;

        // reference min/max over all 32
        vmin = vals[0]; vmax = vals[0];
        for (i=1;i<32;i=i+1) begin
            if (fkey(vals[i]) > fkey(vmax)) vmax = vals[i];
            if (fkey(vals[i]) < fkey(vmin)) vmin = vals[i];
        end
        vrange = vmax - vmin;                      // stub subtract

        hdr = 512'd0; hdr[447:0] = {448{1'b1}}; hdr[495:480] = 16'hffff;
        repeat(4) @(negedge clk); rst=0; repeat(2) @(negedge clk);

        send(hdr, 1'b0);
        for (i=0;i<16;i=i+1) ln[i*32 +: 32] = vals[i];    send(ln, 1'b0);
        for (i=0;i<16;i=i+1) ln[i*32 +: 32] = vals[16+i]; send(ln, 1'b1);

        wait (nbeat == 2); repeat(2) @(posedge clk); #1;

        $display("TEST  min-max normalisation, 2 lines x 16 mixed-sign values");
        $display("  reference  min=%h  max=%h  range=%h", vmin, vmax, vrange);
        $display("  dut        min=%h  max=%h  range=%h", dut.min_val, dut.max_val, dut.range);
        if (dut.min_val !== vmin) begin $display("  FAIL min"); errors=errors+1; end
        if (dut.max_val !== vmax) begin $display("  FAIL max"); errors=errors+1; end
        if (dut.range   !== vrange) begin $display("  FAIL range"); errors=errors+1; end

        for (b=0;b<2;b=b+1) for (i=0;i<16;i=i+1) begin
            // stub chain: sub gives (x - min); div concatenates it with range
            expect_w[31:16] = (vals[b*16+i] - vmin);
            expect_w[15:0]  = vrange;
            if (beats[b][i*32 +: 32] !== expect_w) begin
                $display("  FAIL beat %0d word %2d: got %h want %h (x=%h)",
                         b, i, beats[b][i*32 +: 32], expect_w, vals[b*16+i]);
                errors = errors + 1;
            end
        end
        if (beat_last[0] !== 1'b0 || beat_last[1] !== 1'b1) begin
            $display("  FAIL tlast: beat0=%0d beat1=%0d", beat_last[0], beat_last[1]); errors=errors+1; end
        $display("  tlast: beat0=%0d beat1=%0d", beat_last[0], beat_last[1]);

        if (errors==0) $display("\nPASS: min/max over both signs, range constant, word order natural");
        else           $display("\nFAIL: %0d errors", errors);
        $finish;
    end
    initial begin #400000; $display("TIMEOUT (nbeat=%0d)", nbeat); $finish; end
endmodule
