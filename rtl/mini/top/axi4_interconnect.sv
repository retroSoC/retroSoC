// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.
// See LICENSE for the complete license text.

`include "axi4_define.svh"
`include "mmap_define.svh"
`include "rib_defs.svh"

module axi4_interconnect #(
    parameter int NumMasters = 7,
    parameter int NumTargets = 10
) (
    input  logic                 clk_i,
    input  logic                 rst_n_i,
           axi4_if.slave         masters                [NumMasters],
           axi4_if.master        targets                [NumTargets],
    input  logic                 user_bus_enable_i,
    output logic                 user_bus_idle_o,
    input  logic          [ 1:0] mem_pad_mode_i,
    input  logic                 perf_enable_i,
    input  logic                 perf_clear_i,
    output logic                 fault_valid_o,
    output logic          [31:0] fault_addr_o,
    output logic          [ 3:0] fault_wstrb_o,
    output logic                 fault_reserved_o,
    output logic                 fault_access_o,
    output logic          [ 2:0] fault_master_o,
    output logic          [ 2:0] fault_code_o,
    output logic          [63:0] perf_mgmt_wait_o,
    output logic          [63:0] perf_user_wait_o,
    output logic          [63:0] perf_dma_wait_o,
    output logic          [63:0] perf_sdio0_wait_o,
    output logic          [63:0] perf_sdio1_wait_o,
    output logic          [63:0] perf_usb2_wait_o,
    output logic          [63:0] perf_apb4_periph_wait_o,
    output logic          [63:0] perf_apb4_system_wait_o,
    output logic          [63:0] perf_sdram_wait_o,
    output logic          [63:0] perf_psram_wait_o,
    output logic          [63:0] perf_flash_wait_o,
    output logic          [63:0] perf_opipsram_wait_o
);
  localparam int MASTER_WIDTH = $clog2(NumMasters);
  localparam int TARGET_WIDTH = $clog2(NumTargets);

  localparam logic [TARGET_WIDTH-1:0] TARGET_CFG = TARGET_WIDTH'(0);
  localparam logic [TARGET_WIDTH-1:0] TARGET_APB4_SYSTEM = TARGET_WIDTH'(1);
  localparam logic [TARGET_WIDTH-1:0] TARGET_RAM = TARGET_WIDTH'(2);
  localparam logic [TARGET_WIDTH-1:0] TARGET_SDRAM = TARGET_WIDTH'(3);
  localparam logic [TARGET_WIDTH-1:0] TARGET_PSRAM = TARGET_WIDTH'(4);
  localparam logic [TARGET_WIDTH-1:0] TARGET_XPI = TARGET_WIDTH'(5);
  localparam logic [TARGET_WIDTH-1:0] TARGET_RETIRED_SPISD = TARGET_WIDTH'(6);
  localparam logic [TARGET_WIDTH-1:0] TARGET_DECERR = TARGET_WIDTH'(7);
  localparam logic [TARGET_WIDTH-1:0] TARGET_SLVERR = TARGET_WIDTH'(8);
  localparam logic [TARGET_WIDTH-1:0] TARGET_OPIPSRAM = TARGET_WIDTH'(9);

  localparam logic [1:0] MASTER_IDLE = 2'd0;
  localparam logic [1:0] MASTER_PENDING = 2'd1;
  localparam logic [1:0] MASTER_ACTIVE = 2'd2;

  logic [NumMasters-1:0] m_awvalid, m_awready;
  logic [NumMasters-1:0][31:0] m_awaddr;
  logic [NumMasters-1:0][ 7:0] m_awlen;
  logic [NumMasters-1:0][ 2:0] m_awsize;
  logic [NumMasters-1:0][ 1:0] m_awburst;
  logic [NumMasters-1:0]       m_awlock;
  logic [NumMasters-1:0][ 3:0] m_awcache;
  logic [NumMasters-1:0][ 2:0] m_awprot;
  logic [NumMasters-1:0][3:0] m_awqos, m_awregion;
  logic [NumMasters-1:0] m_awid, m_awuser;
  logic [NumMasters-1:0] m_wvalid, m_wready, m_wlast;
  logic [NumMasters-1:0][31:0] m_wdata;
  logic [NumMasters-1:0][ 3:0] m_wstrb;
  logic [NumMasters-1:0]       m_wuser;
  logic [NumMasters-1:0] m_bvalid, m_bready, m_bid, m_buser;
  logic [NumMasters-1:0][1:0] m_bresp;
  logic [NumMasters-1:0] m_arvalid, m_arready;
  logic [NumMasters-1:0][31:0] m_araddr;
  logic [NumMasters-1:0][ 7:0] m_arlen;
  logic [NumMasters-1:0][ 2:0] m_arsize;
  logic [NumMasters-1:0][ 1:0] m_arburst;
  logic [NumMasters-1:0]       m_arlock;
  logic [NumMasters-1:0][ 3:0] m_arcache;
  logic [NumMasters-1:0][ 2:0] m_arprot;
  logic [NumMasters-1:0][3:0] m_arqos, m_arregion;
  logic [NumMasters-1:0] m_arid, m_aruser;
  logic [NumMasters-1:0] m_rvalid, m_rready, m_rid, m_rlast, m_ruser;
  logic [NumMasters-1:0][31:0] m_rdata;
  logic [NumMasters-1:0][ 1:0] m_rresp;

  logic [NumTargets-1:0] t_awvalid, t_awready;
  logic [NumTargets-1:0][31:0] t_awaddr;
  logic [NumTargets-1:0][ 7:0] t_awlen;
  logic [NumTargets-1:0][ 2:0] t_awsize;
  logic [NumTargets-1:0][ 1:0] t_awburst;
  logic [NumTargets-1:0]       t_awlock;
  logic [NumTargets-1:0][ 3:0] t_awcache;
  logic [NumTargets-1:0][ 2:0] t_awprot;
  logic [NumTargets-1:0][3:0] t_awqos, t_awregion;
  logic [NumTargets-1:0] t_awid, t_awuser;
  logic [NumTargets-1:0] t_wvalid, t_wready, t_wlast;
  logic [NumTargets-1:0][31:0] t_wdata;
  logic [NumTargets-1:0][ 3:0] t_wstrb;
  logic [NumTargets-1:0]       t_wuser;
  logic [NumTargets-1:0] t_bvalid, t_bready, t_bid, t_buser;
  logic [NumTargets-1:0][1:0] t_bresp;
  logic [NumTargets-1:0] t_arvalid, t_arready;
  logic [NumTargets-1:0][31:0] t_araddr;
  logic [NumTargets-1:0][ 7:0] t_arlen;
  logic [NumTargets-1:0][ 2:0] t_arsize;
  logic [NumTargets-1:0][ 1:0] t_arburst;
  logic [NumTargets-1:0]       t_arlock;
  logic [NumTargets-1:0][ 3:0] t_arcache;
  logic [NumTargets-1:0][ 2:0] t_arprot;
  logic [NumTargets-1:0][3:0] t_arqos, t_arregion;
  logic [NumTargets-1:0] t_arid, t_aruser;
  logic [NumTargets-1:0] t_rvalid, t_rready, t_rid, t_rlast, t_ruser;
  logic [NumTargets-1:0][            31:0] t_rdata;
  logic [NumTargets-1:0][             1:0] t_rresp;

  // These arrays encode coupled master/target arbitration priorities. Their
  // consolidated sequential process preserves the established update order.
  // Convert them to Common registers only with sequential-equivalence proof.
  logic [NumMasters-1:0][             1:0] s_master_state;
  logic [NumMasters-1:0]                   s_master_write;
  logic [NumMasters-1:0][TARGET_WIDTH-1:0] s_master_target;
  logic [NumMasters-1:0][            31:0] s_master_addr;
  logic [NumMasters-1:0][             7:0] s_master_len;
  logic [NumMasters-1:0][             2:0] s_master_size;
  logic [NumMasters-1:0][             1:0] s_master_burst;
  logic [NumMasters-1:0]                   s_master_lock;
  logic [NumMasters-1:0][             3:0] s_master_cache;
  logic [NumMasters-1:0][             2:0] s_master_prot;
  logic [NumMasters-1:0][3:0] s_master_qos, s_master_region;
  logic [NumMasters-1:0] s_master_id, s_master_user;
  logic [NumMasters-1:0]      s_master_access_err;
  logic [NumMasters-1:0][3:0] s_master_first_wstrb;

  logic [NumTargets-1:0] s_target_valid, s_target_addr_sent;
  logic [NumTargets-1:0][MASTER_WIDTH-1:0] s_target_owner;
  logic [NumTargets-1:0][  NumMasters-1:0] s_target_req;
  logic [NumTargets-1:0][  NumMasters-1:0] s_target_grant;
  logic [NumTargets-1:0][MASTER_WIDTH-1:0] s_target_selected;
  logic [NumTargets-1:0] s_target_grant_valid, s_target_advance;
  logic [NumTargets-1:0] s_target_terminal;
  logic [NumMasters-1:0] s_master_terminal, s_master_fault;
  logic [NumMasters-1:0][ 2:0] s_master_fault_code;
  logic [NumMasters-1:0][32:0] s_last_addr;
  logic [NumMasters-1:0] s_protocol_legal, s_access_allowed;
  logic [NumMasters-1:0][TARGET_WIDTH-1:0] s_capture_target;

  logic [          63:0]                   s_perf_master_wait[NumMasters];
  logic [          63:0]                   s_perf_target_wait[NumTargets];

  function automatic logic [TARGET_WIDTH-1:0] decode_target(input logic [31:0] addr,
                                                            input logic [1:0] mem_pad_mode);
    if (`SOC_ADDR_IS_SDRAM(addr)) return TARGET_SDRAM;
    if (`SOC_ADDR_IS_PSRAM(addr)) return (mem_pad_mode == 2'd1) ? TARGET_PSRAM : TARGET_SLVERR;
    if (`SOC_ADDR_IS_OPIPSRAM(addr))
      return (mem_pad_mode == 2'd2) ? TARGET_OPIPSRAM : TARGET_SLVERR;
    if (`SOC_ADDR_IS_FLASH(addr) || `SOC_ADDR_IS_XPI(addr)) return TARGET_XPI;
    if (`SOC_ADDR_IS_SPISD(addr)) return TARGET_RETIRED_SPISD;
    if (`SOC_ADDR_IS_APB4_SYSTEM(addr)) return TARGET_APB4_SYSTEM;
    if (`SOC_ADDR_IS_RAM(addr)) return TARGET_RAM;
    if (`SOC_ADDR_IS_APB4_PERIPH(addr)) return TARGET_CFG;
    return TARGET_DECERR;
  endfunction

  for (genvar master = 0; master < NumMasters; master++) begin : gen_master_ports
    assign m_awvalid[master]       = masters[master].awvalid;
    assign m_awaddr[master]        = masters[master].awaddr;
    assign m_awlen[master]         = masters[master].awlen;
    assign m_awsize[master]        = masters[master].awsize;
    assign m_awburst[master]       = masters[master].awburst;
    assign m_awlock[master]        = masters[master].awlock;
    assign m_awcache[master]       = masters[master].awcache;
    assign m_awprot[master]        = masters[master].awprot;
    assign m_awqos[master]         = masters[master].awqos;
    assign m_awregion[master]      = masters[master].awregion;
    assign m_awid[master]          = masters[master].awid;
    assign m_awuser[master]        = masters[master].awuser;
    assign masters[master].awready = m_awready[master];
    assign m_wvalid[master]        = masters[master].wvalid;
    assign m_wdata[master]         = masters[master].wdata;
    assign m_wstrb[master]         = masters[master].wstrb;
    assign m_wlast[master]         = masters[master].wlast;
    assign m_wuser[master]         = masters[master].wuser;
    assign masters[master].wready  = m_wready[master];
    assign masters[master].bid     = m_bid[master];
    assign masters[master].bresp   = m_bresp[master];
    assign masters[master].buser   = m_buser[master];
    assign masters[master].bvalid  = m_bvalid[master];
    assign m_bready[master]        = masters[master].bready;
    assign m_arvalid[master]       = masters[master].arvalid;
    assign m_araddr[master]        = masters[master].araddr;
    assign m_arlen[master]         = masters[master].arlen;
    assign m_arsize[master]        = masters[master].arsize;
    assign m_arburst[master]       = masters[master].arburst;
    assign m_arlock[master]        = masters[master].arlock;
    assign m_arcache[master]       = masters[master].arcache;
    assign m_arprot[master]        = masters[master].arprot;
    assign m_arqos[master]         = masters[master].arqos;
    assign m_arregion[master]      = masters[master].arregion;
    assign m_arid[master]          = masters[master].arid;
    assign m_aruser[master]        = masters[master].aruser;
    assign masters[master].arready = m_arready[master];
    assign masters[master].rid     = m_rid[master];
    assign masters[master].rdata   = m_rdata[master];
    assign masters[master].rresp   = m_rresp[master];
    assign masters[master].rlast   = m_rlast[master];
    assign masters[master].ruser   = m_ruser[master];
    assign masters[master].rvalid  = m_rvalid[master];
    assign m_rready[master]        = masters[master].rready;
  end

  for (genvar target = 0; target < NumTargets; target++) begin : gen_target_ports
    assign targets[target].awid     = t_awid[target];
    assign targets[target].awaddr   = t_awaddr[target];
    assign targets[target].awlen    = t_awlen[target];
    assign targets[target].awsize   = t_awsize[target];
    assign targets[target].awburst  = t_awburst[target];
    assign targets[target].awlock   = t_awlock[target];
    assign targets[target].awcache  = t_awcache[target];
    assign targets[target].awprot   = t_awprot[target];
    assign targets[target].awqos    = t_awqos[target];
    assign targets[target].awregion = t_awregion[target];
    assign targets[target].awuser   = t_awuser[target];
    assign targets[target].awvalid  = t_awvalid[target];
    assign t_awready[target]        = targets[target].awready;
    assign targets[target].wdata    = t_wdata[target];
    assign targets[target].wstrb    = t_wstrb[target];
    assign targets[target].wlast    = t_wlast[target];
    assign targets[target].wuser    = t_wuser[target];
    assign targets[target].wvalid   = t_wvalid[target];
    assign t_wready[target]         = targets[target].wready;
    assign t_bid[target]            = targets[target].bid;
    assign t_bresp[target]          = targets[target].bresp;
    assign t_buser[target]          = targets[target].buser;
    assign t_bvalid[target]         = targets[target].bvalid;
    assign targets[target].bready   = t_bready[target];
    assign targets[target].arid     = t_arid[target];
    assign targets[target].araddr   = t_araddr[target];
    assign targets[target].arlen    = t_arlen[target];
    assign targets[target].arsize   = t_arsize[target];
    assign targets[target].arburst  = t_arburst[target];
    assign targets[target].arlock   = t_arlock[target];
    assign targets[target].arcache  = t_arcache[target];
    assign targets[target].arprot   = t_arprot[target];
    assign targets[target].arqos    = t_arqos[target];
    assign targets[target].arregion = t_arregion[target];
    assign targets[target].aruser   = t_aruser[target];
    assign targets[target].arvalid  = t_arvalid[target];
    assign t_arready[target]        = targets[target].arready;
    assign t_rid[target]            = targets[target].rid;
    assign t_rdata[target]          = targets[target].rdata;
    assign t_rresp[target]          = targets[target].rresp;
    assign t_rlast[target]          = targets[target].rlast;
    assign t_ruser[target]          = targets[target].ruser;
    assign t_rvalid[target]         = targets[target].rvalid;
    assign targets[target].rready   = t_rready[target];

    round_robin_arbiter #(
        .CLIENTS(NumMasters)
    ) u_target_arbiter (
        .clk_i     (clk_i),
        .rst_n_i   (rst_n_i),
        .advance_i (s_target_advance[target]),
        .request_i (s_target_req[target]),
        .grant_o   (s_target_grant[target]),
        .selected_o(s_target_selected[target]),
        .valid_o   (s_target_grant_valid[target])
    );

