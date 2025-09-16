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
    nmi_if.master natv_nmi,
    nmi_if.master apb_nmi
    // verilog_format: on
);

  logic s_natv_sel, s_apb_sel, s_ram_sel;
  logic s_ram_valid, s_ram_ready;

  assign s_natv_sel      = core_nmi.addr[31:24] == `NATV_IP_START ||
                           core_nmi.addr[31:24] == `PSRAM_START ||
                           core_nmi.addr[31:24] == `SPISD_START;
  assign natv_nmi.valid  = core_nmi.valid && s_natv_sel;
  assign natv_nmi.addr   = core_nmi.addr;
  assign natv_nmi.wdata  = core_nmi.wdata;
  assign natv_nmi.wstrb  = core_nmi.wstrb;

  assign s_apb_sel       = core_nmi.addr[31:24] == `FLASH_START ||
                           core_nmi.addr[31:24] == `APB_IP_START;
  assign apb_nmi.valid   = core_nmi.valid && s_apb_sel;
  assign apb_nmi.addr    = core_nmi.addr;
  assign apb_nmi.wdata   = core_nmi.wdata;
  assign apb_nmi.wstrb   = core_nmi.wstrb;

`ifdef HAVE_SRAM_IF
  assign s_ram_sel     = core_nmi.addr[31:24] == `SRAM_START;
  assign s_ram_valid   = core_nmi.valid && s_ram_sel;
  assign ram.addr      = core_nmi.addr[16:2];
  assign ram.wdata     = core_nmi.wdata;
  assign ram.wstrb     = s_ram_valid ? core_nmi.wstrb : '0;
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
  assign core_nmi.ready = (natv_nmi.valid && natv_nmi.ready) ||
                          (apb_nmi.valid && apb_nmi.ready)   ||
                          s_ram_ready;
`else
  assign core_nmi.ready = (natv_nmi.valid && natv_nmi.ready) ||
                          (apb_nmi.valid && apb_nmi.ready);
`endif

  assign core_nmi.rdata = (natv_nmi.valid && natv_nmi.ready) ? natv_nmi.rdata :
                          (apb_nmi.valid && apb_nmi.ready) ? apb_nmi.rdata :
`ifdef HAVE_SRAM_IF
                          s_ram_ready ? ram.rdata :
`endif
                          '0;
  // verilog_format: on
endmodule
