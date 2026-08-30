// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "mmap_define.svh"

module axi4_data_crossbar #(
    parameter int unsigned NumMasters = 8,
    parameter int unsigned NumTargets = 6
) (
    input  logic                clk_i,
    input  logic                rst_n_i,
    input  logic                block_new_i,
    input  logic          [1:0] mem_pad_mode_i,
           axi4_if.slave        masters       [NumMasters],
           axi4_if.master       targets       [NumTargets],
    output logic                idle_o
);
  localparam int unsigned MasterWidth = $clog2(NumMasters);
  localparam int unsigned TargetWidth = $clog2(NumTargets);
  localparam logic [TargetWidth-1:0] TargetSram = TargetWidth'(0);
  localparam logic [TargetWidth-1:0] TargetSdram = TargetWidth'(1);
  localparam logic [TargetWidth-1:0] TargetQpi = TargetWidth'(2);
  localparam logic [TargetWidth-1:0] TargetOpi = TargetWidth'(3);
  localparam logic [TargetWidth-1:0] TargetXpi = TargetWidth'(4);
  localparam logic [TargetWidth-1:0] TargetError = TargetWidth'(5);

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

  addr_channel_t                                    m_aw                  [NumMasters];
  addr_channel_t                                    m_ar                  [NumMasters];
  write_channel_t                                   m_w                   [NumMasters];
  write_resp_t                                      m_b                   [NumMasters];
  read_resp_t                                       m_r                   [NumMasters];
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

  addr_channel_t                                    t_aw                  [NumTargets];
  addr_channel_t                                    t_ar                  [NumTargets];
  write_channel_t                                   t_w                   [NumTargets];
  write_resp_t                                      t_b                   [NumTargets];
  read_resp_t                                       t_r                   [NumTargets];
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
  logic           [NumTargets-1:0][ NumMasters-1:0] s_read_grant;
  logic           [NumTargets-1:0][ NumMasters-1:0] s_write_grant;
  logic                                             s_unused_grant;
  logic           [NumTargets-1:0][MasterWidth-1:0] s_read_selected;
  logic           [NumTargets-1:0][MasterWidth-1:0] s_write_selected;
  logic           [NumTargets-1:0]                  s_read_grant_valid;
  logic           [NumTargets-1:0]                  s_write_grant_valid;
  logic           [NumTargets-1:0]                  s_read_capture;
  logic           [NumTargets-1:0]                  s_write_capture;
  logic           [NumTargets-1:0]                  s_read_terminal;
  logic           [NumTargets-1:0]                  s_write_terminal;
  logic           [NumTargets-1:0]                  s_read_owner_valid_d;
  logic           [NumTargets-1:0]                  s_read_owner_valid_q;
  logic           [NumTargets-1:0]                  s_write_owner_valid_d;
  logic           [NumTargets-1:0]                  s_write_owner_valid_q;
  logic           [NumTargets-1:0][MasterWidth-1:0] s_read_owner_d;
  logic           [NumTargets-1:0][MasterWidth-1:0] s_read_owner_q;
  logic           [NumTargets-1:0][MasterWidth-1:0] s_write_owner_d;
  logic           [NumTargets-1:0][MasterWidth-1:0] s_write_owner_q;
  logic           [NumMasters-1:0]                  s_master_read_busy_d;
  logic           [NumMasters-1:0]                  s_master_read_busy_q;
  logic           [NumMasters-1:0]                  s_master_write_busy_d;
  logic           [NumMasters-1:0]                  s_master_write_busy_q;
  logic           [NumMasters-1:0][TargetWidth-1:0] s_master_read_target;
  logic           [NumMasters-1:0][TargetWidth-1:0] s_master_write_target;

  function automatic logic [TargetWidth-1:0] decode_target(input logic [31:0] addr,
                                                           input logic [1:0] pad_mode);
    if (`SOC_ADDR_IS_SRAM(addr)) return TargetSram;
    if (`SOC_ADDR_IS_SDRAM(addr)) return TargetSdram;
    if (`SOC_ADDR_IS_PSRAM(addr)) return (pad_mode == 2'd1) ? TargetQpi : TargetError;
    if (`SOC_ADDR_IS_OPIPSRAM(addr)) return (pad_mode == 2'd2) ? TargetOpi : TargetError;
    if (`SOC_ADDR_IS_FLASH(addr) || `SOC_ADDR_IS_XPI(addr)) return TargetXpi;
    return TargetError;
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
    ) u_read_arbiter (
        .clk_i     (clk_i),
        .rst_n_i   (rst_n_i),
        .advance_i (s_read_capture[target]),
        .request_i (s_read_req[target]),
        .grant_o   (s_read_grant[target]),
        .selected_o(s_read_selected[target]),
        .valid_o   (s_read_grant_valid[target])
    );
    round_robin_arbiter #(
        .CLIENTS(NumMasters)
    ) u_write_arbiter (
        .clk_i     (clk_i),
        .rst_n_i   (rst_n_i),
        .advance_i (s_write_capture[target]),
        .request_i (s_write_req[target]),
        .grant_o   (s_write_grant[target]),
        .selected_o(s_write_selected[target]),
        .valid_o   (s_write_grant_valid[target])
    );
  end

  always_comb begin
    s_read_req            = '0;
    s_write_req           = '0;
    s_master_read_target  = '0;
    s_master_write_target = '0;

    for (int master = 0; master < NumMasters; master++) begin
      s_master_read_target[master]  = decode_target(m_ar[master].addr, mem_pad_mode_i);
      s_master_write_target[master] = decode_target(m_aw[master].addr, mem_pad_mode_i);
      if (!block_new_i && !s_master_read_busy_q[master] && m_arvalid[master]) begin
        s_read_req[s_master_read_target[master]][master] = 1'b1;
      end
      if (!block_new_i && !s_master_write_busy_q[master] && m_awvalid[master]) begin
        s_write_req[s_master_write_target[master]][master] = 1'b1;
      end
    end
  end

  always_comb begin
    m_arready            = '0;
    m_r                  = '{default: '0};
    m_rvalid             = '0;
    t_ar                 = '{default: '0};
    t_arvalid            = '0;
    t_rready             = '0;
    s_read_capture       = '0;
    s_read_terminal      = '0;
    s_read_owner_valid_d = s_read_owner_valid_q;
    s_read_owner_d       = s_read_owner_q;
    s_master_read_busy_d = s_master_read_busy_q;

    for (int target = 0; target < NumTargets; target++) begin
      if (!s_read_owner_valid_q[target] && s_read_grant_valid[target]) begin
        automatic logic [MasterWidth-1:0] owner = s_read_selected[target];
        t_ar[target]           = m_ar[owner];
        t_arvalid[target]      = m_arvalid[owner];
        m_arready[owner]       = t_arready[target];
        s_read_capture[target] = t_arvalid[target] && t_arready[target];
        if (s_read_capture[target]) begin
          s_read_owner_valid_d[target] = 1'b1;
          s_read_owner_d[target]       = owner;
          s_master_read_busy_d[owner]  = 1'b1;
        end
      end else if (s_read_owner_valid_q[target]) begin
        automatic logic [MasterWidth-1:0] owner = s_read_owner_q[target];
        m_r[owner]              = t_r[target];
        m_rvalid[owner]         = t_rvalid[target];
        t_rready[target]        = m_rready[owner];
        s_read_terminal[target] = t_rvalid[target] && t_rready[target] && t_r[target].last;
        if (s_read_terminal[target]) begin
          s_read_owner_valid_d[target] = 1'b0;
          s_master_read_busy_d[owner]  = 1'b0;
        end
      end
    end
  end

  always_comb begin
    m_awready             = '0;
    m_wready              = '0;
    m_b                   = '{default: '0};
    m_bvalid              = '0;
    t_aw                  = '{default: '0};
    t_awvalid             = '0;
    t_w                   = '{default: '0};
    t_wvalid              = '0;
    t_bready              = '0;
    s_write_capture       = '0;
    s_write_terminal      = '0;
    s_write_owner_valid_d = s_write_owner_valid_q;
    s_write_owner_d       = s_write_owner_q;
    s_master_write_busy_d = s_master_write_busy_q;

    for (int target = 0; target < NumTargets; target++) begin
      if (!s_write_owner_valid_q[target] && s_write_grant_valid[target]) begin
        automatic logic [MasterWidth-1:0] owner = s_write_selected[target];
        t_aw[target]            = m_aw[owner];
        t_awvalid[target]       = m_awvalid[owner];
        m_awready[owner]        = t_awready[target];
        s_write_capture[target] = t_awvalid[target] && t_awready[target];
        if (s_write_capture[target]) begin
          s_write_owner_valid_d[target] = 1'b1;
          s_write_owner_d[target]       = owner;
          s_master_write_busy_d[owner]  = 1'b1;
        end
      end else if (s_write_owner_valid_q[target]) begin
        automatic logic [MasterWidth-1:0] owner = s_write_owner_q[target];
        t_w[target]              = m_w[owner];
        t_wvalid[target]         = m_wvalid[owner];
        m_wready[owner]          = t_wready[target];
        m_b[owner]               = t_b[target];
        m_bvalid[owner]          = t_bvalid[target];
        t_bready[target]         = m_bready[owner];
        s_write_terminal[target] = t_bvalid[target] && t_bready[target];
        if (s_write_terminal[target]) begin
          s_write_owner_valid_d[target] = 1'b0;
          s_master_write_busy_d[owner]  = 1'b0;
        end
      end
    end
  end

  assign idle_o = !(|s_master_read_busy_q) && !(|s_master_write_busy_q) &&
                  !(|s_read_owner_valid_q) && !(|s_write_owner_valid_q);
  assign s_unused_grant = ^{s_read_grant, s_write_grant};

  dffr #(
      .DATA_WIDTH(NumTargets)
  ) u_read_owner_valid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_owner_valid_d),
      .dat_o  (s_read_owner_valid_q)
  );
  dffr #(
      .DATA_WIDTH(NumTargets)
  ) u_write_owner_valid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_owner_valid_d),
      .dat_o  (s_write_owner_valid_q)
  );
  dffr #(
      .DATA_WIDTH(NumTargets * MasterWidth)
  ) u_read_owner_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_owner_d),
      .dat_o  (s_read_owner_q)
  );
  dffr #(
      .DATA_WIDTH(NumTargets * MasterWidth)
  ) u_write_owner_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_owner_d),
      .dat_o  (s_write_owner_q)
  );
  dffr #(
      .DATA_WIDTH(NumMasters)
  ) u_master_read_busy_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_master_read_busy_d),
      .dat_o  (s_master_read_busy_q)
  );
  dffr #(
      .DATA_WIDTH(NumMasters)
  ) u_master_write_busy_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_master_write_busy_d),
      .dat_o  (s_master_write_busy_q)
  );

`ifndef SYNTHESIS
  initial begin
    if ((NumMasters != 8) || (NumTargets != 6)) begin
      $fatal(1, "axi4_data_crossbar: product topology must be 8x6");
    end
  end
`endif
endmodule
