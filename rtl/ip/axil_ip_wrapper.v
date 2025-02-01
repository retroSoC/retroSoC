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
    output [31:0] mem_axi_rdata
    // pwm
    // input         ls_clk_i,
    // input         pwm_pin_in_i,
    // output        pwm_irq3_o,
    // output        pwm_irq2_o,
    // output        pwm_irq1_o,
    // output        pwm_irq0_o,
    // output [ 3:0] pwm_tim0_o,
    // output [ 3:0] pwm_tim1_o,
    // output [ 3:0] pwm_tim2_o,
    // output [ 3:0] pwm_tim3_o
);

  localparam APB_SLAVES_NUM = 2;
  localparam [32*APB_SLAVES_NUM-1 : 0] MEM_REGIONS1 = 64'h0300_2000__0300_1000;
  localparam [32*APB_SLAVES_NUM-1 : 0] MEM_REGIONS2 = 64'h0300_2008__0300_1008;

  wire [              31:0] s_m_apb_paddr;
  wire [               2:0] s_m_apb_pprot;
  wire [APB_SLAVES_NUM-1:0] s_m_apb_psel;
  wire                      s_m_apb_penable;
  wire                      s_m_apb_pwrite;
  wire [              31:0] s_m_apb_pwdata;
  wire [               3:0] s_m_apb_pstrb;
  wire [APB_SLAVES_NUM-1:0] s_m_apb_pready;

  wire [              31:0] s_m_apb_prdata;
  wire [              31:0] s_m_apb_prdata2;
  wire [              31:0] s_m_apb_prdata3;
  wire [APB_SLAVES_NUM-1:0] s_m_apb_pslverr;
  // ARCHINFO
  // RNG
  // UART
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
      .prdata (s_m_apb_prdata),
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

//   apb_adv_timer #(
//       .APB_ADDR_WIDTH(32)
//   ) u_apb_adv_timer (
//       .HCLK           (clk_i),
//       .HRESETn        (rst_n_i),
//       .PADDR          (s_m_apb_paddr),
//       .PWDATA         (s_m_apb_pwdata),
//       .PWRITE         (s_m_apb_pwrite),
//       .PSEL           (s_m_apb_psel[2]),
//       .PENABLE        (s_m_apb_penable),
//       .PRDATA         (s_m_apb_prdata3),
//       .PREADY         (s_m_apb_pready[2]),
//       .PSLVERR        (s_m_apb_pslverr[2]),
//       .dft_cg_enable_i(1'b0),
//       .low_speed_clk_i(ls_clk_i),
//       .ext_sig_i      (pwm_pin_in_i),
//       .events_o       ({pwm_irq3_o, pwm_irq2_o, pwm_irq1_o, pwm_irq0_o}),
//       .ch_0_o         (pwm_tim0_o),
//       .ch_1_o         (pwm_tim1_o),
//       .ch_2_o         (pwm_tim2_o),
//       .ch_3_o         (pwm_tim3_o)
//   );

  axi_apb_bridge #(
      .c_apb_num_slaves(APB_SLAVES_NUM),
      .memory_regions1 (MEM_REGIONS1),
      .memory_regions2 (MEM_REGIONS2),
      .timeout_val     (1),
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
      .m_apb_prdata  (s_m_apb_prdata),
      .m_apb_prdata2 (s_m_apb_prdata2),
      .m_apb_prdata3 (32'h0),
      .m_apb_prdata4 (32'h0),
      .m_apb_prdata5 (32'h0),
      .m_apb_prdata6 (32'h0),
      .m_apb_prdata7 (32'h0),
      .m_apb_prdata8 (32'h0),
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
