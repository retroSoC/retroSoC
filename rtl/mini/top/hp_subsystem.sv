// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module hp_subsystem (
    // verilog_format: off -- preserve HP integration boundary alignment
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        core_reset_i,
    input  logic [63:0] time_i,
    input  logic        timer_irq_i,
    input  logic        software_irq_i,
    input  logic        machine_external_irq_i,
    input  logic        supervisor_external_irq_i,
    input  logic        jtag_tck_i,
    input  logic        jtag_tms_i,
    input  logic        jtag_tdi_i,
    input  logic        jtag_trst_n_i,
    output logic        jtag_tdo_o,
    output logic        debug_reset_req_o,
    axi4_if.master      axi4
    // verilog_format: on
);
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) u_icache_wide_axi4_if (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) u_dcache_wide_axi4_if (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) u_mmio_wide_axi4_if (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_icache_narrow_axi4_if (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_dcache_narrow_axi4_if (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_mmio_narrow_axi4_if (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_hp_mux_axi4_if (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  hp_core_wrapper u_hp_core_wrapper (
      .clk_i                    (clk_i),
      .rst_n_i                  (rst_n_i),
      .core_reset_i             (core_reset_i),
      .time_i                   (time_i),
      .timer_irq_i              (timer_irq_i),
      .software_irq_i           (software_irq_i),
      .machine_external_irq_i   (machine_external_irq_i),
      .supervisor_external_irq_i(supervisor_external_irq_i),
      .jtag_tck_i               (jtag_tck_i),
      .jtag_tms_i               (jtag_tms_i),
      .jtag_tdi_i               (jtag_tdi_i),
      .jtag_trst_n_i            (jtag_trst_n_i),
      .jtag_tdo_o               (jtag_tdo_o),
      .debug_reset_req_o        (debug_reset_req_o),
      .icache_axi4              (u_icache_wide_axi4_if),
      .dcache_axi4              (u_dcache_wide_axi4_if),
      .mmio_axi4                (u_mmio_wide_axi4_if)
  );

  axi4_downsizer_64to32 u_icache_downsizer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .wide   (u_icache_wide_axi4_if),
      .narrow (u_icache_narrow_axi4_if)
  );
  axi4_downsizer_64to32 u_dcache_downsizer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .wide   (u_dcache_wide_axi4_if),
      .narrow (u_dcache_narrow_axi4_if)
  );
  axi4_downsizer_64to32 u_mmio_downsizer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .wide   (u_mmio_wide_axi4_if),
      .narrow (u_mmio_narrow_axi4_if)
  );

  hp_axi4_mux3 u_hp_axi4_mux3 (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .icache (u_icache_narrow_axi4_if),
      .dcache (u_dcache_narrow_axi4_if),
      .mmio   (u_mmio_narrow_axi4_if),
      .axi4   (u_hp_mux_axi4_if)
  );

  axi4_regslice #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1),
      .BYPASS    (1'b0)
  ) u_hp_axi4_regslice (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(core_reset_i),
      .slv    (u_hp_mux_axi4_if),
      .mst    (axi4)
  );
endmodule
