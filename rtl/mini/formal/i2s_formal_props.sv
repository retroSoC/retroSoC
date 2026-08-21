// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module i2s_formal;
  (* anyseq *) (* gclk *) reg clk_i;
  logic rst_n_i, f_past_valid, rib_valid, rib_ready, rib_resp_err, irq;
  logic [31:0] rib_addr, rib_wdata;
  logic [3:0] rib_wstrb;
  logic [3:0] intr_state, intr_enable;
  i2s_formal_design u_design (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .f_past_valid(f_past_valid),
      .rib_valid   (rib_valid),
      .rib_addr    (rib_addr),
      .rib_wdata   (rib_wdata),
      .rib_wstrb   (rib_wstrb),
      .rib_ready   (rib_ready),
      .rib_resp_err(rib_resp_err),
      .intr_state  (intr_state),
      .intr_enable (intr_enable),
      .irq         (irq)
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
      cover (rib_resp_err);
      cover (irq);
    end
  end
endmodule
