module i2s_core (
    // verilog_format: off
    input logic    clk_i,
    input logic    rst_n_i,
    nv_i2s_if.dut i2s
    // verilog_format: on
);

  // clk_i / 8 / 32
  logic [1:0] s_sclk_div_cnt_d, s_sclk_div_cnt_q;
  logic s_sclk_d, s_sclk_q;
  logic [3:0] s_lrck_div_cnt_d, s_lrck_div_cnt_q;
  logic s_lrck_d, s_lrck_q;
  logic s_sclk_pos, s_sclk_fall;
  logic [15:0] s_tmp_dat;

  assign i2s.mclk_o  = clk_i;
  assign i2s.sclk_o  = s_sclk_q;
  assign i2s.lrck_o  = s_lrck_q;

  assign s_sclk_pos  = (~s_sclk_q) && (s_sclk_div_cnt_q == '0);
  assign s_sclk_fall = s_sclk_q && (s_sclk_div_cnt_q == '0);

  always_comb begin
    s_sclk_d = s_sclk_q;
    if (s_sclk_div_cnt_q == '0) begin
      s_sclk_div_cnt_d = '1;
      s_sclk_d         = ~s_sclk_q;
    end else begin
      s_sclk_div_cnt_d = s_sclk_div_cnt_q - 1'b1;
    end
  end
  dffrh #(2) u_sclk_div_cnt_dffrh (
      clk_i,
      rst_n_i,
      s_sclk_div_cnt_d,
      s_sclk_div_cnt_q
  );
  dffr #(1) u_sclk_dffr (
      clk_i,
      rst_n_i,
      s_sclk_d,
      s_sclk_q
  );


  always_comb begin
    s_lrck_d = s_lrck_q;
    if (s_lrck_div_cnt_q == '0) begin
      s_lrck_div_cnt_d = '1;
      s_lrck_d         = ~s_lrck_q;
    end else begin
      s_lrck_div_cnt_d = s_lrck_div_cnt_q - 1'b1;
    end
  end
  dfferh #(4) u_lrck_div_cnt_dfferh (
      clk_i,
      rst_n_i,
      s_sclk_fall,
      s_lrck_div_cnt_d,
      s_lrck_div_cnt_q
  );
  dffer #(1) u_lrck_dffer (
      clk_i,
      rst_n_i,
      s_sclk_fall,
      s_lrck_d,
      s_lrck_q
  );


  i2s_recv u_i2s_recv (
      .clk_i     (clk_i),
      .rst_n_i   (rst_n_i),
      .sclk_pos_i(s_sclk_pos),
      .lrck_i    (s_lrck_q),
      .adcdat_i  (i2s.adcdat_i),
      .data_o    (s_tmp_dat),
      .done_o    ()
  );

  i2s_send u_i2s_send (
      .clk_i      (clk_i),
      .rst_n_i    (rst_n_i),
      .sclk_pos_i (s_sclk_pos),
      .sclk_fall_i(s_sclk_fall),
      .lrck_i     (s_lrck_q),
      .data_i     (s_tmp_dat),
      .dacdat_o   (i2s.dacdat_o),
      .done_o     ()
  );




endmodule
