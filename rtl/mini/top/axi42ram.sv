// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// See LICENSE for the complete license text.

`include "axi4_define.svh"

module axi42ram (
    input logic         clk_i,
    input logic         rst_n_i,
          axi4_if.slave axi4,
          ram_if.master ram
);
  localparam int RSP_WIDTH = 37;

  logic s_active_d, s_active_q;
  logic s_write_d, s_write_q;
  logic s_id_d, s_id_q;
  logic [31:0] s_addr_d, s_addr_q;
  logic [7:0] s_len_d, s_len_q;
  logic [2:0] s_size_d, s_size_q;
  logic [7:0] s_issue_beat_d, s_issue_beat_q;
  logic s_issue_valid_d, s_issue_valid_q;
  logic [7:0] s_write_beat_d, s_write_beat_q;
  logic s_bvalid_d, s_bvalid_q;
  logic [1:0] s_bresp_d, s_bresp_q;
  logic s_read_pending_d, s_read_pending_q;
  logic [7:0] s_read_beat_d, s_read_beat_q;
  logic s_read_last_d, s_read_last_q;
  logic [14:0] s_read_addr;
  logic [31:0] s_read_issue_addr, s_read_hold_addr, s_write_addr;
  logic s_read_issue, s_write_hdshk;
  logic s_rsp_input_valid, s_rsp_input_ready;
  logic [RSP_WIDTH-1:0] s_rsp_input_data, s_rsp_output_data;

  assign axi4.awready = !s_active_q && !axi4.arvalid;
  assign axi4.arready = !s_active_q;
  assign axi4.wready = s_active_q && s_write_q && !s_bvalid_q;
  assign axi4.bid = s_id_q;
  assign axi4.bresp = s_bresp_q;
  assign axi4.buser = '0;
  assign axi4.bvalid = s_bvalid_q;
  assign axi4.rid = s_rsp_output_data[36];
  assign axi4.rdata = s_rsp_output_data[35:4];
  assign axi4.rresp = s_rsp_output_data[3:2];
  assign axi4.rlast = s_rsp_output_data[1];
  assign axi4.ruser = s_rsp_output_data[0];
  assign s_write_hdshk = axi4.wvalid && axi4.wready;
  assign s_read_issue = s_active_q && !s_write_q && s_issue_valid_q &&
                        (!s_read_pending_q || s_rsp_input_ready);

  assign s_read_issue_addr = s_addr_q + (32'(s_issue_beat_q) << s_size_q);
  assign s_read_hold_addr = s_addr_q + (32'(s_read_beat_q) << s_size_q);
  assign s_write_addr = s_addr_q + (32'(s_write_beat_q) << s_size_q);

  always_comb begin
    s_read_addr = s_read_issue_addr[16:2];
    if (s_read_pending_q && !s_rsp_input_ready) begin
      s_read_addr = s_read_hold_addr[16:2];
    end
  end

  assign ram.addr          = s_write_q ? s_write_addr[16:2] : s_read_addr;
  assign ram.wdata         = axi4.wdata;
  assign ram.wstrb         = s_write_hdshk ? axi4.wstrb : '0;

  assign s_rsp_input_valid = s_read_pending_q;
  assign s_rsp_input_data  = {s_id_q, ram.rdata, `AXI4_RESP_OKAY, s_read_last_q, 1'b0};

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
      .valid_o(axi4.rvalid),
      .ready_i(axi4.rready),
      .data_o (s_rsp_output_data)
  );

  always_comb begin
    s_active_d       = s_active_q;
    s_write_d        = s_write_q;
    s_id_d           = s_id_q;
    s_addr_d         = s_addr_q;
    s_len_d          = s_len_q;
    s_size_d         = s_size_q;
    s_issue_beat_d   = s_issue_beat_q;
    s_issue_valid_d  = s_issue_valid_q;
    s_write_beat_d   = s_write_beat_q;
    s_bvalid_d       = s_bvalid_q;
    s_bresp_d        = s_bresp_q;
    s_read_pending_d = s_read_pending_q;
    s_read_beat_d    = s_read_beat_q;
    s_read_last_d    = s_read_last_q;

    if (axi4.arvalid && axi4.arready) begin
      s_active_d       = 1'b1;
      s_write_d        = 1'b0;
      s_id_d           = axi4.arid;
      s_addr_d         = axi4.araddr;
      s_len_d          = axi4.arlen;
      s_size_d         = axi4.arsize;
      s_issue_beat_d   = '0;
      s_issue_valid_d  = 1'b1;
      s_read_pending_d = 1'b0;
    end else if (axi4.awvalid && axi4.awready) begin
      s_active_d     = 1'b1;
      s_write_d      = 1'b1;
      s_id_d         = axi4.awid;
      s_addr_d       = axi4.awaddr;
      s_len_d        = axi4.awlen;
      s_size_d       = axi4.awsize;
      s_write_beat_d = '0;
      s_bvalid_d     = 1'b0;
      s_bresp_d      = `AXI4_RESP_OKAY;
    end

    if (s_read_pending_q && s_rsp_input_ready) s_read_pending_d = 1'b0;
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
      if ((s_write_beat_q == s_len_q) || axi4.wlast) begin
        s_bvalid_d = 1'b1;
        s_bresp_d = (axi4.wlast == (s_write_beat_q == s_len_q)) ?
                    `AXI4_RESP_OKAY : `AXI4_RESP_SLAVE_ERROR;
      end else begin
        s_write_beat_d = s_write_beat_q + 1'b1;
      end
    end
    if (axi4.bvalid && axi4.bready) begin
      s_active_d = 1'b0;
      s_bvalid_d = 1'b0;
    end
    if (axi4.rvalid && axi4.rready && axi4.rlast) begin
      s_active_d       = 1'b0;
      s_issue_valid_d  = 1'b0;
      s_read_pending_d = 1'b0;
    end
  end

  dffr #(
      .DATA_WIDTH(1)
  ) u_active_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_active_d),
      .dat_o  (s_active_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_write_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_d),
      .dat_o  (s_write_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_id_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_id_d),
      .dat_o  (s_id_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_addr_d),
      .dat_o  (s_addr_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_len_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_len_d),
      .dat_o  (s_len_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_size_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_size_d),
      .dat_o  (s_size_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_issue_beat_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_issue_beat_d),
      .dat_o  (s_issue_beat_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_issue_valid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_issue_valid_d),
      .dat_o  (s_issue_valid_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_write_beat_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_beat_d),
      .dat_o  (s_write_beat_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_bvalid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_bvalid_d),
      .dat_o  (s_bvalid_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_bresp_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_bresp_d),
      .dat_o  (s_bresp_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_read_pending_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_pending_d),
      .dat_o  (s_read_pending_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_read_beat_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_beat_d),
      .dat_o  (s_read_beat_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_read_last_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_last_d),
      .dat_o  (s_read_last_q)
  );
endmodule
