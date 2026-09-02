// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module tc_sram_1024x32 (
    // verilog_format: off -- preserve the technology memory interface columns
    input  logic        clk_i,
    input  logic        cs_i,
    input  logic [ 9:0] addr_i,
    input  logic [31:0] data_i,
    input  logic [ 3:0] mask_i,
    input  logic        wren_i,
    output logic [31:0] data_o
    // verilog_format: on
);

`ifdef PDK_BEHAV
  logic [31:0] s_data_q;
  logic [31:0] s_storage_q[0:1023];

  assign data_o = s_data_q;
  always_ff @(posedge clk_i) begin
    if (cs_i) begin
      if (!wren_i) begin
        s_data_q <= s_storage_q[addr_i];
      end else begin
        if (mask_i[0]) s_storage_q[addr_i][7:0] <= data_i[7:0];
        if (mask_i[1]) s_storage_q[addr_i][15:8] <= data_i[15:8];
        if (mask_i[2]) s_storage_q[addr_i][23:16] <= data_i[23:16];
        if (mask_i[3]) s_storage_q[addr_i][31:24] <= data_i[31:24];
        s_data_q <= 32'bx;
      end
    end
  end
`elsif PDK_IHP130
`ifdef HAVE_SRAM_MACRO
  RM_IHPSG13_1P_1024x32_c2_bm_bist u_mem (
      .A_CLK      (clk_i),
      .A_ADDR     (addr_i),
      .A_BM       ({{8{mask_i[3]}}, {8{mask_i[2]}}, {8{mask_i[1]}}, {8{mask_i[0]}}}),
      .A_MEN      (cs_i),
      .A_WEN      (wren_i),
      .A_REN      (~wren_i),
      .A_DIN      (data_i),
      .A_DOUT     (data_o),
      .A_DLY      (1'b1),
      .A_BIST_CLK (1'b0),
      .A_BIST_EN  (1'b0),
      .A_BIST_MEN (1'b0),
      .A_BIST_WEN (1'b0),
      .A_BIST_REN (1'b0),
      .A_BIST_ADDR(10'b0),
      .A_BIST_DIN (32'b0),
      .A_BIST_BM  (32'b0)
  );
`endif
`elsif PDK_GF180
`ifdef HAVE_SRAM_MACRO
  logic                 s_read_depth_q;
  logic [1:0][3:0][7:0] s_macro_data_o;
