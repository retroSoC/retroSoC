// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module apb4_plic #(
    parameter int NumSources  = 32,
    parameter int NumContexts = 2
) (
    // verilog_format: off -- preserve APB and interrupt alignment
    input  logic                   clk_i,
    input  logic                   rst_n_i,
    input  logic [NumSources-1:0]  source_i,
    apb4_if.slave                  apb4,
    output logic [NumContexts-1:0] context_irq_o
    // verilog_format: on
);
  localparam int SourceWidth = $clog2(NumSources);

  logic        s_req_accept;
  logic        s_write;
  logic [25:0] s_offset;
  logic s_ready_d, s_ready_q;
  logic s_resp_err_d, s_resp_err_q;
  logic [31:0] s_rdata_d, s_rdata_q;
  logic [2:0] s_priority_d[NumSources], s_priority_q[NumSources];
  logic [NumSources-1:0] s_pending_d, s_pending_q;
  logic [NumSources-1:0] s_claimed_d, s_claimed_q;
  logic [NumSources-1:0] s_en_d[NumContexts], s_en_q[NumContexts];
  logic [2:0] s_threshold_d[NumContexts], s_threshold_q[NumContexts];
  logic [SourceWidth-1:0] s_claim_id      [NumContexts];
  logic [            2:0] s_claim_priority[NumContexts];
  logic                   s_priority_sel;
  logic                   s_pending_sel;
  logic                   s_en_sel        [NumContexts];
  logic                   s_threshold_sel [NumContexts];
  logic                   s_claim_sel     [NumContexts];
  logic [SourceWidth-1:0] s_priority_src;

  assign s_req_accept   = apb4.psel && apb4.penable && !s_ready_q;
  assign s_write        = apb4.pwrite;
  assign s_offset       = apb4.paddr[25:0];
  assign s_priority_sel = (s_offset < 26'h0001000) && (s_offset[1:0] == 2'b00);
  assign s_priority_src = s_offset[SourceWidth+1:2];
  assign s_pending_sel  = s_offset == 26'h0001000;
  for (genvar ctx = 0; ctx < NumContexts; ctx++) begin : gen_select
    assign s_en_sel[ctx]        = s_offset == (26'h0002000 + 26'(ctx * 128));
    assign s_threshold_sel[ctx] = s_offset == (26'h0200000 + 26'(ctx * 4096));
    assign s_claim_sel[ctx]     = s_offset == (26'h0200004 + 26'(ctx * 4096));
  end

  always_comb begin
    for (int ctx = 0; ctx < NumContexts; ctx++) begin
      s_claim_id[ctx]       = '0;
      s_claim_priority[ctx] = '0;
      for (int source = 1; source < NumSources; source++) begin
        if (s_pending_q[source] && s_en_q[ctx][source] &&
            (s_priority_q[source] > s_threshold_q[ctx]) &&
            ((s_priority_q[source] > s_claim_priority[ctx]) ||
             ((s_priority_q[source] == s_claim_priority[ctx]) &&
              ((s_claim_id[ctx] == '0) || (source < s_claim_id[ctx]))))) begin
          s_claim_id[ctx]       = SourceWidth'(source);
          s_claim_priority[ctx] = s_priority_q[source];
        end
      end
      context_irq_o[ctx] = s_claim_id[ctx] != '0;
    end
  end

  always_comb begin
    s_rdata_d    = '0;
    s_resp_err_d = 1'b0;
    if (s_priority_sel && ({1'b0, s_priority_src} < (SourceWidth + 1)'(NumSources))) begin
      s_rdata_d = {29'd0, s_priority_q[s_priority_src]};
    end else if (s_pending_sel) begin
      s_rdata_d = 32'(s_pending_q);
    end else begin
      s_resp_err_d = 1'b1;
      for (int ctx = 0; ctx < NumContexts; ctx++) begin
        if (s_en_sel[ctx]) begin
          s_rdata_d    = 32'(s_en_q[ctx]);
          s_resp_err_d = 1'b0;
        end
        if (s_threshold_sel[ctx]) begin
          s_rdata_d    = {29'd0, s_threshold_q[ctx]};
          s_resp_err_d = 1'b0;
        end
        if (s_claim_sel[ctx]) begin
          s_rdata_d    = 32'(s_claim_id[ctx]);
          s_resp_err_d = 1'b0;
        end
      end
    end
    if (s_write && s_pending_sel) s_resp_err_d = 1'b1;
  end

  always_comb begin
    for (int source = 0; source < NumSources; source++) begin
      s_priority_d[source] = s_priority_q[source];
    end
    for (int ctx = 0; ctx < NumContexts; ctx++) begin
      s_en_d[ctx]        = s_en_q[ctx];
      s_threshold_d[ctx] = s_threshold_q[ctx];
    end
    s_pending_d    = s_pending_q;
    s_claimed_d    = s_claimed_q;
    s_pending_d[0] = 1'b0;
    s_claimed_d[0] = 1'b0;
    for (int source = 1; source < NumSources; source++) begin
      if (source_i[source] && !s_claimed_q[source]) s_pending_d[source] = 1'b1;
    end

    if (s_req_accept && s_write && !s_resp_err_d) begin
      if (s_priority_sel && (s_priority_src != '0) && apb4.pstrb[0]) begin
        s_priority_d[s_priority_src] = apb4.pwdata[2:0];
      end
      for (int ctx = 0; ctx < NumContexts; ctx++) begin
        if (s_en_sel[ctx]) begin
          for (int byte_index = 0; byte_index < 4; byte_index++) begin
            if (apb4.pstrb[byte_index]) begin
              s_en_d[ctx][byte_index*8+:8] = apb4.pwdata[byte_index*8+:8];
            end
          end
          s_en_d[ctx][0] = 1'b0;
        end
        if (s_threshold_sel[ctx] && apb4.pstrb[0]) begin
          s_threshold_d[ctx] = apb4.pwdata[2:0];
        end
        if (s_claim_sel[ctx] && (apb4.pwdata[SourceWidth-1:0] != '0) &&
            ({1'b0, apb4.pwdata[SourceWidth-1:0]} < (SourceWidth + 1)'(NumSources))) begin
          s_claimed_d[apb4.pwdata[SourceWidth-1:0]] = 1'b0;
        end
      end
    end

    if (s_req_accept && !s_write) begin
      for (int ctx = 0; ctx < NumContexts; ctx++) begin
        if (s_claim_sel[ctx] && (s_claim_id[ctx] != '0)) begin
          s_pending_d[s_claim_id[ctx]] = 1'b0;
          s_claimed_d[s_claim_id[ctx]] = 1'b1;
        end
      end
    end
  end

  assign s_ready_d    = s_req_accept;
  assign apb4.pready  = s_ready_q;
  assign apb4.pslverr = s_resp_err_q;
  assign apb4.prdata  = s_rdata_q;

  for (genvar source = 0; source < NumSources; source++) begin : gen_priority
    dffr #(
        .DATA_WIDTH(3)
    ) u_priority_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_priority_d[source]),
        .dat_o  (s_priority_q[source])
    );
  end
  for (genvar ctx = 0; ctx < NumContexts; ctx++) begin : gen_context
    dffr #(
        .DATA_WIDTH(NumSources)
    ) u_enable_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_en_d[ctx]),
        .dat_o  (s_en_q[ctx])
    );
    dffr #(
        .DATA_WIDTH(3)
    ) u_threshold_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_threshold_d[ctx]),
        .dat_o  (s_threshold_q[ctx])
    );
  end
  dffr #(
      .DATA_WIDTH(NumSources)
  ) u_pending_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_pending_d),
      .dat_o  (s_pending_q)
  );
  dffr #(
      .DATA_WIDTH(NumSources)
  ) u_claimed_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_claimed_d),
      .dat_o  (s_claimed_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_ready_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ready_d),
      .dat_o  (s_ready_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_resp_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_req_accept && s_resp_err_d),
      .dat_o  (s_resp_err_q)
  );
  dffer #(
      .DATA_WIDTH(32)
  ) u_rdata_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_req_accept && !s_write),
      .dat_i  (s_rdata_d),
      .dat_o  (s_rdata_q)
  );

`ifndef SYNTHESIS
  initial begin
    if ((NumSources != 32) || (NumContexts != 2)) begin
      $fatal(1, "apb4_plic: Mini HP profile requires 32 sources and two contexts");
    end
  end
`endif
endmodule
