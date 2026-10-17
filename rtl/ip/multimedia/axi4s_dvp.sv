// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "dvp_define.svh"

/* verilator lint_off DECLFILENAME */
interface dvp_if ();
  logic       pclk_i;
  logic       href_i;
  logic       vsync_i;
  logic [7:0] dat_i;

  modport dut(input pclk_i, input href_i, input vsync_i, input dat_i);
endinterface
/* verilator lint_on DECLFILENAME */

// Configuration and commands cross from clk_i into the selected pixel clock;
// captured payloads return through the warm-flush FIFO. The FIFO backpressures
// the pixel core, and reset clears both transfer domains before streaming resumes.
module axi4s_dvp (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic          clk_i,
    input  logic          rst_n_i,
    apb4_if.slave         apb4,
    axi4_stream_if.source rx_axis,
    dvp_if.dut            dvp,
    output logic          irq_o,
    output logic          lifecycle_idle_o,
    output logic          lifecycle_reset_ready_o
    // verilog_format: on
);
  localparam int DvpPayloadWidth = 42;

  logic [127:0] s_cfg_sys;
  logic         s_cfg_v_sys;
  logic         s_cfg_rdy_sys;
  logic         s_cfg_link_ready;
  logic         s_cfg_admit;
  logic         s_cfg_apply_pclk_q;
  logic [128:0] s_cfg_packet_pclk;
  logic s_cfg_epoch_q, s_cfg_epoch_pclk_q, s_cfg_epoch_latched_q;
  logic s_cfg_busy_d, s_cfg_busy_q, s_cfg_accept_sys;
  logic s_cmd_epoch_q, s_cmd_epoch_pclk_q;
  logic s_cmd_busy_d, s_cmd_busy_q, s_cmd_accept_sys;
  logic [3:0] s_cmd_packet_pclk;
  logic s_cfg_cancel_d, s_cfg_cancel_q;
  logic       s_cfg_cancel_epoch_q;
  logic       s_cfg_cancel_apply;
  logic       s_ctrl_pending;
  logic       s_stat_seen_q;
  logic       s_capture_idle_pclk;
  logic [5:0] s_core_err_events;
  logic [5:0] s_err_pending_d, s_err_pending_q;
  logic s_err_report_ready, s_err_report_valid;
  logic [  5:0] s_err_report_sys;
  logic [127:0] s_cfg_pclk_q;
  logic         s_cfg_v_pclk;
  logic         s_cfg_rdy_pclk;
  logic [  1:0] s_cmd_sys;
  logic [  1:0] s_cmd_pclk;
  logic         s_cmd_v_pclk;
  logic         s_cmd_rdy_pclk;
  logic         s_cmd_rdy_sys;
  logic         s_cmd_v_sys;
  logic [  1:0] s_cmd_core;
  logic         s_cmd_abort_sys;
  logic         s_cmd_flush_sys;

  logic         s_pclk_inv;
  logic         s_pclk_buf;
  logic         s_pclk_rst_n;
  logic         s_pclk_sel;
  logic         s_pclk_falling;
  logic         s_active;
  logic         s_active_pclk;
  logic [  5:0] s_err_clear;
  logic [5:0] s_clear_pending_d, s_clear_pending_q;
  logic [5:0] s_clear_mask_q;
  logic s_clear_busy_d, s_clear_busy_q;
  logic                                    s_clear_epoch_q;
  logic                                    s_clear_epoch_pclk_q;
  logic                                    s_clear_ready_sys;
  logic                                    s_clear_valid_pclk;
  logic                                    s_clear_ready_pclk;
  logic [                             6:0] s_clear_packet_pclk;
  logic                                    s_clear_accept_sys;
  logic                                    s_clear_accept_pclk;
  logic [                             5:0] s_clear_done;
  logic [                            12:0] s_stat_sys;
  logic                                    s_stat_valid_sys;
  logic                                    s_stream_en;
  logic                                    s_fifo_src_ready;
  logic                                    s_fifo_dst_valid;
  logic [             DvpPayloadWidth-1:0] s_fifo_dst_data;
  logic                                    s_fifo_dst_ready;
  logic                                    s_fifo_src_clear;
  logic                                    s_fifo_src_clear_busy;
  logic                                    s_fifo_dst_clear_busy;
  logic [             DvpPayloadWidth-1:0] s_core_push_data;
  logic                                    s_core_push_valid;
  logic [                            31:0] s_fifo_rx_data;
  logic                                    s_rx_pop;
  logic                                    s_fifo_full_sys;
  logic                                    s_fifo_empty_sys;
  logic                                    s_frm_start_tgl;
  logic                                    s_line_done_tgl;
  logic                                    s_frm_done_tgl;
  logic                                    s_unused_err_tgl;
  logic                                    s_frame_start_event;
  logic                                    s_line_done_event;
  logic                                    s_frame_done_event;
  logic [                             2:0] s_event_rise;
  logic [                             2:0] s_event_fall;
  logic [                             5:0] s_err_flags_pclk;
  logic [                             5:0] s_err_flags_sys;
  logic [`APB4_DVP__FRAME_STATS_WIDTH-1:0] s_frm_stats_pclk;
  logic                                    s_frm_stats_v_pclk;
  logic                                    s_frm_stats_rdy_pclk;
  logic [`APB4_DVP__FRAME_STATS_WIDTH-1:0] s_frm_stats_sys;
  logic                                    s_frm_stats_v_sys;

  assign s_cmd_sys = {s_cmd_flush_sys, s_cmd_abort_sys};
  // Commands are consumed in the pixel domain as soon as they cross the CDC.
  assign s_cmd_rdy_pclk = !s_fifo_src_clear_busy;
  assign s_pclk_falling = s_cfg_sys[106];
  assign s_fifo_src_clear = s_cmd_v_pclk && s_cmd_rdy_pclk &&
                            (s_cmd_pclk[`APB4_DVP__COMMAND_FLUSH] ||
                             s_cmd_pclk[`APB4_DVP__COMMAND_ABORT]);
  assign s_fifo_dst_ready = !s_fifo_dst_clear_busy && (s_stream_en ? rx_axis.tready : s_rx_pop);
  assign s_fifo_rx_data = s_fifo_dst_data[31:0];
  assign s_fifo_empty_sys = !s_fifo_dst_valid;
  assign s_cfg_admit = !s_clear_busy_q && !(|s_clear_pending_q) && !(|s_err_clear) &&
                        !s_cfg_busy_q && !s_cmd_busy_q && !s_cmd_v_sys;
  assign s_cfg_rdy_sys = s_cfg_admit && s_cfg_link_ready;
  assign s_cfg_accept_sys = s_cfg_v_sys && s_cfg_rdy_sys;
  assign s_cfg_busy_d = (s_stat_valid_sys && s_cfg_busy_q &&
                         s_stat_sys[10] == s_cfg_epoch_q) ? 1'b0 :
                         (s_cfg_accept_sys || s_cfg_busy_q);
  assign s_cmd_accept_sys = s_cmd_v_sys && !s_cmd_busy_q && s_cmd_rdy_sys;
  assign s_cmd_busy_d = (s_stat_valid_sys && s_cmd_busy_q && s_stat_sys[12] &&
                         s_stat_sys[11] == s_cmd_epoch_q) ? 1'b0 :
                         (s_cmd_accept_sys || s_cmd_busy_q);
  assign s_cmd_pclk = s_cmd_packet_pclk[1:0];
  // One config may be in flight. ABORT carries its epoch independently of
  // config readiness, so an active frame can always be stopped. The cancelled
  // config still retires through the normal CDC/application acknowledgement.
  assign s_cfg_cancel_apply = s_cfg_cancel_q && (s_cfg_epoch_latched_q == s_cfg_cancel_epoch_q);
  assign s_cfg_cancel_d = s_cmd_core[`APB4_DVP__COMMAND_ABORT] ? 1'b1 :
                           (s_cfg_apply_pclk_q &&
                            (s_cfg_epoch_latched_q != s_cfg_cancel_epoch_q)) ? 1'b0 :
                           s_cfg_cancel_q;
  assign s_ctrl_pending = s_cfg_v_sys || s_cfg_busy_q || s_cmd_v_sys || s_cmd_busy_q ||
                         s_clear_busy_q || (|s_clear_pending_q) || (|s_err_clear);

  tc_clk_buf u_dvp_pclk_clk_buf (
      .clk_i(dvp.pclk_i),
      .clk_o(s_pclk_buf)
  );
  tc_clk_inv u_dvp_pclk_inv (
      .clk_i(s_pclk_buf),
      .clk_o(s_pclk_inv)
  );
  tc_clk_mux2 u_dvp_pclk_mux (
      .clk0_i   (s_pclk_buf),
      .clk1_i   (s_pclk_inv),
      .clk_sel_i(s_pclk_falling),
      .clk_o    (s_pclk_sel)
  );

  rst_sync #(
      .STAGE(5)
  ) u_dvp_pclk_rst_sync (
      .clk_i  (s_pclk_sel),
      .rst_n_i(rst_n_i),
      .rst_n_o(s_pclk_rst_n)
  );

  dvp_reg u_dvp_reg (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .apb4               (apb4),
      .active_i           (s_active),
      .enabled_i          (s_stat_sys[7]),
      .fifo_empty_i       (s_fifo_empty_sys),
      .fifo_full_i        (s_fifo_full_sys),
      .rx_data_i          (s_fifo_rx_data),
      .frame_start_i      (s_frame_start_event),
      .line_done_i        (s_line_done_event),
      .frame_done_i       (s_frame_done_event),
      .error_event_i      (s_err_report_valid),
      .error_events_i     (s_err_report_sys),
      .error_flags_i      (s_err_flags_sys),
      .error_valid_i      (s_stat_valid_sys),
      .error_clear_done_i (s_clear_done),
      .error_clear_o      (s_err_clear),
      .frame_stats_i      (s_frm_stats_sys),
      .frame_stats_valid_i(s_frm_stats_v_sys),
      .cfg_o              (s_cfg_sys),
      .cfg_valid_o        (s_cfg_v_sys),
      .cfg_ready_i        (s_cfg_rdy_sys),
      .cmd_abort_o        (s_cmd_abort_sys),
      .cmd_flush_o        (s_cmd_flush_sys),
      .cmd_valid_o        (s_cmd_v_sys),
      .cmd_ready_i        (s_cmd_rdy_sys && !s_cmd_busy_q),
      .rx_pop_o           (s_rx_pop),
      .stream_enable_o    (s_stream_en),
      .irq_o              (irq_o)
  );

  cdc_2phase #(
      .DATA_WIDTH(129)
  ) u_dvp_config_cdc (
      .src_clk_i  (clk_i),
      .src_rst_n_i(rst_n_i),
      .src_data_i ({!s_cfg_epoch_q, s_cfg_sys}),
      .src_valid_i(s_cfg_v_sys && s_cfg_admit),
      .src_ready_o(s_cfg_link_ready),
      .dst_clk_i  (s_pclk_sel),
      .dst_rst_n_i(s_pclk_rst_n),
      .dst_data_o (s_cfg_packet_pclk),
      .dst_valid_o(s_cfg_v_pclk),
      .dst_ready_i(s_cfg_rdy_pclk && !s_cfg_apply_pclk_q)
  );
  // The CDC mailbox presents data before acceptance. Freeze the applied
  // configuration during capture, and notify the core after it is latched.
  dffer #(
      .DATA_WIDTH(128)
  ) u_applied_config (
      .clk_i  (s_pclk_sel),
      .rst_n_i(s_pclk_rst_n),
      .en_i   (s_cfg_v_pclk && s_cfg_rdy_pclk && !s_cfg_apply_pclk_q),
      .dat_i  (s_cfg_packet_pclk[127:0]),
      .dat_o  (s_cfg_pclk_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_config_applied (
      .clk_i  (s_pclk_sel),
      .rst_n_i(s_pclk_rst_n),
      .dat_i  (s_cfg_v_pclk && s_cfg_rdy_pclk && !s_cfg_apply_pclk_q),
      .dat_o  (s_cfg_apply_pclk_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_config_busy (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_cfg_busy_d),
      .dat_o  (s_cfg_busy_q)
  );
  dffer #(
      .DATA_WIDTH(1)
  ) u_config_epoch (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_cfg_accept_sys),
      .dat_i  (!s_cfg_epoch_q),
      .dat_o  (s_cfg_epoch_q)
  );
  dffer #(
      .DATA_WIDTH(1)
  ) u_config_epoch_latch (
      .clk_i  (s_pclk_sel),
      .rst_n_i(s_pclk_rst_n),
      .en_i   (s_cfg_v_pclk && s_cfg_rdy_pclk && !s_cfg_apply_pclk_q),
      .dat_i  (s_cfg_packet_pclk[128]),
      .dat_o  (s_cfg_epoch_latched_q)
  );
  dffer #(
      .DATA_WIDTH(1)
  ) u_config_epoch_applied (
      .clk_i  (s_pclk_sel),
      .rst_n_i(s_pclk_rst_n),
      .en_i   (s_cfg_apply_pclk_q),
      .dat_i  (s_cfg_epoch_latched_q),
      .dat_o  (s_cfg_epoch_pclk_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_command_busy (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_cmd_busy_d),
      .dat_o  (s_cmd_busy_q)
  );
  // Source admission prevents a newer config until this command has drained.
  // Clear the tombstone on the first different applied epoch, before the
  // one-bit epoch can be reused. Repeated ABORTs of the same item cannot wrap it.
  dffr #(
      .DATA_WIDTH(1)
  ) u_config_cancel (
      .clk_i  (s_pclk_sel),
      .rst_n_i(s_pclk_rst_n),
      .dat_i  (s_cfg_cancel_d),
      .dat_o  (s_cfg_cancel_q)
  );
  dffer #(
      .DATA_WIDTH(1)
  ) u_config_cancel_epoch (
      .clk_i  (s_pclk_sel),
      .rst_n_i(s_pclk_rst_n),
      .en_i   (s_cmd_core[`APB4_DVP__COMMAND_ABORT]),
      .dat_i  (s_cmd_packet_pclk[3]),
      .dat_o  (s_cfg_cancel_epoch_q)
  );
  dffer #(
      .DATA_WIDTH(1)
  ) u_command_epoch (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_cmd_accept_sys),
      .dat_i  (!s_cmd_epoch_q),
      .dat_o  (s_cmd_epoch_q)
  );
  dffer #(
      .DATA_WIDTH(1)
  ) u_command_epoch_applied (
      .clk_i  (s_pclk_sel),
      .rst_n_i(s_pclk_rst_n),
      .en_i   (s_cmd_v_pclk && s_cmd_rdy_pclk),
      .dat_i  (s_cmd_packet_pclk[2]),
      .dat_o  (s_cmd_epoch_pclk_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_status_seen (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_stat_seen_q || s_stat_valid_sys),
      .dat_o  (s_stat_seen_q)
  );

  cdc_2phase #(
      .DATA_WIDTH(4)
  ) u_dvp_command_cdc (
      .src_clk_i  (clk_i),
      .src_rst_n_i(rst_n_i),
      .src_data_i ({s_cfg_epoch_q, !s_cmd_epoch_q, s_cmd_sys}),
      .src_valid_i(s_cmd_v_sys && !s_cmd_busy_q),
      .src_ready_o(s_cmd_rdy_sys),
      .dst_clk_i  (s_pclk_sel),
      .dst_rst_n_i(s_pclk_rst_n),
      .dst_data_o (s_cmd_packet_pclk),
      .dst_valid_o(s_cmd_v_pclk),
      .dst_ready_i(s_cmd_rdy_pclk)
  );

  cdc_fifo_warm_flush #(
      .DATA_WIDTH  (DvpPayloadWidth),
      .BUFFER_DEPTH(128)
  ) u_dvp_payload_fifo (
      .src_clk_i       (s_pclk_sel),
      .src_rst_n_i     (s_pclk_rst_n),
      .src_clear_i     (s_fifo_src_clear),
      .src_clear_busy_o(s_fifo_src_clear_busy),
      .src_data_i      (s_core_push_data),
      .src_valid_i     (s_core_push_valid),
      .src_ready_o     (s_fifo_src_ready),
      .dst_clk_i       (clk_i),
      .dst_rst_n_i     (rst_n_i),
      .dst_clear_busy_o(s_fifo_dst_clear_busy),
      .dst_data_o      (s_fifo_dst_data),
      .dst_valid_o     (s_fifo_dst_valid),
      .dst_ready_i     (s_fifo_dst_ready)
  );
  assign s_cmd_core = (s_cmd_v_pclk && s_cmd_rdy_pclk) ? s_cmd_pclk : 2'b00;

  // W1C is acknowledged by a coherent post-clear status packet, not by
  // sampling the old asynchronously synchronized sticky error level.
  assign s_clear_accept_sys = !s_clear_busy_q && (|s_clear_pending_q) && s_clear_ready_sys;
  assign s_clear_ready_pclk = !s_fifo_src_clear_busy && !s_cmd_v_pclk;
  assign s_clear_accept_pclk = s_clear_valid_pclk && s_clear_ready_pclk;
  assign s_clear_done = (s_stat_valid_sys && s_clear_busy_q &&
                         s_stat_sys[8] == s_clear_epoch_q) ? s_clear_mask_q : 6'd0;
  assign s_clear_pending_d = (s_clear_accept_sys ? 6'd0 : s_clear_pending_q) | s_err_clear;
  assign s_err_flags_sys = s_stat_sys[5:0];
  assign s_active = s_stat_sys[6];
  assign s_clear_busy_d = (|s_clear_done) ? 1'b0 : (s_clear_accept_sys || s_clear_busy_q);
  dffr #(
      .DATA_WIDTH(6)
  ) u_clear_pending (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_clear_pending_d),
      .dat_o  (s_clear_pending_q)
  );
  dffer #(
      .DATA_WIDTH(6)
  ) u_clear_mask (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_clear_accept_sys),
      .dat_i  (s_clear_pending_q),
      .dat_o  (s_clear_mask_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_clear_busy (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_clear_busy_d),
      .dat_o  (s_clear_busy_q)
  );
  dffer #(
      .DATA_WIDTH(1)
  ) u_clear_epoch (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_clear_accept_sys),
      .dat_i  (!s_clear_epoch_q),
      .dat_o  (s_clear_epoch_q)
  );
  dffer #(
      .DATA_WIDTH(1)
  ) u_clear_pixel_epoch (
      .clk_i  (s_pclk_sel),
      .rst_n_i(s_pclk_rst_n),
      .en_i   (s_clear_accept_pclk),
      .dat_i  (s_clear_packet_pclk[6]),
      .dat_o  (s_clear_epoch_pclk_q)
  );
  cdc_2phase #(
      .DATA_WIDTH(7)
  ) u_error_clear_cdc (
      .src_clk_i  (clk_i),
      .src_rst_n_i(rst_n_i),
      .src_data_i ({!s_clear_epoch_q, s_clear_pending_q}),
      .src_valid_i(!s_clear_busy_q && (|s_clear_pending_q)),
      .src_ready_o(s_clear_ready_sys),
      .dst_clk_i  (s_pclk_sel),
      .dst_rst_n_i(s_pclk_rst_n),
      .dst_data_o (s_clear_packet_pclk),
      .dst_valid_o(s_clear_valid_pclk),
      .dst_ready_i(s_clear_ready_pclk)
  );
  /* verilator lint_off PINCONNECTEMPTY */
  cdc_2phase #(
      .DATA_WIDTH(13)
  ) u_status_cdc (
      .src_clk_i(s_pclk_sel),
      .src_rst_n_i(s_pclk_rst_n),
      .src_data_i({
        !s_fifo_src_clear_busy,
        s_cmd_epoch_pclk_q,
        s_cfg_epoch_pclk_q,
        s_capture_idle_pclk && !s_fifo_src_clear_busy && !(|s_err_pending_q) && s_err_report_ready,
        s_clear_epoch_pclk_q,
        s_cfg_pclk_q[96],
        s_active_pclk,
        s_err_flags_pclk
      }),
      .src_valid_i(1'b1),
      .src_ready_o(),  // Polling status producer has no payload to retire.
      .dst_clk_i(clk_i),
      .dst_rst_n_i(rst_n_i),
      .dst_data_o(s_stat_sys),
      .dst_valid_o(s_stat_valid_sys),
      .dst_ready_i(1'b1)
  );
  /* verilator lint_on PINCONNECTEMPTY */

  // Coalesce causes while a notification is in flight. A new cause on the
  // acceptance edge remains pending for the next transfer, even for the same
  // bit. Unlike a sampled toggle, an even number of events cannot disappear.
  assign s_err_pending_d = (s_err_report_ready ? 6'd0 : s_err_pending_q) | s_core_err_events;
  dffr #(
      .DATA_WIDTH(6)
  ) u_error_pending (
      .clk_i  (s_pclk_sel),
      .rst_n_i(s_pclk_rst_n),
      .dat_i  (s_err_pending_d),
      .dat_o  (s_err_pending_q)
  );
  cdc_2phase #(
      .DATA_WIDTH(6)
  ) u_error_events_cdc (
      .src_clk_i  (s_pclk_sel),
      .src_rst_n_i(s_pclk_rst_n),
      .src_data_i (s_err_pending_q),
      .src_valid_i(|s_err_pending_q),
      .src_ready_o(s_err_report_ready),
      .dst_clk_i  (clk_i),
      .dst_rst_n_i(rst_n_i),
      .dst_data_o (s_err_report_sys),
      .dst_valid_o(s_err_report_valid),
      .dst_ready_i(1'b1)
  );

  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_fifo_full_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (!s_fifo_src_ready),
      .dat_o  (s_fifo_full_sys)
  );

  // Each source event toggles its level. Both synchronized edges represent
  // events; consuming only rising edges loses every second frame/line/error.
  assign {s_frame_done_event, s_line_done_event, s_frame_start_event} =
      s_event_rise[2:0] | s_event_fall[2:0];
  /* verilator lint_off PINCONNECTEMPTY */
  edge_det #(
      .STAGE(2)
  ) u_frame_start_event (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_frm_start_tgl),
      .dat_o  (),                 // Only the synchronized edge pulses are consumed.
      .re_o   (s_event_rise[0]),
      .fe_o   (s_event_fall[0])
  );
  edge_det #(
      .STAGE(2)
  ) u_line_done_event (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_line_done_tgl),
      .dat_o  (),                 // Only the synchronized edge pulses are consumed.
      .re_o   (s_event_rise[1]),
      .fe_o   (s_event_fall[1])
  );
  edge_det #(
      .STAGE(2)
  ) u_frame_done_event (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_frm_done_tgl),
      .dat_o  (),                 // Only the synchronized edge pulses are consumed.
      .re_o   (s_event_rise[2]),
      .fe_o   (s_event_fall[2])
  );
  /* verilator lint_on PINCONNECTEMPTY */

  cdc_2phase #(
      .DATA_WIDTH(`APB4_DVP__FRAME_STATS_WIDTH)
  ) u_dvp_stats_cdc (
      .src_clk_i  (s_pclk_sel),
      .src_rst_n_i(s_pclk_rst_n),
      .src_data_i (s_frm_stats_pclk),
      .src_valid_i(s_frm_stats_v_pclk),
      .src_ready_o(s_frm_stats_rdy_pclk),
      .dst_clk_i  (clk_i),
      .dst_rst_n_i(rst_n_i),
      .dst_data_o (s_frm_stats_sys),
      .dst_valid_o(s_frm_stats_v_sys),
      .dst_ready_i(1'b1)
  );

  assign rx_axis.tdata = s_fifo_dst_data[31:0];
  assign rx_axis.tkeep = s_fifo_dst_data[39:36];
  assign rx_axis.tstrb = s_fifo_dst_data[35:32];
  assign rx_axis.tlast = s_fifo_dst_data[40];
  assign rx_axis.tid = '0;
  assign rx_axis.tdest = '0;
  assign rx_axis.tuser = s_fifo_dst_data[41];
  assign rx_axis.tvalid = s_stream_en && s_fifo_dst_valid;
  assign lifecycle_idle_o = !s_ctrl_pending && (!s_stat_seen_q || s_stat_sys[9]) &&
                            s_fifo_empty_sys && !s_fifo_dst_clear_busy && !rx_axis.tvalid;
  assign lifecycle_reset_ready_o = s_stat_seen_q && lifecycle_idle_o && s_stat_sys[12];

  dvp_core u_dvp_core (
      .clk_i               (s_pclk_sel),
      .rst_n_i             (s_pclk_rst_n),
      .cfg_i               (s_cfg_pclk_q),
      .cfg_valid_i         (s_cfg_apply_pclk_q),
      .cfg_cancel_i        (s_cfg_cancel_apply),
      .cmd_i               (s_cmd_core),
      .error_clear_i       (s_clear_accept_pclk ? s_clear_packet_pclk[5:0] : 6'd0),
      .cfg_ready_o         (s_cfg_rdy_pclk),
      .push_ready_i        (s_fifo_src_ready),
      .push_valid_o        (s_core_push_valid),
      .push_data_o         (s_core_push_data),
      .active_o            (s_active_pclk),
      .capture_idle_o      (s_capture_idle_pclk),
      .frame_start_toggle_o(s_frm_start_tgl),
      .line_done_toggle_o  (s_line_done_tgl),
      .frame_done_toggle_o (s_frm_done_tgl),
      .error_toggle_o      (s_unused_err_tgl),
      .error_flags_o       (s_err_flags_pclk),
      .error_events_o      (s_core_err_events),
      .frame_stats_o       (s_frm_stats_pclk),
      .frame_stats_valid_o (s_frm_stats_v_pclk),
      .frame_stats_ready_i (s_frm_stats_rdy_pclk),
      .href_i              (dvp.href_i),
      .vsync_i             (dvp.vsync_i),
      .dat_i               (dvp.dat_i)
  );
endmodule
