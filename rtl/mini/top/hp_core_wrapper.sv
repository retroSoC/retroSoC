// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "axi4_define.svh"

// OpenC906 HP core integration.
//
// Contract (docs/ip/hp-platform.md):
// - Reset vector 0x38000000 (pad_cpu_rvba), internal CLINT/PLIC window at
//   0x08000000 (pad_cpu_apb_base; 128 MiB aligned, decoded inside the BIU,
//   never reaches the external bus).
// - Single 128-bit AXI4 master, downsized to the 64-bit HP fabric and split
//   into the data-fabric port and the MMIO port by address window.
// - mhartid reports 1 via the controlled aq_sysio_kid.v override (LP is
//   hart 0). SoC interrupt source n drives pad_plic_int_vld[n] and appears
//   to software as PLIC ID n+16.
// - The JTAG DTM (tdt_dmi_top) runs on a divide-by-2 sys_apb clock; its
//   hartreset request participates in the core reset so debugger resets
//   preserve the existing lifecycle semantics.
// - No low-power or DFT support: scan/mbist inputs are tied off and the
//   debug SBA AXI master is left unconnected.
module hp_core_wrapper (
    // verilog_format: off -- preserve the HP integration boundary alignment
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        core_reset_i,
    input  logic [63:0] time_i,
    input  logic [15:0] plic_src_i,
    input  logic        jtag_tck_i,
    input  logic        jtag_tms_i,
    input  logic        jtag_tdi_i,
    input  logic        jtag_trst_n_i,
    output logic        jtag_tdo_o,
    output logic        debug_reset_req_o,
    axi4_if.master      mem_axi4,
    axi4_if.master      mmio_axi4
    // verilog_format: on
);
  localparam logic [39:0] HpResetVector = 40'h00_3800_0000;
  localparam logic [39:0] HpApbBase = 40'h00_0800_0000;

  logic        s_sys_apb_clk;
  logic        s_sys_apb_rst_b;
  logic        s_core_rst_b;
  logic        s_hartreset_n;
  logic        s_ndmreset_n;
  logic        s_dtm_tdo;
  logic        s_dtm_tdo_en;
  logic [11:0] s_dmi_paddr;
  logic        s_dmi_psel;
  logic        s_dmi_penable;
  logic        s_dmi_pwrite;
  logic [31:0] s_dmi_pwdata;
  logic [31:0] s_dmi_prdata;
  logic        s_dmi_pready;
  logic        s_dmi_pslverr;
  // The C906 drives 40-bit addresses; the Mini HP fabric is 32-bit physical.
  logic [39:0] s_c906_araddr;
  logic [39:0] s_c906_awaddr;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(128),
      .ID_WIDTH  (8),
      .USER_WIDTH(1)
  ) u_c906_axi4_if (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) u_hp_64_axi4_if (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  // The debug module clock must be slower than the core clock; divide the
  // core clock by two (JTAG tck is always slower still).
  clk_int_even_div_static #(
      .DIV_VALUE_WIDTH(1)
  ) u_sys_apb_clk_div (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .clk_o  (s_sys_apb_clk)
  );

  // The debug module lives in the JTAG reset domain so that a lifecycle
  // reset of the core does not detach the debugger; the DM hartreset
  // request joins the core reset exactly like the previous ndmreset path.
  assign s_sys_apb_rst_b   = rst_n_i && jtag_trst_n_i;
  assign s_core_rst_b      = rst_n_i && !core_reset_i && s_hartreset_n;
  assign debug_reset_req_o = !s_ndmreset_n;
  assign jtag_tdo_o        = s_dtm_tdo && s_dtm_tdo_en;

  // verilog_format: off -- vendored OpenC906 ports are upstream ABI
  openC906 u_openc906 (
      .pll_core_cpuclk       (clk_i),
      .axim_clk_en           (1'b1),
      .sys_apb_clk           (s_sys_apb_clk),
      .sys_apb_rst_b         (s_sys_apb_rst_b),
      .pad_cpu_rst_b         (s_core_rst_b),
      .pad_cpu_rvba          (HpResetVector),
      .pad_cpu_apb_base      (HpApbBase),
      .pad_cpu_sys_cnt       (time_i),
      .pad_plic_int_vld      ({224'd0, plic_src_i}),
      .pad_plic_int_cfg      (240'd0),
      .biu_pad_araddr        (s_c906_araddr),
      .biu_pad_arburst       (u_c906_axi4_if.arburst),
      .biu_pad_arcache       (u_c906_axi4_if.arcache),
      .biu_pad_arid          (u_c906_axi4_if.arid),
      .biu_pad_arlen         (u_c906_axi4_if.arlen),
      .biu_pad_arlock        (u_c906_axi4_if.arlock),
      .biu_pad_arprot        (u_c906_axi4_if.arprot),
      .biu_pad_arsize        (u_c906_axi4_if.arsize),
      .biu_pad_arvalid       (u_c906_axi4_if.arvalid),
      .biu_pad_awaddr        (s_c906_awaddr),
      .biu_pad_awburst       (u_c906_axi4_if.awburst),
      .biu_pad_awcache       (u_c906_axi4_if.awcache),
      .biu_pad_awid          (u_c906_axi4_if.awid),
      .biu_pad_awlen         (u_c906_axi4_if.awlen),
      .biu_pad_awlock        (u_c906_axi4_if.awlock),
      .biu_pad_awprot        (u_c906_axi4_if.awprot),
      .biu_pad_awsize        (u_c906_axi4_if.awsize),
      .biu_pad_awvalid       (u_c906_axi4_if.awvalid),
      .biu_pad_bready        (u_c906_axi4_if.bready),
      .biu_pad_rready        (u_c906_axi4_if.rready),
      .biu_pad_wdata         (u_c906_axi4_if.wdata),
      .biu_pad_wlast         (u_c906_axi4_if.wlast),
      .biu_pad_wstrb         (u_c906_axi4_if.wstrb),
      .biu_pad_wvalid        (u_c906_axi4_if.wvalid),
      .pad_biu_arready       (u_c906_axi4_if.arready),
      .pad_biu_awready       (u_c906_axi4_if.awready),
      .pad_biu_bid           (u_c906_axi4_if.bid),
      .pad_biu_bresp         (u_c906_axi4_if.bresp),
      .pad_biu_bvalid        (u_c906_axi4_if.bvalid),
      .pad_biu_rdata         (u_c906_axi4_if.rdata),
      .pad_biu_rid           (u_c906_axi4_if.rid),
      .pad_biu_rlast         (u_c906_axi4_if.rlast),
      .pad_biu_rresp         (u_c906_axi4_if.rresp),
      .pad_biu_rvalid        (u_c906_axi4_if.rvalid),
      .pad_biu_wready        (u_c906_axi4_if.wready),
      .pad_tdt_dm_arready    (1'b0),
      .pad_tdt_dm_awready    (1'b0),
      .pad_tdt_dm_bid        (4'd0),
      .pad_tdt_dm_bresp      (2'd0),
      .pad_tdt_dm_bvalid     (1'b0),
      .pad_tdt_dm_core_unavail(1'b0),
      .pad_tdt_dm_rdata      (128'd0),
      .pad_tdt_dm_rid        (4'd0),
      .pad_tdt_dm_rlast      (1'b0),
      .pad_tdt_dm_rresp      (2'd0),
      .pad_tdt_dm_rvalid     (1'b0),
      .pad_tdt_dm_wready     (1'b0),
      .pad_yy_dft_clk_rst_b  (rst_n_i),
      .pad_yy_icg_scan_en    (1'b0),
      .pad_yy_mbist_mode     (1'b0),
      .pad_yy_scan_enable    (1'b0),
      .pad_yy_scan_mode      (1'b0),
      .pad_yy_scan_rst_b     (1'b1),
      .core0_pad_halted      (),
      .core0_pad_lpmd_b      (),
      .core0_pad_retire      (),
      .core0_pad_retire_pc   (),
      .cpu_debug_port        (),
      .tdt_dm_pad_araddr     (),
      .tdt_dm_pad_arburst    (),
      .tdt_dm_pad_arcache    (),
      .tdt_dm_pad_arid       (),
      .tdt_dm_pad_arlen      (),
      .tdt_dm_pad_arlock     (),
      .tdt_dm_pad_arprot     (),
      .tdt_dm_pad_arsize     (),
      .tdt_dm_pad_arvalid    (),
      .tdt_dm_pad_awaddr     (),
      .tdt_dm_pad_awburst    (),
      .tdt_dm_pad_awcache    (),
      .tdt_dm_pad_awid       (),
      .tdt_dm_pad_awlen      (),
      .tdt_dm_pad_awlock     (),
      .tdt_dm_pad_awprot     (),
      .tdt_dm_pad_awsize     (),
      .tdt_dm_pad_awvalid    (),
      .tdt_dm_pad_bready     (),
      .tdt_dm_pad_hartreset_n(s_hartreset_n),
      .tdt_dm_pad_ndmreset_n (s_ndmreset_n),
      .tdt_dm_pad_rready     (),
      .tdt_dm_pad_wdata      (),
      .tdt_dm_pad_wlast      (),
      .tdt_dm_pad_wstrb      (),
      .tdt_dm_pad_wvalid     (),
      .tdt_dmi_paddr         (s_dmi_paddr),
      .tdt_dmi_penable       (s_dmi_penable),
      .tdt_dmi_prdata        (s_dmi_prdata),
      .tdt_dmi_pready        (s_dmi_pready),
      .tdt_dmi_psel          (s_dmi_psel),
      .tdt_dmi_pslverr       (s_dmi_pslverr),
      .tdt_dmi_pwdata        (s_dmi_pwdata),
      .tdt_dmi_pwrite        (s_dmi_pwrite)
  );

  tdt_dmi_top u_tdt_dmi_top (
      .pad_tdt_dtm_jtag2_sel(1'b0),
      .pad_tdt_dtm_tap_en   (1'b1),
      .pad_tdt_dtm_tclk     (jtag_tck_i),
      .pad_tdt_dtm_tdi      (jtag_tdi_i),
      .pad_tdt_dtm_tms_i    (jtag_tms_i),
      .pad_tdt_dtm_trst_b   (jtag_trst_n_i),
      .pad_tdt_icg_scan_en  (1'b0),
      .pad_yy_scan_mode     (1'b0),
      .pad_yy_scan_rst_b    (1'b1),
      .sys_apb_clk          (s_sys_apb_clk),
      .sys_apb_rst_b        (s_sys_apb_rst_b),
      .tdt_dmi_paddr        (s_dmi_paddr),
      .tdt_dmi_penable      (s_dmi_penable),
      .tdt_dmi_prdata       (s_dmi_prdata),
      .tdt_dmi_pready       (s_dmi_pready),
      .tdt_dmi_psel         (s_dmi_psel),
      .tdt_dmi_pslverr      (s_dmi_pslverr),
      .tdt_dmi_pwdata       (s_dmi_pwdata),
      .tdt_dmi_pwrite       (s_dmi_pwrite),
      .tdt_dtm_pad_tdo      (s_dtm_tdo),
      .tdt_dtm_pad_tdo_en   (s_dtm_tdo_en),
      .tdt_dtm_pad_tms_o    (),
      .tdt_dtm_pad_tms_oe   ()
  );
  // verilog_format: on

  assign u_c906_axi4_if.araddr   = s_c906_araddr[31:0];
  assign u_c906_axi4_if.awaddr   = s_c906_awaddr[31:0];
  // The C906 BIU has no qos/region/user sidebands; tie the interface fields.
  assign u_c906_axi4_if.arqos    = '0;
  assign u_c906_axi4_if.arregion = '0;
  assign u_c906_axi4_if.aruser   = '0;
  assign u_c906_axi4_if.awqos    = '0;
  assign u_c906_axi4_if.awregion = '0;
  assign u_c906_axi4_if.awuser   = '0;
  assign u_c906_axi4_if.wuser    = '0;

  axi4_downsizer_128to64 u_hp_downsizer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .clear_i(core_reset_i),
      .wide   (u_c906_axi4_if),
      .narrow (u_hp_64_axi4_if)
  );

  axi4_mmio_demux u_hp_mmio_demux (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .clear_i(core_reset_i),
      .source (u_hp_64_axi4_if),
      .mem    (mem_axi4),
      .mmio   (mmio_axi4)
  );
endmodule
