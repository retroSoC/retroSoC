`include "dvp_define.svh"

module ppalite_route_formal (
    input wire clk_i
);
  reg rst_n = 1'b0;
  always @(posedge clk_i) rst_n <= 1'b1;

  (* anyseq *)reg                                    route_write;
  (* anyseq *)reg                                    route_value;
  (* anyseq *)reg [                             2:0] processing_format;
  (* anyseq *)reg [                             2:0] capture_state;
  (* anyseq *)reg                                    capture_arm;
  (* anyseq *)reg                                    capture_close;
  (* anyseq *)reg                                    processor_idle;
  (* anyseq *)reg                                    dma_idle;
  (* anyseq *)reg                                    dma_start;
  (* anyseq *)reg                                    transport_idle;
  (* anyseq *)reg                                    transport_admitted;
  (* anyseq *)reg                                    stream_isolated;
  (* anyseq *)reg [                           127:0] source_config;
  (* anyseq *)reg                                    source_config_pending;
  (* anyseq *)reg                                    source_command_pending;
  (* anyseq *)reg                                    source_flush_pending;
  (* anyseq *)reg                                    source_status_valid;
  (* anyseq *)reg                                    source_capture_idle;
  (* anyseq *)reg                                    source_active;
  (* anyseq *)reg                                    source_enabled;
  (* anyseq *)reg                                    source_requested_enabled;
  (* anyseq *)reg                                    source_fifo_empty;
  (* anyseq *)reg                                    source_lifecycle_idle;
  (* anyseq *)reg [`APB4_DVP__FRAME_STATS_WIDTH-1:0] source_frame_stats;
  (* anyseq *)reg                                    source_frame_stats_valid;
  (* anyseq *)reg [                             5:0] source_error;
  (* anyseq *)reg [                            31:0] dvp_paddr;
  (* anyseq *)reg [                             2:0] dvp_pprot;
  (* anyseq *)reg                                    dvp_psel;
  (* anyseq *)reg                                    dvp_penable;
  (* anyseq *)reg                                    dvp_pwrite;
  (* anyseq *)reg [                            31:0] dvp_pwdata;
  (* anyseq *)reg [                             3:0] dvp_pstrb;
  (* anyseq *)reg                                    source_pready;
  (* anyseq *)reg [                            31:0] source_prdata;
  (* anyseq *)reg                                    source_pslverr;
  (* anyseq *)reg                                    dvp_valid;
  (* anyseq *)reg [                            31:0] dvp_data;
  (* anyseq *)reg [                             3:0] dvp_keep;
  (* anyseq *)reg [                             3:0] dvp_strb;
  (* anyseq *)reg                                    dvp_id;
  (* anyseq *)reg                                    dvp_dest;
  (* anyseq *)reg                                    dvp_user;
  (* anyseq *)reg                                    dvp_last;
  (* anyseq *)reg                                    process_ready;
  (* anyseq *)reg                                    processed_valid;
  (* anyseq *)reg [                            31:0] processed_data;
  (* anyseq *)reg [                             3:0] processed_keep;
  (* anyseq *)reg [                             3:0] processed_strb;
  (* anyseq *)reg                                    processed_id;
  (* anyseq *)reg                                    processed_dest;
  (* anyseq *)reg                                    processed_user;
  (* anyseq *)reg                                    processed_last;
  (* anyseq *)reg                                    dma_ready;

  apb4_if dvp_apb (
      .pclk   (clk_i),
      .presetn(rst_n)
  );
  apb4_if source_apb (
      .pclk   (clk_i),
      .presetn(rst_n)
  );
  assign dvp_apb.paddr      = dvp_paddr;
  assign dvp_apb.pprot      = dvp_pprot;
  assign dvp_apb.psel       = dvp_psel;
  assign dvp_apb.penable    = dvp_penable;
  assign dvp_apb.pwrite     = dvp_pwrite;
  assign dvp_apb.pwdata     = dvp_pwdata;
  assign dvp_apb.pstrb      = dvp_pstrb;
  assign source_apb.pready  = source_pready;
  assign source_apb.prdata  = source_prdata;
  assign source_apb.pslverr = source_pslverr;

  /* verilator lint_off PINCONNECTEMPTY */
  ppalite_route_ctrl u_dut (
      .clk_i                     (clk_i),
      .rst_n_i                   (rst_n),
      .dvp_apb4                  (dvp_apb),
      .source_apb4               (source_apb),
      .route_write_i             (route_write),
      .route_value_i             (route_value),
      .processing_format_i       (processing_format),
      .capture_state_i           (capture_state),
      .capture_arm_i             (capture_arm),
      .capture_close_i           (capture_close),
      .processor_idle_i          (processor_idle),
      .route_o                   (),
      .route_idle_o              (),
      .route_change_o            (),
      .dma_idle_i                (dma_idle),
      .dma_start_i               (dma_start),
      .transport_idle_i          (transport_idle),
      .transport_admitted_i      (transport_admitted),
      .stream_isolated_i         (stream_isolated),
      .source_config_i           (source_config),
      .source_config_pending_i   (source_config_pending),
      .source_command_pending_i  (source_command_pending),
      .source_flush_pending_i    (source_flush_pending),
      .source_status_valid_i     (source_status_valid),
      .source_capture_idle_i     (source_capture_idle),
      .source_active_i           (source_active),
      .source_enabled_i          (source_enabled),
      .source_requested_enabled_i(source_requested_enabled),
      .source_fifo_empty_i       (source_fifo_empty),
      .source_lifecycle_idle_i   (source_lifecycle_idle),
      .source_frame_stats_i      (source_frame_stats),
      .source_frame_stats_valid_i(source_frame_stats_valid),
      .source_error_i            (source_error),
      .source_ready_o            (),
      .source_quiet_o            (),
      .source_done_o             (),
      .source_stopped_o          (),
      .source_sequence_o         (),
      .source_words_o            (),
      .source_geometry_o         (),
      .source_err_o              (),
      .source_config_err_o       (),
      .source_stats_err_o        (),
      .dvp_valid_i               (dvp_valid),
      .dvp_ready_o               (),
      .dvp_data_i                (dvp_data),
      .dvp_keep_i                (dvp_keep),
      .dvp_strb_i                (dvp_strb),
      .dvp_id_i                  (dvp_id),
      .dvp_dest_i                (dvp_dest),
      .dvp_user_i                (dvp_user),
      .dvp_last_i                (dvp_last),
      .process_valid_o           (),
      .process_ready_i           (process_ready),
      .process_data_o            (),
      .process_keep_o            (),
      .process_strb_o            (),
      .process_id_o              (),
      .process_dest_o            (),
      .process_user_o            (),
      .process_last_o            (),
      .processed_valid_i         (processed_valid),
      .processed_ready_o         (),
      .processed_data_i          (processed_data),
      .processed_keep_i          (processed_keep),
      .processed_strb_i          (processed_strb),
      .processed_id_i            (processed_id),
      .processed_dest_i          (processed_dest),
      .processed_user_i          (processed_user),
      .processed_last_i          (processed_last),
      .dma_valid_o               (),
      .dma_ready_i               (dma_ready),
      .dma_data_o                (),
      .dma_keep_o                (),
      .dma_strb_o                (),
      .dma_id_o                  (),
      .dma_dest_o                (),
      .dma_user_o                (),
      .dma_last_o                ()
  );
  /* verilator lint_on PINCONNECTEMPTY */
endmodule