`ifndef SYNTHESIS
  wire s_vdd = 1'b1;
  wire s_vss = 1'b0;
`endif

  dffl #(
      .DATA_WIDTH(1)
  ) u_read_depth_dffl (
      .clk_i(clk_i),
      .en_i (cs_i && !wren_i),
      .dat_i(addr_i[9]),
      .dat_o(s_read_depth_q)
  );

  for (genvar depth = 0; depth < 2; depth++) begin : gen_depth
    for (genvar byte_index = 0; byte_index < 4; byte_index++) begin : gen_byte
      // verilog_format: off -- preserve conditional PDK power-pin connections
      gf180mcu_fd_ip_sram__sram512x8m8wm1 u_sram (
          .CLK (clk_i),
          .CEN (~(cs_i && (addr_i[9] == 1'(depth)))),
          .GWEN(~wren_i),
          .WEN (~{8{mask_i[byte_index]}}),
          .A   (addr_i[8:0]),
          .D   (data_i[byte_index*8+:8]),
`ifndef SYNTHESIS
          .Q   (s_macro_data_o[depth][byte_index]),
          .VDD (s_vdd),
          .VSS (s_vss)
`else
          .Q   (s_macro_data_o[depth][byte_index])
`endif
      );
      // verilog_format: on
    end
  end

  assign data_o = {
    s_macro_data_o[s_read_depth_q][3],
    s_macro_data_o[s_read_depth_q][2],
    s_macro_data_o[s_read_depth_q][1],
    s_macro_data_o[s_read_depth_q][0]
  };
`endif
`elsif PDK_SKY130
`ifdef HAVE_SRAM_MACRO
`ifdef USE_POWER_PINS
  wire s_vccd1 = 1'b1;
  wire s_vssd1 = 1'b0;
`endif
  sky130_sram_4kbyte_1rw_32x1024_8 u_sram (
`ifdef USE_POWER_PINS
      .vccd1 (s_vccd1),
      .vssd1 (s_vssd1),
`endif
      .clk0  (clk_i),
      .csb0  (~cs_i),
      .web0  (~wren_i),
      .wmask0(mask_i),
      .addr0 ({1'b0, addr_i}),
      .din0  (data_i),
      .dout0 (data_o)
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

module tc_sram_64x64 (
    // verilog_format: off -- preserve the technology memory interface columns
    input  logic        clk_i,
    input  logic        cs_i,
    input  logic [ 5:0] addr_i,
    input  logic [63:0] data_i,
    input  logic        wren_i,
    output logic [63:0] data_o
    // verilog_format: on
);
`ifdef PDK_IHP130
`ifdef HAVE_SRAM_MACRO
  `define _TC_SRAM_64X64_IHP_MACRO
`endif
`endif

`ifdef _TC_SRAM_64X64_IHP_MACRO
  RM_IHPSG13_1P_64x64_c2_bm_bist u_mem (
      .A_CLK      (clk_i),
      .A_ADDR     (addr_i),
      .A_BM       (64'hffff_ffff_ffff_ffff),
      .A_MEN      (cs_i),
      .A_WEN      (wren_i),
      .A_REN      (~wren_i),
      .A_DIN      (data_i),
      .A_DOUT     (data_o),
      .A_DLY      (1'b1),
      .A_BIST_CLK (1'b0),
      .A_BIST_EN  (1'b0),
      .A_BIST_MEN (1'b0),
      .A_BIST_WEN (1'b0),
      .A_BIST_REN (1'b0),
      .A_BIST_ADDR(6'b0),
      .A_BIST_DIN (64'b0),
      .A_BIST_BM  (64'b0)
  );
`else
  logic [63:0] s_storage[64];

  always_ff @(posedge clk_i) begin
    if (cs_i) begin
      if (wren_i) begin
        s_storage[addr_i] <= data_i;
      end else begin
        data_o <= s_storage[addr_i];
      end
    end
  end
`endif

`ifdef _TC_SRAM_64X64_IHP_MACRO
  `undef _TC_SRAM_64X64_IHP_MACRO
`endif
endmodule

module tc_sram_64x32_2p (
    // verilog_format: off -- preserve the dual-port technology memory columns
    input  logic        clk_i,
    input  logic        a_cs_i,
    input  logic [ 5:0] a_addr_i,
    input  logic [31:0] a_data_i,
    input  logic        a_wren_i,
    output logic [31:0] a_data_o,
    input  logic        b_cs_i,
    input  logic [ 5:0] b_addr_i,
    input  logic [31:0] b_data_i,
    input  logic        b_wren_i,
    output logic [31:0] b_data_o
    // verilog_format: on
);
`ifdef PDK_IHP130
`ifdef HAVE_SRAM_MACRO
  `define _TC_SRAM_64X32_2P_IHP_MACRO
`endif
`endif

`ifdef _TC_SRAM_64X32_2P_IHP_MACRO
  RM_IHPSG13_2P_64x32_c2 u_mem (
      .A_CLK (clk_i),
      .A_ADDR(a_addr_i),
      .A_MEN (a_cs_i),
      .A_WEN (a_wren_i),
      .A_REN (~a_wren_i),
      .A_DIN (a_data_i),
      .A_DOUT(a_data_o),
      .A_DLY (1'b1),
      .B_CLK (clk_i),
      .B_ADDR(b_addr_i),
      .B_MEN (b_cs_i),
      .B_WEN (b_wren_i),
      .B_REN (~b_wren_i),
      .B_DIN (b_data_i),
      .B_DOUT(b_data_o),
      .B_DLY (1'b1)
  );
`else
  logic [31:0] s_storage[64];

  always_ff @(posedge clk_i) begin
    if (a_cs_i) begin
      if (a_wren_i) begin
        s_storage[a_addr_i] <= a_data_i;
      end else begin
        a_data_o <= s_storage[a_addr_i];
      end
    end
    if (b_cs_i) begin
      if (b_wren_i) begin
        s_storage[b_addr_i] <= b_data_i;
      end else begin
        b_data_o <= s_storage[b_addr_i];
      end
    end
  end
`endif

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (a_cs_i && b_cs_i && (a_addr_i == b_addr_i) && (a_wren_i || b_wren_i)) begin
      $fatal(1, "tc_sram_64x32_2p: conflicting access at address %0d", a_addr_i);
    end
  end
`endif

`ifdef _TC_SRAM_64X32_2P_IHP_MACRO
  `undef _TC_SRAM_64X32_2P_IHP_MACRO
`endif
endmodule

module tc_sram_4096x32 (
    // verilog_format: off -- preserve the technology memory interface columns
    input  logic        clk_i,
    input  logic        cs_i,
    input  logic [11:0] addr_i,
    input  logic [31:0] data_i,
    input  logic [ 3:0] mask_i,
    input  logic        wren_i,
    output logic [31:0] data_o
    // verilog_format: on
);
`ifdef PDK_BEHAV
  logic [31:0] s_data_q;
  logic [31:0] s_storage_q[0:4095];

  assign data_o = s_data_q;
  always_ff @(posedge clk_i) begin
    if (cs_i) begin
      if (wren_i) begin
        if (mask_i[0]) s_storage_q[addr_i][7:0] <= data_i[7:0];
        if (mask_i[1]) s_storage_q[addr_i][15:8] <= data_i[15:8];
        if (mask_i[2]) s_storage_q[addr_i][23:16] <= data_i[23:16];
        if (mask_i[3]) s_storage_q[addr_i][31:24] <= data_i[31:24];
      end else begin
        s_data_q <= s_storage_q[addr_i];
      end
    end
  end
`elsif PDK_ICS55
`ifdef HAVE_SRAM_MACRO
  SRAM_4096X32_M8_BW u_sram (
      .A   (addr_i),
      .D   (data_i),
      .CEB (~cs_i),
      .CLK (clk_i),
      .GWEB(~wren_i),
      .WEB (~{{8{mask_i[3]}}, {8{mask_i[2]}}, {8{mask_i[1]}}, {8{mask_i[0]}}}),
      .MARE(1'b0),
      .MAR (4'd0),
      .Q   (data_o)
  );
`else
  assign data_o = '0;
`endif
`else
  logic [31:0] s_data_q;
  logic [31:0] s_storage_q[0:4095];

  assign data_o = s_data_q;
  always_ff @(posedge clk_i) begin
    if (cs_i) begin
      if (wren_i) begin
        if (mask_i[0]) s_storage_q[addr_i][7:0] <= data_i[7:0];
        if (mask_i[1]) s_storage_q[addr_i][15:8] <= data_i[15:8];
        if (mask_i[2]) s_storage_q[addr_i][23:16] <= data_i[23:16];
        if (mask_i[3]) s_storage_q[addr_i][31:24] <= data_i[31:24];
      end else begin
        s_data_q <= s_storage_q[addr_i];
      end
    end
  end
`endif
endmodule
