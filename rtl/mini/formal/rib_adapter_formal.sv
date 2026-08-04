// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module rib_adapter_formal_design (
    input  logic        clk_i,
    output logic        rst_n_i,
    output logic        f_past_valid,
    output logic        cmd_valid,
    output logic        cmd_ready,
    output logic [31:0] cmd_addr,
    output logic        cmd_write,
    output logic [ 1:0] cmd_len,
    output logic        w_valid,
    output logic        w_ready,
    output logic [31:0] wdata,
    output logic [ 3:0] wstrb,
    output logic        wlast,
    output logic        rsp_valid,
    output logic        rsp_ready,
    output logic [31:0] rsp_rdata,
    output logic        rsp_error,
    output logic [ 2:0] rsp_code,
    output logic [ 1:0] rsp_beat,
    output logic        rsp_last,
    output logic        ribp_valid,
    output logic        ribp_ready,
    output logic        ribp_resp_err,
    output logic [31:0] ribp_addr,
    output logic [31:0] ribp_wdata,
    output logic [ 3:0] ribp_wstrb,
    output logic        source_valid,
    output logic        source_ready,
    output logic        source_resp_err,
    output logic [31:0] source_addr,
    output logic [ 3:0] source_wstrb,
    output logic        adapted_cmd_valid,
    output logic        adapted_cmd_ready,
    output logic [31:0] adapted_cmd_addr,
    output logic [ 1:0] adapted_cmd_len,
    output logic        adapted_w_valid,
    output logic        adapted_w_ready,
    output logic [31:0] adapted_wdata,
    output logic [ 3:0] adapted_wstrb,
    output logic        adapted_wlast,
    output logic        adapted_rsp_error
);

  rib_if rib_source ();
  ribp_if ribp_target ();
  ribp_if ribp_source ();
  rib_if rib_target ();

  (* anyseq *)logic        f_cmd_valid;
  (* anyseq *)logic [31:0] f_cmd_addr;
  (* anyseq *)logic        f_cmd_write;
  (* anyseq *)logic [ 1:0] f_cmd_len;
  (* anyseq *)logic        f_w_valid;
  (* anyseq *)logic [31:0] f_wdata;
  (* anyseq *)logic [ 3:0] f_wstrb;
  (* anyseq *)logic        f_wlast;
  (* anyseq *)logic        f_rsp_ready;
  (* anyseq *)logic        f_ribp_ready;
  (* anyseq *)logic [31:0] f_ribp_rdata;
  (* anyseq *)logic        f_ribp_error;

  (* anyseq *)logic        f_source_valid;
  (* anyseq *)logic [31:0] f_source_addr;
  (* anyseq *)logic [31:0] f_source_wdata;
  (* anyseq *)logic [ 3:0] f_source_wstrb;
  (* anyseq *)logic        f_target_cmd_ready;
  (* anyseq *)logic        f_target_w_ready;
  (* anyseq *)logic        f_target_rsp_valid;
  (* anyseq *)logic [31:0] f_target_rdata;
  (* anyseq *)logic        f_target_error;
  (* anyseq *)logic [ 2:0] f_target_code;

  assign rib_source.cmd_valid = f_cmd_valid;
  assign rib_source.cmd_addr  = f_cmd_addr;
  assign rib_source.cmd_write = f_cmd_write;
  assign rib_source.cmd_len   = f_cmd_len;
  assign rib_source.w_valid   = f_w_valid;
  assign rib_source.wdata     = f_wdata;
  assign rib_source.wstrb     = f_wstrb;
  assign rib_source.wlast     = f_wlast;
  assign rib_source.rsp_ready = f_rsp_ready;
  assign ribp_target.ready    = f_ribp_ready;
  assign ribp_target.rdata    = f_ribp_rdata;
  assign ribp_target.resp_err = f_ribp_error;

  rib2ribp u_rib2ribp (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .rib    (rib_source),
      .ribp   (ribp_target)
  );

  assign ribp_source.valid    = f_source_valid;
  assign ribp_source.addr     = f_source_addr;
  assign ribp_source.wdata    = f_source_wdata;
  assign ribp_source.wstrb    = f_source_wstrb;
  assign rib_target.cmd_ready = f_target_cmd_ready;
  assign rib_target.w_ready   = f_target_w_ready;
  assign rib_target.rsp_valid = f_target_rsp_valid;
  assign rib_target.rdata     = f_target_rdata;
  assign rib_target.resp_err  = f_target_error;
  assign rib_target.resp_code = f_target_code;
  assign rib_target.rsp_beat  = '0;
  assign rib_target.rsp_last  = 1'b1;

  ribp2rib u_ribp2rib (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .ribp   (ribp_source),
      .rib    (rib_target)
  );

  assign cmd_valid         = rib_source.cmd_valid;
  assign cmd_ready         = rib_source.cmd_ready;
  assign cmd_addr          = rib_source.cmd_addr;
  assign cmd_write         = rib_source.cmd_write;
  assign cmd_len           = rib_source.cmd_len;
  assign w_valid           = rib_source.w_valid;
  assign w_ready           = rib_source.w_ready;
  assign wdata             = rib_source.wdata;
  assign wstrb             = rib_source.wstrb;
  assign wlast             = rib_source.wlast;
  assign rsp_valid         = rib_source.rsp_valid;
  assign rsp_ready         = rib_source.rsp_ready;
  assign rsp_rdata         = rib_source.rdata;
  assign rsp_error         = rib_source.resp_err;
  assign rsp_code          = rib_source.resp_code;
  assign rsp_beat          = rib_source.rsp_beat;
  assign rsp_last          = rib_source.rsp_last;
  assign ribp_valid        = ribp_target.valid;
  assign ribp_ready        = ribp_target.ready;
  assign ribp_resp_err     = ribp_target.resp_err;
  assign ribp_addr         = ribp_target.addr;
  assign ribp_wdata        = ribp_target.wdata;
  assign ribp_wstrb        = ribp_target.wstrb;

  assign source_valid      = ribp_source.valid;
  assign source_ready      = ribp_source.ready;
  assign source_resp_err   = ribp_source.resp_err;
  assign source_addr       = ribp_source.addr;
  assign source_wstrb      = ribp_source.wstrb;
  assign adapted_cmd_valid = rib_target.cmd_valid;
  assign adapted_cmd_ready = rib_target.cmd_ready;
  assign adapted_cmd_addr  = rib_target.cmd_addr;
  assign adapted_cmd_len   = rib_target.cmd_len;
  assign adapted_w_valid   = rib_target.w_valid;
  assign adapted_w_ready   = rib_target.w_ready;
  assign adapted_wdata     = rib_target.wdata;
  assign adapted_wstrb     = rib_target.wstrb;
  assign adapted_wlast     = rib_target.wlast;
  assign adapted_rsp_error = rib_target.resp_err;

  initial begin
    rst_n_i      = 1'b0;
    f_past_valid = 1'b0;
  end
  always_ff @(posedge clk_i) begin
    rst_n_i      <= 1'b1;
    f_past_valid <= 1'b1;
  end

endmodule
