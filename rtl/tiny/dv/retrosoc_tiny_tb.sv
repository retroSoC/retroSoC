// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0
`timescale 1ns / 1ps

module retrosoc_tiny_tb;
  logic s_clk_driver = 1'b0;
  wire  s_clk = s_clk_driver;
  logic s_reset_driver = 1'b0;
  wire  s_rst_n = s_reset_driver;
  wire s_uart0_tx, s_uart1_tx;
  wire           s_uart0_rx = 1'b1;
  wire           s_uart1_rx = 1'b1;
  logic          s_jtag_tck_driver = 1'b0;
  logic          s_jtag_tms_driver = 1'b1;
  logic          s_jtag_tdi_driver = 1'b0;
  wire           s_jtag_tck = s_jtag_tck_driver;
  wire           s_jtag_tms = s_jtag_tms_driver;
  wire           s_jtag_tdi = s_jtag_tdi_driver;
  wire           s_jtag_trst_n = s_rst_n;
  wire           s_jtag_tdo;
  tri1    [31:0] s_gpio;
  wire           s_xpi_sck;
  wire    [ 3:0] s_xpi_nss;
  tri     [ 3:0] s_xpi_data;
  integer        s_cycles;
  integer        s_max_cycles = 20000000;
  integer        s_done_cycles = 0;
  logic   [ 7:0] s_uart_byte;
  `include "tiny_jtag_smoke.svh"

`ifdef RETROSOC_SOC__TINY_NETLIST
  wire [7:0] s_test_code = {
    u_dut.s_test_code_7_,
    u_dut.s_test_code_6_,
    u_dut.s_test_code_5_,
    u_dut.s_test_code_4_,
    u_dut.s_test_code_3_,
    u_dut.s_test_code_2_,
    u_dut.s_test_code_1_,
    u_dut.s_test_code_0_
  };
`else
  wire [7:0] s_test_code = u_dut.s_test_code;
`endif

  always #20.833333 s_clk_driver = !s_clk_driver;
  initial begin
    if ($value$plusargs("max_cycles=%d", s_max_cycles)) begin
    end
    repeat (20) @(posedge s_clk);
    @(negedge s_clk);
    s_reset_driver = 1'b1;
    for (s_cycles = 0; s_cycles < s_max_cycles; s_cycles = s_cycles + 1) begin
      @(posedge s_clk);
      if (u_dut.s_test_done) begin
        if (!u_dut.s_test_pass) $fatal(1, "SIM_TEST_FAIL code=%0d", s_test_code);
        s_done_cycles = s_done_cycles + 1;
        if (s_done_cycles >= 128 && s_jtag_checks_done) begin
          $display("SIM_TEST_PASS Tiny cycles=%0d", s_cycles);
          $finish;
        end
      end
    end
    if (s_done_cycles != 128) $fatal(1, "SIM_TEST_TIMEOUT Tiny cycles=%0d", s_cycles);
  end

`ifdef RETROSOC_SOC__TINY_NETLIST
  localparam bit ObserveUartAlways = 1'b1;
`else
  localparam bit ObserveUartAlways = 1'b0;
`endif
`ifdef SIMU_IVERILOG
  localparam bit ObserveUartBaseline = 1'b1;
`else
  localparam bit ObserveUartBaseline = 1'b0;
