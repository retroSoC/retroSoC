// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0
`include "sysctrl_define.svh"

module tiny_sysctrl (
    input  logic                clk_i,
    input  logic                rst_n_i,
           apb4_if.slave        apb4,
    input  logic                fault_valid_i,
    input  logic         [31:0] fault_addr_i,
    input  logic                fault_write_i,
    input  logic                fault_master_i,
    input  logic         [ 1:0] fault_resp_i,
    input  logic         [63:0] cpu_wait_i,
    input  logic         [63:0] dma_wait_i,
    input  logic                rtc_wake_i,
    output logic                perf_enable_o,
    output logic                perf_clear_o,
    output logic                test_done_o,
    output logic                test_pass_o,
    output logic         [ 7:0] test_code_o
);
  logic [31:0] s_test_d, s_test_q;
  logic [31:0] s_fault_addr_d, s_fault_addr_q;
  logic [31:0] s_fault_count_d, s_fault_count_q;
  logic [4:0] s_fault_stat_d, s_fault_stat_q;
  logic s_fault_master_d, s_fault_master_q;
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

  assign s_offset = {20'd0, apb4.paddr[11:0]};
  assign s_req = apb4.psel && apb4.penable && !s_ready_q;
  assign s_write = s_req && apb4.pwrite && !s_access_err;
  assign s_access_err = (apb4.paddr[1:0] != 2'd0) || !s_valid ||
      (apb4.pwrite && (!s_writable || (apb4.pstrb != 4'hf)));
  assign s_ready_d = s_req;
  assign s_err_d = s_req && s_access_err;
  assign s_rdata_d = s_req ? s_read_data : s_rdata_q;
  assign apb4.pready = s_ready_q;
  assign apb4.pslverr = s_err_q;
  assign apb4.prdata = s_rdata_q;
  assign perf_enable_o = s_perf_en_q;
  assign perf_clear_o = s_write && (s_offset == `APB4_SYSCTRL__PERF_CTRL) && apb4.pwdata[1];
  assign test_done_o = s_test_q[31];
  assign test_pass_o = s_test_q[0];
  assign test_code_o = s_test_q[15:8];

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
      `APB4_SYSCTRL__FAULT_MASTER:                  s_read_data = {31'd0, s_fault_master_q};
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
      if (s_fault_count_q != 32'hffff_ffff) s_fault_count_d = s_fault_count_q + 32'd1;
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
      .DATA_WIDTH(1)
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
