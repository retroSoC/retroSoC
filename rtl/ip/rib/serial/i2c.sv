// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef RIB_I2C_DEF_SV
`define RIB_I2C_DEF_SV

// verilog_format: off
`define RIB_I2C_CLKDIV  8'h00
`define RIB_I2C_DEVADDR 8'h04
`define RIB_I2C_REGADDR 8'h08
`define RIB_I2C_TXDATA  8'h0C
`define RIB_I2C_RXDATA  8'h10
`define RIB_I2C_XFER    8'h14
`define RIB_I2C_CFG     8'h18
`define RIB_I2C_STATUS  8'h1C
// verilog_format: on

`endif

module rib_i2c (
    // verilog_format: off
    input logic  clk_i,
    input logic  rst_n_i,
    rib_if.slave rib,
    i2c_if.dut   i2c
    // verilog_format: on
);

  logic s_rib_wr_hdshk, s_rib_rd_hdshk;
  logic s_rib_ready_d, s_rib_ready_q;
  logic s_rib_rdata_en;
  logic [31:0] s_rib_rdata_d, s_rib_rdata_q;

  //2^7=128
  logic s_i2c_clkdiv_en;
  logic [6:0] s_i2c_clkdiv_d, s_i2c_clkdiv_q;
  logic s_i2c_devaddr_en;
  logic [6:0] s_i2c_devaddr_d, s_i2c_devaddr_q;
  logic s_i2c_regaddr_en;
  logic [15:0] s_i2c_regaddr_d, s_i2c_regaddr_q;
  logic s_i2c_txdata_en;
  logic [7:0] s_i2c_txdata_d, s_i2c_txdata_q;
  logic [7:0] s_i2c_rxdata;
  logic [1:0] s_i2c_xfer_d, s_i2c_xfer_q;
  logic s_i2c_cfg_en;
  logic s_i2c_cfg_d, s_i2c_cfg_q;
  logic s_i2c_status_d, s_i2c_status_q;

  logic s_bit_rdwr, s_bit_start;
  logic s_bit_end, s_bit_end_re;
  logic s_bit_extn_addr;

  logic s_oper_clk_pos;

  assign s_bit_rdwr      = s_i2c_xfer_q[0];
  assign s_bit_start     = s_i2c_xfer_q[1];
  assign s_bit_extn_addr = s_i2c_cfg_q;

  assign s_rib_wr_hdshk  = rib.valid && (~s_rib_ready_q) && (|rib.wstrb);
  assign s_rib_rd_hdshk  = rib.valid && (~s_rib_ready_q) && (~(|rib.wstrb));
  assign rib.ready       = s_rib_ready_q;
  assign rib.rdata       = s_rib_rdata_q;


  assign s_i2c_clkdiv_en = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_I2C_CLKDIV;
  assign s_i2c_clkdiv_d  = rib.wdata[6:0];
  dffer #(7) u_i2c_clkdiv_dffer (
      clk_i,
      rst_n_i,
      s_i2c_clkdiv_en,
      s_i2c_clkdiv_d,
      s_i2c_clkdiv_q
  );

  assign s_i2c_devaddr_en = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_I2C_DEVADDR;
  assign s_i2c_devaddr_d  = rib.wdata[6:0];
  dffer #(7) u_i2c_devaddr_dffer (
      clk_i,
      rst_n_i,
      s_i2c_devaddr_en,
      s_i2c_devaddr_d,
      s_i2c_devaddr_q
  );


  assign s_i2c_regaddr_en = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_I2C_REGADDR;
  always_comb begin
    s_i2c_regaddr_d = s_i2c_regaddr_q;
    if (rib.wstrb[0]) s_i2c_regaddr_d[7:0] = rib.wdata[7:0];
    if (rib.wstrb[1]) s_i2c_regaddr_d[15:8] = rib.wdata[15:8];
  end
  dffer #(16) u_i2c_regaddr_dffer (
      clk_i,
      rst_n_i,
      s_i2c_regaddr_en,
      s_i2c_regaddr_d,
      s_i2c_regaddr_q
  );


  assign s_i2c_txdata_en = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_I2C_TXDATA;
  assign s_i2c_txdata_d  = rib.wdata[7:0];
  dffer #(8) u_i2c_txdata_dffer (
      clk_i,
      rst_n_i,
      s_i2c_txdata_en,
      s_i2c_txdata_d,
      s_i2c_txdata_q
  );


  always_comb begin
    s_i2c_xfer_d = s_i2c_xfer_q;
    if (s_rib_wr_hdshk && rib.addr[7:0] == `RIB_I2C_XFER) begin
      s_i2c_xfer_d = rib.wdata[1:0];
    end else if (s_oper_clk_pos && (|s_i2c_xfer_q)) begin
      s_i2c_xfer_d = '0;
    end
  end
  dffr #(2) u_i2c_xfer_dffr (
      clk_i,
      rst_n_i,
      s_i2c_xfer_d,
      s_i2c_xfer_q
  );


  assign s_i2c_cfg_en = s_rib_wr_hdshk && rib.addr[7:0] == `RIB_I2C_CFG;
  assign s_i2c_cfg_d  = rib.wdata[0];
  dffer #(1) u_i2c_cfg_dffer (
      clk_i,
      rst_n_i,
      s_i2c_cfg_en,
      s_i2c_cfg_d,
      s_i2c_cfg_q
  );


  edge_det_sync_re #(1) u_i2c_end_edge_det_sync_re (
      clk_i,
      rst_n_i,
      s_bit_end,
      s_bit_end_re
  );
  always_comb begin
    s_i2c_status_d = s_i2c_status_q;
    if (s_bit_end_re) s_i2c_status_d = 1'b1;
    else if (s_rib_rd_hdshk && rib.addr[7:0] == `RIB_I2C_STATUS) begin
      s_i2c_status_d = 1'b0;
    end
  end
  dffr #(1) u_i2c_status_dffr (
      clk_i,
      rst_n_i,
      s_i2c_status_d,
      s_i2c_status_q
  );


  assign s_rib_ready_d = rib.valid && (~s_rib_ready_q);
  dffr #(1) u_rib_ready_dffr (
      clk_i,
      rst_n_i,
      s_rib_ready_d,
      s_rib_ready_q
  );

  assign s_rib_rdata_en = s_rib_rd_hdshk;
  always_comb begin
    s_rib_rdata_d = s_rib_rdata_q;
    unique case (rib.addr[7:0])
      `RIB_I2C_CLKDIV:  s_rib_rdata_d = {25'd0, s_i2c_clkdiv_q};
      `RIB_I2C_DEVADDR: s_rib_rdata_d = {25'd0, s_i2c_devaddr_q};
      `RIB_I2C_REGADDR: s_rib_rdata_d = {16'd0, s_i2c_regaddr_q};
      `RIB_I2C_TXDATA:  s_rib_rdata_d = {24'd0, s_i2c_txdata_q};
      `RIB_I2C_RXDATA:  s_rib_rdata_d = {24'd0, s_i2c_rxdata};
      `RIB_I2C_XFER:    s_rib_rdata_d = {30'd0, s_i2c_xfer_q};
      `RIB_I2C_CFG:     s_rib_rdata_d = {31'd0, s_i2c_cfg_q};
      `RIB_I2C_STATUS:  s_rib_rdata_d = {31'd0, s_i2c_status_q};
      default:          s_rib_rdata_d = s_rib_rdata_q;
    endcase
  end
  dffer #(32) u_rib_rdata_dffer (
      clk_i,
      rst_n_i,
      s_rib_rdata_en,
      s_rib_rdata_d,
      s_rib_rdata_q
  );


  assign i2c.scl_oe_o = 1'b1;
  assign i2c.irq_o    = 1'b0;
  i2c_core u_i2c_core (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .clk_div_i     (s_i2c_clkdiv_q),
      .dev_addr_i    (s_i2c_devaddr_q),
      .rdwr_i        (s_bit_rdwr),
      .start_i       (s_bit_start),
      .end_o         (s_bit_end),
      .extn_addr_i   (s_bit_extn_addr),
      .reg_addr_i    (s_i2c_regaddr_q),
      .wr_data_i     (s_i2c_txdata_q),
      .rd_data_o     (s_i2c_rxdata),
      .oper_clk_pos_o(s_oper_clk_pos),
      .scl_o         (i2c.scl_o),
      .sda_oe_o      (i2c.sda_oe_o),
      .sda_o         (i2c.sda_o),
      .sda_i         (i2c.sda_i)
  );


endmodule
