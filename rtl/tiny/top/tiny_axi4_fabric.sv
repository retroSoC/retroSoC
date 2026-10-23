// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0
`include "mmap_define.svh"
`include "tiny_topology.svh"

// Three active owners and topology-selected independent targets. CPU admits one
// combined operation; DMA and SDIO each admit one read and one write. IDs are
// unchanged: saved target ownership, not ID expansion, routes all responses.
module tiny_axi4_fabric (
    input logic clk_i,
    input logic rst_n_i,
    input logic perf_enable_i,
    input logic perf_clear_i,
    input logic target_rst_n_i[`RETROSOC_TINY__TARGET_COUNT],
    axi4_if.slave masters[3],
    axi4_if.master targets[`RETROSOC_TINY__TARGET_COUNT],
    output logic [5:0] fault_valid_o,
    output logic [5:0][31:0] fault_addr_o,
    output logic [5:0][1:0] fault_resp_o,
    output logic [5:0] fault_instruction_o,
    output logic [2:0] owner_idle_o,
    output logic [`RETROSOC_TINY__TARGET_COUNT-1:0] target_idle_o,
    output logic [63:0] cpu_wait_o,
    output logic [63:0] dma_wait_o
);
  localparam logic [4:0] DecodeErrorTarget = 5'(`RETROSOC_TINY__DECODE_ERROR);
  localparam logic [4:0] ProtocolErrorTarget = 5'(`RETROSOC_TINY__PROTOCOL_ERROR);
  logic [5:0] s_busy_d, s_busy_q, s_admit, s_done, s_eligible;
  logic s_cpu_prefer_write_d, s_cpu_prefer_write_q;
  logic [2:0][4:0] s_read_target, s_write_target;
  logic [`RETROSOC_TINY__TARGET_COUNT-1:0][2:0] s_arready, s_awready, s_wready, s_rvalid, s_bvalid;
  logic [`RETROSOC_TINY__TARGET_COUNT-1:0][ 2:0][39:0] s_rdata;
  logic [`RETROSOC_TINY__TARGET_COUNT-1:0][ 2:0][ 6:0] s_bdata;
  logic [                             2:0][39:0]       s_read_return;
  logic [                             2:0][ 6:0]       s_write_return;
  logic [2:0] s_master_arready, s_master_awready, s_master_wready, s_master_rvalid, s_master_bvalid;
  logic [2:0] s_arvalid, s_awvalid;
  logic [1:0][63:0] s_wait_d, s_wait_q;
  logic [`RETROSOC_TINY__TARGET_COUNT-1:0] s_fault_valid, s_fault_write, s_fault_instruction;
  logic [`RETROSOC_TINY__TARGET_COUNT-1:0][31:0] s_fault_addr;
  logic [`RETROSOC_TINY__TARGET_COUNT-1:0][1:0] s_fault_master, s_fault_resp;

  function automatic logic [4:0] decode_target(input logic [31:0] addr_i);
    if (`SOC_ADDR_IS_SRAM(addr_i)) return {3'd0, addr_i[16:15]};
    if (`SOC_ADDR_IS_FLASH(addr_i) || `SOC_ADDR_IS_XPI(addr_i)) return 5'd4;
    `include "tiny_fabric_decode.svh"
    return DecodeErrorTarget;
  endfunction
  function automatic logic [4:0] checked_target(input logic [31:0] addr_i, input logic [7:0] len_i,
                                                input logic [2:0] size_i, input logic [1:0] burst_i,
                                                input logic lock_i, input logic instruction_i);
    logic [32:0] last_addr;
    logic [ 4:0] decoded;
    decoded   = decode_target(addr_i);
    last_addr = {1'b0, addr_i} + (({25'd0, len_i} + 33'd1) << size_i) - 33'd1;
    if (lock_i || (size_i > 3'd2) || (len_i > 8'd15) ||
        ((addr_i & ((32'd1 << size_i) - 32'd1)) != 32'd0) ||
        !((burst_i == 2'b01) || ((burst_i == 2'b00) && (len_i == 8'd0))) ||
        last_addr[32] || (last_addr[31:12] != addr_i[31:12]) ||
        (decode_target(
            last_addr[31:0]
        ) != decoded) || ((decoded >= 5'd5) && (decoded < DecodeErrorTarget) && (len_i != 8'd0)))
      return ProtocolErrorTarget;
    if (instruction_i && !(
        `SOC_ADDR_IS_FLASH(addr_i)
        || ((addr_i >= 32'h5000_0000) && (addr_i < 32'h5400_0000)))) begin
      if ((decoded >= 5'd5) && (decoded < DecodeErrorTarget)) return ProtocolErrorTarget;
      return DecodeErrorTarget;
    end
    return decoded;
  endfunction

  assign s_busy_d             = (s_busy_q & ~s_done) | s_admit;
  assign s_cpu_prefer_write_d = s_admit[0] ? 1'b1 : s_admit[1] ? 1'b0 : s_cpu_prefer_write_q;
  assign cpu_wait_o           = s_wait_q[0];
  assign dma_wait_o           = s_wait_q[1];
  dffr #(
      .DATA_WIDTH(6)
  ) u_direction_busy (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_busy_d),
      .dat_o  (s_busy_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_cpu_direction (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_cpu_prefer_write_d),
      .dat_o  (s_cpu_prefer_write_q)
  );
  dffr #(
      .DATA_WIDTH(128)
  ) u_wait_counters (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_wait_d),
      .dat_o  (s_wait_q)
  );

  always_comb begin
    s_master_arready    = '0;
    s_master_awready    = '0;
    s_master_wready     = '0;
    s_master_rvalid     = '0;
    s_master_bvalid     = '0;
    s_read_return       = '0;
    s_write_return      = '0;
    fault_valid_o       = '0;
    fault_addr_o        = '0;
    fault_resp_o        = '0;
    fault_instruction_o = '0;
    for (int target_index = 0; target_index < `RETROSOC_TINY__TARGET_COUNT; target_index++) begin
      s_master_arready |= s_arready[target_index];
      s_master_awready |= s_awready[target_index];
      s_master_wready |= s_wready[target_index];
      s_master_rvalid |= s_rvalid[target_index];
      s_master_bvalid |= s_bvalid[target_index];
      for (int owner = 0; owner < 3; owner++) begin
        if (s_rvalid[target_index][owner]) s_read_return[owner] = s_rdata[target_index][owner];
        if (s_bvalid[target_index][owner]) s_write_return[owner] = s_bdata[target_index][owner];
      end
      if (s_fault_valid[target_index]) begin
        fault_valid_o[{s_fault_master[target_index], s_fault_write[target_index]}] = 1'b1;
        fault_addr_o[{
          s_fault_master[target_index], s_fault_write[target_index]
        }] = s_fault_addr[target_index];
        fault_resp_o[{
          s_fault_master[target_index], s_fault_write[target_index]
        }] = s_fault_resp[target_index];
        fault_instruction_o[{
          s_fault_master[target_index], s_fault_write[target_index]
        }] = s_fault_instruction[target_index];
      end
    end
    s_wait_d = s_wait_q;
    for (int owner = 0; owner < 2; owner++) begin
      if (perf_clear_i) s_wait_d[owner] = '0;
      else if (perf_enable_i && (s_arvalid[owner] || s_awvalid[owner]) &&
          !(s_admit[2*owner] || s_admit[2*owner+1]) && (s_wait_q[owner] != 64'hffff_ffff_ffff_ffff))
        s_wait_d[owner] = s_wait_q[owner] + 64'd1;
    end
  end
  for (genvar owner = 0; owner < 3; owner++) begin : gen_owner
    assign s_arvalid[owner] = masters[owner].arvalid;
    assign s_awvalid[owner] = masters[owner].awvalid;
    assign owner_idle_o[owner] = !(s_busy_q[2*owner] || s_busy_q[2*owner+1]);
    assign s_read_target[owner] = checked_target(
        masters[owner].araddr,
        masters[owner].arlen,
        masters[owner].arsize,
        masters[owner].arburst,
        masters[owner].arlock,
        (owner == 0) && masters[owner].arprot[2]
    );
    assign s_write_target[owner] = checked_target(
        masters[owner].awaddr,
        masters[owner].awlen,
        masters[owner].awsize,
        masters[owner].awburst,
        masters[owner].awlock,
        1'b0
    );
    if (owner == 0) begin : gen_combined_credit
      assign s_eligible[2*owner] = rst_n_i && owner_idle_o[owner] && masters[owner].arvalid &&
          (!masters[owner].awvalid || !s_cpu_prefer_write_q);
      assign s_eligible[2*owner+1] = rst_n_i && owner_idle_o[owner] && masters[owner].awvalid &&
          (!masters[owner].arvalid || s_cpu_prefer_write_q);
    end else begin : gen_direction_credits
      assign s_eligible[2*owner]   = rst_n_i && !s_busy_q[2*owner] && masters[owner].arvalid;
      assign s_eligible[2*owner+1] = rst_n_i && !s_busy_q[2*owner+1] && masters[owner].awvalid;
    end
    assign s_admit[2*owner] = masters[owner].arvalid && masters[owner].arready;
    assign s_admit[2*owner+1] = masters[owner].awvalid && masters[owner].awready;
    assign s_done[2*owner] = masters[owner].rvalid && masters[owner].rready && masters[owner].rlast;
    assign s_done[2*owner+1] = masters[owner].bvalid && masters[owner].bready;
    assign masters[owner].arready = s_master_arready[owner];
    assign masters[owner].awready = s_master_awready[owner];
    assign masters[owner].wready = s_master_wready[owner];
    assign masters[owner].rvalid = s_master_rvalid[owner];
    assign masters[owner].bvalid = s_master_bvalid[owner];
    assign {masters[owner].rid, masters[owner].rdata, masters[owner].rresp,
            masters[owner].rlast, masters[owner].ruser} = s_read_return[owner];
    assign {masters[owner].bid, masters[owner].bresp, masters[owner].buser} = s_write_return[owner];
  end
  for (
      genvar target_index = 0; target_index < `RETROSOC_TINY__TARGET_COUNT; target_index++
  ) begin : gen_target
    axi4_if #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32),
        .ID_WIDTH  (1),
        .USER_WIDTH(4)
    ) u_routes[3] (
        .aclk   (clk_i),
        .aresetn(rst_n_i)
    );
    for (genvar owner = 0; owner < 3; owner++) begin : gen_route
      logic s_read_selected, s_write_selected;
      assign s_read_selected = s_read_target[owner] == 5'(target_index);
      assign s_write_selected = s_write_target[owner] == 5'(target_index);
      assign u_routes[owner].arid = masters[owner].arid;
      assign u_routes[owner].araddr = masters[owner].araddr;
      assign u_routes[owner].arlen = masters[owner].arlen;
      assign u_routes[owner].arsize = masters[owner].arsize;
      assign u_routes[owner].arburst = masters[owner].arburst;
      assign u_routes[owner].arlock = masters[owner].arlock;
      assign u_routes[owner].arcache = masters[owner].arcache;
      assign u_routes[owner].arprot = masters[owner].arprot;
      assign u_routes[owner].arqos = masters[owner].arqos;
      assign u_routes[owner].arregion = masters[owner].arregion;
      assign u_routes[owner].aruser = masters[owner].aruser;
      assign u_routes[owner].awid = masters[owner].awid;
      assign u_routes[owner].awaddr = masters[owner].awaddr;
      assign u_routes[owner].awlen = masters[owner].awlen;
      assign u_routes[owner].awsize = masters[owner].awsize;
      assign u_routes[owner].awburst = masters[owner].awburst;
      assign u_routes[owner].awlock = masters[owner].awlock;
      assign u_routes[owner].awcache = masters[owner].awcache;
      assign u_routes[owner].awprot = masters[owner].awprot;
      assign u_routes[owner].awqos = masters[owner].awqos;
      assign u_routes[owner].awregion = masters[owner].awregion;
      assign u_routes[owner].awuser = masters[owner].awuser;
      assign u_routes[owner].arvalid = s_eligible[2*owner] && s_read_selected;
      assign u_routes[owner].awvalid = s_eligible[2*owner+1] && s_write_selected;
      assign u_routes[owner].wdata = masters[owner].wdata;
      assign u_routes[owner].wstrb = masters[owner].wstrb;
      assign u_routes[owner].wlast = masters[owner].wlast;
      assign u_routes[owner].wuser = masters[owner].wuser;
      assign u_routes[owner].wvalid = masters[owner].wvalid;
      assign u_routes[owner].rready = masters[owner].rready;
      assign u_routes[owner].bready = masters[owner].bready;
      assign s_arready[target_index][owner] = u_routes[owner].arready;
      assign s_awready[target_index][owner] = u_routes[owner].awready;
      assign s_wready[target_index][owner] = u_routes[owner].wready;
      assign s_rvalid[target_index][owner] = u_routes[owner].rvalid;
      assign s_bvalid[target_index][owner] = u_routes[owner].bvalid;
      assign s_rdata[target_index][owner] = {
        u_routes[owner].rid,
        u_routes[owner].rdata,
        u_routes[owner].rresp,
        u_routes[owner].rlast,
        u_routes[owner].ruser
      };
      assign s_bdata[target_index][owner] = {
        u_routes[owner].bid, u_routes[owner].bresp, u_routes[owner].buser
      };
    end
    tiny_axi4_target u_controller (
        .clk_i              (clk_i),
        .rst_n_i            (rst_n_i),
        .enable_i           (target_rst_n_i[target_index]),
        .masters            (u_routes),
        .target             (targets[target_index]),
        .idle_o             (target_idle_o[target_index]),
        .fault_valid_o      (s_fault_valid[target_index]),
        .fault_addr_o       (s_fault_addr[target_index]),
        .fault_master_o     (s_fault_master[target_index]),
        .fault_write_o      (s_fault_write[target_index]),
        .fault_instruction_o(s_fault_instruction[target_index]),
        .fault_resp_o       (s_fault_resp[target_index])
    );
  end
`ifdef HAVE_SVA
  assert property (@(posedge clk_i) disable iff (!rst_n_i) !(s_busy_q[0] && s_busy_q[1]));
  assert property (@(posedge clk_i) disable iff (!rst_n_i) (s_admit & s_busy_q) == 6'd0);
  assert property (@(posedge clk_i) disable iff (!rst_n_i) (s_done & ~s_busy_q) == 6'd0);
  for (genvar owner = 0; owner < 3; owner++) begin : gen_route_assert
    logic [`RETROSOC_TINY__TARGET_COUNT-1:0] s_reads, s_writes;
    for (genvar t = 0; t < `RETROSOC_TINY__TARGET_COUNT; t++) begin : gen_column
      assign s_reads[t]  = s_rvalid[t][owner];
      assign s_writes[t] = s_bvalid[t][owner];
    end
    assert property (@(posedge clk_i) disable iff (!rst_n_i) $onehot0(s_reads));
    assert property (@(posedge clk_i) disable iff (!rst_n_i) $onehot0(s_writes));
  end
`endif
endmodule
