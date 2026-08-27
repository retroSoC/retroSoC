// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "axi4_define.svh"

module hp_core_wrapper (
    // verilog_format: off -- preserve generated-core boundary alignment
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
    axi4_if.master      icache_axi4,
    axi4_if.master      dcache_axi4,
    axi4_if.master      mmio_axi4
    // verilog_format: on
);
  logic s_unused_debug_stoptime;

  assign icache_axi4.awid     = '0;
  assign icache_axi4.awaddr   = '0;
  assign icache_axi4.awlen    = '0;
  assign icache_axi4.awsize   = '0;
  assign icache_axi4.awburst  = '0;
  assign icache_axi4.awlock   = '0;
  assign icache_axi4.awcache  = '0;
  assign icache_axi4.awprot   = '0;
  assign icache_axi4.awqos    = '0;
  assign icache_axi4.awregion = '0;
  assign icache_axi4.awuser   = '0;
  assign icache_axi4.awvalid  = 1'b0;
  assign icache_axi4.wdata    = '0;
  assign icache_axi4.wstrb    = '0;
  assign icache_axi4.wlast    = 1'b0;
  assign icache_axi4.wuser    = '0;
  assign icache_axi4.wvalid   = 1'b0;
  assign icache_axi4.bready   = 1'b1;

  // verilog_format: off -- generated VexiiRiscv ports are upstream ABI
  vexii_riscv_hp_generated u_vexii_riscv_hp_generated (
      .EmbeddedRiscvJtag_logic_jtag_tms                         (jtag_tms_i),
      .EmbeddedRiscvJtag_logic_jtag_tdi                         (jtag_tdi_i),
      .EmbeddedRiscvJtag_logic_jtag_tdo                         (jtag_tdo_o),
      .EmbeddedRiscvJtag_logic_jtag_tck                         (jtag_tck_i),
      .EmbeddedRiscvJtag_logic_ndmreset                         (debug_reset_req_o),
      .LsuL1Axi4Plugin_logic_axi_aw_valid                       (dcache_axi4.awvalid),
      .LsuL1Axi4Plugin_logic_axi_aw_ready                       (dcache_axi4.awready),
      .LsuL1Axi4Plugin_logic_axi_aw_payload_addr                (dcache_axi4.awaddr),
      .LsuL1Axi4Plugin_logic_axi_aw_payload_id                  (dcache_axi4.awid),
      .LsuL1Axi4Plugin_logic_axi_aw_payload_len                 (dcache_axi4.awlen),
      .LsuL1Axi4Plugin_logic_axi_aw_payload_size                (dcache_axi4.awsize),
      .LsuL1Axi4Plugin_logic_axi_aw_payload_burst               (dcache_axi4.awburst),
      .LsuL1Axi4Plugin_logic_axi_aw_payload_cache               (dcache_axi4.awcache),
      .LsuL1Axi4Plugin_logic_axi_aw_payload_prot                (dcache_axi4.awprot),
      .LsuL1Axi4Plugin_logic_axi_w_valid                        (dcache_axi4.wvalid),
      .LsuL1Axi4Plugin_logic_axi_w_ready                        (dcache_axi4.wready),
      .LsuL1Axi4Plugin_logic_axi_w_payload_data                 (dcache_axi4.wdata),
      .LsuL1Axi4Plugin_logic_axi_w_payload_strb                 (dcache_axi4.wstrb),
      .LsuL1Axi4Plugin_logic_axi_w_payload_last                 (dcache_axi4.wlast),
      .LsuL1Axi4Plugin_logic_axi_b_valid                        (dcache_axi4.bvalid),
      .LsuL1Axi4Plugin_logic_axi_b_ready                        (dcache_axi4.bready),
      .LsuL1Axi4Plugin_logic_axi_b_payload_id                   (dcache_axi4.bid),
      .LsuL1Axi4Plugin_logic_axi_b_payload_resp                 (dcache_axi4.bresp),
      .LsuL1Axi4Plugin_logic_axi_ar_valid                       (dcache_axi4.arvalid),
      .LsuL1Axi4Plugin_logic_axi_ar_ready                       (dcache_axi4.arready),
      .LsuL1Axi4Plugin_logic_axi_ar_payload_addr                (dcache_axi4.araddr),
      .LsuL1Axi4Plugin_logic_axi_ar_payload_id                  (dcache_axi4.arid),
      .LsuL1Axi4Plugin_logic_axi_ar_payload_len                 (dcache_axi4.arlen),
      .LsuL1Axi4Plugin_logic_axi_ar_payload_size                (dcache_axi4.arsize),
      .LsuL1Axi4Plugin_logic_axi_ar_payload_burst               (dcache_axi4.arburst),
      .LsuL1Axi4Plugin_logic_axi_ar_payload_cache               (dcache_axi4.arcache),
      .LsuL1Axi4Plugin_logic_axi_ar_payload_prot                (dcache_axi4.arprot),
      .LsuL1Axi4Plugin_logic_axi_r_valid                        (dcache_axi4.rvalid),
      .LsuL1Axi4Plugin_logic_axi_r_ready                        (dcache_axi4.rready),
      .LsuL1Axi4Plugin_logic_axi_r_payload_data                 (dcache_axi4.rdata),
      .LsuL1Axi4Plugin_logic_axi_r_payload_id                   (dcache_axi4.rid),
      .LsuL1Axi4Plugin_logic_axi_r_payload_resp                 (dcache_axi4.rresp),
      .LsuL1Axi4Plugin_logic_axi_r_payload_last                 (dcache_axi4.rlast),
      .PrivilegedPlugin_logic_rdtime                            (time_i),
      .PrivilegedPlugin_logic_harts_0_int_m_timer               (timer_irq_i),
      .PrivilegedPlugin_logic_harts_0_int_m_software            (software_irq_i),
      .PrivilegedPlugin_logic_harts_0_int_m_external            (machine_external_irq_i),
      .PrivilegedPlugin_logic_harts_0_int_s_external            (supervisor_external_irq_i),
      .FetchL1Axi4Plugin_logic_axi_ar_valid                     (icache_axi4.arvalid),
      .FetchL1Axi4Plugin_logic_axi_ar_ready                     (icache_axi4.arready),
      .FetchL1Axi4Plugin_logic_axi_ar_payload_addr              (icache_axi4.araddr),
      .FetchL1Axi4Plugin_logic_axi_ar_payload_id                (icache_axi4.arid[0]),
      .FetchL1Axi4Plugin_logic_axi_ar_payload_len               (icache_axi4.arlen),
      .FetchL1Axi4Plugin_logic_axi_ar_payload_size              (icache_axi4.arsize),
      .FetchL1Axi4Plugin_logic_axi_ar_payload_burst             (icache_axi4.arburst),
      .FetchL1Axi4Plugin_logic_axi_ar_payload_cache             (icache_axi4.arcache),
      .FetchL1Axi4Plugin_logic_axi_ar_payload_prot              (icache_axi4.arprot),
      .FetchL1Axi4Plugin_logic_axi_r_valid                      (icache_axi4.rvalid),
      .FetchL1Axi4Plugin_logic_axi_r_ready                      (icache_axi4.rready),
      .FetchL1Axi4Plugin_logic_axi_r_payload_data               (icache_axi4.rdata),
      .FetchL1Axi4Plugin_logic_axi_r_payload_id                 (icache_axi4.rid[0]),
      .FetchL1Axi4Plugin_logic_axi_r_payload_resp               (icache_axi4.rresp),
      .FetchL1Axi4Plugin_logic_axi_r_payload_last               (icache_axi4.rlast),
      .PrivilegedPlugin_logic_harts_0_debug_stoptime            (s_unused_debug_stoptime),
      .LsuCachelessAxi4Plugin_logic_axi_aw_valid                (mmio_axi4.awvalid),
      .LsuCachelessAxi4Plugin_logic_axi_aw_ready                (mmio_axi4.awready),
      .LsuCachelessAxi4Plugin_logic_axi_aw_payload_addr         (mmio_axi4.awaddr),
      .LsuCachelessAxi4Plugin_logic_axi_aw_payload_size         (mmio_axi4.awsize),
      .LsuCachelessAxi4Plugin_logic_axi_aw_payload_cache        (mmio_axi4.awcache),
      .LsuCachelessAxi4Plugin_logic_axi_aw_payload_prot         (mmio_axi4.awprot),
      .LsuCachelessAxi4Plugin_logic_axi_w_valid                 (mmio_axi4.wvalid),
      .LsuCachelessAxi4Plugin_logic_axi_w_ready                 (mmio_axi4.wready),
      .LsuCachelessAxi4Plugin_logic_axi_w_payload_data          (mmio_axi4.wdata),
      .LsuCachelessAxi4Plugin_logic_axi_w_payload_strb          (mmio_axi4.wstrb),
      .LsuCachelessAxi4Plugin_logic_axi_w_payload_last          (mmio_axi4.wlast),
      .LsuCachelessAxi4Plugin_logic_axi_b_valid                 (mmio_axi4.bvalid),
      .LsuCachelessAxi4Plugin_logic_axi_b_ready                 (mmio_axi4.bready),
      .LsuCachelessAxi4Plugin_logic_axi_b_payload_resp          (mmio_axi4.bresp),
      .LsuCachelessAxi4Plugin_logic_axi_ar_valid                (mmio_axi4.arvalid),
      .LsuCachelessAxi4Plugin_logic_axi_ar_ready                (mmio_axi4.arready),
      .LsuCachelessAxi4Plugin_logic_axi_ar_payload_addr         (mmio_axi4.araddr),
      .LsuCachelessAxi4Plugin_logic_axi_ar_payload_size         (mmio_axi4.arsize),
      .LsuCachelessAxi4Plugin_logic_axi_ar_payload_cache        (mmio_axi4.arcache),
      .LsuCachelessAxi4Plugin_logic_axi_ar_payload_prot         (mmio_axi4.arprot),
      .LsuCachelessAxi4Plugin_logic_axi_r_valid                 (mmio_axi4.rvalid),
      .LsuCachelessAxi4Plugin_logic_axi_r_ready                 (mmio_axi4.rready),
      .LsuCachelessAxi4Plugin_logic_axi_r_payload_data          (mmio_axi4.rdata),
      .LsuCachelessAxi4Plugin_logic_axi_r_payload_resp          (mmio_axi4.rresp),
      .LsuCachelessAxi4Plugin_logic_axi_r_payload_last          (mmio_axi4.rlast),
      .clk                                                     (clk_i),
      .reset                                                   (!rst_n_i || core_reset_i),
      .EmbeddedRiscvJtag_logic_debug_reset                     (!jtag_trst_n_i)
  );
  // verilog_format: on

  assign icache_axi4.arid[2:1] = '0;
  assign icache_axi4.arlock    = 1'b0;
  assign icache_axi4.arqos     = '0;
  assign icache_axi4.arregion  = '0;
  assign icache_axi4.aruser    = '0;
  assign dcache_axi4.awlock    = 1'b0;
  assign dcache_axi4.awqos     = '0;
  assign dcache_axi4.awregion  = '0;
  assign dcache_axi4.awuser    = '0;
  assign dcache_axi4.wuser     = '0;
  assign dcache_axi4.arlock    = 1'b0;
  assign dcache_axi4.arqos     = '0;
  assign dcache_axi4.arregion  = '0;
  assign dcache_axi4.aruser    = '0;
  assign mmio_axi4.awid        = '0;
  assign mmio_axi4.awlen       = '0;
  assign mmio_axi4.awburst     = `AXI4_BURST_TYPE_INCR;
  assign mmio_axi4.awlock      = 1'b0;
  assign mmio_axi4.awqos       = '0;
  assign mmio_axi4.awregion    = '0;
  assign mmio_axi4.awuser      = '0;
  assign mmio_axi4.wuser       = '0;
  assign mmio_axi4.arid        = '0;
  assign mmio_axi4.arlen       = '0;
  assign mmio_axi4.arburst     = `AXI4_BURST_TYPE_INCR;
  assign mmio_axi4.arlock      = 1'b0;
  assign mmio_axi4.arqos       = '0;
  assign mmio_axi4.arregion    = '0;
  assign mmio_axi4.aruser      = '0;
endmodule
