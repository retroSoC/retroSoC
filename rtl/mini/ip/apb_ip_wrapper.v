module apb_ip_wrapper (
    input         clk_i,
    input         rst_n_i,
    // mem if
    input         mem_valid_i,
    input         mem_instr_i,
    output        mem_ready_o,
    input  [31:0] mem_addr_i,
    input  [31:0] mem_wdata_i,
    input  [ 3:0] mem_wstrb_i,
    output [31:0] mem_rdata_o,
    // uart
    input         uart_rx_i,
    output        uart_tx_o,
    output        uart_irq_o,
    // pwm
    output [ 3:0] pwm_pwm_o,
    output        pwm_irq_o,
    // ps2
    input         ps2_ps2_clk_i,
    input         ps2_ps2_dat_i,
    output        ps2_irq_o,
    // i2c
    input         i2c_scl_i,
    output        i2c_scl_o,
    output        i2c_scl_dir_o,
    input         i2c_sda_i,
    output        i2c_sda_o,
    output        i2c_sda_dir_o,
    output        i2c_irq_o,
    // qspi
    output        qspi_spi_clk_o,
    output [ 3:0] qspi_spi_csn_o,
    output [ 3:0] qspi_spi_sdo_o,
    output [ 3:0] qspi_spi_oe_o,
    input  [ 3:0] qspi_spi_sdi_i,
    output        qspi_irq_o,
    // spfs
    input         spfs_div4_i,
    output        spfs_clk_o,
    output        spfs_cs_o,
    output        spfs_mosi_o,
    input         spfs_miso_i,
    output        spfs_irq_o
);

  localparam APB_SLAVES_NUM = 8;

  wire [              31:0] s_m_apb_paddr;
  wire [               2:0] s_m_apb_pprot;
  wire [APB_SLAVES_NUM-1:0] s_m_apb_psel;
  wire                      s_m_apb_penable;
  wire                      s_m_apb_pwrite;
  wire [              31:0] s_m_apb_pwdata;
  wire [               3:0] s_m_apb_pstrb;
  wire [APB_SLAVES_NUM-1:0] s_m_apb_pready;

  wire [              31:0] s_m_apb_prdata0;
  wire [              31:0] s_m_apb_prdata1;
  wire [              31:0] s_m_apb_prdata2;
  wire [              31:0] s_m_apb_prdata3;
  wire [              31:0] s_m_apb_prdata4;
  wire [              31:0] s_m_apb_prdata5;
  wire [              31:0] s_m_apb_prdata6;
  wire [              31:0] s_m_apb_prdata7;
  wire [APB_SLAVES_NUM-1:0] s_m_apb_pslverr;

  apb4_archinfo u_apb4_archinfo (
      .pclk   (clk_i),
      .presetn(rst_n_i),
      .paddr  (s_m_apb_paddr),
      .pprot  (s_m_apb_pprot),
      .psel   (s_m_apb_psel[0]),
      .penable(s_m_apb_penable),
      .pwrite (s_m_apb_pwrite),
      .pwdata (s_m_apb_pwdata),
      .pstrb  (s_m_apb_pstrb),
      .pready (s_m_apb_pready[0]),
      .prdata (s_m_apb_prdata0),
      .pslverr(s_m_apb_pslverr[0])
  );

  apb4_rng u_apb4_rng (
      .pclk   (clk_i),
      .presetn(rst_n_i),
      .paddr  (s_m_apb_paddr),
      .pprot  (s_m_apb_pprot),
      .psel   (s_m_apb_psel[1]),
      .penable(s_m_apb_penable),
      .pwrite (s_m_apb_pwrite),
      .pwdata (s_m_apb_pwdata),
      .pstrb  (s_m_apb_pstrb),
      .pready (s_m_apb_pready[1]),
      .prdata (s_m_apb_prdata1),
      .pslverr(s_m_apb_pslverr[1])
  );

  apb4_uart u_apb4_uart (
      .pclk     (clk_i),
      .presetn  (rst_n_i),
      .paddr    (s_m_apb_paddr),
      .pprot    (s_m_apb_pprot),
      .psel     (s_m_apb_psel[2]),
      .penable  (s_m_apb_penable),
      .pwrite   (s_m_apb_pwrite),
      .pwdata   (s_m_apb_pwdata),
      .pstrb    (s_m_apb_pstrb),
      .pready   (s_m_apb_pready[2]),
      .prdata   (s_m_apb_prdata2),
      .pslverr  (s_m_apb_pslverr[2]),
      .uart_rx_i(uart_rx_i),
      .uart_tx_o(uart_tx_o),
      .irq_o    (uart_irq_o)
  );

  apb4_pwm u_apb4_pwm (
      .pclk   (clk_i),
      .presetn(rst_n_i),
      .paddr  (s_m_apb_paddr),
      .pprot  (s_m_apb_pprot),
      .psel   (s_m_apb_psel[3]),
      .penable(s_m_apb_penable),
      .pwrite (s_m_apb_pwrite),
      .pwdata (s_m_apb_pwdata),
      .pstrb  (s_m_apb_pstrb),
      .pready (s_m_apb_pready[3]),
      .prdata (s_m_apb_prdata3),
      .pslverr(s_m_apb_pslverr[3]),
      .pwm_o  (pwm_pwm_o),
      .irq_o  (pwm_irq_o)
  );

  apb4_ps2 u_apb4_ps2 (
      .pclk     (clk_i),
      .presetn  (rst_n_i),
      .paddr    (s_m_apb_paddr),
      .pprot    (s_m_apb_pprot),
      .psel     (s_m_apb_psel[4]),
      .penable  (s_m_apb_penable),
      .pwrite   (s_m_apb_pwrite),
      .pwdata   (s_m_apb_pwdata),
      .pstrb    (s_m_apb_pstrb),
      .pready   (s_m_apb_pready[4]),
      .prdata   (s_m_apb_prdata4),
      .pslverr  (s_m_apb_pslverr[4]),
      .ps2_clk_i(ps2_ps2_clk_i),
      .ps2_dat_i(ps2_ps2_dat_i),
      .irq_o    (ps2_irq_o)
  );


  apb4_i2c u_apb4_i2c (
      .pclk     (clk_i),
      .presetn  (rst_n_i),
      .paddr    (s_m_apb_paddr),
      .pprot    (s_m_apb_pprot),
      .psel     (s_m_apb_psel[5]),
      .penable  (s_m_apb_penable),
      .pwrite   (s_m_apb_pwrite),
      .pwdata   (s_m_apb_pwdata),
      .pstrb    (s_m_apb_pstrb),
      .pready   (s_m_apb_pready[5]),
      .prdata   (s_m_apb_prdata5),
      .pslverr  (s_m_apb_pslverr[5]),
      .scl_i    (i2c_scl_i),
      .scl_o    (i2c_scl_o),
      .scl_dir_o(i2c_scl_dir_o),
      .sda_i    (i2c_sda_i),
      .sda_o    (i2c_sda_o),
      .sda_dir_o(i2c_sda_dir_o),
      .irq_o    (i2c_irq_o)
  );

  apb_spi_master #(
      .BUFFER_DEPTH  (32),
      .APB_ADDR_WIDTH(32)
  ) u_apb_spi_master (
      .HCLK    (clk_i),
      .HRESETn (rst_n_i),
      .PADDR   (s_m_apb_paddr),
      .PWDATA  (s_m_apb_pwdata),
      .PWRITE  (s_m_apb_pwrite),
      .PSEL    (s_m_apb_psel[6]),
      .PENABLE (s_m_apb_penable),
      .PRDATA  (s_m_apb_prdata6),
      .PREADY  (s_m_apb_pready[6]),
      .PSLVERR (s_m_apb_pslverr[6]),
      .spi_clk (qspi_spi_clk_o),
      .spi_csn0(qspi_spi_csn_o[0]),
      .spi_csn1(qspi_spi_csn_o[1]),
      .spi_csn2(qspi_spi_csn_o[2]),
      .spi_csn3(qspi_spi_csn_o[3]),
      .spi_sdo0(qspi_spi_sdo_o[0]),
      .spi_sdo1(qspi_spi_sdo_o[1]),
      .spi_sdo2(qspi_spi_sdo_o[2]),
      .spi_sdo3(qspi_spi_sdo_o[3]),
      .spi_oe0 (qspi_spi_oe_o[0]),
      .spi_oe1 (qspi_spi_oe_o[1]),
      .spi_oe2 (qspi_spi_oe_o[2]),
      .spi_oe3 (qspi_spi_oe_o[3]),
      .spi_sdi0(qspi_spi_sdi_i[0]),
      .spi_sdi1(qspi_spi_sdi_i[1]),
      .spi_sdi2(qspi_spi_sdi_i[2]),
      .spi_sdi3(qspi_spi_sdi_i[3]),
      .events_o(qspi_irq_o)
  );

  spi_flash #(
      .flash_addr_start(32'h3000_0000),
      .flash_addr_end  (32'h3FFF_FFFF),
      .spi_cs_num      (1)
  ) u_spi_flash (
      .pclk       (clk_i),
      .presetn    (rst_n_i),
      .paddr      (s_m_apb_paddr),
      .psel       (s_m_apb_psel[7]),
      .penable    (s_m_apb_penable),
      .pwrite     (s_m_apb_pwrite),
      .pwdata     (s_m_apb_pwdata),
      .pwstrb     (4'hF),
      .pready     (s_m_apb_pready[7]),
      .prdata     (s_m_apb_prdata7),
      .pslverr    (s_m_apb_pslverr[7]),
      .div4_i     (spfs_div4_i),
      .spi_clk    (spfs_clk_o),
      .spi_cs     (spfs_cs_o),
      .spi_mosi   (spfs_mosi_o),
      .spi_miso   (spfs_miso_i),
      .spi_irq_out(spfs_irq_o)
  );

  mem2apb #(
      .APB_SLAVES_NUM(APB_SLAVES_NUM)
  ) u_mem2apb (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .mem_valid_i  (mem_valid_i),
      .mem_instr_i  (mem_instr_i),
      .mem_ready_o  (mem_ready_o),
      .mem_addr_i   (mem_addr_i),
      .mem_wdata_i  (mem_wdata_i),
      .mem_wstrb_i  (mem_wstrb_i),
      .mem_rdata_o  (mem_rdata_o),
      .apb_paddr_o  (s_m_apb_paddr),
      .apb_pprot_o  (s_m_apb_pprot),
      .apb_psel_o   (s_m_apb_psel),
      .apb_penable_o(s_m_apb_penable),
      .apb_pwrite_o (s_m_apb_pwrite),
      .apb_pwdata_o (s_m_apb_pwdata),
      .apb_pstrb_o  (s_m_apb_pstrb),
      .apb_pready_i (s_m_apb_pready),
      .apb_prdata0_i(s_m_apb_prdata0),
      .apb_prdata1_i(s_m_apb_prdata1),
      .apb_prdata2_i(s_m_apb_prdata2),
      .apb_prdata3_i(s_m_apb_prdata3),
      .apb_prdata4_i(s_m_apb_prdata4),
      .apb_prdata5_i(s_m_apb_prdata5),
      .apb_prdata6_i(s_m_apb_prdata6),
      .apb_prdata7_i(s_m_apb_prdata7),
      .apb_pslverr_i(s_m_apb_pslverr)
  );

endmodule
