// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module sysctrl_formal_design (
    input  logic        clk_i,
    output logic        rst_n_i,
    output logic        f_past_valid,
    output logic        nmi_valid,
    output logic [31:0] nmi_addr,
    output logic [31:0] nmi_wdata,
    output logic [ 3:0] nmi_wstrb,
    output logic        nmi_ready,
    output logic [ 7:0] ip_sel,
    output logic [ 4:0] core_sel,
    output logic [ 2:0] pll_cfg,
    output logic        pll_req_valid,
    output logic        pll_req_ready,
    output logic        pll_busy,
    output logic        pll_error,
    output logic [ 1:0] pll_error_reason,
    output logic        pll_rsp_valid,
    output logic        fault_valid,
    output logic [31:0] fault_addr,
    output logic [ 3:0] fault_wstrb,
    output logic        fault_reserved,
    output logic        fault_pending,
    output logic        fault_write,
    output logic [ 1:0] fault_reason,
    output logic [31:0] fault_addr_q,
    output logic [31:0] fault_count
);

  nmi_if nmi ();
  sysctrl_if sysctrl ();
  pll_ctrl_if pll_ctrl ();

  (* anyseq *)logic        f_nmi_valid;
  (* anyseq *)logic [31:0] f_nmi_addr;
  (* anyseq *)logic [31:0] f_nmi_wdata;
  (* anyseq *)logic [ 3:0] f_nmi_wstrb;
  (* anyseq *)logic [ 4:0] f_core_sel;
  (* anyseq *)logic        f_pll_req_ready;
  (* anyseq *)logic [ 2:0] f_pll_active_sel;
  (* anyseq *)logic        f_pll_active_valid;
  (* anyseq *)logic        f_pll_safe_clk;
  (* anyseq *)logic        f_pll_lock;
  (* anyseq *)logic [ 1:0] f_pll_rsp_error;
  (* anyseq *)logic        f_pll_rsp_valid;
  (* anyseq *)logic        f_pll_capable;
  (* anyseq *)logic        f_fault_valid;
  (* anyseq *)logic [31:0] f_fault_addr;
  (* anyseq *)logic [ 3:0] f_fault_wstrb;
  (* anyseq *)logic        f_fault_reserved;

  assign nmi.valid                   = f_nmi_valid;
  assign nmi.addr                    = f_nmi_addr;
  assign nmi.wdata                   = f_nmi_wdata;
  assign nmi.wstrb                   = f_nmi_wstrb;
  assign sysctrl.core_sel_i          = f_core_sel;
  assign pll_ctrl.req_ready_i        = f_pll_req_ready;
  assign pll_ctrl.rsp_active_sel_i   = f_pll_active_sel;
  assign pll_ctrl.rsp_active_valid_i = f_pll_active_valid;
  assign pll_ctrl.rsp_safe_clk_i     = f_pll_safe_clk;
  assign pll_ctrl.rsp_pll_lock_i     = f_pll_lock;
  assign pll_ctrl.rsp_error_i        = f_pll_rsp_error;
  assign pll_ctrl.rsp_valid_i        = f_pll_rsp_valid;
  assign pll_ctrl.capable_i          = f_pll_capable;

  assign nmi_valid                   = nmi.valid;
  assign nmi_addr                    = nmi.addr;
  assign nmi_wdata                   = nmi.wdata;
  assign nmi_wstrb                   = nmi.wstrb;
  assign nmi_ready                   = nmi.ready;
  assign ip_sel                      = sysctrl.ip_sel_o;
  assign core_sel                    = u_dut.s_sysctrl_coresel_q;
  assign pll_cfg                     = u_dut.s_pll_cfg_q;
  assign pll_req_valid               = pll_ctrl.req_valid_o;
  assign pll_req_ready               = pll_ctrl.req_ready_i;
  assign pll_busy                    = u_dut.s_pll_busy_q;
  assign pll_error                   = u_dut.s_pll_error_q;
  assign pll_error_reason            = u_dut.s_pll_error_reason_q;
  assign pll_rsp_valid               = pll_ctrl.rsp_valid_i;
  assign fault_valid                 = f_fault_valid;
  assign fault_addr                  = f_fault_addr;
  assign fault_wstrb                 = f_fault_wstrb;
  assign fault_reserved              = f_fault_reserved;
  assign fault_pending               = u_dut.s_fault_pending_q;
  assign fault_write                 = u_dut.s_fault_write_q;
  assign fault_reason                = u_dut.s_fault_reason_q;
  assign fault_addr_q                = u_dut.s_fault_addr_q;
  assign fault_count                 = u_dut.s_fault_count_q;

  nmi_sysctrl u_dut (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .fault_valid_i   (f_fault_valid),
      .fault_addr_i    (f_fault_addr),
      .fault_wstrb_i   (f_fault_wstrb),
      .fault_reserved_i(f_fault_reserved),
      .nmi             (nmi),
      .sysctrl         (sysctrl),
      .pll_ctrl        (pll_ctrl)
  );

  initial begin
    rst_n_i      = 1'b0;
    f_past_valid = 1'b0;
  end

  always_ff @(posedge clk_i) begin
    rst_n_i      <= 1'b1;
    f_past_valid <= 1'b1;
  end

endmodule
