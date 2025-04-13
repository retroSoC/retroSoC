/*
 *  retroSoC - A simple example SoC using PicoRV32
 *
 *  Copyright (C) 2017  Clifford Wolf <clifford@clifford.at>
 *  Copyright (C) 2018,2019  Tim Edwards <tim@efabless.com>
 *  Copyright (C) 2025  Yuchi Miao <miaoyuchi@ict.ac.cn>

 *  Permission to use, copy, modify, and/or distribute this software for any
 *  purpose with or without fee is hereby granted, provided that the above
 *  copyright notice and this permission notice appear in all copies.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 *  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 *  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 *  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 *  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 *  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 *  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 */

`include "mmap_define.svh"

module retrosoc (
    input         clk_i,
    input         rst_n_i,
    output [14:0] ram_addr_o,
    output [31:0] ram_wdata_o,
    output [ 3:0] ram_wstrb_o,
    input  [31:0] ram_rdata_i,
    // memory mapped I/O signals
    output [15:0] gpio_out_o,
    input  [15:0] gpio_in_i,
    output [15:0] gpio_pub_o,
    output [15:0] gpio_pdb_o,
    output [15:0] gpio_oeb_o,
    output        uart_tx_o,
    input         uart_rx_i,
    // irq
    input         irq_pin_i,
    // cust
    input         cust_uart_rx_i,
    output        cust_uart_tx_o,
    output [ 3:0] cust_pwm_pwm_o,
    input         cust_ps2_ps2_clk_i,
    input         cust_ps2_ps2_dat_i,
    input         cust_i2c_scl_i,
    output        cust_i2c_scl_o,
    output        cust_i2c_scl_dir_o,
    input         cust_i2c_sda_i,
    output        cust_i2c_sda_o,
    output        cust_i2c_sda_dir_o,
    output        cust_qspi_spi_clk_o,
    output [ 3:0] cust_qspi_spi_csn_o,
    output [ 3:0] cust_qspi_spi_sdo_o,
    output [ 3:0] cust_qspi_spi_oe_o,
    input  [ 3:0] cust_qspi_spi_sdi_i,
    output        cust_psram_sclk_o,
    output        cust_psram_ce_o,
    input         cust_psram_sio0_i,
    input         cust_psram_sio1_i,
    input         cust_psram_sio2_i,
    input         cust_psram_sio3_i,
    output        cust_psram_sio0_o,
    output        cust_psram_sio1_o,
    output        cust_psram_sio2_o,
    output        cust_psram_sio3_o,
    output        cust_psram_sio_oe_o,
    input         cust_spfs_div4_i,
    output        cust_spfs_clk_o,
    output        cust_spfs_cs_o,
    output        cust_spfs_mosi_o,
    input         cust_spfs_miso_i
);
  // core if
  wire        s_core_valid;
  wire [31:0] s_core_addr;
  wire [31:0] s_core_wdata;
  wire [ 3:0] s_core_wstrb;
  wire [31:0] s_core_rdata;
  wire        s_core_ready;
  // mmap if
  wire        s_mmap_valid;
  wire [ 3:0] s_mmap_wstrb;
  wire [31:0] s_mmap_addr;
  wire [31:0] s_mmap_wdata;
  wire [31:0] s_mmap_rdata;
  wire        s_mmap_ready;
  // natv if
  wire        s_natv_valid;
  wire [ 3:0] s_natv_wstrb;
  wire [31:0] s_natv_addr;
  wire [31:0] s_natv_wdata;
  wire [31:0] s_natv_rdata;
  wire        s_natv_ready;
  // psram if
  wire        s_psram_valid;
  wire [ 3:0] s_psram_wstrb;
  wire [31:0] s_psram_addr;
  wire [31:0] s_psram_wdata;
  wire [31:0] s_psram_rdata;
  wire        s_psram_ready;
  // psram cfg if
  wire        s_psram_cfg_wait_wr_en;
  wire [ 4:0] s_psram_cfg_wait_i;
  wire [ 4:0] s_psram_cfg_wait_o;
  wire        s_psram_cfg_chd_wr_en;
  wire [ 2:0] s_psram_cfg_chd_i;
  wire [ 2:0] s_psram_cfg_chd_o;

  // irq
  wire [31:0] s_irq;
  wire [ 2:0] s_natv_irq;
  wire [ 5:0] s_apb_irq;

  assign s_irq[4:0]   = 5'd0;
  assign s_irq[5]     = irq_pin_i;
  assign s_irq[8:6]   = s_natv_irq;
  assign s_irq[14:9]  = s_apb_irq;
  assign s_irq[31:15] = 17'd0;

  // memory mapped IP
  // NATV WRAPPER
  //    16 x GPIO
  //    1  x UART
  //    2  x TIMER
  //    1  x PSRAM(8MB)
  // APB WRAPPER
  //    1 x RNG
  //    1 x ARCHINFO
  //    1 x UART
  //    4 x PWM
  //    1 x PS2
  //    1 x QSPI
  //    1 x SPFS(HP)
  //    1 x I2C
  picorv32 #(
      .BARREL_SHIFTER (1),
      .COMPRESSED_ISA (1),
      .ENABLE_MUL     (1),
      .ENABLE_FAST_MUL(1),
      .ENABLE_DIV     (1),
      .ENABLE_IRQ     (0),
      .PROGADDR_RESET (`FLASH_START_ADDR)
  ) u_picorv32 (
      .clk      (clk_i),
      .resetn   (rst_n_i),
      .mem_valid(s_core_valid),
      .mem_instr(),
      .mem_addr (s_core_addr),
      .mem_wdata(s_core_wdata),
      .mem_wstrb(s_core_wstrb),
      .mem_rdata(s_core_rdata),
      .mem_ready(s_core_ready),
      .irq      (s_irq),
      .trap     ()
  );

  bus u_bus (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      // core if
      .core_valid_i (s_core_valid),
      .core_ready_o (s_core_ready),
      .core_addr_i  (s_core_addr),
      .core_wdata_i (s_core_wdata),
      .core_wstrb_i (s_core_wstrb),
      .core_rdata_o (s_core_rdata),
      // natv if
      .natv_valid_o (s_natv_valid),
      .natv_ready_i (s_natv_ready),
      .natv_addr_o  (s_natv_addr),
      .natv_wdata_o (s_natv_wdata),
      .natv_wstrb_o (s_natv_wstrb),
      .natv_rdata_i (s_natv_rdata),
      // mmap if
      .mmap_valid_o (s_mmap_valid),
      .mmap_ready_i (s_mmap_ready),
      .mmap_addr_o  (s_mmap_addr),
      .mmap_wdata_o (s_mmap_wdata),
      .mmap_wstrb_o (s_mmap_wstrb),
      .mmap_rdata_i (s_mmap_rdata),
      .ram_addr_o   (ram_addr_o),
      .ram_wdata_o  (ram_wdata_o),
      .ram_wstrb_o  (ram_wstrb_o),
      .ram_rdata_i  (ram_rdata_i),
      // psram if
      .psram_valid_o(s_psram_valid),
      .psram_ready_i(s_psram_ready),
      .psram_addr_o (s_psram_addr),
      .psram_wdata_o(s_psram_wdata),
      .psram_wstrb_o(s_psram_wstrb),
      .psram_rdata_i(s_psram_rdata)
  );

  natv_ip_wrapper u_natv_ip_wrapper (
      .clk_i                 (clk_i),
      .rst_n_i               (rst_n_i),
      .natv_valid_i          (s_natv_valid),
      .natv_addr_i           (s_natv_addr),
      .natv_wdata_i          (s_natv_wdata),
      .natv_wstrb_i          (s_natv_wstrb),
      .natv_rdata_o          (s_natv_rdata),
      .natv_ready_o          (s_natv_ready),
      .gpio_out_o            (gpio_out_o),
      .gpio_in_i             (gpio_in_i),
      .gpio_pub_o            (gpio_pub_o),
      .gpio_pdb_o            (gpio_pdb_o),
      .gpio_oeb_o            (gpio_oeb_o),
      .uart_rx_i             (uart_rx_i),
      .uart_tx_o             (uart_tx_o),
      .psram_cfg_wait_wr_en_o(s_psram_cfg_wait_wr_en),
      .psram_cfg_wait_i      (s_psram_cfg_wait_i),
      .psram_cfg_wait_o      (s_psram_cfg_wait_o),
      .psram_cfg_chd_wr_en_o (s_psram_cfg_chd_wr_en),
      .psram_cfg_chd_i       (s_psram_cfg_chd_i),
      .psram_cfg_chd_o       (s_psram_cfg_chd_o),
      .irq_o                 (s_natv_irq)
  );

  apb_ip_wrapper u_apb_ip_wrapper (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .mmap_valid_i  (s_mmap_valid),
      .mmap_addr_i   (s_mmap_addr),
      .mmap_wdata_i  (s_mmap_wdata),
      .mmap_wstrb_i  (s_mmap_wstrb),
      .mmap_rdata_o  (s_mmap_rdata),
      .mmap_ready_o  (s_mmap_ready),
      .uart_rx_i     (cust_uart_rx_i),
      .uart_tx_o     (cust_uart_tx_o),
      .pwm_pwm_o     (cust_pwm_pwm_o),
      .ps2_ps2_clk_i (cust_ps2_ps2_clk_i),
      .ps2_ps2_dat_i (cust_ps2_ps2_dat_i),
      .i2c_scl_i     (cust_i2c_scl_i),
      .i2c_scl_o     (cust_i2c_scl_o),
      .i2c_scl_dir_o (cust_i2c_scl_dir_o),
      .i2c_sda_i     (cust_i2c_sda_i),
      .i2c_sda_o     (cust_i2c_sda_o),
      .i2c_sda_dir_o (cust_i2c_sda_dir_o),
      .qspi_spi_clk_o(cust_qspi_spi_clk_o),
      .qspi_spi_csn_o(cust_qspi_spi_csn_o),
      .qspi_spi_sdo_o(cust_qspi_spi_sdo_o),
      .qspi_spi_oe_o (cust_qspi_spi_oe_o),
      .qspi_spi_sdi_i(cust_qspi_spi_sdi_i),
      .spfs_div4_i   (cust_spfs_div4_i),
      .spfs_clk_o    (cust_spfs_clk_o),
      .spfs_cs_o     (cust_spfs_cs_o),
      .spfs_mosi_o   (cust_spfs_mosi_o),
      .spfs_miso_i   (cust_spfs_miso_i),
      .irq_o         (s_apb_irq)
  );

  psram_top u_psram_top (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .cfg_wait_wr_en_i(s_psram_cfg_wait_wr_en),
      .cfg_wait_i      (s_psram_cfg_wait_o),
      .cfg_wait_o      (s_psram_cfg_wait_i),
      .cfg_chd_wr_en_i (s_psram_cfg_chd_wr_en),
      .cfg_chd_i       (s_psram_cfg_chd_o),
      .cfg_chd_o       (s_psram_cfg_chd_i),
      .mem_valid_i     (s_psram_valid),
      .mem_addr_i      ({1'b0, s_psram_addr[22:0]}),
      .mem_wdata_i     (s_psram_wdata),
      .mem_wstrb_i     (s_psram_wstrb),
      .mem_rdata_o     (s_psram_rdata),
      .mem_ready_o     (s_psram_ready),
      .psram_sclk_o    (cust_psram_sclk_o),
      .psram_ce_o      (cust_psram_ce_o),
      .psram_mosi_i    (cust_psram_sio0_i),
      .psram_miso_i    (cust_psram_sio1_i),
      .psram_sio2_i    (cust_psram_sio2_i),
      .psram_sio3_i    (cust_psram_sio3_i),
      .psram_mosi_o    (cust_psram_sio0_o),
      .psram_miso_o    (cust_psram_sio1_o),
      .psram_sio2_o    (cust_psram_sio2_o),
      .psram_sio3_o    (cust_psram_sio3_o),
      .psram_sio_oen_o (cust_psram_sio_oe_o)
  );

endmodule
