// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module gpio_formal;

  (* anyseq *) (* gclk *)reg         clk_i;
  wire        rst_n_i;
  wire        f_past_valid;
  wire        ribp_valid;
  wire        ribp_ready;
  wire        ribp_resp_err;
  wire [31:0] ribp_addr;
  wire [31:0] ribp_wdata;
  wire [ 3:0] ribp_wstrb;
  wire [ 3:0] gpio_oe;
  wire [ 3:0] gpio_do;
  wire [ 3:0] user_oe;
  wire [ 3:0] user_do;
  wire [ 3:0] user_select;
  wire [ 3:0] user_lock;
  wire [ 3:0] user_handoff;
  wire [ 3:0] user_access;
  wire [ 3:0] config_lock;
  wire [ 3:0] data_out;
  wire [ 3:0] output_enable;
  wire [ 3:0] open_drain;
  wire [ 3:0] selected_data;
  wire [ 3:0] intr_state;
  wire        irq;

  gpio_formal_design u_design (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .f_past_valid (f_past_valid),
      .ribp_valid   (ribp_valid),
      .ribp_ready   (ribp_ready),
      .ribp_resp_err(ribp_resp_err),
      .ribp_addr    (ribp_addr),
      .ribp_wdata   (ribp_wdata),
      .ribp_wstrb   (ribp_wstrb),
      .gpio_oe      (gpio_oe),
      .gpio_do      (gpio_do),
      .user_oe      (user_oe),
      .user_do      (user_do),
      .user_select  (user_select),
      .user_lock    (user_lock),
      .user_handoff (user_handoff),
      .user_access  (user_access),
      .config_lock  (config_lock),
      .data_out     (data_out),
      .output_enable(output_enable),
      .open_drain   (open_drain),
      .selected_data(selected_data),
      .intr_state   (intr_state),
      .irq          (irq)
  );

  always @(posedge clk_i) begin
    if (f_past_valid && $past(rst_n_i && ribp_valid && !ribp_ready)) begin
      assume (ribp_valid);
      assume (ribp_addr == $past(ribp_addr));
      assume (ribp_wdata == $past(ribp_wdata));
      assume (ribp_wstrb == $past(ribp_wstrb));
    end

    if (rst_n_i) begin
      assert ((gpio_oe & user_handoff) == 4'd0);
      assert ((gpio_do & open_drain) == 4'd0);
      assert ((gpio_oe & open_drain & selected_data) == 4'd0);
      if (f_past_valid) begin
        assert (user_handoff == (user_select ^ $past(user_select)));
        assert ((user_lock & $past(user_lock)) == $past(user_lock));
        assert ((config_lock & $past(config_lock)) == $past(config_lock));
        assert ((user_select & $past(user_lock)) == ($past(user_select) & $past(user_lock)));
        if ($past(ribp_valid && !ribp_ready && (ribp_addr[31:12] == 20'h10000))) begin
          assert ((data_out & ~$past(user_access)) == ($past(data_out) & ~$past(user_access)));
          assert (user_access == $past(user_access));
          assert (config_lock == $past(config_lock));
        end
      end
      cover (|user_handoff);
      cover (|user_lock && |user_select);
      cover (irq && |intr_state);
      cover (ribp_ready && ribp_resp_err);
    end
  end

endmodule
