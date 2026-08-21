// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module apb4_opipsram (
    // verilog_format: off -- preserve reviewed port order and alignment
    input logic         clk_i,
    input logic         rst_n_i,
    input logic         clk_phy_i,
    input logic         rst_phy_n_i,
    apb4_if.slave       cfg_apb4,
    axi4_if.slave        mem_axi4,
    opipsram_if.dut     psram
    // verilog_format: on
);

  import opipsram_pkg::*;

  logic                   s_ctrl_en;
  logic                   s_mem_en;
  logic                   s_auto_init;
  logic                   s_line_buffer;
  logic                   s_protocol_hyper;
  logic            [31:0] s_device_size;
  logic            [31:0] s_opi_read_cmd;
  logic            [31:0] s_opi_write_cmd;
  logic            [31:0] s_opi_reg_read_cmd;
  logic            [31:0] s_opi_reg_write_cmd;
  logic            [31:0] s_opi_timing;
  logic            [31:0] s_hyper_timing;
  logic            [31:0] s_clk_config;
  logic            [31:0] s_cs_timing;
  logic            [31:0] s_powerup_cycles;
  logic            [31:0] s_timeout_cycles;
  logic            [ 7:0] s_rx_delay;

  logic                   s_init;
  logic                   s_abort;
  logic                   s_soft_reset;
  logic                   s_train;
  logic                   s_indirect_start;
  logic                   s_indirect_write;
  logic                   s_indirect_register;
  logic            [ 3:0] s_indirect_len;
  logic            [31:0] s_indirect_addr;
  logic            [63:0] s_indirect_wdata;
  logic            [63:0] s_indirect_rdata;

  logic                   s_core_busy;
  logic                   s_axi_busy;
  logic                   s_initialized;
  logic                   s_ready;
  logic                   s_trained;
  logic                   s_err;
  logic                   s_profile_lock;
  logic                   s_profile_hyper;
  logic                   s_quiesced;
  logic            [31:0] s_profile_stat;
  logic            [31:0] s_train_stat;
  logic            [31:0] s_train_window;
  opipsram_error_e        s_last_err;
  logic            [31:0] s_last_err_addr;

  logic                   s_init_done_event;
  logic                   s_indirect_done_event;
  logic                   s_train_done_event;
  logic                   s_err_evt;
  logic                   s_timeout_evt;
  logic            [ 3:0] s_perf_read_bytes_event;
  logic            [ 3:0] s_perf_write_bytes_event;
  logic                   s_cmd_event;
  logic                   s_perf_cache_hit_event;
  logic                   s_perf_stall_event;
  logic                   s_perf_err_event;
  logic                   s_core_perf_err_event;

  logic                   s_mem_req_valid;
  logic                   s_mem_req_ready;
  logic                   s_mem_req_write;
  logic            [31:0] s_mem_req_addr;
  logic            [ 3:0] s_mem_req_len;
  logic            [31:0] s_mem_req_wdata;
  logic            [ 3:0] s_mem_req_wstrb;
  logic                   s_mem_rsp_valid;
  logic                   s_mem_rsp_ready;
  logic                   s_mem_rsp_err;
  logic            [31:0] s_mem_rsp_rdata;

  logic                   s_phy_req_valid;
  logic                   s_phy_req_ready;
  logic                   s_phy_req_profile_hyper;
  logic                   s_phy_req_write;
  logic                   s_phy_req_indirect_register;
  logic            [31:0] s_phy_req_addr;
  logic            [ 3:0] s_phy_req_len;
  logic            [63:0] s_phy_req_wdata;
  logic            [15:0] s_phy_req_opi_cmd;
  logic                   s_phy_req_opi_width16;
  logic            [31:0] s_phy_req_opi_timing;
  logic            [31:0] s_phy_req_hyper_timing;
  logic            [31:0] s_phy_req_cs_timing;
  logic            [31:0] s_phy_req_clk_config;
  logic            [ 7:0] s_phy_req_rx_delay;
  logic            [31:0] s_phy_req_timeout;
  logic                   s_phy_abort_valid;
  logic                   s_phy_abort_ready;
  logic                   s_phy_rsp_ready;

  opipsram_cmd_t          s_cmd_sys;
  opipsram_cmd_t          s_cmd_phy;
  opipsram_rsp_t          s_rsp_phy;
  opipsram_rsp_t          s_rsp_sys;
  logic                   s_cmd_phy_valid;
  logic                   s_cmd_phy_ready;
  logic                   s_rsp_phy_valid;
  logic                   s_rsp_phy_ready;
  logic                   s_rsp_sys_valid;
  logic                   s_abort_phy_valid;
  logic                   unused_core_init_busy;
  logic                   unused_core_indirect_busy;
  logic            [ 3:0] unused_core_read_bytes;
  logic            [ 3:0] unused_core_write_bytes;
  logic                   unused_abort_data;

  opipsram_reg u_opipsram_reg (
      .clk_i                   (clk_i),
      .rst_n_i                 (rst_n_i),
      .apb4                    (cfg_apb4),
      .busy_i                  (s_core_busy || s_axi_busy),
      .initialized_i           (s_initialized),
      .ready_i                 (s_ready),
      .quiesced_i              (s_quiesced),
      .trained_i               (s_trained),
      .error_i                 (s_err),
      .profile_lock_i          (s_profile_lock),
      .profile_hyper_i         (s_profile_hyper),
      .profile_status_i        (s_profile_stat),
      .train_status_i          (s_train_stat),
      .train_window_i          (s_train_window),
      .last_error_i            (s_last_err),
      .last_error_addr_i       (s_last_err_addr),
      .init_done_event_i       (s_init_done_event),
      .indirect_done_event_i   (s_indirect_done_event),
      .train_done_event_i      (s_train_done_event),
      .error_event_i           (s_err_evt || s_perf_err_event || s_core_perf_err_event),
      .timeout_event_i         (s_timeout_evt),
      .perf_read_bytes_event_i (s_perf_read_bytes_event),
      .perf_write_bytes_event_i(s_perf_write_bytes_event),
      .perf_command_event_i    (s_cmd_event),
      .perf_cache_hit_event_i  (s_perf_cache_hit_event),
      .perf_stall_event_i      (s_perf_stall_event),
      .perf_error_event_i      (s_perf_err_event || s_core_perf_err_event),
      .indirect_rdata_i        (s_indirect_rdata),
      .controller_enable_o     (s_ctrl_en),
      .memory_enable_o         (s_mem_en),
      .auto_init_o             (s_auto_init),
      .line_buffer_o           (s_line_buffer),
      .protocol_hyper_o        (s_protocol_hyper),
      .device_size_o           (s_device_size),
      .opi_read_cmd_o          (s_opi_read_cmd),
      .opi_write_cmd_o         (s_opi_write_cmd),
      .opi_reg_read_cmd_o      (s_opi_reg_read_cmd),
      .opi_reg_write_cmd_o     (s_opi_reg_write_cmd),
      .opi_timing_o            (s_opi_timing),
      .hyper_timing_o          (s_hyper_timing),
      .clk_config_o            (s_clk_config),
      .cs_timing_o             (s_cs_timing),
      .powerup_cycles_o        (s_powerup_cycles),
      .timeout_cycles_o        (s_timeout_cycles),
      .rx_delay_o              (s_rx_delay),
      .init_o                  (s_init),
      .abort_o                 (s_abort),
      .soft_reset_o            (s_soft_reset),
      .train_o                 (s_train),
      .indirect_start_o        (s_indirect_start),
      .indirect_write_o        (s_indirect_write),
      .indirect_register_o     (s_indirect_register),
      .indirect_length_o       (s_indirect_len),
      .indirect_addr_o         (s_indirect_addr),
      .indirect_wdata_o        (s_indirect_wdata),
      .irq_o                   (psram.irq_o)
  );

  opipsram_axi4 u_opipsram_axi4 (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .accept_enable_i    (!s_quiesced && !s_indirect_start),
      .device_size_i      (s_device_size),
      .memory_available_i (s_ready),
      .axi4               (mem_axi4),
      .core_req_valid_o   (s_mem_req_valid),
      .core_req_ready_i   (s_mem_req_ready),
      .core_req_write_o   (s_mem_req_write),
      .core_req_addr_o    (s_mem_req_addr),
      .core_req_len_o     (s_mem_req_len),
      .core_req_wdata_o   (s_mem_req_wdata),
      .core_req_wstrb_o   (s_mem_req_wstrb),
      .core_rsp_valid_i   (s_mem_rsp_valid),
      .core_rsp_ready_o   (s_mem_rsp_ready),
      .core_rsp_error_i   (s_mem_rsp_err),
      .core_rsp_rdata_i   (s_mem_rsp_rdata),
      .busy_o             (s_axi_busy),
      .stall_event_o      (s_perf_stall_event),
      .read_bytes_event_o (s_perf_read_bytes_event),
      .write_bytes_event_o(s_perf_write_bytes_event),
      .error_event_o      (s_perf_err_event)
  );

  opipsram_core u_opipsram_core (
      .clk_i                      (clk_i),
      .rst_n_i                    (rst_n_i),
      .controller_enable_i        (s_ctrl_en),
      .memory_enable_i            (s_mem_en),
      .auto_init_i                (s_auto_init),
      .line_buffer_i              (s_line_buffer),
      .protocol_hyper_i           (s_protocol_hyper),
      .device_size_i              (s_device_size),
      .powerup_cycles_i           (s_powerup_cycles),
      .timeout_cycles_i           (s_timeout_cycles),
      .opi_read_cmd_i             (s_opi_read_cmd),
      .opi_write_cmd_i            (s_opi_write_cmd),
      .opi_reg_read_cmd_i         (s_opi_reg_read_cmd),
      .opi_reg_write_cmd_i        (s_opi_reg_write_cmd),
      .opi_timing_i               (s_opi_timing),
      .hyper_timing_i             (s_hyper_timing),
      .cs_timing_i                (s_cs_timing),
      .clk_config_i               (s_clk_config),
      .rx_delay_i                 (s_rx_delay),
      .init_i                     (s_init),
      .abort_i                    (s_abort),
      .soft_reset_i               (s_soft_reset),
      .train_i                    (s_train),
      .indirect_start_i           (s_indirect_start),
      .indirect_write_i           (s_indirect_write),
      .indirect_register_i        (s_indirect_register),
      .indirect_length_i          (s_indirect_len),
      .indirect_addr_i            (s_indirect_addr),
      .indirect_wdata_i           (s_indirect_wdata),
      .axi_busy_i                 (s_axi_busy),
      .mem_req_valid_i            (s_mem_req_valid),
      .mem_req_ready_o            (s_mem_req_ready),
      .mem_req_write_i            (s_mem_req_write),
      .mem_req_addr_i             (s_mem_req_addr),
      .mem_req_len_i              (s_mem_req_len),
      .mem_req_wdata_i            (s_mem_req_wdata),
      .mem_req_wstrb_i            (s_mem_req_wstrb),
      .mem_rsp_valid_o            (s_mem_rsp_valid),
      .mem_rsp_ready_i            (s_mem_rsp_ready),
      .mem_rsp_error_o            (s_mem_rsp_err),
      .mem_rsp_rdata_o            (s_mem_rsp_rdata),
      .phy_req_valid_o            (s_phy_req_valid),
      .phy_req_ready_i            (s_phy_req_ready),
      .phy_req_profile_hyper_o    (s_phy_req_profile_hyper),
      .phy_req_write_o            (s_phy_req_write),
      .phy_req_indirect_register_o(s_phy_req_indirect_register),
      .phy_req_addr_o             (s_phy_req_addr),
      .phy_req_len_o              (s_phy_req_len),
      .phy_req_wdata_o            (s_phy_req_wdata),
      .phy_req_opi_cmd_o          (s_phy_req_opi_cmd),
      .phy_req_opi_width16_o      (s_phy_req_opi_width16),
      .phy_req_opi_timing_o       (s_phy_req_opi_timing),
      .phy_req_hyper_timing_o     (s_phy_req_hyper_timing),
      .phy_req_cs_timing_o        (s_phy_req_cs_timing),
      .phy_req_clk_config_o       (s_phy_req_clk_config),
      .phy_req_rx_delay_o         (s_phy_req_rx_delay),
      .phy_req_timeout_o          (s_phy_req_timeout),
      .phy_rsp_valid_i            (s_rsp_sys_valid),
      .phy_rsp_ready_o            (s_phy_rsp_ready),
      .phy_rsp_error_i            (s_rsp_sys.error),
      .phy_rsp_rdata_i            (s_rsp_sys.rdata),
      .phy_abort_valid_o          (s_phy_abort_valid),
      .phy_abort_ready_i          (s_phy_abort_ready),
      .busy_o                     (s_core_busy),
      .init_busy_o                (unused_core_init_busy),
      .indirect_busy_o            (unused_core_indirect_busy),
      .quiesced_o                 (s_quiesced),
      .initialized_o              (s_initialized),
      .ready_o                    (s_ready),
      .trained_o                  (s_trained),
      .error_o                    (s_err),
      .profile_lock_o             (s_profile_lock),
      .profile_hyper_o            (s_profile_hyper),
      .profile_status_o           (s_profile_stat),
      .train_status_o             (s_train_stat),
      .train_window_o             (s_train_window),
      .last_error_o               (s_last_err),
      .last_error_addr_o          (s_last_err_addr),
      .indirect_rdata_o           (s_indirect_rdata),
      .init_done_event_o          (s_init_done_event),
      .indirect_done_event_o      (s_indirect_done_event),
      .train_done_event_o         (s_train_done_event),
      .error_event_o              (s_err_evt),
      .timeout_event_o            (s_timeout_evt),
      .perf_read_bytes_event_o    (unused_core_read_bytes),
      .perf_write_bytes_event_o   (unused_core_write_bytes),
      .perf_command_event_o       (s_cmd_event),
      .perf_cache_hit_event_o     (s_perf_cache_hit_event),
      .perf_error_event_o         (s_core_perf_err_event)
  );

  always_comb begin
    s_cmd_sys                   = '0;
    s_cmd_sys.profile_hyper     = s_phy_req_profile_hyper;
    s_cmd_sys.write             = s_phy_req_write;
    s_cmd_sys.indirect_register = s_phy_req_indirect_register;
    s_cmd_sys.addr              = s_phy_req_addr;
    s_cmd_sys.len               = s_phy_req_len;
    s_cmd_sys.wdata             = s_phy_req_wdata;
    s_cmd_sys.opi_cmd           = s_phy_req_opi_cmd;
    s_cmd_sys.opi_width16       = s_phy_req_opi_width16;
    s_cmd_sys.opi_timing        = s_phy_req_opi_timing;
    s_cmd_sys.hyper_timing      = s_phy_req_hyper_timing;
    s_cmd_sys.cs_timing         = s_phy_req_cs_timing;
    s_cmd_sys.clk_config        = s_phy_req_clk_config;
    s_cmd_sys.rx_delay          = s_phy_req_rx_delay;
    s_cmd_sys.timeout           = s_phy_req_timeout;
  end

  cdc_2phase #(
      .DATA_WIDTH(OPIPSRAM_CMD_WIDTH)
  ) u_command_cdc (
      .src_clk_i  (clk_i),
      .src_rst_n_i(rst_n_i),
      .src_data_i (s_cmd_sys),
      .src_valid_i(s_phy_req_valid),
      .src_ready_o(s_phy_req_ready),
      .dst_clk_i  (clk_phy_i),
      .dst_rst_n_i(rst_phy_n_i),
      .dst_data_o (s_cmd_phy),
      .dst_valid_o(s_cmd_phy_valid),
      .dst_ready_i(s_cmd_phy_ready)
  );

  opipsram_phy u_opipsram_phy (
      .clk_phy_i              (clk_phy_i),
      .rst_phy_n_i            (rst_phy_n_i),
      .cmd_valid_i            (s_cmd_phy_valid),
      .cmd_ready_o            (s_cmd_phy_ready),
      .cmd_profile_hyper_i    (s_cmd_phy.profile_hyper),
      .cmd_write_i            (s_cmd_phy.write),
      .cmd_indirect_register_i(s_cmd_phy.indirect_register),
      .cmd_addr_i             (s_cmd_phy.addr),
      .cmd_len_i              (s_cmd_phy.len),
      .cmd_wdata_i            (s_cmd_phy.wdata),
      .cmd_opi_cmd_i          (s_cmd_phy.opi_cmd),
      .cmd_opi_width16_i      (s_cmd_phy.opi_width16),
      .cmd_opi_timing_i       (s_cmd_phy.opi_timing),
      .cmd_hyper_timing_i     (s_cmd_phy.hyper_timing),
      .cmd_cs_timing_i        (s_cmd_phy.cs_timing),
      .cmd_clk_config_i       (s_cmd_phy.clk_config),
      .cmd_rx_delay_i         (s_cmd_phy.rx_delay),
      .cmd_timeout_i          (s_cmd_phy.timeout),
      .abort_i                (s_abort_phy_valid),
      .rsp_valid_o            (s_rsp_phy_valid),
      .rsp_ready_i            (s_rsp_phy_ready),
      .rsp_error_o            (s_rsp_phy.error),
      .rsp_rdata_o            (s_rsp_phy.rdata),
      .ck_o                   (psram.ck_o),
      .cs_n_o                 (psram.cs_n_o),
      .dq_oe_o                (psram.dq_oe_o),
      .dq_i                   (psram.dq_i),
      .dq_o                   (psram.dq_o),
      .rwds_oe_o              (psram.rwds_oe_o),
      .rwds_i                 (psram.rwds_i),
      .rwds_o                 (psram.rwds_o)
  );

  cdc_2phase #(
      .DATA_WIDTH(OPIPSRAM_RSP_WIDTH)
  ) u_response_cdc (
      .src_clk_i  (clk_phy_i),
      .src_rst_n_i(rst_phy_n_i),
      .src_data_i (s_rsp_phy),
      .src_valid_i(s_rsp_phy_valid),
      .src_ready_o(s_rsp_phy_ready),
      .dst_clk_i  (clk_i),
      .dst_rst_n_i(rst_n_i),
      .dst_data_o (s_rsp_sys),
      .dst_valid_o(s_rsp_sys_valid),
      .dst_ready_i(s_phy_rsp_ready)
  );

  cdc_2phase #(
      .DATA_WIDTH(1)
  ) u_abort_cdc (
      .src_clk_i  (clk_i),
      .src_rst_n_i(rst_n_i),
      .src_data_i (1'b1),
      .src_valid_i(s_phy_abort_valid),
      .src_ready_o(s_phy_abort_ready),
      .dst_clk_i  (clk_phy_i),
      .dst_rst_n_i(rst_phy_n_i),
      .dst_data_o (unused_abort_data),
      .dst_valid_o(s_abort_phy_valid),
      .dst_ready_i(1'b1)
  );

endmodule
