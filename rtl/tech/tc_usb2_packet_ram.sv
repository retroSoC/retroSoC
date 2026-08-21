// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module tc_usb2_packet_ram (
    input  logic        clk_i,
    input  logic        cs_i,
    input  logic        write_i,
    input  logic [11:0] addr_i,
    input  logic [39:0] data_i,
    output logic [39:0] data_o
);
`ifdef PDK_IHP130
  logic [15:0] s_data_low;
  logic [15:0] s_data_high;
  logic [ 7:0] s_data_ecc;

  RM_IHPSG13_1P_4096x16_c3_bm_bist u_data_low (
      .A_CLK      (clk_i),
      .A_MEN      (cs_i),
      .A_WEN      (write_i),
      .A_REN      (!write_i),
      .A_ADDR     (addr_i),
      .A_DIN      (data_i[15:0]),
      .A_DLY      (1'b0),
      .A_DOUT     (s_data_low),
      .A_BM       (16'hFFFF),
      .A_BIST_CLK (1'b0),
      .A_BIST_EN  (1'b0),
      .A_BIST_MEN (1'b0),
      .A_BIST_WEN (1'b0),
      .A_BIST_REN (1'b0),
      .A_BIST_ADDR(12'd0),
      .A_BIST_DIN (16'd0),
      .A_BIST_BM  (16'd0)
  );

  RM_IHPSG13_1P_4096x16_c3_bm_bist u_data_high (
      .A_CLK      (clk_i),
      .A_MEN      (cs_i),
      .A_WEN      (write_i),
      .A_REN      (!write_i),
      .A_ADDR     (addr_i),
      .A_DIN      (data_i[31:16]),
      .A_DLY      (1'b0),
      .A_DOUT     (s_data_high),
      .A_BM       (16'hFFFF),
      .A_BIST_CLK (1'b0),
      .A_BIST_EN  (1'b0),
      .A_BIST_MEN (1'b0),
      .A_BIST_WEN (1'b0),
      .A_BIST_REN (1'b0),
      .A_BIST_ADDR(12'd0),
      .A_BIST_DIN (16'd0),
      .A_BIST_BM  (16'd0)
  );

  RM_IHPSG13_1P_4096x8_c3_bm_bist u_ecc (
      .A_CLK      (clk_i),
      .A_MEN      (cs_i),
      .A_WEN      (write_i),
      .A_REN      (!write_i),
      .A_ADDR     (addr_i),
      .A_DIN      (data_i[39:32]),
      .A_DLY      (1'b0),
      .A_DOUT     (s_data_ecc),
      .A_BM       (8'hFF),
      .A_BIST_CLK (1'b0),
      .A_BIST_EN  (1'b0),
      .A_BIST_MEN (1'b0),
      .A_BIST_WEN (1'b0),
      .A_BIST_REN (1'b0),
      .A_BIST_ADDR(12'd0),
      .A_BIST_DIN (8'd0),
      .A_BIST_BM  (8'd0)
  );

  assign data_o = {s_data_ecc, s_data_high, s_data_low};
`else
  logic [39:0] s_memory[0:4095];
  always_ff @(posedge clk_i) begin
    if (cs_i) begin
      if (write_i) begin
        s_memory[addr_i] <= data_i;
      end else begin
        data_o <= s_memory[addr_i];
      end
    end
  end
`endif
endmodule
