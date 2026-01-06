// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "mmap_define.svh"
`include "mdd_config.svh"

module core_wrapper (
    // verilog_format: off
    input logic                           clk_i,
    input logic                           rst_n_i,
    input logic [31:0]                    irq_i,
`ifdef CORE_MDD
    input logic [`USER_CORESEL_WIDTH-1:0] core_sel_i,
`endif
    nmi_if.master                         nmi
    // verilog_format: on
);

`ifdef CORE_PICORV32
  picorv32 #(
      .BARREL_SHIFTER (1),
      .COMPRESSED_ISA (1),
      .ENABLE_MUL     (1),
      .ENABLE_FAST_MUL(1),
      .ENABLE_DIV     (1),
      .ENABLE_IRQ     (0),
      .PROGADDR_RESET (`FLASH_START_ADDR),
      .PROGADDR_IRQ   (`IRQ_HANDLER_START_ADDR)
  ) u_picorv32 (
      .clk         (clk_i),
      .resetn      (rst_n_i),
      .trap        (),
      .mem_valid   (nmi.valid),
      .mem_instr   (),
      .mem_addr    (nmi.addr),
      .mem_wdata   (nmi.wdata),
      .mem_wstrb   (nmi.wstrb),
      .mem_rdata   (nmi.rdata),
      .mem_ready   (nmi.ready),
      .mem_la_read (),
      .mem_la_write(),
      .mem_la_addr (),
      .mem_la_wdata(),
      .mem_la_wstrb(),
      .pcpi_valid  (),
      .pcpi_insn   (),
      .pcpi_rs1    (),
      .pcpi_rs2    (),
      .pcpi_wr     (),
      .pcpi_rd     (),
      .pcpi_wait   (),
      .pcpi_ready  (),
      .irq         (irq_i),
      .eoi         (),
      .trace_valid (),
      .trace_data  ()
  );

`elsif CORE_HAZARD3

  logic s_pwrup_req;
  // verilog_format: off
  ahbl_if u_ahbl_if (clk_i, rst_n_i);
  ahbl2nmi u_ahbl2nmi (u_ahbl_if, nmi);
  // verilog_format: on

  hazard3_cpu_1port #(
      .RESET_VECTOR       (`FLASH_START_ADDR),
      .MTVEC_INIT         (32'h0000_0000),
      .EXTENSION_A        (1),
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
      .DEBUG_SUPPORT      (0),
      .BREAKPOINT_TRIGGERS(0),
      .NUM_IRQS           (30),
      .IRQ_PRIORITY_BITS  (2),
      .IRQ_INPUT_BYPASS   (30'h0),
      .MVENDORID_VAL      (32'h0),
      .MCONFIGPTR_VAL     (32'h0),
      .REDUCED_BYPASS     (0),
      .MULDIV_UNROLL      (1),
      .MUL_FAST           (1),
      .MUL_FASTER         (1),
      .MULH_FAST          (1),
      .FAST_BRANCHCMP     (1),
      .RESET_REGFILE      (1),
      .BRANCH_PREDICTOR   (0),
      .MTVEC_WMASK        (32'hfffffffd)
  ) u_hazard3_cpu_1port (
      // Global signals
      .clk                       (clk_i),
      .clk_always_on             (clk_i),
      .rst_n                     (rst_n_i),
      // Power control signals
      .pwrup_req                 (s_pwrup_req),
      .pwrup_ack                 (s_pwrup_req),          // tied back
      .clk_en                    (),
      .unblock_out               (),
      .unblock_in                (1'b0),
      // AHB5 Master port
      .haddr                     (u_ahbl_if.haddr),
      .hwrite                    (u_ahbl_if.hwrite),
      .htrans                    (u_ahbl_if.htrans),
      .hsize                     (u_ahbl_if.hsize),
      .hburst                    (u_ahbl_if.hburst),
      .hprot                     (u_ahbl_if.hprot),
      .hmastlock                 (u_ahbl_if.hmastlock),
      .hmaster                   (),
      .hexcl                     (),
      .hready                    (u_ahbl_if.hready),
      .hresp                     (u_ahbl_if.hresp),
      .hexokay                   (1'b1),
      .hwdata                    (u_ahbl_if.hwdata),
      .hrdata                    (u_ahbl_if.hrdata),
      // Memory ordering signals
      .fence_i_vld               (),
      .fence_d_vld               (),
      .fence_rdy                 (1'b1),
      // Debugger run/halt control
      .dbg_req_halt              (1'b0),
      .dbg_req_halt_on_reset     (1'b0),
      .dbg_req_resume            (1'b0),
      .dbg_halted                (),
      .dbg_running               (),
      // Debugger access to data0 CSR
      .dbg_data0_rdata           ('0),
      .dbg_data0_wdata           (),
      .dbg_data0_wen             (),
      // Debugger instruction injection
      .dbg_instr_data            ('0),
      .dbg_instr_data_vld        ('0),
      .dbg_instr_data_rdy        (),
      .dbg_instr_caught_exception(),
      .dbg_instr_caught_ebreak   (),
      // Optional debug system bus access patch-through
      .dbg_sbus_addr             ('0),
      .dbg_sbus_write            ('0),
      .dbg_sbus_size             ('0),
      .dbg_sbus_vld              ('0),
      .dbg_sbus_rdy              (),
      .dbg_sbus_err              (),
      .dbg_sbus_wdata            ('0),
      .dbg_sbus_rdata            (),
      // Identification CSR values
      .mhartid_val               ('0),
      .eco_version               ('0),
      // Level-sensitive interrupt sources
      .irq                       (irq_i[31:2]),
      .soft_irq                  (irq_i[0]),
      .timer_irq                 (irq_i[1])
  );

`elsif CORE_MDD
  user_core_wrapper u_user_core_wrapper (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .irq_i  (irq_i),
      .sel_i  (core_sel_i),
      .nmi    (nmi)
  );

`endif

endmodule
