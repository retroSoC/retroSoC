`include "dvp_define.svh"

module apb4_ppalite_route_top (
    input  logic                                    clk_i,
    input  logic                                    pixel_clk_i,
    input  logic                                    rst_n_i,
    input  logic                                    source_rst_n_i,
    input  logic                                    href_i,
    input  logic                                    vsync_i,
    input  logic [                             7:0] dat_i,
    input  logic [                            31:0] dvp_paddr_i,
    input  logic [                             2:0] dvp_pprot_i,
    input  logic                                    dvp_psel_i,
    input  logic                                    dvp_penable_i,
    input  logic                                    dvp_pwrite_i,
    input  logic [                            31:0] dvp_pwdata_i,
    input  logic [                             3:0] dvp_pstrb_i,
    output logic                                    dvp_pready_o,
    output logic [                            31:0] dvp_prdata_o,
    output logic                                    dvp_pslverr_o,
    input  logic [                            31:0] ppa_paddr_i,
    input  logic [                             2:0] ppa_pprot_i,
    input  logic                                    ppa_psel_i,
    input  logic                                    ppa_penable_i,
    input  logic                                    ppa_pwrite_i,
    input  logic [                            31:0] ppa_pwdata_i,
    input  logic [                             3:0] ppa_pstrb_i,
    output logic                                    ppa_pready_o,
    output logic [                            31:0] ppa_prdata_o,
    output logic                                    ppa_pslverr_o,
    input  logic                                    dma_idle_i,
    input  logic                                    dma_start_i,
    input  logic                                    transport_ready_i,
    input  logic                                    transport_idle_i,
    input  logic                                    transport_admitted_i,
    input  logic                                    transport_done_i,
    input  logic [                             7:0] transport_err_i,
    input  logic                                    stream_isolated_i,
    output logic                                    out_valid_o,
    input  logic                                    out_ready_i,
    output logic [                            31:0] out_data_o,
    output logic [                             3:0] out_keep_o,
    output logic [                             3:0] out_strb_o,
    output logic                                    out_last_o,
    output logic                                    out_id_o,
    output logic                                    out_dest_o,
    output logic                                    out_user_o,
    output logic                                    dvp_irq_o,
    output logic                                    ppa_irq_o,
    output logic [                           127:0] source_config_o,
    output logic                                    source_status_valid_o,
    output logic                                    source_lifecycle_idle_o,
    output logic                                    source_reset_ready_o,
    output logic [`APB4_DVP__FRAME_STATS_WIDTH-1:0] source_frame_stats_o,
    output logic                                    source_frame_stats_valid_o,
    output logic [                             5:0] source_error_o
);
  apb4_if u_dvp_host_apb (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  apb4_if u_dvp_source_apb (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  apb4_if u_ppa_apb (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .DEST_WIDTH(1),
      .USER_WIDTH(1)
  ) u_dvp_rx (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  dvp_if u_camera ();

  assign u_camera.pclk_i        = pixel_clk_i;
  assign u_camera.href_i        = href_i;
  assign u_camera.vsync_i       = vsync_i;
  assign u_camera.dat_i         = dat_i;

  assign u_dvp_host_apb.paddr   = dvp_paddr_i;
  assign u_dvp_host_apb.pprot   = dvp_pprot_i;
  assign u_dvp_host_apb.psel    = dvp_psel_i;
  assign u_dvp_host_apb.penable = dvp_penable_i;
  assign u_dvp_host_apb.pwrite  = dvp_pwrite_i;
  assign u_dvp_host_apb.pwdata  = dvp_pwdata_i;
  assign u_dvp_host_apb.pstrb   = dvp_pstrb_i;
  assign dvp_pready_o           = u_dvp_host_apb.pready;
  assign dvp_prdata_o           = u_dvp_host_apb.prdata;
  assign dvp_pslverr_o          = u_dvp_host_apb.pslverr;

  assign u_ppa_apb.paddr        = ppa_paddr_i;
  assign u_ppa_apb.pprot        = ppa_pprot_i;
  assign u_ppa_apb.psel         = ppa_psel_i;
  assign u_ppa_apb.penable      = ppa_penable_i;
  assign u_ppa_apb.pwrite       = ppa_pwrite_i;
  assign u_ppa_apb.pwdata       = ppa_pwdata_i;
  assign u_ppa_apb.pstrb        = ppa_pstrb_i;
  assign ppa_pready_o           = u_ppa_apb.pready;
  assign ppa_prdata_o           = u_ppa_apb.prdata;
  assign ppa_pslverr_o          = u_ppa_apb.pslverr;

  logic        s_route;
  logic        s_route_idle;
  logic        s_route_change;
  logic        s_route_write;
  logic        s_route_value;
  logic [ 2:0] s_processing_format;
  logic [ 2:0] s_capture_state;
  logic        s_capture_arm;
  logic        s_capture_close;
  logic        s_processor_idle;
  logic        s_source_ready;
  logic        s_source_quiet;
  logic        s_source_done;
  logic        s_source_stopped;
  logic [31:0] s_source_sequence;
  logic [31:0] s_source_words;
  logic [31:0] s_source_geometry;
  logic [ 7:0] s_source_err;
  logic        s_source_config_err;
  logic        s_source_stats_err;
  logic        s_source_config_pending;
  logic        s_source_command_pending;
  logic        s_source_flush_pending;
  logic        s_source_capture_idle;
  logic        s_source_active;
  logic        s_source_enabled;
  logic        s_source_requested_enabled;
  logic        s_source_fifo_empty;
  logic        s_dvp_valid;
  logic        s_dvp_ready;
  logic        s_process_valid;
  logic        s_process_ready;
  logic [31:0] s_process_data;
  logic [ 3:0] s_process_keep;
  logic [ 3:0] s_process_strb;
  logic        s_process_id;
  logic        s_process_dest;
  logic        s_process_user;
  logic        s_process_last;
  logic        s_processed_valid;
  logic        s_processed_ready;
  logic [31:0] s_processed_data;
  logic [ 3:0] s_processed_keep;
  logic [ 3:0] s_processed_strb;
  logic        s_processed_id;
  logic        s_processed_dest;
  logic        s_processed_user;
  logic        s_processed_last;

  assign s_dvp_valid     = u_dvp_rx.tvalid;
  assign u_dvp_rx.tready = s_dvp_ready;

  ppalite_route_ctrl u_route (
      .clk_i                     (clk_i),
      .rst_n_i                   (rst_n_i),
      .dvp_apb4                  (u_dvp_host_apb),
      .source_apb4               (u_dvp_source_apb),
      .route_write_i             (s_route_write),
      .route_value_i             (s_route_value),
      .processing_format_i       (s_processing_format),
      .capture_state_i           (s_capture_state),
      .capture_arm_i             (s_capture_arm),
      .capture_close_i           (s_capture_close),
      .processor_idle_i          (s_processor_idle),
      .route_o                   (s_route),
      .route_idle_o              (s_route_idle),
      .route_change_o            (s_route_change),
      .dma_idle_i                (dma_idle_i),
      .dma_start_i               (dma_start_i),
      .transport_idle_i          (transport_idle_i),
      .transport_admitted_i      (transport_admitted_i),
      .stream_isolated_i         (stream_isolated_i),
      .source_config_i           (source_config_o),
      .source_config_pending_i   (s_source_config_pending),
      .source_command_pending_i  (s_source_command_pending),
      .source_flush_pending_i    (s_source_flush_pending),
      .source_status_valid_i     (source_status_valid_o),
      .source_capture_idle_i     (s_source_capture_idle),
      .source_active_i           (s_source_active),
      .source_enabled_i          (s_source_enabled),
      .source_requested_enabled_i(s_source_requested_enabled),
      .source_fifo_empty_i       (s_source_fifo_empty),
      .source_lifecycle_idle_i   (source_lifecycle_idle_o),
      .source_frame_stats_i      (source_frame_stats_o),
      .source_frame_stats_valid_i(source_frame_stats_valid_o),
      .source_error_i            (source_error_o),
      .source_ready_o            (s_source_ready),
      .source_quiet_o            (s_source_quiet),
      .source_done_o             (s_source_done),
      .source_stopped_o          (s_source_stopped),
      .source_sequence_o         (s_source_sequence),
      .source_words_o            (s_source_words),
      .source_geometry_o         (s_source_geometry),
      .source_err_o              (s_source_err),
      .source_config_err_o       (s_source_config_err),
      .source_stats_err_o        (s_source_stats_err),
      .dvp_valid_i               (s_dvp_valid),
      .dvp_ready_o               (s_dvp_ready),
      .dvp_data_i                (u_dvp_rx.tdata),
      .dvp_keep_i                (u_dvp_rx.tkeep),
      .dvp_strb_i                (u_dvp_rx.tstrb),
      .dvp_id_i                  (u_dvp_rx.tid),
      .dvp_dest_i                (u_dvp_rx.tdest),
      .dvp_user_i                (u_dvp_rx.tuser),
      .dvp_last_i                (u_dvp_rx.tlast),
      .process_valid_o           (s_process_valid),
      .process_ready_i           (s_process_ready),
      .process_data_o            (s_process_data),
      .process_keep_o            (s_process_keep),
      .process_strb_o            (s_process_strb),
      .process_id_o              (s_process_id),
      .process_dest_o            (s_process_dest),
      .process_user_o            (s_process_user),
      .process_last_o            (s_process_last),
      .processed_valid_i         (s_processed_valid),
      .processed_ready_o         (s_processed_ready),
      .processed_data_i          (s_processed_data),
      .processed_keep_i          (s_processed_keep),
      .processed_strb_i          (s_processed_strb),
      .processed_id_i            (s_processed_id),
      .processed_dest_i          (s_processed_dest),
      .processed_user_i          (s_processed_user),
      .processed_last_i          (s_processed_last),
      .dma_valid_o               (out_valid_o),
      .dma_ready_i               (out_ready_i),
      .dma_data_o                (out_data_o),
      .dma_keep_o                (out_keep_o),
      .dma_strb_o                (out_strb_o),
      .dma_id_o                  (out_id_o),
      .dma_dest_o                (out_dest_o),
      .dma_user_o                (out_user_o),
      .dma_last_o                (out_last_o)
  );

  axi4s_dvp u_dvp (
      .clk_i                     (clk_i),
      .rst_n_i                   (source_rst_n_i),
      .apb4                      (u_dvp_source_apb),
      .rx_axis                   (u_dvp_rx),
      .dvp                       (u_camera),
      .irq_o                     (dvp_irq_o),
      .lifecycle_idle_o          (source_lifecycle_idle_o),
      .lifecycle_reset_ready_o   (source_reset_ready_o),
      .source_config_o           (source_config_o),
      .source_config_pending_o   (s_source_config_pending),
      .source_command_pending_o  (s_source_command_pending),
      .source_flush_pending_o    (s_source_flush_pending),
      .source_status_valid_o     (source_status_valid_o),
      .source_capture_idle_o     (s_source_capture_idle),
      .source_active_o           (s_source_active),
      .source_enabled_o          (s_source_enabled),
      .source_requested_enabled_o(s_source_requested_enabled),
      .source_fifo_empty_o       (s_source_fifo_empty),
      .source_frame_stats_o      (source_frame_stats_o),
      .source_frame_stats_valid_o(source_frame_stats_valid_o),
      .source_error_o            (source_error_o)
  );

  apb4_ppalite #(
      .ExternalRoute(1'b1)
  ) u_ppa (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .clock_hz_i         (32'd24000000),
      .route_idle_i       (s_route_idle),
      .route_i            (s_route),
      .route_change_i     (s_route_change),
      .route_write_o      (s_route_write),
      .route_value_o      (s_route_value),
      .processing_format_o(s_processing_format),
      .capture_state_o    (s_capture_state),
      .capture_arm_o      (s_capture_arm),
      .capture_close_o    (s_capture_close),
      .processor_idle_o   (s_processor_idle),
      .source_ready_i     (s_source_ready),
      .source_quiet_i     (s_source_quiet),
      .source_done_i      (s_source_done),
      .source_stopped_i   (s_source_stopped),
      .source_sequence_i  (s_source_sequence),
      .source_words_i     (s_source_words),
      .source_geometry_i  (s_source_geometry),
      .source_err_i       (s_source_err),
      .source_config_err_i(s_source_config_err),
      .source_stats_err_i (s_source_stats_err),
      .transport_ready_i  (transport_ready_i),
      .transport_idle_i   (transport_idle_i),
      .transport_done_i   (transport_done_i),
      .transport_err_i    (transport_err_i),
      .in_valid_i         (s_process_valid),
      .in_ready_o         (s_process_ready),
      .in_data_i          (s_process_data),
      .in_keep_i          (s_process_keep),
      .in_strb_i          (s_process_strb),
      .in_id_i            (s_process_id),
      .in_dest_i          (s_process_dest),
      .in_user_i          (s_process_user),
      .in_last_i          (s_process_last),
      .out_valid_o        (s_processed_valid),
      .out_ready_i        (s_processed_ready),
      .out_data_o         (s_processed_data),
      .out_keep_o         (s_processed_keep),
      .out_strb_o         (s_processed_strb),
      .out_last_o         (s_processed_last),
      .out_id_o           (s_processed_id),
      .out_dest_o         (s_processed_dest),
      .out_user_o         (s_processed_user),
      .irq_o              (ppa_irq_o),
      .apb4               (u_ppa_apb)
  );
endmodule
