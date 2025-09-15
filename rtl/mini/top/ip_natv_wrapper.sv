// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

// addr range: [31:24]: 8'h10(reg), 8'h40(psram), 8'h50(spisd)
module ip_natv_wrapper (
    // verilog_format: off
    input  logic       clk_i,
    input  logic       rst_n_i,
    // natv if
    nmi_if.slave       nmi,
    // gpio
    output logic [7:0] gpio_out_o,
    input  logic [7:0] gpio_in_i,
    output logic [7:0] gpio_oen_o,
    output logic [7:0] gpio_pun_o,
    output logic [7:0] gpio_pdn_o,
    // uart
    input  logic       uart_rx_i,
    output logic       uart_tx_o,
    // psram
    output logic       psram_sclk_o,
    output logic [1:0] psram_ce_o,
    input  logic       psram_sio0_i,
    input  logic       psram_sio1_i,
    input  logic       psram_sio2_i,
    input  logic       psram_sio3_i,
    output logic       psram_sio0_o,
    output logic       psram_sio1_o,
    output logic       psram_sio2_o,
    output logic       psram_sio3_o,
    output logic       psram_sio_oe_o,
    // sd
    output logic       spisd_sclk_o,
    output logic       spisd_cs_o,
    output logic       spisd_mosi_o,
    input  logic       spisd_miso_i,
    // i2c
    i2c_if.dut         i2c,
    // irq
    output logic [2:0] irq_o
    // verilog_format: on
);

  nmi_if u_gpio_nmi_if ();
  nmi_if u_uart_nmi_if ();
  nmi_if u_tim0_nmi_if ();
  nmi_if u_tim1_nmi_if ();
  nmi_if u_psram_nmi_if ();
  nmi_if u_spisd_nmi_if ();
  nmi_if u_i2c_nmi_if ();
  simp_gpio_if u_simp_gpio_if ();
  simp_uart_if u_simp_uart_if ();


  logic s_psram_cfg_sel;
  logic s_spisd_cfg_sel;
  assign u_gpio_nmi_if.valid    = nmi.valid && (nmi.addr[31:24] == 8'h10 && nmi.addr[15:8] == 8'h00);
  assign u_gpio_nmi_if.addr     = nmi.addr;
  assign u_gpio_nmi_if.wdata    = nmi.wdata;
  assign u_gpio_nmi_if.wstrb    = nmi.wstrb;

  assign u_uart_nmi_if.valid    = nmi.valid && (nmi.addr[31:24] == 8'h10 && nmi.addr[15:8] == 8'h10);
  assign u_uart_nmi_if.addr     = nmi.addr;
  assign u_uart_nmi_if.wdata    = nmi.wdata;
  assign u_uart_nmi_if.wstrb    = nmi.wstrb;

  assign u_tim0_nmi_if.valid    = nmi.valid && (nmi.addr[31:24] == 8'h10 && nmi.addr[15:8] == 8'h20);
  assign u_tim0_nmi_if.addr     = nmi.addr;
  assign u_tim0_nmi_if.wdata    = nmi.wdata;
  assign u_tim0_nmi_if.wstrb    = nmi.wstrb;

  assign u_tim1_nmi_if.valid    = nmi.valid && (nmi.addr[31:24] == 8'h10 && nmi.addr[15:8] == 8'h30);
  assign u_tim1_nmi_if.addr     = nmi.addr;
  assign u_tim1_nmi_if.wdata    = nmi.wdata;
  assign u_tim1_nmi_if.wstrb    = nmi.wstrb;

  assign s_psram_cfg_sel        = nmi.addr[31:24] == 8'h10 && nmi.addr[15:8] == 8'h40;
  assign u_psram_nmi_if.valid   = nmi.valid && (nmi.addr[31:24] == 8'h40 || s_psram_cfg_sel);
  assign u_psram_nmi_if.addr    = nmi.addr;
  assign u_psram_nmi_if.wdata   = nmi.wdata;
  assign u_psram_nmi_if.wstrb   = nmi.wstrb;

  assign s_spisd_cfg_sel        = nmi.addr[31:24] == 8'h10 && nmi.addr[15:8] == 8'h50;
  assign u_spisd_nmi_if.valid   = nmi.valid && (nmi.addr[31:24] == 8'h50 || s_spisd_cfg_sel);
  assign u_spisd_nmi_if.addr    = nmi.addr;
  assign u_spisd_nmi_if.wdata   = nmi.wdata;
  assign u_spisd_nmi_if.wstrb   = nmi.wstrb;

  assign u_i2c_nmi_if.valid   = nmi.valid && (nmi.addr[31:24] == 8'h10 && nmi.addr[15:8] == 8'h60);
  assign u_i2c_nmi_if.addr    = nmi.addr;
  assign u_i2c_nmi_if.wdata   = nmi.wdata;
  assign u_i2c_nmi_if.wstrb   = nmi.wstrb;

  // verilog_format: off
  assign nmi.ready              = (u_gpio_nmi_if.valid  & u_gpio_nmi_if.ready)  |
                                  (u_uart_nmi_if.valid  & u_uart_nmi_if.ready)  |
                                  (u_tim0_nmi_if.valid  & u_tim0_nmi_if.ready)  |
                                  (u_tim1_nmi_if.valid  & u_tim1_nmi_if.ready)  |
                                  (u_psram_nmi_if.valid & u_psram_nmi_if.ready) |
                                  (u_spisd_nmi_if.valid & u_spisd_nmi_if.ready);

  assign nmi.rdata              = ({32{(u_gpio_nmi_if.valid  & u_gpio_nmi_if.ready)}}  & u_gpio_nmi_if.rdata)  |
                                  ({32{(u_uart_nmi_if.valid  & u_uart_nmi_if.ready)}}  & u_uart_nmi_if.rdata)  |
                                  ({32{(u_tim0_nmi_if.valid  & u_tim0_nmi_if.ready)}}  & u_tim0_nmi_if.rdata)  |
                                  ({32{(u_tim1_nmi_if.valid  & u_tim1_nmi_if.ready)}}  & u_tim1_nmi_if.rdata)  |
                                  ({32{(u_psram_nmi_if.valid & u_psram_nmi_if.ready)}} & u_psram_nmi_if.rdata) |
                                  ({32{(u_spisd_nmi_if.valid & u_spisd_nmi_if.ready)}} & u_spisd_nmi_if.rdata);
 // verilog_format: on

  assign gpio_out_o             = u_simp_gpio_if.gpio_out;
  assign u_simp_gpio_if.gpio_in = gpio_in_i;
  assign gpio_oen_o             = u_simp_gpio_if.gpio_oen;
  assign gpio_pun_o             = u_simp_gpio_if.gpio_pun;
  assign gpio_pdn_o             = u_simp_gpio_if.gpio_pdn;

  assign u_simp_uart_if.rx      = uart_rx_i;
  assign uart_tx_o              = u_simp_uart_if.tx;
  assign irq_o[0]               = u_simp_uart_if.irq;

  simple_gpio u_simple_gpio (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (u_gpio_nmi_if),
      .gpio   (u_simp_gpio_if)
  );

  simple_uart u_simple_uart (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (u_uart_nmi_if),
      .uart   (u_simp_uart_if)
  );

  simple_timer u_simple_timer0 (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (u_tim0_nmi_if),
      .irq_o  (irq_o[1])
  );

  simple_timer u_simple_timer1 (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (u_tim1_nmi_if),
      .irq_o  (irq_o[2])
  );


  psram_top u_psram_top (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .mem_valid_i    (u_psram_nmi_if.valid),
      .mem_addr_i     (u_psram_nmi_if.addr),
      .mem_wdata_i    (u_psram_nmi_if.wdata),
      .mem_wstrb_i    (u_psram_nmi_if.wstrb),
      .mem_rdata_o    (u_psram_nmi_if.rdata),
      .mem_ready_o    (u_psram_nmi_if.ready),
      .psram_sclk_o   (psram_sclk_o),
      .psram_ce_o     (psram_ce_o),
      .psram_mosi_i   (psram_sio0_i),
      .psram_miso_i   (psram_sio1_i),
      .psram_sio2_i   (psram_sio2_i),
      .psram_sio3_i   (psram_sio3_i),
      .psram_mosi_o   (psram_sio0_o),
      .psram_miso_o   (psram_sio1_o),
      .psram_sio2_o   (psram_sio2_o),
      .psram_sio3_o   (psram_sio3_o),
      .psram_sio_oen_o(psram_sio_oe_o)
  );

  spisd u_spisd (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .mem_valid_i (u_spisd_nmi_if.valid),
      .mem_ready_o (u_spisd_nmi_if.ready),
      .mem_addr_i  (u_spisd_nmi_if.addr),
      .mem_wdata_i (u_spisd_nmi_if.wdata),
      .mem_wstrb_i (u_spisd_nmi_if.wstrb),
      .mem_rdata_o (u_spisd_nmi_if.rdata),
      .spisd_sclk_o(spisd_sclk_o),
      .spisd_cs_o  (spisd_cs_o),
      .spisd_mosi_o(spisd_mosi_o),
      .spisd_miso_i(spisd_miso_i)
  );


  nmi_i2c u_nmi_i2c (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (u_i2c_nmi_if),
      .i2c    (i2c)
  );

  // nmi2nmi u_nmi2nmi (
  //     .mstr_clk_i  (clk_i),
  //     .mstr_rst_n_i(rst_n_i),
  //     .mstr_valid_i(s_i2s_valid),
  //     .mstr_addr_i (s_i2s_addr),
  //     .mstr_wdata_i(s_i2s_wdata),
  //     .mstr_wstrb_i(s_i2s_wstrb),
  //     .mstr_rdata_o(s_i2s_rdata),
  //     .mstr_ready_o(s_i2s_ready),
  //     .slvr_clk_i  (clk_aud_i),
  //     .slvr_rst_n_i(rst_aud_n_i),
  //     .slvr_valid_o(s_i2s_aud_valid),
  //     .slvr_addr_o (s_i2s_aud_addr),
  //     .slvr_wdata_o(s_i2s_aud_wdata),
  //     .slvr_wstrb_o(s_i2s_aud_wstrb),
  //     .slvr_rdata_i(s_i2s_aud_rdata),
  //     .slvr_ready_i(s_i2s_aud_ready)
  // );

  // // HACK:
  // assign s_i2s_aud_rdata = '0;
  // assign s_i2s_aud_ready = '0;
endmodule
