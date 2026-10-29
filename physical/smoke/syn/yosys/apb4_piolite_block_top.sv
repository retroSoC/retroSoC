module apb4_piolite_block_top (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic [31:0] clock_hz_i,
    input  logic [31:0] user_select_i,
    input  logic [31:0] user_status_i,
    input  logic [31:0] filter_enable_i,
    input  logic        gpio_ready_i,
    input  logic [31:0] gpio_input_i,
    output logic [31:0] gpio_value_o,
    output logic [31:0] gpio_oe_o,
    input  logic        dma_tx_job_i,
    input  logic        dma_rx_job_i,
    input  logic        dma_tx_valid_i,
    output logic        dma_tx_ready_o,
    input  logic [31:0] dma_tx_data_i,
    input  logic [ 3:0] dma_tx_keep_i,
    input  logic [ 3:0] dma_tx_strb_i,
    input  logic        dma_tx_id_i,
    input  logic        dma_tx_dest_i,
    input  logic        dma_tx_user_i,
    input  logic        dma_tx_last_i,
    output logic        dma_rx_valid_o,
    input  logic        dma_rx_ready_i,
    output logic [31:0] dma_rx_data_o,
    output logic [ 3:0] dma_rx_keep_o,
    output logic [ 3:0] dma_rx_strb_o,
    output logic        dma_rx_last_o,
    output logic        dma_rx_id_o,
    output logic        dma_rx_dest_o,
    output logic        dma_rx_user_o,
    output logic        dma_tx_admit_o,
    output logic        dma_rx_admit_o,
    output logic        irq_o,
    input  logic [31:0] paddr_i,
    input  logic [ 2:0] pprot_i,
    input  logic        psel_i,
    input  logic        penable_i,
    input  logic        pwrite_i,
    input  logic [31:0] pwdata_i,
    input  logic [ 3:0] pstrb_i,
    output logic        pready_o,
    output logic [31:0] prdata_o,
`ifdef PIOLITE_FORMAL_TOP
    output logic [43:0] formal_sm0_o,
`endif
    output logic        pslverr_o
);
  apb4_if u_apb (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  assign u_apb.paddr   = paddr_i;
  assign u_apb.pprot   = pprot_i;
  assign u_apb.psel    = psel_i;
  assign u_apb.penable = penable_i;
  assign u_apb.pwrite  = pwrite_i;
  assign u_apb.pwdata  = pwdata_i;
  assign u_apb.pstrb   = pstrb_i;
  assign pready_o      = u_apb.pready;
  assign prdata_o      = u_apb.prdata;
  assign pslverr_o     = u_apb.pslverr;

  apb4_piolite u_dut (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .clock_hz_i     (clock_hz_i),
      .user_select_i  (user_select_i),
      .user_status_i  (user_status_i),
      .filter_enable_i(filter_enable_i),
      .gpio_ready_i   (gpio_ready_i),
      .gpio_input_i   (gpio_input_i),
      .gpio_value_o   (gpio_value_o),
      .gpio_oe_o      (gpio_oe_o),
      .dma_tx_job_i   (dma_tx_job_i),
      .dma_rx_job_i   (dma_rx_job_i),
      .dma_tx_valid_i (dma_tx_valid_i),
      .dma_tx_ready_o (dma_tx_ready_o),
      .dma_tx_data_i  (dma_tx_data_i),
      .dma_tx_keep_i  (dma_tx_keep_i),
      .dma_tx_strb_i  (dma_tx_strb_i),
      .dma_tx_id_i    (dma_tx_id_i),
      .dma_tx_dest_i  (dma_tx_dest_i),
      .dma_tx_user_i  (dma_tx_user_i),
      .dma_tx_last_i  (dma_tx_last_i),
      .dma_rx_valid_o (dma_rx_valid_o),
      .dma_rx_ready_i (dma_rx_ready_i),
      .dma_rx_data_o  (dma_rx_data_o),
      .dma_rx_keep_o  (dma_rx_keep_o),
      .dma_rx_strb_o  (dma_rx_strb_o),
      .dma_rx_last_o  (dma_rx_last_o),
      .dma_rx_id_o    (dma_rx_id_o),
      .dma_rx_dest_o  (dma_rx_dest_o),
      .dma_rx_user_o  (dma_rx_user_o),
      .dma_tx_admit_o (dma_tx_admit_o),
      .dma_rx_admit_o (dma_rx_admit_o),
      .irq_o          (irq_o),
`ifdef PIOLITE_FORMAL_TOP
      .formal_sm0_o   (formal_sm0_o),
`endif
      .apb4           (u_apb)
  );
endmodule
