module tc_sram_1024x32 (
    input  logic        clk_i,
    input  logic        cs_i,
    input  logic [ 9:0] addr_i,
    input  logic [31:0] data_i,
    input  logic [ 3:0] mask_i,
    input  logic        wren_i,
    output logic [31:0] data_o
);

`ifdef PDK_BEHAV
  logic [31:0] r_data;
  logic [31:0] mem    [0:1023];

  assign data_o = r_data;
  always_ff @(posedge clk_i) begin
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
`elsif PDK_IHP130
`ifdef HAVE_SRAM_MACRO
  logic [63:0] s_rd_data_mem;
  assign data_o = s_rd_data_mem[31:0];
  RM_IHPSG13_1P_1024x64_c2_bm_bist u_mem (
      .A_CLK      (clk_i),
      .A_ADDR     (addr_i),
      .A_BM       ({32'h0, {8{mask_i[3]}}, {8{mask_i[2]}}, {8{mask_i[1]}}, {8{mask_i[0]}}}),
      .A_MEN      (cs_i),
      .A_WEN      (wren_i),
      .A_REN      (~wren_i),
      .A_DIN      ({32'h0, data_i[31:0]}),
      .A_DOUT     (s_rd_data_mem),
      .A_DLY      ('0),
      .A_BIST_CLK ('0),
      .A_BIST_EN  ('0),
      .A_BIST_MEN ('0),
      .A_BIST_WEN ('0),
      .A_BIST_REN ('0),
      .A_BIST_ADDR('0),
      .A_BIST_DIN ('0),
      .A_BIST_BM  ('0)
  );
`endif
`elsif PDK_S110
`ifdef HAVE_SRAM_MACRO
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

`elsif PDK_ICS55
`ifdef HAVE_SRAM_MACRO
  S55NLLG1PH_X256Y4D32_BW u_S55NLLG1PH_X256Y4D32_BW (
      .Q   (data_o),
      .CLK (clk_i),
      .CEN (~cs_i),
      .WEN (~wren_i),
      .BWEN(~{{8{mask_i[3]}}, {8{mask_i[2]}}, {8{mask_i[1]}}, {8{mask_i[0]}}}),
      .A   (addr_i),
      .D   (data_i)
  );

`endif
`endif
endmodule
