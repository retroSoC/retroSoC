// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

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
    output logic          irq_o
    // verilog_format: on
);
  localparam int DvpPayloadWidth = 42;

  logic [              127:0] s_cfg_sys;
  logic                       s_cfg_v_sys;
  logic                       s_cfg_rdy_sys;
  logic [              127:0] s_cfg_pclk_q;
  logic                       s_cfg_v_pclk;
  logic                       s_cfg_rdy_pclk;
  logic [                1:0] s_cmd_sys;
  logic [                1:0] s_cmd_pclk;
  logic                       s_cmd_v_pclk;
  logic                       s_cmd_rdy_pclk;
  logic                       s_cmd_rdy_sys;
  logic                       s_cmd_v_sys;
  logic [                1:0] s_cmd_core;
  logic                       s_cmd_abort_sys;
  logic                       s_cmd_flush_sys;

  logic                       s_pclk_inv;
  logic                       s_pclk_buf;
  logic                       s_pclk_rst_n;
  logic                       s_pclk_sel;
  logic                       s_pclk_falling;
  logic                       s_active;
  logic                       s_stream_en;
  logic                       s_fifo_src_ready;
  logic                       s_fifo_dst_valid;
  logic [DvpPayloadWidth-1:0] s_fifo_dst_data;
  logic                       s_fifo_dst_ready;
  logic                       s_fifo_src_clear;
  logic                       s_fifo_src_clear_busy;
  logic                       s_fifo_dst_clear_busy;
  logic [DvpPayloadWidth-1:0] s_core_push_data;
  logic                       s_core_push_valid;
  logic [               31:0] s_fifo_rx_data;
  logic                       s_rx_pop;
  logic                       s_fifo_full_sys;
  logic                       s_fifo_empty_sys;
  logic                       s_frm_start_tgl;
  logic                       s_line_done_tgl;
  logic                       s_frm_done_tgl;
  logic                       s_err_tgl;
  logic                       s_frame_start_event;
  logic                       s_line_done_event;
  logic                       s_frame_done_event;
  logic                       s_err_evt;
  logic [                5:0] s_err_flags_pclk;
  logic [                5:0] s_err_flags_sys;
  logic [              127:0] s_frm_stats_pclk;
  logic                       s_frm_stats_v_pclk;
  logic                       s_frm_stats_rdy_pclk;
  logic [              127:0] s_frm_stats_sys;
  logic                       s_frm_stats_v_sys;

  assign s_cmd_sys = {s_cmd_flush_sys, s_cmd_abort_sys};
  // Commands are consumed in the pixel domain as soon as they cross the CDC.
  assign s_cmd_rdy_pclk = !s_fifo_src_clear_busy;
  assign s_pclk_falling = s_cfg_sys[106];
  assign s_fifo_src_clear = s_cmd_pclk[`APB4_DVP__COMMAND_FLUSH] ||
                            s_cmd_pclk[`APB4_DVP__COMMAND_ABORT];
  assign s_fifo_dst_ready = !s_fifo_dst_clear_busy && (s_stream_en ? rx_axis.tready : s_rx_pop);
  assign s_fifo_rx_data = s_fifo_dst_data[31:0];
  assign s_fifo_empty_sys = !s_fifo_dst_valid;

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
      .fifo_empty_i       (s_fifo_empty_sys),
      .fifo_full_i        (s_fifo_full_sys),
      .rx_data_i          (s_fifo_rx_data),
      .frame_start_i      (s_frame_start_event),
      .line_done_i        (s_line_done_event),
      .frame_done_i       (s_frame_done_event),
      .error_event_i      (s_err_evt),
      .error_flags_i      (s_err_flags_sys),
      .frame_stats_i      (s_frm_stats_sys),
      .frame_stats_valid_i(s_frm_stats_v_sys),
      .cfg_o              (s_cfg_sys),
      .cfg_valid_o        (s_cfg_v_sys),
      .cfg_ready_i        (s_cfg_rdy_sys),
      .cmd_abort_o        (s_cmd_abort_sys),
      .cmd_flush_o        (s_cmd_flush_sys),
      .cmd_valid_o        (s_cmd_v_sys),
      .cmd_ready_i        (s_cmd_rdy_sys),
      .rx_pop_o           (s_rx_pop),
      .stream_enable_o    (s_stream_en),
      .irq_o              (irq_o)
  );

  cdc_2phase #(
      .DATA_WIDTH(128)
  ) u_dvp_config_cdc (
      .src_clk_i  (clk_i),
      .src_rst_n_i(rst_n_i),
      .src_data_i (s_cfg_sys),
      .src_valid_i(s_cfg_v_sys),
      .src_ready_o(s_cfg_rdy_sys),
      .dst_clk_i  (s_pclk_sel),
      .dst_rst_n_i(s_pclk_rst_n),
      .dst_data_o (s_cfg_pclk_q),
      .dst_valid_o(s_cfg_v_pclk),
      .dst_ready_i(s_cfg_rdy_pclk)
  );

  cdc_2phase #(
      .DATA_WIDTH(2)
  ) u_dvp_command_cdc (
      .src_clk_i  (clk_i),
      .src_rst_n_i(rst_n_i),
      .src_data_i (s_cmd_sys),
      .src_valid_i(s_cmd_v_sys),
      .src_ready_o(s_cmd_rdy_sys),
      .dst_clk_i  (s_pclk_sel),
      .dst_rst_n_i(s_pclk_rst_n),
      .dst_data_o (s_cmd_pclk),
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
  assign s_cmd_core = s_cmd_v_pclk ? s_cmd_pclk : 2'b00;

  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_fifo_full_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (!s_fifo_src_ready),
      .dat_o  (s_fifo_full_sys)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(6)
  ) u_error_flags_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_flags_pclk),
      .dat_o  (s_err_flags_sys)
  );

  /* verilator lint_off PINCONNECTEMPTY */
  edge_det #(
      .STAGE(2)
  ) u_frame_start_event (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .dat_i(s_frm_start_tgl),
      .dat_o(),  // Synchronized level is intentionally unused; only the rising edge is consumed.
      .re_o(s_frame_start_event),
      .fe_o()  // Falling edge is intentionally unused.
  );
  edge_det #(
      .STAGE(2)
  ) u_line_done_event (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .dat_i(s_line_done_tgl),
      .dat_o(),  // Synchronized level is intentionally unused; only the rising edge is consumed.
      .re_o(s_line_done_event),
      .fe_o()  // Falling edge is intentionally unused.
  );
  edge_det #(
      .STAGE(2)
  ) u_frame_done_event (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .dat_i(s_frm_done_tgl),
      .dat_o(),  // Synchronized level is intentionally unused; only the rising edge is consumed.
      .re_o(s_frame_done_event),
      .fe_o()  // Falling edge is intentionally unused.
  );
  edge_det #(
      .STAGE(2)
  ) u_error_event (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .dat_i(s_err_tgl),
      .dat_o(),  // Synchronized level is intentionally unused; only the rising edge is consumed.
      .re_o(s_err_evt),
      .fe_o()  // Falling edge is intentionally unused.
  );
  /* verilator lint_on PINCONNECTEMPTY */

  cdc_2phase #(
      .DATA_WIDTH(128)
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

  assign rx_axis.tdata  = s_fifo_dst_data[31:0];
  assign rx_axis.tkeep  = s_fifo_dst_data[39:36];
  assign rx_axis.tstrb  = s_fifo_dst_data[35:32];
  assign rx_axis.tlast  = s_fifo_dst_data[40];
  assign rx_axis.tid    = '0;
  assign rx_axis.tdest  = '0;
  assign rx_axis.tuser  = s_fifo_dst_data[41];
  assign rx_axis.tvalid = s_stream_en && s_fifo_dst_valid;

  dvp_core u_dvp_core (
      .clk_i               (s_pclk_sel),
      .rst_n_i             (s_pclk_rst_n),
      .cfg_i               (s_cfg_pclk_q),
      .cfg_valid_i         (s_cfg_v_pclk),
      .cmd_i               (s_cmd_core),
      .cfg_ready_o         (s_cfg_rdy_pclk),
      .push_ready_i        (s_fifo_src_ready),
      .push_valid_o        (s_core_push_valid),
      .push_data_o         (s_core_push_data),
      .active_o            (s_active),
      .frame_start_toggle_o(s_frm_start_tgl),
      .line_done_toggle_o  (s_line_done_tgl),
      .frame_done_toggle_o (s_frm_done_tgl),
      .error_toggle_o      (s_err_tgl),
      .error_flags_o       (s_err_flags_pclk),
      .frame_stats_o       (s_frm_stats_pclk),
      .frame_stats_valid_o (s_frm_stats_v_pclk),
      .frame_stats_ready_i (s_frm_stats_rdy_pclk),
      .href_i              (dvp.href_i),
      .vsync_i             (dvp.vsync_i),
      .dat_i               (dvp.dat_i)
  );
endmodule
