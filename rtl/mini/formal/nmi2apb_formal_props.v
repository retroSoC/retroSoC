// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module nmi2apb_formal;

  localparam [1:0] FSM_SETP = 2'd1;
  localparam [1:0] FSM_ENAB = 2'd2;

  (* anyseq *) (* gclk *)reg         clk_i;
  wire        rst_n_i;
  wire        f_past_valid;
  wire        nmi_valid;
  wire [31:0] nmi_addr;
  wire [31:0] nmi_wdata;
  wire [ 3:0] nmi_wstrb;
  wire        nmi_ready;
  wire [ 8:0] psel_comb;
  wire [ 8:0] psel_q;
  wire        xfer_ready;
  wire [ 1:0] fsm_q;

  nmi2apb_formal_design u_design (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .f_past_valid(f_past_valid),
      .nmi_valid   (nmi_valid),
      .nmi_addr    (nmi_addr),
      .nmi_wdata   (nmi_wdata),
      .nmi_wstrb   (nmi_wstrb),
      .nmi_ready   (nmi_ready),
      .psel_comb   (psel_comb),
      .psel_q      (psel_q),
      .xfer_ready  (xfer_ready),
      .fsm_q       (fsm_q)
  );

  always @(posedge clk_i) begin
    if (f_past_valid && $past(rst_n_i && nmi_valid && !nmi_ready)) begin
      assume (nmi_valid);
      assume (nmi_addr == $past(nmi_addr));
      assume (nmi_wdata == $past(nmi_wdata));
      assume (nmi_wstrb == $past(nmi_wstrb));
    end

    if (rst_n_i) begin
      assert ($onehot0(psel_comb));
      assert ($onehot0(psel_q));
      if (nmi_ready) begin
        assert (xfer_ready);
        assert (fsm_q == FSM_ENAB);
      end
      if (f_past_valid && $past(rst_n_i && fsm_q == FSM_SETP)) begin
        assert (psel_q == $past(psel_q));
      end
      if (f_past_valid && $past(rst_n_i && fsm_q == FSM_ENAB && !xfer_ready)) begin
        assert (fsm_q == FSM_ENAB);
        assert (psel_q == $past(psel_q));
      end
      cover (fsm_q == FSM_ENAB && nmi_ready);
    end
  end

endmodule
