module axil_ip_wrapper (
    input         clk_i,
    input         rst_n_i,
    input         mem_axi_awvalid,
    output        mem_axi_awready,
    input  [31:0] mem_axi_awaddr,
    input  [ 2:0] mem_axi_awprot,
    input         mem_axi_wvalid,
    output        mem_axi_wready,
    input  [31:0] mem_axi_wdata,
    input  [ 3:0] mem_axi_wstrb,
    output        mem_axi_bvalid,
    input         mem_axi_bready,
    input         mem_axi_arvalid,
    output        mem_axi_arready,
    input  [31:0] mem_axi_araddr,
    input  [ 2:0] mem_axi_arprot,
    output        mem_axi_rvalid,
    input         mem_axi_rready,
    output [31:0] mem_axi_rdata,
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
  localparam [32*APB_SLAVES_NUM-1 : 0] MEM_REGIONS1 = {
    32'h3000_0000, 224'h0300_7000__0300_6000__0300_5000__0300_4000__0300_3000__0300_2000__0300_1000
  };
  localparam [32*APB_SLAVES_NUM-1 : 0] MEM_REGIONS2 = {
    32'h3FFF_FFFF, 224'h0300_7FFF__0300_6FFF__0300_5FFF__0300_4FFF__0300_3FFF__0300_2FFF__0300_1FFF
  };

  wire [              31:0] s_m_apb_paddr;
  wire [               2:0] s_m_apb_pprot;
  wire [APB_SLAVES_NUM-1:0] s_m_apb_psel;
  wire                      s_m_apb_penable;
  wire                      s_m_apb_pwrite;
  wire [              31:0] s_m_apb_pwdata;
  wire [               3:0] s_m_apb_pstrb;
  wire [APB_SLAVES_NUM-1:0] s_m_apb_pready;

  wire [              31:0] s_m_apb_prdata1;
  wire [              31:0] s_m_apb_prdata2;
  wire [              31:0] s_m_apb_prdata3;
  wire [              31:0] s_m_apb_prdata4;
  wire [              31:0] s_m_apb_prdata5;
  wire [              31:0] s_m_apb_prdata6;
  wire [              31:0] s_m_apb_prdata7;
  wire [              31:0] s_m_apb_prdata8;
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
      .prdata (s_m_apb_prdata1),
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
      .prdata (s_m_apb_prdata2),
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
      .prdata   (s_m_apb_prdata3),
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
      .prdata (s_m_apb_prdata4),
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
      .prdata   (s_m_apb_prdata5),
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
      .prdata   (s_m_apb_prdata6),
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
      .PRDATA  (s_m_apb_prdata7),
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
      .prdata     (s_m_apb_prdata8),
      .pslverr    (s_m_apb_pslverr[7]),
      .div4_i     (spfs_div4_i),
      .spi_clk    (spfs_clk_o),
      .spi_cs     (spfs_cs_o),
      .spi_mosi   (spfs_mosi_o),
      .spi_miso   (spfs_miso_i),
      .spi_irq_out(spfs_irq_o)
  );

  axi_apb_bridge #(
      .c_apb_num_slaves(APB_SLAVES_NUM),
      .memory_regions1 (MEM_REGIONS1),
      .memory_regions2 (MEM_REGIONS2),
      .timeout_val     (32'hFFFF_FFFF),
      .APB_Protocol    (4)
  ) u_axi_apb_bridge (
      .s_axi_clk    (clk_i),
      .s_axi_aresetn(rst_n_i),
      .s_axi_awaddr (mem_axi_awaddr),
      .s_axi_awvalid(mem_axi_awvalid),
      .s_axi_awready(mem_axi_awready),
      .s_axi_wdata  (mem_axi_wdata),
      .s_axi_wvalid (mem_axi_wvalid),
      .s_axi_wstrb  (mem_axi_wstrb),
      .s_axi_wready (mem_axi_wready),
      .s_axi_bresp  (),
      .s_axi_bvalid (mem_axi_bvalid),
      .s_axi_bready (mem_axi_bready),
      .s_axi_araddr (mem_axi_araddr),
      .s_axi_arvalid(mem_axi_arvalid),
      .s_axi_arready(mem_axi_arready),
      .s_axi_rresp  (),
      .s_axi_rvalid (mem_axi_rvalid),
      .s_axi_rdata  (mem_axi_rdata),
      .s_axi_rready (mem_axi_rready),
      .s_axi_arprot (mem_axi_arprot),
      .s_axi_awprot (mem_axi_awprot),

      .m_apb_paddr   (s_m_apb_paddr),
      .m_apb_pprot   (s_m_apb_pprot),
      .m_apb_psel    (s_m_apb_psel),
      .m_apb_penable (s_m_apb_penable),
      .m_apb_pwrite  (s_m_apb_pwrite),
      .m_apb_pwdata  (s_m_apb_pwdata),
      .m_apb_pstrb   (s_m_apb_pstrb),
      .m_apb_pready  (s_m_apb_pready),
      // diff apb slave rdata
      .m_apb_prdata  (s_m_apb_prdata1),
      .m_apb_prdata2 (s_m_apb_prdata2),
      .m_apb_prdata3 (s_m_apb_prdata3),
      .m_apb_prdata4 (s_m_apb_prdata4),
      .m_apb_prdata5 (s_m_apb_prdata5),
      .m_apb_prdata6 (s_m_apb_prdata6),
      .m_apb_prdata7 (s_m_apb_prdata7),
      .m_apb_prdata8 (s_m_apb_prdata8),
      .m_apb_prdata9 (32'h0),
      .m_apb_prdata10(32'h0),
      .m_apb_prdata11(32'h0),
      .m_apb_prdata12(32'h0),
      .m_apb_prdata13(32'h0),
      .m_apb_prdata14(32'h0),
      .m_apb_prdata15(32'h0),
      .m_apb_prdata16(32'h0),
      .m_apb_pslverr (s_m_apb_pslverr)
  );

endmodule
