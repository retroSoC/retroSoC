// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

// Converts Debug Module reset requests into a management-hart-only reset.
// The request is retained until the AHB-Lite bridge has completed its current
// RIBP transfer, so a debugger cannot discard an accepted management access.
module mgmt_debug_reset (
    input  logic clk_i,
    input  logic rst_n_i,
    input  logic reset_req_i,
    input  logic bridge_idle_i,
    output logic core_rst_n_o,
    output logic reset_done_o
);

  logic s_pending_d, s_pending_q;
  logic s_reset_active_d, s_reset_active_q;

  always_comb begin
    s_pending_d      = s_pending_q;
    s_reset_active_d = s_reset_active_q;

    if (reset_req_i) begin
      s_pending_d = 1'b1;
    end

    if (s_reset_active_q && !reset_req_i) begin
      s_pending_d      = 1'b0;
      s_reset_active_d = 1'b0;
    end else if (!s_reset_active_q && s_pending_q && bridge_idle_i) begin
      s_reset_active_d = 1'b1;
    end
  end

  dffr #(
      .DATA_WIDTH(1)
  ) u_pending_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_pending_d),
      .dat_o  (s_pending_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_reset_active_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_reset_active_d),
      .dat_o  (s_reset_active_q)
  );
  rst_sync u_core_rst_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i && !s_reset_active_q),
      .rst_n_o(core_rst_n_o)
  );

  assign reset_done_o = core_rst_n_o && !s_pending_q && !s_reset_active_q;

endmodule
