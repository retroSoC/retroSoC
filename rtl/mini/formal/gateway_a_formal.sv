// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module gateway_a_formal_design (
    input  logic        clk_i,
    output logic        rst_n_i,
    output logic        f_past_valid,
    output logic [ 5:0] cycle,
    output logic [ 2:0] response,
    output logic [ 2:0] seen,
    output logic        address_valid,
    output logic        address_ready,
    output logic [31:0] address_value,
    output logic        address_accept,
    output logic        terminal
);
  logic [ 5:0] s_cycle_q;
  logic        s_response_valid_q;
  logic [31:0] s_response_data_q;
  logic [ 2:0] s_seen_q;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) icache (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) dcache (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) mmio (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  assign icache.arid     = 1'b0;
  assign dcache.arid     = 1'b0;
  assign mmio.arid       = 1'b0;
  assign icache.araddr   = 32'h0000_1000;
  assign dcache.araddr   = 32'h0000_2000;
  assign mmio.araddr     = 32'h0000_3000;
  assign icache.arlen    = 8'd0;
  assign dcache.arlen    = 8'd0;
  assign mmio.arlen      = 8'd0;
  assign icache.arsize   = 3'd2;
  assign dcache.arsize   = 3'd2;
  assign mmio.arsize     = 3'd2;
  assign icache.arburst  = 2'd1;
  assign dcache.arburst  = 2'd1;
  assign mmio.arburst    = 2'd1;
  assign icache.arlock   = 1'b0;
  assign dcache.arlock   = 1'b0;
  assign mmio.arlock     = 1'b0;
  assign icache.arcache  = 4'd0;
  assign dcache.arcache  = 4'd0;
  assign mmio.arcache    = 4'd0;
  assign icache.arprot   = 3'd0;
  assign dcache.arprot   = 3'd0;
  assign mmio.arprot     = 3'd0;
  assign icache.arqos    = 4'd0;
  assign dcache.arqos    = 4'd0;
  assign mmio.arqos      = 4'd0;
  assign icache.arregion = 4'd0;
  assign dcache.arregion = 4'd0;
  assign mmio.arregion   = 4'd0;
  assign icache.aruser   = 1'b0;
  assign dcache.aruser   = 1'b0;
  assign mmio.aruser     = 1'b0;
  assign icache.arvalid  = rst_n_i;
  assign dcache.arvalid  = rst_n_i && (s_cycle_q >= 6'd1);
  assign mmio.arvalid    = rst_n_i && (s_cycle_q >= 6'd2);
  assign icache.rready   = 1'b1;
  assign dcache.rready   = 1'b1;
  assign mmio.rready     = 1'b1;

  assign icache.awid     = 1'b0;
  assign dcache.awid     = 1'b0;
  assign mmio.awid       = 1'b0;
  assign icache.awaddr   = 32'd0;
  assign dcache.awaddr   = 32'd0;
  assign mmio.awaddr     = 32'd0;
  assign icache.awlen    = 8'd0;
  assign dcache.awlen    = 8'd0;
  assign mmio.awlen      = 8'd0;
  assign icache.awsize   = 3'd2;
  assign dcache.awsize   = 3'd2;
  assign mmio.awsize     = 3'd2;
  assign icache.awburst  = 2'd1;
  assign dcache.awburst  = 2'd1;
  assign mmio.awburst    = 2'd1;
  assign icache.awlock   = 1'b0;
  assign dcache.awlock   = 1'b0;
  assign mmio.awlock     = 1'b0;
  assign icache.awcache  = 4'd0;
  assign dcache.awcache  = 4'd0;
  assign mmio.awcache    = 4'd0;
  assign icache.awprot   = 3'd0;
  assign dcache.awprot   = 3'd0;
  assign mmio.awprot     = 3'd0;
  assign icache.awqos    = 4'd0;
  assign dcache.awqos    = 4'd0;
  assign mmio.awqos      = 4'd0;
  assign icache.awregion = 4'd0;
  assign dcache.awregion = 4'd0;
  assign mmio.awregion   = 4'd0;
  assign icache.awuser   = 1'b0;
  assign dcache.awuser   = 1'b0;
  assign mmio.awuser     = 1'b0;
  assign icache.awvalid  = 1'b0;
  assign dcache.awvalid  = 1'b0;
  assign mmio.awvalid    = 1'b0;
  assign icache.wdata    = 32'd0;
  assign dcache.wdata    = 32'd0;
  assign mmio.wdata      = 32'd0;
  assign icache.wstrb    = 4'd0;
  assign dcache.wstrb    = 4'd0;
  assign mmio.wstrb      = 4'd0;
  assign icache.wlast    = 1'b0;
  assign dcache.wlast    = 1'b0;
  assign mmio.wlast      = 1'b0;
  assign icache.wuser    = 1'b0;
  assign dcache.wuser    = 1'b0;
  assign mmio.wuser      = 1'b0;
  assign icache.wvalid   = 1'b0;
  assign dcache.wvalid   = 1'b0;
  assign mmio.wvalid     = 1'b0;
  assign icache.bready   = 1'b1;
  assign dcache.bready   = 1'b1;
  assign mmio.bready     = 1'b1;

  assign axi4.awready    = 1'b0;
  assign axi4.wready     = 1'b0;
  assign axi4.bid        = 1'b0;
  assign axi4.bresp      = 2'd0;
  assign axi4.buser      = 1'b0;
  assign axi4.bvalid     = 1'b0;
  assign axi4.arready    = !s_response_valid_q && (s_cycle_q >= 6'd3);
  assign axi4.rid        = 1'b0;
  assign axi4.rdata      = s_response_data_q;
  assign axi4.rresp      = 2'd0;
  assign axi4.rlast      = 1'b1;
  assign axi4.ruser      = 1'b0;
  assign axi4.rvalid     = s_response_valid_q;

  hp_axi4_mux3 #(
      .RoundRobin(1'b1)
  ) u_dut (
      .clk_i,
      .rst_n_i,
      .epoch_i(8'd0),
      .icache,
      .dcache,
      .mmio,
      .axi4
  );

  assign cycle = s_cycle_q;
  assign response = {
    mmio.rvalid && mmio.rready, dcache.rvalid && dcache.rready, icache.rvalid && icache.rready
  };
  assign seen = s_seen_q;
  assign address_valid = axi4.arvalid;
  assign address_ready = axi4.arready;
  assign address_value = axi4.araddr;
  assign address_accept = axi4.arvalid && axi4.arready;
  assign terminal = axi4.rvalid && axi4.rready && axi4.rlast;

  initial begin
    rst_n_i      = 1'b0;
    f_past_valid = 1'b0;
  end

  always_ff @(posedge clk_i) begin
    rst_n_i      <= 1'b1;
    f_past_valid <= 1'b1;
    if (!rst_n_i) begin
      s_cycle_q <= 6'd0;
      s_seen_q  <= 3'd0;
    end else begin
      if (s_cycle_q != 6'h3f) s_cycle_q <= s_cycle_q + 1'b1;
      s_seen_q <= s_seen_q | response;
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_response_valid_q <= 1'b0;
      s_response_data_q  <= 32'd0;
    end else begin
      if (axi4.arvalid && axi4.arready) begin
        s_response_valid_q <= 1'b1;
        s_response_data_q  <= axi4.araddr;
      end
      if (axi4.rvalid && axi4.rready) s_response_valid_q <= 1'b0;
    end
  end
endmodule
