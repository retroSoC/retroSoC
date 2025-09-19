

module i2s_send (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        sclk_pos_i,
    input  logic        sclk_fall_i,
    input  logic        lrck_i,
    input  logic [15:0] data_i,
    output logic        dacdat_o,
    output logic        done_o
);

  logic s_lrck_dely_d, s_lrck_dely_q;
  logic s_lrck_trg;
  logic [4:0] s_bit_cnt_d, s_bit_cnt_q;
  logic [15:0] s_xfer_data_d, s_xfer_data_q;
  logic s_dacdat_d, s_dacdat_q;

  assign dacdat_o      = s_dacdat_q;
  assign done_o        = s_bit_cnt_q == 5'd15;
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
    else if (s_bit_cnt_q < 5'd15) begin
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


  assign s_xfer_data_d = s_lrck_trg ? data_i : s_xfer_data_q;
  dffer #(16) u_xfer_data_dffer (
      clk_i,
      rst_n_i,
      sclk_pos_i,
      s_xfer_data_d,
      s_xfer_data_q
  );


  assign s_dacdat_d = s_bit_cnt_q <= 5'd15 ? s_xfer_data_q[15-s_bit_cnt_q] : s_dacdat_q;
  dffer #(1) u_dacdat_dffer (
      clk_i,
      rst_n_i,
      sclk_fall_i,
      s_dacdat_d,
      s_dacdat_q
  );

endmodule
