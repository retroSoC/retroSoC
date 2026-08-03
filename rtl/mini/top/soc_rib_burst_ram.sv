// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "soc_rib_defs.svh"

module soc_rib_burst_ram (
    input logic                  clk_i,
    input logic                  rst_n_i,
          soc_rib_burst_if.slave burst,
          ram_if.master          ram
);

  localparam int RSP_WIDTH = 39;

  logic s_active_d, s_active_q;
  logic        s_write_q;
  logic [31:0] s_addr_q;
  logic [ 1:0] s_len_q;
  logic [1:0] s_issue_beat_d, s_issue_beat_q;
  logic s_issue_valid_d, s_issue_valid_q;
  logic [1:0] s_write_beat_d, s_write_beat_q;
  logic s_write_done_d, s_write_done_q;
  logic s_read_pending_d, s_read_pending_q;
  logic [1:0] s_read_beat_d, s_read_beat_q;
  logic s_read_last_d, s_read_last_q;
  logic                 s_read_issue;
  logic [          1:0] s_read_addr_beat;
  logic                 s_write_hdshk;
  logic                 s_write_rsp_valid;
  logic                 s_write_rsp_error;
  logic                 s_rsp_input_valid;
  logic                 s_rsp_input_ready;
  logic [RSP_WIDTH-1:0] s_rsp_input_data;
  logic [RSP_WIDTH-1:0] s_rsp_output_data;

  assign burst.cmd_ready = ~s_active_q;
  assign burst.w_ready = s_active_q && s_write_q && ~s_write_done_q &&
                         ((s_write_beat_q != s_len_q) || s_rsp_input_ready);
  assign s_write_hdshk = burst.w_valid && burst.w_ready;
  assign s_write_rsp_valid = s_write_hdshk && ((s_write_beat_q == s_len_q) || burst.wlast);
  assign s_write_rsp_error = s_write_rsp_valid && (burst.wlast != (s_write_beat_q == s_len_q));

  assign s_read_issue = s_active_q && ~s_write_q && s_issue_valid_q &&
                        (~s_read_pending_q || s_rsp_input_ready);

  // ram_if has no read enable. Keep the address on a blocked pending beat so
  // a synchronous RAM cannot overwrite ram.rdata before it enters the spill.
  always_comb begin
    s_read_addr_beat = s_issue_beat_q;
    if (s_read_pending_q && ~s_rsp_input_ready) begin
      s_read_addr_beat = s_read_beat_q;
    end
  end
  assign ram.addr = s_write_q ? ((s_addr_q[16:2]) + s_write_beat_q) :
                                ((s_addr_q[16:2]) + s_read_addr_beat);
  assign ram.wdata = burst.wdata;
  assign ram.wstrb = s_write_hdshk ? burst.wstrb : '0;

  assign s_rsp_input_valid = s_write_q ? s_write_rsp_valid : s_read_pending_q;
  assign s_rsp_input_data = s_write_q ?
      {1'b1, s_write_beat_q,
       s_write_rsp_error ? `SOC_RIB_RESP_BURSTERR : `SOC_RIB_RESP_OK,
       s_write_rsp_error, 32'd0} :
      {s_read_last_q, s_read_beat_q, `SOC_RIB_RESP_OK, 1'b0, ram.rdata};

  spill_register #(
      .DATA_WIDTH(RSP_WIDTH),
      .BYPASS    (1'b0)
  ) u_rsp_spill_register (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(1'b0),
      .valid_i(s_rsp_input_valid),
      .ready_o(s_rsp_input_ready),
      .data_i (s_rsp_input_data),
      .valid_o(burst.rsp_valid),
      .ready_i(burst.rsp_ready),
      .data_o (s_rsp_output_data)
  );

  assign burst.rdata     = s_rsp_output_data[31:0];
  assign burst.resp_err  = s_rsp_output_data[32];
  assign burst.resp_code = s_rsp_output_data[35:33];
  assign burst.rsp_beat  = s_rsp_output_data[37:36];
  assign burst.rsp_last  = s_rsp_output_data[38];

  always_comb begin
    s_active_d       = s_active_q;
    s_issue_beat_d   = s_issue_beat_q;
    s_issue_valid_d  = s_issue_valid_q;
    s_write_beat_d   = s_write_beat_q;
    s_write_done_d   = s_write_done_q;
    s_read_pending_d = s_read_pending_q;
    s_read_beat_d    = s_read_beat_q;
    s_read_last_d    = s_read_last_q;

    if (burst.cmd_valid && burst.cmd_ready) begin
      s_active_d       = 1'b1;
      s_issue_beat_d   = '0;
      s_issue_valid_d  = ~burst.cmd_write;
      s_write_beat_d   = '0;
      s_write_done_d   = 1'b0;
      s_read_pending_d = 1'b0;
    end

    if (s_read_pending_q && s_rsp_input_ready) begin
      s_read_pending_d = 1'b0;
    end
    if (s_read_issue) begin
      s_read_pending_d = 1'b1;
      s_read_beat_d    = s_issue_beat_q;
      s_read_last_d    = s_issue_beat_q == s_len_q;
      if (s_issue_beat_q == s_len_q) begin
        s_issue_valid_d = 1'b0;
      end else begin
        s_issue_beat_d = s_issue_beat_q + 1'b1;
      end
    end

    if (s_write_hdshk) begin
      if (s_write_rsp_valid) begin
        s_write_done_d = 1'b1;
      end else begin
        s_write_beat_d = s_write_beat_q + 1'b1;
      end
    end

    if (burst.rsp_valid && burst.rsp_ready && burst.rsp_last) begin
      s_active_d       = 1'b0;
      s_issue_valid_d  = 1'b0;
      s_write_done_d   = 1'b0;
      s_read_pending_d = 1'b0;
    end
  end

  dffr #(1) u_active_dffr (
      clk_i,
      rst_n_i,
      s_active_d,
      s_active_q
  );
  dffer #(1) u_write_dffer (
      clk_i,
      rst_n_i,
      burst.cmd_valid && burst.cmd_ready,
      burst.cmd_write,
      s_write_q
  );
  dffer #(32) u_addr_dffer (
      clk_i,
      rst_n_i,
      burst.cmd_valid && burst.cmd_ready,
      burst.cmd_addr,
      s_addr_q
  );
  dffer #(2) u_len_dffer (
      clk_i,
      rst_n_i,
      burst.cmd_valid && burst.cmd_ready,
      burst.cmd_len,
      s_len_q
  );
  dffr #(2) u_issue_beat_dffr (
      clk_i,
      rst_n_i,
      s_issue_beat_d,
      s_issue_beat_q
  );
  dffr #(1) u_issue_valid_dffr (
      clk_i,
      rst_n_i,
      s_issue_valid_d,
      s_issue_valid_q
  );
  dffr #(2) u_write_beat_dffr (
      clk_i,
      rst_n_i,
      s_write_beat_d,
      s_write_beat_q
  );
  dffr #(1) u_write_done_dffr (
      clk_i,
      rst_n_i,
      s_write_done_d,
      s_write_done_q
  );
  dffr #(1) u_read_pending_dffr (
      clk_i,
      rst_n_i,
      s_read_pending_d,
      s_read_pending_q
  );
  dffr #(2) u_read_beat_dffr (
      clk_i,
      rst_n_i,
      s_read_beat_d,
      s_read_beat_q
  );
  dffr #(1) u_read_last_dffr (
      clk_i,
      rst_n_i,
      s_read_last_d,
      s_read_last_q
  );

endmodule
