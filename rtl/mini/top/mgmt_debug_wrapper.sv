// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

// Hazard3 JTAG-DTM and Debug Module integration. The Debug Module is in the
// management-core clock domain and exposes abstract commands only (no SBA).
module mgmt_debug_wrapper #(
    parameter logic [31:0] JTAG_IDCODE = 32'hDEAD_BEEF
) (
    input  logic clk_i,
    input  logic rst_n_i,
    input  logic bridge_idle_i,
    input  logic jtag_tck_i,
    input  logic jtag_tms_i,
    input  logic jtag_tdi_i,
    input  logic jtag_trst_n_i,
    output logic jtag_tdo_o,
    output logic core_rst_n_o,

    output logic        dbg_req_halt_o,
    output logic        dbg_req_halt_on_reset_o,
    output logic        dbg_req_resume_o,
    input  logic        dbg_halted_i,
    input  logic        dbg_running_i,
    output logic [31:0] dbg_data0_rdata_o,
    input  logic [31:0] dbg_data0_wdata_i,
    input  logic        dbg_data0_wen_i,
    output logic [31:0] dbg_instr_data_o,
    output logic        dbg_instr_data_vld_o,
    input  logic        dbg_instr_data_rdy_i,
    input  logic        dbg_instr_caught_exception_i,
    input  logic        dbg_instr_caught_ebreak_i,
    output logic [31:0] dbg_sbus_addr_o,
    output logic        dbg_sbus_write_o,
    output logic [ 1:0] dbg_sbus_size_o,
    output logic        dbg_sbus_vld_o,
    input  logic        dbg_sbus_rdy_i,
    input  logic        dbg_sbus_err_i,
    output logic [31:0] dbg_sbus_wdata_o,
    input  logic [31:0] dbg_sbus_rdata_i
);

  logic        s_jtag_tck_buf;
  logic        s_jtag_trst_n_sync;
  logic        s_dmihardreset_req;
  logic        s_dmihardreset_sync;
  logic        s_dmi_rst_n;
  logic        s_dmi_psel;
  logic        s_dmi_penable;
  logic        s_dmi_pwrite;
  logic [ 8:0] s_dmi_paddr;
  logic [31:0] s_dmi_pwdata;
  logic [31:0] s_dmi_prdata;
  logic        s_dmi_pready;
  logic        s_dmi_pslverr;
  logic        s_sys_reset_req;
  logic        s_reset_done;
  logic        s_hart_reset_req;

  tc_clk_buf u_jtag_tck_buf (
      .clk_i(jtag_tck_i),
      .clk_o(s_jtag_tck_buf)
  );
  rst_sync u_jtag_rst_sync (
      .clk_i  (s_jtag_tck_buf),
      .rst_n_i(jtag_trst_n_i),
      .rst_n_o(s_jtag_trst_n_sync)
  );
  cdc_sync u_dmihardreset_cdc_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_dmihardreset_req),
      .dat_o  (s_dmihardreset_sync)
  );
  rst_sync u_dmi_rst_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i && !s_dmihardreset_sync),
      .rst_n_o(s_dmi_rst_n)
  );

  hazard3_jtag_dtm #(
      .IDCODE(JTAG_IDCODE)
  ) u_hazard3_jtag_dtm (
      .tck             (s_jtag_tck_buf),
      .trst_n          (s_jtag_trst_n_sync),
      .tms             (jtag_tms_i),
      .tdi             (jtag_tdi_i),
      .tdo             (jtag_tdo_o),
      .dmihardreset_req(s_dmihardreset_req),
      .clk_dmi         (clk_i),
      .rst_n_dmi       (s_dmi_rst_n),
      .dmi_psel        (s_dmi_psel),
      .dmi_penable     (s_dmi_penable),
      .dmi_pwrite      (s_dmi_pwrite),
      .dmi_paddr       (s_dmi_paddr),
      .dmi_pwdata      (s_dmi_pwdata),
      .dmi_prdata      (s_dmi_prdata),
      .dmi_pready      (s_dmi_pready),
      .dmi_pslverr     (s_dmi_pslverr)
  );

  hazard3_dm #(
      .N_HARTS (1),
      .HAVE_SBA(0)
  ) u_hazard3_dm (
      .clk                        (clk_i),
      .rst_n                      (s_dmi_rst_n),
      .dmi_psel                   (s_dmi_psel),
      .dmi_penable                (s_dmi_penable),
      .dmi_pwrite                 (s_dmi_pwrite),
      .dmi_paddr                  (s_dmi_paddr),
      .dmi_pwdata                 (s_dmi_pwdata),
      .dmi_prdata                 (s_dmi_prdata),
      .dmi_pready                 (s_dmi_pready),
      .dmi_pslverr                (s_dmi_pslverr),
      .sys_reset_req              (s_sys_reset_req),
      .sys_reset_done             (s_reset_done),
      .hart_reset_req             (s_hart_reset_req),
      .hart_reset_done            (s_reset_done),
      .hart_req_halt              (dbg_req_halt_o),
      .hart_req_halt_on_reset     (dbg_req_halt_on_reset_o),
      .hart_req_resume            (dbg_req_resume_o),
      .hart_halted                (dbg_halted_i),
      .hart_running               (dbg_running_i),
      .hart_data0_rdata           (dbg_data0_rdata_o),
      .hart_data0_wdata           (dbg_data0_wdata_i),
      .hart_data0_wen             (dbg_data0_wen_i),
      .hart_instr_data            (dbg_instr_data_o),
      .hart_instr_data_vld        (dbg_instr_data_vld_o),
      .hart_instr_data_rdy        (dbg_instr_data_rdy_i),
      .hart_instr_caught_exception(dbg_instr_caught_exception_i),
      .hart_instr_caught_ebreak   (dbg_instr_caught_ebreak_i),
      .sbus_addr                  (dbg_sbus_addr_o),
      .sbus_write                 (dbg_sbus_write_o),
      .sbus_size                  (dbg_sbus_size_o),
      .sbus_vld                   (dbg_sbus_vld_o),
      .sbus_rdy                   (dbg_sbus_rdy_i),
      .sbus_err                   (dbg_sbus_err_i),
      .sbus_wdata                 (dbg_sbus_wdata_o),
      .sbus_rdata                 (dbg_sbus_rdata_i)
  );

  mgmt_debug_reset u_mgmt_debug_reset (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .reset_req_i  (s_sys_reset_req || s_hart_reset_req),
      .bridge_idle_i(bridge_idle_i),
      .core_rst_n_o (core_rst_n_o),
      .reset_done_o (s_reset_done)
  );

endmodule
