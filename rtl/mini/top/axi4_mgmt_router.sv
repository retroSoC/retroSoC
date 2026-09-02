// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "mmap_define.svh"

module axi4_mgmt_router (
    // verilog_format: off -- preserve the control/data route columns
    input logic          clk_i,
    input logic          rst_n_i,
          axi4_if.slave  source,
          axi4_if.master control,
          axi4_if.master data,
    output logic         idle_o
    // verilog_format: on
);
  logic s_read_active_d, s_read_active_q;
  logic s_read_data_d, s_read_data_q;
  logic s_write_active_d, s_write_active_q;
  logic s_write_data_d, s_write_data_q;
  logic s_read_data_sel;
  logic s_write_data_sel;
  logic s_read_accept;
  logic s_write_accept;
  logic s_read_terminal;
  logic s_write_terminal;

  function automatic logic is_data_addr(input logic [31:0] addr);
    return
    `SOC_ADDR_IS_FLASH(addr)
    ||
    `SOC_ADDR_IS_SRAM(addr)
    ||
    `SOC_ADDR_IS_SDRAM(addr)
    ||
    `SOC_ADDR_IS_PSRAM(addr)
    ||
    `SOC_ADDR_IS_OPIPSRAM(addr)
    ||
    `SOC_ADDR_IS_XPI(addr)
    ;
  endfunction

  assign s_read_data_sel = is_data_addr(source.araddr);
  assign s_write_data_sel = is_data_addr(source.awaddr);

  assign control.arid = source.arid;
  assign data.arid = source.arid;
  assign control.araddr = source.araddr;
  assign data.araddr = source.araddr;
  assign control.arlen = source.arlen;
  assign data.arlen = source.arlen;
  assign control.arsize = source.arsize;
  assign data.arsize = source.arsize;
  assign control.arburst = source.arburst;
  assign data.arburst = source.arburst;
  assign control.arlock = source.arlock;
  assign data.arlock = source.arlock;
  assign control.arcache = source.arcache;
  assign data.arcache = source.arcache;
  assign control.arprot = source.arprot;
  assign data.arprot = source.arprot;
  assign control.arqos = source.arqos;
  assign data.arqos = source.arqos;
  assign control.arregion = source.arregion;
  assign data.arregion = source.arregion;
  assign control.aruser = source.aruser;
  assign data.aruser = source.aruser;
  assign control.arvalid = !s_read_active_q && !s_read_data_sel && source.arvalid;
  assign data.arvalid = !s_read_active_q && s_read_data_sel && source.arvalid;
  assign source.arready = !s_read_active_q && (s_read_data_sel ? data.arready : control.arready);

  assign source.rid = s_read_data_q ? data.rid : control.rid;
  assign source.rdata = s_read_data_q ? data.rdata : control.rdata;
  assign source.rresp = s_read_data_q ? data.rresp : control.rresp;
  assign source.rlast = s_read_data_q ? data.rlast : control.rlast;
  assign source.ruser = s_read_data_q ? data.ruser : control.ruser;
  assign source.rvalid = s_read_active_q && (s_read_data_q ? data.rvalid : control.rvalid);
  assign control.rready = s_read_active_q && !s_read_data_q && source.rready;
  assign data.rready = s_read_active_q && s_read_data_q && source.rready;

  assign control.awid = source.awid;
  assign data.awid = source.awid;
  assign control.awaddr = source.awaddr;
  assign data.awaddr = source.awaddr;
  assign control.awlen = source.awlen;
  assign data.awlen = source.awlen;
  assign control.awsize = source.awsize;
  assign data.awsize = source.awsize;
  assign control.awburst = source.awburst;
  assign data.awburst = source.awburst;
  assign control.awlock = source.awlock;
  assign data.awlock = source.awlock;
  assign control.awcache = source.awcache;
  assign data.awcache = source.awcache;
  assign control.awprot = source.awprot;
  assign data.awprot = source.awprot;
  assign control.awqos = source.awqos;
  assign data.awqos = source.awqos;
  assign control.awregion = source.awregion;
  assign data.awregion = source.awregion;
  assign control.awuser = source.awuser;
  assign data.awuser = source.awuser;
  assign control.awvalid = !s_write_active_q && !s_write_data_sel && source.awvalid;
  assign data.awvalid = !s_write_active_q && s_write_data_sel && source.awvalid;
  assign source.awready = !s_write_active_q && (s_write_data_sel ? data.awready : control.awready);

  assign control.wdata = source.wdata;
  assign data.wdata = source.wdata;
  assign control.wstrb = source.wstrb;
  assign data.wstrb = source.wstrb;
  assign control.wlast = source.wlast;
  assign data.wlast = source.wlast;
  assign control.wuser = source.wuser;
  assign data.wuser = source.wuser;
  assign control.wvalid = s_write_active_q && !s_write_data_q && source.wvalid;
  assign data.wvalid = s_write_active_q && s_write_data_q && source.wvalid;
  assign source.wready = s_write_active_q && (s_write_data_q ? data.wready : control.wready);

  assign source.bid = s_write_data_q ? data.bid : control.bid;
  assign source.bresp = s_write_data_q ? data.bresp : control.bresp;
  assign source.buser = s_write_data_q ? data.buser : control.buser;
  assign source.bvalid = s_write_active_q && (s_write_data_q ? data.bvalid : control.bvalid);
  assign control.bready = s_write_active_q && !s_write_data_q && source.bready;
  assign data.bready = s_write_active_q && s_write_data_q && source.bready;

  assign s_read_accept = source.arvalid && source.arready;
  assign s_write_accept = source.awvalid && source.awready;
  assign s_read_terminal = source.rvalid && source.rready && source.rlast;
  assign s_write_terminal = source.bvalid && source.bready;
  assign idle_o = !s_read_active_q && !s_write_active_q;

  always_comb begin
    s_read_active_d  = s_read_active_q;
    s_read_data_d    = s_read_data_q;
    s_write_active_d = s_write_active_q;
    s_write_data_d   = s_write_data_q;
    if (s_read_terminal) s_read_active_d = 1'b0;
    if (s_read_accept) begin
      s_read_active_d = 1'b1;
      s_read_data_d   = s_read_data_sel;
    end
    if (s_write_terminal) s_write_active_d = 1'b0;
    if (s_write_accept) begin
      s_write_active_d = 1'b1;
      s_write_data_d   = s_write_data_sel;
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_read_active_q  <= 1'b0;
      s_read_data_q    <= 1'b0;
      s_write_active_q <= 1'b0;
      s_write_data_q   <= 1'b0;
    end else begin
      s_read_active_q  <= s_read_active_d;
      s_read_data_q    <= s_read_data_d;
      s_write_active_q <= s_write_active_d;
      s_write_data_q   <= s_write_data_d;
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (rst_n_i && $test$plusargs("trace_mgmt")) begin
      if (source.arvalid && source.arready) begin
        $display("MGMT_AR addr=%08x data=%0d", source.araddr, s_read_data_sel);
      end
      if (source.rvalid && source.rready && source.rlast) begin
        $display("MGMT_R resp=%0d data=%08x", source.rresp, source.rdata);
      end
      if (source.awvalid && source.awready) begin
        $display("MGMT_AW addr=%08x data=%0d", source.awaddr, s_write_data_sel);
      end
      if (source.bvalid && source.bready) begin
        $display("MGMT_B resp=%0d", source.bresp);
      end
    end
  end
`endif
endmodule
