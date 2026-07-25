// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module sysctrl_formal;

  localparam [7:0] SYSCTRL_IPSEL_OFFSET = 8'h04;
  localparam [7:0] SYSCTRL_PLL_CFG_OFFSET = 8'h08;
  localparam [7:0] SYSCTRL_PLL_CMD_OFFSET = 8'h0c;
  localparam [7:0] SYSCTRL_FAULT_STATUS_OFFSET = 8'h10;

  (* anyseq *) (* gclk *)reg         clk_i;
  wire        rst_n_i;
  wire        f_past_valid;
  wire        nmi_valid;
  wire [31:0] nmi_addr;
  wire [31:0] nmi_wdata;
  wire [ 3:0] nmi_wstrb;
  wire        nmi_ready;
  wire [ 7:0] ip_sel;
  wire [ 4:0] core_sel;
  wire [ 2:0] pll_cfg;
  wire        pll_req_valid;
  wire        pll_req_ready;
  wire        pll_busy;
  wire        pll_error;
  wire [ 1:0] pll_error_reason;
  wire        pll_rsp_valid;
  wire        fault_valid;
  wire [31:0] fault_addr;
  wire [ 3:0] fault_wstrb;
  wire        fault_reserved;
  wire        fault_pending;
  wire        fault_write;
  wire [ 1:0] fault_reason;
  wire [31:0] fault_addr_q;
  wire [31:0] fault_count;

  sysctrl_formal_design u_design (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .f_past_valid    (f_past_valid),
      .nmi_valid       (nmi_valid),
      .nmi_addr        (nmi_addr),
      .nmi_wdata       (nmi_wdata),
      .nmi_wstrb       (nmi_wstrb),
      .nmi_ready       (nmi_ready),
      .ip_sel          (ip_sel),
      .core_sel        (core_sel),
      .pll_cfg         (pll_cfg),
      .pll_req_valid   (pll_req_valid),
      .pll_req_ready   (pll_req_ready),
      .pll_busy        (pll_busy),
      .pll_error       (pll_error),
      .pll_error_reason(pll_error_reason),
      .pll_rsp_valid   (pll_rsp_valid),
      .fault_valid     (fault_valid),
      .fault_addr      (fault_addr),
      .fault_wstrb     (fault_wstrb),
      .fault_reserved  (fault_reserved),
      .fault_pending   (fault_pending),
      .fault_write     (fault_write),
      .fault_reason    (fault_reason),
      .fault_addr_q    (fault_addr_q),
      .fault_count     (fault_count)
  );

  always @(posedge clk_i) begin
    if (f_past_valid && $past(rst_n_i && nmi_valid && !nmi_ready)) begin
      assume (nmi_valid);
      assume (nmi_addr == $past(nmi_addr));
      assume (nmi_wdata == $past(nmi_wdata));
      assume (nmi_wstrb == $past(nmi_wstrb));
    end
    if (rst_n_i && pll_rsp_valid) begin
      assume (pll_busy);
    end

    if (rst_n_i && f_past_valid) begin
      if ($past(
              rst_n_i && nmi_valid && !nmi_ready && |nmi_wstrb &&
                nmi_addr[7:0] == SYSCTRL_IPSEL_OFFSET
          )) begin
        assert (ip_sel == $past(nmi_wdata[7:0]));
      end
      if ($past(
              rst_n_i && nmi_valid && !nmi_ready && nmi_wstrb[0] &&
                nmi_addr[7:0] == SYSCTRL_PLL_CFG_OFFSET
          )) begin
        assert (pll_cfg == $past(nmi_wdata[2:0]));
      end
      if ($past(
              rst_n_i && nmi_valid && !nmi_ready && nmi_wstrb[0] && nmi_wdata[0] &&
                nmi_addr[7:0] == SYSCTRL_PLL_CMD_OFFSET && !pll_busy && !pll_req_valid
          )) begin
        assert (pll_busy);
      end
      if ($past(
              rst_n_i && nmi_valid && !nmi_ready && nmi_wstrb[0] && nmi_wdata[0] &&
                nmi_addr[7:0] == SYSCTRL_PLL_CMD_OFFSET && pll_busy
          )) begin
        assert (pll_error);
        if (!$past(pll_rsp_valid)) begin
          assert (pll_error_reason == 2'd3);
        end
      end
      if ($past(rst_n_i && fault_valid)) begin
        assert (fault_pending);
        assert (fault_write == (|$past(fault_wstrb)));
        assert (fault_reason == ($past(fault_reserved) ? 2'd2 : 2'd1));
        assert (fault_addr_q == $past(fault_addr));
        if (!$past(&fault_count)) begin
          assert (fault_count == $past(fault_count) + 32'd1);
        end
      end
      if ($past(
              rst_n_i && nmi_valid && !nmi_ready && nmi_wstrb[0] && nmi_wdata[0] &&
                nmi_addr[7:0] == SYSCTRL_FAULT_STATUS_OFFSET && !fault_valid
          )) begin
        assert (!fault_pending);
      end
    end

    if (rst_n_i) begin
      cover (pll_busy && pll_req_valid);
      cover (pll_error && pll_error_reason == 2'd3);
      cover (fault_pending && fault_reason == 2'd2);
    end
  end

endmodule
