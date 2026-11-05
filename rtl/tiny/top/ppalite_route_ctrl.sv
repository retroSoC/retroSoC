`include "dvp_define.svh"
`include "ppalite_define.svh"

module ppalite_route_ctrl (
    input  logic                                             clk_i,
    input  logic                                             rst_n_i,
           apb4_if.slave                                     dvp_apb4,
           apb4_if.master                                    source_apb4,
    input  logic                                             route_write_i,
    input  logic                                             route_value_i,
    input  logic          [                             2:0] processing_format_i,
    input  logic          [                             2:0] capture_state_i,
    input  logic                                             capture_arm_i,
    input  logic                                             capture_close_i,
    input  logic                                             processor_idle_i,
    output logic                                             route_o,
    output logic                                             route_idle_o,
    output logic                                             route_change_o,
    input  logic                                             dma_idle_i,
    input  logic                                             dma_start_i,
    input  logic                                             transport_idle_i,
    input  logic                                             transport_admitted_i,
    input  logic                                             stream_isolated_i,
    input  logic          [                           127:0] source_config_i,
    input  logic                                             source_config_pending_i,
    input  logic                                             source_command_pending_i,
    input  logic                                             source_flush_pending_i,
    input  logic                                             source_status_valid_i,
    input  logic                                             source_capture_idle_i,
    input  logic                                             source_active_i,
    input  logic                                             source_enabled_i,
    input  logic                                             source_requested_enabled_i,
    input  logic                                             source_fifo_empty_i,
    input  logic                                             source_lifecycle_idle_i,
    input  logic          [`APB4_DVP__FRAME_STATS_WIDTH-1:0] source_frame_stats_i,
    input  logic                                             source_frame_stats_valid_i,
    input  logic          [                             5:0] source_error_i,
    output logic                                             source_ready_o,
    output logic                                             source_quiet_o,
    output logic                                             source_done_o,
    output logic                                             source_stopped_o,
    output logic          [                            31:0] source_sequence_o,
    output logic          [                            31:0] source_words_o,
    output logic          [                            31:0] source_geometry_o,
    output logic          [                             7:0] source_err_o,
    output logic                                             source_config_err_o,
    output logic                                             source_stats_err_o,
    input  logic                                             dvp_valid_i,
    output logic                                             dvp_ready_o,
    input  logic          [                            31:0] dvp_data_i,
    input  logic          [                             3:0] dvp_keep_i,
    input  logic          [                             3:0] dvp_strb_i,
    input  logic                                             dvp_id_i,
    input  logic                                             dvp_dest_i,
    input  logic                                             dvp_user_i,
    input  logic                                             dvp_last_i,
    output logic                                             process_valid_o,
    input  logic                                             process_ready_i,
    output logic          [                            31:0] process_data_o,
    output logic          [                             3:0] process_keep_o,
    output logic          [                             3:0] process_strb_o,
    output logic                                             process_id_o,
    output logic                                             process_dest_o,
    output logic                                             process_user_o,
    output logic                                             process_last_o,
    input  logic                                             processed_valid_i,
    output logic                                             processed_ready_o,
    input  logic          [                            31:0] processed_data_i,
    input  logic          [                             3:0] processed_keep_i,
    input  logic          [                             3:0] processed_strb_i,
    input  logic                                             processed_id_i,
    input  logic                                             processed_dest_i,
    input  logic                                             processed_user_i,
    input  logic                                             processed_last_i,
    output logic                                             dma_valid_o,
    input  logic                                             dma_ready_i,
    output logic          [                            31:0] dma_data_o,
    output logic          [                             3:0] dma_keep_o,
    output logic          [                             3:0] dma_strb_o,
    output logic                                             dma_id_o,
    output logic                                             dma_dest_o,
    output logic                                             dma_user_o,
    output logic                                             dma_last_o
);
  logic         s_route_d;
  logic         s_route_q;
  logic [127:0] s_source_config_d;
  logic [127:0] s_source_config_q;
  logic         s_frame_done_d;
  logic         s_frame_done_q;
  logic         s_reject_d;
  logic         s_reject_q;
  logic         s_legal_d;
  logic         s_legal_q;
  logic         s_access_reject;
  logic         s_owned;
  logic         s_closing;
  logic         s_source_quiet;
  logic         s_source_format_ok;
  logic         s_source_geometry_ok;
  logic         s_source_update;
  logic         s_access_forbidden;
  logic         s_config_access;
  logic         s_cmd_access;
  logic         s_ctrl_access;
  logic         s_write_access;
  logic [ 31:0] s_ctrl_current;
  logic [ 31:0] s_ctrl_merged;
  logic [127:0] s_active_config;
  logic [ 15:0] s_active_width;
  logic [ 15:0] s_active_height;
  logic [ 31:0] s_expected_pixels;
  logic [ 31:0] s_expected_words;

  function automatic logic [31:0] merge_wstrb(
      input logic [31:0] current_i, input logic [31:0] value_i, input logic [3:0] strobe_i);
    logic [31:0] merged;
    begin
      merged = current_i;
      for (int index = 0; index < 4; index++) begin
        if (strobe_i[index]) merged[index*8+:8] = value_i[index*8+:8];
      end
      return merged;
    end
  endfunction

  assign route_o = s_route_q;
  assign s_owned = capture_state_i != `PPALITE_STATE_IDLE;
  assign s_closing = capture_state_i == `PPALITE_STATE_CLOSING;
  assign s_source_quiet = source_status_valid_i && !source_enabled_i && !source_active_i &&
      source_capture_idle_i && source_fifo_empty_i && source_lifecycle_idle_i &&
      !source_config_pending_i && !source_command_pending_i && !source_flush_pending_i &&
      !source_frame_stats_valid_i;
  assign s_source_format_ok = source_config_i[99] && source_config_i[97] &&
      (source_config_i[103:102] == 2'd0) &&
      ((processing_format_i < 3'd2) ? (source_config_i[101:100] == 2'd0) :
                                      (source_config_i[101:100] == 2'd1));
  assign s_source_geometry_ok = (source_config_i[15:0] != 16'd0) &&
      (source_config_i[31:16] != 16'd0) &&
      (!source_config_i[98] ||
       ((source_config_i[79:64] != 16'd0) && (source_config_i[95:80] != 16'd0) &&
        (({1'b0, source_config_i[47:32]} + {1'b0, source_config_i[79:64]}) <=
         {1'b0, source_config_i[15:0]}) &&
        (({1'b0, source_config_i[63:48]} + {1'b0, source_config_i[95:80]}) <=
         {1'b0, source_config_i[31:16]})));
  assign source_ready_o = source_status_valid_i && s_source_format_ok &&
      s_source_geometry_ok && !s_source_update;
  assign source_quiet_o = s_source_quiet;
  assign source_done_o = source_frame_stats_valid_i;
  assign source_stopped_o = source_status_valid_i && !source_enabled_i && !source_active_i &&
      !source_config_pending_i && !source_command_pending_i && !source_flush_pending_i;
  assign source_sequence_o = source_frame_stats_i[31:0];
  assign source_words_o = source_frame_stats_i[111:80];
  assign source_geometry_o = source_config_i[98] ?
      {source_config_i[95:80], source_config_i[79:64]} :
      {source_config_i[31:16], source_config_i[15:0]};
  assign source_err_o = {1'b0, (s_owned && !source_status_valid_i), source_error_i};
  assign source_config_err_o = s_owned &&
      ({source_config_i[106:97], source_config_i[95:0]} !=
       {s_source_config_q[106:97], s_source_config_q[95:0]});
  assign s_active_config = s_owned ? s_source_config_q : source_config_i;
  assign s_active_width = s_active_config[98] ? s_active_config[79:64] : s_active_config[15:0];
  assign s_active_height = s_active_config[98] ? s_active_config[95:80] : s_active_config[31:16];
  assign s_expected_pixels = {16'd0, s_active_width} * {16'd0, s_active_height};
  assign s_expected_words = (({16'd0, s_active_width} + 32'd1) >> 1) * {16'd0, s_active_height};
  assign source_stats_err_o = source_frame_stats_valid_i &&
      ((source_frame_stats_i[47:32] != s_active_config[31:16]) ||
       (source_frame_stats_i[79:48] != s_expected_pixels) ||
       (source_frame_stats_i[111:80] != s_expected_words) ||
       (source_frame_stats_i[143:112] != 32'd0));

  assign route_idle_o = !s_owned && processor_idle_i && s_source_quiet && !s_source_update;
  assign route_change_o = (route_value_i == s_route_q) ? 1'b1 :
      (!s_owned && processor_idle_i && s_source_quiet && dma_idle_i && transport_idle_i &&
       !dma_start_i && !s_source_update && !dvp_valid_i && !processed_valid_i);

  assign s_write_access = dvp_apb4.psel && dvp_apb4.penable &&
      (dvp_apb4.pwrite || (|dvp_apb4.pstrb));
  assign s_ctrl_access = dvp_apb4.paddr[11:0] == `APB4_DVP_CTRL;
  assign s_cmd_access = dvp_apb4.paddr[11:0] == `APB4_DVP_COMMAND;
  assign s_config_access = s_ctrl_access || s_cmd_access ||
      (dvp_apb4.paddr[11:0] == `APB4_DVP_STREAM_CTRL) ||
      (dvp_apb4.paddr[11:0] == `APB4_DVP_FORMAT) ||
      (dvp_apb4.paddr[11:0] == `APB4_DVP_SYNC_CFG) ||
      (dvp_apb4.paddr[11:0] == `APB4_DVP_FRAME_SIZE) ||
      (dvp_apb4.paddr[11:0] == `APB4_DVP_CROP_START) ||
      (dvp_apb4.paddr[11:0] == `APB4_DVP_CROP_SIZE);
  assign s_ctrl_current = {29'd0, source_config_i[98:97], source_requested_enabled_i};
  assign s_ctrl_merged = merge_wstrb(s_ctrl_current, dvp_apb4.pwdata, dvp_apb4.pstrb);
  assign s_access_reject = s_access_forbidden && !s_legal_q;
  assign s_source_update = s_write_access && s_config_access && !s_access_reject &&
      !s_reject_q && !s_legal_q;

  always_comb begin
    s_access_forbidden = 1'b0;
    if (s_write_access && s_config_access && s_route_q) begin
      if (!dvp_apb4.pwrite || !(|dvp_apb4.pstrb)) begin
        s_access_forbidden = 1'b1;
      end else if (!s_owned) begin
        if ((source_requested_enabled_i && !source_enabled_i && !s_ctrl_access) ||
            (s_ctrl_access && s_ctrl_merged[`APB4_DVP__CTRL_ENABLE])) begin
          s_access_forbidden = 1'b1;
        end
      end else if ((source_config_pending_i || source_command_pending_i) && !s_closing) begin
        s_access_forbidden = 1'b1;
      end else if (s_closing) begin
        if (s_ctrl_access) begin
          if (s_ctrl_merged[`APB4_DVP__CTRL_ENABLE] ||
              (s_ctrl_merged[2:1] != s_ctrl_current[2:1])) begin
            s_access_forbidden = 1'b1;
          end
        end else if (s_cmd_access) begin
          if (!(transport_idle_i && stream_isolated_i)) s_access_forbidden = 1'b1;
        end else begin
          s_access_forbidden = 1'b1;
        end
      end else if (s_cmd_access) begin
        s_access_forbidden = 1'b1;
      end else if (s_ctrl_access) begin
        if (s_ctrl_merged[2:1] != s_ctrl_current[2:1]) begin
          s_access_forbidden = 1'b1;
        end else if (s_ctrl_merged[`APB4_DVP__CTRL_ENABLE] != source_enabled_i) begin
          if (s_ctrl_merged[`APB4_DVP__CTRL_ENABLE]) begin
            s_access_forbidden = !((capture_state_i == `PPALITE_STATE_ARMED) &&
                                   transport_admitted_i && !source_enabled_i && !capture_close_i);
          end else begin
            s_access_forbidden = !(s_frame_done_q && !source_active_i);
          end
        end
      end else begin
        s_access_forbidden = 1'b1;
      end
    end
  end

  always_comb begin
    source_apb4.paddr   = dvp_apb4.paddr;
    source_apb4.pprot   = dvp_apb4.pprot;
    source_apb4.psel    = dvp_apb4.psel && !s_access_reject && !s_reject_q;
    source_apb4.penable = dvp_apb4.penable;
    source_apb4.pwrite  = dvp_apb4.pwrite;
    source_apb4.pwdata  = dvp_apb4.pwdata;
    source_apb4.pstrb   = dvp_apb4.pstrb;
    dvp_apb4.pready     = s_reject_q ? 1'b1 : (s_access_reject ? 1'b0 : source_apb4.pready);
    dvp_apb4.prdata     = s_reject_q ? 32'd0 : source_apb4.prdata;
    dvp_apb4.pslverr    = s_reject_q ? 1'b1 : source_apb4.pslverr;
  end

  always_comb begin
    s_route_d = s_route_q;
    if (route_write_i && route_change_o) s_route_d = route_value_i;
  end
  dffr #(
      .DATA_WIDTH(1)
  ) u_route_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_route_d),
      .dat_o  (s_route_q)
  );

  always_comb begin
    s_source_config_d = s_source_config_q;
    if (capture_arm_i) s_source_config_d = source_config_i;
  end
  dffr #(
      .DATA_WIDTH(128)
  ) u_source_config_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_source_config_d),
      .dat_o  (s_source_config_q)
  );

  always_comb begin
    s_frame_done_d = s_frame_done_q;
    if (!s_owned) begin
      s_frame_done_d = 1'b0;
    end else if (source_frame_stats_valid_i) begin
      s_frame_done_d = 1'b1;
    end
  end
  dffr #(
      .DATA_WIDTH(1)
  ) u_frame_done_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_frame_done_d),
      .dat_o  (s_frame_done_q)
  );

  always_comb begin
    s_reject_d = s_reject_q;
    if (s_reject_q && dvp_apb4.pready) begin
      s_reject_d = 1'b0;
    end else if (dvp_apb4.psel && dvp_apb4.penable && s_access_reject) begin
      s_reject_d = 1'b1;
    end else if (!dvp_apb4.psel) begin
      s_reject_d = 1'b0;
    end
  end
  dffr #(
      .DATA_WIDTH(1)
  ) u_reject_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_reject_d),
      .dat_o  (s_reject_q)
  );

  always_comb begin
    s_legal_d = s_legal_q;
    if (s_write_access && s_config_access && !s_access_forbidden && !s_reject_q && !s_legal_q) begin
      s_legal_d = 1'b1;
    end else if (!dvp_apb4.psel || source_apb4.pready) begin
      s_legal_d = 1'b0;
    end
  end
  dffr #(
      .DATA_WIDTH(1)
  ) u_legal_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_legal_d),
      .dat_o  (s_legal_q)
  );

  always_comb begin
    dvp_ready_o       = 1'b0;
    process_valid_o   = 1'b0;
    process_data_o    = dvp_data_i;
    process_keep_o    = dvp_keep_i;
    process_strb_o    = dvp_strb_i;
    process_id_o      = dvp_id_i;
    process_dest_o    = dvp_dest_i;
    process_user_o    = dvp_user_i;
    process_last_o    = dvp_last_i;
    processed_ready_o = 1'b0;
    dma_valid_o       = 1'b0;
    dma_data_o        = dvp_data_i;
    dma_keep_o        = dvp_keep_i;
    dma_strb_o        = dvp_strb_i;
    dma_id_o          = dvp_id_i;
    dma_dest_o        = dvp_dest_i;
    dma_user_o        = dvp_user_i;
    dma_last_o        = dvp_last_i;
    if (s_route_q) begin
      process_valid_o   = s_closing ? 1'b0 : dvp_valid_i;
      dvp_ready_o       = s_closing ? 1'b0 : process_ready_i;
      dma_valid_o       = processed_valid_i;
      dma_data_o        = processed_data_i;
      dma_keep_o        = processed_keep_i;
      dma_strb_o        = processed_strb_i;
      dma_id_o          = processed_id_i;
      dma_dest_o        = processed_dest_i;
      dma_user_o        = processed_user_i;
      dma_last_o        = processed_last_i;
      processed_ready_o = dma_ready_i;
    end else begin
      dvp_ready_o = dma_ready_i;
      dma_valid_o = dvp_valid_i;
    end
  end

