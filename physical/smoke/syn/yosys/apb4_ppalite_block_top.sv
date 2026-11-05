module apb4_ppalite_block_top (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic [31:0] clock_hz_i,
    input  logic        route_idle_i,
    input  logic        source_ready_i,
    input  logic        source_quiet_i,
    input  logic        source_done_i,
    input  logic        source_stopped_i,
    input  logic [31:0] source_sequence_i,
    input  logic [31:0] source_words_i,
    input  logic [31:0] source_geometry_i,
    input  logic [ 7:0] source_err_i,
    input  logic        transport_ready_i,
    input  logic        transport_idle_i,
    input  logic        transport_done_i,
    input  logic [ 7:0] transport_err_i,
    input  logic        in_valid_i,
    output logic        in_ready_o,
    input  logic [31:0] in_data_i,
    input  logic [ 3:0] in_keep_i,
    input  logic [ 3:0] in_strb_i,
    input  logic        in_id_i,
    input  logic        in_dest_i,
    input  logic        in_user_i,
    input  logic        in_last_i,
    output logic        out_valid_o,
    input  logic        out_ready_i,
    output logic [31:0] out_data_o,
    output logic [ 3:0] out_keep_o,
    output logic [ 3:0] out_strb_o,
    output logic        out_last_o,
    output logic        out_id_o,
    output logic        out_dest_o,
    output logic        out_user_o,
    output logic        irq_o,
`ifdef PPALITE_FORMAL_TOP
    output logic [ 2:0] formal_state_o,
    output logic [ 7:0] formal_core_err_o,
`endif
    input  logic [31:0] paddr_i,
    input  logic [ 2:0] pprot_i,
    input  logic        psel_i,
    input  logic        penable_i,
    input  logic        pwrite_i,
    input  logic [31:0] pwdata_i,
    input  logic [ 3:0] pstrb_i,
    output logic        pready_o,
    output logic [31:0] prdata_o,
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

  /* verilator lint_off PINCONNECTEMPTY */
  apb4_ppalite u_dut (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .clock_hz_i         (clock_hz_i),
      .route_idle_i       (route_idle_i),
      .route_i            (1'b0),
      .route_change_i     (1'b0),
      .route_write_o      (),                   // P1 synthesis retains the internal selector.
      .route_value_o      (),
      .processing_format_o(),
      .capture_state_o    (),
      .capture_arm_o      (),
      .capture_close_o    (),
      .processor_idle_o   (),
      .source_ready_i     (source_ready_i),
      .source_quiet_i     (source_quiet_i),
      .source_done_i      (source_done_i),
      .source_stopped_i   (source_stopped_i),
      .source_sequence_i  (source_sequence_i),
      .source_words_i     (source_words_i),
      .source_geometry_i  (source_geometry_i),
      .source_err_i       (source_err_i),
      .source_config_err_i(1'b0),
      .source_stats_err_i (1'b0),
      .transport_ready_i  (transport_ready_i),
      .transport_idle_i   (transport_idle_i),
      .transport_done_i   (transport_done_i),
      .transport_err_i    (transport_err_i),
      .in_valid_i         (in_valid_i),
      .in_ready_o         (in_ready_o),
      .in_data_i          (in_data_i),
      .in_keep_i          (in_keep_i),
      .in_strb_i          (in_strb_i),
      .in_id_i            (in_id_i),
      .in_dest_i          (in_dest_i),
      .in_user_i          (in_user_i),
      .in_last_i          (in_last_i),
      .out_valid_o        (out_valid_o),
      .out_ready_i        (out_ready_i),
      .out_data_o         (out_data_o),
      .out_keep_o         (out_keep_o),
      .out_strb_o         (out_strb_o),
      .out_last_o         (out_last_o),
      .out_id_o           (out_id_o),
      .out_dest_o         (out_dest_o),
      .out_user_o         (out_user_o),
`ifdef PPALITE_FORMAL_TOP
      .formal_state_o     (formal_state_o),
      .formal_core_err_o  (formal_core_err_o),
`endif
      .irq_o              (irq_o),
      .apb4               (u_apb)
  );
  /* verilator lint_on PINCONNECTEMPTY */
endmodule
