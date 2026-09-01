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
  for (genvar index = 0; index < 64; index++) begin : gen_quant_entry
    dffl #(
        .DATA_WIDTH(8)
    ) u_quant_dffl (
        .clk_i(clk_i),
        .en_i (write_i && (entry_kind_i < 4'd4) && (entry_index_i == 8'(index))),
        .dat_i(entry_data_i[7:0]),
        .dat_o(quant_o[index*8+:8])
    );
    dffl #(
        .DATA_WIDTH(25)
    ) u_reciprocal_dffl (
        .clk_i(clk_i),
        .en_i (write_i && (entry_kind_i < 4'd4) && (entry_index_i == 8'(index))),
        .dat_i(entry_reciprocal_i),
        .dat_o(reciprocal_o[index*25+:25])
    );
  end

  for (genvar index = 0; index < 12; index++) begin : gen_dc_entry
    dffl #(
        .DATA_WIDTH(16)
    ) u_code_dffl (
        .clk_i(clk_i),
        .en_i (write_i && (entry_kind_i >= 4'd4) && (entry_kind_i < 4'd8) &&
               (entry_index_i == 8'(index))),
        .dat_i(entry_data_i[15:0]),
        .dat_o(dc_code_o[index*16+:16])
    );
    dffl #(
        .DATA_WIDTH(5)
    ) u_length_dffl (
        .clk_i(clk_i),
        .en_i (write_i && (entry_kind_i >= 4'd4) && (entry_kind_i < 4'd8) &&
               (entry_index_i == 8'(index))),
        .dat_i(entry_data_i[20:16]),
        .dat_o(dc_length_o[index*5+:5])
    );
  end

  for (genvar index = 0; index < 256; index++) begin : gen_ac_entry
    dffl #(
        .DATA_WIDTH(16)
    ) u_code_dffl (
        .clk_i(clk_i),
        .en_i (write_i && (entry_kind_i >= 4'd8) && (entry_index_i == 8'(index))),
        .dat_i(entry_data_i[15:0]),
        .dat_o(ac_code_o[index*16+:16])
    );
    dffl #(
        .DATA_WIDTH(5)
    ) u_length_dffl (
        .clk_i(clk_i),
        .en_i (write_i && (entry_kind_i >= 4'd8) && (entry_index_i == 8'(index))),
        .dat_i(entry_data_i[20:16]),
        .dat_o(ac_length_o[index*5+:5])
    );
  end
endmodule
