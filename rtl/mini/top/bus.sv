// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "mmap_define.svh"

module regslice #(
    parameter int WIDTH  = 1,
    parameter int BYPASS = 0
) (
    input  logic             clk_i,
    input  logic             rst_n_i,
    input  logic [WIDTH-1:0] dat_i,
    output logic [WIDTH-1:0] dat_o
);

  if (BYPASS == 1) assign dat_o = dat_i;
  else begin
    dffr #(WIDTH) u_regslice_dffr (
        clk_i,
        rst_n_i,
        dat_i,
        dat_o
    );
  end
endmodule


module bus (
    // verilog_format: off
    input  logic  clk_i,
    input  logic  rst_n_i,
`ifdef HAVE_SRAM_IF
    ram_if.master ram,
`endif
    nmi_if.slave  core_nmi,
    nmi_if.slave  dma_nmi,
    nmi_if.master natv_nmi,
    nmi_if.master apb_nmi
    // verilog_format: on
);

  logic s_natv_sel, s_apb_sel, s_ram_sel;
  logic s_ram_valid, s_ram_ready;
  logic s_mstr_lock_d, s_mstr_lock_q;
  logic s_mstr_id_d, s_mstr_id_q;
  nmi_if u_mstr_nmi_if ();
  nmi_if u_mstr_rgsl_nmi_if ();

  always_comb begin
    s_mstr_lock_d = s_mstr_lock_q;
    s_mstr_id_d   = s_mstr_id_q;
    if (~s_mstr_lock_q) begin
      if (core_nmi.valid && ~dma_nmi.valid) begin
        s_mstr_lock_d = 1'b1;
        s_mstr_id_d   = 1'b0;
      end else if (dma_nmi.valid) begin
        s_mstr_lock_d = 1'b1;
        s_mstr_id_d   = 1'b1;
      end
    end else begin
      if (~s_mstr_id_q && core_nmi.ready) begin
        s_mstr_lock_d = 1'b0;
      end else if (s_mstr_id_q && dma_nmi.ready) begin
        s_mstr_lock_d = 1'b0;
      end
    end
  end
  dffr #(1) u_mstr_lock_dffr (
      clk_i,
      rst_n_i,
      s_mstr_lock_d,
      s_mstr_lock_q
  );
  dffr #(1) u_mstr_id_dffr (
      clk_i,
      rst_n_i,
      s_mstr_id_d,
      s_mstr_id_q
  );

  // simple arbiter
  // verilog_format: off
  assign u_mstr_nmi_if.valid = s_mstr_id_q ? dma_nmi.valid : core_nmi.valid;
  assign u_mstr_nmi_if.addr  = s_mstr_id_q ? dma_nmi.addr  : core_nmi.addr;
  assign u_mstr_nmi_if.wdata = s_mstr_id_q ? dma_nmi.wdata : core_nmi.wdata;
  assign u_mstr_nmi_if.wstrb = s_mstr_id_q ? dma_nmi.wstrb : core_nmi.wstrb;

  assign dma_nmi.ready       = s_mstr_id_q ?  u_mstr_nmi_if.ready : '0;
  assign dma_nmi.rdata       = s_mstr_id_q ?  u_mstr_nmi_if.rdata : '0;
  assign core_nmi.ready      = ~s_mstr_id_q ? u_mstr_nmi_if.ready : '0;
  assign core_nmi.rdata      = ~s_mstr_id_q ? u_mstr_nmi_if.rdata : '0;
  // verilog_format: on

  // regslice to opt the timing
  nmi_regslice u_nmi_regslice (
      clk_i,
      rst_n_i,
      u_mstr_nmi_if,
      u_mstr_rgsl_nmi_if
  );

  // bus mux
  // verilog_format: off
  assign s_natv_sel      = u_mstr_rgsl_nmi_if.addr[31:28] == `NATV_IP_START ||
                           u_mstr_rgsl_nmi_if.addr[31:28] == `PSRAM_START ||
                           u_mstr_rgsl_nmi_if.addr[31:28] == `SPISD_START0 ||
                           u_mstr_rgsl_nmi_if.addr[31:28] == `SPISD_START1 ||
                           u_mstr_rgsl_nmi_if.addr[31:28] == `SPISD_START2 ||
                           u_mstr_rgsl_nmi_if.addr[31:28] == `SPISD_START3;
  assign natv_nmi.valid  = u_mstr_rgsl_nmi_if.valid && s_natv_sel;
  assign natv_nmi.addr   = u_mstr_rgsl_nmi_if.addr;
  assign natv_nmi.wdata  = u_mstr_rgsl_nmi_if.wdata;
  assign natv_nmi.wstrb  = u_mstr_rgsl_nmi_if.wstrb;

  assign s_apb_sel       = u_mstr_rgsl_nmi_if.addr[31:28] == `FLASH_START ||
                           u_mstr_rgsl_nmi_if.addr[31:28] == `APB_IP_START;
  assign apb_nmi.valid   = u_mstr_rgsl_nmi_if.valid && s_apb_sel;
  assign apb_nmi.addr    = u_mstr_rgsl_nmi_if.addr;
  assign apb_nmi.wdata   = u_mstr_rgsl_nmi_if.wdata;
  assign apb_nmi.wstrb   = u_mstr_rgsl_nmi_if.wstrb;

`ifdef HAVE_SRAM_IF
  assign s_ram_sel     = u_mstr_rgsl_nmi_if.addr[31:28] == `SRAM_START;
  assign s_ram_valid   = u_mstr_rgsl_nmi_if.valid && s_ram_sel;
  assign ram.addr      = u_mstr_rgsl_nmi_if.addr[16:2];
  assign ram.wdata     = u_mstr_rgsl_nmi_if.wdata;
  assign ram.wstrb     = s_ram_valid ? u_mstr_rgsl_nmi_if.wstrb : '0;
`endif
  // verilog_format: on

`ifdef HAVE_SRAM_MACRO
  dffr #(1) u_ram_ready_dffr (
      clk_i,
      rst_n_i,
      s_ram_valid,
      s_ram_ready
  );
`endif

  // verilog_format: off
`ifdef HAVE_SRAM_IF
  assign u_mstr_rgsl_nmi_if.ready = (natv_nmi.valid && natv_nmi.ready) ||
                                    (apb_nmi.valid && apb_nmi.ready)   ||
                                    s_ram_ready;
`else
  assign u_mstr_rgsl_nmi_if.ready = (natv_nmi.valid && natv_nmi.ready) ||
                                    (apb_nmi.valid && apb_nmi.ready);
`endif


`ifdef HAVE_SRAM_IF
  assign u_mstr_rgsl_nmi_if.rdata = (natv_nmi.valid && natv_nmi.ready) ? natv_nmi.rdata :
                                    (apb_nmi.valid && apb_nmi.ready) ? apb_nmi.rdata :
                                    s_ram_ready ? ram.rdata : '0;
`else
  assign u_mstr_rgsl_nmi_if.rdata = (natv_nmi.valid && natv_nmi.ready) ? natv_nmi.rdata :
                                    (apb_nmi.valid && apb_nmi.ready) ? apb_nmi.rdata : '0;
`endif

  // verilog_format: on
endmodule
