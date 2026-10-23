// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module dvp_formal;
  (* anyseq *) (* gclk *) reg clk_i;
  logic rst_n_i, f_past_valid, rib_valid, rib_ready, rib_resp_err, irq;
  logic [31:0] rib_addr, rib_wdata;
  logic [3:0] rib_wstrb;
  logic [6:0] intr_state, intr_enable;
  logic [6:0] event_set;
  logic cfg_pending, abort_accept;
  logic stats_valid;
  // Independent expected mailbox width; properties compile without RTL headers.
  logic [143:0] stats_input, stats_latched;
  dvp_formal_design u_design (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .f_past_valid (f_past_valid),
      .rib_valid    (rib_valid),
      .rib_addr     (rib_addr),
      .rib_wdata    (rib_wdata),
      .rib_wstrb    (rib_wstrb),
      .rib_ready    (rib_ready),
      .rib_resp_err (rib_resp_err),
      .intr_state   (intr_state),
      .intr_enable  (intr_enable),
      .irq          (irq),
      .cfg_pending  (cfg_pending),
      .abort_accept (abort_accept),
      .event_set    (event_set),
      .stats_input  (stats_input),
      .stats_latched(stats_latched),
      .stats_valid  (stats_valid)
  );
  always_ff @(posedge clk_i) begin
    if (rst_n_i) begin
      if (f_past_valid && $past(rst_n_i && rib_valid && !rib_ready)) begin
        assume (rib_valid);
        assume (rib_addr == $past(rib_addr));
        assume (rib_wdata == $past(rib_wdata));
        assume (rib_wstrb == $past(rib_wstrb));
        assert (rib_ready);
      end
      assert (irq == ((intr_state & intr_enable) != 0));
      if (f_past_valid && $past(rst_n_i))
        assert ((intr_state & $past(event_set)) == $past(event_set));
      if (f_past_valid && $past(rst_n_i && abort_accept)) assert (!cfg_pending);
      if (f_past_valid && $past(rst_n_i)) begin
        if ($past(stats_valid))
          assert (stats_latched == $past(stats_input));
          else assert (stats_latched == $past(stats_latched));
      end
      cover (stats_latched[111:80] == 32'd153600 && stats_latched[143:112] != 0);
      cover (cfg_pending && abort_accept);
      cover (rib_resp_err);
      cover (irq);
    end
  end
endmodule
