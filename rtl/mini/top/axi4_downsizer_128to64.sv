// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "axi4_define.svh"

// Serializing 128-bit to 64-bit AXI4 downsizer for the OpenC906 BIU master.
// Accepts one outstanding wide transaction per direction and emits legal
// narrow bursts. The C906 only issues size-4 INCR (len 1/4) and WRAP4 reads
// and size<=4 INCR writes, so no burst splitting is required: a size-4 wide
// burst maps to a doubled-length narrow burst (WRAP4x16B becomes WRAP8x8B).
module axi4_downsizer_128to64 #(
    parameter int unsigned WideIdWidth = 8
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
  logic [31:0] s_read_addr_d, s_read_addr_q;
  logic [31:0] s_write_addr_d, s_write_addr_q;
  logic s_read_upper_d, s_read_upper_q;
  logic s_write_upper_d, s_write_upper_q;
  logic [63:0] s_read_lower_d, s_read_lower_q;
  logic [1:0] s_read_resp_d, s_read_resp_q;
  logic s_read_accept;
  logic s_write_addr_accept;
  logic s_narrow_read_accept;
  logic s_narrow_write_accept;
  logic s_wide_read_accept;
  logic s_wide_write_accept;
  logic s_b_pending_d, s_b_pending_q;
  logic [1:0] s_b_resp_d, s_b_resp_q;

  assign s_read_state_q = channel_state_e'(s_read_state_bits_q);
  assign s_write_state_q = channel_state_e'(s_write_state_bits_q);

  // Address channels are forwarded combinationally while idle; a size-4 wide
  // burst doubles its beat count on the narrow side, all other transfers
  // pass through unchanged.
  assign wide.arready = (s_read_state_q == Idle) && narrow.arready;
  assign narrow.arvalid = (s_read_state_q == Idle) && wide.arvalid;
  assign narrow.arid = '0;
  assign narrow.araddr = wide.araddr;
  assign narrow.arlen = (wide.arsize == 3'd4) ? 8'((wide.arlen << 1) | 8'd1) : wide.arlen;
  assign narrow.arsize = (wide.arsize == 3'd4) ? 3'd3 : wide.arsize;
  assign narrow.arburst = wide.arburst;
  assign narrow.arlock = wide.arlock;
  assign narrow.arcache = wide.arcache;
  assign narrow.arprot = wide.arprot;
  assign narrow.arqos = wide.arqos;
  assign narrow.arregion = wide.arregion;
  assign narrow.aruser = '0;
  assign s_read_accept = wide.arvalid && wide.arready;

  assign wide.rid = s_read_id_q;
  assign wide.rdata = (s_read_size_q == 3'd4) ? {narrow.rdata, s_read_lower_q} :
                      s_read_addr_q[3] ? {narrow.rdata, 64'd0} : {64'd0, narrow.rdata};
  assign wide.rresp = (s_read_size_q == 3'd4) && (s_read_resp_q != `AXI4_RESP_OKAY) ?
                      s_read_resp_q : narrow.rresp;
  assign wide.rlast = narrow.rlast;
  assign wide.ruser = '0;
  assign wide.rvalid = (s_read_state_q == Active) && narrow.rvalid &&
                       ((s_read_size_q != 3'd4) || s_read_upper_q);
  assign narrow.rready = (s_read_state_q == Active) &&
                         (((s_read_size_q == 3'd4) && !s_read_upper_q) || wide.rready);
  assign s_narrow_read_accept = narrow.rvalid && narrow.rready;
  assign s_wide_read_accept = wide.rvalid && wide.rready;

  always_comb begin
    s_read_state_d = s_read_state_q;
    s_read_id_d    = s_read_id_q;
    s_read_size_d  = s_read_size_q;
    s_read_addr_d  = s_read_addr_q;
    s_read_upper_d = s_read_upper_q;
    s_read_lower_d = s_read_lower_q;
    s_read_resp_d  = s_read_resp_q;

    if (s_read_accept) begin
      s_read_state_d = Active;
      s_read_id_d    = wide.arid;
      s_read_size_d  = wide.arsize;
      s_read_addr_d  = wide.araddr;
      s_read_upper_d = 1'b0;
      s_read_resp_d  = `AXI4_RESP_OKAY;
    end

    if (s_narrow_read_accept && (s_read_size_q == 3'd4)) begin
      if (!s_read_upper_q) begin
        s_read_lower_d = narrow.rdata;
        s_read_resp_d  = narrow.rresp;
        s_read_upper_d = 1'b1;
      end else begin
        s_read_upper_d = 1'b0;
        s_read_resp_d  = `AXI4_RESP_OKAY;
      end
    end

    if (s_wide_read_accept && narrow.rlast) s_read_state_d = Idle;

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
  assign narrow.awlen = (wide.awsize == 3'd4) ? 8'((wide.awlen << 1) | 8'd1) : wide.awlen;
  assign narrow.awsize = (wide.awsize == 3'd4) ? 3'd3 : wide.awsize;
  assign narrow.awburst = wide.awburst;
  assign narrow.awlock = wide.awlock;
  assign narrow.awcache = wide.awcache;
  assign narrow.awprot = wide.awprot;
  assign narrow.awqos = wide.awqos;
  assign narrow.awregion = wide.awregion;
  assign narrow.awuser = '0;
  assign s_write_addr_accept = wide.awvalid && wide.awready;

  assign narrow.wdata = (s_write_size_q == 3'd4) ?
                        (s_write_upper_q ? wide.wdata[127:64] : wide.wdata[63:0]) :
                        (s_write_addr_q[3] ? wide.wdata[127:64] : wide.wdata[63:0]);
  assign narrow.wstrb = (s_write_size_q == 3'd4) ?
                        (s_write_upper_q ? wide.wstrb[15:8] : wide.wstrb[7:0]) :
                        (s_write_addr_q[3] ? wide.wstrb[15:8] : wide.wstrb[7:0]);
  assign narrow.wlast = (s_write_size_q != 3'd4) ? wide.wlast : s_write_upper_q && wide.wlast;
  assign narrow.wuser = '0;
  assign narrow.wvalid = (s_write_state_q == Active) && wide.wvalid;
  assign wide.wready = (s_write_state_q == Active) && narrow.wready &&
                       ((s_write_size_q != 3'd4) || s_write_upper_q);
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
    s_write_addr_d  = s_write_addr_q;
    s_write_upper_d = s_write_upper_q;
    s_b_pending_d   = s_b_pending_q;
    s_b_resp_d      = s_b_resp_q;

    if (s_write_addr_accept) begin
      s_write_state_d = Active;
      s_write_id_d    = wide.awid;
      s_write_size_d  = wide.awsize;
      s_write_addr_d  = wide.awaddr;
      s_write_upper_d = 1'b0;
      s_b_pending_d   = 1'b0;
    end

    if (s_narrow_write_accept && (s_write_size_q == 3'd4)) s_write_upper_d = !s_write_upper_q;

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
      .DATA_WIDTH(64)
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
        ((wide.arsize <= 3'd4) &&
         ((wide.arsize != 3'd4) ||
          ((wide.arlen <= 8'd15) && (wide.araddr[3:0] == 4'd0) &&
           ((wide.arburst != `AXI4_BURST_TYPE_WRAP) || (wide.arlen == 8'd3)))));
  endproperty
  assert property (p_wide_read_geometry);

  property p_wide_write_geometry;
    @(posedge clk_i) disable iff (!rst_n_i) wide.awvalid |->
        ((wide.awsize <= 3'd4) &&
         ((wide.awsize != 3'd4) ||
          ((wide.awlen <= 8'd15) && (wide.awaddr[3:0] == 4'd0) &&
           (wide.awburst == `AXI4_BURST_TYPE_INCR))));
  endproperty
  assert property (p_wide_write_geometry);
`endif
endmodule
