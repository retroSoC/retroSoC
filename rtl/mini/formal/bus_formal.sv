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
    output logic        rib_valid,
    output logic        apb_valid,
    output logic        fault_valid,
    output logic        fault_access,
    output logic        arb_locked,
    output logic [ 1:0] arb_owner
);

  soc_rib_if mgmt_rib ();
  soc_rib_if user_rib ();
  soc_rib_if dma_rib ();
  rib_if rib ();
  rib_if apb_rib ();

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
  (* anyseq *)logic        f_rib_ready;
  (* anyseq *)logic [31:0] f_rib_rdata;
  (* anyseq *)logic        f_apb_ready;
  (* anyseq *)logic [31:0] f_apb_rdata;
  logic [31:0] fault_addr;
  logic [ 3:0] fault_wstrb;
  logic        fault_reserved;
  logic [ 1:0] fault_master;
  logic        user_idle;

  assign mgmt_rib.valid = f_mgmt_valid;
  assign mgmt_rib.addr  = f_mgmt_addr;
  assign mgmt_rib.wdata = f_mgmt_wdata;
  assign mgmt_rib.wstrb = f_mgmt_wstrb;
  assign user_rib.valid = f_user_valid;
  assign user_rib.addr  = f_user_addr;
  assign user_rib.wdata = f_user_wdata;
  assign user_rib.wstrb = f_user_wstrb;
  assign dma_rib.valid  = f_dma_valid;
  assign dma_rib.addr   = f_dma_addr;
  assign dma_rib.wdata  = f_dma_wdata;
  assign dma_rib.wstrb  = f_dma_wstrb;
  assign rib.ready      = f_rib_ready;
  assign rib.rdata      = f_rib_rdata;
  assign apb_rib.ready  = f_apb_ready;
  assign apb_rib.rdata  = f_apb_rdata;

  assign mgmt_valid     = mgmt_rib.valid;
  assign mgmt_addr      = mgmt_rib.addr;
  assign mgmt_wstrb     = mgmt_rib.wstrb;
  assign mgmt_ready     = mgmt_rib.ready;
  assign user_valid     = user_rib.valid;
  assign user_addr      = user_rib.addr;
  assign user_wstrb     = user_rib.wstrb;
  assign user_ready     = user_rib.ready;
  assign dma_valid      = dma_rib.valid;
  assign dma_ready      = dma_rib.ready;
  assign rib_valid      = rib.valid;
  assign apb_valid      = apb_rib.valid;

  bus u_dut (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .mgmt_rib         (mgmt_rib),
      .user_rib         (user_rib),
      .dma_rib          (dma_rib),
      .user_bus_enable_i(1'b1),
      .user_bus_idle_o  (user_idle),
      .rib              (rib),
      .apb_rib          (apb_rib),
      .apb_resp_err_i   (1'b0),
      .perf_enable_i    (1'b0),
      .perf_clear_i     (1'b0),
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
