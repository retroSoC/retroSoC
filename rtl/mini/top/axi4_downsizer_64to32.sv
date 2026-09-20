// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "axi4_define.svh"

// Converts one outstanding 64-bit AXI4 transaction into 32-bit transactions.
// A size-3 INCR burst longer than eight beats is split into sequential legal
// narrow bursts of at most eight wide beats (sixteen narrow beats) each.
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
  logic s_narrow_read_addr_accept;
  logic s_narrow_write_addr_accept;
  logic s_wide_read_accept;
  logic s_wide_write_accept;
  logic s_b_pending_d, s_b_pending_q;
  logic [1:0] s_b_resp_d, s_b_resp_q;
  logic [8:0] s_read_beats;
  logic [8:0] s_write_beats;
  logic       s_read_wide_split;
  logic       s_write_wide_split;
  logic       s_read_split;
  logic       s_write_split;
  logic s_read_fragment_d, s_read_fragment_q;
  logic s_read_fragment_ar_d, s_read_fragment_ar_q;
  logic s_write_fragment_d, s_write_fragment_q;
  logic s_write_fragment_aw_d, s_write_fragment_aw_q;
  logic [2:0] s_write_fragment_beat_d, s_write_fragment_beat_q;
  logic       s_read_fragment_ar_issue;
  logic       s_write_fragment_aw_issue;
  logic [7:0] s_read_fragment_len;
  logic [7:0] s_write_fragment_len;
  logic       s_write_fragment_wlast;
  logic s_read_lock_d, s_read_lock_q;
  logic s_write_lock_d, s_write_lock_q;
  logic [3:0] s_read_cache_d, s_read_cache_q;
  logic [3:0] s_write_cache_d, s_write_cache_q;
  logic [2:0] s_read_prot_d, s_read_prot_q;
  logic [2:0] s_write_prot_d, s_write_prot_q;
  logic [3:0] s_read_qos_d, s_read_qos_q;
  logic [3:0] s_write_qos_d, s_write_qos_q;
  logic [3:0] s_read_region_d, s_read_region_q;
  logic [3:0] s_write_region_d, s_write_region_q;

  assign s_read_state_q = channel_state_e'(s_read_state_bits_q);
  assign s_write_state_q = channel_state_e'(s_write_state_bits_q);
  assign s_read_beats = {1'b0, wide.arlen} + 9'd1;
  assign s_write_beats = {1'b0, wide.awlen} + 9'd1;

  // Split fragments replay the accepted address channel, so lock, cache, prot,
  // qos, and region are registered alongside the geometry fields.
  assign s_read_wide_split = (wide.arsize == 3'd3) && (wide.arburst == `AXI4_BURST_TYPE_INCR) &&
                             (wide.arlen > 8'd7);
  assign s_write_wide_split = (wide.awsize == 3'd3) && (wide.awburst == `AXI4_BURST_TYPE_INCR) &&
                              (wide.awlen > 8'd7);
  assign s_read_split = (s_read_size_q == 3'd3) && (s_read_burst_q == `AXI4_BURST_TYPE_INCR) &&
                        (s_read_len_q > 8'd7);
  assign s_write_split = (s_write_size_q == 3'd3) && (s_write_burst_q == `AXI4_BURST_TYPE_INCR) &&
                         (s_write_len_q > 8'd7);
  assign s_read_fragment_ar_issue = (s_read_state_q == Active) && s_read_split &&
                                    !s_read_fragment_ar_q;
  assign s_write_fragment_aw_issue = (s_write_state_q == Active) && s_write_split &&
                                     s_write_fragment_q && !s_write_fragment_aw_q;
  assign s_read_fragment_len = 8'((({1'b0, s_read_len_q} - 9'd7) << 1) - 9'd1);
  assign s_write_fragment_len = 8'((({1'b0, s_write_len_q} - 9'd7) << 1) - 9'd1);

  assign wide.arready = (s_read_state_q == Idle) && narrow.arready;
  assign narrow.arvalid = ((s_read_state_q == Idle) && wide.arvalid) || s_read_fragment_ar_issue;
  assign narrow.arid = '0;
  assign narrow.araddr = (s_read_state_q == Idle) ? wide.araddr : s_read_addr_q;
  assign narrow.arlen = (s_read_state_q == Idle) ?
                        ((wide.arsize == 3'd3) ?
                         (s_read_wide_split ? 8'd15 : 8'((s_read_beats << 1) - 9'd1)) :
                         wide.arlen) :
                        s_read_fragment_len;
  assign narrow.arsize = (s_read_state_q == Idle) ? ((wide.arsize == 3'd3) ? 3'd2 : wide.arsize) :
                         3'd2;
  assign narrow.arburst = (s_read_state_q == Idle) ? wide.arburst : s_read_burst_q;
  assign narrow.arlock = (s_read_state_q == Idle) ? wide.arlock : s_read_lock_q;
  assign narrow.arcache = (s_read_state_q == Idle) ? wide.arcache : s_read_cache_q;
  assign narrow.arprot = (s_read_state_q == Idle) ? wide.arprot : s_read_prot_q;
  assign narrow.arqos = (s_read_state_q == Idle) ? wide.arqos : s_read_qos_q;
  assign narrow.arregion = (s_read_state_q == Idle) ? wide.arregion : s_read_region_q;
  assign narrow.aruser = '0;
  assign s_read_accept = wide.arvalid && wide.arready;
  assign s_narrow_read_addr_accept = s_read_fragment_ar_issue && narrow.arready;

  assign wide.rid = s_read_id_q;
  assign wide.rdata = (s_read_size_q == 3'd3) ? {narrow.rdata, s_read_lower_q} :
                      s_read_addr_q[2] ? {narrow.rdata, 32'd0} : {32'd0, narrow.rdata};
  assign wide.rresp = (s_read_size_q == 3'd3) && (s_read_resp_q != `AXI4_RESP_OKAY) ?
                      s_read_resp_q : narrow.rresp;
  assign wide.rlast = narrow.rlast && (!s_read_split || s_read_fragment_q);
  assign wide.ruser = '0;
  assign wide.rvalid = (s_read_state_q == Active) && narrow.rvalid &&
                       ((s_read_size_q != 3'd3) || s_read_upper_q);
  assign narrow.rready = (s_read_state_q == Active) &&
                         (((s_read_size_q == 3'd3) && !s_read_upper_q) || wide.rready);
  assign s_narrow_read_accept = narrow.rvalid && narrow.rready;
  assign s_wide_read_accept = wide.rvalid && wide.rready;

  always_comb begin
    s_read_state_d       = s_read_state_q;
    s_read_id_d          = s_read_id_q;
    s_read_size_d        = s_read_size_q;
    s_read_len_d         = s_read_len_q;
    s_read_burst_d       = s_read_burst_q;
    s_read_addr_d        = s_read_addr_q;
    s_read_upper_d       = s_read_upper_q;
    s_read_lower_d       = s_read_lower_q;
    s_read_resp_d        = s_read_resp_q;
    s_read_fragment_d    = s_read_fragment_q;
    s_read_fragment_ar_d = s_read_fragment_ar_q;
    s_read_lock_d        = s_read_lock_q;
    s_read_cache_d       = s_read_cache_q;
    s_read_prot_d        = s_read_prot_q;
    s_read_qos_d         = s_read_qos_q;
    s_read_region_d      = s_read_region_q;

    if (s_read_accept) begin
      s_read_state_d       = Active;
      s_read_id_d          = wide.arid;
      s_read_size_d        = wide.arsize;
      s_read_len_d         = wide.arlen;
      s_read_burst_d       = wide.arburst;
      s_read_addr_d        = wide.araddr;
      s_read_upper_d       = 1'b0;
      s_read_resp_d        = `AXI4_RESP_OKAY;
      s_read_fragment_d    = 1'b0;
      s_read_fragment_ar_d = 1'b1;
      s_read_lock_d        = wide.arlock;
      s_read_cache_d       = wide.arcache;
      s_read_prot_d        = wide.arprot;
      s_read_qos_d         = wide.arqos;
      s_read_region_d      = wide.arregion;
    end

    if (s_narrow_read_addr_accept) s_read_fragment_ar_d = 1'b1;

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

    if (s_narrow_read_accept && narrow.rlast && s_read_split && !s_read_fragment_q) begin
      s_read_fragment_d    = 1'b1;
      s_read_fragment_ar_d = 1'b0;
    end

    if (s_wide_read_accept) begin
      s_read_addr_d = s_read_next_addr;
      if (narrow.rlast && (!s_read_split || s_read_fragment_q)) s_read_state_d = Idle;
    end

    if (clear_i) begin
      s_read_state_d       = Idle;
      s_read_upper_d       = 1'b0;
      s_read_resp_d        = `AXI4_RESP_OKAY;
      s_read_fragment_d    = 1'b0;
      s_read_fragment_ar_d = 1'b0;
    end
  end

  assign wide.awready = (s_write_state_q == Idle) && narrow.awready;
  assign narrow.awvalid = ((s_write_state_q == Idle) && wide.awvalid) || s_write_fragment_aw_issue;
  assign narrow.awid = '0;
  assign narrow.awaddr = (s_write_state_q == Idle) ? wide.awaddr : s_write_addr_q;
  assign narrow.awlen = (s_write_state_q == Idle) ?
                        ((wide.awsize == 3'd3) ?
                         (s_write_wide_split ? 8'd15 : 8'((s_write_beats << 1) - 9'd1)) :
                         wide.awlen) :
                        s_write_fragment_len;
  assign narrow.awsize = (s_write_state_q == Idle) ?
                         ((wide.awsize == 3'd3) ? 3'd2 : wide.awsize) : 3'd2;
  assign narrow.awburst = (s_write_state_q == Idle) ? wide.awburst : s_write_burst_q;
  assign narrow.awlock = (s_write_state_q == Idle) ? wide.awlock : s_write_lock_q;
  assign narrow.awcache = (s_write_state_q == Idle) ? wide.awcache : s_write_cache_q;
  assign narrow.awprot = (s_write_state_q == Idle) ? wide.awprot : s_write_prot_q;
  assign narrow.awqos = (s_write_state_q == Idle) ? wide.awqos : s_write_qos_q;
  assign narrow.awregion = (s_write_state_q == Idle) ? wide.awregion : s_write_region_q;
  assign narrow.awuser = '0;
  assign s_write_addr_accept = wide.awvalid && wide.awready;
  assign s_narrow_write_addr_accept = s_write_fragment_aw_issue && narrow.awready;

  assign narrow.wdata = (s_write_size_q == 3'd3) ?
                        (s_write_upper_q ? wide.wdata[63:32] : wide.wdata[31:0]) :
                        (s_write_addr_q[2] ? wide.wdata[63:32] : wide.wdata[31:0]);
  assign narrow.wstrb = (s_write_size_q == 3'd3) ?
                        (s_write_upper_q ? wide.wstrb[7:4] : wide.wstrb[3:0]) :
                        (s_write_addr_q[2] ? wide.wstrb[7:4] : wide.wstrb[3:0]);
  assign s_write_fragment_wlast = (s_write_fragment_q == 1'b0) ?
                                  (s_write_fragment_beat_q == 3'd7) : wide.wlast;
  assign narrow.wlast = (s_write_size_q != 3'd3) ? wide.wlast :
                        s_write_upper_q && (s_write_split ? s_write_fragment_wlast : wide.wlast);
  assign narrow.wuser = '0;
  assign narrow.wvalid = (s_write_state_q == Active) && s_write_fragment_aw_q && wide.wvalid;
  assign wide.wready = (s_write_state_q == Active) && s_write_fragment_aw_q && narrow.wready &&
                       ((s_write_size_q != 3'd3) || s_write_upper_q);
  assign s_narrow_write_accept = narrow.wvalid && narrow.wready;
  assign s_wide_write_accept = wide.wvalid && wide.wready;

  assign wide.bid = s_write_id_q;
  assign wide.bresp = s_b_resp_q;
  assign wide.buser = '0;
  assign wide.bvalid = s_b_pending_q;
  assign narrow.bready = (s_write_state_q == Active) && !s_b_pending_q;

  always_comb begin
    s_write_state_d         = s_write_state_q;
    s_write_id_d            = s_write_id_q;
    s_write_size_d          = s_write_size_q;
    s_write_len_d           = s_write_len_q;
    s_write_burst_d         = s_write_burst_q;
    s_write_addr_d          = s_write_addr_q;
    s_write_upper_d         = s_write_upper_q;
    s_b_pending_d           = s_b_pending_q;
    s_b_resp_d              = s_b_resp_q;
    s_write_fragment_d      = s_write_fragment_q;
    s_write_fragment_aw_d   = s_write_fragment_aw_q;
    s_write_fragment_beat_d = s_write_fragment_beat_q;
    s_write_lock_d          = s_write_lock_q;
    s_write_cache_d         = s_write_cache_q;
    s_write_prot_d          = s_write_prot_q;
    s_write_qos_d           = s_write_qos_q;
    s_write_region_d        = s_write_region_q;

    if (s_write_addr_accept) begin
      s_write_state_d         = Active;
      s_write_id_d            = wide.awid;
      s_write_size_d          = wide.awsize;
      s_write_len_d           = wide.awlen;
      s_write_burst_d         = wide.awburst;
      s_write_addr_d          = wide.awaddr;
      s_write_upper_d         = 1'b0;
      s_b_pending_d           = 1'b0;
      s_write_fragment_d      = 1'b0;
      s_write_fragment_aw_d   = 1'b1;
      s_write_fragment_beat_d = 3'd0;
      s_write_lock_d          = wide.awlock;
      s_write_cache_d         = wide.awcache;
      s_write_prot_d          = wide.awprot;
      s_write_qos_d           = wide.awqos;
      s_write_region_d        = wide.awregion;
    end

    if (s_narrow_write_addr_accept) s_write_fragment_aw_d = 1'b1;

    if (s_narrow_write_accept && (s_write_size_q == 3'd3)) begin
      s_write_upper_d = !s_write_upper_q;
    end

    if (s_narrow_write_accept && narrow.wlast && s_write_split && !s_write_fragment_q) begin
      s_write_fragment_aw_d = 1'b0;
    end

    if (s_wide_write_accept) begin
      s_write_addr_d = s_write_next_addr;
      if (s_write_split && !s_write_fragment_q) begin
        s_write_fragment_beat_d = (s_write_fragment_beat_q == 3'd7) ? 3'd0 :
                                  (s_write_fragment_beat_q + 3'd1);
      end
    end

    if (narrow.bvalid && narrow.bready) begin
      if (s_write_split && !s_write_fragment_q) begin
        s_b_resp_d         = narrow.bresp;
        s_write_fragment_d = 1'b1;
      end else begin
        s_b_pending_d = 1'b1;
        s_b_resp_d = (s_write_split && (s_b_resp_q != `AXI4_RESP_OKAY)) ? s_b_resp_q : narrow.bresp;
      end
    end
    if (wide.bvalid && wide.bready) begin
      s_b_pending_d   = 1'b0;
      s_write_state_d = Idle;
    end

    if (clear_i) begin
      s_write_state_d         = Idle;
      s_write_upper_d         = 1'b0;
      s_b_pending_d           = 1'b0;
      s_b_resp_d              = `AXI4_RESP_OKAY;
      s_write_fragment_d      = 1'b0;
      s_write_fragment_aw_d   = 1'b0;
      s_write_fragment_beat_d = 3'd0;
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
  dffr #(
      .DATA_WIDTH(1)
  ) u_read_fragment_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_fragment_d),
      .dat_o  (s_read_fragment_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_read_fragment_ar_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_fragment_ar_d),
      .dat_o  (s_read_fragment_ar_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_write_fragment_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_fragment_d),
      .dat_o  (s_write_fragment_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_write_fragment_aw_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_fragment_aw_d),
      .dat_o  (s_write_fragment_aw_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_write_fragment_beat_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_fragment_beat_d),
      .dat_o  (s_write_fragment_beat_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_read_lock_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_lock_d),
      .dat_o  (s_read_lock_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_write_lock_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_lock_d),
      .dat_o  (s_write_lock_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_read_cache_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_cache_d),
      .dat_o  (s_read_cache_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_write_cache_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_cache_d),
      .dat_o  (s_write_cache_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_read_prot_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_prot_d),
      .dat_o  (s_read_prot_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_write_prot_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_prot_d),
      .dat_o  (s_write_prot_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_read_qos_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_qos_d),
      .dat_o  (s_read_qos_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_write_qos_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_qos_d),
      .dat_o  (s_write_qos_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_read_region_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_region_d),
      .dat_o  (s_read_region_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_write_region_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_region_d),
      .dat_o  (s_write_region_q)
  );

`ifndef SYNTHESIS
  property p_wide_read_geometry;
    @(posedge clk_i) disable iff (!rst_n_i) wide.arvalid |->
        ((wide.arsize <= 3'd3) &&
         ((wide.arsize != 3'd3) ||
          ((wide.arlen <= 8'd15) && (wide.araddr[2:0] == 3'd0) &&
           ((wide.arlen <= 8'd7) || (wide.arburst == `AXI4_BURST_TYPE_INCR)))));
  endproperty
  assert property (p_wide_read_geometry);

  property p_wide_write_geometry;
    @(posedge clk_i) disable iff (!rst_n_i) wide.awvalid |->
        ((wide.awsize <= 3'd3) &&
         ((wide.awsize != 3'd3) ||
          ((wide.awlen <= 8'd15) && (wide.awaddr[2:0] == 3'd0) &&
           ((wide.awlen <= 8'd7) || (wide.awburst == `AXI4_BURST_TYPE_INCR)))));
  endproperty
  assert property (p_wide_write_geometry);
`endif
endmodule