`ifdef FORMAL
  logic s_formal_past_q;
  always_ff @(posedge clk_i) begin
    if (!rst_n_i) begin
      s_formal_past_q <= 1'b0;
    end else begin
      s_formal_past_q <= 1'b1;
      if (s_formal_past_q && $past(!route_write_i)) assert (s_route_q == $past(s_route_q));
      if (s_formal_past_q && $past(
              route_write_i && dma_start_i && (route_value_i != s_route_q)
          )) begin
        assert (s_route_q == $past(s_route_q));
      end
      if (route_write_i && (route_value_i != s_route_q) &&
          (s_owned || !processor_idle_i || !s_source_quiet || !dma_idle_i || !transport_idle_i ||
           dma_start_i || s_source_update || dvp_valid_i || processed_valid_i)) begin
        assert (!route_change_o);
      end
      if (s_reject_q) begin
        assert (dvp_apb4.pready && dvp_apb4.pslverr && !source_apb4.psel);
      end
      if (!s_route_q) begin
        assert (dma_valid_o == dvp_valid_i && dvp_ready_o == dma_ready_i);
        assert ({dma_data_o, dma_keep_o, dma_strb_o, dma_id_o, dma_dest_o, dma_user_o,
                 dma_last_o} ==
                {dvp_data_i, dvp_keep_i, dvp_strb_i, dvp_id_i, dvp_dest_i, dvp_user_i,
                 dvp_last_i});
      end
      if (s_route_q) begin
        assert (dma_valid_o == processed_valid_i && processed_ready_o == dma_ready_i);
        assert (process_valid_o == (s_closing ? 1'b0 : dvp_valid_i));
        assert ({dma_data_o, dma_keep_o, dma_strb_o, dma_id_o, dma_dest_o, dma_user_o,
                 dma_last_o} ==
                {processed_data_i, processed_keep_i, processed_strb_i, processed_id_i,
                 processed_dest_i, processed_user_i, processed_last_i});
      end
      if (route_value_i == s_route_q) assert (route_change_o);
      if (s_source_update) assert (!source_ready_o);
      if (s_owned && !source_status_valid_i) assert (source_err_o[6]);
      if (source_frame_stats_valid_i &&
          ((source_frame_stats_i[47:32] != s_active_config[31:16]) ||
           (source_frame_stats_i[79:48] != s_expected_pixels) ||
           (source_frame_stats_i[111:80] != s_expected_words) ||
           (source_frame_stats_i[143:112] != 32'd0))) begin
        assert (source_stats_err_o);
      end
      if (s_formal_past_q && $past(s_owned && !capture_arm_i)) begin
        assert (s_source_config_q == $past(s_source_config_q));
      end
      if (s_reject_q) assert (!source_apb4.psel);
      if (s_owned && s_closing && s_route_q) assert (!process_valid_o && !dvp_ready_o);
      if (s_route_q && s_write_access && s_config_access &&
          (!dvp_apb4.pwrite || !(|dvp_apb4.pstrb))) begin
        assert (s_access_forbidden && !s_source_update);
      end
      if (s_route_q && !s_owned && source_requested_enabled_i && !source_enabled_i &&
          s_write_access && s_config_access && !s_ctrl_access) begin
        assert (s_access_forbidden && !s_source_update);
      end
      if (s_route_q && !s_owned && s_write_access && s_ctrl_access &&
          s_ctrl_merged[`APB4_DVP__CTRL_ENABLE]) begin
        assert (s_access_forbidden && !s_source_update);
      end
      if (s_route_q && s_closing && s_write_access && s_config_access &&
          !s_ctrl_access && !s_cmd_access) begin
        assert (s_access_forbidden && !s_source_update);
      end
      if (s_route_q && capture_close_i && s_write_access && s_ctrl_access &&
          s_ctrl_merged[`APB4_DVP__CTRL_ENABLE] && !source_enabled_i) begin
        assert (s_access_forbidden && !s_source_update);
      end
      cover (!s_route_q && dvp_valid_i && dma_ready_i);
      cover (route_write_i && route_change_o && (route_value_i != s_route_q));
      cover (s_route_q && s_owned && source_frame_stats_valid_i && !source_stats_err_o);
      cover (s_owned && s_closing && !source_status_valid_i);
      cover (s_owned && source_enabled_i && !source_config_pending_i &&
             (source_config_i == s_source_config_q));
    end
  end
`endif
endmodule
