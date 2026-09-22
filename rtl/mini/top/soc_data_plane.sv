// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "soc_data_policy.svh"

module soc_data_plane (
    // verilog_format: off -- preserve the LP/HP and memory-target boundary columns
    input  logic       clk_lp_i,
    input  logic       rst_lp_n_i,
    input  logic       clk_io_i,
    input  logic       rst_io_n_i,
    input  logic       clk_hp_i,
    input  logic       rst_hp_n_i,
    input  logic       clk_mem_i,
    input  logic       rst_mem_n_i,
    input  logic       block_new_i,
    input  logic       recovery_i,
    input  logic       flush_i,
    input  logic [9:0] resource_block_i,
    input  logic [1:0] mem_pad_mode_i,
    input  logic       ext_h_block_i,
    input  logic [31:0] ext_h_read_base_i,
    input  logic [31:0] ext_h_read_limit_i,
    input  logic [31:0] ext_h_write_base_i,
    input  logic [31:0] ext_h_write_limit_i,
    axi4_if.slave      hp_icache_axi4,
    axi4_if.slave      hp_dcache_axi4,
    axi4_if.slave      dma_axi4,
    axi4_if.slave      sdio0_axi4,
    axi4_if.slave      sdio1_axi4,
    axi4_if.slave      spisd_axi4,
    axi4_if.slave      usb2_axi4,
    axi4_if.slave      apu_axi4,
    axi4_if.slave      jpeg_axi4,
    axi4_if.slave      ga2d_axi4,
    input  logic       ga2d_core_safe_idle_i
                              = 1'b1,
    axi4_if.slave      npu_axi4,
    input  logic       npu_source_idle_i,
    input  logic       npu_source_quiesced_i,
    input  logic       npu_flush_busy_i,
    axi4_if.slave      lp_data_axi4,
    axi4_if.slave      ext_h_axi4,
    axi4_if.master     sram_gateway_axi4,
    axi4_if.master     sdram_gateway_axi4,
    axi4_if.master     qpi_gateway_axi4,
    axi4_if.master     opi_gateway_axi4,
    axi4_if.master     xpi_gateway_axi4,
    apb4_if.slave      fabric_monitor_apb4,
    input  logic       fault_ready_i,
    output logic       idle_o,
    output logic       flush_busy_o,
    output logic       ext_h_idle_o,
    output logic [7:0] apu_bridge_epoch_o,
    output logic       ga2d_source_stop_o,
    output logic       ga2d_source_safe_idle_o,
    output logic       ga2d_bridge_clear_busy_o,
    output logic [7:0] ga2d_bridge_epoch_o,
    output logic       ga2d_data_ready_o,
    output logic [9:0] resource_idle_o,
    output logic [9:0] resource_block_ack_o,
    output logic [7:0] outstanding_read_o,
    output logic [7:0] outstanding_write_o,
    output logic       fault_valid_o,
    output logic [3:0] fault_master_o,
    output logic [2:0] fault_target_o,
    output logic [31:0] fault_addr_o,
    output logic       fault_write_o,
    output logic [3:0] fault_reason_o
    // verilog_format: on
);
  localparam int unsigned NumIoMasters = 3;
  localparam int unsigned NumMemoryTargets = 5;
  localparam int unsigned NumDataMasters = 10;
  localparam int unsigned NumFaultSources = NumMemoryTargets + 1;
  localparam int unsigned FaultSourceWidth = $clog2(NumFaultSources);
  localparam logic [3:0] FaultTimeout = 4'd5;

  logic [                 1:0]       s_mem_pad_mode_hp;
  logic [    NumIoMasters-1:0]       s_io_clear_busy;
  logic [NumMemoryTargets-1:0]       s_target_clear_busy;
  logic [NumMemoryTargets-1:0]       s_guard_clear_busy;
  logic [NumMemoryTargets-1:0]       s_guard_abort;
  logic [NumMemoryTargets-1:0]       s_guard_abort_done;
  logic [NumMemoryTargets-1:0]       s_guard_abort_seen_q;
  logic [NumMemoryTargets-1:0]       s_guard_timeout_valid;
  logic [NumMemoryTargets-1:0]       s_guard_isolated;
  logic [NumMemoryTargets-1:0]       s_guard_timeout_write;
  logic [NumMemoryTargets-1:0][ 6:0] s_guard_timeout_id;
  logic [NumMemoryTargets-1:0][31:0] s_guard_timeout_addr;
  logic [NumMemoryTargets-1:0]       s_target_abort_mem;
  logic                              s_crossbar_fault_valid;
  logic [                 3:0]       s_crossbar_fault_master;
  logic [                 2:0]       s_crossbar_fault_target;
  logic [                31:0]       s_crossbar_fault_addr;
  logic                              s_crossbar_fault_write;
  logic [                 3:0]       s_crossbar_fault_reason;
  logic                              s_crossbar_fault_ready;
  logic [NumMemoryTargets-1:0]       s_guard_timeout_ready;
  logic [ NumFaultSources-1:0]       s_fault_src_req;
  logic                              s_fault_src_candidate_valid;
  logic [FaultSourceWidth-1:0]       s_fault_src_candidate;
  logic s_fault_src_hold_d, s_fault_src_hold_q;
  logic [FaultSourceWidth-1:0] s_fault_src_sel_d, s_fault_src_sel_q;
  logic [FaultSourceWidth-1:0] s_fault_src_last_d, s_fault_src_last_q;
  logic                             s_fault_src_valid;
  logic [FaultSourceWidth-1:0]      s_fault_src_sel;
  logic                             s_lp_clear_busy;
  logic                             s_ext_clear_busy;
  logic                             s_jpeg_clear_busy;
  logic                             s_ga2d_clear_busy;
  logic [    NumIoMasters-1:0][7:0] unused_io_epoch;
  logic [NumMemoryTargets-1:0][7:0] unused_target_epoch;
  logic [                 7:0]      unused_lp_epoch;
  logic [                 7:0]      unused_ext_epoch;
  logic [                 7:0]      unused_jpeg_epoch;
  logic [                 7:0]      s_ga2d_epoch;
  logic [                 2:0]      s_unused_epoch;
  logic                             s_ga2d_recovery_condition;
  logic                             s_ga2d_source_stop_q;
  logic                             s_ga2d_source_stop_ready;
  logic                             s_ga2d_addr_gate_idle;
  logic                             s_ga2d_core_safe_idle;
  logic                             s_ga2d_source_safe_idle;
  logic                             s_ga2d_write_pending;
  logic                             s_ga2d_source_safe_idle_hp;
  logic                             s_ga2d_source_quiesced_q;
  logic                             s_ga2d_source_quiesced_hp;
  logic                             s_ga2d_hp_reset_n_pclk;
  logic                             s_ga2d_flush_pclk;
  logic [                 7:0]      s_ga2d_epoch_seen_q;
  logic                             s_ga2d_data_ready_q;
  logic                             s_ga2d_rearm_q;
  logic                             s_ga2d_master_idle_pclk;
  logic                             s_ga2d_block_ack_pclk;
  logic                             s_npu_source_safe_idle_hp;
  logic                             s_npu_source_quiesced_hp;
  logic [                 9:0]      s_resource_block_hp;
  logic [                 9:0]      s_master_idle;
  logic [                 9:0]      s_master_block;
  logic [                 9:0]      s_monitor_master_read_accept;
  logic [                 9:0]      s_monitor_master_write_accept;
  logic [                 9:0]      s_monitor_master_read_beat;
  logic [                 9:0]      s_monitor_master_write_beat;
  logic [                 9:0]      s_monitor_master_wait;
  logic [                 9:0]      s_monitor_master_promotion;
  logic [                 9:0][2:0] s_monitor_master_read_outstanding;
  logic [                 9:0][2:0] s_monitor_master_write_outstanding;
  logic [                 5:0]      s_monitor_target_read_accept;
  logic [                 5:0]      s_monitor_target_write_accept;
  logic [                 5:0]      s_monitor_target_read_beat;
  logic [                 5:0]      s_monitor_target_write_beat;
  logic [                 5:0]      s_monitor_target_wait;
  logic [                 5:0][2:0] s_monitor_target_read_outstanding;
  logic [                 5:0][2:0] s_monitor_target_write_outstanding;
  logic [                 5:0]      s_monitor_target_timeout;
  logic [                 5:0]      s_monitor_target_isolated;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (7),
      .USER_WIDTH(1)
  ) u_master_axi4[NumDataMasters] (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (7),
      .USER_WIDTH(1)
  ) u_crossbar_target_axi4[6] (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (7),
      .USER_WIDTH(1)
  ) u_target_axi4[NumMemoryTargets] (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (7),
      .USER_WIDTH(1)
  ) u_target_mem_axi4[NumMemoryTargets-1] (
      .aclk   (clk_mem_i),
      .aresetn(rst_mem_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_target_mem_narrow_axi4[NumMemoryTargets-1] (
      .aclk   (clk_mem_i),
      .aresetn(rst_mem_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (7),
      .USER_WIDTH(1)
  ) u_hp_icache_prefixed_axi4 (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (7),
      .USER_WIDTH(1)
  ) u_hp_dcache_prefixed_axi4 (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_io_lp_axi4[NumIoMasters] (
      .aclk   (clk_io_i),
      .aresetn(rst_io_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_io_hp_axi4[NumIoMasters] (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_io_idle_axi4[1] (
      .aclk   (clk_io_i),
      .aresetn(rst_io_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_lp_data_hp_axi4 (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) u_ext_h_hp_axi4 (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) u_ext_h_gated_axi4 (
      .aclk   (clk_io_i),
      .aresetn(rst_io_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (7),
      .USER_WIDTH(1)
  ) u_ext_h_prefixed_axi4 (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) u_jpeg_hp_axi4 (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (7),
      .USER_WIDTH(1)
  ) u_jpeg_prefixed_axi4 (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) u_ga2d_gated_axi4 (
      .aclk   (clk_io_i),
      .aresetn(rst_io_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) u_ga2d_hp_axi4 (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (7),
      .USER_WIDTH(1)
  ) u_ga2d_prefixed_axi4 (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (7),
      .USER_WIDTH(1)
  ) u_npu_prefixed_axi4 (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(2)
  ) u_mem_pad_mode_sync (
      .clk_i  (clk_hp_i),
      .rst_n_i(rst_hp_n_i),
      .dat_i  (mem_pad_mode_i),
      .dat_o  (s_mem_pad_mode_hp)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(10)
  ) u_resource_block_sync (
      .clk_i  (clk_hp_i),
      .rst_n_i(rst_hp_n_i),
      .dat_i  (resource_block_i),
      .dat_o  (s_resource_block_hp)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_ga2d_source_idle_sync (
      .clk_i  (clk_hp_i),
      .rst_n_i(rst_hp_n_i),
      .dat_i  (s_ga2d_source_safe_idle),
      .dat_o  (s_ga2d_source_safe_idle_hp)
  );
  // A fresh source quiesce prevents stale idle from blocking W-before-AW traffic.
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_ga2d_source_quiesced_sync (
      .clk_i  (clk_hp_i),
      .rst_n_i(rst_hp_n_i),
      .dat_i  (s_ga2d_source_quiesced_q),
      .dat_o  (s_ga2d_source_quiesced_hp)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_ga2d_hp_reset_sync (
      .clk_i  (clk_io_i),
      .rst_n_i(rst_io_n_i),
      .dat_i  (rst_hp_n_i),
      .dat_o  (s_ga2d_hp_reset_n_pclk)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_ga2d_flush_sync (
      .clk_i  (clk_io_i),
      .rst_n_i(rst_io_n_i),
      .dat_i  (flush_i),
      .dat_o  (s_ga2d_flush_pclk)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_ga2d_master_idle_sync (
      .clk_i  (clk_io_i),
      .rst_n_i(rst_io_n_i),
      .dat_i  (s_master_idle[8]),
      .dat_o  (s_ga2d_master_idle_pclk)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_ga2d_block_ack_sync (
      .clk_i  (clk_io_i),
      .rst_n_i(rst_io_n_i),
      .dat_i  (resource_block_ack_o[8]),
      .dat_o  (s_ga2d_block_ack_pclk)
  );
  // The NPU shell owns its PCLK-side idle and round-trip quiesce
  // acknowledgement; both cross into HP exactly like the GA2D source state.
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_npu_source_idle_sync (
      .clk_i  (clk_hp_i),
      .rst_n_i(rst_hp_n_i),
      .dat_i  (npu_source_idle_i),
      .dat_o  (s_npu_source_safe_idle_hp)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_npu_source_quiesced_sync (
      .clk_i  (clk_hp_i),
      .rst_n_i(rst_hp_n_i),
      .dat_i  (npu_source_quiesced_i),
      .dat_o  (s_npu_source_quiesced_hp)
  );

  assign s_ga2d_recovery_condition = resource_block_i[8] || !s_ga2d_hp_reset_n_pclk ||
                                     s_ga2d_flush_pclk || s_ga2d_clear_busy ||
                                     (s_ga2d_epoch != s_ga2d_epoch_seen_q);
  assign s_ga2d_core_safe_idle = ga2d_core_safe_idle_i;
  assign s_ga2d_source_safe_idle = s_ga2d_addr_gate_idle && s_ga2d_core_safe_idle;
  assign s_ga2d_source_stop_ready = (!ga2d_axi4.awvalid || ga2d_axi4.awready) &&
                                    (!ga2d_axi4.arvalid || ga2d_axi4.arready) &&
                                    (!ga2d_axi4.wvalid || s_ga2d_write_pending);
  assign ga2d_source_stop_o = s_ga2d_source_stop_q;
  assign ga2d_source_safe_idle_o = s_ga2d_source_safe_idle;
  assign ga2d_bridge_clear_busy_o = s_ga2d_clear_busy;
  assign ga2d_bridge_epoch_o = s_ga2d_epoch;
  assign ga2d_data_ready_o = s_ga2d_data_ready_q;

  always_ff @(posedge clk_io_i or negedge rst_io_n_i) begin
    if (!rst_io_n_i) begin
      s_ga2d_source_stop_q     <= 1'b1;
      s_ga2d_epoch_seen_q      <= '0;
      s_ga2d_data_ready_q      <= 1'b0;
      s_ga2d_rearm_q           <= 1'b1;
      s_ga2d_source_quiesced_q <= 1'b0;
    end else begin
      s_ga2d_epoch_seen_q <= s_ga2d_epoch;
      s_ga2d_source_quiesced_q <= resource_block_i[8] && s_ga2d_source_stop_q &&
                                  s_ga2d_source_safe_idle;
      if (s_ga2d_recovery_condition) begin
        s_ga2d_rearm_q      <= 1'b1;
        s_ga2d_data_ready_q <= 1'b0;
        if (s_ga2d_source_stop_ready) begin
          s_ga2d_source_stop_q <= 1'b1;
        end
      end else if (s_ga2d_rearm_q) begin
        s_ga2d_data_ready_q <= 1'b0;
        if (s_ga2d_source_safe_idle && s_ga2d_master_idle_pclk && !s_ga2d_block_ack_pclk) begin
          s_ga2d_source_stop_q <= 1'b0;
          s_ga2d_rearm_q       <= 1'b0;
        end
      end else begin
        s_ga2d_data_ready_q <= 1'b1;
      end
    end
  end

  assign s_master_block = {
    s_resource_block_hp[9] && s_npu_source_quiesced_hp,
    s_resource_block_hp[8] && s_ga2d_source_quiesced_hp,
    s_resource_block_hp[5],
    s_resource_block_hp[6],
    1'b0,
    s_resource_block_hp[4] || s_resource_block_hp[3],
    s_resource_block_hp[2] || s_resource_block_hp[1],
    s_resource_block_hp[0],
    2'b00
  };
  assign resource_idle_o = {
    (s_resource_block_hp[9] ? s_npu_source_quiesced_hp : s_npu_source_safe_idle_hp) &&
        s_master_idle[9],
    (s_resource_block_hp[8] ? s_ga2d_source_quiesced_hp : s_ga2d_source_safe_idle_hp) &&
        s_master_idle[8],
    s_master_idle[3],
    s_master_idle[6],
    s_master_idle[7],
    s_master_idle[4],
    s_master_idle[4],
    s_master_idle[3],
    s_master_idle[3],
    s_master_idle[2]
  };
  assign resource_block_ack_o = {
    s_resource_block_hp[9] && s_npu_source_quiesced_hp && s_master_idle[9],
    s_resource_block_hp[8] && s_ga2d_source_quiesced_hp && s_master_idle[8],
    s_resource_block_hp[7:0]
  };

  axi4_id_prefix #(
      .MasterIndex(4'd0)
  ) u_hp_icache_prefix (
      .source(hp_icache_axi4),
      .sink  (u_hp_icache_prefixed_axi4)
  );
  axi4_connector u_hp_icache_connector (
      .source(u_hp_icache_prefixed_axi4),
      .sink  (u_master_axi4[0])
  );
  axi4_id_prefix #(
      .MasterIndex(4'd1)
  ) u_hp_dcache_prefix (
      .source(hp_dcache_axi4),
      .sink  (u_hp_dcache_prefixed_axi4)
  );
  axi4_connector u_hp_dcache_connector (
      .source(u_hp_dcache_prefixed_axi4),
      .sink  (u_master_axi4[1])
  );

  axi4_connector u_dma_source_connector (
      .source(dma_axi4),
      .sink  (u_io_lp_axi4[0])
  );
  hp_axi4_mux3 #(
      .RoundRobin       (1'b1),
      .Client0EpochAware(1'b1)
  ) u_io_gateway_a (
      .clk_i  (clk_io_i),
      .rst_n_i(rst_io_n_i),
      .epoch_i(unused_io_epoch[1]),
      .icache (apu_axi4),
      .dcache (sdio0_axi4),
      .mmio   (usb2_axi4),
      .axi4   (u_io_lp_axi4[1])
  );
  hp_axi4_mux3 u_io_gateway_b (
      .clk_i  (clk_io_i),
      .rst_n_i(rst_io_n_i),
      .epoch_i(unused_io_epoch[2]),
      .icache (u_io_idle_axi4[0]),
      .dcache (spisd_axi4),
      .mmio   (sdio1_axi4),
      .axi4   (u_io_lp_axi4[2])
  );
  axi4_master_idle u_io_gateway_b_idle (.axi4(u_io_idle_axi4[0]));

  for (genvar master = 0; master < NumIoMasters; master++) begin : gen_io_master
    axi4_async_bridge #(
        .DataWidth(32),
        .IdWidth  (1)
    ) u_io_cdc (
        .src_clk_i   (clk_io_i),
        .src_rst_n_i (rst_io_n_i),
        .dst_clk_i   (clk_hp_i),
        .dst_rst_n_i (rst_hp_n_i),
        .clear_i     (flush_i),
        .clear_busy_o(s_io_clear_busy[master]),
        .epoch_o     (unused_io_epoch[master]),
        .src_axi4    (u_io_lp_axi4[master]),
        .dst_axi4    (u_io_hp_axi4[master])
    );
    axi4_upsizer_32to64 #(
        .MasterIndex(4'(master + 2))
    ) u_io_upsizer (
        .clk_i  (clk_hp_i),
        .rst_n_i(rst_hp_n_i),
        .narrow (u_io_hp_axi4[master]),
        .wide   (u_master_axi4[master+2])
    );
  end

  axi4_async_bridge #(
      .DataWidth(32),
      .IdWidth  (1)
  ) u_lp_data_cdc (
      .src_clk_i   (clk_lp_i),
      .src_rst_n_i (rst_lp_n_i),
      .dst_clk_i   (clk_hp_i),
      .dst_rst_n_i (rst_hp_n_i),
      // An HP lifecycle flush invalidates HP transport, not an LP request
      // still queued before crossbar admission.
      .clear_i     (1'b0),
      .clear_busy_o(s_lp_clear_busy),
      .epoch_o     (unused_lp_epoch),
      .src_axi4    (lp_data_axi4),
      .dst_axi4    (u_lp_data_hp_axi4)
  );
  axi4_upsizer_32to64 #(
      .MasterIndex(4'd5)
  ) u_lp_data_upsizer (
      .clk_i  (clk_hp_i),
      .rst_n_i(rst_hp_n_i),
      .narrow (u_lp_data_hp_axi4),
      .wide   (u_master_axi4[5])
  );
  axi4_async_bridge #(
      .DataWidth(64),
      .IdWidth  (3)
  ) u_jpeg_cdc (
      .src_clk_i   (clk_io_i),
      .src_rst_n_i (rst_io_n_i),
      .dst_clk_i   (clk_hp_i),
      .dst_rst_n_i (rst_hp_n_i),
      .clear_i     (flush_i),
      .clear_busy_o(s_jpeg_clear_busy),
      .epoch_o     (unused_jpeg_epoch),
      .src_axi4    (jpeg_axi4),
      .dst_axi4    (u_jpeg_hp_axi4)
  );
  axi4_id_prefix #(
      .MasterIndex(4'd6)
  ) u_jpeg_prefix (
      .source(u_jpeg_hp_axi4),
      .sink  (u_jpeg_prefixed_axi4)
  );
  axi4_connector u_jpeg_connector (
      .source(u_jpeg_prefixed_axi4),
      .sink  (u_master_axi4[6])
  );

  axi4_address_gate u_ga2d_source_gate (
      .clk_i          (clk_io_i),
      .rst_n_i        (rst_io_n_i),
      .block_new_i    (s_ga2d_source_stop_q),
      .clear_i        (s_ga2d_flush_pclk),
      .source         (ga2d_axi4),
      .sink           (u_ga2d_gated_axi4),
      .idle_o         (s_ga2d_addr_gate_idle),
      .write_pending_o(s_ga2d_write_pending)
  );
  axi4_async_bridge #(
      .DataWidth(64),
      .IdWidth  (3)
  ) u_ga2d_cdc (
      .src_clk_i   (clk_io_i),
      .src_rst_n_i (rst_io_n_i),
      .dst_clk_i   (clk_hp_i),
      .dst_rst_n_i (rst_hp_n_i),
      .clear_i     (flush_i),
      .clear_busy_o(s_ga2d_clear_busy),
      .epoch_o     (s_ga2d_epoch),
      .src_axi4    (u_ga2d_gated_axi4),
      .dst_axi4    (u_ga2d_hp_axi4)
  );
  axi4_id_prefix #(
      .MasterIndex(4'd8)
  ) u_ga2d_prefix (
      .source(u_ga2d_hp_axi4),
      .sink  (u_ga2d_prefixed_axi4)
  );
  axi4_connector u_ga2d_connector (
      .source(u_ga2d_prefixed_axi4),
      .sink  (u_master_axi4[8])
  );

  // The NPU master is HP-native: no payload CDC or width upsizer. The shell
  // ties it safely idle in Phase 2; the production DMA is Phase 3 scope.
  axi4_id_prefix #(
      .MasterIndex(4'd9)
  ) u_npu_prefix (
      .source(npu_axi4),
      .sink  (u_npu_prefixed_axi4)
  );
  axi4_connector u_npu_connector (
      .source(u_npu_prefixed_axi4),
      .sink  (u_master_axi4[9])
  );

  axi4_async_bridge #(
      .DataWidth(64),
      .IdWidth  (3)
  ) u_ext_h_cdc (
      .src_clk_i   (clk_io_i),
      .src_rst_n_i (rst_io_n_i),
      .dst_clk_i   (clk_hp_i),
      .dst_rst_n_i (rst_hp_n_i),
      .clear_i     (flush_i),
      .clear_busy_o(s_ext_clear_busy),
      .epoch_o     (unused_ext_epoch),
      .src_axi4    (u_ext_h_gated_axi4),
      .dst_axi4    (u_ext_h_hp_axi4)
  );
  axi4_address_gate u_ext_h_address_gate (
      .clk_i          (clk_io_i),
      .rst_n_i        (rst_io_n_i),
      .block_new_i    (ext_h_block_i),
      .clear_i        (1'b0),
      .source         (ext_h_axi4),
      .sink           (u_ext_h_gated_axi4),
      .idle_o         (ext_h_idle_o),
      .write_pending_o()
  );
  axi4_id_prefix #(
      .MasterIndex(4'd7)
  ) u_ext_h_prefix (
      .source(u_ext_h_hp_axi4),
      .sink  (u_ext_h_prefixed_axi4)
  );
  axi4_connector u_ext_h_connector (
      .source(u_ext_h_prefixed_axi4),
      .sink  (u_master_axi4[7])
  );

  axi4_data_crossbar #(
      .NumMasters         (NumDataMasters),
      .NumTargets         (6),
      .ReadTargetMask     (`SOC_DATA_POLICY_READ_TARGET_MASK),
      .WriteTargetMask    (`SOC_DATA_POLICY_WRITE_TARGET_MASK),
      .AllowInstruction   (`SOC_DATA_POLICY_ALLOW_INSTRUCTION),
      .RequireNoncacheable(`SOC_DATA_POLICY_REQUIRE_NONCACHEABLE)
  ) u_data_crossbar (
      .clk_i                             (clk_hp_i),
      .rst_n_i                           (rst_hp_n_i),
      .block_new_i                       (block_new_i),
      .master_block_i                    (s_master_block),
      .recovery_i                        (recovery_i),
      .flush_i                           (flush_i),
      .fault_ready_i                     (s_crossbar_fault_ready),
      .mem_pad_mode_i                    (s_mem_pad_mode_hp),
      .ext_h_read_base_i                 (ext_h_read_base_i),
      .ext_h_read_limit_i                (ext_h_read_limit_i),
      .ext_h_write_base_i                (ext_h_write_base_i),
      .ext_h_write_limit_i               (ext_h_write_limit_i),
      .masters                           (u_master_axi4),
      .targets                           (u_crossbar_target_axi4),
      .idle_o                            (idle_o),
      .master_idle_o                     (s_master_idle),
      .outstanding_read_o                (outstanding_read_o),
      .outstanding_write_o               (outstanding_write_o),
      .fault_valid_o                     (s_crossbar_fault_valid),
      .fault_master_o                    (s_crossbar_fault_master),
      .fault_target_o                    (s_crossbar_fault_target),
      .fault_addr_o                      (s_crossbar_fault_addr),
      .fault_write_o                     (s_crossbar_fault_write),
      .fault_reason_o                    (s_crossbar_fault_reason),
      .monitor_master_read_accept_o      (s_monitor_master_read_accept),
      .monitor_master_write_accept_o     (s_monitor_master_write_accept),
      .monitor_master_read_beat_o        (s_monitor_master_read_beat),
      .monitor_master_write_beat_o       (s_monitor_master_write_beat),
      .monitor_master_wait_o             (s_monitor_master_wait),
      .monitor_master_promotion_o        (s_monitor_master_promotion),
      .monitor_master_read_outstanding_o (s_monitor_master_read_outstanding),
      .monitor_master_write_outstanding_o(s_monitor_master_write_outstanding),
      .monitor_target_read_accept_o      (s_monitor_target_read_accept),
      .monitor_target_write_accept_o     (s_monitor_target_write_accept),
      .monitor_target_read_beat_o        (s_monitor_target_read_beat),
      .monitor_target_write_beat_o       (s_monitor_target_write_beat),
      .monitor_target_wait_o             (s_monitor_target_wait),
      .monitor_target_read_outstanding_o (s_monitor_target_read_outstanding),
      .monitor_target_write_outstanding_o(s_monitor_target_write_outstanding)
  );

  for (genvar target = 0; target < NumMemoryTargets; target++) begin : gen_memory_target
    localparam logic [31:0] TargetTimeout = (target == 0) ? 32'd256 :
        (target == 1) ? 32'd8192 : 32'd65535;

    axi4_target_guard #(
        .IdWidth   (7),
        .ReadDepth (target < 2 ? 4 : 2),
        .WriteDepth(2)
    ) u_target_guard (
        .clk_i          (clk_hp_i),
        .rst_n_i        (rst_hp_n_i),
        .clear_i        (flush_i),
        .timeout_i      (TargetTimeout),
        .clear_busy_o   (s_guard_clear_busy[target]),
        .abort_o        (s_guard_abort[target]),
        .abort_done_i   (s_guard_abort_done[target]),
        .timeout_valid_o(s_guard_timeout_valid[target]),
        .timeout_ready_i(s_guard_timeout_ready[target]),
        .isolated_o     (s_guard_isolated[target]),
        .timeout_write_o(s_guard_timeout_write[target]),
        .timeout_id_o   (s_guard_timeout_id[target]),
        .timeout_addr_o (s_guard_timeout_addr[target]),
        .source         (u_crossbar_target_axi4[target]),
        .sink           (u_target_axi4[target])
    );
    if (target == 0) begin : gen_native_sram
      axi4_connector u_sram_gateway_connector (
          .source(u_target_axi4[target]),
          .sink  (sram_gateway_axi4)
      );
      assign s_target_clear_busy[target] = 1'b0;
      assign unused_target_epoch[target] = 8'd0;
    end else begin : gen_stable_memory
      axi4_async_bridge #(
          .DataWidth(64),
          .IdWidth  (7)
      ) u_target_cdc (
          .src_clk_i   (clk_hp_i),
          .src_rst_n_i (rst_hp_n_i),
          .dst_clk_i   (clk_mem_i),
          .dst_rst_n_i (rst_mem_n_i),
          .clear_i     (flush_i || s_guard_abort[target]),
          .clear_busy_o(s_target_clear_busy[target]),
          .epoch_o     (unused_target_epoch[target]),
          .src_axi4    (u_target_axi4[target]),
          .dst_axi4    (u_target_mem_axi4[target-1])
      );
      cdc_sync #(
          .STAGE     (2),
          .DATA_WIDTH(1)
      ) u_abort_sync (
          .clk_i  (clk_mem_i),
          .rst_n_i(rst_mem_n_i),
          .dat_i  (s_guard_abort[target]),
          .dat_o  (s_target_abort_mem[target])
      );
      axi4_downsizer_64to32 #(
          .WideIdWidth(7)
      ) u_target_downsizer (
          .clk_i  (clk_mem_i),
          .rst_n_i(rst_mem_n_i),
          .clear_i(s_target_abort_mem[target]),
          .wide   (u_target_mem_axi4[target-1]),
          .narrow (u_target_mem_narrow_axi4[target-1])
      );
    end
  end
  assign s_target_abort_mem[0] = 1'b0;

  axi4_error_slave #(
      .Response(2'b11),
      .IdWidth (7)
  ) u_data_error_slave (
      .clk_i  (clk_hp_i),
      .rst_n_i(rst_hp_n_i),
      .axi4   (u_crossbar_target_axi4[5])
  );

  assign s_monitor_target_timeout  = {1'b0, s_guard_timeout_valid & s_guard_timeout_ready};
  assign s_monitor_target_isolated = {1'b0, s_guard_isolated};

  fabric_monitor #(
      .NumMasters(NumDataMasters),
      .NumTargets(6)
  ) u_fabric_monitor (
      .clk_i                     (clk_hp_i),
      .rst_n_i                   (rst_hp_n_i),
      .idle_i                    (idle_o),
      .recovery_i                (recovery_i),
      .flush_busy_i              (flush_busy_o),
      .flush_i                   (flush_i),
      .outstanding_read_i        (outstanding_read_o),
      .outstanding_write_i       (outstanding_write_o),
      .fault_valid_i             (fault_valid_o && fault_ready_i),
      .fault_master_i            (fault_master_o),
      .fault_target_i            (fault_target_o),
      .fault_addr_i              (fault_addr_o),
      .fault_write_i             (fault_write_o),
      .fault_reason_i            (fault_reason_o),
      .master_read_accept_i      (s_monitor_master_read_accept),
      .master_write_accept_i     (s_monitor_master_write_accept),
      .master_read_beat_i        (s_monitor_master_read_beat),
      .master_write_beat_i       (s_monitor_master_write_beat),
      .master_wait_i             (s_monitor_master_wait),
      .master_promotion_i        (s_monitor_master_promotion),
      .master_read_outstanding_i (s_monitor_master_read_outstanding),
      .master_write_outstanding_i(s_monitor_master_write_outstanding),
      .target_read_accept_i      (s_monitor_target_read_accept),
      .target_write_accept_i     (s_monitor_target_write_accept),
      .target_read_beat_i        (s_monitor_target_read_beat),
      .target_write_beat_i       (s_monitor_target_write_beat),
      .target_wait_i             (s_monitor_target_wait),
      .target_timeout_i          (s_monitor_target_timeout),
      .target_isolated_i         (s_monitor_target_isolated),
      .target_read_outstanding_i (s_monitor_target_read_outstanding),
      .target_write_outstanding_i(s_monitor_target_write_outstanding),
      .apb4                      (fabric_monitor_apb4)
  );

  for (genvar target = 0; target < NumMemoryTargets; target++) begin : gen_abort_handshake
    assign s_guard_abort_done[target] = (target == 0) ? s_guard_abort[target] :
        s_guard_abort[target] && s_guard_abort_seen_q[target] &&
        !s_target_clear_busy[target];

    always_ff @(posedge clk_hp_i or negedge rst_hp_n_i) begin
      if (!rst_hp_n_i) begin
        s_guard_abort_seen_q[target] <= 1'b0;
      end else if (!s_guard_abort[target]) begin
        s_guard_abort_seen_q[target] <= 1'b0;
      end else if (s_target_clear_busy[target]) begin
        s_guard_abort_seen_q[target] <= 1'b1;
      end
    end
  end

  always_comb begin
    s_fault_src_req    = '0;
    s_fault_src_req[0] = s_crossbar_fault_valid;
    for (int target = 0; target < NumMemoryTargets; target++) begin
      s_fault_src_req[target+1] = s_guard_timeout_valid[target];
    end
  end

  always_comb begin
    s_fault_src_candidate_valid = 1'b0;
    s_fault_src_candidate       = '0;
    for (int offset = 1; offset <= NumFaultSources; offset++) begin
      int src;
      src = int'(s_fault_src_last_q) + offset;
      if (src >= NumFaultSources) src = src - NumFaultSources;
      if (!s_fault_src_candidate_valid && s_fault_src_req[src]) begin
        s_fault_src_candidate_valid = 1'b1;
        s_fault_src_candidate       = FaultSourceWidth'(src);
      end
    end
  end

  always_comb begin
    s_fault_src_valid = 1'b0;
    s_fault_src_sel   = '0;
    if (s_fault_src_hold_q) begin
      s_fault_src_sel   = s_fault_src_sel_q;
      s_fault_src_valid = s_fault_src_req[s_fault_src_sel_q];
    end else if (s_fault_src_candidate_valid) begin
      s_fault_src_sel   = s_fault_src_candidate;
      s_fault_src_valid = 1'b1;
    end
  end

  always_comb begin
    fault_valid_o  = s_fault_src_valid;
    fault_master_o = '0;
    fault_target_o = '0;
    fault_addr_o   = '0;
    fault_write_o  = 1'b0;
    fault_reason_o = '0;
    if (s_fault_src_valid) begin
      if (s_fault_src_sel == FaultSourceWidth'(0)) begin
        fault_master_o = s_crossbar_fault_master;
        fault_target_o = s_crossbar_fault_target;
        fault_addr_o   = s_crossbar_fault_addr;
        fault_write_o  = s_crossbar_fault_write;
        fault_reason_o = s_crossbar_fault_reason;
      end else begin
        for (int target = 0; target < NumMemoryTargets; target++) begin
          if (s_fault_src_sel == FaultSourceWidth'(target + 1)) begin
            fault_master_o = s_guard_timeout_id[target][6:3];
            fault_target_o = 3'(target);
            fault_addr_o   = s_guard_timeout_addr[target];
            fault_write_o  = s_guard_timeout_write[target];
            fault_reason_o = FaultTimeout;
          end
        end
      end
    end
  end

  always_comb begin
    s_crossbar_fault_ready = 1'b0;
    s_guard_timeout_ready  = '0;
    if (s_fault_src_valid && fault_ready_i) begin
      if (s_fault_src_sel == FaultSourceWidth'(0)) begin
        s_crossbar_fault_ready = 1'b1;
      end else begin
        for (int target = 0; target < NumMemoryTargets; target++) begin
          if (s_fault_src_sel == FaultSourceWidth'(target + 1)) begin
            s_guard_timeout_ready[target] = 1'b1;
          end
        end
      end
    end
  end

  always_comb begin
    s_fault_src_hold_d = s_fault_src_hold_q;
    s_fault_src_sel_d  = s_fault_src_sel_q;
    s_fault_src_last_d = s_fault_src_last_q;
    if (flush_i) begin
      s_fault_src_hold_d = 1'b0;
    end else if (s_fault_src_hold_q) begin
      if (!s_fault_src_valid) begin
        s_fault_src_hold_d = 1'b0;
      end else if (fault_ready_i) begin
        s_fault_src_hold_d = 1'b0;
        s_fault_src_last_d = s_fault_src_sel_q;
      end
    end else if (s_fault_src_candidate_valid) begin
      if (fault_ready_i) begin
        s_fault_src_last_d = s_fault_src_candidate;
      end else begin
        s_fault_src_hold_d = 1'b1;
        s_fault_src_sel_d  = s_fault_src_candidate;
      end
    end
  end

  // Each source holds its payload until accepted; the selector locks it while
  // the mailbox backpressures and rotates grants after every accepted event.
  always_ff @(posedge clk_hp_i or negedge rst_hp_n_i) begin
    if (!rst_hp_n_i) begin
      s_fault_src_hold_q <= 1'b0;
      s_fault_src_sel_q  <= '0;
      s_fault_src_last_q <= FaultSourceWidth'(NumFaultSources - 1);
    end else begin
      s_fault_src_hold_q <= s_fault_src_hold_d;
      s_fault_src_sel_q  <= s_fault_src_sel_d;
      s_fault_src_last_q <= s_fault_src_last_d;
    end
  end

  assign flush_busy_o = (|s_io_clear_busy) || (|s_target_clear_busy) ||
                        (|s_guard_clear_busy) || s_lp_clear_busy || s_ext_clear_busy ||
                        s_jpeg_clear_busy || s_ga2d_clear_busy || npu_flush_busy_i;
  assign apu_bridge_epoch_o = unused_io_epoch[1];
  assign s_unused_epoch = {
    ^unused_io_epoch, ^unused_target_epoch, ^{unused_lp_epoch, unused_ext_epoch, unused_jpeg_epoch}
  };

  axi4_connector u_qpi_gateway_connector (
      .source(u_target_mem_narrow_axi4[1]),
      .sink  (qpi_gateway_axi4)
  );
  axi4_connector u_opi_gateway_connector (
      .source(u_target_mem_narrow_axi4[2]),
      .sink  (opi_gateway_axi4)
  );
  axi4_connector u_xpi_gateway_connector (
      .source(u_target_mem_narrow_axi4[3]),
      .sink  (xpi_gateway_axi4)
  );
  axi4_connector u_sdram_gateway_connector (
      .source(u_target_mem_narrow_axi4[0]),
      .sink  (sdram_gateway_axi4)
  );
endmodule
