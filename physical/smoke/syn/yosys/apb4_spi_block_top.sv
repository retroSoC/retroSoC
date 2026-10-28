// Flat-pin standalone verification/synthesis boundary; not a Tiny instance.
module apb4_spi_block_top (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic [31:0] clock_hz_i,
    input  logic [ 1:0] origin_i,
    input  logic [ 4:0] request_i,
    input  logic [ 2:0] channel_i,
    input  logic [ 1:0] credit_valid_i,
    input  logic [ 1:0] credit_retire_i,
    input  logic [ 1:0] dma_start_pending_i,
    input  logic [ 3:0] dma_status_i,
    input  logic        dma_error_i,
    input  logic [31:0] user_select_i,
    input  logic [31:0] handoff_i,
    input  logic [31:0] alt_enable_i,
    input  logic [31:0] alt_select_i,
    input  logic [31:0] output_enable_i,
    input  logic [31:0] open_drain_i,
    input  logic        gpio_ready_i,
    input  logic        miso_i,
    output logic        sck_o,
    output logic        mosi_o,
    output logic        cs_n_o,
    output logic        output_enable_o,
    output logic        irq_o,
    output logic [ 1:0] credit_commit_o,
    output logic [ 1:0] dma_admit_ready_o,
    output logic        session_owned_o,
    output logic        lifecycle_idle_o,
    input  logic [31:0] paddr_i,
    pwdata_i,
    input  logic [ 3:0] pstrb_i,
    input  logic        psel_i,
    penable_i,
    pwrite_i,
    output logic [31:0] prdata_o,
    output logic        pready_o,
    pslverr_o
);
  apb4_if s_apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  assign s_apb4.paddr   = paddr_i;
  assign s_apb4.pwdata  = pwdata_i;
  assign s_apb4.pstrb   = pstrb_i;
  assign s_apb4.psel    = psel_i;
  assign s_apb4.penable = penable_i;
  assign s_apb4.pwrite  = pwrite_i;
  assign s_apb4.pprot   = 3'd0;
  assign prdata_o       = s_apb4.prdata;
  assign pready_o       = s_apb4.pready;
  assign pslverr_o      = s_apb4.pslverr;
  apb4_spi u_spi (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .clock_hz_i         (clock_hz_i),
      .origin_i           (origin_i),
      .request_i          (request_i),
      .channel_i          (channel_i),
      .credit_valid_i     (credit_valid_i),
      .credit_retire_i    (credit_retire_i),
      .dma_start_pending_i(dma_start_pending_i),
      .dma_status_i       (dma_status_i),
      .dma_error_i        (dma_error_i),
      .user_select_i      (user_select_i),
      .handoff_i          (handoff_i),
      .alt_enable_i       (alt_enable_i),
      .alt_select_i       (alt_select_i),
      .output_enable_i    (output_enable_i),
      .open_drain_i       (open_drain_i),
      .gpio_ready_i       (gpio_ready_i),
      .miso_i             (miso_i),
      .sck_o              (sck_o),
      .mosi_o             (mosi_o),
      .cs_n_o             (cs_n_o),
      .output_enable_o    (output_enable_o),
      .irq_o              (irq_o),
      .credit_commit_o    (credit_commit_o),
      .dma_admit_ready_o  (dma_admit_ready_o),
      .session_owned_o    (session_owned_o),
      .lifecycle_idle_o   (lifecycle_idle_o),
      .apb4               (s_apb4)
  );
endmodule