`ifdef HAVE_SVA
    assert property (@(posedge clk_i) disable iff (!rst_n_i) $onehot0(s_target_grant[target]));
`endif
  end

  always_comb begin
    m_awready           = '0;
    m_wready            = '0;
    m_bid               = '0;
    m_bresp             = '0;
    m_buser             = '0;
    m_bvalid            = '0;
    m_arready           = '0;
    m_rid               = '0;
    m_rdata             = '0;
    m_rresp             = '0;
    m_rlast             = '0;
    m_ruser             = '0;
    m_rvalid            = '0;
    t_awvalid           = '0;
    t_awaddr            = '0;
    t_awlen             = '0;
    t_awsize            = '0;
    t_awburst           = '0;
    t_awlock            = '0;
    t_awcache           = '0;
    t_awprot            = '0;
    t_awqos             = '0;
    t_awregion          = '0;
    t_awid              = '0;
    t_awuser            = '0;
    t_wvalid            = '0;
    t_wdata             = '0;
    t_wstrb             = '0;
    t_wlast             = '0;
    t_wuser             = '0;
    t_bready            = '0;
    t_arvalid           = '0;
    t_araddr            = '0;
    t_arlen             = '0;
    t_arsize            = '0;
    t_arburst           = '0;
    t_arlock            = '0;
    t_arcache           = '0;
    t_arprot            = '0;
    t_arqos             = '0;
    t_arregion          = '0;
    t_arid              = '0;
    t_aruser            = '0;
    t_rready            = '0;
    s_target_req        = '0;
    s_target_advance    = '0;
    s_target_terminal   = '0;
    s_master_terminal   = '0;
    s_master_fault      = '0;
    s_master_fault_code = '0;

    for (int master = 0; master < NumMasters; master++) begin
      if (s_master_state[master] == MASTER_IDLE) begin
        m_arready[master] = (master != 1) || user_bus_enable_i;
        m_awready[master] = ((master != 1) || user_bus_enable_i) && !m_arvalid[master];
        if ((m_arvalid[master] && m_arready[master]) ||
            (m_awvalid[master] && m_awready[master])) begin
          s_target_req[s_capture_target[master]][master] = 1'b1;
        end
      end
      if (s_master_state[master] == MASTER_PENDING) begin
        s_target_req[s_master_target[master]][master] = 1'b1;
      end
    end

    for (int target = 0; target < NumTargets; target++) begin
      s_target_advance[target] = !s_target_valid[target] && s_target_grant_valid[target];
      if (s_target_valid[target]) begin
        automatic logic [MASTER_WIDTH-1:0] owner = s_target_owner[target];
        if (!s_target_addr_sent[target]) begin
          if (s_master_write[owner]) begin
            t_awvalid[target]  = 1'b1;
            t_awaddr[target]   = s_master_addr[owner];
            t_awlen[target]    = s_master_len[owner];
            t_awsize[target]   = s_master_size[owner];
            t_awburst[target]  = s_master_burst[owner];
            t_awlock[target]   = s_master_lock[owner];
            t_awcache[target]  = s_master_cache[owner];
            t_awprot[target]   = s_master_prot[owner];
            t_awqos[target]    = s_master_qos[owner];
            t_awregion[target] = s_master_region[owner];
            t_awid[target]     = s_master_id[owner];
            t_awuser[target]   = s_master_user[owner];
          end else begin
            t_arvalid[target]  = 1'b1;
            t_araddr[target]   = s_master_addr[owner];
            t_arlen[target]    = s_master_len[owner];
            t_arsize[target]   = s_master_size[owner];
            t_arburst[target]  = s_master_burst[owner];
            t_arlock[target]   = s_master_lock[owner];
            t_arcache[target]  = s_master_cache[owner];
            t_arprot[target]   = s_master_prot[owner];
            t_arqos[target]    = s_master_qos[owner];
            t_arregion[target] = s_master_region[owner];
            t_arid[target]     = s_master_id[owner];
            t_aruser[target]   = s_master_user[owner];
          end
        end else if (s_master_write[owner]) begin
          t_wvalid[target]          = m_wvalid[owner];
          t_wdata[target]           = m_wdata[owner];
          t_wstrb[target]           = m_wstrb[owner];
          t_wlast[target]           = m_wlast[owner];
          t_wuser[target]           = m_wuser[owner];
          m_wready[owner]           = t_wready[target];
          t_bready[target]          = m_bready[owner];
          m_bid[owner]              = t_bid[target];
          m_bresp[owner]            = t_bresp[target];
          m_buser[owner]            = t_buser[target];
          m_bvalid[owner]           = t_bvalid[target];
          s_target_terminal[target] = t_bvalid[target] && t_bready[target];
        end else begin
          t_rready[target]          = m_rready[owner];
          m_rid[owner]              = t_rid[target];
          m_rdata[owner]            = t_rdata[target];
          m_rresp[owner]            = t_rresp[target];
          m_rlast[owner]            = t_rlast[target];
          m_ruser[owner]            = t_ruser[target];
          m_rvalid[owner]           = t_rvalid[target];
          s_target_terminal[target] = t_rvalid[target] && t_rready[target] && t_rlast[target];
        end
        if (s_target_terminal[target]) begin
          s_master_terminal[owner] = 1'b1;
          if ((s_master_write[owner] && (t_bresp[target] != `AXI4_RESP_OKAY)) ||
              (!s_master_write[owner] && (t_rresp[target] != `AXI4_RESP_OKAY))) begin
            s_master_fault[owner] = 1'b1;
            s_master_fault_code[owner] =
                (TARGET_WIDTH'(target) == TARGET_DECERR) ? `RIB_RESP_DECERR :
                (TARGET_WIDTH'(target) == TARGET_SLVERR) ?
                (s_master_access_err[owner] ? `RIB_RESP_PROTERR : `RIB_RESP_BURSTERR) :
                `RIB_RESP_SLVERR;
          end
        end
      end
    end
  end

  always_comb begin
    for (int master = 0; master < NumMasters; master++) begin
      automatic logic read_req = m_arvalid[master];
      automatic logic write_req = !read_req && m_awvalid[master];
      automatic logic [31:0] addr = read_req ? m_araddr[master] : m_awaddr[master];
      automatic logic [7:0] len = read_req ? m_arlen[master] : m_awlen[master];
      automatic logic [2:0] size = read_req ? m_arsize[master] : m_awsize[master];
      automatic logic [1:0] burst = read_req ? m_arburst[master] : m_awburst[master];
      automatic logic lock = read_req ? m_arlock[master] : m_awlock[master];
      automatic logic [32:0] beat_bytes = 33'd1 << size;
      automatic logic [32:0] burst_bytes = beat_bytes * (33'(len) + 1'b1);
      automatic logic [32:0] wrap_base = {1'b0, addr} & ~(burst_bytes - 1'b1);
      automatic
      logic
      burst_legal =
          (burst == `AXI4_BURST_TYPE_FIXED) ||
          (burst == `AXI4_BURST_TYPE_INCR) ||
          ((burst == `AXI4_BURST_TYPE_WRAP) &&
           ((len == 8'd1) || (len == 8'd3) || (len == 8'd7) || (len == 8'd15)));
      if (burst == `AXI4_BURST_TYPE_FIXED) begin
        s_last_addr[master] = {1'b0, addr} + beat_bytes - 1'b1;
      end else if (burst == `AXI4_BURST_TYPE_WRAP) begin
        s_last_addr[master] = wrap_base + burst_bytes - 1'b1;
      end else begin
        s_last_addr[master] = {1'b0, addr} + burst_bytes - 1'b1;
      end
      s_protocol_legal[master] = (len <= 8'd15) &&
                                 burst_legal && !lock && (size <= 3'd2) &&
                                 ((addr & ((32'd1 << size) - 1'b1)) == '0) &&
                                 (s_last_addr[master][32] == 1'b0) &&
                                 (addr[31:12] == s_last_addr[master][31:12]) &&
                                 (decode_target(addr, mem_pad_mode_i) ==
          decode_target(s_last_addr[master][31:0], mem_pad_mode_i));
`ifdef MINI_PRODUCT
      s_access_allowed[master] = (master != 6) || read_req || (write_req && !
      `SOC_ADDR_IS_APB4_SYSCTRL(addr)
      && !
      `SOC_ADDR_IS_APB4_WDG(addr)
      && !
      `SOC_ADDR_IS_APB4_GPIO_ADMIN(addr)
      );
`else
      s_access_allowed[master] = (master != 1) || ((read_req &&
      `SOC_USER_ADDR_READABLE(addr)
      &&
      `SOC_USER_ADDR_READABLE(s_last_addr[master][31:0])
      ) || (write_req &&
      `SOC_USER_ADDR_WRITABLE(addr)
      &&
      `SOC_USER_ADDR_WRITABLE(s_last_addr[master][31:0])
      ));
`endif
      s_capture_target[master] = decode_target(addr, mem_pad_mode_i);
      if (!s_protocol_legal[master] ||
          ((s_capture_target[master] == TARGET_CFG ||
            s_capture_target[master] == TARGET_APB4_SYSTEM) && (len != 8'd0))) begin
        s_capture_target[master] = TARGET_SLVERR;
      end else if (!s_access_allowed[master]) begin
        s_capture_target[master] = TARGET_SLVERR;
      end
    end
  end

  assign user_bus_idle_o = s_master_state[1] == MASTER_IDLE;

  always_comb begin
    fault_valid_o    = 1'b0;
    fault_addr_o     = '0;
    fault_wstrb_o    = '0;
    fault_reserved_o = 1'b0;
    fault_access_o   = 1'b0;
    fault_master_o   = '0;
    fault_code_o     = `RIB_RESP_OK;
    for (int master = NumMasters - 1; master >= 0; master--) begin
      if (s_master_fault[master]) begin
        fault_valid_o    = 1'b1;
        fault_addr_o     = s_master_addr[master];
        fault_wstrb_o    = s_master_first_wstrb[master];
        fault_reserved_o = `SOC_ADDR_IS_RESERVED(s_master_addr[master]);
        fault_access_o   = s_master_access_err[master];
        fault_master_o   = 3'(master);
        fault_code_o     = s_master_fault_code[master];
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_master_state       <= '0;
      s_master_write       <= '0;
      s_master_target      <= '0;
      s_master_addr        <= '0;
      s_master_len         <= '0;
      s_master_size        <= '0;
      s_master_burst       <= '0;
      s_master_lock        <= '0;
      s_master_cache       <= '0;
      s_master_prot        <= '0;
      s_master_qos         <= '0;
      s_master_region      <= '0;
      s_master_id          <= '0;
      s_master_user        <= '0;
      s_master_access_err  <= '0;
      s_master_first_wstrb <= '0;
      s_target_valid       <= '0;
      s_target_addr_sent   <= '0;
      s_target_owner       <= '0;
    end else begin
      for (int master = 0; master < NumMasters; master++) begin
        if (s_master_state[master] == MASTER_IDLE &&
            ((m_arvalid[master] && m_arready[master]) ||
             (m_awvalid[master] && m_awready[master]))) begin
          automatic logic read_req = m_arvalid[master] && m_arready[master];
          s_master_state[master]       <= MASTER_PENDING;
          s_master_write[master]       <= !read_req;
          s_master_target[master]      <= s_capture_target[master];
          s_master_addr[master]        <= read_req ? m_araddr[master] : m_awaddr[master];
          s_master_len[master]         <= read_req ? m_arlen[master] : m_awlen[master];
          s_master_size[master]        <= read_req ? m_arsize[master] : m_awsize[master];
          s_master_burst[master]       <= read_req ? m_arburst[master] : m_awburst[master];
          s_master_lock[master]        <= read_req ? m_arlock[master] : m_awlock[master];
          s_master_cache[master]       <= read_req ? m_arcache[master] : m_awcache[master];
          s_master_prot[master]        <= read_req ? m_arprot[master] : m_awprot[master];
          s_master_qos[master]         <= read_req ? m_arqos[master] : m_awqos[master];
          s_master_region[master]      <= read_req ? m_arregion[master] : m_awregion[master];
          s_master_id[master]          <= read_req ? m_arid[master] : m_awid[master];
          s_master_user[master]        <= read_req ? m_aruser[master] : m_awuser[master];
          s_master_access_err[master]  <= !s_access_allowed[master];
          s_master_first_wstrb[master] <= '0;
        end
        if ((s_master_state[master] == MASTER_ACTIVE) && s_master_write[master] &&
            m_wvalid[master] && m_wready[master] && (s_master_first_wstrb[master] == '0)) begin
          s_master_first_wstrb[master] <= m_wstrb[master];
        end
        if (s_master_terminal[master]) s_master_state[master] <= MASTER_IDLE;
      end

      for (int target = 0; target < NumTargets; target++) begin
        if (!s_target_valid[target] && s_target_grant_valid[target]) begin
          s_target_valid[target]                    <= 1'b1;
          s_target_addr_sent[target]                <= 1'b0;
          s_target_owner[target]                    <= s_target_selected[target];
          s_master_state[s_target_selected[target]] <= MASTER_ACTIVE;
        end else if (s_target_valid[target] && !s_target_addr_sent[target]) begin
          automatic logic [MASTER_WIDTH-1:0] owner = s_target_owner[target];
          if ((s_master_write[owner] && t_awvalid[target] && t_awready[target]) ||
              (!s_master_write[owner] && t_arvalid[target] && t_arready[target])) begin
            s_target_addr_sent[target] <= 1'b1;
          end
        end
        if (s_target_terminal[target]) begin
          s_target_valid[target]     <= 1'b0;
          s_target_addr_sent[target] <= 1'b0;
        end
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      for (int master = 0; master < NumMasters; master++) s_perf_master_wait[master] <= '0;
      for (int target = 0; target < NumTargets; target++) s_perf_target_wait[target] <= '0;
    end else if (perf_clear_i) begin
      for (int master = 0; master < NumMasters; master++) s_perf_master_wait[master] <= '0;
      for (int target = 0; target < NumTargets; target++) s_perf_target_wait[target] <= '0;
    end else if (perf_enable_i) begin
      for (int master = 0; master < NumMasters; master++) begin
        if ((s_master_state[master] != MASTER_IDLE) && !s_master_terminal[master] &&
            !(&s_perf_master_wait[master])) begin
          s_perf_master_wait[master] <= s_perf_master_wait[master] + 1'b1;
        end
      end
      for (int target = 0; target < NumTargets; target++) begin
        if (s_target_valid[target] && !s_target_terminal[target] &&
            !(&s_perf_target_wait[target])) begin
          s_perf_target_wait[target] <= s_perf_target_wait[target] + 1'b1;
        end
      end
    end
  end

  assign perf_mgmt_wait_o        = s_perf_master_wait[0];
  assign perf_user_wait_o        = s_perf_master_wait[1];
  // SYSCTRL keeps one DMA aggregate counter for the general and SPI-SD engines.
  assign perf_dma_wait_o         = s_perf_master_wait[2] + s_perf_master_wait[5];
  assign perf_sdio0_wait_o       = s_perf_master_wait[3];
  assign perf_sdio1_wait_o       = s_perf_master_wait[4];
  assign perf_usb2_wait_o        = s_perf_master_wait[6];
  assign perf_apb4_periph_wait_o = s_perf_target_wait[TARGET_CFG];
  assign perf_apb4_system_wait_o = s_perf_target_wait[TARGET_APB4_SYSTEM];
  assign perf_sdram_wait_o       = s_perf_target_wait[TARGET_SDRAM];
  assign perf_psram_wait_o       = s_perf_target_wait[TARGET_PSRAM];
  assign perf_flash_wait_o       = s_perf_target_wait[TARGET_XPI];
  if (NumTargets > 9) begin : gen_opipsram_perf
    assign perf_opipsram_wait_o = s_perf_target_wait[TARGET_OPIPSRAM];
  end else begin : gen_no_opipsram_perf
    assign perf_opipsram_wait_o = '0;
  end

`ifndef SYNTHESIS
  initial begin
    if (((NumMasters != 7) && (NumMasters != 8)) || ((NumTargets != 9) && (NumTargets != 10))) begin
      $fatal(1, "axi4_interconnect: invalid topology dimensions");
    end
  end
`endif
endmodule
