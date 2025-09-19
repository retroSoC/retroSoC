module i2s_recv (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        sclk_pos_i,
    input  logic        lrck_i,
    input  logic        adcdat_i,
    output logic [15:0] data_o,
    output logic        done_o

);

  logic s_lrck_dely_d, s_lrck_dely_q;
  logic s_lrck_trg;
  logic [4:0] s_bit_cnt_d, s_bit_cnt_q;
  logic [15:0] s_recv_data_d, s_recv_data_q;
  logic [15:0] s_data_d, s_data_q;
  logic s_done_d, s_done_q;

  assign data_o        = s_data_q;
  assign done_o        = s_done_q;
  assign s_lrck_trg    = lrck_i ^ s_lrck_dely_q;

  assign s_lrck_dely_d = lrck_i;
  dffer #(1) u_lrck_dely_dffer (
      clk_i,
      rst_n_i,
      sclk_pos_i,
      s_lrck_dely_d,
      s_lrck_dely_q
  );


  // 0-15
  always_comb begin
    s_bit_cnt_d = s_bit_cnt_q;
    if (s_lrck_trg) s_bit_cnt_d = '0;
    else if (s_bit_cnt_q < 5'd16) begin
      s_bit_cnt_d = s_bit_cnt_q + 1'b1;
    end
  end
  dffer #(5) u_bit_cnt_dffer (
      clk_i,
      rst_n_i,
      sclk_pos_i,
      s_bit_cnt_d,
      s_bit_cnt_q
  );


  always_comb begin
    s_recv_data_d = s_recv_data_q;
    if (s_bit_cnt_q <= 5'd15) begin
      s_recv_data_d[15-s_bit_cnt_q] = adcdat_i;
    end
  end
  dffer #(16) u_recv_data_dffer (
      clk_i,
      rst_n_i,
      sclk_pos_i,
      s_recv_data_d,
      s_recv_data_q
  );


  assign s_data_d = s_bit_cnt_q == 5'd16 ? s_recv_data_q : s_data_q;
  dffer #(16) u_data_dffer (
      clk_i,
      rst_n_i,
      sclk_pos_i,
      s_data_d,
      s_data_q
  );


  assign s_done_d = s_bit_cnt_q == 5'd16;
  dffer #(1) u_done_dffer (
      clk_i,
      rst_n_i,
      sclk_pos_i,
      s_done_d,
      s_done_q
  );

endmodule
