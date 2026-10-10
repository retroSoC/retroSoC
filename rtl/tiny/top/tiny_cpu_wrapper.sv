// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "mmap_define.svh"

module tiny_cpu_wrapper #(
    parameter int ExternalIrqCount = 30,
    parameter bit EnableAtomics    = 1'b0,
    parameter int ResetSyncStages  = 3
) (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic [ExternalIrqCount+1:0] irq_i,
    input  logic        jtag_tck_i,
    input  logic        jtag_tms_i,
    input  logic        jtag_tdi_i,
    input  logic        jtag_trst_n_i,
    output logic        jtag_tdo_o,
    output logic        debug_halted_o,
    input  logic        bus_idle_i,
    output logic        core_rst_n_o,
    output logic        quiesce_o,
    ahbl_if.master      cpu[2]
    // verilog_format: on
);

  logic        s_pwrup_req;
  logic        s_reset_pending;
  logic        s_hart_idle;
  logic        s_core_rst_n;
  logic        s_dbg_req_halt;
  logic        s_dbg_req_halt_on_reset;
  logic        s_dbg_req_resume;
  logic        s_dbg_halted;
  logic        s_dbg_running;
  logic [31:0] s_dbg_data0_rdata;
  logic [31:0] s_dbg_data0_wdata;
  logic        s_dbg_data0_wen;
  logic [31:0] s_dbg_instr_data;
  logic        s_dbg_instr_data_vld;
  logic        s_dbg_instr_data_rdy;
  logic        s_dbg_instr_caught_exception;
  logic        s_dbg_instr_caught_ebreak;
  logic [31:0] s_dbg_sbus_addr;
  logic        s_dbg_sbus_write;
  logic [ 1:0] s_dbg_sbus_size;
  logic        s_dbg_sbus_vld;
  logic        s_dbg_sbus_rdy;
  logic        s_dbg_sbus_err;
  logic [31:0] s_dbg_sbus_wdata;
  logic [31:0] s_dbg_sbus_rdata;

  assign debug_halted_o = s_dbg_halted;
  assign core_rst_n_o   = s_core_rst_n;
  // Request a normal debug halt before draining/resetting the core. Never cut
  // off an accepted AHB transfer to manufacture an idle indication.
  assign quiesce_o      = s_reset_pending && s_dbg_halted;
  assign s_hart_idle    = bus_idle_i && (!s_reset_pending || s_dbg_halted);

  mgmt_debug_wrapper #(
      .JtagIdcode     (`SOC_JTAG_IDCODE),
      .ResetSyncStages(ResetSyncStages)
  ) u_mgmt_debug_wrapper (
      .clk_i                       (clk_i),
      .rst_n_i                     (rst_n_i),
      .bridge_idle_i               (s_hart_idle),
      .jtag_tck_i                  (jtag_tck_i),
      .jtag_tms_i                  (jtag_tms_i),
      .jtag_tdi_i                  (jtag_tdi_i),
      .jtag_trst_n_i               (jtag_trst_n_i),
      .jtag_tdo_o                  (jtag_tdo_o),
      .core_rst_n_o                (s_core_rst_n),
      .reset_pending_o             (s_reset_pending),
      .dbg_req_halt_o              (s_dbg_req_halt),
      .dbg_req_halt_on_reset_o     (s_dbg_req_halt_on_reset),
      .dbg_req_resume_o            (s_dbg_req_resume),
      .dbg_halted_i                (s_dbg_halted),
      .dbg_running_i               (s_dbg_running),
      .dbg_data0_rdata_o           (s_dbg_data0_rdata),
      .dbg_data0_wdata_i           (s_dbg_data0_wdata),
      .dbg_data0_wen_i             (s_dbg_data0_wen),
      .dbg_instr_data_o            (s_dbg_instr_data),
      .dbg_instr_data_vld_o        (s_dbg_instr_data_vld),
      .dbg_instr_data_rdy_i        (s_dbg_instr_data_rdy),
      .dbg_instr_caught_exception_i(s_dbg_instr_caught_exception),
      .dbg_instr_caught_ebreak_i   (s_dbg_instr_caught_ebreak),
      .dbg_sbus_addr_o             (s_dbg_sbus_addr),
      .dbg_sbus_write_o            (s_dbg_sbus_write),
      .dbg_sbus_size_o             (s_dbg_sbus_size),
      .dbg_sbus_vld_o              (s_dbg_sbus_vld),
      .dbg_sbus_rdy_i              (s_dbg_sbus_rdy),
      .dbg_sbus_err_i              (s_dbg_sbus_err),
      .dbg_sbus_wdata_o            (s_dbg_sbus_wdata),
      .dbg_sbus_rdata_i            (s_dbg_sbus_rdata)
  );

  hazard3_cpu_2port #(
      .RESET_VECTOR       (`SOC_CPU_RESET_ADDR),
      .MTVEC_INIT         (32'h0000_0000),
      .EXTENSION_A        (EnableAtomics),
      .EXTENSION_C        (1),
      .EXTENSION_E        (0),
      .EXTENSION_M        (1),
      .EXTENSION_ZBA      (1),
      .EXTENSION_ZBB      (1),
      .EXTENSION_ZBC      (1),
      .EXTENSION_ZBKB     (1),
      .EXTENSION_ZBKX     (1),
      .EXTENSION_ZBS      (1),
      .EXTENSION_ZCB      (0),
      .EXTENSION_ZCLSD    (0),
      .EXTENSION_ZCMP     (0),
      .EXTENSION_ZIFENCEI (1),
      .EXTENSION_ZILSD    (1),
      .EXTENSION_XH3BEXTM (1),
      .EXTENSION_XH3IRQ   (1),
      .EXTENSION_XH3PMPM  (0),
      .EXTENSION_XH3POWER (0),
      .CSR_M_MANDATORY    (1),
      .CSR_M_TRAP         (1),
      .CSR_COUNTER        (1),
      .U_MODE             (0),
      .PMP_REGIONS        (0),
      .PMP_GRAIN          (0),
      .PMP_MATCH_NAPOT    (1),
      .PMP_MATCH_TOR      (0),
      .PMP_HARDWIRED      (0),
      .PMP_HARDWIRED_ADDR (0),
      .PMP_HARDWIRED_CFG  (0),
      .DEBUG_SUPPORT      (1),
      .BREAKPOINT_TRIGGERS(2),
      .NUM_IRQS           (ExternalIrqCount),
      .IRQ_PRIORITY_BITS  (2),
      .IRQ_INPUT_BYPASS   ({ExternalIrqCount{1'b0}}),
      .MVENDORID_VAL      (32'h0),
      .MCONFIGPTR_VAL     (32'h0),
      .REDUCED_BYPASS     (0),
      .MULDIV_UNROLL      (2),
      .MUL_FAST           (1),
      .MUL_FASTER         (1),
      .MULH_FAST          (1),
      .FAST_BRANCHCMP     (1),
      .RESET_REGFILE      (1),
      .BRANCH_PREDICTOR   (1),
      .MTVEC_WMASK        (32'hfffffffd)
  ) u_hazard3_cpu_2port (
      .clk                       (clk_i),
      .clk_always_on             (clk_i),
      .rst_n                     (s_core_rst_n),
      .pwrup_req                 (s_pwrup_req),
      .pwrup_ack                 (s_pwrup_req),
      .clk_en                    (),
      .unblock_out               (),
      .unblock_in                (1'b0),
      .i_haddr                   (cpu[0].haddr),
      .i_hwrite                  (cpu[0].hwrite),
      .i_htrans                  (cpu[0].htrans),
      .i_hsize                   (cpu[0].hsize),
      .i_hburst                  (cpu[0].hburst),
      .i_hprot                   (cpu[0].hprot),
      .i_hmastlock               (cpu[0].hmastlock),
      .i_hmaster                 (),
      .i_hready                  (cpu[0].hready),
      .i_hresp                   (cpu[0].hresp),
      .i_hwdata                  (cpu[0].hwdata),
      .i_hrdata                  (cpu[0].hrdata),
      .d_haddr                   (cpu[1].haddr),
      .d_hwrite                  (cpu[1].hwrite),
      .d_htrans                  (cpu[1].htrans),
      .d_hsize                   (cpu[1].hsize),
      .d_hburst                  (cpu[1].hburst),
      .d_hprot                   (cpu[1].hprot),
      .d_hmastlock               (cpu[1].hmastlock),
      .d_hmaster                 (),
      .d_hready                  (cpu[1].hready),
      .d_hresp                   (cpu[1].hresp),
      .d_hwdata                  (cpu[1].hwdata),
      .d_hrdata                  (cpu[1].hrdata),
      .d_hexcl                   (),
      .d_hexokay                 (1'b1),
      .fence_i_vld               (),
      .fence_d_vld               (),
      .fence_rdy                 (1'b1),
      .dbg_req_halt              (s_dbg_req_halt || s_reset_pending),
      .dbg_req_halt_on_reset     (s_dbg_req_halt_on_reset),
      .dbg_req_resume            (s_dbg_req_resume && !s_reset_pending),
      .dbg_halted                (s_dbg_halted),
      .dbg_running               (s_dbg_running),
      .dbg_data0_rdata           (s_dbg_data0_rdata),
      .dbg_data0_wdata           (s_dbg_data0_wdata),
      .dbg_data0_wen             (s_dbg_data0_wen),
      .dbg_instr_data            (s_dbg_instr_data),
      .dbg_instr_data_vld        (s_dbg_instr_data_vld && !s_reset_pending),
      .dbg_instr_data_rdy        (s_dbg_instr_data_rdy),
      .dbg_instr_caught_exception(s_dbg_instr_caught_exception),
      .dbg_instr_caught_ebreak   (s_dbg_instr_caught_ebreak),
      .dbg_sbus_addr             (s_dbg_sbus_addr),
      .dbg_sbus_write            (s_dbg_sbus_write),
      .dbg_sbus_size             (s_dbg_sbus_size),
      .dbg_sbus_vld              (s_dbg_sbus_vld),
      .dbg_sbus_rdy              (s_dbg_sbus_rdy),
      .dbg_sbus_err              (s_dbg_sbus_err),
      .dbg_sbus_wdata            (s_dbg_sbus_wdata),
      .dbg_sbus_rdata            (s_dbg_sbus_rdata),
      .mhartid_val               ('0),
      .eco_version               ('0),
      .irq                       (irq_i[ExternalIrqCount+1:2]),
      .soft_irq                  (irq_i[0]),
      .timer_irq                 (irq_i[1])
  );
endmodule
