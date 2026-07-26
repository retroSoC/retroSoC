// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module bus_formal_design (
    input  logic        clk_i,
    output logic        rst_n_i,
    output logic        f_past_valid,
    output logic        mgmt_valid,
    output logic [31:0] mgmt_addr,
    output logic [ 3:0] mgmt_wstrb,
    output logic        mgmt_ready,
    output logic        user_valid,
    output logic [31:0] user_addr,
    output logic [ 3:0] user_wstrb,
    output logic        user_ready,
    output logic        dma_valid,
    output logic        dma_ready,
    output logic        natv_valid,
    output logic        apb_valid,
    output logic        fault_valid,
    output logic        fault_access,
    output logic        arb_locked,
    output logic [ 1:0] arb_owner
);

  nmi_if mgmt_nmi ();
  nmi_if user_nmi ();
  nmi_if dma_nmi ();
  nmi_if natv_nmi ();
  nmi_if apb_nmi ();

  (* anyseq *)logic        f_mgmt_valid;
  (* anyseq *)logic [31:0] f_mgmt_addr;
  (* anyseq *)logic [31:0] f_mgmt_wdata;
  (* anyseq *)logic [ 3:0] f_mgmt_wstrb;
  (* anyseq *)logic        f_user_valid;
  (* anyseq *)logic [31:0] f_user_addr;
  (* anyseq *)logic [31:0] f_user_wdata;
  (* anyseq *)logic [ 3:0] f_user_wstrb;
  (* anyseq *)logic        f_dma_valid;
  (* anyseq *)logic [31:0] f_dma_addr;
  (* anyseq *)logic [31:0] f_dma_wdata;
  (* anyseq *)logic [ 3:0] f_dma_wstrb;
  (* anyseq *)logic        f_natv_ready;
  (* anyseq *)logic [31:0] f_natv_rdata;
  (* anyseq *)logic        f_apb_ready;
  (* anyseq *)logic [31:0] f_apb_rdata;
  logic [31:0] fault_addr;
  logic [ 3:0] fault_wstrb;
  logic        fault_reserved;
  logic [ 1:0] fault_master;
  logic        user_idle;

  assign mgmt_nmi.valid = f_mgmt_valid;
  assign mgmt_nmi.addr  = f_mgmt_addr;
  assign mgmt_nmi.wdata = f_mgmt_wdata;
  assign mgmt_nmi.wstrb = f_mgmt_wstrb;
  assign user_nmi.valid = f_user_valid;
  assign user_nmi.addr  = f_user_addr;
  assign user_nmi.wdata = f_user_wdata;
  assign user_nmi.wstrb = f_user_wstrb;
  assign dma_nmi.valid  = f_dma_valid;
  assign dma_nmi.addr   = f_dma_addr;
  assign dma_nmi.wdata  = f_dma_wdata;
  assign dma_nmi.wstrb  = f_dma_wstrb;
  assign natv_nmi.ready = f_natv_ready;
  assign natv_nmi.rdata = f_natv_rdata;
  assign apb_nmi.ready  = f_apb_ready;
  assign apb_nmi.rdata  = f_apb_rdata;

  assign mgmt_valid     = mgmt_nmi.valid;
  assign mgmt_addr      = mgmt_nmi.addr;
  assign mgmt_wstrb     = mgmt_nmi.wstrb;
  assign mgmt_ready     = mgmt_nmi.ready;
  assign user_valid     = user_nmi.valid;
  assign user_addr      = user_nmi.addr;
  assign user_wstrb     = user_nmi.wstrb;
  assign user_ready     = user_nmi.ready;
  assign dma_valid      = dma_nmi.valid;
  assign dma_ready      = dma_nmi.ready;
  assign natv_valid     = natv_nmi.valid;
  assign apb_valid      = apb_nmi.valid;

  bus u_dut (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .mgmt_nmi         (mgmt_nmi),
      .user_nmi         (user_nmi),
      .dma_nmi          (dma_nmi),
      .user_bus_enable_i(1'b1),
      .user_bus_idle_o  (user_idle),
      .natv_nmi         (natv_nmi),
      .apb_nmi          (apb_nmi),
      .fault_valid_o    (fault_valid),
      .fault_addr_o     (fault_addr),
      .fault_wstrb_o    (fault_wstrb),
      .fault_reserved_o (fault_reserved),
      .fault_access_o   (fault_access),
      .fault_master_o   (fault_master)
  );

  assign arb_locked = u_dut.s_mstr_lock_q;
  assign arb_owner  = u_dut.s_mstr_id_q;

  initial begin
    rst_n_i      = 1'b0;
    f_past_valid = 1'b0;
  end

  always_ff @(posedge clk_i) begin
    rst_n_i      <= 1'b1;
    f_past_valid <= 1'b1;
  end

endmodule
