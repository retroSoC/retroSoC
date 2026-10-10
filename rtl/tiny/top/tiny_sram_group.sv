// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0

// One independently arbitrated 32 KiB group. Arbitration advances on the
// physical macro edge, never on an AXI address or burst reservation. Captured
// responses isolate all three clients from subsequent macro output changes.
module tiny_sram_group (
    input logic                   clk_i,
    input logic                   rst_n_i,
          tiny_sram_port_if.slave ports  [3]
);
  logic [2:0] s_req, s_grant;
  logic [1:0] s_selected;
  logic       s_issue;
  logic [1:0] s_rsp_valid_d;
  logic [2:0] s_rsp_valid_q;
  logic [31:0] s_rsp_data_d[2], s_rsp_data_q[3];
  logic s_read_pending_d, s_read_pending_q;
  logic [1:0] s_read_owner_d, s_read_owner_q;
  logic [2:0] s_read_bank_d, s_read_bank_q;
  logic [2:0] s_write;
  logic [31:0] s_addr[3], s_wdata[3];
  logic [ 3:0] s_wstrb       [3];
  logic [31:0] s_bank_data   [8];
  logic [ 7:0] s_bank_select;

  for (genvar client = 0; client < 3; client++) begin : gen_client
    assign s_addr[client]          = ports[client].addr;
    assign s_write[client]         = ports[client].write;
    assign s_wdata[client]         = ports[client].wdata;
    assign s_wstrb[client]         = ports[client].wstrb;
    assign ports[client].req_ready = s_grant[client];
    assign ports[client].rsp_valid = s_rsp_valid_q[client];
    assign ports[client].rdata     = s_rsp_data_q[client];

    if (client < 2) begin : gen_local_response
      assign s_req[client] = ports[client].req_valid && !s_rsp_valid_q[client] &&
          !(s_read_pending_q && (s_read_owner_q == 2'(client)));
      always_comb begin
        s_rsp_valid_d[client] = s_rsp_valid_q[client] && !ports[client].rsp_ready;
        s_rsp_data_d[client]  = s_rsp_data_q[client];
        if (s_read_pending_q && (s_read_owner_q == 2'(client))) begin
          s_rsp_valid_d[client] = 1'b1;
          s_rsp_data_d[client]  = s_bank_data[s_read_bank_q];
        end
        if (s_grant[client] && s_write[client]) begin
          s_rsp_valid_d[client] = 1'b1;
          s_rsp_data_d[client]  = '0;
        end
      end
      dffr #(
          .DATA_WIDTH(1)
      ) u_response_valid (
          .clk_i  (clk_i),
          .rst_n_i(rst_n_i),
          .dat_i  (s_rsp_valid_d[client]),
          .dat_o  (s_rsp_valid_q[client])
      );
      dffr #(
          .DATA_WIDTH(32)
      ) u_response_data (
          .clk_i  (clk_i),
          .rst_n_i(rst_n_i),
          .dat_i  (s_rsp_data_d[client]),
          .dat_o  (s_rsp_data_q[client])
      );
    end else begin : gen_external_response
      logic s_empty, s_full, s_pop, s_push, s_pending;
      logic [ 1:0] s_count;
      logic [ 2:0] s_reserved;
      logic [31:0] s_data;
      assign s_pending = s_read_pending_q && (s_read_owner_q == 2'(client));
      assign s_reserved = {1'b0, s_count} + {2'b0, s_pending};
      assign s_pop = ports[client].rsp_ready && !s_empty;
      // Include the macro read already in flight. A returning word must fit
      // even if the consumer removes READY immediately after this issue.
      // A same-client read return and write commit cannot share one FIFO push.
      assign s_req[client] = ports[client].req_valid &&
          ((s_reserved < 3'd2) || ((s_reserved == 3'd2) && s_pop)) &&
          !(s_pending && s_write[client]);
      assign s_push = s_pending || (s_grant[client] && s_write[client]);
      assign s_data = s_pending ? s_bank_data[s_read_bank_q] : 32'd0;
      assign s_rsp_valid_q[client] = !s_empty;
      fifo #(
          .DATA_WIDTH  (32),
          .BUFFER_DEPTH(2)
      ) u_response_fifo (
          .clk_i  (clk_i),
          .rst_n_i(rst_n_i),
          .flush_i(1'b0),
          .push_i (s_push),
          .full_o (s_full),
          .dat_i  (s_data),
          .pop_i  (s_pop),
          .empty_o(s_empty),
          .dat_o  (s_rsp_data_q[client]),
          .cnt_o  (s_count)
      );
`ifdef FORMAL
      always_ff @(posedge clk_i) begin
        if (rst_n_i) begin
          assert (s_reserved <= 3'd2);
          assert (!s_push || !s_full || s_pop);
          assert (!(s_pending && s_grant[client] && s_write[client]));
        end
      end
`endif
`ifdef HAVE_SVA
      assert property (@(posedge clk_i) disable iff (!rst_n_i) s_reserved <= 3'd2);
      assert property (@(posedge clk_i) disable iff (!rst_n_i) !s_push || !s_full || s_pop);
`endif
    end
  end

  round_robin_arbiter #(
      .CLIENTS(3)
  ) u_arbiter (
      .clk_i     (clk_i),
      .rst_n_i   (rst_n_i),
      .advance_i (s_issue),
      .request_i (s_req),
      .grant_o   (s_grant),
      .selected_o(s_selected),
      .valid_o   (s_issue)
  );
  assign s_read_pending_d = s_issue && !s_write[s_selected];
  assign s_read_owner_d   = s_selected;
  assign s_read_bank_d    = s_addr[s_selected][14:12];
  dffr #(
      .DATA_WIDTH(1)
  ) u_read_pending (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_pending_d),
      .dat_o  (s_read_pending_q)
  );
  dffer #(
      .DATA_WIDTH(2)
  ) u_read_owner (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_read_pending_d),
      .dat_i  (s_read_owner_d),
      .dat_o  (s_read_owner_q)
  );
  dffer #(
      .DATA_WIDTH(3)
  ) u_read_bank (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_read_pending_d),
      .dat_i  (s_read_bank_d),
      .dat_o  (s_read_bank_q)
  );

  for (genvar bank = 0; bank < 8; bank++) begin : gen_bank
    assign s_bank_select[bank] = s_issue && (s_addr[s_selected][14:12] == 3'(bank));
    tc_sram_1024x32 u_ram (
        .clk_i (clk_i),
        .cs_i  (s_bank_select[bank]),
        .addr_i(s_addr[s_selected][11:2]),
        .data_i(s_wdata[s_selected]),
        .mask_i(s_wstrb[s_selected]),
        .wren_i(s_write[s_selected]),
        .data_o(s_bank_data[bank])
    );
  end

`ifdef FORMAL
  // Service-count proof: only continuously eligible requests accumulate
  // bypasses. No wall-clock liveness is assumed for a withheld response.
  for (genvar client = 0; client < 3; client++) begin : gen_formal
    logic [1:0] s_bypasses_q;
    logic       s_past_valid_q = 1'b0;
    always_ff @(posedge clk_i) begin
      s_past_valid_q <= 1'b1;
      if (!rst_n_i || !s_req[client] || s_grant[client]) s_bypasses_q <= '0;
      else if (s_issue) s_bypasses_q <= s_bypasses_q + 2'd1;
      if (rst_n_i) begin
        assert ($onehot0(s_grant));
        assert (s_bypasses_q <= 2'd2);
        assert (!(s_req[client] && (s_bypasses_q == 2'd2) && s_issue && !s_grant[client]));
        if (client < 2)
          assert (!(s_rsp_valid_q[client] && s_read_pending_q && (s_read_owner_q == 2'(client))));
      end
      if (s_past_valid_q && rst_n_i && $past(
              rst_n_i && ports[client].rsp_valid && !ports[client].rsp_ready
          )) begin
        assert (ports[client].rsp_valid);
        assert (ports[client].rdata == $past(ports[client].rdata));
      end
    end
  end
`endif
`ifdef HAVE_SVA
  assert property (@(posedge clk_i) disable iff (!rst_n_i) $onehot0(s_grant));
  assert property (@(posedge clk_i) disable iff (!rst_n_i) $onehot0(s_bank_select));
  for (genvar client = 0; client < 3; client++) begin : gen_assert
    assert property (@(posedge clk_i) disable iff (!rst_n_i)
        ports[client].rsp_valid && !ports[client].rsp_ready |=>
        ports[client].rsp_valid && $stable(
        ports[client].rdata
    ));
  end
`endif
endmodule
