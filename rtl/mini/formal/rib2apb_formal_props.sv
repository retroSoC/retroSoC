// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of the Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module rib2apb_formal;

  localparam logic [2:0] FSM_ENAB = 3'd3;
  localparam logic [2:0] FSM_ERR = 3'd5;
  localparam logic [2:0] RIB_RESP_OK = 3'd0;
  localparam logic [2:0] RIB_RESP_SLVERR = 3'd3;

  (* anyseq *) (* gclk *)reg         clk_i;
  wire        rst_n_i;
  wire        f_past_valid;
  wire        rib_cmd_valid;
  wire [31:0] rib_cmd_addr;
  wire        rib_cmd_write;
  wire [ 1:0] rib_cmd_len;
  wire        rib_cmd_ready;
  wire        rib_w_valid;
  wire [31:0] rib_wdata;
  wire [ 3:0] rib_wstrb;
  wire        rib_wlast;
  wire        rib_w_ready;
  wire        rib_rsp_valid;
  wire [31:0] rib_rdata;
  wire        rib_resp_err;
  wire [ 2:0] rib_resp_code;
  wire [ 1:0] rib_rsp_beat;
  wire        rib_rsp_last;
  wire        rib_rsp_ready;
  wire [11:0] psel_comb;
  wire [11:0] psel_q;
  wire        xfer_ready;
  wire        xfer_error;
  wire        rsp_input_valid;
  wire        rsp_input_ready;
  wire [38:0] rsp_input_data;
  wire [ 2:0] fsm_q;

  rib2apb_formal_design u_design (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .f_past_valid   (f_past_valid),
      .rib_cmd_valid  (rib_cmd_valid),
      .rib_cmd_addr   (rib_cmd_addr),
      .rib_cmd_write  (rib_cmd_write),
      .rib_cmd_len    (rib_cmd_len),
      .rib_cmd_ready  (rib_cmd_ready),
      .rib_w_valid    (rib_w_valid),
      .rib_wdata      (rib_wdata),
      .rib_wstrb      (rib_wstrb),
      .rib_wlast      (rib_wlast),
      .rib_w_ready    (rib_w_ready),
      .rib_rsp_valid  (rib_rsp_valid),
      .rib_rdata      (rib_rdata),
      .rib_resp_err   (rib_resp_err),
      .rib_resp_code  (rib_resp_code),
      .rib_rsp_beat   (rib_rsp_beat),
      .rib_rsp_last   (rib_rsp_last),
      .rib_rsp_ready  (rib_rsp_ready),
      .psel_comb      (psel_comb),
      .psel_q         (psel_q),
      .xfer_ready     (xfer_ready),
      .xfer_error     (xfer_error),
      .rsp_input_valid(rsp_input_valid),
      .rsp_input_ready(rsp_input_ready),
      .rsp_input_data (rsp_input_data),
      .fsm_q          (fsm_q)
  );

  always @(posedge clk_i) begin
    if (f_past_valid && $past(rst_n_i && rib_cmd_valid && !rib_cmd_ready)) begin
      assume (rib_cmd_valid);
      assume (rib_cmd_addr == $past(rib_cmd_addr));
      assume (rib_cmd_write == $past(rib_cmd_write));
      assume (rib_cmd_len == $past(rib_cmd_len));
    end
    if (f_past_valid && $past(rst_n_i && rib_w_valid && !rib_w_ready)) begin
      assume (rib_w_valid);
      assume (rib_wdata == $past(rib_wdata));
      assume (rib_wstrb == $past(rib_wstrb));
      assume (rib_wlast == $past(rib_wlast));
    end

    if (rst_n_i) begin
      assert ($onehot0(psel_comb));
      if (f_past_valid && $past(rst_n_i && fsm_q == FSM_ENAB && !xfer_ready)) begin
        assert (fsm_q == FSM_ENAB);
        assert (psel_q == $past(psel_q));
      end
      if (fsm_q == FSM_ENAB && xfer_ready) begin
        assert (rsp_input_valid);
        assert (rsp_input_data[38:36] == 3'b100);
        assert (rsp_input_data[32] == xfer_error);
        assert (rsp_input_data[35:33] == (xfer_error ? RIB_RESP_SLVERR : RIB_RESP_OK));
      end
      if (fsm_q == FSM_ERR) begin
        assert (rsp_input_valid);
        assert (rsp_input_data[38:36] == 3'b100);
        assert (rsp_input_data[32]);
      end
      cover (fsm_q == FSM_ENAB && xfer_ready && rsp_input_ready);
    end
  end

endmodule
