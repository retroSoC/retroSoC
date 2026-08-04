// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module pll_rcu_formal;

  localparam [2:0] PLL_IDLE = 3'd0;
  localparam [2:0] PLL_SAFE = 3'd1;
  localparam [2:0] PLL_APPLY = 3'd2;
  localparam [2:0] PLL_WAIT_LOCK = 3'd3;
  localparam [2:0] PLL_SWITCH = 3'd4;
  localparam [2:0] PLL_RESPOND = 3'd5;

  (* anyseq *) (* gclk *)reg        clk_i;
  wire       rst_n_i;
  wire       f_past_valid;
  wire       req_valid;
  wire [2:0] req_sel;
  wire       req_ready;
  wire       rsp_valid;
  wire       rsp_ready;
  wire       pll_lock;
  wire       pll_capable;
  wire [2:0] state;
  wire       pll_apply;
  wire       select_ext_clk;
  wire       active_valid;
  wire       safe_clk;
  wire       active_lock;
  wire       lock_seen_low;
  wire [1:0] error;

  pll_rcu_formal_design u_design (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .f_past_valid  (f_past_valid),
      .req_valid     (req_valid),
      .req_sel       (req_sel),
      .req_ready     (req_ready),
      .rsp_valid     (rsp_valid),
      .rsp_ready     (rsp_ready),
      .pll_lock      (pll_lock),
      .pll_capable   (pll_capable),
      .state         (state),
      .pll_apply     (pll_apply),
      .select_ext_clk(select_ext_clk),
      .active_valid  (active_valid),
      .safe_clk      (safe_clk),
      .active_lock   (active_lock),
      .lock_seen_low (lock_seen_low),
      .error         (error)
  );

  always @(posedge clk_i) begin
    if (f_past_valid && $past(rst_n_i && req_valid && !req_ready)) begin
      assume (req_valid);
      assume (req_sel == $past(req_sel));
    end

    if (rst_n_i) begin
      assert(!(state == PLL_SAFE || state == PLL_APPLY || state == PLL_WAIT_LOCK) ||
             select_ext_clk);
      assert (!pll_apply || state != PLL_IDLE && state != PLL_SAFE);
      if (f_past_valid && $past(state == PLL_SAFE && !pll_capable)) begin
        assert (state == PLL_RESPOND);
        assert (safe_clk);
        assert (!active_valid);
        assert (error == 2'd1);
      end
      if (f_past_valid && $past(state == PLL_WAIT_LOCK && pll_lock && lock_seen_low)) begin
        assert (state == PLL_SWITCH);
        assert (active_valid);
        assert (!safe_clk);
        assert (active_lock);
        assert (error == 2'd0);
      end
      if (f_past_valid && $past(state == PLL_SWITCH)) begin
        assert (state == PLL_RESPOND);
        assert (!select_ext_clk);
      end
      cover (state == PLL_SWITCH && active_valid && active_lock);
      cover (state == PLL_RESPOND && error == 2'd1);
      cover (state == PLL_RESPOND && error == 2'd2);
    end
  end

endmodule
