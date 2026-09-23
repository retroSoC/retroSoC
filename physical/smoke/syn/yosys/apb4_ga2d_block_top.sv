// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// Pin-level synthesis top for the isolated apb4_ga2d block evidence flow
// (physical/smoke/syn/yosys/ga2d_block.mk). The slang frontend requires the
// top-level module to have no unconnected interface ports, so this wrapper
// instantiates the apb4_if/axi4_if interfaces and exposes their signals as
// plain ports. The AXI4 interface keeps the SoC-integration parameters
// (32-bit address, 64-bit data, 4-bit ID, 4-bit user).
module apb4_ga2d_block_top (
    // verilog_format: off -- preserve the shell lifecycle boundary columns
    input  logic         clk_i,
    input  logic         rst_n_i,
    input  logic         resource_quiesce_i,
    input  logic         resource_reset_i,
    input  logic         source_stop_i,
    input  logic         source_safe_idle_i,
    input  logic         block_ack_i,
    input  logic         bridge_clear_busy_i,
    input  logic [7:0]   bridge_epoch_i,
    input  logic         data_ready_i,
    input  logic [1:0]   mem_pad_mode_i,
    output logic         idle_o,
    output logic         core_safe_idle_o,
    output logic         irq_o,
    // verilog_format: on
    input  logic [31:0]  apb4_paddr,
    input  logic [ 2:0]  apb4_pprot,
    input  logic         apb4_psel,
    input  logic         apb4_penable,
    input  logic         apb4_pwrite,
    input  logic [31:0]  apb4_pwdata,
    input  logic [ 3:0]  apb4_pstrb,
    output logic         apb4_pready,
    output logic [31:0]  apb4_prdata,
    output logic         apb4_pslverr,
    output logic [ 3:0]  ga2d_axi4_awid,
    output logic [31:0]  ga2d_axi4_awaddr,
    output logic [ 7:0]  ga2d_axi4_awlen,
    output logic [ 2:0]  ga2d_axi4_awsize,
    output logic [ 1:0]  ga2d_axi4_awburst,
    output logic         ga2d_axi4_awlock,
    output logic [ 3:0]  ga2d_axi4_awcache,
    output logic [ 2:0]  ga2d_axi4_awprot,
    output logic [ 3:0]  ga2d_axi4_awqos,
    output logic [ 3:0]  ga2d_axi4_awregion,
    output logic [ 3:0]  ga2d_axi4_awuser,
    output logic         ga2d_axi4_awvalid,
    input  logic         ga2d_axi4_awready,
    output logic [63:0]  ga2d_axi4_wdata,
    output logic [ 7:0]  ga2d_axi4_wstrb,
    output logic         ga2d_axi4_wlast,
    output logic [ 3:0]  ga2d_axi4_wuser,
    output logic         ga2d_axi4_wvalid,
    input  logic         ga2d_axi4_wready,
    input  logic [ 3:0]  ga2d_axi4_bid,
    input  logic [ 1:0]  ga2d_axi4_bresp,
    input  logic [ 3:0]  ga2d_axi4_buser,
    input  logic         ga2d_axi4_bvalid,
    output logic         ga2d_axi4_bready,
    output logic [ 3:0]  ga2d_axi4_arid,
    output logic [31:0]  ga2d_axi4_araddr,
    output logic [ 7:0]  ga2d_axi4_arlen,
    output logic [ 2:0]  ga2d_axi4_arsize,
    output logic [ 1:0]  ga2d_axi4_arburst,
    output logic         ga2d_axi4_arlock,
    output logic [ 3:0]  ga2d_axi4_arcache,
    output logic [ 2:0]  ga2d_axi4_arprot,
    output logic [ 3:0]  ga2d_axi4_arqos,
    output logic [ 3:0]  ga2d_axi4_arregion,
    output logic [ 3:0]  ga2d_axi4_aruser,
    output logic         ga2d_axi4_arvalid,
    input  logic         ga2d_axi4_arready,
    input  logic [ 3:0]  ga2d_axi4_rid,
    input  logic [63:0]  ga2d_axi4_rdata,
    input  logic [ 1:0]  ga2d_axi4_rresp,
    input  logic         ga2d_axi4_rlast,
    input  logic [ 3:0]  ga2d_axi4_ruser,
    input  logic         ga2d_axi4_rvalid,
    output logic         ga2d_axi4_rready
);

  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  axi4_if ga2d_axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  assign apb4.paddr    = apb4_paddr;
  assign apb4.pprot    = apb4_pprot;
  assign apb4.psel     = apb4_psel;
  assign apb4.penable  = apb4_penable;
  assign apb4.pwrite   = apb4_pwrite;
  assign apb4.pwdata   = apb4_pwdata;
  assign apb4.pstrb    = apb4_pstrb;
  assign apb4_pready   = apb4.pready;
  assign apb4_prdata   = apb4.prdata;
  assign apb4_pslverr  = apb4.pslverr;

  assign ga2d_axi4_awid     = ga2d_axi4.awid;
  assign ga2d_axi4_awaddr   = ga2d_axi4.awaddr;
  assign ga2d_axi4_awlen    = ga2d_axi4.awlen;
  assign ga2d_axi4_awsize   = ga2d_axi4.awsize;
  assign ga2d_axi4_awburst  = ga2d_axi4.awburst;
  assign ga2d_axi4_awlock   = ga2d_axi4.awlock;
  assign ga2d_axi4_awcache  = ga2d_axi4.awcache;
  assign ga2d_axi4_awprot   = ga2d_axi4.awprot;
  assign ga2d_axi4_awqos    = ga2d_axi4.awqos;
  assign ga2d_axi4_awregion = ga2d_axi4.awregion;
  assign ga2d_axi4_awuser   = ga2d_axi4.awuser;
  assign ga2d_axi4_awvalid  = ga2d_axi4.awvalid;
  assign ga2d_axi4.awready  = ga2d_axi4_awready;
  assign ga2d_axi4_wdata    = ga2d_axi4.wdata;
  assign ga2d_axi4_wstrb    = ga2d_axi4.wstrb;
  assign ga2d_axi4_wlast    = ga2d_axi4.wlast;
  assign ga2d_axi4_wuser    = ga2d_axi4.wuser;
  assign ga2d_axi4_wvalid   = ga2d_axi4.wvalid;
  assign ga2d_axi4.wready   = ga2d_axi4_wready;
  assign ga2d_axi4.bid      = ga2d_axi4_bid;
  assign ga2d_axi4.bresp    = ga2d_axi4_bresp;
  assign ga2d_axi4.buser    = ga2d_axi4_buser;
  assign ga2d_axi4.bvalid   = ga2d_axi4_bvalid;
  assign ga2d_axi4_bready   = ga2d_axi4.bready;
  assign ga2d_axi4_arid     = ga2d_axi4.arid;
  assign ga2d_axi4_araddr   = ga2d_axi4.araddr;
  assign ga2d_axi4_arlen    = ga2d_axi4.arlen;
  assign ga2d_axi4_arsize   = ga2d_axi4.arsize;
  assign ga2d_axi4_arburst  = ga2d_axi4.arburst;
  assign ga2d_axi4_arlock   = ga2d_axi4.arlock;
  assign ga2d_axi4_arcache  = ga2d_axi4.arcache;
  assign ga2d_axi4_arprot   = ga2d_axi4.arprot;
  assign ga2d_axi4_arqos    = ga2d_axi4.arqos;
  assign ga2d_axi4_arregion = ga2d_axi4.arregion;
  assign ga2d_axi4_aruser   = ga2d_axi4.aruser;
  assign ga2d_axi4_arvalid  = ga2d_axi4.arvalid;
  assign ga2d_axi4.arready  = ga2d_axi4_arready;
  assign ga2d_axi4.rid      = ga2d_axi4_rid;
  assign ga2d_axi4.rdata    = ga2d_axi4_rdata;
  assign ga2d_axi4.rresp    = ga2d_axi4_rresp;
  assign ga2d_axi4.rlast    = ga2d_axi4_rlast;
  assign ga2d_axi4.ruser    = ga2d_axi4_ruser;
  assign ga2d_axi4.rvalid   = ga2d_axi4_rvalid;
  assign ga2d_axi4_rready   = ga2d_axi4.rready;

  apb4_ga2d u_apb4_ga2d (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .resource_quiesce_i (resource_quiesce_i),
      .resource_reset_i   (resource_reset_i),
      .source_stop_i      (source_stop_i),
      .source_safe_idle_i (source_safe_idle_i),
      .block_ack_i        (block_ack_i),
      .bridge_clear_busy_i(bridge_clear_busy_i),
      .bridge_epoch_i     (bridge_epoch_i),
      .data_ready_i       (data_ready_i),
      .mem_pad_mode_i     (mem_pad_mode_i),
      .apb4               (apb4),
      .ga2d_axi4          (ga2d_axi4),
      .idle_o             (idle_o),
      .core_safe_idle_o   (core_safe_idle_o),
      .irq_o              (irq_o)
  );
endmodule
