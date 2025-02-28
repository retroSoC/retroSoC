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


/* Note:  Synthesize register memory from flops */
/* Inefficient, but not terribly so */
/* Also note:  To avoid having a hard macro in the place & route    */
/* (method not finished yet in qflow), SRAM pins are brought out to */
/* the retrosoc I/O so that raven_soc.v itself is fully             */
/* synthesizable and routable with qflow as-is.                     */

module retrosoc_tiny #(
    parameter integer        MEM_WORDS      = 16384 * 2,
    parameter         [31:0] STACKADDR      = (4 * MEM_WORDS),  // end of memory
    parameter         [31:0] PROGADDR_RESET = 32'h3000_0000     // flash
) (
    input         clk_i,
    input         rst_n_i,
    input         clk_ext_sel_i,
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
    // cust
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
  // core mem native if
  wire        s_mem_valid;
  wire        s_mem_instr;
  wire        s_mem_ready;
  wire [31:0] s_mem_addr;
  wire [31:0] s_mem_wdata;
  wire [ 3:0] s_mem_wstrb;
  wire [31:0] s_mem_rdata;
  // mem map io if
  wire        s_iomem_valid;
  reg         r_iomem_ready;
  wire [ 3:0] s_iomem_wstrb;
  wire [31:0] s_iomem_addr;
  wire [31:0] s_iomem_wdata;
  reg  [31:0] r_iomem_rdata;
  wire        s_aximem_ready;
  wire [31:0] s_aximem_rdata;
  // psram if
  wire        s_psram_valid;
  wire        s_psram_ready;
  wire [ 3:0] s_psram_wstrb;
  wire [31:0] s_psram_addr;
  wire [31:0] s_psram_wdata;
  wire [31:0] s_psram_rdata;
  // mmio ctrl regs
  reg  [15:0] r_gpio;
  reg  [15:0] r_gpio_pu;
  reg  [15:0] r_gpio_pd;
  reg  [15:0] r_gpio_oeb;
  // mmio axil if
  wire        s_mem_axi_awvalid;
  wire        s_mem_axi_awready;
  wire [31:0] s_mem_axi_awaddr;
  wire [ 2:0] s_mem_axi_awprot;
  wire        s_mem_axi_wvalid;
  wire        s_mem_axi_wready;
  wire [31:0] s_mem_axi_wdata;
  wire [ 3:0] s_mem_axi_wstrb;
  wire        s_mem_axi_bvalid;
  wire        s_mem_axi_bready;
  wire        s_mem_axi_arvalid;
  wire        s_mem_axi_arready;
  wire [31:0] s_mem_axi_araddr;
  wire [ 2:0] s_mem_axi_arprot;
  wire        s_mem_axi_rvalid;
  wire        s_mem_axi_rready;
  wire [31:0] s_mem_axi_rdata;
  // irq
  wire [31:0] s_irq;
  wire        s_irq_stall = 0;
  wire        s_irq_uart;
  wire        s_irq_tim0;
  wire        s_cust_qspi_irq;
  wire        s_cust_spfs_irq;

  // GPIO assignments
  assign gpio_out_o[0]        = r_gpio[0];
  assign gpio_out_o[1]        = r_gpio[1];
  assign gpio_out_o[2]        = r_gpio[2];
  assign gpio_out_o[3]        = r_gpio[3];
  assign gpio_out_o[4]        = r_gpio[4];
  assign gpio_out_o[5]        = r_gpio[5];
  assign gpio_out_o[6]        = r_gpio[6];
  assign gpio_out_o[7]        = r_gpio[7];
  assign gpio_out_o[8]        = r_gpio[8];
  assign gpio_out_o[9]        = r_gpio[9];
  assign gpio_out_o[10]       = r_gpio[10];
  assign gpio_out_o[11]       = r_gpio[11];
  assign gpio_out_o[12]       = r_gpio[12];
  assign gpio_out_o[13]       = r_gpio[13];
  assign gpio_out_o[14]       = r_gpio[14];
  assign gpio_out_o[15]       = r_gpio[15];

  assign gpio_outenb_o[0]     = ~rst_n_i | r_gpio_oeb[0];
  assign gpio_outenb_o[1]     = ~rst_n_i | r_gpio_oeb[1];
  assign gpio_outenb_o[2]     = ~rst_n_i | r_gpio_oeb[2];
  assign gpio_outenb_o[3]     = ~rst_n_i | r_gpio_oeb[3];
  assign gpio_outenb_o[4]     = ~rst_n_i | r_gpio_oeb[4];
  assign gpio_outenb_o[5]     = ~rst_n_i | r_gpio_oeb[5];
  assign gpio_outenb_o[6]     = ~rst_n_i | r_gpio_oeb[6];
  assign gpio_outenb_o[7]     = ~rst_n_i | r_gpio_oeb[7];
  assign gpio_outenb_o[8]     = ~rst_n_i | r_gpio_oeb[8];
  assign gpio_outenb_o[9]     = ~rst_n_i | r_gpio_oeb[9];
  assign gpio_outenb_o[10]    = ~rst_n_i | r_gpio_oeb[10];
  assign gpio_outenb_o[11]    = ~rst_n_i | r_gpio_oeb[11];
  assign gpio_outenb_o[12]    = ~rst_n_i | r_gpio_oeb[12];
  assign gpio_outenb_o[13]    = ~rst_n_i | r_gpio_oeb[13];
  assign gpio_outenb_o[14]    = ~rst_n_i | r_gpio_oeb[14];
  assign gpio_outenb_o[15]    = ~rst_n_i | r_gpio_oeb[15];

  assign gpio_pullupb_o[0]    = r_gpio_pu[0];
  assign gpio_pullupb_o[1]    = r_gpio_pu[1];
  assign gpio_pullupb_o[2]    = r_gpio_pu[2];
  assign gpio_pullupb_o[3]    = r_gpio_pu[3];
  assign gpio_pullupb_o[4]    = r_gpio_pu[4];
  assign gpio_pullupb_o[5]    = r_gpio_pu[5];
  assign gpio_pullupb_o[6]    = r_gpio_pu[6];
  assign gpio_pullupb_o[7]    = r_gpio_pu[7];
  assign gpio_pullupb_o[8]    = r_gpio_pu[8];
  assign gpio_pullupb_o[9]    = r_gpio_pu[9];
  assign gpio_pullupb_o[10]   = r_gpio_pu[10];
  assign gpio_pullupb_o[11]   = r_gpio_pu[11];
  assign gpio_pullupb_o[12]   = r_gpio_pu[12];
  assign gpio_pullupb_o[13]   = r_gpio_pu[13];
  assign gpio_pullupb_o[14]   = r_gpio_pu[14];
  assign gpio_pullupb_o[15]   = r_gpio_pu[15];

  assign gpio_pulldownb_o[0]  = r_gpio_pd[0];
  assign gpio_pulldownb_o[1]  = r_gpio_pd[1];
  assign gpio_pulldownb_o[2]  = r_gpio_pd[2];
  assign gpio_pulldownb_o[3]  = r_gpio_pd[3];
  assign gpio_pulldownb_o[4]  = r_gpio_pd[4];
  assign gpio_pulldownb_o[5]  = r_gpio_pd[5];
  assign gpio_pulldownb_o[6]  = r_gpio_pd[6];
  assign gpio_pulldownb_o[7]  = r_gpio_pd[7];
  assign gpio_pulldownb_o[8]  = r_gpio_pd[8];
  assign gpio_pulldownb_o[9]  = r_gpio_pd[9];
  assign gpio_pulldownb_o[10] = r_gpio_pd[10];
  assign gpio_pulldownb_o[11] = r_gpio_pd[11];
  assign gpio_pulldownb_o[12] = r_gpio_pd[12];
  assign gpio_pulldownb_o[13] = r_gpio_pd[13];
  assign gpio_pulldownb_o[14] = r_gpio_pd[14];
  assign gpio_pulldownb_o[15] = r_gpio_pd[15];

  assign s_irq[2:0]           = 3'd0;
  assign s_irq[3]             = s_irq_stall;
  assign s_irq[4]             = s_irq_uart;
  assign s_irq[5]             = 1'b0;
  assign s_irq[6]             = 1'b0;
  assign s_irq[7]             = s_irq_tim0;
  assign s_irq[8]             = s_cust_qspi_irq;
  assign s_irq[9]             = s_cust_spfs_irq;
  assign s_irq[31:10]         = 22'd0;

  // memory mapped IP
  // 16 x GPIO
  // 1  x UART
  // 1  x TIMER
  // AXIL WRAPPER
  //    1 x QSPI
  //    1 x PSRAM(8MB)
  //    1 x SPFS(HP)
  picorv32 #(
      .PROGADDR_RESET  (PROGADDR_RESET),
      .PROGADDR_IRQ    (32'h0000_0000),
      .STACKADDR       (STACKADDR),
      .BARREL_SHIFTER  (1),
      .COMPRESSED_ISA  (0),
      .ENABLE_MUL      (0),
      .ENABLE_FAST_MUL (0),
      .ENABLE_DIV      (0),
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
      .trap     ()
  );

  // mmio native perip
  assign s_iomem_valid = s_mem_valid && (s_mem_addr[31:24] == 8'h03 || s_mem_addr >= 32'h3000_0000);
  assign s_iomem_wstrb = s_mem_wstrb;
  assign s_iomem_addr = s_mem_addr;
  assign s_iomem_wdata = s_mem_wdata;
  // uart
  wire        s_simpleuart_reg_div_sel = s_iomem_valid && (s_iomem_addr == 32'h0300_0010);
  wire        s_simpleuart_reg_dat_sel = s_iomem_valid && (s_iomem_addr == 32'h0300_0014);
  wire [31:0] s_simpleuart_reg_div_dout;
  wire [31:0] s_simpleuart_reg_dat_dout;
  wire        s_simpleuart_reg_dat_wait;
  // tim0
  wire        s_tim0_reg_cfg_sel = s_iomem_valid && (s_iomem_addr == 32'h0300_005c);
  wire        s_tim0_reg_val_sel = s_iomem_valid && (s_iomem_addr == 32'h0300_0060);
  wire        s_tim0_reg_dat_sel = s_iomem_valid && (s_iomem_addr == 32'h0300_0064);
  wire [31:0] s_tim0_reg_cfg_dout;
  wire [31:0] s_tim0_reg_val_dout;
  wire [31:0] s_tim0_reg_dat_dout;
  // psram
  wire        s_psram_cfg_wait_sel = s_iomem_valid && (s_iomem_addr == 32'h0300_0080);
  wire        s_psram_cfg_chd_sel = s_iomem_valid && (s_iomem_addr == 32'h0300_0084);
  reg  [ 4:0] r_psram_cfg_wait_din;
  wire [ 4:0] s_psram_cfg_wait_dout;
  reg  [ 2:0] r_psram_cfg_chd_din;
  wire [ 2:0] s_psram_cfg_chd_dout;

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

  counter_timer u_counter_timer0 (
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

  assign s_psram_addr  = s_mem_addr;
  assign s_psram_wdata = s_mem_wdata;
  assign s_psram_wstrb = s_mem_wstrb;
  assign s_psram_valid = s_mem_valid && (s_mem_addr[31:24] == 8'h04);
  psram_top u_psram_top (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .cfg_wait_wr_en_i(s_psram_cfg_wait_sel ? s_iomem_wstrb[0] : 1'b0),
      .cfg_wait_i      (r_psram_cfg_wait_din),
      .cfg_wait_o      (s_psram_cfg_wait_dout),
      .cfg_chd_wr_en_i (s_psram_cfg_chd_sel ? s_iomem_wstrb[0] : 1'b0),
      .cfg_chd_i       (r_psram_cfg_chd_din),
      .cfg_chd_o       (s_psram_cfg_chd_dout),
      .mem_valid_i     (s_psram_valid),
      .mem_ready_o     (s_psram_ready),
      .mem_addr_i      ({1'b0, s_psram_addr[22:0]}),
      .mem_wdata_i     (s_psram_wdata),
      .mem_wstrb_i     (s_psram_wstrb),
      .mem_rdata_o     (s_psram_rdata),
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

  wire s_aximem_range = (s_iomem_addr[31:8] >= 24'h0300_10 && s_iomem_addr[31:8] <= 24'h03FF_FF) || s_iomem_addr >= 32'h3000_0000;
  picorv32_axi_adapter u_core2axi (
      .clk            (clk_i),
      .resetn         (rst_n_i),
      .mem_axi_awvalid(s_mem_axi_awvalid),
      .mem_axi_awready(s_mem_axi_awready),
      .mem_axi_awaddr (s_mem_axi_awaddr),
      .mem_axi_awprot (s_mem_axi_awprot),
      .mem_axi_wvalid (s_mem_axi_wvalid),
      .mem_axi_wready (s_mem_axi_wready),
      .mem_axi_wdata  (s_mem_axi_wdata),
      .mem_axi_wstrb  (s_mem_axi_wstrb),
      .mem_axi_bvalid (s_mem_axi_bvalid),
      .mem_axi_bready (s_mem_axi_bready),
      .mem_axi_arvalid(s_mem_axi_arvalid),
      .mem_axi_arready(s_mem_axi_arready),
      .mem_axi_araddr (s_mem_axi_araddr),
      .mem_axi_arprot (s_mem_axi_arprot),
      .mem_axi_rvalid (s_mem_axi_rvalid),
      .mem_axi_rready (s_mem_axi_rready),
      .mem_axi_rdata  (s_mem_axi_rdata),
      .mem_valid      (s_iomem_valid && s_aximem_range),
      .mem_instr      (s_mem_instr),
      .mem_ready      (s_aximem_ready),
      .mem_addr       (s_iomem_addr),
      .mem_wdata      (s_iomem_wdata),
      .mem_wstrb      (s_iomem_wstrb),
      .mem_rdata      (s_aximem_rdata)
  );

  axil_ip_wrapper_tiny u_axil_ip_wrapper_tiny (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .mem_axi_awvalid(s_mem_axi_awvalid),
      .mem_axi_awready(s_mem_axi_awready),
      .mem_axi_awaddr (s_mem_axi_awaddr),
      .mem_axi_awprot (s_mem_axi_awprot),
      .mem_axi_wvalid (s_mem_axi_wvalid),
      .mem_axi_wready (s_mem_axi_wready),
      .mem_axi_wdata  (s_mem_axi_wdata),
      .mem_axi_wstrb  (s_mem_axi_wstrb),
      .mem_axi_bvalid (s_mem_axi_bvalid),
      .mem_axi_bready (s_mem_axi_bready),
      .mem_axi_arvalid(s_mem_axi_arvalid),
      .mem_axi_arready(s_mem_axi_arready),
      .mem_axi_araddr (s_mem_axi_araddr),
      .mem_axi_arprot (s_mem_axi_arprot),
      .mem_axi_rvalid (s_mem_axi_rvalid),
      .mem_axi_rready (s_mem_axi_rready),
      .mem_axi_rdata  (s_mem_axi_rdata),
      .qspi_spi_clk_o (cust_qspi_spi_clk_o),
      .qspi_spi_csn_o (cust_qspi_spi_csn_o),
      .qspi_spi_sdo_o (cust_qspi_spi_sdo_o),
      .qspi_spi_oe_o  (cust_qspi_spi_oe_o),
      .qspi_spi_sdi_i (cust_qspi_spi_sdi_i),
      .qspi_irq_o     (s_cust_qspi_irq),
      .spfs_div4_i    (cust_spfs_div4_i),
      .spfs_clk_o     (cust_spfs_clk_o),
      .spfs_cs_o      (cust_spfs_cs_o),
      .spfs_mosi_o    (cust_spfs_mosi_o),
      .spfs_miso_i    (cust_spfs_miso_i),
      .spfs_irq_o     (s_cust_spfs_irq)
  );

  always @(posedge clk_i, negedge rst_n_i) begin
    if (!rst_n_i) begin
      r_gpio     <= 0;
      r_gpio_oeb <= 16'hffff;
      r_gpio_pu  <= 0;
      r_gpio_pd  <= 0;
    end else begin
      if (s_iomem_valid && !r_iomem_ready && s_iomem_addr[31:8] == 24'h0300_00) begin
        // Handle r_iomem_ready based on wait states
        case (s_iomem_addr[7:0])
          8'h14:   r_iomem_ready <= ~s_simpleuart_reg_dat_wait;
          default: r_iomem_ready <= 1'b1;
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
          8'h10: r_iomem_rdata <= s_simpleuart_reg_div_dout;
          8'h14: r_iomem_rdata <= s_simpleuart_reg_dat_dout;
          8'h18: r_iomem_rdata <= {24'd0, spi_slv_ro_config_i};
          8'h1c: r_iomem_rdata <= {30'd0, spi_slv_ro_xtal_ena_i, spi_slv_ro_reg_ena_i};
          8'h20: begin
            r_iomem_rdata <= {
              25'd0,
              spi_slv_ro_pll_trim_i,
              spi_slv_ro_pll_cp_ena_i,
              spi_slv_ro_pll_vco_ena_i,
              spi_slv_ro_pll_bias_ena_i
            };
          end
          8'h24: r_iomem_rdata <= {20'd0, spi_slv_ro_mfgr_id_i};
          8'h28: r_iomem_rdata <= {24'd0, spi_slv_ro_prod_id_i};
          8'h2c: r_iomem_rdata <= {28'd0, spi_slv_ro_mask_rev_i};
          8'h30: r_iomem_rdata <= {31'd0, clk_ext_sel_i};
          8'h5c: r_iomem_rdata <= s_tim0_reg_cfg_dout;
          8'h60: r_iomem_rdata <= s_tim0_reg_val_dout;
          8'h64: r_iomem_rdata <= s_tim0_reg_dat_dout;
          8'h80: begin
            r_iomem_rdata <= {27'd0, s_psram_cfg_wait_dout};
            if (s_iomem_wstrb[0]) r_psram_cfg_wait_din <= s_iomem_wdata[4:0];
          end
          8'h84: begin
            r_iomem_rdata <= {29'd0, s_psram_cfg_chd_dout};
            if (s_iomem_wstrb[0]) r_psram_cfg_chd_din <= s_iomem_wdata[2:0];
          end
        endcase
      end else if (s_iomem_valid && !r_iomem_ready && s_aximem_range) begin
        r_iomem_ready <= s_aximem_ready;
        r_iomem_rdata <= s_aximem_rdata;
      end else begin
        r_iomem_ready <= 1'b0;
      end
    end
  end

  // data mux
  assign s_mem_ready = (s_iomem_valid && r_iomem_ready) || s_psram_ready;
  assign s_mem_rdata = (s_iomem_valid && r_iomem_ready) ? r_iomem_rdata :
                       s_psram_ready ? s_psram_rdata : 32'h0000_0000;

endmodule
