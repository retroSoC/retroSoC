// Standalone SPI shell. DMA pacing is local; product route and fabric origin remain external.
module apb4_spi #(
    parameter bit EnableDma = 1'b1
) (
    input  logic                clk_i,
    rst_n_i,
    input  logic         [31:0] clock_hz_i,
    input  logic         [ 1:0] origin_i,
    input  logic         [ 4:0] request_i,
    input  logic         [ 2:0] channel_i,
    input  logic         [ 1:0] credit_valid_i,
    credit_retire_i,
    input  logic         [ 3:0] dma_status_i,
    input  logic         [ 1:0] dma_start_pending_i,
    input  logic                dma_error_i,
    input  logic         [31:0] user_select_i,
    handoff_i,
    alt_enable_i,
    alt_select_i,
    input  logic         [31:0] output_enable_i,
    open_drain_i,
    input  logic                gpio_ready_i,
    miso_i,
    output logic                sck_o,
    mosi_o,
    cs_n_o,
    output_enable_o,
    irq_o,
    session_owned_o,
    lifecycle_idle_o,
    output logic         [ 1:0] credit_commit_o,
    output logic         [ 1:0] dma_admit_ready_o,
           apb4_if.slave        apb4
);
  spi_ctrl_if u_ctrl ();
  spi_pkg::configuration_t s_cfg;
  spi_pkg::status_t        s_stat;
  logic [31:0] s_claim, s_ready;
  logic s_handback, s_credit_fault, s_reg_credit_fault, s_pacing_fault;
  logic s_fifo_pending;
  logic [1:0] s_credit_pending, s_pacing_pending, s_reg_credit_pending;
  logic [1:0] s_credit_valid, s_credit_retire, s_credit_commit;
  logic [3:0] s_dma_stat;
  logic       s_unused;
  assign s_cfg            = u_ctrl.cfg;
  assign s_stat           = u_ctrl.stat;
  // Only personality bits feed the GPIO guard; other fields feed the core/reg blocks.
  assign s_unused         = ^s_cfg;
  assign s_credit_fault   = s_reg_credit_fault | s_pacing_fault;
  assign s_credit_pending = s_pacing_pending | s_reg_credit_pending;
  spi_dma_pacing u_dma_pacing (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .enable_i           (EnableDma),
      .tx_binding_i       (s_cfg.tx_binding),
      .rx_binding_i       (s_cfg.rx_binding),
      .dma_start_pending_i(dma_start_pending_i),
      .dma_status_i       (dma_status_i),
      .dma_error_i        (dma_error_i),
      .credit_valid_i     (credit_valid_i),
      .credit_retire_i    (credit_retire_i),
      .credit_commit_i    (s_credit_commit),
      .credit_valid_o     (s_credit_valid),
      .credit_retire_o    (s_credit_retire),
      .credit_pending_o   (s_pacing_pending),
      .dma_status_o       (s_dma_stat),
      .credit_fault_o     (s_pacing_fault),
      .busy_o             ()
  );
  spi_gpio_guard u_gpio_guard (
      .session_i      (s_cfg.session),
      .user_select_i  (user_select_i),
      .handoff_i      (handoff_i),
      .alt_enable_i   (alt_enable_i),
      .alt_select_i   (alt_select_i),
      .output_enable_i(output_enable_i),
      .open_drain_i   (open_drain_i),
      .gpio_ready_i   (gpio_ready_i),
      .claim_o        (s_claim),
      .ready_o        (s_ready),
      .handback_o     (s_handback)
  );
  spi_reg u_reg (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .clock_hz_i         (clock_hz_i),
      .origin_i           (origin_i),
      .request_i          (request_i),
      .channel_i          (channel_i),
      .credit_valid_i     (s_credit_valid),
      .credit_retire_i    (s_credit_retire),
      .dma_status_i       (s_dma_stat),
      .dma_start_pending_i(dma_start_pending_i),
      .credit_commit_o    (s_credit_commit),
      .credit_pending_o   (s_reg_credit_pending),
      .fifo_pending_o     (s_fifo_pending),
      .credit_fault_o     (s_reg_credit_fault),
      .irq_o              (irq_o),
      .apb4               (apb4),
      .ctrl               (u_ctrl)
  );
  assign credit_commit_o = s_credit_commit;
  assign session_owned_o = s_stat.status[5];
  assign lifecycle_idle_o = s_stat.status[10] && s_stat.status[11] && !s_stat.status[5];
  assign dma_admit_ready_o[0] = EnableDma && s_cfg.tx_binding[31] && u_ctrl.tx_ready &&
      !s_credit_pending[0];
  assign dma_admit_ready_o[1] = EnableDma && s_cfg.rx_binding[31] && u_ctrl.rx_ready &&
      !s_credit_pending[1];
  spi_master_core u_master_core (
      .apb_pending_i      (s_fifo_pending),
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .claim_i            (s_claim),
      .ready_pins_i       (s_ready),
      .gpio_ready_i       (gpio_ready_i),
      .handback_i         (s_handback),
      .dma_status_i       (s_dma_stat),
      .dma_start_pending_i(dma_start_pending_i),
      .dma_error_i        (dma_error_i),
      .credit_fault_i     (s_credit_fault),
      .miso_i             (miso_i),
      .sck_o              (sck_o),
      .mosi_o             (mosi_o),
      .cs_n_o             (cs_n_o),
      .output_enable_o    (output_enable_o),
      .ctrl               (u_ctrl)
  );
endmodule
