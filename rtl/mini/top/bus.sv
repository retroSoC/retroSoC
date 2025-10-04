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

  nmi_if u_mstr_nmi_if();
  // simple arbiter
  assign u_mstr_nmi_if.valid = dma_nmi.valid                      ? 1'b1                : core_nmi.valid;
  assign u_mstr_nmi_if.addr  = dma_nmi.valid                      ? dma_nmi.addr        : core_nmi.addr;
  assign u_mstr_nmi_if.wdata = dma_nmi.valid                      ? dma_nmi.wdata       : core_nmi.wdata;
  assign u_mstr_nmi_if.wstrb = dma_nmi.valid                      ? dma_nmi.wstrb       : core_nmi.wstrb;
  assign dma_nmi.ready       = dma_nmi.valid                      ? u_mstr_nmi_if.ready : '0;
  assign dma_nmi.rdata       = dma_nmi.valid                      ? u_mstr_nmi_if.rdata : '0;
  assign core_nmi.ready      = (~dma_nmi.valid && core_nmi.valid) ? u_mstr_nmi_if.ready : '0;
  assign core_nmi.rdata      = (~dma_nmi.valid && core_nmi.valid) ? u_mstr_nmi_if.rdata : '0;


  assign s_natv_sel      = u_mstr_nmi_if.addr[31:24] == `NATV_IP_START ||
                           u_mstr_nmi_if.addr[31:24] == `PSRAM0_START ||
                           u_mstr_nmi_if.addr[31:24] == `PSRAM1_START ||
                           u_mstr_nmi_if.addr[31:28] == `SPISD_START;
  assign natv_nmi.valid  = u_mstr_nmi_if.valid && s_natv_sel;
  assign natv_nmi.addr   = u_mstr_nmi_if.addr;
  assign natv_nmi.wdata  = u_mstr_nmi_if.wdata;
  assign natv_nmi.wstrb  = u_mstr_nmi_if.wstrb;

  assign s_apb_sel       = u_mstr_nmi_if.addr[31:24] == `FLASH_START ||
                           u_mstr_nmi_if.addr[31:24] == `APB_IP_START;
  assign apb_nmi.valid   = u_mstr_nmi_if.valid && s_apb_sel;
  assign apb_nmi.addr    = u_mstr_nmi_if.addr;
  assign apb_nmi.wdata   = u_mstr_nmi_if.wdata;
  assign apb_nmi.wstrb   = u_mstr_nmi_if.wstrb;

`ifdef HAVE_SRAM_IF
  assign s_ram_sel     = u_mstr_nmi_if.addr[31:24] == `SRAM_START;
  assign s_ram_valid   = u_mstr_nmi_if.valid && s_ram_sel;
  assign ram.addr      = u_mstr_nmi_if.addr[16:2];
  assign ram.wdata     = u_mstr_nmi_if.wdata;
  assign ram.wstrb     = s_ram_valid ? u_mstr_nmi_if.wstrb : '0;
`endif

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
  assign u_mstr_nmi_if.ready = (natv_nmi.valid && natv_nmi.ready) ||
                               (apb_nmi.valid && apb_nmi.ready)   ||
                               s_ram_ready;
`else
  assign u_mstr_nmi_if.ready = (natv_nmi.valid && natv_nmi.ready) ||
                               (apb_nmi.valid && apb_nmi.ready);
`endif

  assign u_mstr_nmi_if.rdata = (natv_nmi.valid && natv_nmi.ready) ? natv_nmi.rdata :
                               (apb_nmi.valid && apb_nmi.ready) ? apb_nmi.rdata :
`ifdef HAVE_SRAM_IF
                               s_ram_ready ? ram.rdata :
`endif
                              '0;
  // verilog_format: on
endmodule
