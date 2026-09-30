// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

module jpeg_table_register_bank (
    // verilog_format: off -- preserve streamed entry and expanded table columns
    input  logic          clk_i,
    input  logic          write_i,
    input  logic [  3:0]  entry_kind_i,
    input  logic [  7:0]  entry_index_i,
    input  logic [ 31:0]  entry_data_i,
    input  logic [ 24:0]  entry_reciprocal_i,
    output logic [511:0]  quant_o,
    output logic [1599:0] reciprocal_o,
    output logic [191:0]  dc_code_o,
    output logic [ 59:0]  dc_length_o,
    output logic [4095:0] ac_code_o,
    output logic [1279:0] ac_length_o
    // verilog_format: on
);
  logic [ 511:0] s_quant_d;
  logic [1599:0] s_reciprocal_d;
  logic [ 191:0] s_dc_code_d;
  logic [  59:0] s_dc_len_d;
  logic [4095:0] s_ac_code_d;
  logic [1279:0] s_ac_len_d;
  logic s_quant_write, s_dc_write, s_ac_write;

  assign s_quant_write = write_i && (entry_kind_i < 4'd4) && (entry_index_i < 8'd64);
  assign s_dc_write = write_i && (entry_kind_i >= 4'd4) && (entry_kind_i < 4'd8) &&
      (entry_index_i < 8'd12);
  assign s_ac_write = write_i && (entry_kind_i >= 4'd8);

  always_comb begin
    s_quant_d      = quant_o;
    s_reciprocal_d = reciprocal_o;
    s_dc_code_d    = dc_code_o;
    s_dc_len_d     = dc_length_o;
    s_ac_code_d    = ac_code_o;
    s_ac_len_d     = ac_length_o;
    if (s_quant_write) begin
      s_quant_d[entry_index_i*8+:8]        = entry_data_i[7:0];
      s_reciprocal_d[entry_index_i*25+:25] = entry_reciprocal_i;
    end
    if (s_dc_write) begin
      s_dc_code_d[entry_index_i*16+:16] = entry_data_i[15:0];
      s_dc_len_d[entry_index_i*5+:5]    = entry_data_i[20:16];
    end
    if (s_ac_write) begin
      s_ac_code_d[entry_index_i*16+:16] = entry_data_i[15:0];
      s_ac_len_d[entry_index_i*5+:5]    = entry_data_i[20:16];
    end
  end

  dffl #(
      .DATA_WIDTH(512)
  ) u_quant_dffl (
      .clk_i(clk_i),
      .en_i (s_quant_write),
      .dat_i(s_quant_d),
      .dat_o(quant_o)
  );
  dffl #(
      .DATA_WIDTH(1600)
  ) u_reciprocal_dffl (
      .clk_i(clk_i),
      .en_i (s_quant_write),
      .dat_i(s_reciprocal_d),
      .dat_o(reciprocal_o)
  );
  dffl #(
      .DATA_WIDTH(192)
  ) u_dc_code_dffl (
      .clk_i(clk_i),
      .en_i (s_dc_write),
      .dat_i(s_dc_code_d),
      .dat_o(dc_code_o)
  );
  dffl #(
      .DATA_WIDTH(60)
  ) u_dc_length_dffl (
      .clk_i(clk_i),
      .en_i (s_dc_write),
      .dat_i(s_dc_len_d),
      .dat_o(dc_length_o)
  );
  dffl #(
      .DATA_WIDTH(4096)
  ) u_ac_code_dffl (
      .clk_i(clk_i),
      .en_i (s_ac_write),
      .dat_i(s_ac_code_d),
      .dat_o(ac_code_o)
  );
  dffl #(
      .DATA_WIDTH(1280)
  ) u_ac_length_dffl (
      .clk_i(clk_i),
      .en_i (s_ac_write),
      .dat_i(s_ac_len_d),
      .dat_o(ac_length_o)
  );
endmodule
