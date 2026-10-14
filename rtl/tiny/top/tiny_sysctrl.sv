// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0
`include "sysctrl_define.svh"
`include "tiny_rcu_regs.svh"

module tiny_sysctrl #(
    parameter bit                 PllPresent  = 1'b0,
    parameter bit                 PllProfiles = 1'b0,
    parameter int unsigned        XinHzValue  = 24_000_000,
    parameter logic        [13:0] TargetMask  = 14'd0
) (
    input  logic                clk_i,
    input  logic                rst_n_i,
    input  logic                clk_ref_i,
    input  logic                rst_ref_n_i,
    output logic                rcu_link_ready_o,
           apb4_if.slave        apb4,
    input  logic                fault_valid_i,
    input  logic         [ 3:0] fault_count_i,
    input  logic         [31:0] fault_addr_i,
    input  logic                fault_write_i,
    input  logic         [ 1:0] fault_master_i,
    input  logic         [ 1:0] fault_resp_i,
    input  logic         [63:0] cpu_wait_i,
    input  logic         [63:0] dma_wait_i,
    input  logic                rtc_wake_i,
    input  logic                clock_done_i,
    input  logic         [ 4:0] clock_fault_i,
    input  logic         [ 1:0] clock_current_i,
    input  logic                pll_locked_i,
    input  logic                pll_selected_i,
    input  logic                warm_reset_i,
    input  logic                watchdog_reset_i,
    input  logic                hart_reset_i,
    output logic                system_reset_o,
    output logic                rcu_irq_o,
    output logic         [31:0] clock_timeout_o,
    input  logic                periph_done_i,
    input  logic         [ 4:0] periph_fault_i,
    input  logic         [13:0] gate_actual_i,
    input  logic         [13:0] reset_done_i,
    output logic                periph_apply_o,
    output logic                periph_reset_o,
    output logic         [13:0] periph_request_o,
    output logic         [31:0] clkout_control_o,
    input  logic                clkout_idle_i,
    output logic                perf_enable_o,
    output logic                perf_clear_o,
    output logic                test_done_o,
    output logic                test_pass_o,
    output logic         [ 7:0] test_code_o,
    output logic         [31:0] xin_hz_o,
    output logic         [31:0] ref_hz_o,
    output logic         [31:0] sys_hz_o,
    output logic         [31:0] mem_hz_o,
    output logic         [31:0] pclk_hz_o,
    output logic         [31:0] clint_hz_o,
    output logic         [ 1:0] rcu_current_o,
    output logic                rcu_busy_o,
    output logic                clock_apply_o,
    output logic         [ 1:0] clock_profile_o
);
  localparam logic [31:0] RcuId = `APB4_TINY_RCU__ID;
  localparam logic [31:0] RcuVersion = `APB4_TINY_RCU__VERSION;
  localparam logic [31:0] RcuCapability = `APB4_TINY_RCU__CAPABILITY;
  localparam logic [31:0] ClockRequest = `APB4_TINY_RCU__CLOCK_REQUEST;
  localparam logic [31:0] ClockCurrent = `APB4_TINY_RCU__CLOCK_CURRENT;
  localparam logic [31:0] RcuCommand = `APB4_TINY_RCU__COMMAND;
  localparam logic [31:0] RcuStatus = `APB4_TINY_RCU__STATUS;
  localparam logic [31:0] TimeoutRefCycles = `APB4_TINY_RCU__TIMEOUT;
  localparam logic [31:0] GateRequest = `APB4_TINY_RCU__GATE_REQUEST;
  localparam logic [31:0] GateStatus = `APB4_TINY_RCU__GATE_STATUS;
  localparam logic [31:0] ResetRequest = `APB4_TINY_RCU__RESET_REQUEST;
  localparam logic [31:0] ResetDone = `APB4_TINY_RCU__RESET_DONE;
  localparam logic [31:0] ResetCause = `APB4_TINY_RCU__RESET_CAUSE;
  localparam logic [31:0] RcuFault = `APB4_TINY_RCU__FAULT;
  localparam logic [31:0] RcuIrqState = `APB4_TINY_RCU__IRQ_STATE;
  localparam logic [31:0] RcuIrqEnable = `APB4_TINY_RCU__IRQ_ENABLE;
  localparam logic [31:0] XinHz = `APB4_TINY_RCU__XIN_HZ;
  localparam logic [31:0] RefHz = `APB4_TINY_RCU__REF_HZ;
  localparam logic [31:0] SysHz = `APB4_TINY_RCU__SYS_HZ;
  localparam logic [31:0] MemHz = `APB4_TINY_RCU__MEM_HZ;
  localparam logic [31:0] PclkHz = `APB4_TINY_RCU__PCLK_HZ;
  localparam logic [31:0] ClintHz = `APB4_TINY_RCU__CLINT_HZ;
  localparam logic [31:0] TargetCapability = `APB4_TINY_RCU__TARGET_CAP;
  localparam logic [31:0] ClkoutControl = `APB4_TINY_RCU__CLKOUT;
  logic [31:0] s_test_d, s_test_q;
  logic [31:0] s_fault_addr_d, s_fault_addr_q;
  logic [31:0] s_fault_count_d, s_fault_count_q;
  logic [4:0] s_fault_stat_d, s_fault_stat_q;
  logic [1:0] s_fault_master_d, s_fault_master_q;
  logic [32:0] s_fault_sum;
  logic [1:0] s_fault_resp_d, s_fault_resp_q;
  logic s_perf_en_d, s_perf_en_q;
  logic s_wake_d, s_wake_q;
  logic [63:0] s_cpu_snapshot_d, s_cpu_snapshot_q;
  logic [63:0] s_dma_snapshot_d, s_dma_snapshot_q;
  logic s_req, s_write, s_valid, s_writable, s_access_err;
  logic s_ready_d, s_ready_q;
  logic s_err_d, s_err_q;
  logic [31:0] s_read_data;
  logic [31:0] s_offset;
  logic [31:0] s_rdata_d, s_rdata_q;
  logic [1:0] s_clk_req_d, s_clk_req_q;
  logic [1:0] s_clk_cur_d, s_clk_cur_q;
  logic [1:0] s_clk_latched_d, s_clk_latched_q;
  logic s_system_reset_d, s_system_reset_q;
  logic s_periph_apply_d, s_periph_apply_q, s_periph_reset_d, s_periph_reset_q;
  logic [13:0] s_periph_mask_d, s_periph_mask_q;
  logic [3:0] s_active_cmd_d, s_active_cmd_q;
  logic s_clock_apply_d, s_clock_apply_q;
  logic s_rcu_busy_d, s_rcu_busy_q;
  logic [31:0] s_timeout_ref_d, s_timeout_ref_q;
  logic [31:0] s_gate_req_d, s_gate_req_q;
  logic [31:0] s_gate_stat_d, s_gate_stat_q;
  logic [31:0] s_rst_req_d, s_rst_req_q;
  logic [31:0] s_reset_done_d, s_reset_done_q;
  logic [31:0] s_reset_cause_d, s_reset_cause_q;
  logic [31:0] s_rcu_fault_d, s_rcu_fault_q;
  logic [31:0] s_rcu_irq_state_d, s_rcu_irq_state_q;
  logic [31:0] s_rcu_irq_en_d, s_rcu_irq_en_q;
  logic [31:0] s_clkout_control_d, s_clkout_control_q;
  logic [31:0] s_sys_hz_d, s_sys_hz_q;
  logic [31:0] s_mem_hz_d, s_mem_hz_q;
  logic [31:0] s_pclk_hz_d, s_pclk_hz_q;
  logic [31:0] s_clkout_hz;

  logic s_rcu_selected, s_rcu_req, s_rcu_write, s_rcu_valid, s_rcu_writable, s_rcu_err;
  logic s_rcu_config_err;
  logic s_rcu_ready_d, s_rcu_ready_q, s_rcu_err_d, s_rcu_err_q;
  logic [31:0] s_rcu_offset, s_rcu_read_data, s_rcu_rdata_d, s_rcu_rdata_q;
  apb4_if u_rcu_src (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  apb4_if u_rcu_dst (
      .pclk   (clk_ref_i),
      .presetn(rst_ref_n_i)
  );

  assign s_rcu_selected    = apb4.paddr[11:8] == 4'h1;
  assign u_rcu_src.paddr   = apb4.paddr;
  assign u_rcu_src.pprot   = apb4.pprot;
  assign u_rcu_src.pwrite  = apb4.pwrite;
  assign u_rcu_src.pwdata  = apb4.pwdata;
  assign u_rcu_src.pstrb   = apb4.pstrb;
  assign u_rcu_src.psel    = apb4.psel && s_rcu_selected;
  assign u_rcu_src.penable = apb4.penable;
  tiny_apb_async_bridge u_rcu_cdc (
      .src_clk_i  (clk_i),
      .src_rst_n_i(rst_n_i),
      .dst_clk_i  (clk_ref_i),
      .dst_rst_n_i(rst_ref_n_i),
      .disabled_i (1'b0),
      .idle_o     (),
      .ready_o    (rcu_link_ready_o),
      .src_apb4   (u_rcu_src),
      .dst_apb4   (u_rcu_dst)
  );
  assign s_rcu_offset = {20'd0, u_rcu_dst.paddr[11:0]};
  assign s_rcu_req = u_rcu_dst.psel && u_rcu_dst.penable && !s_rcu_ready_q;
  assign s_rcu_err = (u_rcu_dst.paddr[1:0] != 0) || !s_rcu_valid ||
      (u_rcu_dst.pwrite && (!s_rcu_writable || u_rcu_dst.pstrb != 4'hf)) ||
      (!u_rcu_dst.pwrite && s_rcu_offset == RcuCommand) ||
      (u_rcu_dst.pwrite && s_rcu_config_err);
  assign s_rcu_write = s_rcu_req && u_rcu_dst.pwrite && !s_rcu_err;
  assign s_rcu_ready_d = s_rcu_req;
  assign s_rcu_err_d = s_rcu_req && s_rcu_err;
  assign s_rcu_rdata_d = s_rcu_req ? s_rcu_read_data : s_rcu_rdata_q;
  assign u_rcu_dst.pready = s_rcu_ready_q;
  assign u_rcu_dst.pslverr = s_rcu_err_q;
  assign u_rcu_dst.prdata = s_rcu_rdata_q;
  dffr #(
      .DATA_WIDTH(1)
  ) u_rcu_ready (
      .clk_i  (clk_ref_i),
      .rst_n_i(rst_ref_n_i),
      .dat_i  (s_rcu_ready_d),
      .dat_o  (s_rcu_ready_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_rcu_error (
      .clk_i  (clk_ref_i),
      .rst_n_i(rst_ref_n_i),
      .dat_i  (s_rcu_err_d),
      .dat_o  (s_rcu_err_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_rcu_rdata (
      .clk_i  (clk_ref_i),
      .rst_n_i(rst_ref_n_i),
      .dat_i  (s_rcu_rdata_d),
      .dat_o  (s_rcu_rdata_q)
  );

  assign s_offset = {20'd0, apb4.paddr[11:0]};
  assign s_req = apb4.psel && !s_rcu_selected && apb4.penable && !s_ready_q;
  assign s_write = s_req && apb4.pwrite && !s_access_err;
  assign s_access_err = (apb4.paddr[1:0] != 2'd0) || !s_valid ||
      (apb4.pwrite && (!s_writable || (apb4.pstrb != 4'hf))) ||
      (!apb4.pwrite && (s_offset == RcuCommand));
  assign s_ready_d = s_req;
  assign s_err_d = s_req && s_access_err;
  assign s_rdata_d = s_req ? s_read_data : s_rdata_q;
  assign apb4.pready = s_rcu_selected ? u_rcu_src.pready : s_ready_q;
  assign apb4.pslverr = s_rcu_selected ? u_rcu_src.pslverr : s_err_q;
  assign apb4.prdata = s_rcu_selected ? u_rcu_src.prdata : s_rdata_q;
  assign perf_enable_o = s_perf_en_q;
  assign perf_clear_o = s_write && (s_offset == `APB4_SYSCTRL__PERF_CTRL) && apb4.pwdata[1];
  assign test_done_o = s_test_q[31];
  assign test_pass_o = s_test_q[0];
  assign test_code_o = s_test_q[15:8];
  assign xin_hz_o = XinHzValue;
  assign ref_hz_o = 32'd24_000_000;
  assign sys_hz_o = s_sys_hz_q;
  assign mem_hz_o = s_mem_hz_q;
  assign pclk_hz_o = s_pclk_hz_q;
  assign clint_hz_o = 32'd1_000_000;
  assign rcu_current_o = s_clk_cur_q;
  assign rcu_busy_o = s_rcu_busy_q;
  assign clock_apply_o = s_clock_apply_q;
  assign clock_profile_o = s_clk_latched_q;
  assign clock_timeout_o = s_timeout_ref_q;
  assign clkout_control_o = s_clkout_control_q;
  assign s_clkout_hz = u_rcu_dst.pwdata[2:0] == 2 ? s_sys_hz_q :
      u_rcu_dst.pwdata[2:0] == 3 ? s_mem_hz_q :
      u_rcu_dst.pwdata[2:0] == 4 ? s_pclk_hz_q : 32'd24_000_000;
  assign periph_apply_o = s_periph_apply_q;
  assign periph_reset_o = s_periph_reset_q;
  assign periph_request_o = s_periph_mask_q;
  assign system_reset_o = s_system_reset_q;
  assign rcu_irq_o = |(s_rcu_irq_state_q[1:0] & s_rcu_irq_en_q[1:0]);

  always_comb begin
    s_valid     = 1'b1;
    s_writable  = 1'b0;
    s_read_data = '0;
    unique case (s_offset)
      `APB4_SYSCTRL__CORESEL, `APB4_SYSCTRL__IPSEL: s_read_data = '0;
      `APB4_SYSCTRL__USER_CORE_RESET:               s_read_data = 32'hffff_ffff;
      `APB4_SYSCTRL__USER_CORE_STATUS:              s_read_data = 32'h0000_0200;
      `APB4_SYSCTRL__FAULT_STATUS: begin
        s_read_data = {27'd0, s_fault_stat_q};
        s_writable  = 1'b1;
      end
      `APB4_SYSCTRL__FAULT_ADDR:                    s_read_data = s_fault_addr_q;
      `APB4_SYSCTRL__FAULT_COUNT:                   s_read_data = s_fault_count_q;
      `APB4_SYSCTRL__FAULT_MASTER:                  s_read_data = {30'd0, s_fault_master_q};
      `APB4_SYSCTRL__FAULT_DETAIL:                  s_read_data = {30'd0, s_fault_resp_q};
      `APB4_SYSCTRL__PERF_CTRL: begin
        s_read_data = {31'd0, s_perf_en_q};
        s_writable  = 1'b1;
      end
      `APB4_SYSCTRL__PERF_MGMT_WAIT_LO:             s_read_data = s_cpu_snapshot_q[31:0];
      `APB4_SYSCTRL__PERF_MGMT_WAIT_HI:             s_read_data = s_cpu_snapshot_q[63:32];
      `APB4_SYSCTRL__PERF_DMA_WAIT_LO:              s_read_data = s_dma_snapshot_q[31:0];
      `APB4_SYSCTRL__PERF_DMA_WAIT_HI:              s_read_data = s_dma_snapshot_q[63:32];
      `APB4_SYSCTRL__TEST_STATUS: begin
        s_read_data = s_test_q;
        s_writable  = 1'b1;
      end
      `APB4_SYSCTRL__RTC_WAKE_STATUS: begin
        s_read_data = {30'd0, s_wake_q, rtc_wake_i};
        s_writable  = 1'b1;
      end
      default:                                      s_valid = 1'b0;
    endcase
  end
  always_comb begin
    s_rcu_valid     = 1'b1;
    s_rcu_writable  = 1'b0;
    s_rcu_read_data = 32'd0;
    unique case (s_rcu_offset)
      RcuId: s_rcu_read_data = 32'h5452_4355;
      RcuVersion: s_rcu_read_data = 32'h0001_0000;
      // Advertise only the instantiated product backend and lifecycle paths.
      RcuCapability:
      s_rcu_read_data = 32'h0000_0201 |
          (PllPresent ? 32'h100 : 32'h2) | (PllProfiles ? 32'hc : 32'd0) |
          (TargetMask != 0 ? 32'h1800 : 32'd0);
      ClockRequest: begin
        s_rcu_read_data = {30'd0, s_clk_req_q};
        s_rcu_writable  = 1'b1;
      end
      ClockCurrent: s_rcu_read_data = {30'd0, s_clk_cur_q};
      RcuCommand: begin
        s_rcu_read_data = 32'd0;
        s_rcu_writable  = 1'b1;
      end
      RcuStatus: begin
        s_rcu_read_data       = 32'd0;
        s_rcu_read_data[0]    = s_rcu_busy_q;
        s_rcu_read_data[1]    = (s_clk_cur_q == 2'd0);
        s_rcu_read_data[2]    = pll_locked_i;
        s_rcu_read_data[3]    = pll_selected_i;
        s_rcu_read_data[4]    = |s_rcu_fault_q;
        s_rcu_read_data[11:8] = s_active_cmd_q;
      end
      TimeoutRefCycles: begin
        s_rcu_read_data = s_timeout_ref_q;
        s_rcu_writable  = 1'b1;
      end
      GateRequest: begin
        s_rcu_read_data = s_gate_req_q;
        s_rcu_writable  = 1'b1;
      end
      GateStatus: s_rcu_read_data = {18'd0, gate_actual_i};
      ResetRequest: begin
        s_rcu_read_data = s_rst_req_q;
        s_rcu_writable  = 1'b1;
      end
      ResetDone: s_rcu_read_data = s_reset_done_q;
      ResetCause: begin
        s_rcu_read_data = s_reset_cause_q;
        s_rcu_writable  = 1'b1;
      end
      RcuFault: begin
        s_rcu_read_data = s_rcu_fault_q;
        s_rcu_writable  = 1'b1;
      end
      RcuIrqState: begin
        s_rcu_read_data = s_rcu_irq_state_q;
        s_rcu_writable  = 1'b1;
      end
      RcuIrqEnable: begin
        s_rcu_read_data = s_rcu_irq_en_q;
        s_rcu_writable  = 1'b1;
      end
      XinHz: s_rcu_read_data = XinHzValue;
      RefHz: s_rcu_read_data = 32'd24_000_000;
      SysHz: s_rcu_read_data = s_sys_hz_q;
      MemHz: s_rcu_read_data = s_mem_hz_q;
      PclkHz: s_rcu_read_data = s_pclk_hz_q;
      ClintHz: s_rcu_read_data = 32'd1_000_000;
      TargetCapability: s_rcu_read_data = {18'd0, TargetMask};
      ClkoutControl: begin
        s_rcu_read_data = s_clkout_control_q;
        s_rcu_writable  = 1'b1;
      end
      default: s_rcu_valid = 1'b0;
    endcase
  end
  // Validate before generating a write strobe, so every rejected operation
  // returns PSLVERR and preserves staging as well as committed state.
  always_comb begin
    s_rcu_config_err = 1'b0;
    unique case (s_rcu_offset)
      ClockRequest: s_rcu_config_err = s_rcu_busy_q || u_rcu_dst.pwdata[31:2] != 0;
      TimeoutRefCycles: s_rcu_config_err = s_rcu_busy_q || u_rcu_dst.pwdata == 0;
      GateRequest:
      s_rcu_config_err = s_rcu_busy_q || (u_rcu_dst.pwdata & ~{18'd0, TargetMask}) != 0;
      ResetRequest:
      s_rcu_config_err = s_rcu_busy_q || (u_rcu_dst.pwdata & ~{18'd0, TargetMask[13:1], 1'b0}) != 0;
      ResetCause: s_rcu_config_err = u_rcu_dst.pwdata[31:6] != 0;
      RcuFault: s_rcu_config_err = u_rcu_dst.pwdata[31:5] != 0;
      RcuIrqState, RcuIrqEnable: s_rcu_config_err = u_rcu_dst.pwdata[31:2] != 0;
      RcuCommand: begin
        s_rcu_config_err = s_rcu_busy_q;
        unique case (u_rcu_dst.pwdata)
          32'd1:
          s_rcu_config_err |= s_clkout_control_q[2:0] != 0 || !clkout_idle_i ||
              !(s_clk_req_q == 0 || (s_clk_req_q == 1 && !PllPresent) ||
                (s_clk_req_q >= 2 && PllPresent && PllProfiles));
          32'd2: s_rcu_config_err |= TargetMask == 0 || (s_gate_req_q & ~{18'd0, TargetMask}) != 0;
          32'd4:
          s_rcu_config_err |= s_rst_req_q == 0 ||
              (s_rst_req_q & ~{18'd0, TargetMask[13:1], 1'b0}) != 0 ||
              (s_rst_req_q & {18'd0, gate_actual_i}) != 0;
          32'd8: begin
          end
          default: s_rcu_config_err = 1'b1;
        endcase
      end
      ClkoutControl:
      s_rcu_config_err = s_rcu_busy_q ||
          (u_rcu_dst.pwdata & 32'hff00_00f8) != 0 || u_rcu_dst.pwdata[2:0] > 4 ||
          (u_rcu_dst.pwdata[2:0] != 0 && (s_clkout_control_q[2:0] != 0 ||
           !clkout_idle_i || u_rcu_dst.pwdata[23:8] == 0 ||
           {32'd0, s_clkout_hz} > (64'd48_000_000 * {48'd0, u_rcu_dst.pwdata[23:8]})));
      default: begin
      end
    endcase
  end
  always_comb begin
    s_clk_req_d        = s_clk_req_q;
    s_clk_cur_d        = s_clk_cur_q;
    s_rcu_busy_d       = s_rcu_busy_q;
    s_clk_latched_d    = s_clk_latched_q;
    s_system_reset_d   = 1'b0;
    s_periph_apply_d   = 1'b0;
    s_periph_reset_d   = s_periph_reset_q;
    s_periph_mask_d    = s_periph_mask_q;
    s_active_cmd_d     = s_active_cmd_q;
    s_clock_apply_d    = 1'b0;
    s_timeout_ref_d    = s_timeout_ref_q;
    s_gate_req_d       = s_gate_req_q;
    s_gate_stat_d      = s_gate_stat_q;
    s_rst_req_d        = s_rst_req_q;
    s_reset_done_d     = s_reset_done_q;
    s_reset_cause_d    = s_reset_cause_q;
    s_rcu_fault_d      = s_rcu_fault_q;
    s_rcu_irq_state_d  = s_rcu_irq_state_q;
    s_rcu_irq_en_d     = s_rcu_irq_en_q;
    s_clkout_control_d = s_clkout_control_q;
    s_sys_hz_d         = s_sys_hz_q;
    s_mem_hz_d         = s_mem_hz_q;
    s_pclk_hz_d        = s_pclk_hz_q;
    if (s_rcu_write) begin
      unique case (s_rcu_offset)
        RcuCommand: begin
          if (s_rcu_busy_q || !(u_rcu_dst.pwdata == 1 || u_rcu_dst.pwdata == 2 ||
                               u_rcu_dst.pwdata == 4 || u_rcu_dst.pwdata == 8)) begin
            s_rcu_fault_d[0]     = 1'b1;
            s_rcu_irq_state_d[1] = 1'b1;
          end else if (u_rcu_dst.pwdata == 1) begin
            if (s_clkout_control_q[2:0] == 0 && clkout_idle_i &&
                (s_clk_req_q == 0 || (s_clk_req_q == 1 && !PllPresent) ||
                (s_clk_req_q >= 2 && PllPresent && PllProfiles))) begin
              s_clk_latched_d = s_clk_req_q;
              s_clock_apply_d = 1'b1;
              s_rcu_busy_d    = 1'b1;
              s_active_cmd_d  = 4'd1;
            end else begin
              s_rcu_fault_d[0]     = 1'b1;
              s_rcu_irq_state_d[1] = 1'b1;
            end
          end else if (u_rcu_dst.pwdata == 8) begin
            s_system_reset_d   = 1'b1;
            s_reset_cause_d[1] = 1'b1;
            s_rcu_busy_d       = 1'b1;
            s_active_cmd_d     = 4'd8;
          end else if (TargetMask != 0 && u_rcu_dst.pwdata == 2 &&
                       (s_gate_req_q & ~{18'd0, TargetMask}) == 0) begin
            s_periph_mask_d  = s_gate_req_q[13:0];
            s_periph_reset_d = 1'b0;
            s_periph_apply_d = 1'b1;
            s_rcu_busy_d     = 1'b1;
            s_active_cmd_d   = 4'd2;
          end else if (u_rcu_dst.pwdata == 4 && s_rst_req_q != 0 &&
                       (s_rst_req_q & ~{18'd0, TargetMask[13:1], 1'b0}) == 0 &&
                       (s_rst_req_q & {18'd0, gate_actual_i}) == 0) begin
            s_periph_mask_d  = s_rst_req_q[13:0];
            s_periph_reset_d = 1'b1;
            s_periph_apply_d = 1'b1;
            s_reset_done_d   = 0;
            s_rcu_busy_d     = 1'b1;
            s_active_cmd_d   = 4'd4;
          end else begin
            s_rcu_fault_d[0]     = 1'b1;
            s_rcu_irq_state_d[1] = 1'b1;
          end
        end
        ClockRequest: begin
          if (u_rcu_dst.pwdata[31:2] == 0) s_clk_req_d = u_rcu_dst.pwdata[1:0];
          else begin
            s_rcu_fault_d[0]     = 1'b1;
            s_rcu_irq_state_d[1] = 1'b1;
          end
        end
        TimeoutRefCycles: begin
          if (u_rcu_dst.pwdata != 0) s_timeout_ref_d = u_rcu_dst.pwdata;
          else begin
            s_rcu_fault_d[0]     = 1'b1;
            s_rcu_irq_state_d[1] = 1'b1;
          end
        end
        GateRequest:  s_gate_req_d = u_rcu_dst.pwdata;
        ResetRequest: s_rst_req_d = u_rcu_dst.pwdata;
        ResetCause:   s_reset_cause_d = s_reset_cause_q & ~u_rcu_dst.pwdata;
        RcuFault:     s_rcu_fault_d = s_rcu_fault_q & ~u_rcu_dst.pwdata;
        RcuIrqState:  s_rcu_irq_state_d = s_rcu_irq_state_q & ~u_rcu_dst.pwdata;
        RcuIrqEnable: s_rcu_irq_en_d = u_rcu_dst.pwdata & 32'd3;
        ClkoutControl: begin
          if (s_rcu_busy_q || (u_rcu_dst.pwdata & 32'hff00_00f8) != 0 ||
              u_rcu_dst.pwdata[2:0] > 4 ||
              (u_rcu_dst.pwdata[2:0] != 0 &&
               (s_clkout_control_q[2:0] != 0 || !clkout_idle_i || u_rcu_dst.pwdata[23:8] == 0 ||
                {32'd0, s_clkout_hz} > (64'd48_000_000 * {48'd0, u_rcu_dst.pwdata[23:8]})))) begin
            s_rcu_fault_d[0]     = 1'b1;
            s_rcu_irq_state_d[1] = 1'b1;
          end else s_clkout_control_d = u_rcu_dst.pwdata;
        end
        default: begin
        end
      endcase
    end
    if (clock_done_i) begin
      s_rcu_busy_d = 1'b0;
      s_active_cmd_d = 0;
      s_clk_cur_d = clock_current_i;
      s_sys_hz_d = clock_current_i == 2 ? 32'd192_000_000 :
          clock_current_i == 3 ? 32'd240_000_000 :
          clock_current_i == 1 ? 32'(XinHzValue) : 32'd24_000_000;
      s_mem_hz_d = s_sys_hz_d > 120_000_000 ? s_sys_hz_d / 2 : s_sys_hz_d;
      s_pclk_hz_d = s_sys_hz_d > 120_000_000 ? s_sys_hz_d / 4 :
          s_sys_hz_d > 60_000_000 ? s_sys_hz_d / 2 : s_sys_hz_d;
      s_rcu_irq_state_d[0] = 1'b1;
    end
    if (periph_done_i) begin
      s_rcu_busy_d   = 1'b0;
      s_active_cmd_d = 0;
      s_reset_done_d = {18'd0, reset_done_i};
      if (s_periph_reset_q && reset_done_i != 0) s_reset_cause_d[5] = 1'b1;
      s_rcu_irq_state_d[0] = 1'b1;
    end
    if (warm_reset_i) begin
      s_rcu_busy_d         = 1'b0;
      s_active_cmd_d       = 0;
      s_rcu_irq_en_d       = 0;
      s_rcu_irq_state_d[0] = 1'b0;
      s_clk_cur_d          = 0;
      s_clk_req_d          = 0;
      s_gate_req_d         = 0;
      s_gate_stat_d        = 0;
      s_rst_req_d          = 0;
      s_reset_done_d       = 0;
      s_periph_mask_d      = 0;
      s_periph_reset_d     = 1'b0;
      s_clkout_control_d   = 0;
      s_sys_hz_d           = 24_000_000;
      s_mem_hz_d           = 24_000_000;
      s_pclk_hz_d          = 24_000_000;
    end
    // Hardware set wins over W1C, including rejected APB operations.
    if (s_rcu_req && s_rcu_err) begin
      s_rcu_fault_d[0]     = 1'b1;
      s_rcu_irq_state_d[1] = 1'b1;
    end
    if (watchdog_reset_i) s_reset_cause_d[2] = 1'b1;
    if (clock_fault_i[3]) s_reset_cause_d[3] = 1'b1;
    if (hart_reset_i) s_reset_cause_d[4] = 1'b1;
    if ((clock_fault_i | periph_fault_i) != 0) begin
      s_rcu_fault_d        = s_rcu_fault_d | {27'd0, clock_fault_i | periph_fault_i};
      s_rcu_irq_state_d[1] = 1'b1;
    end
  end

  assign s_fault_sum = {1'b0, s_fault_count_q} + {29'd0, fault_count_i};
  always_comb begin
    s_test_d         = s_test_q;
    s_fault_addr_d   = s_fault_addr_q;
    s_fault_count_d  = s_fault_count_q;
    s_fault_stat_d   = s_fault_stat_q;
    s_fault_master_d = s_fault_master_q;
    s_fault_resp_d   = s_fault_resp_q;
    s_perf_en_d      = s_perf_en_q;
    s_wake_d         = s_wake_q;
    s_cpu_snapshot_d = s_cpu_snapshot_q;
    s_dma_snapshot_d = s_dma_snapshot_q;
    if (s_write) begin
      unique case ({
        20'd0, apb4.paddr[11:0]
      })
        `APB4_SYSCTRL__FAULT_STATUS: if (apb4.pwdata[0]) s_fault_stat_d[0] = 1'b0;
        `APB4_SYSCTRL__PERF_CTRL: begin
          s_perf_en_d = apb4.pwdata[0];
          if (apb4.pwdata[1]) begin
            s_cpu_snapshot_d = '0;
            s_dma_snapshot_d = '0;
          end else if (apb4.pwdata[2]) begin
            s_cpu_snapshot_d = cpu_wait_i;
            s_dma_snapshot_d = dma_wait_i;
          end
        end
        `APB4_SYSCTRL__TEST_STATUS:
        if (!s_test_q[31] && apb4.pwdata[31]) s_test_d = apb4.pwdata & 32'h8000_ff01;
        `APB4_SYSCTRL__RTC_WAKE_STATUS: if (apb4.pwdata[1]) s_wake_d = 1'b0;
        default: begin
        end
      endcase
    end
    if (rtc_wake_i) s_wake_d = 1'b1;
    if (fault_valid_i) begin
      s_fault_count_d = s_fault_sum[32] ? 32'hffff_ffff : s_fault_sum[31:0];
      if (!s_fault_stat_d[0]) begin
        s_fault_stat_d   = {(fault_resp_i == 2'b11) ? 3'd1 : 3'd2, fault_write_i, 1'b1};
        s_fault_addr_d   = fault_addr_i;
        s_fault_master_d = fault_master_i;
        s_fault_resp_d   = fault_resp_i;
      end
    end
  end
  dffr #(
      .DATA_WIDTH(32)
  ) u_test_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_test_d),
      .dat_o  (s_test_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_fault_addr_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fault_addr_d),
      .dat_o  (s_fault_addr_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_clock_latched (
      .clk_i  (clk_ref_i),
      .rst_n_i(rst_ref_n_i),
      .dat_i  (s_clk_latched_d),
      .dat_o  (s_clk_latched_q)
  );
  dffr #(
      .DATA_WIDTH(20)
  ) u_periph_command (
      .clk_i  (clk_ref_i),
      .rst_n_i(rst_ref_n_i),
      .dat_i  ({s_active_cmd_d, s_periph_mask_d, s_periph_reset_d, s_periph_apply_d}),
      .dat_o  ({s_active_cmd_q, s_periph_mask_q, s_periph_reset_q, s_periph_apply_q})
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_system_reset (
      .clk_i  (clk_ref_i),
      .rst_n_i(rst_ref_n_i),
      .dat_i  (s_system_reset_d),
      .dat_o  (s_system_reset_q)
  );
  dffr #(2) u_rcu_clock_request (
      .clk_i  (clk_ref_i),
      .rst_n_i(rst_ref_n_i),
      .dat_i  (s_clk_req_d),
      .dat_o  (s_clk_req_q)
  );
  dffr #(2) u_rcu_clock_current (
      .clk_i  (clk_ref_i),
      .rst_n_i(rst_ref_n_i),
      .dat_i  (s_clk_cur_d),
      .dat_o  (s_clk_cur_q)
  );
  dffr #(1) u_rcu_busy (
      .clk_i  (clk_ref_i),
      .rst_n_i(rst_ref_n_i),
      .dat_i  (s_rcu_busy_d),
      .dat_o  (s_rcu_busy_q)
  );
  dffr #(1) u_clock_apply (
      .clk_i  (clk_ref_i),
      .rst_n_i(rst_ref_n_i),
      .dat_i  (s_clock_apply_d),
      .dat_o  (s_clock_apply_q)
  );
  dffrc #(
      .DATA_WIDTH(32),
      .RESET_VAL (32'd240000)
  ) u_rcu_timeout (
      .clk_i  (clk_ref_i),
      .rst_n_i(rst_ref_n_i),
      .dat_i  (s_timeout_ref_d),
      .dat_o  (s_timeout_ref_q)
  );
  dffr #(32) u_rcu_gate_request (
      .clk_i  (clk_ref_i),
      .rst_n_i(rst_ref_n_i),
      .dat_i  (s_gate_req_d),
      .dat_o  (s_gate_req_q)
  );
  dffr #(32) u_rcu_gate_status (
      .clk_i  (clk_ref_i),
      .rst_n_i(rst_ref_n_i),
      .dat_i  (s_gate_stat_d),
      .dat_o  (s_gate_stat_q)
  );
  dffr #(32) u_rcu_reset_request (
      .clk_i  (clk_ref_i),
      .rst_n_i(rst_ref_n_i),
      .dat_i  (s_rst_req_d),
      .dat_o  (s_rst_req_q)
  );
  dffr #(32) u_rcu_reset_done (
      .clk_i  (clk_ref_i),
      .rst_n_i(rst_ref_n_i),
      .dat_i  (s_reset_done_d),
      .dat_o  (s_reset_done_q)
  );
  dffrc #(
      .DATA_WIDTH(32),
      .RESET_VAL (32'd1)
  ) u_rcu_reset_cause (
      .clk_i  (clk_ref_i),
      .rst_n_i(rst_ref_n_i),
      .dat_i  (s_reset_cause_d),
      .dat_o  (s_reset_cause_q)
  );
  dffr #(32) u_rcu_fault (
      .clk_i  (clk_ref_i),
      .rst_n_i(rst_ref_n_i),
      .dat_i  (s_rcu_fault_d),
      .dat_o  (s_rcu_fault_q)
  );
  dffr #(32) u_rcu_irq_state (
      .clk_i  (clk_ref_i),
      .rst_n_i(rst_ref_n_i),
      .dat_i  (s_rcu_irq_state_d),
      .dat_o  (s_rcu_irq_state_q)
  );
  dffr #(32) u_rcu_irq_enable (
      .clk_i  (clk_ref_i),
      .rst_n_i(rst_ref_n_i),
      .dat_i  (s_rcu_irq_en_d),
      .dat_o  (s_rcu_irq_en_q)
  );
  dffr #(32) u_rcu_clkout (
      .clk_i  (clk_ref_i),
      .rst_n_i(rst_ref_n_i),
      .dat_i  (s_clkout_control_d),
      .dat_o  (s_clkout_control_q)
  );
  dffrc #(
      .DATA_WIDTH(32),
      .RESET_VAL (32'd24000000)
  ) u_rcu_sys_hz (
      .clk_i  (clk_ref_i),
      .rst_n_i(rst_ref_n_i),
      .dat_i  (s_sys_hz_d),
      .dat_o  (s_sys_hz_q)
  );
  dffrc #(
      .DATA_WIDTH(32),
      .RESET_VAL (32'd24000000)
  ) u_rcu_mem_hz (
      .clk_i  (clk_ref_i),
      .rst_n_i(rst_ref_n_i),
      .dat_i  (s_mem_hz_d),
      .dat_o  (s_mem_hz_q)
  );
  dffrc #(
      .DATA_WIDTH(32),
      .RESET_VAL (32'd24000000)
  ) u_rcu_pclk_hz (
      .clk_i  (clk_ref_i),
      .rst_n_i(rst_ref_n_i),
      .dat_i  (s_pclk_hz_d),
      .dat_o  (s_pclk_hz_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_fault_count_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fault_count_d),
      .dat_o  (s_fault_count_q)
  );
  dffr #(
      .DATA_WIDTH(5)
  ) u_fault_status_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fault_stat_d),
      .dat_o  (s_fault_stat_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_fault_master_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fault_master_d),
      .dat_o  (s_fault_master_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_fault_resp_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fault_resp_d),
      .dat_o  (s_fault_resp_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_perf_enable_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_en_d),
      .dat_o  (s_perf_en_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_wake_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_wake_d),
      .dat_o  (s_wake_q)
  );
  dffr #(
      .DATA_WIDTH(64)
  ) u_cpu_snapshot_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_cpu_snapshot_d),
      .dat_o  (s_cpu_snapshot_q)
  );
  dffr #(
      .DATA_WIDTH(64)
  ) u_dma_snapshot_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_dma_snapshot_d),
      .dat_o  (s_dma_snapshot_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_ready_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ready_d),
      .dat_o  (s_ready_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_error_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_d),
      .dat_o  (s_err_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_rdata_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rdata_d),
      .dat_o  (s_rdata_q)
  );
endmodule
