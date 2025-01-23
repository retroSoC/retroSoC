module tc_sram_1024x32 (
    input             clk_i,
    input             cs_i,
    input      [ 9:0] addr_i,
    input      [31:0] data_i,
    input      [ 3:0] mask_i,
    input             wren_i,
    output reg [31:0] data_o
);

  wire [15:0] s_rd_data_mem1, s_rd_data_mem2;
  assign data_o = {s_rd_data_mem2, s_rd_data_mem1};

  RM_IHPSG13_1P_1024x16_c2_bm_bist u_mem1 (
      .A_CLK      (clk_i),
      .A_ADDR     (addr_i[9:0]),
      .A_BM       ({{8{mask_i[1]}}, {8{mask_i[0]}}}),
      .A_MEN      (cs_i),
      .A_WEN      (wren_i),
      .A_REN      (~wren_i),
      .A_DIN      (data_i[15:0]),
      .A_DOUT     (s_rd_data_mem1),
      .A_BIST_CLK (1'b0),
      .A_BIST_ADDR(10'd0),
      .A_BIST_DIN (16'd0),
      .A_BIST_BM  (16'd0),
      .A_BIST_MEN (1'b0),
      .A_BIST_WEN (1'b0),
      .A_BIST_REN (1'b0),
      .A_BIST_EN  (1'b0),
      .A_DLY      (1'b0)
  );

  RM_IHPSG13_1P_1024x16_c2_bm_bist u_mem2 (
      .A_CLK      (clk_i),
      .A_ADDR     (addr_i[9:0]),
      .A_BM       ({{8{mask_i[3]}}, {8{mask_i[2]}}}),
      .A_MEN      (cs_i),
      .A_WEN      (wren_i),
      .A_REN      (~wren_i),
      .A_DIN      (data_i[31:16]),
      .A_DOUT     (s_rd_data_mem2),
      .A_BIST_CLK (1'b0),
      .A_BIST_ADDR(10'd0),
      .A_BIST_DIN (16'd0),
      .A_BIST_BM  (16'd0),
      .A_BIST_MEN (1'b0),
      .A_BIST_WEN (1'b0),
      .A_BIST_REN (1'b0),
      .A_BIST_EN  (1'b0),
      .A_DLY      (1'b0)
  );
endmodule
