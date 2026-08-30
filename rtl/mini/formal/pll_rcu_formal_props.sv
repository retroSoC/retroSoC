// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module pll_rcu_formal;

  localparam [3:0] PLL_APPLY = 4'd4;
  localparam [3:0] PLL_WAIT_LOCK_LOW = 4'd5;
  localparam [3:0] PLL_QUALIFY_LOCK = 4'd6;
  localparam [3:0] PLL_SWITCH = 4'd7;
  localparam [3:0] PLL_RESTORE_LP = 4'd8;
  localparam [3:0] PLL_RESPOND = 4'd9;
  localparam [3:0] PLL_FAIL_SAFE = 4'd10;

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
  wire [3:0] state;
  wire       pll_apply;
  wire       select_ext_clk;
  wire       active_valid;
  wire       safe_clk;
  wire       active_lock;
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
      .error         (error)
  );

  always @(posedge clk_i) begin
    if (f_past_valid && $past(rst_n_i && req_valid && !req_ready)) begin
      assume (req_valid);
      assume (req_sel == $past(req_sel));
    end

    if (rst_n_i) begin
      assert (!(state == PLL_APPLY || state == PLL_WAIT_LOCK_LOW ||
                state == PLL_QUALIFY_LOCK) || (select_ext_clk && safe_clk));
      assert (!(state == PLL_APPLY || state == PLL_WAIT_LOCK_LOW ||
                state == PLL_QUALIFY_LOCK) ||
              (error == 2'd0 && !active_valid && !active_lock));
      assert (!pll_apply || state == PLL_WAIT_LOCK_LOW);
      if (state == PLL_SWITCH) begin
        assert (active_valid);
        assert (select_ext_clk);
        assert (safe_clk);
        assert (active_lock);
        assert (error == 2'd0);
      end
      if (f_past_valid && $past(state == PLL_SWITCH)) begin
        assert (state == PLL_RESTORE_LP);
        assert (!select_ext_clk);
        assert (!safe_clk);
      end
      if (f_past_valid && $past(state == PLL_FAIL_SAFE)) begin
        assert (state == PLL_RESPOND);
        assert (select_ext_clk);
        assert (safe_clk);
        assert (!active_valid);
        assert (!active_lock);
      end
      cover (state == PLL_SWITCH && active_valid && active_lock);
      cover (state == PLL_RESPOND && error == 2'd1);
      cover (state == PLL_RESPOND && error == 2'd2);
    end
  end

endmodule
