// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "axi4_define.svh"

// Converts one outstanding 64-bit AXI4 transaction into a 32-bit transaction.
module axi4_downsizer_64to32 #(
    parameter int unsigned WideIdWidth = 3
) (
    input logic          clk_i,
    input logic          rst_n_i,
    input logic          clear_i,
          axi4_if.slave  wide,
          axi4_if.master narrow
);
  typedef enum logic {
    Idle,
    Active
  } channel_state_e;

  channel_state_e s_read_state_d, s_read_state_q;
  channel_state_e s_write_state_d, s_write_state_q;
  logic s_read_state_bits_q;
  logic s_write_state_bits_q;
  logic [WideIdWidth-1:0] s_read_id_d, s_read_id_q;
  logic [WideIdWidth-1:0] s_write_id_d, s_write_id_q;
  logic [2:0] s_read_size_d, s_read_size_q;
  logic [2:0] s_write_size_d, s_write_size_q;
  logic [7:0] s_read_len_d, s_read_len_q;
  logic [7:0] s_write_len_d, s_write_len_q;
  logic [1:0] s_read_burst_d, s_read_burst_q;
  logic [1:0] s_write_burst_d, s_write_burst_q;
  logic [31:0] s_read_addr_d, s_read_addr_q;
  logic [31:0] s_write_addr_d, s_write_addr_q;
  logic [31:0] s_read_next_addr;
  logic [31:0] s_write_next_addr;
  logic s_read_upper_d, s_read_upper_q;
  logic s_write_upper_d, s_write_upper_q;
  logic [31:0] s_read_lower_d, s_read_lower_q;
  logic [1:0] s_read_resp_d, s_read_resp_q;
  logic s_read_accept;
  logic s_write_addr_accept;
  logic s_narrow_read_accept;
  logic s_narrow_write_accept;
  logic s_wide_read_accept;
  logic s_wide_write_accept;
  logic s_b_pending_d, s_b_pending_q;
  logic [1:0] s_b_resp_d, s_b_resp_q;
  logic [8:0] s_read_beats;
  logic [8:0] s_write_beats;

  assign s_read_state_q = channel_state_e'(s_read_state_bits_q);
  assign s_write_state_q = channel_state_e'(s_write_state_bits_q);
  assign s_read_beats = {1'b0, wide.arlen} + 9'd1;
  assign s_write_beats = {1'b0, wide.awlen} + 9'd1;

  assign wide.arready = (s_read_state_q == Idle) && narrow.arready;
  assign narrow.arvalid = (s_read_state_q == Idle) && wide.arvalid;
  assign narrow.arid = '0;
  assign narrow.araddr = wide.araddr;
  assign narrow.arlen = (wide.arsize == 3'd3) ? 8'((s_read_beats << 1) - 9'd1) : wide.arlen;
  assign narrow.arsize = (wide.arsize == 3'd3) ? 3'd2 : wide.arsize;
  assign narrow.arburst = wide.arburst;
  assign narrow.arlock = wide.arlock;
  assign narrow.arcache = wide.arcache;
  assign narrow.arprot = wide.arprot;
  assign narrow.arqos = wide.arqos;
  assign narrow.arregion = wide.arregion;
  assign narrow.aruser = '0;
  assign s_read_accept = wide.arvalid && wide.arready;

  assign wide.rid = s_read_id_q;
  assign wide.rdata = (s_read_size_q == 3'd3) ? {narrow.rdata, s_read_lower_q} :
                      s_read_addr_q[2] ? {narrow.rdata, 32'd0} : {32'd0, narrow.rdata};
  assign wide.rresp = (s_read_size_q == 3'd3) && (s_read_resp_q != `AXI4_RESP_OKAY) ?
                      s_read_resp_q : narrow.rresp;
  assign wide.rlast = narrow.rlast;
  assign wide.ruser = '0;
  assign wide.rvalid = (s_read_state_q == Active) && narrow.rvalid &&
                       ((s_read_size_q != 3'd3) || s_read_upper_q);
  assign narrow.rready = (s_read_state_q == Active) &&
                         (((s_read_size_q == 3'd3) && !s_read_upper_q) || wide.rready);
  assign s_narrow_read_accept = narrow.rvalid && narrow.rready;
  assign s_wide_read_accept = wide.rvalid && wide.rready;

  always_comb begin
    s_read_state_d = s_read_state_q;
    s_read_id_d    = s_read_id_q;
    s_read_size_d  = s_read_size_q;
    s_read_len_d   = s_read_len_q;
    s_read_burst_d = s_read_burst_q;
    s_read_addr_d  = s_read_addr_q;
    s_read_upper_d = s_read_upper_q;
    s_read_lower_d = s_read_lower_q;
    s_read_resp_d  = s_read_resp_q;

    if (s_read_accept) begin
      s_read_state_d = Active;
      s_read_id_d    = wide.arid;
      s_read_size_d  = wide.arsize;
      s_read_len_d   = wide.arlen;
      s_read_burst_d = wide.arburst;
      s_read_addr_d  = wide.araddr;
      s_read_upper_d = 1'b0;
      s_read_resp_d  = `AXI4_RESP_OKAY;
    end

    if (s_narrow_read_accept && (s_read_size_q == 3'd3)) begin
      if (!s_read_upper_q) begin
        s_read_lower_d = narrow.rdata;
        s_read_resp_d  = narrow.rresp;
        s_read_upper_d = 1'b1;
      end else begin
        s_read_upper_d = 1'b0;
        s_read_resp_d  = `AXI4_RESP_OKAY;
      end
    end

    if (s_wide_read_accept) begin
      s_read_addr_d = s_read_next_addr;
      if (narrow.rlast) s_read_state_d = Idle;
    end

    if (clear_i) begin
      s_read_state_d = Idle;
      s_read_upper_d = 1'b0;
      s_read_resp_d  = `AXI4_RESP_OKAY;
    end
  end

  assign wide.awready = (s_write_state_q == Idle) && narrow.awready;
  assign narrow.awvalid = (s_write_state_q == Idle) && wide.awvalid;
  assign narrow.awid = '0;
  assign narrow.awaddr = wide.awaddr;
  assign narrow.awlen = (wide.awsize == 3'd3) ? 8'((s_write_beats << 1) - 9'd1) : wide.awlen;
  assign narrow.awsize = (wide.awsize == 3'd3) ? 3'd2 : wide.awsize;
  assign narrow.awburst = wide.awburst;
  assign narrow.awlock = wide.awlock;
  assign narrow.awcache = wide.awcache;
  assign narrow.awprot = wide.awprot;
  assign narrow.awqos = wide.awqos;
  assign narrow.awregion = wide.awregion;
  assign narrow.awuser = '0;
  assign s_write_addr_accept = wide.awvalid && wide.awready;

  assign narrow.wdata = (s_write_size_q == 3'd3) ?
                        (s_write_upper_q ? wide.wdata[63:32] : wide.wdata[31:0]) :
                        (s_write_addr_q[2] ? wide.wdata[63:32] : wide.wdata[31:0]);
  assign narrow.wstrb = (s_write_size_q == 3'd3) ?
                        (s_write_upper_q ? wide.wstrb[7:4] : wide.wstrb[3:0]) :
                        (s_write_addr_q[2] ? wide.wstrb[7:4] : wide.wstrb[3:0]);
  assign narrow.wlast = wide.wlast && ((s_write_size_q != 3'd3) || s_write_upper_q);
  assign narrow.wuser = '0;
  assign narrow.wvalid = (s_write_state_q == Active) && wide.wvalid;
  assign wide.wready = (s_write_state_q == Active) && narrow.wready &&
                       ((s_write_size_q != 3'd3) || s_write_upper_q);
  assign s_narrow_write_accept = narrow.wvalid && narrow.wready;
  assign s_wide_write_accept = wide.wvalid && wide.wready;

  assign wide.bid = s_write_id_q;
  assign wide.bresp = s_b_resp_q;
  assign wide.buser = '0;
  assign wide.bvalid = s_b_pending_q;
  assign narrow.bready = (s_write_state_q == Active) && !s_b_pending_q;

  always_comb begin
    s_write_state_d = s_write_state_q;
    s_write_id_d    = s_write_id_q;
    s_write_size_d  = s_write_size_q;
    s_write_len_d   = s_write_len_q;
    s_write_burst_d = s_write_burst_q;
    s_write_addr_d  = s_write_addr_q;
    s_write_upper_d = s_write_upper_q;
    s_b_pending_d   = s_b_pending_q;
    s_b_resp_d      = s_b_resp_q;

    if (s_write_addr_accept) begin
      s_write_state_d = Active;
      s_write_id_d    = wide.awid;
      s_write_size_d  = wide.awsize;
      s_write_len_d   = wide.awlen;
      s_write_burst_d = wide.awburst;
      s_write_addr_d  = wide.awaddr;
      s_write_upper_d = 1'b0;
      s_b_pending_d   = 1'b0;
    end

    if (s_narrow_write_accept && (s_write_size_q == 3'd3)) begin
      s_write_upper_d = !s_write_upper_q;
    end

    if (s_wide_write_accept) s_write_addr_d = s_write_next_addr;

    if (narrow.bvalid && narrow.bready) begin
      s_b_pending_d = 1'b1;
      s_b_resp_d    = narrow.bresp;
    end
    if (wide.bvalid && wide.bready) begin
      s_b_pending_d   = 1'b0;
      s_write_state_d = Idle;
    end

    if (clear_i) begin
      s_write_state_d = Idle;
      s_write_upper_d = 1'b0;
      s_b_pending_d   = 1'b0;
      s_b_resp_d      = `AXI4_RESP_OKAY;
    end
  end

  axi4_addr_gen #(
      .ADDR_WIDTH(32)
  ) u_read_addr_gen (
      .alen_i  (s_read_len_q),
      .asize_i (s_read_size_q),
      .aburst_i(s_read_burst_q),
      .addr_i  (s_read_addr_q),
      .addr_o  (s_read_next_addr)
  );
  axi4_addr_gen #(
      .ADDR_WIDTH(32)
  ) u_write_addr_gen (
      .alen_i  (s_write_len_q),
      .asize_i (s_write_size_q),
      .aburst_i(s_write_burst_q),
      .addr_i  (s_write_addr_q),
      .addr_o  (s_write_next_addr)
  );

  dffr #(
      .DATA_WIDTH(1)
  ) u_read_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_state_d),
      .dat_o  (s_read_state_bits_q)
  );

  dffr #(
      .DATA_WIDTH(1)
  ) u_write_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_state_d),
      .dat_o  (s_write_state_bits_q)
  );

  dffr #(
      .DATA_WIDTH(WideIdWidth)
  ) u_read_id_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_id_d),
      .dat_o  (s_read_id_q)
  );
  dffr #(
      .DATA_WIDTH(WideIdWidth)
  ) u_write_id_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_id_d),
      .dat_o  (s_write_id_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_read_size_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_size_d),
      .dat_o  (s_read_size_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_write_size_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_size_d),
      .dat_o  (s_write_size_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_read_len_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_len_d),
      .dat_o  (s_read_len_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_write_len_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_len_d),
      .dat_o  (s_write_len_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_read_burst_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_burst_d),
      .dat_o  (s_read_burst_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_write_burst_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_burst_d),
      .dat_o  (s_write_burst_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_read_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_addr_d),
      .dat_o  (s_read_addr_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_write_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_addr_d),
      .dat_o  (s_write_addr_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_read_upper_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_upper_d),
      .dat_o  (s_read_upper_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_write_upper_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_upper_d),
      .dat_o  (s_write_upper_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_read_lower_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_lower_d),
      .dat_o  (s_read_lower_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_read_resp_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_resp_d),
      .dat_o  (s_read_resp_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_b_pending_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_b_pending_d),
      .dat_o  (s_b_pending_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_b_resp_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_b_resp_d),
      .dat_o  (s_b_resp_q)
  );

`ifndef SYNTHESIS
  property p_wide_read_geometry;
    @(posedge clk_i) disable iff (!rst_n_i) wide.arvalid |->
        ((wide.arsize <= 3'd3) &&
         ((wide.arsize != 3'd3) || ((wide.arlen <= 8'd7) && (wide.araddr[2:0] == 3'd0))));
  endproperty
  assert property (p_wide_read_geometry);

  property p_wide_write_geometry;
    @(posedge clk_i) disable iff (!rst_n_i) wide.awvalid |->
        ((wide.awsize <= 3'd3) &&
         ((wide.awsize != 3'd3) || ((wide.awlen <= 8'd7) && (wide.awaddr[2:0] == 3'd0))));
  endproperty
  assert property (p_wide_write_geometry);
`endif
endmodule
