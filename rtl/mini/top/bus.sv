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
    input  logic        clk_i,
    input  logic        rst_n_i,
    nmi_if.slave        core_nmi,
    nmi_if.master       natv_nmi,
    // apb if
    output logic        apb_valid_o,
    output logic [31:0] apb_addr_o,
    output logic [31:0] apb_wdata_o,
    output logic [ 3:0] apb_wstrb_o,
    input  logic [31:0] apb_rdata_i,
    input  logic        apb_ready_i,
    // ram if
`ifdef HAVE_SRAM_IF
    output logic [14:0] ram_addr_o,
    output logic [31:0] ram_wdata_o,
    output logic [ 3:0] ram_wstrb_o,
    input  logic [31:0] ram_rdata_i,
`endif
    // psram if
    output logic        psram_valid_o,
    output logic [31:0] psram_addr_o,
    output logic [31:0] psram_wdata_o,
    output logic [ 3:0] psram_wstrb_o,
    input  logic [31:0] psram_rdata_i,
    input  logic        psram_ready_i,
    // spisd if
    output logic        spisd_valid_o,
    output logic [31:0] spisd_addr_o,
    output logic [31:0] spisd_wdata_o,
    output logic [ 3:0] spisd_wstrb_o,
    input  logic [31:0] spisd_rdata_i,
    input  logic        spisd_ready_i,
    // i2s if
    output logic        i2s_valid_o,
    output logic [31:0] i2s_addr_o,
    output logic [31:0] i2s_wdata_o,
    output logic [ 3:0] i2s_wstrb_o,
    input  logic [31:0] i2s_rdata_i,
    input  logic        i2s_ready_i
);

  logic s_natv_sel, s_apb_sel, s_ram_sel, s_psram_sel, s_spisd_sel;
  logic s_ram_valid, s_ram_ready;

  assign s_natv_sel      = core_nmi.addr[31:24] == `NATV_IP_START;
  assign natv_nmi.valid  = core_nmi.valid && s_natv_sel;
  assign natv_nmi.addr   = core_nmi.addr;
  assign natv_nmi.wdata  = core_nmi.wdata;
  assign natv_nmi.wstrb  = core_nmi.wstrb;

  assign s_apb_sel    = core_nmi.addr[31:24] == `FLASH_START || core_nmi.addr[31:24] == `CUST_IP_START;
  assign apb_valid_o  = core_nmi.valid && s_apb_sel;
  assign apb_addr_o   = core_nmi.addr;
  assign apb_wdata_o  = core_nmi.wdata;
  assign apb_wstrb_o  = core_nmi.wstrb;

`ifdef HAVE_SRAM_IF
  assign s_ram_sel     = core_nmi.addr[31:24] == `SRAM_START;
  assign s_ram_valid   = core_nmi.valid && s_ram_sel;
  assign ram_addr_o    = core_nmi.addr[16:2];
  assign ram_wdata_o   = core_nmi.wdata;
  assign ram_wstrb_o   = s_ram_valid ? core_nmi.wstrb : '0;
`endif

  assign s_psram_sel   = core_nmi.addr[31:24] == `PSRAM_START;
  assign psram_valid_o = core_nmi.valid && s_psram_sel;
  assign psram_addr_o  = core_nmi.addr;
  assign psram_wdata_o = core_nmi.wdata;
  assign psram_wstrb_o = core_nmi.wstrb;

  assign s_spisd_sel   = core_nmi.addr[31:24] == `SPISD_START;
  assign spisd_valid_o = core_nmi.valid && s_spisd_sel;
  assign spisd_addr_o  = core_nmi.addr;
  assign spisd_wdata_o = core_nmi.wdata;
  assign spisd_wstrb_o = core_nmi.wstrb;

  assign s_i2s_sel   = core_nmi.addr[31:24] == `I2S_START;
  assign i2s_valid_o = core_nmi.valid && s_i2s_sel;
  assign i2s_addr_o  = core_nmi.addr;
  assign i2s_wdata_o = core_nmi.wdata;
  assign i2s_wstrb_o = core_nmi.wstrb;


`ifdef HAVE_SRAM_MACRO
  dffr #(1) u_ram_ready_dffr (
      clk_i,
      rst_n_i,
      s_ram_valid,
      s_ram_ready
  );
`endif

  // verilog_format: off
  assign core_nmi.ready = (natv_nmi.valid && natv_nmi.ready) ||
                          (apb_valid_o && apb_ready_i) ||
`ifdef HAVE_SRAM_IF
                          s_ram_ready ||
`endif
                          (psram_valid_o && psram_ready_i) ||
                          (spisd_valid_o && spisd_ready_i);

  assign core_nmi.rdata = (natv_nmi.valid && natv_nmi.ready) ? natv_nmi.rdata:
                          (apb_valid_o && apb_ready_i) ? apb_rdata_i :
`ifdef HAVE_SRAM_IF
                          s_ram_ready ? ram_rdata_i :
`endif
                          (psram_valid_o && psram_ready_i) ? psram_rdata_i :
                          (spisd_valid_o && spisd_ready_i) ? spisd_rdata_i :
                          '0;
  // verilog_format: on
endmodule
