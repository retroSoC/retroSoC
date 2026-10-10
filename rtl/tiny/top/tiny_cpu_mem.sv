// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0
`include "mmap_define.svh"

// Independent one-operation I/D frontends. AHB write data belongs to the cycle
// following address acceptance. Local stores complete only after macro commit.
// Only non-SRAM work enters the tagged, non-posted slow-path merge.
module tiny_cpu_mem (
    input  logic                    clk_i,
    input  logic                    rst_n_i,
    input  logic                    quiesce_i,
    output logic                    idle_o,
           ahbl_if.slave            cpu        [2],
           tiny_sram_port_if.master local_ports[2],
           axi4_if.master           slow_axi4
);
  typedef enum logic [2:0] {
    Idle,
    WriteCapture,
    LocalIssue,
    LocalWait,
    SlowIssue,
    SlowWait,
    ErrorFirst,
    ErrorLast
  } state_e;
  typedef struct packed {
    state_e      state;
    logic [31:0] addr,  data;
    logic [2:0]  size;
    logic        write;
    logic [3:0]  strb;
  } request_t;
  request_t s_req_d[2], s_req_q[2];
  logic [1:0] s_terminal, s_err, s_slow_req, s_slow_grant, s_front_idle;
  logic s_slow_selected, s_slow_valid, s_slow_accept;
  typedef enum logic [1:0] {
    SlowIdle,
    SlowAddress,
    SlowData,
    SlowResponse
  } slow_state_e;
  typedef struct packed {
    slow_state_e state;
    logic        owner, write, error;
    logic [2:0]  size;
    logic [31:0] addr,  data,  rdata;
  } slow_t;
  slow_t s_slow_d, s_slow_q;
  ahbl_if u_slow_ahbl_if (
      .hclk   (clk_i),
      .hresetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_slow_axi4_if (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  logic s_adapter_idle;

  for (genvar port_index = 0; port_index < 2; port_index++) begin : gen_port
    assign s_slow_req[port_index] = s_req_q[port_index].state == SlowIssue;
    assign s_front_idle[port_index] = (s_req_q[port_index].state == Idle) &&
        (quiesce_i || !cpu[port_index].htrans[1]);
    assign s_err[port_index] = (s_req_q[port_index].state == ErrorFirst) ||
        (s_req_q[port_index].state == ErrorLast) ||
        ((s_req_q[port_index].state == SlowWait) &&
         (s_slow_q.state == SlowResponse) && (s_slow_q.owner == 1'(port_index)) && s_slow_q.error);
    assign s_terminal[port_index] = (s_req_q[port_index].state == ErrorLast) ||
        ((s_req_q[port_index].state == LocalWait) && local_ports[port_index].rsp_valid) ||
        ((s_req_q[port_index].state == SlowWait) &&
         (s_slow_q.state == SlowResponse) && (s_slow_q.owner == 1'(port_index)) && !s_slow_q.error);
    assign cpu[port_index].hready =
        ((s_req_q[port_index].state == Idle) && !quiesce_i) || s_terminal[port_index];
    assign cpu[port_index].hresp = s_err[port_index];
    assign cpu[port_index].hrdata = (s_req_q[port_index].state == LocalWait) ?
        local_ports[port_index].rdata : s_slow_q.rdata;
    assign local_ports[port_index].req_valid = s_req_q[port_index].state == LocalIssue;
    assign local_ports[port_index].addr = s_req_q[port_index].addr;
    assign local_ports[port_index].write = s_req_q[port_index].write;
    assign local_ports[port_index].wdata = s_req_q[port_index].data;
    assign local_ports[port_index].wstrb = s_req_q[port_index].strb;
    assign local_ports[port_index].rsp_ready = s_req_q[port_index].state == LocalWait;

    always_comb begin
      s_req_d[port_index] = s_req_q[port_index];
      unique case (s_req_q[port_index].state)
        WriteCapture: begin
          unique case (s_req_q[port_index].size)
            3'd0: begin
              s_req_d[port_index].data = {24'd0, cpu[port_index].hwdata[7:0]} <<
                  (8 * s_req_q[port_index].addr[1:0]);
              s_req_d[port_index].strb = 4'b0001 << s_req_q[port_index].addr[1:0];
            end
            3'd1: begin
              s_req_d[port_index].data = {16'd0, cpu[port_index].hwdata[15:0]} <<
                  (8 * s_req_q[port_index].addr[1:0]);
              s_req_d[port_index].strb = 4'b0011 << s_req_q[port_index].addr[1:0];
            end
            default: begin
              s_req_d[port_index].data = cpu[port_index].hwdata;
              s_req_d[port_index].strb = 4'b1111;
            end
          endcase
          s_req_d[port_index].state =
          `SOC_ADDR_IS_SRAM(s_req_q[port_index].addr)
          ? LocalIssue : SlowIssue;
        end
        LocalIssue: if (local_ports[port_index].req_ready) s_req_d[port_index].state = LocalWait;
        SlowIssue:
        if (s_slow_accept && s_slow_grant[port_index]) s_req_d[port_index].state = SlowWait;
        SlowWait: if (s_err[port_index]) s_req_d[port_index].state = ErrorLast;
        ErrorFirst: s_req_d[port_index].state = ErrorLast;
        default: begin
        end
      endcase
      if (cpu[port_index].hready) begin
        s_req_d[port_index].state = Idle;
        // Capture even a terminal-cycle overlap during quiesce: that address
        // was acknowledged by HREADY and cannot be silently discarded.
        if (cpu[port_index].htrans[1]) begin
          s_req_d[port_index].addr  = cpu[port_index].haddr;
          s_req_d[port_index].size  = cpu[port_index].hsize;
          s_req_d[port_index].write = cpu[port_index].hwrite;
          s_req_d[port_index].strb  = '0;
          if ((cpu[port_index].htrans != 2'b10) || cpu[port_index].hmastlock ||
              (cpu[port_index].hsize > 3'd2) ||
              ((cpu[port_index].haddr & ((32'd1 << cpu[port_index].hsize) - 32'd1)) != 32'd0) ||
              ((port_index == 0) && (cpu[port_index].hwrite || (cpu[port_index].hsize != 3'd2))))
            s_req_d[port_index].state = ErrorFirst;
          else if (cpu[port_index].hwrite) s_req_d[port_index].state = WriteCapture;
          else
            s_req_d[port_index].state =
            `SOC_ADDR_IS_SRAM(cpu[port_index].haddr)
            ? LocalIssue : SlowIssue;
        end
      end
    end
    dffr #(
        .DATA_WIDTH($bits(request_t))
    ) u_request (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_req_d[port_index]),
        .dat_o  (s_req_q[port_index])
    );
  end

  assign idle_o        = (&s_front_idle) && (s_slow_q.state == SlowIdle) && s_adapter_idle;
  assign s_slow_accept = (s_slow_q.state == SlowIdle) && s_slow_valid;
  round_robin_arbiter #(
      .CLIENTS(2)
  ) u_slow_arbiter (
      .clk_i     (clk_i),
      .rst_n_i   (rst_n_i),
      .advance_i (s_slow_accept),
      .request_i (s_slow_req),
      .grant_o   (s_slow_grant),
      .selected_o(s_slow_selected),
      .valid_o   (s_slow_valid)
  );
  always_comb begin
    s_slow_d = s_slow_q;
    unique case (s_slow_q.state)
      SlowIdle:
      if (s_slow_accept) begin
        s_slow_d.owner = s_slow_selected;
        s_slow_d.addr  = s_req_q[s_slow_selected].addr;
        s_slow_d.write = s_req_q[s_slow_selected].write;
        s_slow_d.size  = s_req_q[s_slow_selected].size;
        // The shared AHB adapter applies lane shifting itself.
        s_slow_d.data  = s_req_q[s_slow_selected].data >> (8 * s_req_q[s_slow_selected].addr[1:0]);
        s_slow_d.state = SlowAddress;
      end
      SlowAddress:  if (u_slow_ahbl_if.hready) s_slow_d.state = SlowData;
      SlowData:
      if (u_slow_ahbl_if.hready) begin
        s_slow_d.rdata = u_slow_ahbl_if.hrdata;
        s_slow_d.error = u_slow_ahbl_if.hresp;
        s_slow_d.state = SlowResponse;
      end
      SlowResponse: s_slow_d.state = SlowIdle;
      default:      s_slow_d.state = SlowIdle;
    endcase
  end
  dffr #(
      .DATA_WIDTH($bits(slow_t))
  ) u_slow_state (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_slow_d),
      .dat_o  (s_slow_q)
  );
  assign u_slow_ahbl_if.haddr     = s_slow_q.addr;
  assign u_slow_ahbl_if.hwrite    = s_slow_q.write;
  assign u_slow_ahbl_if.hsize     = s_slow_q.size;
  assign u_slow_ahbl_if.hwdata    = s_slow_q.data;
  assign u_slow_ahbl_if.htrans    = (s_slow_q.state == SlowAddress) ? 2'b10 : 2'b00;
  assign u_slow_ahbl_if.hburst    = '0;
  assign u_slow_ahbl_if.hprot     = {3'b001, s_slow_q.owner};
  assign u_slow_ahbl_if.hmastlock = 1'b0;
  ahbl2axi4 #(
      .TwoCycleErrors(1'b1)
  ) u_slow_adapter (
      .ahbl  (u_slow_ahbl_if),
      .axi4  (u_slow_axi4_if),
      .idle_o(s_adapter_idle)
  );
  // Forward every channel unchanged except the saved instruction attribute.
  // Tiny's fabric uses it to reject fetches before peripheral side effects.
  assign slow_axi4.awid         = u_slow_axi4_if.awid;
  assign slow_axi4.awaddr       = u_slow_axi4_if.awaddr;
  assign slow_axi4.awlen        = u_slow_axi4_if.awlen;
  assign slow_axi4.awsize       = u_slow_axi4_if.awsize;
  assign slow_axi4.awburst      = u_slow_axi4_if.awburst;
  assign slow_axi4.awlock       = u_slow_axi4_if.awlock;
  assign slow_axi4.awcache      = u_slow_axi4_if.awcache;
  assign slow_axi4.awprot       = {!s_slow_q.owner, u_slow_axi4_if.awprot[1:0]};
  assign slow_axi4.awqos        = u_slow_axi4_if.awqos;
  assign slow_axi4.awregion     = u_slow_axi4_if.awregion;
  assign slow_axi4.awuser       = u_slow_axi4_if.awuser;
  assign slow_axi4.awvalid      = u_slow_axi4_if.awvalid;
  assign slow_axi4.arid         = u_slow_axi4_if.arid;
  assign slow_axi4.araddr       = u_slow_axi4_if.araddr;
  assign slow_axi4.arlen        = u_slow_axi4_if.arlen;
  assign slow_axi4.arsize       = u_slow_axi4_if.arsize;
  assign slow_axi4.arburst      = u_slow_axi4_if.arburst;
  assign slow_axi4.arlock       = u_slow_axi4_if.arlock;
  assign slow_axi4.arcache      = u_slow_axi4_if.arcache;
  assign slow_axi4.arprot       = {!s_slow_q.owner, u_slow_axi4_if.arprot[1:0]};
  assign slow_axi4.arqos        = u_slow_axi4_if.arqos;
  assign slow_axi4.arregion     = u_slow_axi4_if.arregion;
  assign slow_axi4.aruser       = u_slow_axi4_if.aruser;
  assign slow_axi4.arvalid      = u_slow_axi4_if.arvalid;
  assign slow_axi4.wdata        = u_slow_axi4_if.wdata;
  assign slow_axi4.wstrb        = u_slow_axi4_if.wstrb;
  assign slow_axi4.wlast        = u_slow_axi4_if.wlast;
  assign slow_axi4.wuser        = u_slow_axi4_if.wuser;
  assign slow_axi4.wvalid       = u_slow_axi4_if.wvalid;
  assign slow_axi4.rready       = u_slow_axi4_if.rready;
  assign slow_axi4.bready       = u_slow_axi4_if.bready;
  assign u_slow_axi4_if.awready = slow_axi4.awready;
  assign u_slow_axi4_if.arready = slow_axi4.arready;
  assign u_slow_axi4_if.wready  = slow_axi4.wready;
  assign u_slow_axi4_if.rvalid  = slow_axi4.rvalid;
  assign u_slow_axi4_if.rid     = slow_axi4.rid;
  assign u_slow_axi4_if.rdata   = slow_axi4.rdata;
  assign u_slow_axi4_if.rresp   = slow_axi4.rresp;
  assign u_slow_axi4_if.rlast   = slow_axi4.rlast;
  assign u_slow_axi4_if.ruser   = slow_axi4.ruser;
  assign u_slow_axi4_if.bvalid  = slow_axi4.bvalid;
  assign u_slow_axi4_if.bid     = slow_axi4.bid;
  assign u_slow_axi4_if.bresp   = slow_axi4.bresp;
  assign u_slow_axi4_if.buser   = slow_axi4.buser;
endmodule
