// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module clint_formal;

  (* anyseq *) (* gclk *)reg         clk_i;
  wire        rst_n_i;
  wire        f_past_valid;
  wire        rib_valid;
  wire [31:0] rib_addr;
  wire [31:0] rib_wdata;
  wire [ 3:0] rib_wstrb;
  wire        rib_ready;
  wire        rib_resp_err;
  wire        tick;
  wire [63:0] mtime;
  wire        mtime_load;
  wire [63:0] mtime_load_value;
  wire [ 1:0] msip;
  wire [ 1:0] timer_irq_next;
  wire [ 1:0] timer_irq;

  clint_formal_design u_design (.*);

  always @(posedge clk_i) begin
    if (f_past_valid && $past(rst_n_i && rib_valid && !rib_ready)) begin
      assume (rib_valid);
      assume (rib_addr == $past(rib_addr));
      assume (rib_wdata == $past(rib_wdata));
      assume (rib_wstrb == $past(rib_wstrb));
    end

    if (f_past_valid && !$past(rst_n_i)) begin
      assert (mtime == 64'd0);
      assert (msip == 2'b00);
      assert (timer_irq == 2'b00);
    end

    if (rst_n_i) begin
      if (f_past_valid && $past(rst_n_i && rib_valid && !rib_ready)) begin
        assert (rib_ready);
      end
      if (f_past_valid && $past(rst_n_i)) begin
        assert (timer_irq == $past(timer_irq_next));
        if ($past(mtime_load)) begin
          assert (mtime == $past(mtime_load_value));
        end else if ($past(tick)) begin
          assert (mtime == $past(mtime) + 64'd1);
        end else begin
          assert (mtime == $past(mtime));
        end
      end

      cover (msip[0]);
      cover (timer_irq[0]);
      cover (rib_ready && rib_resp_err);
      cover (mtime_load);
    end
  end

endmodule
