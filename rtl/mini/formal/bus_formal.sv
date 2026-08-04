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
    output logic        user_cmd_valid,
    output logic        user_cmd_ready,
    output logic [31:0] user_cmd_addr,
    output logic        user_cmd_write,
    output logic [ 1:0] user_cmd_len,
    output logic        dma_cmd_valid,
    output logic        dma_cmd_ready,
    output logic [31:0] dma_cmd_addr,
    output logic        dma_cmd_write,
    output logic [ 1:0] dma_cmd_len,
    output logic        rib_cmd_valid,
    output logic [ 1:0] rib_cmd_len,
    output logic        apb_valid,
    output logic        fault_valid,
    output logic        fault_access,
    output logic        arb_locked,
    output logic [ 1:0] arb_owner,
    output logic        cmd_accepted,
    output logic        terminal_rsp
);

  ribp_if mgmt_ribp ();
  rib_if user_rib ();
  rib_if dma_rib ();
  rib_if rib ();
  ribp_if apb_ribp ();

  (* anyseq *)logic        f_mgmt_valid;
  (* anyseq *)logic [31:0] f_mgmt_addr;
  (* anyseq *)logic [31:0] f_mgmt_wdata;
  (* anyseq *)logic [ 3:0] f_mgmt_wstrb;
  (* anyseq *)logic        f_user_cmd_valid;
  (* anyseq *)logic [31:0] f_user_cmd_addr;
  (* anyseq *)logic        f_user_cmd_write;
  (* anyseq *)logic [ 1:0] f_user_cmd_len;
  (* anyseq *)logic        f_user_w_valid;
  (* anyseq *)logic [31:0] f_user_wdata;
  (* anyseq *)logic [ 3:0] f_user_wstrb;
  (* anyseq *)logic        f_user_wlast;
  (* anyseq *)logic        f_user_rsp_ready;
  (* anyseq *)logic        f_dma_cmd_valid;
  (* anyseq *)logic [31:0] f_dma_cmd_addr;
  (* anyseq *)logic        f_dma_cmd_write;
  (* anyseq *)logic [ 1:0] f_dma_cmd_len;
  (* anyseq *)logic        f_dma_w_valid;
  (* anyseq *)logic [31:0] f_dma_wdata;
  (* anyseq *)logic [ 3:0] f_dma_wstrb;
  (* anyseq *)logic        f_dma_wlast;
  (* anyseq *)logic        f_dma_rsp_ready;

  logic        target_active_q;
  logic        target_write_q;
  logic        target_write_done_q;
  logic [ 1:0] target_len_q;
  logic [ 1:0] target_beat_q;
  logic [31:0] fault_addr;
  logic [ 3:0] fault_wstrb;
  logic        fault_reserved;
  logic [ 1:0] fault_master;
  logic [ 2:0] fault_code;
  logic        user_idle;

  assign mgmt_ribp.valid    = f_mgmt_valid;
  assign mgmt_ribp.addr     = f_mgmt_addr;
  assign mgmt_ribp.wdata    = f_mgmt_wdata;
  assign mgmt_ribp.wstrb    = f_mgmt_wstrb;

  assign user_rib.cmd_valid = f_user_cmd_valid;
  assign user_rib.cmd_addr  = f_user_cmd_addr;
  assign user_rib.cmd_write = f_user_cmd_write;
  assign user_rib.cmd_len   = f_user_cmd_len;
  assign user_rib.w_valid   = f_user_w_valid;
  assign user_rib.wdata     = f_user_wdata;
  assign user_rib.wstrb     = f_user_wstrb;
  assign user_rib.wlast     = f_user_wlast;
  assign user_rib.rsp_ready = f_user_rsp_ready;

  assign dma_rib.cmd_valid  = f_dma_cmd_valid;
  assign dma_rib.cmd_addr   = f_dma_cmd_addr;
  assign dma_rib.cmd_write  = f_dma_cmd_write;
  assign dma_rib.cmd_len    = f_dma_cmd_len;
  assign dma_rib.w_valid    = f_dma_w_valid;
  assign dma_rib.wdata      = f_dma_wdata;
  assign dma_rib.wstrb      = f_dma_wstrb;
  assign dma_rib.wlast      = f_dma_wlast;
  assign dma_rib.rsp_ready  = f_dma_rsp_ready;

  assign rib.cmd_ready      = ~target_active_q;
  assign rib.w_ready        = target_active_q && target_write_q && ~target_write_done_q;
  assign rib.rsp_valid      = target_active_q && (~target_write_q || target_write_done_q);
  assign rib.rdata          = 32'hCAFE_0000 | {30'd0, target_beat_q};
  assign rib.resp_err       = 1'b0;
  assign rib.resp_code      = `RIB_RESP_OK;
  assign rib.rsp_beat       = target_beat_q;
  assign rib.rsp_last       = target_write_q || (target_beat_q == target_len_q);

  always_ff @(posedge clk_i) begin
    if (!rst_n_i) begin
      target_active_q     <= 1'b0;
      target_write_q      <= 1'b0;
      target_write_done_q <= 1'b0;
      target_len_q        <= '0;
      target_beat_q       <= '0;
    end else begin
      if (rib.cmd_valid && rib.cmd_ready) begin
        target_active_q     <= 1'b1;
        target_write_q      <= rib.cmd_write;
        target_write_done_q <= 1'b0;
        target_len_q        <= rib.cmd_len;
        target_beat_q       <= '0;
      end
      if (rib.w_valid && rib.w_ready) begin
        if (rib.wlast) begin
          target_write_done_q <= 1'b1;
          target_beat_q       <= target_len_q;
        end else begin
          target_beat_q <= target_beat_q + 1'b1;
        end
      end
      if (rib.rsp_valid && rib.rsp_ready) begin
        if (rib.rsp_last) begin
          target_active_q <= 1'b0;
        end else begin
          target_beat_q <= target_beat_q + 1'b1;
        end
      end
    end
  end

  assign apb_ribp.ready    = apb_ribp.valid;
  assign apb_ribp.rdata    = 32'h1234_5678;
  assign apb_ribp.resp_err = 1'b0;

  assign mgmt_valid        = mgmt_ribp.valid;
  assign mgmt_addr         = mgmt_ribp.addr;
  assign mgmt_wstrb        = mgmt_ribp.wstrb;
  assign mgmt_ready        = mgmt_ribp.ready;
  assign user_cmd_valid    = user_rib.cmd_valid;
  assign user_cmd_ready    = user_rib.cmd_ready;
  assign user_cmd_addr     = user_rib.cmd_addr;
  assign user_cmd_write    = user_rib.cmd_write;
  assign user_cmd_len      = user_rib.cmd_len;
  assign dma_cmd_valid     = dma_rib.cmd_valid;
  assign dma_cmd_ready     = dma_rib.cmd_ready;
  assign dma_cmd_addr      = dma_rib.cmd_addr;
  assign dma_cmd_write     = dma_rib.cmd_write;
  assign dma_cmd_len       = dma_rib.cmd_len;
  assign rib_cmd_valid     = rib.cmd_valid;
  assign rib_cmd_len       = rib.cmd_len;
  assign apb_valid         = apb_ribp.valid;

  bus u_dut (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .mgmt_ribp        (mgmt_ribp),
      .user_rib         (user_rib),
      .dma_rib          (dma_rib),
      .user_bus_enable_i(1'b1),
      .user_bus_idle_o  (user_idle),
      .rib              (rib),
      .apb_ribp         (apb_ribp),
      .perf_enable_i    (1'b0),
      .perf_clear_i     (1'b0),
      .fault_valid_o    (fault_valid),
      .fault_addr_o     (fault_addr),
      .fault_wstrb_o    (fault_wstrb),
      .fault_reserved_o (fault_reserved),
      .fault_access_o   (fault_access),
      .fault_master_o   (fault_master),
      .fault_code_o     (fault_code),
      .perf_mgmt_wait_o (),
      .perf_user_wait_o (),
      .perf_dma_wait_o  (),
      .perf_ribp_wait_o (),
      .perf_apb_wait_o  (),
      .perf_sdram_wait_o(),
      .perf_psram_wait_o(),
      .perf_flash_wait_o()
  );

  assign arb_locked   = u_dut.s_mstr_lock_q;
  assign arb_owner    = u_dut.s_mstr_id_q;
  assign cmd_accepted = u_dut.s_cmd_accepted_q;
  assign terminal_rsp = u_dut.s_terminal_rsp;

  initial begin
    rst_n_i      = 1'b0;
    f_past_valid = 1'b0;
  end

  always_ff @(posedge clk_i) begin
    rst_n_i      <= 1'b1;
    f_past_valid <= 1'b1;
  end

endmodule
