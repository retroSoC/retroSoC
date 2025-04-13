module tc_sram_1024x32 (
    input         clk_i,
    input         cs_i,
    input  [ 9:0] addr_i,
    input  [31:0] data_i,
    input  [ 3:0] mask_i,
    input         wren_i,
    output [31:0] data_o
);

`ifdef RTL_BEHAV
  reg [31:0] r_data;
  reg [31:0] mem    [0:1023];

  assign data_o = r_data;
  always @(posedge clk_i) begin
    if (cs_i) begin
      if (!wren_i) begin
        r_data <= mem[addr_i];
      end else begin
        if (mask_i[0]) mem[addr_i][7:0] <= data_i[7:0];
        if (mask_i[1]) mem[addr_i][15:8] <= data_i[15:8];
        if (mask_i[2]) mem[addr_i][23:16] <= data_i[23:16];
        if (mask_i[3]) mem[addr_i][31:24] <= data_i[31:24];
        r_data <= 32'bx;
      end
    end
  end
`else
  // wire [63:0] s_rd_data_mem;
  // assign data_o = s_rd_data_mem[31:0];
  // RM_IHPSG13_1P_1024x64_c2_bm_bist u_mem (
  //     .A_CLK      (clk_i),
  //     .A_ADDR     (addr_i),
  //     .A_BM       ({32'h0, {8{mask_i[3]}}, {8{mask_i[2]}}, {8{mask_i[1]}}, {8{mask_i[0]}}}),
  //     .A_MEN      (cs_i),
  //     .A_WEN      (wren_i),
  //     .A_REN      (~wren_i),
  //     .A_DIN      ({32'h0, data_i[31:0]}),
  //     .A_DOUT     (s_rd_data_mem),
  //     .A_DLY      (1'b0),
  //     .A_BIST_CLK (1'b0),
  //     .A_BIST_EN  (1'b0),
  //     .A_BIST_MEN (1'b0),
  //     .A_BIST_WEN (1'b0),
  //     .A_BIST_REN (1'b0),
  //     .A_BIST_ADDR(10'd0),
  //     .A_BIST_DIN (64'd0),
  //     .A_BIST_BM  (64'd0)
  // );

  // mask_i
  S011HD1P_X256Y4D32_BW u_S011HD1P_X256Y4D32_BW (
      .Q   (data_o),
      .CLK (clk_i),
      .CEN (~cs_i),
      .WEN (~wren_i),
      .BWEN(~{{8{mask_i[3]}}, {8{mask_i[2]}}, {8{mask_i[1]}}, {8{mask_i[0]}}}),
      .A   (addr_i),
      .D   (data_i)
  );
`endif
endmodule
