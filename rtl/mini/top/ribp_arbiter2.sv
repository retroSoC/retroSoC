// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// See LICENSE for the complete license text.

module ribp_arbiter2 (
    input logic          clk_i,
    input logic          rst_n_i,
          ribp_if.slave  cfg,
          ribp_if.slave  data,
          ribp_if.master target
);
  logic s_locked_d, s_locked_q;
  logic s_owner_d, s_owner_q;
  logic s_select_data;

  assign s_select_data = s_locked_q ? s_owner_q : (!cfg.valid && data.valid);

  assign target.valid  = s_select_data ? data.valid : cfg.valid;
  assign target.addr   = s_select_data ? data.addr : cfg.addr;
  assign target.wdata  = s_select_data ? data.wdata : cfg.wdata;
  assign target.wstrb  = s_select_data ? data.wstrb : cfg.wstrb;

  assign cfg.ready     = !s_select_data && target.ready;
  assign cfg.rdata     = target.rdata;
  assign cfg.resp_err  = target.resp_err;
  assign data.ready    = s_select_data && target.ready;
  assign data.rdata    = target.rdata;
  assign data.resp_err = target.resp_err;

  always_comb begin
    s_locked_d = s_locked_q;
    s_owner_d  = s_owner_q;
    if (!s_locked_q && target.valid && !target.ready) begin
      s_locked_d = 1'b1;
      s_owner_d  = s_select_data;
    end else if (s_locked_q && target.ready) begin
      s_locked_d = 1'b0;
    end
  end

  dffr #(1) u_locked_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_locked_d),
      .dat_o  (s_locked_q)
  );

  dffr #(1) u_owner_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_owner_d),
      .dat_o  (s_owner_q)
  );
endmodule
