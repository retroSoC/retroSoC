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

// `ifdef PICORV32_V
// `error "retrosoc.v must be read before picorv32.v!"
// `endif

/* Note:  Synthesize register memory from flops */
/* Inefficient, but not terribly so */

/* Also note:  To avoid having a hard macro in the place & route    */
/* (method not finished yet in qflow), SRAM pins are brought out to */
/* the retrosoc I/O so that raven_soc.v itself is fully             */
/* synthesizable and routable with qflow as-is.                     */
// `define PICORV32_REGS retrosoc_regs

module retrosoc #(
    /* parameter integer MEM_WORDS = 256; */
    /* Increase scratchpad memory to 4K words */
    // parameter integer MEM_WORDS = 4096;
    parameter integer        MEM_WORDS      = 16384,
    parameter         [31:0] STACKADDR      = (4 * MEM_WORDS),  // end of memory
    parameter         [31:0] PROGADDR_RESET = 32'h0010_0000     // 1 MB into flash
) (
    input         clk_i,
    input         rst_n_i,
    input         xtal_in_i,
    input         clk_pll_i,
    input         clk_ext_sel_i,
    // pass-through mode from housekeeping SPI
    input         hk_pt_i,
    input         hk_pt_csb_i,
    input         hk_pt_sck_i,
    input         hk_pt_sdi_i,
    output        hk_pt_sdo_o,
    //sram if including clk_i and rst_n_i above
    output [ 3:0] ram_wenb_o,
    output [13:0] ram_addr_o,
    output [31:0] ram_wdata_o,
    input  [31:0] ram_rdata_o,
    // memory mapped I/O signals
    output [15:0] gpio_out_o,
    input  [15:0] gpio_in_i,
    output [15:0] gpio_pullupb_o,
    output [15:0] gpio_pulldownb_o,
    output [15:0] gpio_outenb_o,
    input  [ 7:0] spi_slv_ro_config_i,
    input         spi_slv_ro_xtal_ena_i,
    input         spi_slv_ro_reg_ena_i,
    input         spi_slv_ro_pll_cp_ena_i,
    input         spi_slv_ro_pll_vco_ena_i,
    input         spi_slv_ro_pll_bias_ena_i,
    input  [ 3:0] spi_slv_ro_pll_trim_i,
    input  [11:0] spi_slv_ro_mfgr_id_i,
    input  [ 7:0] spi_slv_ro_prod_id_i,
    input  [ 3:0] spi_slv_ro_mask_rev_i,
    output        uart_tx_o,
    input         uart_rx_i,
    input         i2c_scl_i,
    output        i2c_scl_o,
    output        i2c_scl_oeb_o,
    input         i2c_sda_i,
    output        i2c_sda_o,
    output        i2c_sda_oeb_o,
    output        spi_mst_sdo_o,
    output        spi_mst_csb_o,
    output        spi_mst_sck_o,
    input         spi_mst_sdi_i,
    output        spi_mst_oenb_o,
    // irq
    input         irq_pin_i,
    input         irq_spi_i,
    output        trap_o,
    // spi flash
    output        flash_csb_o,
    output        flash_clk_o,
    output        flash_clk_oeb_o,
    output        flash_csb_oeb_o,
    output        flash_io0_oeb_o,
    output        flash_io1_oeb_o,
    output        flash_io2_oeb_o,
    output        flash_io3_oeb_o,
    output        flash_io0_do_o,
    output        flash_io1_do_o,
    output        flash_io2_do_o,
    output        flash_io3_do_o,
    input         flash_io0_di_i,
    input         flash_io1_di_i,
    input         flash_io2_di_i,
    input         flash_io3_di_i
);

  wire        s_iomem_valid;
  reg         r_iomem_ready;
  wire [ 3:0] s_iomem_wstrb;
  wire [31:0] s_iomem_addr;
  wire [31:0] s_iomem_wdata;
  reg  [31:0] r_iomem_rdata;
  // memory-mapped I/O control registers
  reg  [15:0] r_gpio;
  reg  [15:0] r_gpio_pu;
  reg  [15:0] r_gpio_pd;
  reg  [15:0] r_gpio_oeb;
  reg  [ 1:0] r_pll_out_dest;
  reg  [ 1:0] r_xtal_out_dest;
  reg  [ 1:0] r_trap_out_dest;
  reg  [ 1:0] r_irq_7_in_src;
  reg  [ 1:0] r_irq_8_in_src;


  // GPIO assignments
  assign gpio_out_o[0]        = r_gpio[0];
  assign gpio_out_o[1]        = r_gpio[1];
  assign gpio_out_o[2]        = r_gpio[2];
  assign gpio_out_o[3]        = r_gpio[3];
  assign gpio_out_o[4]        = r_gpio[4];
  assign gpio_out_o[5]        = r_xtal_out_dest == 2'b01 ? xtal_in_i : r_gpio[5];
  assign gpio_out_o[6]        = r_xtal_out_dest == 2'b10 ? xtal_in_i : r_gpio[6];
  assign gpio_out_o[7]        = r_xtal_out_dest == 2'b11 ? xtal_in_i : r_gpio[7];
  assign gpio_out_o[8]        = r_pll_out_dest == 2'b01 ? clk_pll_i : r_gpio[8];
  assign gpio_out_o[9]        = r_pll_out_dest == 2'b10 ? clk_i : r_gpio[9];
  assign gpio_out_o[10]       = r_gpio[10];
  assign gpio_out_o[11]       = r_trap_out_dest == 2'b01 ? trap_o : r_gpio[11];
  assign gpio_out_o[12]       = r_trap_out_dest == 2'b10 ? trap_o : r_gpio[12];
  assign gpio_out_o[13]       = r_trap_out_dest == 2'b11 ? trap_o : r_gpio[13];
  assign gpio_out_o[14]       = r_gpio[14];
  assign gpio_out_o[15]       = r_gpio[15];

  assign gpio_outenb_o[0]     = ~rst_n_i | r_gpio_oeb[0];
  assign gpio_outenb_o[1]     = ~rst_n_i | r_gpio_oeb[1];
  assign gpio_outenb_o[2]     = ~rst_n_i | r_gpio_oeb[2];
  assign gpio_outenb_o[3]     = ~rst_n_i | r_gpio_oeb[3];
  assign gpio_outenb_o[4]     = ~rst_n_i | r_gpio_oeb[4];
  assign gpio_outenb_o[5]     = ~rst_n_i | (r_xtal_out_dest == 2'b00 ? r_gpio_oeb[5] : 1'b0);
  assign gpio_outenb_o[6]     = ~rst_n_i | (r_xtal_out_dest == 2'b00 ? r_gpio_oeb[6] : 1'b0);
  assign gpio_outenb_o[7]     = ~rst_n_i | (r_xtal_out_dest == 2'b00 ? r_gpio_oeb[7] : 1'b0);
  assign gpio_outenb_o[8]     = ~rst_n_i | (r_pll_out_dest == 2'b00 ? r_gpio_oeb[8] : 1'b0);
  assign gpio_outenb_o[9]     = ~rst_n_i | (r_pll_out_dest == 2'b00 ? r_gpio_oeb[9] : 1'b0);
  assign gpio_outenb_o[10]    = ~rst_n_i | (r_pll_out_dest == 2'b00 ? r_gpio_oeb[10] : 1'b0);
  assign gpio_outenb_o[11]    = ~rst_n_i | (r_trap_out_dest == 2'b00 ? r_gpio_oeb[11] : 1'b0);
  assign gpio_outenb_o[12]    = ~rst_n_i | (r_trap_out_dest == 2'b00 ? r_gpio_oeb[12] : 1'b0);
  assign gpio_outenb_o[13]    = ~rst_n_i | (r_trap_out_dest == 2'b00 ? r_gpio_oeb[13] : 1'b0);
  assign gpio_outenb_o[14]    = ~rst_n_i | r_gpio_oeb[14];
  assign gpio_outenb_o[15]    = ~rst_n_i | r_gpio_oeb[15];

  assign gpio_pullupb_o[0]    = r_gpio_pu[0];
  assign gpio_pullupb_o[1]    = r_gpio_pu[1];
  assign gpio_pullupb_o[2]    = r_gpio_pu[2];
  assign gpio_pullupb_o[3]    = r_gpio_pu[3];
  assign gpio_pullupb_o[4]    = r_gpio_pu[4];
  assign gpio_pullupb_o[5]    = r_xtal_out_dest == 2'b00 ? r_gpio_pu[5] : 1'b1;
  assign gpio_pullupb_o[6]    = r_xtal_out_dest == 2'b00 ? r_gpio_pu[6] : 1'b1;
  assign gpio_pullupb_o[7]    = r_xtal_out_dest == 2'b00 ? r_gpio_pu[7] : 1'b1;
  assign gpio_pullupb_o[8]    = r_pll_out_dest == 2'b00 ? r_gpio_pu[8] : 1'b1;
  assign gpio_pullupb_o[9]    = r_pll_out_dest == 2'b00 ? r_gpio_pu[9] : 1'b1;
  assign gpio_pullupb_o[10]   = r_pll_out_dest == 2'b00 ? r_gpio_pu[10] : 1'b1;
  assign gpio_pullupb_o[11]   = r_trap_out_dest == 2'b00 ? r_gpio_pu[11] : 1'b1;
  assign gpio_pullupb_o[12]   = r_trap_out_dest == 2'b00 ? r_gpio_pu[12] : 1'b1;
  assign gpio_pullupb_o[13]   = r_trap_out_dest == 2'b00 ? r_gpio_pu[13] : 1'b1;
  assign gpio_pullupb_o[14]   = r_gpio_pu[14];
  assign gpio_pullupb_o[15]   = r_gpio_pu[15];

  assign gpio_pulldownb_o[0]  = r_gpio_pd[0];
  assign gpio_pulldownb_o[1]  = r_gpio_pd[1];
  assign gpio_pulldownb_o[2]  = r_gpio_pd[2];
  assign gpio_pulldownb_o[3]  = r_gpio_pd[3];
  assign gpio_pulldownb_o[4]  = r_gpio_pd[4];
  assign gpio_pulldownb_o[5]  = r_xtal_out_dest == 2'b00 ? r_gpio_pd[5] : 1'b1;
  assign gpio_pulldownb_o[6]  = r_xtal_out_dest == 2'b00 ? r_gpio_pd[6] : 1'b1;
  assign gpio_pulldownb_o[7]  = r_xtal_out_dest == 2'b00 ? r_gpio_pd[7] : 1'b1;
  assign gpio_pulldownb_o[8]  = r_pll_out_dest == 2'b00 ? r_gpio_pd[8] : 1'b1;
  assign gpio_pulldownb_o[9]  = r_pll_out_dest == 2'b00 ? r_gpio_pd[9] : 1'b1;
  assign gpio_pulldownb_o[10] = r_pll_out_dest == 2'b00 ? r_gpio_pd[10] : 1'b1;
  assign gpio_pulldownb_o[11] = r_trap_out_dest == 2'b00 ? r_gpio_pd[11] : 1'b1;
  assign gpio_pulldownb_o[12] = r_trap_out_dest == 2'b00 ? r_gpio_pd[12] : 1'b1;
  assign gpio_pulldownb_o[13] = r_trap_out_dest == 2'b00 ? r_gpio_pd[13] : 1'b1;
  assign gpio_pulldownb_o[14] = r_gpio_pd[14];
  assign gpio_pulldownb_o[15] = r_gpio_pd[15];

  wire s_irq_7, s_irq_8;
  assign s_irq_7 = (r_irq_7_in_src == 2'b01) ? gpio_in_i[0] :
                   (r_irq_7_in_src == 2'b10) ? gpio_in_i[1] :
                   (r_irq_7_in_src == 2'b11) ? gpio_in_i[2] : 1'b0;
  assign s_irq_8 = (r_irq_8_in_src == 2'b01) ? gpio_in_i[3] :
                   (r_irq_8_in_src == 2'b10) ? gpio_in_i[4] :
                   (r_irq_8_in_src == 2'b11) ? gpio_in_i[5] : 1'b0;

  assign ram_wenb_o = (s_mem_valid && !s_mem_ready && s_mem_addr < 4*MEM_WORDS) ?
        {~s_mem_wstrb[3], ~s_mem_wstrb[2], ~s_mem_wstrb[1], ~s_mem_wstrb[0]} : 4'hf;
  assign ram_addr_o = s_mem_addr[15:2];
  assign ram_wdata_o = s_mem_wdata;  // just for naming conventions

  wire [31:0] s_irq;
  wire        s_irq_stall = 0;  // not impl
  wire        s_irq_uart;
  wire        s_irq_i2c;
  wire        s_irq_spi_mst;
  wire        s_irq_tim0;

  assign s_irq[2:0] = 3'd0;
  assign s_irq[3]   = s_irq_stall;
  assign s_irq[4]   = s_irq_uart;
  assign s_irq[5]   = irq_pin_i;
  assign s_irq[6]   = irq_spi_i;
  assign s_irq[7]   = s_irq_7;
  assign s_irq[8]   = s_irq_8;
  assign s_irq[9]   = 1'd0;
  assign s_irq[10]  = 1'd0;
  assign s_irq[11]  = s_irq_i2c;
  assign s_irq[12]  = s_irq_spi_mst;
  assign s_irq[13]  = s_irq_tim0;

  wire        s_mem_valid;
  wire        s_mem_instr;
  wire        s_mem_ready;
  wire [31:0] s_mem_addr;
  wire [31:0] s_mem_wdata;
  wire [ 3:0] s_mem_wstrb;
  wire [31:0] s_mem_rdata;
  wire        s_spimem_ready;
  wire [31:0] s_spimem_rdata;
  reg         r_ram_ready;

  assign s_iomem_valid = s_mem_valid && (s_mem_addr[31:24] > 8'h02);
  assign s_iomem_wstrb = s_mem_wstrb;
  assign s_iomem_addr  = s_mem_addr;
  assign s_iomem_wdata = s_mem_wdata;

  // spi flash
  wire        s_spimemio_cfgreg_sel = s_mem_valid && (s_mem_addr == 32'h0200_0000);
  wire [31:0] s_spimemio_cfgreg_dout;
  // uart
  wire        s_simpleuart_reg_div_sel = s_iomem_valid && (s_iomem_addr == 32'h0300_0078);
  wire        s_simpleuart_reg_dat_sel = s_iomem_valid && (s_iomem_addr == 32'h0300_007c);
  wire [31:0] s_simpleuart_reg_div_dout;
  wire [31:0] s_simpleuart_reg_dat_dout;
  wire        s_simpleuart_reg_dat_wait;
  // i2c
  wire        s_simplei2c_reg_cfg1_sel = s_iomem_valid && (s_iomem_addr == 32'h0300_00d4);
  wire        s_simplei2c_reg_cfg2_sel = s_iomem_valid && (s_iomem_addr == 32'h0300_00d8);
  wire        s_simplei2c_reg_dat_sel = s_iomem_valid && (s_iomem_addr == 32'h0300_00dc);
  wire [31:0] s_simplei2c_reg_cfg1_dout;
  wire [31:0] s_simplei2c_reg_cfg2_dout;
  wire [31:0] s_simplei2c_reg_dat_dout;
  // spi mst
  wire        s_simplespi_reg_cfg_sel = s_iomem_valid && (s_iomem_addr == 32'h0300_00b8);
  wire        s_simplespi_reg_dat_sel = s_iomem_valid && (s_iomem_addr == 32'h0300_00bc);
  wire [31:0] s_simplespi_reg_cfg_dout;
  wire [31:0] s_simplespi_reg_dat_dout;
  wire        s_simplespi_reg_dat_wait;
  // tim
  wire        s_tim0_reg_cfg_sel = s_iomem_valid && (s_iomem_addr == 32'h0300_00f4);
  wire        s_tim0_reg_val_sel = s_iomem_valid && (s_iomem_addr == 32'h0300_00f8);
  wire        s_tim0_reg_dat_sel = s_iomem_valid && (s_iomem_addr == 32'h0300_00fc);
  wire [31:0] s_tim0_reg_cfg_dout;
  wire [31:0] s_tim0_reg_val_dout;
  wire [31:0] s_tim0_reg_dat_dout;

  assign s_mem_ready = (s_iomem_valid && r_iomem_ready) ||
                       s_spimem_ready || r_ram_ready || s_spimemio_cfgreg_sel;

  assign s_mem_rdata = (s_iomem_valid && r_iomem_ready) ? r_iomem_rdata :
                       s_spimem_ready ? s_spimem_rdata :
                       r_ram_ready ? ram_rdata_o :
                       s_spimemio_cfgreg_sel ? s_spimemio_cfgreg_dout :
                       32'h0000_0000;


  // retroSoC memory mapped IP
  // 1 crystal oscillator
  // 1 I2C master
  // 1 SPI master
  // 1 32-bit counter/timer
  // 1 QSPI flash controller
  // 1 UART

  // NOTE: Signals affecting critical core functions are controlled through
  // an independent SPI having read-only access through the picorv32 core.
  // SPI pins are independent of picorv32 SPI master. Signals controlled
  // by the SPI are:
  // 1) crystal oscillator enable (default on)
  // 2) PLL enables (default on)
  // 3) PLL trim (default TBD)
  // NOTE:  SPI should have a pass-through mode that configures SDO as a
  // copy of a chosen signal for as long as CSB is held low. This can be
  // an SPI command, allows other internal signals to be passed to the
  // output and viewed, including the RC oscillator output, comparator
  // output, and other edge-based signals.

  // Memory map:
  // GPIO: 32 channels total
  //          addr 0x03000000-1   data (16 bits)
  //          addr 0x03000004-5   out (=0) or in (=1) (default 1)
  //          addr 0x03000008-9   pu (=0)  or none (=1) (default 1)
  //          addr 0x0300000c-d   pd (=0)  or none (=1) (default 1)
  //
  // UART:
  //          addr 0x03000078     clock divider
  //          addr 0x0300007c     data
  //
  // SPI SLV:
  //          addr 0x03000080     SPI configuration
  //          addr 0x03000084     xtal osc, reg, bg enables
  //          addr 0x03000088     PLL enables, trim
  //          addr 0x0300008c-d   manufacturer ID
  //          addr 0x03000090     product ID
  //          addr 0x03000094     product mask revision
  //          addr 0x03000098     external clock select
  //          addr 0x030000a0     xtal osc output dest (ext r_gpio pin 5-7)
  //          addr 0x030000a4     PLL output dest (ext r_gpio pin 8-10)
  //          addr 0x030000a8     trap_o output dest (ext r_gpio pin 11-13)
  //          addr 0x030000b0     IRQ 7 source (ext r_gpio pin 0-3)
  //          addr 0x030000b4     IRQ 8 source (ext r_gpio pin 4-7)
  //
  // SPI MST:
  //          addr 0x030000b8     configuration
  //          addr 0x030000bc     data
  //
  // I2C:     
  //          addr 0x030000d4     configuration (1)
  //          addr 0x030000d8     configuration (2)
  //          addr 0x030000dc     data
  //
  // TIM:
  //           addr 0x030000f4    configuration
  //           addr 0x030000f8-b  count resetn value
  //           addr 0x030000fc-f  count current value
  picorv32 #(
      .PROGADDR_RESET  (PROGADDR_RESET),
      .PROGADDR_IRQ    (32'h0000_0000),
      .STACKADDR       (STACKADDR),
      .BARREL_SHIFTER  (1),
      .COMPRESSED_ISA  (1),
      .ENABLE_MUL      (1),
      .ENABLE_FAST_MUL (1),
      .ENABLE_DIV      (1),
      .ENABLE_IRQ      (1),
      .ENABLE_IRQ_QREGS(0)
  ) u_picorv32 (
      .clk      (clk_i),
      .resetn   (rst_n_i),
      .mem_valid(s_mem_valid),
      .mem_instr(s_mem_instr),
      .mem_ready(s_mem_ready),
      .mem_addr (s_mem_addr),
      .mem_wdata(s_mem_wdata),
      .mem_wstrb(s_mem_wstrb),
      .mem_rdata(s_mem_rdata),
      .irq      (s_irq),
      .trap     (trap_o)
  );

  spimemio u_spimemio (
      .clk          (clk_i),
      .resetn       (rst_n_i),
      .valid        (s_mem_valid && s_mem_addr >= 4 * MEM_WORDS && s_mem_addr < 32'h0200_0000),
      .ready        (s_spimem_ready),
      .addr         (s_mem_addr[23:0]),
      .rdata        (s_spimem_rdata),
      .pass_thru    (hk_pt_i),
      .pass_thru_csb(hk_pt_csb_i),
      .pass_thru_sck(hk_pt_sck_i),
      .pass_thru_sdi(hk_pt_sdi_i),
      .pass_thru_sdo(hk_pt_sdo_o),
      .flash_csb    (flash_csb_o),
      .flash_clk    (flash_clk_o),
      .flash_csb_oeb(flash_csb_oeb_o),
      .flash_clk_oeb(flash_clk_oeb_o),
      .flash_io0_oeb(flash_io0_oeb_o),
      .flash_io1_oeb(flash_io1_oeb_o),
      .flash_io2_oeb(flash_io2_oeb_o),
      .flash_io3_oeb(flash_io3_oeb_o),
      .flash_io0_do (flash_io0_do_o),
      .flash_io1_do (flash_io1_do_o),
      .flash_io2_do (flash_io2_do_o),
      .flash_io3_do (flash_io3_do_o),
      .flash_io0_di (flash_io0_di_i),
      .flash_io1_di (flash_io1_di_i),
      .flash_io2_di (flash_io2_di_i),
      .flash_io3_di (flash_io3_di_i),
      .cfgreg_we    (s_spimemio_cfgreg_sel ? s_mem_wstrb : 4'b0000),
      .cfgreg_di    (s_mem_wdata),
      .cfgreg_do    (s_spimemio_cfgreg_dout)
  );

  simpleuart u_simpleuart (
      .clk         (clk_i),
      .resetn      (rst_n_i),
      .ser_tx      (uart_tx_o),
      .ser_rx      (uart_rx_i),
      .reg_div_we  (s_simpleuart_reg_div_sel ? s_iomem_wstrb : 4'b0000),
      .reg_div_di  (s_iomem_wdata),
      .reg_div_do  (s_simpleuart_reg_div_dout),
      .reg_dat_we  (s_simpleuart_reg_dat_sel ? s_iomem_wstrb[0] : 1'b0),
      .reg_dat_re  (s_simpleuart_reg_dat_sel && !s_iomem_wstrb),
      .reg_dat_di  (s_iomem_wdata),
      .reg_dat_do  (s_simpleuart_reg_dat_dout),
      .reg_dat_wait(s_simpleuart_reg_dat_wait),
      .irq_out     (s_irq_uart)
  );

  simple_i2c_master u_simplei2c_master (
      .clk         (clk_i),
      .resetn      (rst_n_i),
      .reg_cfg1_we (s_simplei2c_reg_cfg1_sel ? s_iomem_wstrb[2:0] : 3'b000),
      .reg_cfg1_di (s_iomem_wdata),
      .reg_cfg1_do (s_simplei2c_reg_cfg1_dout),
      .reg_cfg2_we (s_simplei2c_reg_cfg2_sel ? s_iomem_wstrb[0] : 1'b0),
      .reg_cfg2_di (s_iomem_wdata),
      .reg_cfg2_do (s_simplei2c_reg_cfg2_dout),
      .reg_dat_we  (s_simplei2c_reg_dat_sel ? s_iomem_wstrb[0] : 1'b0),
      .reg_dat_re  (s_simplei2c_reg_dat_sel && !s_iomem_wstrb),
      .reg_dat_di  (s_iomem_wdata),
      .reg_dat_do  (s_simplei2c_reg_dat_dout),
      .scl_pad_i   (i2c_scl_i),
      .scl_pad_o   (i2c_scl_o),
      .scl_padoeb_o(i2c_scl_oeb_o),
      .sda_pad_i   (i2c_sda_i),
      .sda_pad_o   (i2c_sda_o),
      .sda_padoeb_o(i2c_sda_oeb_o),
      .irq_o       (s_irq_i2c)
  );

  simple_spi_master u_simple_spi_master (
      .resetn      (rst_n_i),
      .clk         (clk_i),
      .reg_cfg_we  (s_simplespi_reg_cfg_sel ? s_iomem_wstrb[1:0] : 2'b00),
      .reg_cfg_di  (s_iomem_wdata),
      .reg_cfg_do  (s_simplespi_reg_cfg_dout),
      .reg_dat_we  (s_simplespi_reg_dat_sel ? s_iomem_wstrb[0] : 1'b0),
      .reg_dat_re  (s_simplespi_reg_dat_sel && !s_iomem_wstrb),
      .reg_dat_di  (s_iomem_wdata),
      .reg_dat_do  (s_simplespi_reg_dat_dout),
      .reg_dat_wait(s_simplespi_reg_dat_wait),
      .irq_out     (s_irq_spi_mst),
      .sdi         (spi_mst_sdi_i),
      .csb         (spi_mst_csb_o),
      .sck         (spi_mst_sck_o),
      .sdo         (spi_mst_sdo_o),
      .sdoenb      (spi_mst_oenb_o)
  );

  counter_timer u_counter_timer (
      .resetn    (rst_n_i),
      .clkin     (clk_i),
      .reg_val_we(s_tim0_reg_val_sel ? s_iomem_wstrb[3:0] : 4'h0),
      .reg_val_di(s_iomem_wdata),
      .reg_val_do(s_tim0_reg_val_dout),
      .reg_cfg_we(s_tim0_reg_cfg_sel ? s_iomem_wstrb[0] : 1'b0),
      .reg_cfg_di(s_iomem_wdata),
      .reg_cfg_do(s_tim0_reg_cfg_dout),
      .reg_dat_we(s_tim0_reg_dat_sel ? s_iomem_wstrb[3:0] : 4'h0),
      .reg_dat_di(s_iomem_wdata),
      .reg_dat_do(s_tim0_reg_dat_dout),
      .irq_out   (s_irq_tim0)
  );

  always @(posedge clk_i) begin
    r_ram_ready <= s_mem_valid && !s_mem_ready && s_mem_addr < 4 * MEM_WORDS;
  end

  always @(posedge clk_i) begin
    if (!rst_n_i) begin
      r_gpio          <= 0;
      r_gpio_oeb      <= 16'hffff;
      r_gpio_pu       <= 0;
      r_gpio_pd       <= 0;
      r_pll_out_dest  <= 0;
      r_xtal_out_dest <= 0;
      r_trap_out_dest <= 0;
      r_irq_7_in_src  <= 0;
      r_irq_8_in_src  <= 0;
    end else begin
      if (s_iomem_valid && !r_iomem_ready && s_iomem_addr[31:8] == 24'h030000) begin
        // Handle r_iomem_ready based on wait states
        case (s_iomem_addr[7:0])
          8'h7c:   r_iomem_ready = ~s_simpleuart_reg_dat_wait;
          8'hbc:   r_iomem_ready = ~s_simplespi_reg_dat_wait;
          default: r_iomem_ready = 1'b1;
        endcase
        case (s_iomem_addr[7:0])
          8'h00: begin
            r_iomem_rdata <= {gpio_out_o, gpio_in_i};
            if (s_iomem_wstrb[0]) r_gpio[7:0] <= s_iomem_wdata[7:0];
            if (s_iomem_wstrb[1]) r_gpio[15:8] <= s_iomem_wdata[15:8];
          end
          8'h04: begin
            r_iomem_rdata <= {16'd0, r_gpio_oeb};
            if (s_iomem_wstrb[0]) r_gpio_oeb[7:0] <= s_iomem_wdata[7:0];
            if (s_iomem_wstrb[1]) r_gpio_oeb[15:8] <= s_iomem_wdata[15:8];
          end
          8'h08: begin
            r_iomem_rdata <= {16'd0, r_gpio_pu};
            if (s_iomem_wstrb[0]) r_gpio_pu[7:0] <= s_iomem_wdata[7:0];
            if (s_iomem_wstrb[1]) r_gpio_pu[15:8] <= s_iomem_wdata[15:8];
          end
          8'h0c: begin
            r_iomem_rdata <= {16'd0, r_gpio_pu};
            if (s_iomem_wstrb[0]) r_gpio_pd[7:0] <= s_iomem_wdata[7:0];
            if (s_iomem_wstrb[1]) r_gpio_pd[15:8] <= s_iomem_wdata[15:8];
          end
          8'h78: r_iomem_rdata <= s_simpleuart_reg_div_dout;
          8'h7c: r_iomem_rdata <= s_simpleuart_reg_dat_dout;
          8'h80: r_iomem_rdata <= {24'd0, spi_slv_ro_config_i};
          8'h84: r_iomem_rdata <= {30'd0, spi_slv_ro_xtal_ena_i, spi_slv_ro_reg_ena_i};
          8'h88: begin
            r_iomem_rdata <= {
              25'd0,
              spi_slv_ro_pll_trim_i,
              spi_slv_ro_pll_cp_ena_i,
              spi_slv_ro_pll_vco_ena_i,
              spi_slv_ro_pll_bias_ena_i
            };
          end
          8'h8c: r_iomem_rdata <= {20'd0, spi_slv_ro_mfgr_id_i};
          8'h90: r_iomem_rdata <= {24'd0, spi_slv_ro_prod_id_i};
          8'h94: r_iomem_rdata <= {28'd0, spi_slv_ro_mask_rev_i};
          8'h98: r_iomem_rdata <= {31'd0, clk_ext_sel_i};
          8'ha0: begin
            r_iomem_rdata <= {30'd0, r_xtal_out_dest};
            if (s_iomem_wstrb[0]) r_xtal_out_dest <= s_iomem_wdata[1:0];
          end
          8'ha4: begin
            r_iomem_rdata <= {30'd0, r_pll_out_dest};
            if (s_iomem_wstrb[0]) r_pll_out_dest <= s_iomem_wdata[1:0];
          end
          8'ha8: begin
            r_iomem_rdata <= {30'd0, r_trap_out_dest};
            if (s_iomem_wstrb[0]) r_trap_out_dest <= s_iomem_wdata[1:0];
          end
          8'hb0: begin
            r_iomem_rdata <= {30'd0, r_irq_7_in_src};
            if (s_iomem_wstrb[0]) r_irq_7_in_src <= s_iomem_wdata[1:0];
          end
          8'hb4: begin
            r_iomem_rdata <= {30'd0, r_irq_8_in_src};
            if (s_iomem_wstrb[0]) r_irq_8_in_src <= s_iomem_wdata[1:0];
          end
          8'hb8: r_iomem_rdata <= s_simplespi_reg_cfg_dout;
          8'hbc: r_iomem_rdata <= s_simplespi_reg_dat_dout;
          8'hd4: r_iomem_rdata <= s_simplei2c_reg_cfg1_dout;
          8'hd8: r_iomem_rdata <= s_simplei2c_reg_cfg2_dout;
          8'hdc: r_iomem_rdata <= s_simplei2c_reg_dat_dout;
          8'hf4: r_iomem_rdata <= {28'd0, s_tim0_reg_cfg_dout};
          8'hf8: r_iomem_rdata <= s_tim0_reg_val_dout;
          8'hfc: r_iomem_rdata <= s_tim0_reg_dat_dout;
        endcase
      end else begin
        r_iomem_ready = 1'b0;
      end
    end
  end
endmodule

// implementation note:
// replace the following two modules with wrappers for your SRAM cells.
// module retrosoc_regs (
//     input         clk,
//     input         wen,
//     input  [ 5:0] waddr,
//     input  [ 5:0] raddr1,
//     input  [ 5:0] raddr2,
//     input  [31:0] wdata,
//     output [31:0] rdata1,
//     output [31:0] rdata2
// );
//   reg [31:0] regs[0:31];

//   always @(posedge clk) if (wen) regs[waddr[4:0]] <= wdata;

//   assign rdata1 = regs[raddr1[4:0]];
//   assign rdata2 = regs[raddr2[4:0]];
// endmodule