// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "mmap_define.svh"

module axi4_data_crossbar #(
    parameter int unsigned                                  NumMasters          = 8,
    parameter int unsigned                                  NumTargets          = 6,
    parameter int unsigned                                  StarvationCycles    = 256,
    parameter logic        [NumMasters-1:0][NumTargets-2:0] ReadTargetMask      = '1,
    parameter logic        [NumMasters-1:0][NumTargets-2:0] WriteTargetMask     = '1,
    parameter logic        [NumMasters-1:0]                 AllowInstruction    = '1,
    parameter logic        [NumMasters-1:0]                 RequireNoncacheable = '0
) (
    // verilog_format: off -- preserve the data-plane contract columns
    input  logic                clk_i,
    input  logic                rst_n_i,
    input  logic                block_new_i,
    input  logic [NumMasters-1:0] master_block_i,
    input  logic                recovery_i,
    input  logic          [1:0] mem_pad_mode_i,
    input  logic         [31:0] ext_h_read_base_i,
    input  logic         [31:0] ext_h_read_limit_i,
    input  logic         [31:0] ext_h_write_base_i,
    input  logic         [31:0] ext_h_write_limit_i,
           axi4_if.slave        masters             [NumMasters],
           axi4_if.master       targets             [NumTargets],
    output logic                idle_o,
    output logic [NumMasters-1:0] master_idle_o,
    output logic          [7:0] outstanding_read_o,
    output logic          [7:0] outstanding_write_o,
    output logic                fault_valid_o,
    output logic          [2:0] fault_master_o,
    output logic          [2:0] fault_target_o,
    output logic         [31:0] fault_addr_o,
    output logic                fault_write_o,
    output logic          [3:0] fault_reason_o,
    output logic [NumMasters-1:0] monitor_master_read_accept_o,
    output logic [NumMasters-1:0] monitor_master_write_accept_o,
    output logic [NumMasters-1:0] monitor_master_read_beat_o,
    output logic [NumMasters-1:0] monitor_master_write_beat_o,
    output logic [NumMasters-1:0] monitor_master_wait_o,
    output logic [NumMasters-1:0] monitor_master_promotion_o,
    output logic [NumMasters-1:0][2:0] monitor_master_read_outstanding_o,
    output logic [NumMasters-1:0][2:0] monitor_master_write_outstanding_o,
    output logic [NumTargets-1:0] monitor_target_read_accept_o,
    output logic [NumTargets-1:0] monitor_target_write_accept_o,
    output logic [NumTargets-1:0] monitor_target_read_beat_o,
    output logic [NumTargets-1:0] monitor_target_write_beat_o,
    output logic [NumTargets-1:0] monitor_target_wait_o,
    output logic [NumTargets-1:0][2:0] monitor_target_read_outstanding_o,
    output logic [NumTargets-1:0][2:0] monitor_target_write_outstanding_o
    // verilog_format: on
);
  localparam int unsigned MasterWidth = $clog2(NumMasters);
  localparam int unsigned TargetWidth = $clog2(NumTargets);
  localparam int unsigned SourceIds = 8;
  localparam int unsigned RouteDepth = 2;
  localparam int unsigned CountWidth = 3;
  localparam int unsigned AgeWidth = $clog2(StarvationCycles + 1);

  localparam logic [TargetWidth-1:0] TargetSram = TargetWidth'(0);
  localparam logic [TargetWidth-1:0] TargetSdram = TargetWidth'(1);
  localparam logic [TargetWidth-1:0] TargetQpi = TargetWidth'(2);
  localparam logic [TargetWidth-1:0] TargetOpi = TargetWidth'(3);
  localparam logic [TargetWidth-1:0] TargetXpi = TargetWidth'(4);
  localparam logic [TargetWidth-1:0] TargetError = TargetWidth'(5);

  localparam logic [3:0] FaultUnmapped = 4'd1;
  localparam logic [3:0] FaultInactivePad = 4'd2;
  localparam logic [3:0] FaultAccess = 4'd3;
  localparam logic [3:0] FaultProtocol = 4'd4;

  typedef struct packed {
    logic [5:0]  id;
    logic [31:0] addr;
    logic [7:0]  len;
    logic [2:0]  size;
    logic [1:0]  burst;
    logic        lock;
    logic [3:0]  cache;
    logic [2:0]  prot;
    logic [3:0]  qos;
    logic [3:0]  region;
    logic        user;
  } addr_channel_t;

  typedef struct packed {
    logic [63:0] data;
    logic [7:0]  strb;
    logic        last;
    logic        user;
  } write_channel_t;

  typedef struct packed {
    logic [5:0] id;
    logic [1:0] resp;
    logic       user;
  } write_resp_t;

  typedef struct packed {
    logic [5:0]  id;
    logic [63:0] data;
    logic [1:0]  resp;
    logic        last;
    logic        user;
  } read_resp_t;

  addr_channel_t                                    m_aw                            [NumMasters];
  addr_channel_t                                    m_ar                            [NumMasters];
  write_channel_t                                   m_w                             [NumMasters];
  write_resp_t                                      m_b                             [NumMasters];
  read_resp_t                                       m_r                             [NumMasters];
  logic           [NumMasters-1:0]                  m_awvalid;
  logic           [NumMasters-1:0]                  m_awready;
  logic           [NumMasters-1:0]                  m_wvalid;
  logic           [NumMasters-1:0]                  m_wready;
  logic           [NumMasters-1:0]                  m_bvalid;
  logic           [NumMasters-1:0]                  m_bready;
  logic           [NumMasters-1:0]                  m_arvalid;
  logic           [NumMasters-1:0]                  m_arready;
  logic           [NumMasters-1:0]                  m_rvalid;
  logic           [NumMasters-1:0]                  m_rready;

  addr_channel_t                                    t_aw                            [NumTargets];
  addr_channel_t                                    t_ar                            [NumTargets];
  write_channel_t                                   t_w                             [NumTargets];
  write_resp_t                                      t_b                             [NumTargets];
  read_resp_t                                       t_r                             [NumTargets];
  logic           [NumTargets-1:0]                  t_awvalid;
  logic           [NumTargets-1:0]                  t_awready;
  logic           [NumTargets-1:0]                  t_wvalid;
  logic           [NumTargets-1:0]                  t_wready;
  logic           [NumTargets-1:0]                  t_bvalid;
  logic           [NumTargets-1:0]                  t_bready;
  logic           [NumTargets-1:0]                  t_arvalid;
  logic           [NumTargets-1:0]                  t_arready;
  logic           [NumTargets-1:0]                  t_rvalid;
  logic           [NumTargets-1:0]                  t_rready;

  logic           [NumTargets-1:0][ NumMasters-1:0] s_read_req;
  logic           [NumTargets-1:0][ NumMasters-1:0] s_write_req;
  logic           [NumTargets-1:0][ NumMasters-1:0] s_read_priority_req;
  logic           [NumTargets-1:0][ NumMasters-1:0] s_write_priority_req;
  logic           [NumTargets-1:0][ NumMasters-1:0] unused_read_grant;
  logic           [NumTargets-1:0][ NumMasters-1:0] unused_write_grant;
  logic           [NumTargets-1:0][MasterWidth-1:0] s_read_selected;
  logic           [NumTargets-1:0][MasterWidth-1:0] s_write_selected;
  logic           [NumTargets-1:0]                  s_read_grant_valid;
  logic           [NumTargets-1:0]                  s_write_grant_valid;
  logic           [NumTargets-1:0]                  s_read_capture;
  logic           [NumTargets-1:0]                  s_write_capture;

  logic           [NumMasters-1:0][ NumTargets-1:0] s_read_resp_req;
  logic           [NumMasters-1:0][ NumTargets-1:0] s_write_resp_req;
  logic           [NumMasters-1:0][ NumTargets-1:0] unused_read_resp_grant;
  logic           [NumMasters-1:0][ NumTargets-1:0] unused_write_resp_grant;
  logic           [NumMasters-1:0][TargetWidth-1:0] s_read_resp_selected;
  logic           [NumMasters-1:0][TargetWidth-1:0] s_write_resp_selected;
  logic           [NumMasters-1:0]                  s_read_resp_valid;
  logic           [NumMasters-1:0]                  s_write_resp_valid;
  logic           [NumMasters-1:0]                  s_read_terminal;
  logic           [NumMasters-1:0]                  s_write_terminal;

  logic           [NumTargets-1:0]                  s_target_write_owner_full;
  logic           [NumTargets-1:0]                  s_target_write_owner_empty;
  logic           [NumTargets-1:0]                  s_target_write_owner_push;
  logic           [NumTargets-1:0]                  s_target_write_owner_pop;
  logic           [NumTargets-1:0][MasterWidth-1:0] s_target_write_owner_data;
  logic           [NumTargets-1:0][            1:0] unused_target_write_owner_count;

  logic           [NumMasters-1:0][TargetWidth-1:0] s_read_decoded_target;
  logic           [NumMasters-1:0][TargetWidth-1:0] s_write_decoded_target;
  logic           [NumMasters-1:0][TargetWidth-1:0] s_read_routed_target;
  logic           [NumMasters-1:0][TargetWidth-1:0] s_write_routed_target;
  logic           [NumMasters-1:0][            3:0] s_read_fault_reason;
  logic           [NumMasters-1:0][            3:0] s_write_fault_reason;

  logic [NumMasters-1:0][CountWidth-1:0] s_master_read_count_d, s_master_read_count_q;
  logic [NumMasters-1:0][CountWidth-1:0] s_master_write_count_d, s_master_write_count_q;
  logic [NumTargets-1:0][CountWidth-1:0] s_target_read_count_d, s_target_read_count_q;
  logic [NumTargets-1:0][CountWidth-1:0] s_target_write_count_d, s_target_write_count_q;
  logic [NumMasters-1:0][SourceIds-1:0] s_read_id_busy_d, s_read_id_busy_q;
  logic [NumMasters-1:0][SourceIds-1:0] s_write_id_busy_d, s_write_id_busy_q;
  logic [NumTargets-1:0][NumMasters-1:0][AgeWidth-1:0] s_read_age_d, s_read_age_q;
  logic [NumTargets-1:0][NumMasters-1:0][AgeWidth-1:0] s_write_age_d, s_write_age_q;

  logic [NumMasters-1:0][RouteDepth-1:0][TargetWidth-1:0] s_write_route_d;
  logic [NumMasters-1:0][RouteDepth-1:0][TargetWidth-1:0] s_write_route_q;
  logic [NumMasters-1:0] s_route_read_ptr_d, s_route_read_ptr_q;
  logic [NumMasters-1:0] s_route_write_ptr_d, s_route_write_ptr_q;
  logic [NumMasters-1:0][1:0] s_route_count_d, s_route_count_q;
  logic [NumMasters-1:0]                  s_write_data_terminal;

  logic [NumMasters-1:0]                  s_read_accept;
  logic [NumMasters-1:0]                  s_write_accept;
  logic [NumMasters-1:0][TargetWidth-1:0] s_read_accept_target;
  logic [NumMasters-1:0][TargetWidth-1:0] s_write_accept_target;
  logic [NumMasters-1:0][            2:0] s_read_accept_id;
  logic [NumMasters-1:0][            2:0] s_write_accept_id;
  logic [NumMasters-1:0][            2:0] s_read_complete_id;
  logic [NumMasters-1:0][            2:0] s_write_complete_id;
  logic [NumTargets-1:0][            4:0] s_read_max_priority;
  logic [NumTargets-1:0][            4:0] s_write_max_priority;
  logic                                   s_fault_valid_d;
  logic [           2:0]                  s_fault_master_d;
  logic [           2:0]                  s_fault_target_d;
  logic [          31:0]                  s_fault_addr_d;
  logic                                   s_fault_write_d;
  logic [           3:0]                  s_fault_reason_d;

  function automatic logic [TargetWidth-1:0] decode_target(input logic [31:0] addr,
                                                           input logic [1:0] pad_mode);
    if (`SOC_ADDR_IS_SRAM(addr)) return TargetSram;
    if (`SOC_ADDR_IS_SDRAM(addr)) return TargetSdram;
    if (`SOC_ADDR_IS_PSRAM(addr)) return (pad_mode == 2'd1) ? TargetQpi : TargetError;
    if (`SOC_ADDR_IS_OPIPSRAM(addr)) return (pad_mode == 2'd2) ? TargetOpi : TargetError;
    if (`SOC_ADDR_IS_FLASH(addr) || `SOC_ADDR_IS_XPI(addr)) return TargetXpi;
    return TargetError;
  endfunction

  function automatic logic [3:0] decode_fault_reason(input logic [31:0] addr,
                                                     input logic [1:0] pad_mode);
    if (`SOC_ADDR_IS_PSRAM(addr) && (pad_mode != 2'd1)) return FaultInactivePad;
    if (`SOC_ADDR_IS_OPIPSRAM(addr) && (pad_mode != 2'd2)) return FaultInactivePad;
    if (!(
        `SOC_ADDR_IS_SRAM(addr)
        ||
        `SOC_ADDR_IS_SDRAM(addr)
        ||
        `SOC_ADDR_IS_PSRAM(addr)
        ||
        `SOC_ADDR_IS_OPIPSRAM(addr)
        ||
        `SOC_ADDR_IS_FLASH(addr)
        ||
        `SOC_ADDR_IS_XPI(addr)
        )) begin
      return FaultUnmapped;
    end
    return 4'd0;
  endfunction

  function automatic logic access_allowed(
      input int unsigned master, input logic [TargetWidth-1:0] target, input logic [31:0] addr,
      input logic write_access, input logic [2:0] prot, input logic [3:0] cache,
      input logic [31:0] ext_read_base, input logic [31:0] ext_read_limit,
      input logic [31:0] ext_write_base, input logic [31:0] ext_write_limit);
    if (target == TargetError) return 1'b1;
    if (write_access && !WriteTargetMask[master][target]) return 1'b0;
    if (!write_access && !ReadTargetMask[master][target]) return 1'b0;
    if (prot[2] && !AllowInstruction[master]) return 1'b0;
    if (RequireNoncacheable[master] && (cache != 4'd0)) return 1'b0;
    if ((master == 7) && write_access && ((addr < ext_write_base) || (addr > ext_write_limit)))
      return 1'b0;
    if ((master == 7) && !write_access && ((addr < ext_read_base) || (addr > ext_read_limit)))
      return 1'b0;
    return 1'b1;
  endfunction

  function automatic logic burst_legal(input logic [31:0] addr, input logic [7:0] len,
                                       input logic [2:0] size, input logic [1:0] burst,
                                       input logic lock);
    logic [32:0] beat_bytes;
    logic [32:0] burst_bytes;
    logic [32:0] last_addr;
    logic [32:0] window_limit;
    beat_bytes = 33'd1 << size;
    burst_bytes = beat_bytes * ({25'd0, len} + 1'b1);
    last_addr = (burst == 2'b00) ?
        ({1'b0, addr} + beat_bytes - 1'b1) :
        ({1'b0, addr} + burst_bytes - 1'b1);
    window_limit = {1'b0, addr[31:12], 12'd0} + 33'd4096;
    return !lock && (size <= 3'd3) &&
           ((burst == 2'b00) || (burst == 2'b01) ||
            ((burst == 2'b10) &&
             ((len == 8'd1) || (len == 8'd3) || (len == 8'd7) || (len == 8'd15)))) &&
           (last_addr < window_limit);
  endfunction

  function automatic logic [CountWidth-1:0] master_read_limit(input int unsigned master);
    if ((master <= 2) || (master == 7)) return CountWidth'(4);
    if ((master == 3) || (master == 4)) return CountWidth'(2);
    if (master == 5) return CountWidth'(1);
    return '0;
  endfunction

  function automatic logic [CountWidth-1:0] master_write_limit(input int unsigned master);
    if ((master == 1) || (master == 2) || (master == 7)) return CountWidth'(2);
    if ((master >= 3) && (master <= 5)) return CountWidth'(1);
    return '0;
  endfunction

  function automatic logic [CountWidth-1:0] target_read_limit(input logic [TargetWidth-1:0] target);
    if ((target == TargetSram) || (target == TargetSdram)) return CountWidth'(4);
    return CountWidth'(1);
  endfunction

  function automatic logic [CountWidth-1:0] target_write_limit(
      input logic [TargetWidth-1:0] target);
    if ((target == TargetSram) || (target == TargetSdram)) return CountWidth'(2);
    return CountWidth'(1);
  endfunction

  function automatic logic [4:0] master_priority(input int unsigned master,
                                                 input logic [3:0] request_qos, input logic aged,
                                                 input logic recovery);
    logic [3:0] base_priority;
    unique case (master)
      0, 1:    base_priority = 4'd12;
      3, 4:    base_priority = 4'd10;
      2, 7:    base_priority = 4'd8;
      5:       base_priority = recovery ? 4'd15 : 4'd2;
      default: base_priority = 4'd0;
    endcase
    if (recovery && (master == 5)) return 5'd31;
    if (aged) return 5'd16;
    return {1'b0, (request_qos > base_priority) ? request_qos : base_priority};
  endfunction

  for (genvar master = 0; master < NumMasters; master++) begin : gen_master_ports
    assign m_aw[master] = {
      masters[master].awid,
      masters[master].awaddr,
      masters[master].awlen,
      masters[master].awsize,
      masters[master].awburst,
      masters[master].awlock,
      masters[master].awcache,
      masters[master].awprot,
      masters[master].awqos,
      masters[master].awregion,
      masters[master].awuser
    };
    assign m_awvalid[master] = masters[master].awvalid;
    assign masters[master].awready = m_awready[master];
    assign m_w[master] = {
      masters[master].wdata, masters[master].wstrb, masters[master].wlast, masters[master].wuser
    };
    assign m_wvalid[master] = masters[master].wvalid;
    assign masters[master].wready = m_wready[master];
    assign masters[master].bid = m_b[master].id;
    assign masters[master].bresp = m_b[master].resp;
    assign masters[master].buser = m_b[master].user;
    assign masters[master].bvalid = m_bvalid[master];
    assign m_bready[master] = masters[master].bready;
    assign m_ar[master] = {
      masters[master].arid,
      masters[master].araddr,
      masters[master].arlen,
      masters[master].arsize,
      masters[master].arburst,
      masters[master].arlock,
      masters[master].arcache,
      masters[master].arprot,
      masters[master].arqos,
      masters[master].arregion,
      masters[master].aruser
    };
    assign m_arvalid[master] = masters[master].arvalid;
    assign masters[master].arready = m_arready[master];
    assign masters[master].rid = m_r[master].id;
    assign masters[master].rdata = m_r[master].data;
    assign masters[master].rresp = m_r[master].resp;
    assign masters[master].rlast = m_r[master].last;
    assign masters[master].ruser = m_r[master].user;
    assign masters[master].rvalid = m_rvalid[master];
    assign m_rready[master] = masters[master].rready;

    round_robin_arbiter #(
        .CLIENTS(NumTargets)
    ) u_read_response_arbiter (
        .clk_i     (clk_i),
        .rst_n_i   (rst_n_i),
        .advance_i (s_read_terminal[master]),
        .request_i (s_read_resp_req[master]),
        .grant_o   (unused_read_resp_grant[master]),
        .selected_o(s_read_resp_selected[master]),
        .valid_o   (s_read_resp_valid[master])
    );
    round_robin_arbiter #(
        .CLIENTS(NumTargets)
    ) u_write_response_arbiter (
        .clk_i     (clk_i),
        .rst_n_i   (rst_n_i),
        .advance_i (s_write_terminal[master]),
        .request_i (s_write_resp_req[master]),
        .grant_o   (unused_write_resp_grant[master]),
        .selected_o(s_write_resp_selected[master]),
        .valid_o   (s_write_resp_valid[master])
    );
  end

  for (genvar target = 0; target < NumTargets; target++) begin : gen_target_ports
    assign targets[target].awid = t_aw[target].id;
    assign targets[target].awaddr = t_aw[target].addr;
    assign targets[target].awlen = t_aw[target].len;
    assign targets[target].awsize = t_aw[target].size;
    assign targets[target].awburst = t_aw[target].burst;
    assign targets[target].awlock = t_aw[target].lock;
    assign targets[target].awcache = t_aw[target].cache;
    assign targets[target].awprot = t_aw[target].prot;
    assign targets[target].awqos = t_aw[target].qos;
    assign targets[target].awregion = t_aw[target].region;
    assign targets[target].awuser = t_aw[target].user;
    assign targets[target].awvalid = t_awvalid[target];
    assign t_awready[target] = targets[target].awready;
    assign targets[target].wdata = t_w[target].data;
    assign targets[target].wstrb = t_w[target].strb;
    assign targets[target].wlast = t_w[target].last;
    assign targets[target].wuser = t_w[target].user;
    assign targets[target].wvalid = t_wvalid[target];
    assign t_wready[target] = targets[target].wready;
    assign t_b[target] = {targets[target].bid, targets[target].bresp, targets[target].buser};
    assign t_bvalid[target] = targets[target].bvalid;
    assign targets[target].bready = t_bready[target];
    assign targets[target].arid = t_ar[target].id;
    assign targets[target].araddr = t_ar[target].addr;
    assign targets[target].arlen = t_ar[target].len;
    assign targets[target].arsize = t_ar[target].size;
    assign targets[target].arburst = t_ar[target].burst;
    assign targets[target].arlock = t_ar[target].lock;
    assign targets[target].arcache = t_ar[target].cache;
    assign targets[target].arprot = t_ar[target].prot;
    assign targets[target].arqos = t_ar[target].qos;
    assign targets[target].arregion = t_ar[target].region;
    assign targets[target].aruser = t_ar[target].user;
    assign targets[target].arvalid = t_arvalid[target];
    assign t_arready[target] = targets[target].arready;
    assign t_r[target] = {
      targets[target].rid,
      targets[target].rdata,
      targets[target].rresp,
      targets[target].rlast,
      targets[target].ruser
    };
    assign t_rvalid[target] = targets[target].rvalid;
    assign targets[target].rready = t_rready[target];

    round_robin_arbiter #(
        .CLIENTS(NumMasters)
    ) u_read_address_arbiter (
        .clk_i     (clk_i),
        .rst_n_i   (rst_n_i),
        .advance_i (s_read_capture[target]),
        .request_i (s_read_priority_req[target]),
        .grant_o   (unused_read_grant[target]),
        .selected_o(s_read_selected[target]),
        .valid_o   (s_read_grant_valid[target])
    );
    round_robin_arbiter #(
        .CLIENTS(NumMasters)
    ) u_write_address_arbiter (
        .clk_i     (clk_i),
        .rst_n_i   (rst_n_i),
        .advance_i (s_write_capture[target]),
        .request_i (s_write_priority_req[target]),
        .grant_o   (unused_write_grant[target]),
        .selected_o(s_write_selected[target]),
        .valid_o   (s_write_grant_valid[target])
    );

    fifo #(
        .DATA_WIDTH  (MasterWidth),
        .BUFFER_DEPTH(RouteDepth)
    ) u_write_owner_fifo (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .flush_i(1'b0),
        .push_i (s_target_write_owner_push[target]),
        .full_o (s_target_write_owner_full[target]),
        .dat_i  (s_write_selected[target]),
        .pop_i  (s_target_write_owner_pop[target]),
        .empty_o(s_target_write_owner_empty[target]),
        .dat_o  (s_target_write_owner_data[target]),
        .cnt_o  (unused_target_write_owner_count[target])
    );
  end


  always_comb begin
    s_read_req             = '0;
    s_write_req            = '0;
    s_read_decoded_target  = '0;
    s_write_decoded_target = '0;
    s_read_routed_target   = '0;
    s_write_routed_target  = '0;
    s_read_fault_reason    = '0;
    s_write_fault_reason   = '0;
    for (int master = 0; master < NumMasters; master++) begin
      s_read_decoded_target[master]  = decode_target(m_ar[master].addr, mem_pad_mode_i);
      s_write_decoded_target[master] = decode_target(m_aw[master].addr, mem_pad_mode_i);
      s_read_fault_reason[master]    = decode_fault_reason(m_ar[master].addr, mem_pad_mode_i);
      s_write_fault_reason[master]   = decode_fault_reason(m_aw[master].addr, mem_pad_mode_i);
      if ((s_read_fault_reason[master] == 4'd0) && !access_allowed(
              master,
              s_read_decoded_target[master],
              m_ar[master].addr,
              1'b0,
              m_ar[master].prot,
              m_ar[master].cache,
              ext_h_read_base_i,
              ext_h_read_limit_i,
              ext_h_write_base_i,
              ext_h_write_limit_i
          )) begin
        s_read_fault_reason[master] = FaultAccess;
      end else if (!burst_legal(
              m_ar[master].addr,
              m_ar[master].len,
              m_ar[master].size,
              m_ar[master].burst,
              m_ar[master].lock
          )) begin
        s_read_fault_reason[master] = FaultProtocol;
      end
      if ((s_write_fault_reason[master] == 4'd0) && !access_allowed(
              master,
              s_write_decoded_target[master],
              m_aw[master].addr,
              1'b1,
              m_aw[master].prot,
              m_aw[master].cache,
              ext_h_read_base_i,
              ext_h_read_limit_i,
              ext_h_write_base_i,
              ext_h_write_limit_i
          )) begin
        s_write_fault_reason[master] = FaultAccess;
      end else if (!burst_legal(
              m_aw[master].addr,
              m_aw[master].len,
              m_aw[master].size,
              m_aw[master].burst,
              m_aw[master].lock
          )) begin
        s_write_fault_reason[master] = FaultProtocol;
      end
      s_read_routed_target[master] = (s_read_fault_reason[master] == 4'd0) ?
          s_read_decoded_target[master] : TargetError;
      s_write_routed_target[master] = (s_write_fault_reason[master] == 4'd0) ?
          s_write_decoded_target[master] : TargetError;
      if (!block_new_i && !master_block_i[master] && m_arvalid[master] &&
          (s_target_read_count_q[s_read_routed_target[master]] <
           target_read_limit(
              s_read_routed_target[master]
          )) && (s_master_read_count_q[master] <
                 ((s_read_fault_reason[master] != 4'd0) ? CountWidth'(1) : master_read_limit(
              master
          ))) && !s_read_id_busy_q[master][m_ar[master].id[2:0]]) begin
        s_read_req[s_read_routed_target[master]][master] = 1'b1;
      end
      if (!block_new_i && !master_block_i[master] && m_awvalid[master] &&
          !s_target_write_owner_full[s_write_routed_target[master]] &&
          (s_target_write_count_q[s_write_routed_target[master]] <
           target_write_limit(
              s_write_routed_target[master]
          )) && (s_master_write_count_q[master] <
                 ((s_write_fault_reason[master] != 4'd0) ? CountWidth'(1) : master_write_limit(
              master
          ))) && (s_route_count_q[master] < 2'(RouteDepth)) &&
              !s_write_id_busy_q[master][m_aw[master].id[2:0]]) begin
        s_write_req[s_write_routed_target[master]][master] = 1'b1;
      end
    end
  end

  always_comb begin
    s_read_priority_req  = '0;
    s_write_priority_req = '0;
    s_read_max_priority  = '0;
    s_write_max_priority = '0;
    for (int target = 0; target < NumTargets; target++) begin
      for (int master = 0; master < NumMasters; master++) begin
        if (s_read_req[target][master] && (master_priority(
                master,
                m_ar[master].qos,
                s_read_age_q[target][master] == AgeWidth'(StarvationCycles),
                recovery_i
            ) > s_read_max_priority[target])) begin
          s_read_max_priority[target] = master_priority(
            master,
            m_ar[master].qos,
            s_read_age_q[target][master] == AgeWidth'(StarvationCycles),
            recovery_i
          );
        end
        if (s_write_req[target][master] && (master_priority(
                master,
                m_aw[master].qos,
                s_write_age_q[target][master] == AgeWidth'(StarvationCycles),
                recovery_i
            ) > s_write_max_priority[target])) begin
          s_write_max_priority[target] = master_priority(
            master,
            m_aw[master].qos,
            s_write_age_q[target][master] == AgeWidth'(StarvationCycles),
            recovery_i
          );
        end
      end
      for (int master = 0; master < NumMasters; master++) begin
        s_read_priority_req[target][master] = s_read_req[target][master] && (master_priority(
          master,
          m_ar[master].qos,
          s_read_age_q[target][master] == AgeWidth'(StarvationCycles),
          recovery_i
        ) == s_read_max_priority[target]);
        s_write_priority_req[target][master] = s_write_req[target][master] && (master_priority(
          master,
          m_aw[master].qos,
          s_write_age_q[target][master] == AgeWidth'(StarvationCycles),
          recovery_i
        ) == s_write_max_priority[target]);
      end
    end
  end

  always_comb begin
    m_arready            = '0;
    t_ar                 = '{default: '0};
    t_arvalid            = '0;
    s_read_capture       = '0;
    s_read_accept        = '0;
    s_read_accept_target = '0;
    s_read_accept_id     = '0;
    for (int target = 0; target < NumTargets; target++) begin
      if (s_read_grant_valid[target]) begin
        automatic logic [MasterWidth-1:0] owner = s_read_selected[target];
        t_ar[target]           = m_ar[owner];
        t_arvalid[target]      = m_arvalid[owner];
        m_arready[owner]       = t_arready[target];
        s_read_capture[target] = t_arvalid[target] && t_arready[target];
        if (s_read_capture[target]) begin
          s_read_accept[owner]        = 1'b1;
          s_read_accept_target[owner] = TargetWidth'(target);
          s_read_accept_id[owner]     = m_ar[owner].id[2:0];
        end
      end
    end
  end

  always_comb begin
    m_awready                 = '0;
    t_aw                      = '{default: '0};
    t_awvalid                 = '0;
    s_write_capture           = '0;
    s_target_write_owner_push = '0;
    s_write_accept            = '0;
    s_write_accept_target     = '0;
    s_write_accept_id         = '0;
    for (int target = 0; target < NumTargets; target++) begin
      if (s_write_grant_valid[target]) begin
        automatic logic [MasterWidth-1:0] owner = s_write_selected[target];
        t_aw[target]                      = m_aw[owner];
        t_awvalid[target]                 = m_awvalid[owner];
        m_awready[owner]                  = t_awready[target];
        s_write_capture[target]           = t_awvalid[target] && t_awready[target];
        s_target_write_owner_push[target] = s_write_capture[target];
        if (s_write_capture[target]) begin
          s_write_accept[owner]        = 1'b1;
          s_write_accept_target[owner] = TargetWidth'(target);
          s_write_accept_id[owner]     = m_aw[owner].id[2:0];
        end
      end
    end
  end

  always_comb begin
    m_wready                 = '0;
    t_w                      = '{default: '0};
    t_wvalid                 = '0;
    s_write_data_terminal    = '0;
    s_target_write_owner_pop = '0;
    for (int target = 0; target < NumTargets; target++) begin
      if (!s_target_write_owner_empty[target]) begin
        automatic logic [MasterWidth-1:0] master = s_target_write_owner_data[target];
        if ((s_route_count_q[master] != 2'd0) &&
            (s_write_route_q[master][s_route_read_ptr_q[master]] == TargetWidth'(target))) begin
          t_w[target] = m_w[master];
          t_wvalid[target] = m_wvalid[master];
          m_wready[master] = t_wready[target];
          s_write_data_terminal[master] = t_wvalid[target] && t_wready[target] && t_w[target].last;
          s_target_write_owner_pop[target] = s_write_data_terminal[master];
        end
      end
    end
  end

  always_comb begin
    s_read_resp_req  = '0;
    s_write_resp_req = '0;
    for (int target = 0; target < NumTargets; target++) begin
      if (t_rvalid[target]) begin
        s_read_resp_req[t_r[target].id[5:3]][target] = 1'b1;
      end
      if (t_bvalid[target]) begin
        s_write_resp_req[t_b[target].id[5:3]][target] = 1'b1;
      end
    end
  end

  always_comb begin
    m_r                 = '{default: '0};
    m_rvalid            = '0;
    t_rready            = '0;
    s_read_terminal     = '0;
    s_read_complete_id  = '0;
    m_b                 = '{default: '0};
    m_bvalid            = '0;
    t_bready            = '0;
    s_write_terminal    = '0;
    s_write_complete_id = '0;
    for (int master = 0; master < NumMasters; master++) begin
      if (s_read_resp_valid[master]) begin
        automatic logic [TargetWidth-1:0] target = s_read_resp_selected[master];
        m_r[master]                = t_r[target];
        m_rvalid[master]           = t_rvalid[target];
        t_rready[target]           = m_rready[master];
        s_read_terminal[master]    = m_rvalid[master] && m_rready[master] && m_r[master].last;
        s_read_complete_id[master] = m_r[master].id[2:0];
      end
      if (s_write_resp_valid[master]) begin
        automatic logic [TargetWidth-1:0] target = s_write_resp_selected[master];
        m_b[master]                 = t_b[target];
        m_bvalid[master]            = t_bvalid[target];
        t_bready[target]            = m_bready[master];
        s_write_terminal[master]    = m_bvalid[master] && m_bready[master];
        s_write_complete_id[master] = m_b[master].id[2:0];
      end
    end
  end

  always_comb begin
    s_master_read_count_d  = s_master_read_count_q;
    s_master_write_count_d = s_master_write_count_q;
    s_target_read_count_d  = s_target_read_count_q;
    s_target_write_count_d = s_target_write_count_q;
    s_read_id_busy_d       = s_read_id_busy_q;
    s_write_id_busy_d      = s_write_id_busy_q;
    for (int master = 0; master < NumMasters; master++) begin
      if (s_read_terminal[master]) begin
        s_master_read_count_d[master] = s_master_read_count_d[master] - 1'b1;
        s_target_read_count_d[s_read_resp_selected[master]]  =
            s_target_read_count_d[s_read_resp_selected[master]] - 1'b1;
        s_read_id_busy_d[master][s_read_complete_id[master]] = 1'b0;
      end
      if (s_write_terminal[master]) begin
        s_master_write_count_d[master] = s_master_write_count_d[master] - 1'b1;
        s_target_write_count_d[s_write_resp_selected[master]] =
            s_target_write_count_d[s_write_resp_selected[master]] - 1'b1;
        s_write_id_busy_d[master][s_write_complete_id[master]] = 1'b0;
      end
      if (s_read_accept[master]) begin
        s_master_read_count_d[master] = s_master_read_count_d[master] + 1'b1;
        s_target_read_count_d[s_read_accept_target[master]] =
            s_target_read_count_d[s_read_accept_target[master]] + 1'b1;
        s_read_id_busy_d[master][s_read_accept_id[master]] = 1'b1;
      end
      if (s_write_accept[master]) begin
        s_master_write_count_d[master] = s_master_write_count_d[master] + 1'b1;
        s_target_write_count_d[s_write_accept_target[master]] =
            s_target_write_count_d[s_write_accept_target[master]] + 1'b1;
        s_write_id_busy_d[master][s_write_accept_id[master]] = 1'b1;
      end
    end
  end

  always_comb begin
    s_write_route_d     = s_write_route_q;
    s_route_read_ptr_d  = s_route_read_ptr_q;
    s_route_write_ptr_d = s_route_write_ptr_q;
    s_route_count_d     = s_route_count_q;
    for (int master = 0; master < NumMasters; master++) begin
      unique case ({
        s_write_accept[master], s_write_data_terminal[master]
      })
        2'b10:   s_route_count_d[master] = s_route_count_q[master] + 1'b1;
        2'b01:   s_route_count_d[master] = s_route_count_q[master] - 1'b1;
        default: s_route_count_d[master] = s_route_count_q[master];
      endcase
      if (s_write_accept[master]) begin
        s_write_route_d[master][s_route_write_ptr_q[master]] = s_write_accept_target[master];
        s_route_write_ptr_d[master]                          = ~s_route_write_ptr_q[master];
      end
      if (s_write_data_terminal[master]) begin
        s_route_read_ptr_d[master] = ~s_route_read_ptr_q[master];
      end
    end
  end

  always_comb begin
    s_read_age_d  = s_read_age_q;
    s_write_age_d = s_write_age_q;
    for (int target = 0; target < NumTargets; target++) begin
      for (int master = 0; master < NumMasters; master++) begin
        if (!s_read_req[target][master] ||
            (s_read_capture[target] && (s_read_selected[target] == MasterWidth'(master)))) begin
          s_read_age_d[target][master] = '0;
        end else if (s_read_age_q[target][master] < AgeWidth'(StarvationCycles)) begin
          s_read_age_d[target][master] = s_read_age_q[target][master] + 1'b1;
        end
        if (!s_write_req[target][master] ||
            (s_write_capture[target] && (s_write_selected[target] == MasterWidth'(master)))) begin
          s_write_age_d[target][master] = '0;
        end else if (s_write_age_q[target][master] < AgeWidth'(StarvationCycles)) begin
          s_write_age_d[target][master] = s_write_age_q[target][master] + 1'b1;
        end
      end
    end
  end

  always_comb begin
    s_fault_valid_d  = 1'b0;
    s_fault_master_d = '0;
    s_fault_target_d = '0;
    s_fault_addr_d   = '0;
    s_fault_write_d  = 1'b0;
    s_fault_reason_d = '0;
    for (int master = 0; master < NumMasters; master++) begin
      if (!s_fault_valid_d && s_read_accept[master] && (s_read_fault_reason[master] != 4'd0)) begin
        s_fault_valid_d  = 1'b1;
        s_fault_master_d = 3'(master);
        s_fault_target_d = 3'(s_read_decoded_target[master]);
        s_fault_addr_d   = m_ar[master].addr;
        s_fault_reason_d = s_read_fault_reason[master];
      end
      if (!s_fault_valid_d && s_write_accept[master] &&
          (s_write_fault_reason[master] != 4'd0)) begin
        s_fault_valid_d  = 1'b1;
        s_fault_master_d = 3'(master);
        s_fault_target_d = 3'(s_write_decoded_target[master]);
        s_fault_addr_d   = m_aw[master].addr;
        s_fault_write_d  = 1'b1;
        s_fault_reason_d = s_write_fault_reason[master];
      end
    end
  end

  always_comb begin
    outstanding_read_o  = '0;
    outstanding_write_o = '0;
    for (int master = 0; master < NumMasters; master++) begin
      outstanding_read_o  = outstanding_read_o + 8'(s_master_read_count_q[master]);
      outstanding_write_o = outstanding_write_o + 8'(s_master_write_count_q[master]);
    end
  end

  assign idle_o = (outstanding_read_o == 8'd0) && (outstanding_write_o == 8'd0) &&
                  !(|s_route_count_q);
  for (genvar master = 0; master < NumMasters; master++) begin : gen_master_idle
    assign master_idle_o[master] = (s_master_read_count_q[master] == '0) &&
        (s_master_write_count_q[master] == '0) && (s_route_count_q[master] == '0) &&
        !m_arvalid[master] && !m_awvalid[master] && !m_wvalid[master];
    assign monitor_master_read_accept_o[master] = s_read_accept[master];
    assign monitor_master_write_accept_o[master] = s_write_accept[master];
    assign monitor_master_read_beat_o[master] = m_rvalid[master] && m_rready[master];
    assign monitor_master_write_beat_o[master] = m_wvalid[master] && m_wready[master];
    assign monitor_master_wait_o[master] =
        (m_arvalid[master] && !m_arready[master]) ||
        (m_awvalid[master] && !m_awready[master]) ||
        (m_wvalid[master] && !m_wready[master]);
    assign monitor_master_promotion_o[master] =
        (s_read_accept[master] &&
         (s_read_age_q[s_read_accept_target[master]][master] == AgeWidth'(StarvationCycles))) ||
        (s_write_accept[master] &&
         (s_write_age_q[s_write_accept_target[master]][master] == AgeWidth'(StarvationCycles)));
    assign monitor_master_read_outstanding_o[master] = s_master_read_count_q[master];
    assign monitor_master_write_outstanding_o[master] = s_master_write_count_q[master];
  end
  for (genvar target = 0; target < NumTargets; target++) begin : gen_target_monitor
    assign monitor_target_read_accept_o[target] = s_read_capture[target];
    assign monitor_target_write_accept_o[target] = s_write_capture[target];
    assign monitor_target_read_beat_o[target] = t_rvalid[target] && t_rready[target];
    assign monitor_target_write_beat_o[target] = t_wvalid[target] && t_wready[target];
    assign monitor_target_wait_o[target] =
        (t_arvalid[target] && !t_arready[target]) ||
        (t_awvalid[target] && !t_awready[target]) ||
        (t_wvalid[target] && !t_wready[target]) ||
        (t_rvalid[target] && !t_rready[target]) ||
        (t_bvalid[target] && !t_bready[target]);
    assign monitor_target_read_outstanding_o[target] = s_target_read_count_q[target];
    assign monitor_target_write_outstanding_o[target] = s_target_write_count_q[target];
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_master_read_count_q  <= '0;
      s_master_write_count_q <= '0;
      s_target_read_count_q  <= '0;
      s_target_write_count_q <= '0;
      s_read_id_busy_q       <= '0;
      s_write_id_busy_q      <= '0;
      s_write_route_q        <= '0;
      s_route_read_ptr_q     <= '0;
      s_route_write_ptr_q    <= '0;
      s_route_count_q        <= '0;
      s_read_age_q           <= '0;
      s_write_age_q          <= '0;
      fault_valid_o          <= 1'b0;
      fault_master_o         <= '0;
      fault_target_o         <= '0;
      fault_addr_o           <= '0;
      fault_write_o          <= 1'b0;
      fault_reason_o         <= '0;
    end else begin
      s_master_read_count_q  <= s_master_read_count_d;
      s_master_write_count_q <= s_master_write_count_d;
      s_target_read_count_q  <= s_target_read_count_d;
      s_target_write_count_q <= s_target_write_count_d;
      s_read_id_busy_q       <= s_read_id_busy_d;
      s_write_id_busy_q      <= s_write_id_busy_d;
      s_write_route_q        <= s_write_route_d;
      s_route_read_ptr_q     <= s_route_read_ptr_d;
      s_route_write_ptr_q    <= s_route_write_ptr_d;
      s_route_count_q        <= s_route_count_d;
      s_read_age_q           <= s_read_age_d;
      s_write_age_q          <= s_write_age_d;
      fault_valid_o          <= s_fault_valid_d;
      fault_master_o         <= s_fault_master_d;
      fault_target_o         <= s_fault_target_d;
      fault_addr_o           <= s_fault_addr_d;
      fault_write_o          <= s_fault_write_d;
      fault_reason_o         <= s_fault_reason_d;
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (rst_n_i && $test$plusargs("trace_mgmt")) begin
      if (m_arvalid[5] && m_arready[5]) begin
        $display("DATA_M5_AR addr=%08x target=%0d", m_ar[5].addr, s_read_routed_target[5]);
      end
      if (m_rvalid[5] && m_rready[5] && m_r[5].last) begin
        $display("DATA_M5_R resp=%0d data=%016x", m_r[5].resp, m_r[5].data);
      end
    end
  end

  initial begin
    if ((NumMasters != 8) || (NumTargets != 6) || (StarvationCycles < 2) ||
        ((StarvationCycles & (StarvationCycles - 1)) != 0)) begin
      $fatal(1, "axi4_data_crossbar: invalid product topology or aging interval");
    end
  end
`endif
endmodule
