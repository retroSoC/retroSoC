// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module apu_formal;
  (* anyseq *) (* gclk *) reg clk_i;
  wire rst_n_i, f_past_valid;
  wire [2:0] scenario;
  wire [5:0] cycle;
  wire busy, done, error, aborted;
  wire [5:0] error_code;
  wire [63:0] read_bytes, write_bytes;
  wire terminal_seen, terminal_error, terminal_aborted;
  wire [5:0] terminal_code;
  wire awvalid, awready, wvalid, wready, wlast, bvalid, bready;
  wire arvalid, arready, rvalid, rready, rlast;
  wire [31:0] awaddr, araddr;
  wire [7:0] awlen, arlen;
  wire [2:0] awsize, arsize;
  wire [1:0] awburst, arburst;
  wire [3:0] awcache, arcache, wstrb;
  wire [2:0] awprot, arprot;

  apu_formal_design u_design (.*);

  always @(posedge clk_i) begin
    if (rst_n_i) begin
      assume (scenario <= 3'd5);
      assert (!(awvalid && arvalid));
      if (awvalid) begin
        assert (awlen < 8'd16);
        assert (awsize == 3'd2);
        assert (awburst == 2'd1);
        assert (awcache == 4'd0);
        assert (awprot[2] == 1'b0);
        assert ({1'b0, awaddr[11:0]} + (({5'd0, awlen} + 1'b1) << awsize) <= 13'd4096);
      end
      if (arvalid) begin
        assert (arlen < 8'd16);
        assert (arsize == 3'd2);
        assert (arburst == 2'd1);
        assert (arcache == 4'd0);
        assert (arprot[2] == 1'b0);
        assert ({1'b0, araddr[11:0]} + (({5'd0, arlen} + 1'b1) << arsize) <= 13'd4096);
      end
      if (wvalid) assert (wstrb != 4'd0);
      if (done) begin
        if (scenario == 3'd0) assert (!error && !aborted && (read_bytes == 64'd8));
        if (scenario == 3'd1) assert (!error && !aborted && (write_bytes == 64'd8));
        if (scenario == 3'd2) assert (error && !aborted && (error_code == 6'd17));
        if (scenario == 3'd3) assert (!error && aborted && (error_code == 6'd20));
        if (scenario == 3'd4) assert (!error && !aborted && (read_bytes == 64'd8));
        if (scenario == 3'd5) assert (error && !aborted && (error_code == 6'd15));
      end
      if (cycle >= 6'd20) begin
        assert (terminal_seen);
        if (scenario == 3'd2) assert (terminal_error && (terminal_code == 6'd17));
        if (scenario == 3'd3)
          assert (!terminal_error && terminal_aborted && (terminal_code == 6'd20));
        if (scenario == 3'd4) assert (!terminal_error && !terminal_aborted);
        if (scenario == 3'd5) assert (terminal_error && (terminal_code == 6'd15));
      end
    end
    if (f_past_valid && $past(rst_n_i)) begin
      if ($past(awvalid && !awready)) begin
        assert (awvalid);
        assert (awaddr == $past(awaddr));
        assert (awlen == $past(awlen));
      end
      if ($past(arvalid && !arready)) begin
        assert (arvalid);
        assert (araddr == $past(araddr));
        assert (arlen == $past(arlen));
      end
      if ($past(wvalid && !wready)) begin
        assert (wvalid);
        assert (wstrb == $past(wstrb));
        assert (wlast == $past(wlast));
      end
      if ($past(bvalid && !bready)) assert (bvalid);
      if ($past(rvalid && !rready)) begin
        assert (rvalid);
        assert (rlast == $past(rlast));
      end
    end

    cover (rst_n_i && done && (scenario == 3'd0));
    cover (rst_n_i && done && (scenario == 3'd1));
    cover (rst_n_i && done && (scenario == 3'd2));
    cover (rst_n_i && done && (scenario == 3'd3));
    cover (rst_n_i && done && (scenario == 3'd4));
    cover (rst_n_i && done && (scenario == 3'd5));
  end
endmodule
