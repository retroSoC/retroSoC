// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module gpio_user_formal;

  (* anyseq *) (* gclk *)reg         clk_i;
  wire        rst_n_i;
  wire        f_past_valid;
  wire        rib_valid;
  wire [31:0] rib_addr;
  wire [31:0] rib_wdata;
  wire [ 3:0] rib_wstrb;
  wire        rib_ready;
  wire [31:0] gpio_di;
  wire [31:0] gpio_oe;
  wire [31:0] gpio_do;
  wire [31:0] user_di;
  wire [31:0] user_oe;
  wire [31:0] user_do;
  wire [31:0] user_sel;
  wire [31:0] user_lock;
  wire [31:0] user_handoff;
  wire [31:0] user_status;
  wire [31:0] native_oe;
  wire [31:0] native_do;

  gpio_user_formal_design u_design (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .f_past_valid(f_past_valid),
      .rib_valid   (rib_valid),
      .rib_addr    (rib_addr),
      .rib_wdata   (rib_wdata),
      .rib_wstrb   (rib_wstrb),
      .rib_ready   (rib_ready),
      .gpio_di     (gpio_di),
      .gpio_oe     (gpio_oe),
      .gpio_do     (gpio_do),
      .user_di     (user_di),
      .user_oe     (user_oe),
      .user_do     (user_do),
      .user_sel    (user_sel),
      .user_lock   (user_lock),
      .user_handoff(user_handoff),
      .user_status (user_status),
      .native_oe   (native_oe),
      .native_do   (native_do)
  );

  always @(posedge clk_i) begin
    if (f_past_valid && $past(rst_n_i && rib_valid && !rib_ready)) begin
      assume (rib_valid);
      assume (rib_addr == $past(rib_addr));
      assume (rib_wdata == $past(rib_wdata));
      assume (rib_wstrb == $past(rib_wstrb));
    end

    if (rst_n_i) begin
      assert (user_di == gpio_di);
      assert(gpio_oe == ((~user_handoff & user_sel & user_oe) |
                         (~user_handoff & ~user_sel & native_oe)));
      assert (gpio_do == ((user_sel & user_do) | (~user_sel & native_do)));
      assert (user_status == (user_sel & ~user_handoff));
      if (f_past_valid) begin
        assert (user_handoff == (user_sel ^ $past(user_sel)));
        if ($past(user_lock)) begin
          assert (user_lock);
          assert ((user_sel & $past(user_lock)) == ($past(user_sel) & $past(user_lock)));
        end
      end
      cover (|user_handoff);
      cover (|user_lock && |user_sel);
      cover (|user_status && |gpio_oe);
    end
  end

endmodule