`endif
  // The Verilator RTL already prints accepted TX bytes. The Icarus observer is
  // opt-in for measurements; SYSCTRL remains the authoritative verdict.
  initial begin
    if (ObserveUartAlways || (ObserveUartBaseline && ($test$plusargs(
            "tiny_r2_baseline"
        ) || $test$plusargs(
            "tiny_r2_p3"
        )))) begin
      forever begin
        @(negedge s_uart0_tx);
        #1627.604;
        for (int bit_index = 0; bit_index < 8; bit_index++) begin
          s_uart_byte[bit_index] = s_uart0_tx;
          #1085.069;
        end
        $write("%c", s_uart_byte);
      end
    end
  end


`ifndef RETROSOC_SOC__TINY_NETLIST
  // Verification-only R2-P1 instrumentation. PERF_CTRL retains its existing
  // software meaning; its enable selects the observation window. No design
  // signal is driven, and the ordinary acceptance path leaves this disabled.
  logic s_baseline_enabled = 1'b0;
  logic [31:0] s_baseline_tcd_base, s_baseline_tcd_end;
  initial begin
    s_baseline_enabled = $test$plusargs("tiny_r2_baseline") || $test$plusargs("tiny_r2_p3");
    if (s_baseline_enabled) begin
      if (!$value$plusargs(
              "baseline_tcd_base=%h", s_baseline_tcd_base
          ) || !$value$plusargs(
              "baseline_tcd_end=%h", s_baseline_tcd_end
          ) || (s_baseline_tcd_end <= s_baseline_tcd_base)) begin
        $fatal(1, "SIM_TEST_FAIL missing baseline descriptor range");
      end
    end
  end

  // Address acceptance and terminal response are distinct events. A CPU
  // transaction can straddle PERF_CTRL itself; pending counts explicitly mark
  // the right-censored window instead of inventing its completion latency.
  for (genvar owner = 0; owner < 2; owner++) begin : gen_baseline_axi
    longint unsigned s_cycle = 0;
    longint unsigned s_window_cycles = 0;
    longint unsigned s_read_start, s_write_start;
    longint unsigned s_reads, s_writes, s_read_done, s_write_done;
    longint unsigned s_read_bytes, s_write_bytes, s_descriptor_bytes;
    longint unsigned s_read_latency, s_write_latency;
    longint unsigned s_stall_run[5], s_stall_max[5];
    logic s_previous_enable = 1'b0;
    logic s_read_measured = 1'b0, s_write_measured = 1'b0;
    logic         s_descriptor_read = 1'b0;
    logic   [2:0] s_read_size;
    integer       s_window = 0;
    wire          s_enable = u_dut.u_soc.s_perf_enable && s_baseline_enabled;
    `define _BASELINE_AXI u_dut.u_soc.u_masters_axi4_if[owner]
    wire [4:0] s_stalls = {
      `_BASELINE_AXI.rvalid && !`_BASELINE_AXI.rready,
      `_BASELINE_AXI.arvalid && !`_BASELINE_AXI.arready,
      `_BASELINE_AXI.bvalid && !`_BASELINE_AXI.bready,
      `_BASELINE_AXI.wvalid && !`_BASELINE_AXI.wready,
      `_BASELINE_AXI.awvalid && !`_BASELINE_AXI.awready
    };

    always @(posedge s_clk) begin
      s_cycle = s_cycle + 1;
      if (!u_dut.u_soc.s_rst_n) begin
        s_previous_enable = 1'b0;
        s_read_measured   = 1'b0;
        s_write_measured  = 1'b0;
        s_window          = 0;
      end else if (s_baseline_enabled) begin
        if (s_enable && !s_previous_enable) begin
          s_window           = s_window + 1;
          s_window_cycles    = 0;
          s_reads            = 0;
          s_writes           = 0;
          s_read_done        = 0;
          s_write_done       = 0;
          s_read_bytes       = 0;
          s_write_bytes      = 0;
          s_descriptor_bytes = 0;
          s_read_latency     = 0;
          s_write_latency    = 0;
          s_read_measured    = 1'b0;
          s_write_measured   = 1'b0;
          for (int channel = 0; channel < 5; channel++) begin
            s_stall_run[channel] = 0;
            s_stall_max[channel] = 0;
          end
        end
        if (s_enable) begin
          s_window_cycles = s_window_cycles + 1;
          for (int channel = 0; channel < 5; channel++) begin
            s_stall_run[channel] = s_stalls[channel] ? s_stall_run[channel] + 1 : 0;
            if (s_stall_run[channel] > s_stall_max[channel])
              s_stall_max[channel] = s_stall_run[channel];
          end
          if (`_BASELINE_AXI.arvalid && `_BASELINE_AXI.arready) begin
            s_reads = s_reads + 1;
            s_read_start = s_cycle;
            s_read_size = `_BASELINE_AXI.arsize;
            s_read_measured = 1'b1;
            s_descriptor_read = (owner == 1) &&
                (`_BASELINE_AXI.araddr >= s_baseline_tcd_base) &&
                (`_BASELINE_AXI.araddr < s_baseline_tcd_end);
          end
          if (`_BASELINE_AXI.awvalid && `_BASELINE_AXI.awready) begin
            s_writes         = s_writes + 1;
            s_write_start    = s_cycle;
            s_write_measured = 1'b1;
          end
          if (`_BASELINE_AXI.rvalid && `_BASELINE_AXI.rready && s_read_measured) begin
            if (s_descriptor_read) s_descriptor_bytes = s_descriptor_bytes + (64'd1 << s_read_size);
            else s_read_bytes = s_read_bytes + (64'd1 << s_read_size);
            if (`_BASELINE_AXI.rlast) begin
              s_read_done = s_read_done + 1;
              if ((s_cycle - s_read_start) > s_read_latency)
                s_read_latency = s_cycle - s_read_start;
              s_read_measured = 1'b0;
            end
          end
          if (`_BASELINE_AXI.wvalid && `_BASELINE_AXI.wready && s_write_measured) begin
            for (int lane = 0; lane < 4; lane++) begin
              if (`_BASELINE_AXI.wstrb[lane]) s_write_bytes = s_write_bytes + 1;
            end
          end
          if (`_BASELINE_AXI.bvalid && `_BASELINE_AXI.bready && s_write_measured) begin
            s_write_done = s_write_done + 1;
            if ((s_cycle - s_write_start) > s_write_latency)
              s_write_latency = s_cycle - s_write_start;
            s_write_measured = 1'b0;
          end
        end
        if (!s_enable && s_previous_enable) begin
          // No timing control occurs between writes, so one observer emits
          // one complete record without interleaving another observer's line.
          $write("R2_AXI window=%0d owner=%0d cycles=%0d reads=%0d writes=%0d ", s_window, owner,
                 s_window_cycles, s_reads, s_writes);
          $write("read_done=%0d write_done=%0d read_bytes=%0d write_bytes=%0d ", s_read_done,
                 s_write_done, s_read_bytes, s_write_bytes);
          $write("descriptor_bytes=%0d read_latency_max=%0d write_latency_max=%0d ",
                 s_descriptor_bytes, s_read_latency, s_write_latency);
          $write("aw_stall_max=%0d w_stall_max=%0d b_stall_max=%0d ", s_stall_max[0],
                 s_stall_max[1], s_stall_max[2]);
          $display("ar_stall_max=%0d r_stall_max=%0d pending_reads=%0d pending_writes=%0d",
                   s_stall_max[3], s_stall_max[4], s_read_measured, s_write_measured);
        end
        s_previous_enable = s_enable;
      end
    end
    `undef _BASELINE_AXI
  end

  // Verification-only per-group issue/conflict accounting. A bank conflict is
  // two or more eligible macro clients in one cycle, not an AXI address stall.
  for (genvar group = 0; group < 4; group++) begin : gen_bank_observer
    longint unsigned s_issues[3], s_waits[3];
    longint unsigned       s_conflicts = 0;
    logic                  s_previous_enable = 0;
    integer                s_window = 0;
    wire                   s_enable = u_dut.u_soc.s_perf_enable && s_baseline_enabled;
    wire             [2:0] s_req = u_dut.u_soc.u_sram.gen_group[group].u_group.s_req;
    wire             [2:0] s_grant = u_dut.u_soc.u_sram.gen_group[group].u_group.s_grant;
    always @(posedge s_clk) begin
      if (!u_dut.u_soc.s_rst_n) begin
        s_previous_enable = 0;
        s_window          = 0;
      end else if (s_baseline_enabled) begin
        if (s_enable && !s_previous_enable) begin
          s_window    = s_window + 1;
          s_conflicts = 0;
          for (int client = 0; client < 3; client++) begin
            s_issues[client] = 0;
            s_waits[client]  = 0;
          end
        end
        if (s_enable) begin
          if ((s_req & (s_req - 3'd1)) != 3'd0) s_conflicts = s_conflicts + 1;
          for (int client = 0; client < 3; client++) begin
            if (s_grant[client]) s_issues[client] = s_issues[client] + 1;
            if (s_req[client] && !s_grant[client]) s_waits[client] = s_waits[client] + 1;
          end
        end
        if (!s_enable && s_previous_enable)
          $display(
              "R2_P4_BANK window=%0d group=%0d issues_i=%0d issues_d=%0d issues_external=%0d conflicts=%0d wait_i=%0d wait_d=%0d wait_external=%0d",
              s_window,
              group,
              s_issues[0],
              s_issues[1],
              s_issues[2],
              s_conflicts,
              s_waits[0],
              s_waits[1],
              s_waits[2]
          );
        s_previous_enable = s_enable;
      end
    end
  end

  // P4 retains the original per-kind record format, now observed on two
  // independent ports. External AXI counts remain external traffic only.
  for (genvar port_index = 0; port_index < 2; port_index++) begin : gen_ahb_observer
    longint unsigned s_cycle = 0, s_start = 0;
    longint unsigned s_accepted = 0, s_completed = 0, s_latency = 0;
    longint unsigned s_local_accepted = 0, s_local_completed = 0, s_local_latency = 0;
    longint unsigned s_admission_wait = 0;
    logic s_pending = 0, s_measured = 0, s_local = 0, s_previous_enable = 0;
    integer s_window = 0;
    wire    s_enable = u_dut.u_soc.s_perf_enable && s_baseline_enabled;
    `define _P4_AHB u_dut.u_soc.u_cpu_ahbl_if[port_index]
    always @(posedge s_clk) begin
      s_cycle = s_cycle + 1;
      if (!u_dut.u_soc.s_core_rst_n) begin
        s_pending         = 0;
        s_measured        = 0;
        s_previous_enable = 0;
        s_window          = 0;
      end else if (s_baseline_enabled) begin
        if (s_enable && !s_previous_enable) begin
          s_window          = s_window + 1;
          s_measured        = 0;
          s_accepted        = 0;
          s_completed       = 0;
          s_latency         = 0;
          s_local_accepted  = 0;
          s_local_completed = 0;
          s_local_latency   = 0;
          s_admission_wait  = 0;
        end
        if (s_enable && `_P4_AHB.htrans[1] && !`_P4_AHB.hready)
          s_admission_wait = s_admission_wait + 1;
        if (`_P4_AHB.hready) begin
          if (s_pending && s_measured && s_enable) begin
            s_completed = s_completed + 1;
            if ((s_cycle - s_start) > s_latency) s_latency = s_cycle - s_start;
            if (s_local) begin
              s_local_completed = s_local_completed + 1;
              if ((s_cycle - s_start) > s_local_latency) s_local_latency = s_cycle - s_start;
            end
          end
          s_pending  = `_P4_AHB.htrans[1];
          s_measured = s_pending && s_enable;
          if (s_measured) begin
            s_start    = s_cycle;
            s_accepted = s_accepted + 1;
            s_local    = (`_P4_AHB.haddr >= 32'h30000000) && (`_P4_AHB.haddr < 32'h30020000);
            if (s_local) s_local_accepted = s_local_accepted + 1;
          end
        end
        if (!s_enable && s_previous_enable) begin
          $display("R2_AHB window=%0d kind=%0d accepted=%0d completed=%0d latency_max=%0d",
                   s_window, port_index, s_accepted, s_completed, s_latency);
          $display(
              "R2_P4_LOCAL window=%0d port=%0d accepted=%0d completed=%0d latency_max=%0d admission_wait=%0d",
              s_window, port_index, s_local_accepted, s_local_completed, s_local_latency,
              s_admission_wait);
        end
        s_previous_enable = s_enable;
      end
    end
    `undef _P4_AHB
  end
`endif

  retrosoc_tiny_asic u_dut (
      `include "retrosoc_asic_tb_bindings.svh"
  );
  tiny_qspi_nor u_flash (
      .sck_i  (s_xpi_sck),
      .cs_n_i (s_xpi_nss[0]),
      .data_io(s_xpi_data)
  );
endmodule
