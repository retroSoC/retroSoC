module merge_mstr_wrapper (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic [ 4:0] sel_i,
    output logic        core_valid_o,
    output logic [31:0] core_addr_o,
    output logic [31:0] core_wdata_o,
    output logic [ 3:0] core_wstrb_o,
    input  logic [31:0] core_rdata_i,
    input  logic        core_ready_i,
    input  logic [31:0] irq_i
);
  // mgmt
  logic        s_mgmt_core_valid;
  logic [31:0] s_mgmt_core_addr;
  logic [31:0] s_mgmt_core_wdata;
  logic [ 3:0] s_mgmt_core_wstrb;
  logic [31:0] s_mgmt_core_rdata;
  logic        s_mgmt_core_ready;
  logic [31:0] s_mgmt_irq;
  //user
  logic        s_user_core_valid;
  logic [31:0] s_user_core_addr;
  logic [31:0] s_user_core_wdata;
  logic [ 3:0] s_user_core_wstrb;
  logic [31:0] s_user_core_rdata;
  logic        s_user_core_ready;
  logic [31:0] s_user_irq;

  assign core_valid_o      = sel_i == '0 ? s_mgmt_core_valid : s_user_core_valid;
  assign core_addr_o       = sel_i == '0 ? s_mgmt_core_addr : s_user_core_addr;
  assign core_wdata_o      = sel_i == '0 ? s_mgmt_core_wdata : s_user_core_wdata;
  assign core_wstrb_o      = sel_i == '0 ? s_mgmt_core_wstrb : s_user_core_wstrb;

  assign s_mgmt_core_rdata = sel_i == '0 ? core_rdata_i : '0;
  assign s_mgmt_core_ready = sel_i == '0 ? core_ready_i : '0;
  assign s_mgmt_irq        = sel_i == '0 ? irq_i : '0;

  assign s_user_core_rdata = sel_i != '0 ? core_rdata_i : '0;
  assign s_user_core_ready = sel_i != '0 ? core_ready_i : '0;
  assign s_user_irq        = sel_i != '0 ? irq_i : '0;


  mgmt_wrapper u_mgmt_wrapper (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .core_valid_o(s_mgmt_core_valid),
      .core_addr_o (s_mgmt_core_addr),
      .core_wdata_o(s_mgmt_core_wdata),
      .core_wstrb_o(s_mgmt_core_wstrb),
      .core_rdata_i(s_mgmt_core_rdata),
      .core_ready_i(s_mgmt_core_ready),
      .irq_i       (s_mgmt_irq)
  );

  user_mstr_wrapper u_user_mstr_wrapper (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .sel_i       (sel_i),
      .core_valid_o(s_user_core_valid),
      .core_addr_o (s_user_core_addr),
      .core_wdata_o(s_user_core_wdata),
      .core_wstrb_o(s_user_core_wstrb),
      .core_rdata_i(s_user_core_rdata),
      .core_ready_i(s_user_core_ready),
      .irq_i       (s_user_irq)
  );

endmodule
