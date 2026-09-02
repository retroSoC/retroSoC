// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module onchip_ram_formal;
  (* anyseq *) (* gclk *)reg          clk_i;
  logic        rst_n_i;
  logic        f_past_valid;
  logic        awvalid;
  logic        awready;
  logic [31:0] awaddr;
  logic [ 7:0] awlen;
  logic [ 2:0] awsize;
  logic [ 1:0] awburst;
  logic        wvalid;
  logic        wready;
  logic [31:0] wdata;
  logic [ 3:0] wstrb;
  logic        wlast;
  logic        bvalid;
  logic        bready;
  logic [ 1:0] bresp;
  logic        arvalid;
  logic        arready;
  logic [31:0] araddr;
  logic [ 7:0] arlen;
  logic [ 2:0] arsize;
  logic [ 1:0] arburst;
  logic        rvalid;
  logic        rready;
  logic [31:0] rdata;
  logic [ 1:0] rresp;
  logic        rlast;
  logic        memory_read;
  logic        memory_write;
  logic [14:0] memory_word_addr;
  logic [ 3:0] memory_write_strobe;
  logic [ 4:0] s_read_beat_count_q;
  logic [ 4:0] s_write_beat_count_q;

  onchip_ram_formal_design u_design (.*);

  always @(posedge clk_i) begin
    if (!rst_n_i) begin
      s_read_beat_count_q  <= '0;
      s_write_beat_count_q <= '0;
    end else begin
      if (arvalid && arready) s_read_beat_count_q <= '0;
      else if (rvalid && rready) s_read_beat_count_q <= s_read_beat_count_q + 1'b1;
      if (awvalid && awready) s_write_beat_count_q <= '0;
      else if (wvalid && wready) s_write_beat_count_q <= s_write_beat_count_q + 1'b1;
    end

    if (f_past_valid && $past(rst_n_i)) begin
      if ($past(awvalid && !awready)) begin
        assume (awvalid);
        assume (awaddr == $past(awaddr));
        assume (awlen == $past(awlen));
        assume (awsize == $past(awsize));
        assume (awburst == $past(awburst));
      end
      if ($past(wvalid && !wready)) begin
        assume (wvalid);
        assume (wdata == $past(wdata));
        assume (wstrb == $past(wstrb));
        assume (wlast == $past(wlast));
      end
      if ($past(arvalid && !arready)) begin
        assume (arvalid);
        assume (araddr == $past(araddr));
        assume (arlen == $past(arlen));
        assume (arsize == $past(arsize));
        assume (arburst == $past(arburst));
      end
      if ($past(bvalid && !bready)) begin
        assert (bvalid);
        assert (bresp == $past(bresp));
      end
      if ($past(rvalid && !rready)) begin
        assert (rvalid);
        assert (rdata == $past(rdata));
        assert (rresp == $past(rresp));
        assert (rlast == $past(rlast));
      end
    end

    if (rst_n_i) begin
      assert (!((awvalid && awready) && (arvalid && arready)));
      assert (!(memory_read && memory_write));
      assert (s_read_beat_count_q <= 5'd16);
      assert (s_write_beat_count_q <= 5'd16);
      if (memory_write) begin
        assert (wvalid && wready);
        assert (memory_write_strobe != 4'd0);
      end
      if (rlast && rvalid) assert (s_read_beat_count_q <= 5'd15);
      if (bvalid) assert (s_write_beat_count_q <= 5'd16);

      cover (arvalid && arready && (arlen == 8'd3));
      cover (rvalid && rready && rlast && (rresp == 2'b00));
      cover (awvalid && awready && (awlen == 8'd3));
      cover (memory_write && (memory_write_strobe == 4'hF));
      cover (bvalid && bready && (bresp == 2'b00));
      cover (rvalid && rready && (rresp == 2'b11));
    end
  end
endmodule
