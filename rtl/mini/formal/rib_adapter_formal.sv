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
    output logic [ 2:0] rsp_code,
    output logic [ 1:0] rsp_beat,
    output logic        rsp_last,
    output logic        legacy_valid,
    output logic        legacy_ready,
    output logic [31:0] legacy_addr,
    output logic [31:0] legacy_wdata,
    output logic [ 3:0] legacy_wstrb,
    output logic        source_valid,
    output logic        source_ready,
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
    output logic        adapted_wlast
);

  soc_rib_burst_if burst_source ();
  rib_if legacy_target ();
  soc_rib_if legacy_source ();
  soc_rib_burst_if burst_target ();

  (* anyseq *)logic        f_cmd_valid;
  (* anyseq *)logic [31:0] f_cmd_addr;
  (* anyseq *)logic        f_cmd_write;
  (* anyseq *)logic [ 1:0] f_cmd_len;
  (* anyseq *)logic        f_w_valid;
  (* anyseq *)logic [31:0] f_wdata;
  (* anyseq *)logic [ 3:0] f_wstrb;
  (* anyseq *)logic        f_wlast;
  (* anyseq *)logic        f_rsp_ready;
  (* anyseq *)logic        f_legacy_ready;
  (* anyseq *)logic [31:0] f_legacy_rdata;
  (* anyseq *)logic        f_legacy_error;
  (* anyseq *)logic [ 2:0] f_legacy_code;

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

  assign burst_source.cmd_valid = f_cmd_valid;
  assign burst_source.cmd_addr  = f_cmd_addr;
  assign burst_source.cmd_write = f_cmd_write;
  assign burst_source.cmd_len   = f_cmd_len;
  assign burst_source.w_valid   = f_w_valid;
  assign burst_source.wdata     = f_wdata;
  assign burst_source.wstrb     = f_wstrb;
  assign burst_source.wlast     = f_wlast;
  assign burst_source.rsp_ready = f_rsp_ready;
  assign legacy_target.ready    = f_legacy_ready;
  assign legacy_target.rdata    = f_legacy_rdata;

  soc_rib_burst_to_legacy u_burst_to_legacy (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .legacy_resp_err_i (f_legacy_error),
      .legacy_resp_code_i(f_legacy_code),
      .burst             (burst_source),
      .legacy            (legacy_target)
  );

  assign legacy_source.valid    = f_source_valid;
  assign legacy_source.addr     = f_source_addr;
  assign legacy_source.wdata    = f_source_wdata;
  assign legacy_source.wstrb    = f_source_wstrb;
  assign burst_target.cmd_ready = f_target_cmd_ready;
  assign burst_target.w_ready   = f_target_w_ready;
  assign burst_target.rsp_valid = f_target_rsp_valid;
  assign burst_target.rdata     = f_target_rdata;
  assign burst_target.resp_err  = f_target_error;
  assign burst_target.resp_code = f_target_code;
  assign burst_target.rsp_beat  = '0;
  assign burst_target.rsp_last  = 1'b1;

  soc_rib_legacy_to_burst u_legacy_to_burst (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .legacy (legacy_source),
      .burst  (burst_target)
  );

  assign cmd_valid         = burst_source.cmd_valid;
  assign cmd_ready         = burst_source.cmd_ready;
  assign cmd_addr          = burst_source.cmd_addr;
  assign cmd_write         = burst_source.cmd_write;
  assign cmd_len           = burst_source.cmd_len;
  assign w_valid           = burst_source.w_valid;
  assign w_ready           = burst_source.w_ready;
  assign wdata             = burst_source.wdata;
  assign wstrb             = burst_source.wstrb;
  assign wlast             = burst_source.wlast;
  assign rsp_valid         = burst_source.rsp_valid;
  assign rsp_ready         = burst_source.rsp_ready;
  assign rsp_rdata         = burst_source.rdata;
  assign rsp_code          = burst_source.resp_code;
  assign rsp_beat          = burst_source.rsp_beat;
  assign rsp_last          = burst_source.rsp_last;
  assign legacy_valid      = legacy_target.valid;
  assign legacy_ready      = legacy_target.ready;
  assign legacy_addr       = legacy_target.addr;
  assign legacy_wdata      = legacy_target.wdata;
  assign legacy_wstrb      = legacy_target.wstrb;

  assign source_valid      = legacy_source.valid;
  assign source_ready      = legacy_source.ready;
  assign source_addr       = legacy_source.addr;
  assign source_wstrb      = legacy_source.wstrb;
  assign adapted_cmd_valid = burst_target.cmd_valid;
  assign adapted_cmd_ready = burst_target.cmd_ready;
  assign adapted_cmd_addr  = burst_target.cmd_addr;
  assign adapted_cmd_len   = burst_target.cmd_len;
  assign adapted_w_valid   = burst_target.w_valid;
  assign adapted_w_ready   = burst_target.w_ready;
  assign adapted_wdata     = burst_target.wdata;
  assign adapted_wstrb     = burst_target.wstrb;
  assign adapted_wlast     = burst_target.wlast;

  initial begin
    rst_n_i      = 1'b0;
    f_past_valid = 1'b0;
  end
  always_ff @(posedge clk_i) begin
    rst_n_i      <= 1'b1;
    f_past_valid <= 1'b1;
  end

endmodule
