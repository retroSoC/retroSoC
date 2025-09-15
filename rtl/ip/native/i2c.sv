`ifndef NATV_I2C_DEF_SV
`define NATV_I2C_DEF_SV

// verilog_format: off
`define NATV_I2C_CLKDIV  8'h00
`define NATV_I2C_DEVADDR 8'h04
`define NATV_I2C_REGADDR 8'h08
`define NATV_I2C_TXDATA  8'h0C
`define NATV_I2C_RXDATA  8'h10
`define NATV_I2C_XFER    8'h14
`define NATV_I2C_CFG     8'h18
`define NATV_I2C_STATUS  8'h1C
// verilog_format: on

`endif

module nmi_i2c (
    // verilog_format: off
    input logic  clk_i,
    input logic  rst_n_i,
    nmi_if.slave nmi,
    i2c_if.dut   i2c
    // verilog_format: on
);

  logic s_nmi_wr_hdshk, s_nmi_rd_hdshk;
  logic s_nmi_ready_d, s_nmi_ready_q;
  logic s_nmi_rdata_en;
  logic [31:0] s_nmi_rdata_d, s_nmi_rdata_q;

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
  logic       s_i2c_xfer_en;
  logic [2:0] s_i2c_xfer_d, s_i2c_xfer_q;
  logic s_i2c_cfg_en;
  logic s_i2c_cfg_d, s_i2c_cfg_q;
  logic s_i2c_status_en;
  logic s_i2c_status_d, s_i2c_status_q;

  logic s_bit_wr, s_bit_rd, s_bit_start;
  logic s_bit_end;
  logic s_bit_extn_addr;

  assign s_bit_wr        = s_i2c_xfer_q[0];
  assign s_bit_rd        = s_i2c_xfer_q[1];
  assign s_bit_start     = s_i2c_xfer_q[2];
  assign s_bit_extn_addr = s_i2c_cfg_q;

  assign s_nmi_wr_hdshk  = nmi.valid && (~s_nmi_ready_q) && (|nmi.wstrb);
  assign s_nmi_rd_hdshk  = nmi.valid && (~s_nmi_ready_q) && (~(|nmi.wstrb));
  assign nmi.ready       = s_nmi_ready_q;
  assign nmi.rdata       = s_nmi_rdata_q;


  assign s_i2c_clkdiv_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_I2C_CLKDIV;
  assign s_i2c_clkdiv_d  = nmi.wdata[6:0];
  dffer #(7) u_i2c_clkdiv_dffer (
      clk_i,
      rst_n_i,
      s_i2c_clkdiv_en,
      s_i2c_clkdiv_d,
      s_i2c_clkdiv_q
  );

  assign s_i2c_devaddr_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_I2C_DEVADDR;
  assign s_i2c_devaddr_d  = nmi.wdata[6:0];
  dffer #(7) u_i2c_devaddr_dffer (
      clk_i,
      rst_n_i,
      s_i2c_devaddr_en,
      s_i2c_devaddr_d,
      s_i2c_devaddr_q
  );


  assign s_i2c_regaddr_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_I2C_REGADDR;
  always_comb begin
    s_i2c_regaddr_d = s_i2c_regaddr_q;
    if (nmi.wstrb[0]) s_i2c_regaddr_d[7:0] = nmi.wdata[7:0];
    if (nmi.wstrb[1]) s_i2c_regaddr_d[15:8] = nmi.wdata[15:8];
  end
  dffer #(16) u_i2c_regaddr_dffer (
      clk_i,
      rst_n_i,
      s_i2c_regaddr_en,
      s_i2c_regaddr_d,
      s_i2c_regaddr_q
  );


  assign s_i2c_txdata_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_I2C_TXDATA;
  assign s_i2c_txdata_d  = nmi.wdata[7:0];
  dffer #(8) u_i2c_txdata_dffer (
      clk_i,
      rst_n_i,
      s_i2c_txdata_en,
      s_i2c_txdata_d,
      s_i2c_txdata_q
  );



  assign s_i2c_xfer_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_I2C_XFER;
  assign s_i2c_xfer_d  = nmi.wdata[2:0];
  dffer #(3) u_i2c_xfer_dffer (
      clk_i,
      rst_n_i,
      s_i2c_xfer_en,
      s_i2c_xfer_d,
      s_i2c_xfer_q
  );


  assign s_i2c_cfg_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `NATV_I2C_CFG;
  assign s_i2c_cfg_d  = nmi.wdata[0];
  dffer #(1) u_i2c_cfg_dffer (
      clk_i,
      rst_n_i,
      s_i2c_cfg_en,
      s_i2c_cfg_d,
      s_i2c_cfg_q
  );


  assign s_i2c_status_en = 1'b1;
  assign s_i2c_status_d  = s_bit_end;
  dffer #(1) u_i2c_status_dffer (
      clk_i,
      rst_n_i,
      s_i2c_status_en,
      s_i2c_status_d,
      s_i2c_status_q
  );


  assign s_nmi_ready_d = nmi.valid && (~s_nmi_ready_q);
  dffr #(1) u_nmi_ready_dffr (
      clk_i,
      rst_n_i,
      s_nmi_ready_d,
      s_nmi_ready_q
  );

  assign s_nmi_rdata_en = s_nmi_rd_hdshk;
  always_comb begin
    s_nmi_rdata_d = s_nmi_rdata_q;
    unique case (nmi.addr[7:0])
      `NATV_I2C_CLKDIV:  s_nmi_rdata_d = {25'd0, s_i2c_clkdiv_q};
      `NATV_I2C_DEVADDR: s_nmi_rdata_d = {25'd0, s_i2c_devaddr_q};
      `NATV_I2C_REGADDR: s_nmi_rdata_d = {16'd0, s_i2c_regaddr_q};
      `NATV_I2C_TXDATA:  s_nmi_rdata_d = {24'd0, s_i2c_txdata_q};
      `NATV_I2C_RXDATA:  s_nmi_rdata_d = {24'd0, s_i2c_rxdata};
      `NATV_I2C_XFER:    s_nmi_rdata_d = {29'd0, s_i2c_xfer_q};
      `NATV_I2C_CFG:     s_nmi_rdata_d = {31'd0, s_i2c_cfg_q};
      `NATV_I2C_STATUS:  s_nmi_rdata_d = {31'd0, s_i2c_status_q};
      default:           s_nmi_rdata_d = s_nmi_rdata_q;
    endcase
  end
  dffer #(32) u_nmi_rdata_dffer (
      clk_i,
      rst_n_i,
      s_nmi_rdata_en,
      s_nmi_rdata_d,
      s_nmi_rdata_q
  );


  assign i2c.scl_dir_o = 1'b1;
  assign i2c.irq_o     = 1'b0;
  i2c_core u_i2c_core (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .clk_div_i      (s_i2c_clkdiv_q),
      .dev_addr_i     (s_i2c_devaddr_q),
      .wr_en_i        (s_bit_wr),
      .rd_en_i        (s_bit_rd),
      .start_i        (s_bit_start),
      .end_o          (s_bit_end),
      .extn_addr_i    (s_bit_extn_addr),
      .reg_addr_i     (s_i2c_regaddr_q),
      .wr_data_i      (s_i2c_txdata_q),
      .rd_data_o      (s_i2c_rxdata),
      .oper_clk_pos_o (),
      .oper_clk_fall_o(),
      .scl_o          (i2c.scl_o),
      .sda_oe_o       (i2c.sda_dir_o),
      .sda_o          (i2c.sda_o),
      .sda_i          (i2c.sda_i)
  );


endmodule
