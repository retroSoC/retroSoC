// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module opipsram_formal_design (
    // verilog_format: off -- formal observations are grouped by protocol layer.
    input  logic        clk_i,
    output logic        rst_n_i,
    output logic        f_past_valid,

    output logic        awvalid,
    output logic        awready,
    output logic        awid,
    output logic [31:0] awaddr,
    output logic [7:0]  awlen,
    output logic [2:0]  awsize,
    output logic [1:0]  awburst,
    output logic        awlock,
    output logic [3:0]  awcache,
    output logic [2:0]  awprot,
    output logic [3:0]  awqos,
    output logic [3:0]  awregion,
    output logic        awuser,
    output logic        wvalid,
    output logic        wready,
    output logic [31:0] wdata,
    output logic [3:0]  wstrb,
    output logic        wlast,
    output logic        wuser,
    output logic        bvalid,
    output logic        bready,
    output logic        bid,
    output logic [1:0]  bresp,
    output logic        buser,
    output logic        arvalid,
    output logic        arready,
    output logic        arid,
    output logic [31:0] araddr,
    output logic [7:0]  arlen,
    output logic [2:0]  arsize,
    output logic [1:0]  arburst,
    output logic        arlock,
    output logic [3:0]  arcache,
    output logic [2:0]  arprot,
    output logic [3:0]  arqos,
    output logic [3:0]  arregion,
    output logic        aruser,
    output logic        rvalid,
    output logic        rready,
    output logic        rid,
    output logic [31:0] rdata,
    output logic [1:0]  rresp,
    output logic        rlast,
    output logic        ruser,

    output logic        apb_psel,
    output logic        apb_penable,
    output logic        apb_pwrite,
    output logic [31:0] apb_paddr,
    output logic [31:0] apb_pwdata,
    output logic [3:0]  apb_pstrb,
    output logic [2:0]  apb_pprot,
    output logic        apb_pready,
    output logic [31:0] apb_prdata,
    output logic        apb_pslverr,

    output logic        core_mem_req_valid,
    output logic        core_mem_req_ready,
    output logic        core_mem_req_write,
    output logic [31:0] core_mem_req_addr,
    output logic [3:0]  core_mem_req_len,
    output logic [31:0] core_mem_req_wdata,
    output logic [3:0]  core_mem_req_wstrb,
    output logic        core_mem_rsp_valid,
    output logic        core_mem_rsp_ready,
    output logic        core_mem_rsp_error,
    output logic [31:0] core_mem_rsp_rdata,
    output logic        core_phy_req_valid,
    output logic        core_phy_req_ready,
    output logic        core_phy_req_profile_hyper,
    output logic        core_phy_req_write,
    output logic        core_phy_req_indirect_register,
    output logic [31:0] core_phy_req_addr,
    output logic [3:0]  core_phy_req_len,
    output logic [63:0] core_phy_req_wdata,
    output logic [15:0] core_phy_req_opi_cmd,
    output logic        core_phy_req_opi_width16,
    output logic [31:0] core_phy_req_opi_timing,
    output logic [31:0] core_phy_req_hyper_timing,
    output logic [31:0] core_phy_req_cs_timing,
    output logic [31:0] core_phy_req_clk_config,
    output logic [7:0]  core_phy_req_rx_delay,
    output logic [31:0] core_phy_req_timeout,
    output logic        core_phy_rsp_valid,
    output logic        core_phy_rsp_ready,
    output logic        core_phy_rsp_error,
    output logic [63:0] core_phy_rsp_rdata,
    output logic        core_abort_valid,
    output logic        core_abort_ready,
    output logic        core_busy,
    output logic        core_io_active,
    output logic        core_quiesced,
    output logic        core_initialized,
    output logic        core_ready,
    output logic        core_trained,
    output logic        core_error,
    output logic        core_profile_lock,
    output logic        core_profile_hyper,
    output logic [31:0] core_last_error_addr,
    output logic        core_init_done_event,
    output logic        core_indirect_done_event,
    output logic        core_train_done_event,
    output logic        core_error_event,
    output logic        core_timeout_event,

    output logic        controller_enable,
    output logic        memory_enable,
    output logic        auto_init,
    output logic        line_buffer,
    output logic        protocol_hyper,
    output logic [31:0] device_size,
    output logic [31:0] opi_read_cmd,
    output logic [31:0] opi_write_cmd,
    output logic [31:0] opi_reg_read_cmd,
    output logic [31:0] opi_reg_write_cmd,
    output logic [31:0] opi_timing,
    output logic [31:0] hyper_timing,
    output logic [31:0] clk_config,
    output logic [31:0] cs_timing,
    output logic [31:0] powerup_cycles,
    output logic [31:0] timeout_cycles,
    output logic [7:0]  rx_delay,
    output logic        init_cmd,
    output logic        abort_cmd,
    output logic        soft_reset_cmd,
    output logic        train_cmd,
    output logic        indirect_start_cmd,
    output logic        indirect_write_cmd,
    output logic        indirect_register_cmd,
    output logic        reg_irq,
    output logic [4:0]  reg_intr_state,
    output logic [4:0]  reg_intr_enable,
    output logic [4:0]  reg_event_bits,
    output logic [4:0]  reg_intr_next,
    output logic        reg_busy,

    output logic        phy_cmd_valid,
    output logic        phy_cmd_ready,
    output logic        phy_cmd_profile_hyper,
    output logic        phy_cmd_write,
    output logic        phy_cmd_indirect_register,
    output logic [3:0]  phy_cmd_len,
    output logic [31:0] phy_cmd_clk_config,
    output logic        phy_abort,
    output logic        phy_rsp_valid,
    output logic        phy_rsp_ready,
    output logic        phy_rsp_error,
    output logic [63:0] phy_rsp_rdata,
    output logic        phy_ck,
    output logic        phy_cs_n,
    output logic [7:0]  phy_dq_oe,
    output logic        phy_rwds_oe
    // verilog_format: on
);

  import opipsram_pkg::*;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  apb4_if cfg_apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );

  (* anyseq *)logic                   f_awvalid;
  (* anyseq *)logic                   f_awid;
  (* anyseq *)logic            [31:0] f_awaddr;
  (* anyseq *)logic            [ 7:0] f_awlen;
  (* anyseq *)logic            [ 2:0] f_awsize;
  (* anyseq *)logic            [ 1:0] f_awburst;
  (* anyseq *)logic                   f_awlock;
  (* anyseq *)logic            [ 3:0] f_awcache;
  (* anyseq *)logic            [ 2:0] f_awprot;
  (* anyseq *)logic            [ 3:0] f_awqos;
  (* anyseq *)logic            [ 3:0] f_awregion;
  (* anyseq *)logic                   f_awuser;
  (* anyseq *)logic                   f_wvalid;
  (* anyseq *)logic            [31:0] f_wdata;
  (* anyseq *)logic            [ 3:0] f_wstrb;
  (* anyseq *)logic                   f_wlast;
  (* anyseq *)logic                   f_wuser;
  (* anyseq *)logic                   f_bready;
  (* anyseq *)logic                   f_arvalid;
  (* anyseq *)logic                   f_arid;
  (* anyseq *)logic            [31:0] f_araddr;
  (* anyseq *)logic            [ 7:0] f_arlen;
  (* anyseq *)logic            [ 2:0] f_arsize;
  (* anyseq *)logic            [ 1:0] f_arburst;
  (* anyseq *)logic                   f_arlock;
  (* anyseq *)logic            [ 3:0] f_arcache;
  (* anyseq *)logic            [ 2:0] f_arprot;
  (* anyseq *)logic            [ 3:0] f_arqos;
  (* anyseq *)logic            [ 3:0] f_arregion;
  (* anyseq *)logic                   f_aruser;
  (* anyseq *)logic                   f_rready;

  (* anyseq *)logic                   f_psel;
  (* anyseq *)logic                   f_penable;
  (* anyseq *)logic                   f_pwrite;
  (* anyseq *)logic            [31:0] f_paddr;
  (* anyseq *)logic            [31:0] f_pwdata;
  (* anyseq *)logic            [ 3:0] f_pstrb;
  (* anyseq *)logic            [ 2:0] f_pprot;

  (* anyseq *)logic                   f_phy_req_ready;
  (* anyseq *)logic                   f_phy_rsp_valid;
  (* anyseq *)logic                   f_phy_rsp_error;
  (* anyseq *)logic            [63:0] f_phy_rsp_rdata;
  (* anyseq *)logic                   f_phy_abort_ready;

  (* anyseq *)logic                   f_phy_cmd_valid;
  (* anyseq *)logic                   f_phy_cmd_profile_hyper;
  (* anyseq *)logic                   f_phy_cmd_write;
  (* anyseq *)logic                   f_phy_cmd_indirect_register;
  (* anyseq *)logic            [31:0] f_phy_cmd_addr;
  (* anyseq *)logic            [ 3:0] f_phy_cmd_len;
  (* anyseq *)logic            [63:0] f_phy_cmd_wdata;
  (* anyseq *)logic            [15:0] f_phy_cmd_opi_cmd;
  (* anyseq *)logic                   f_phy_cmd_opi_width16;
  (* anyseq *)logic            [31:0] f_phy_cmd_opi_timing;
  (* anyseq *)logic            [31:0] f_phy_cmd_hyper_timing;
  (* anyseq *)logic            [31:0] f_phy_cmd_cs_timing;
  (* anyseq *)logic            [31:0] f_phy_cmd_clk_config;
  (* anyseq *)logic            [ 7:0] f_phy_cmd_rx_delay;
  (* anyseq *)logic            [31:0] f_phy_cmd_timeout;
  (* anyseq *)logic                   f_phy_abort;
  (* anyseq *)logic                   f_phy_rsp_ready;
  (* anyseq *)logic            [ 7:0] f_phy_dq;
  (* anyseq *)logic                   f_phy_rwds;

  logic            [31:0] s_profile_status;
  logic            [31:0] s_train_status;
  logic            [31:0] s_train_window;
  logic            [ 3:0] s_indirect_length;
  logic            [31:0] s_indirect_addr;
  logic            [63:0] s_indirect_wdata;
  logic            [63:0] s_indirect_rdata;
  logic            [ 3:0] s_axi_read_bytes_event;
  logic            [ 3:0] s_axi_write_bytes_event;
  logic                   s_axi_stall_event;
  logic                   s_axi_error_event;
  logic            [ 3:0] s_core_read_bytes_event;
  logic            [ 3:0] s_core_write_bytes_event;
  logic                   s_core_command_event;
  logic                   s_core_cache_hit_event;
  logic                   s_core_perf_error_event;
  opipsram_error_e        s_core_last_error;
  logic                   s_error_event;
  logic                   s_perf_read_bytes_event;
  logic                   s_perf_write_bytes_event;
  logic                   s_perf_command_event;
  logic                   s_perf_cache_hit_event;
  logic                   s_perf_stall_event;
  logic                   s_perf_error_event;
  logic                   s_reg_irq;
  logic                   s_axi_busy;

  assign axi4.awid        = f_awid;
  assign axi4.awaddr      = f_awaddr;
  assign axi4.awlen       = f_awlen;
  assign axi4.awsize      = f_awsize;
  assign axi4.awburst     = f_awburst;
  assign axi4.awlock      = f_awlock;
  assign axi4.awcache     = f_awcache;
  assign axi4.awprot      = f_awprot;
  assign axi4.awqos       = f_awqos;
  assign axi4.awregion    = f_awregion;
  assign axi4.awuser      = f_awuser;
  assign axi4.awvalid     = f_awvalid;
  assign axi4.wdata       = f_wdata;
  assign axi4.wstrb       = f_wstrb;
  assign axi4.wlast       = f_wlast;
  assign axi4.wuser       = f_wuser;
  assign axi4.wvalid      = f_wvalid;
  assign axi4.bready      = f_bready;
  assign axi4.arid        = f_arid;
  assign axi4.araddr      = f_araddr;
  assign axi4.arlen       = f_arlen;
  assign axi4.arsize      = f_arsize;
  assign axi4.arburst     = f_arburst;
  assign axi4.arlock      = f_arlock;
  assign axi4.arcache     = f_arcache;
  assign axi4.arprot      = f_arprot;
  assign axi4.arqos       = f_arqos;
  assign axi4.arregion    = f_arregion;
  assign axi4.aruser      = f_aruser;
  assign axi4.arvalid     = f_arvalid;
  assign axi4.rready      = f_rready;

  assign cfg_apb4.psel    = f_psel;
  assign cfg_apb4.penable = f_penable;
  assign cfg_apb4.pwrite  = f_pwrite;
  assign cfg_apb4.paddr   = f_paddr;
  assign cfg_apb4.pwdata  = f_pwdata;
  assign cfg_apb4.pstrb   = f_pstrb;
  assign cfg_apb4.pprot   = f_pprot;

  assign awvalid          = axi4.awvalid;
  assign awready          = axi4.awready;
  assign awid             = axi4.awid;
  assign awaddr           = axi4.awaddr;
  assign awlen            = axi4.awlen;
  assign awsize           = axi4.awsize;
  assign awburst          = axi4.awburst;
  assign awlock           = axi4.awlock;
  assign awcache          = axi4.awcache;
  assign awprot           = axi4.awprot;
  assign awqos            = axi4.awqos;
  assign awregion         = axi4.awregion;
  assign awuser           = axi4.awuser;
  assign wvalid           = axi4.wvalid;
  assign wready           = axi4.wready;
  assign wdata            = axi4.wdata;
  assign wstrb            = axi4.wstrb;
  assign wlast            = axi4.wlast;
  assign wuser            = axi4.wuser;
  assign bvalid           = axi4.bvalid;
  assign bready           = axi4.bready;
  assign bid              = axi4.bid;
  assign bresp            = axi4.bresp;
  assign buser            = axi4.buser;
  assign arvalid          = axi4.arvalid;
  assign arready          = axi4.arready;
  assign arid             = axi4.arid;
  assign araddr           = axi4.araddr;
  assign arlen            = axi4.arlen;
  assign arsize           = axi4.arsize;
  assign arburst          = axi4.arburst;
  assign arlock           = axi4.arlock;
  assign arcache          = axi4.arcache;
  assign arprot           = axi4.arprot;
  assign arqos            = axi4.arqos;
  assign arregion         = axi4.arregion;
  assign aruser           = axi4.aruser;
  assign rvalid           = axi4.rvalid;
  assign rready           = axi4.rready;
  assign rid              = axi4.rid;
  assign rdata            = axi4.rdata;
  assign rresp            = axi4.rresp;
  assign rlast            = axi4.rlast;
  assign ruser            = axi4.ruser;

  assign apb_psel         = cfg_apb4.psel;
  assign apb_penable      = cfg_apb4.penable;
  assign apb_pwrite       = cfg_apb4.pwrite;
  assign apb_paddr        = cfg_apb4.paddr;
  assign apb_pwdata       = cfg_apb4.pwdata;
  assign apb_pstrb        = cfg_apb4.pstrb;
  assign apb_pprot        = cfg_apb4.pprot;
  assign apb_pready       = cfg_apb4.pready;
  assign apb_prdata       = cfg_apb4.prdata;
  assign apb_pslverr      = cfg_apb4.pslverr;

  opipsram_reg u_reg (
      .clk_i                   (clk_i),
      .rst_n_i                 (rst_n_i),
      .apb4                    (cfg_apb4),
      .busy_i                  (reg_busy),
      .initialized_i           (core_initialized),
      .ready_i                 (core_ready),
      .quiesced_i              (core_quiesced),
      .trained_i               (core_trained),
      .error_i                 (core_error),
      .profile_lock_i          (core_profile_lock),
      .profile_hyper_i         (core_profile_hyper),
      .profile_status_i        (s_profile_status),
      .train_status_i          (s_train_status),
      .train_window_i          (s_train_window),
      .last_error_i            (s_core_last_error),
      .last_error_addr_i       (core_last_error_addr),
      .init_done_event_i       (core_init_done_event),
      .indirect_done_event_i   (core_indirect_done_event),
      .train_done_event_i      (core_train_done_event),
      .error_event_i           (s_error_event),
      .timeout_event_i         (core_timeout_event),
      .perf_read_bytes_event_i (s_perf_read_bytes_event),
      .perf_write_bytes_event_i(s_perf_write_bytes_event),
      .perf_command_event_i    (s_perf_command_event),
      .perf_cache_hit_event_i  (s_perf_cache_hit_event),
      .perf_stall_event_i      (s_perf_stall_event),
      .perf_error_event_i      (s_perf_error_event),
      .indirect_rdata_i        (s_indirect_rdata),
      .controller_enable_o     (controller_enable),
      .memory_enable_o         (memory_enable),
      .auto_init_o             (auto_init),
      .line_buffer_o           (line_buffer),
      .protocol_hyper_o        (protocol_hyper),
      .device_size_o           (device_size),
      .opi_read_cmd_o          (opi_read_cmd),
      .opi_write_cmd_o         (opi_write_cmd),
      .opi_reg_read_cmd_o      (opi_reg_read_cmd),
      .opi_reg_write_cmd_o     (opi_reg_write_cmd),
      .opi_timing_o            (opi_timing),
      .hyper_timing_o          (hyper_timing),
      .clk_config_o            (clk_config),
      .cs_timing_o             (cs_timing),
      .powerup_cycles_o        (powerup_cycles),
      .timeout_cycles_o        (timeout_cycles),
      .rx_delay_o              (rx_delay),
      .init_o                  (init_cmd),
      .abort_o                 (abort_cmd),
      .soft_reset_o            (soft_reset_cmd),
      .train_o                 (train_cmd),
      .indirect_start_o        (indirect_start_cmd),
      .indirect_write_o        (indirect_write_cmd),
      .indirect_register_o     (indirect_register_cmd),
      .indirect_length_o       (s_indirect_length),
      .indirect_addr_o         (s_indirect_addr),
      .indirect_wdata_o        (s_indirect_wdata),
      .irq_o                   (s_reg_irq)
  );

  opipsram_axi4 u_axi4 (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .accept_enable_i    (!core_quiesced),
      .device_size_i      (device_size),
      .memory_available_i (core_ready),
      .axi4               (axi4),
      .core_req_valid_o   (core_mem_req_valid),
      .core_req_ready_i   (core_mem_req_ready),
      .core_req_write_o   (core_mem_req_write),
      .core_req_addr_o    (core_mem_req_addr),
      .core_req_len_o     (core_mem_req_len),
      .core_req_wdata_o   (core_mem_req_wdata),
      .core_req_wstrb_o   (core_mem_req_wstrb),
      .core_rsp_valid_i   (core_mem_rsp_valid),
      .core_rsp_ready_o   (core_mem_rsp_ready),
      .core_rsp_error_i   (core_mem_rsp_error),
      .core_rsp_rdata_i   (core_mem_rsp_rdata),
      .busy_o             (s_axi_busy),
      .stall_event_o      (s_axi_stall_event),
      .read_bytes_event_o (s_axi_read_bytes_event),
      .write_bytes_event_o(s_axi_write_bytes_event),
      .error_event_o      (s_axi_error_event)
  );

  opipsram_core u_core (
      .clk_i                      (clk_i),
      .rst_n_i                    (rst_n_i),
      .controller_enable_i        (controller_enable),
      .memory_enable_i            (memory_enable),
      .auto_init_i                (auto_init),
      .line_buffer_i              (line_buffer),
      .protocol_hyper_i           (protocol_hyper),
      .device_size_i              (device_size),
      .powerup_cycles_i           (powerup_cycles),
      .timeout_cycles_i           (timeout_cycles),
      .opi_read_cmd_i             (opi_read_cmd),
      .opi_write_cmd_i            (opi_write_cmd),
      .opi_reg_read_cmd_i         (opi_reg_read_cmd),
      .opi_reg_write_cmd_i        (opi_reg_write_cmd),
      .opi_timing_i               (opi_timing),
      .hyper_timing_i             (hyper_timing),
      .cs_timing_i                (cs_timing),
      .clk_config_i               (clk_config),
      .rx_delay_i                 (rx_delay),
      .init_i                     (init_cmd),
      .abort_i                    (abort_cmd),
      .soft_reset_i               (soft_reset_cmd),
      .train_i                    (train_cmd),
      .indirect_start_i           (indirect_start_cmd),
      .indirect_write_i           (u_reg.indirect_write_o),
      .indirect_register_i        (u_reg.indirect_register_o),
      .indirect_length_i          (s_indirect_length),
      .indirect_addr_i            (s_indirect_addr),
      .indirect_wdata_i           (s_indirect_wdata),
      .axi_busy_i                 (u_axi4.busy_o),
      .mem_req_valid_i            (core_mem_req_valid),
      .mem_req_ready_o            (core_mem_req_ready),
      .mem_req_write_i            (core_mem_req_write),
      .mem_req_addr_i             (core_mem_req_addr),
      .mem_req_len_i              (core_mem_req_len),
      .mem_req_wdata_i            (core_mem_req_wdata),
      .mem_req_wstrb_i            (core_mem_req_wstrb),
      .mem_rsp_valid_o            (core_mem_rsp_valid),
      .mem_rsp_ready_i            (core_mem_rsp_ready),
      .mem_rsp_error_o            (core_mem_rsp_error),
      .mem_rsp_rdata_o            (core_mem_rsp_rdata),
      .phy_req_valid_o            (core_phy_req_valid),
      .phy_req_ready_i            (core_phy_req_ready),
      .phy_req_profile_hyper_o    (core_phy_req_profile_hyper),
      .phy_req_write_o            (core_phy_req_write),
      .phy_req_indirect_register_o(core_phy_req_indirect_register),
      .phy_req_addr_o             (core_phy_req_addr),
      .phy_req_len_o              (core_phy_req_len),
      .phy_req_wdata_o            (core_phy_req_wdata),
      .phy_req_opi_cmd_o          (core_phy_req_opi_cmd),
      .phy_req_opi_width16_o      (core_phy_req_opi_width16),
      .phy_req_opi_timing_o       (core_phy_req_opi_timing),
      .phy_req_hyper_timing_o     (core_phy_req_hyper_timing),
      .phy_req_cs_timing_o        (core_phy_req_cs_timing),
      .phy_req_clk_config_o       (core_phy_req_clk_config),
      .phy_req_rx_delay_o         (core_phy_req_rx_delay),
      .phy_req_timeout_o          (core_phy_req_timeout),
      .phy_rsp_valid_i            (core_phy_rsp_valid),
      .phy_rsp_ready_o            (core_phy_rsp_ready),
      .phy_rsp_error_i            (core_phy_rsp_error),
      .phy_rsp_rdata_i            (core_phy_rsp_rdata),
      .phy_abort_valid_o          (core_abort_valid),
      .phy_abort_ready_i          (core_abort_ready),
      .busy_o                     (core_busy),
      .init_busy_o                (),
      .indirect_busy_o            (),
      .quiesced_o                 (core_quiesced),
      .initialized_o              (core_initialized),
      .ready_o                    (core_ready),
      .trained_o                  (core_trained),
      .error_o                    (core_error),
      .profile_lock_o             (core_profile_lock),
      .profile_hyper_o            (core_profile_hyper),
      .profile_status_o           (s_profile_status),
      .train_status_o             (s_train_status),
      .train_window_o             (s_train_window),
      .last_error_o               (s_core_last_error),
      .last_error_addr_o          (core_last_error_addr),
      .indirect_rdata_o           (s_indirect_rdata),
      .init_done_event_o          (core_init_done_event),
      .indirect_done_event_o      (core_indirect_done_event),
      .train_done_event_o         (core_train_done_event),
      .error_event_o              (core_error_event),
      .timeout_event_o            (core_timeout_event),
      .perf_read_bytes_event_o    (s_core_read_bytes_event),
      .perf_write_bytes_event_o   (s_core_write_bytes_event),
      .perf_command_event_o       (s_core_command_event),
      .perf_cache_hit_event_o     (s_core_cache_hit_event),
      .perf_error_event_o         (s_core_perf_error_event)
  );

  assign s_perf_read_bytes_event = s_axi_read_bytes_event | s_core_read_bytes_event;
  assign s_perf_write_bytes_event = s_axi_write_bytes_event | s_core_write_bytes_event;
  assign s_perf_command_event = s_core_command_event;
  assign s_perf_cache_hit_event = s_core_cache_hit_event;
  assign s_perf_stall_event = s_axi_stall_event;
  assign s_error_event = s_axi_error_event | core_error_event | s_core_perf_error_event;
  assign s_perf_error_event = s_axi_error_event | s_core_perf_error_event;

  assign reg_busy = core_busy || s_axi_busy;
  assign reg_irq = s_reg_irq;
  assign reg_intr_state = u_reg.s_intr_state_q;
  assign reg_intr_enable = u_reg.s_intr_en_q;
  assign reg_intr_next = u_reg.s_intr_next;
  assign reg_event_bits = {
    core_timeout_event,
    s_error_event,
    core_train_done_event,
    core_indirect_done_event,
    core_init_done_event
  };

  assign core_phy_req_ready = f_phy_req_ready;
  assign core_phy_rsp_valid = f_phy_rsp_valid;
  assign core_phy_rsp_error = f_phy_rsp_error;
  assign core_phy_rsp_rdata = f_phy_rsp_rdata;
  assign core_abort_ready = f_phy_abort_ready;
  assign core_io_active       = core_phy_req_valid || core_phy_rsp_ready ||
                                core_mem_rsp_valid || core_abort_valid;

  opipsram_phy u_phy (
      .clk_phy_i              (clk_i),
      .rst_phy_n_i            (rst_n_i),
      .cmd_valid_i            (f_phy_cmd_valid),
      .cmd_ready_o            (phy_cmd_ready),
      .cmd_profile_hyper_i    (f_phy_cmd_profile_hyper),
      .cmd_write_i            (f_phy_cmd_write),
      .cmd_indirect_register_i(f_phy_cmd_indirect_register),
      .cmd_addr_i             (f_phy_cmd_addr),
      .cmd_len_i              (f_phy_cmd_len),
      .cmd_wdata_i            (f_phy_cmd_wdata),
      .cmd_opi_cmd_i          (f_phy_cmd_opi_cmd),
      .cmd_opi_width16_i      (f_phy_cmd_opi_width16),
      .cmd_opi_timing_i       (f_phy_cmd_opi_timing),
      .cmd_hyper_timing_i     (f_phy_cmd_hyper_timing),
      .cmd_cs_timing_i        (f_phy_cmd_cs_timing),
      .cmd_clk_config_i       (f_phy_cmd_clk_config),
      .cmd_rx_delay_i         (f_phy_cmd_rx_delay),
      .cmd_timeout_i          (f_phy_cmd_timeout),
      .abort_i                (f_phy_abort),
      .rsp_valid_o            (phy_rsp_valid),
      .rsp_ready_i            (f_phy_rsp_ready),
      .rsp_error_o            (phy_rsp_error),
      .rsp_rdata_o            (phy_rsp_rdata),
      .ck_o                   (phy_ck),
      .cs_n_o                 (phy_cs_n),
      .dq_oe_o                (phy_dq_oe),
      .dq_i                   (f_phy_dq),
      .dq_o                   (),
      .rwds_oe_o              (phy_rwds_oe),
      .rwds_i                 (f_phy_rwds),
      .rwds_o                 ()
  );

  assign phy_cmd_valid             = f_phy_cmd_valid;
  assign phy_rsp_ready             = f_phy_rsp_ready;
  assign phy_cmd_profile_hyper     = f_phy_cmd_profile_hyper;
  assign phy_cmd_write             = f_phy_cmd_write;
  assign phy_cmd_indirect_register = f_phy_cmd_indirect_register;
  assign phy_cmd_len               = f_phy_cmd_len;
  assign phy_cmd_clk_config        = f_phy_cmd_clk_config;
  assign phy_abort                 = f_phy_abort;

  initial begin
    rst_n_i      = 1'b0;
    f_past_valid = 1'b0;
  end

  always_ff @(posedge clk_i) begin
    if (!f_past_valid) begin
      rst_n_i      <= 1'b1;
      f_past_valid <= 1'b1;
    end else begin
      rst_n_i <= 1'b1;
    end
  end

endmodule
