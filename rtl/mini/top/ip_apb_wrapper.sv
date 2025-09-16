// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "mmap_define.svh"

`include "uart_define.svh"
`include "pwm_define.svh"
`include "ps2_define.svh"
`include "i2c_define.svh"
`include "spi_define.svh"

module ip_apb_wrapper (
    // verilog_format: off
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        spfs_div4_i,
    nmi_if.slave        nmi,
    uart_if.dut         uart,
    pwm_if.dut          pwm,
    ps2_if.dut          ps2,
    i2c_if.dut          i2c,
    qspi_if.dut         qspi,
    spi_if.dut          spfs,
`ifdef IP_MDD
    output logic [15:0] ip_mdd_gpio_out_o,
    input  logic [15:0] ip_mdd_gpio_in_i,
    output logic [15:0] ip_mdd_gpio_oen_o,
`endif
    output logic [ 5:0] irq_o
    // verilog_format: on
);

  // verilog_format: off
  apb4_if u_archinfo_apb_if (clk_i, rst_n_i);
  apb4_if u_rng_apb_if      (clk_i, rst_n_i);
  apb4_if u_uart1_apb_if    (clk_i, rst_n_i);
  apb4_if u_pwm_apb_if      (clk_i, rst_n_i);
  apb4_if u_ps2_apb_if      (clk_i, rst_n_i);
  apb4_if u_i2c_apb_if      (clk_i, rst_n_i);
  apb4_if u_qspi_apb_if     (clk_i, rst_n_i);
  apb4_if u_spfs_apb_if     (clk_i, rst_n_i);
`ifdef IP_MDD
  apb4_if u_user_ip_apb_if  (clk_i, rst_n_i);
`endif

  apb4_archinfo                u_apb4_archinfo (u_archinfo_apb_if);
  apb4_rng                     u_apb4_rng      (u_rng_apb_if);
  apb4_uart #(.FIFO_DEPTH(32)) u_apb4_uart     (u_uart1_apb_if, uart);
  apb4_pwm                     u_apb4_pwm      (u_pwm_apb_if, pwm);
  apb4_ps2                     u_apb4_ps2      (u_ps2_apb_if, ps2);
  apb4_i2c                     u_apb4_i2c      (u_i2c_apb_if, i2c);
  apb4_spi #(.FIFO_DEPTH(32))  u_apb4_spi      (u_qspi_apb_if, qspi);
  // verilog_format: on

  assign irq_o[0] = uart.irq_o;
  assign irq_o[1] = pwm.irq_o;
  assign irq_o[2] = ps2.irq_o;
  assign irq_o[3] = i2c.irq_o;
  assign irq_o[4] = qspi.irq_o;

  mem2apb u_mem2apb (
      .clk_i   (clk_i),
      .rst_n_i (rst_n_i),
      .nmi     (nmi),
`ifdef IP_MDD
      .user_ip (u_user_ip_apb_if),
`endif
      .archinfo(u_archinfo_apb_if),
      .rng     (u_rng_apb_if),
      .uart    (u_uart1_apb_if),
      .pwm     (u_pwm_apb_if),
      .ps2     (u_ps2_apb_if),
      .i2c     (u_i2c_apb_if),
      .qspi    (u_qspi_apb_if),
      .spfs    (u_spfs_apb_if)
  );

  spi_flash #(
      .flash_addr_start(`FLASH_START_ADDR),
      .flash_addr_end  (`FLASH_END_ADDR),
      .spi_cs_num      (1)
  ) u_spi_flash (
      .pclk       (clk_i),
      .presetn    (rst_n_i),
      .paddr      (u_spfs_apb_if.paddr),
      .psel       (u_spfs_apb_if.psel),
      .penable    (u_spfs_apb_if.penable),
      .pwrite     (u_spfs_apb_if.pwrite),
      .pwdata     (u_spfs_apb_if.pwdata),
      .pwstrb     (4'hF),
      .pready     (u_spfs_apb_if.pready),
      .prdata     (u_spfs_apb_if.prdata),
      .pslverr    (u_spfs_apb_if.pslverr),
      .div4_i     (spfs_div4_i),
      .spi_clk    (spfs.spi_sck_o),
      .spi_cs     (spfs.spi_nss_o),
      .spi_mosi   (spfs.spi_mosi_o),
      .spi_miso   (spfs.spi_miso_i),
      .spi_irq_out(irq_o[5])
  );

`ifdef IP_MDD
  ip_mdd_wrapper u_ip_mdd_wrapper (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      // HACK:
      .sel_i            ('0),
      .gpio_out_o       (ip_mdd_gpio_out_o),
      .gpio_in_i        (ip_mdd_gpio_in_i),
      .gpio_oen_o       (ip_mdd_gpio_oen_o),
      .slv_apb_paddr_i  (u_user_ip_apb_if.paddr),
      .slv_apb_pprot_i  (u_user_ip_apb_if.pprot),
      .slv_apb_psel_i   (u_user_ip_apb_if.psel),
      .slv_apb_penable_i(u_user_ip_apb_if.penable),
      .slv_apb_pwrite_i (u_user_ip_apb_if.pwrite),
      .slv_apb_pwdata_i (u_user_ip_apb_if.pwdata),
      .slv_apb_pstrb_i  (u_user_ip_apb_if.pstrb),
      .slv_apb_pready_o (u_user_ip_apb_if.pready),
      .slv_apb_prdata_o (u_user_ip_apb_if.prdata)
  );
`endif

endmodule
