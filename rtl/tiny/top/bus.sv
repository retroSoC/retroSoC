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
    // core if
    input  logic        core_valid_i,
    input  logic [31:0] core_addr_i,
    input  logic [31:0] core_wdata_i,
    input  logic [ 3:0] core_wstrb_i,
    output logic [31:0] core_rdata_o,
    output logic        core_ready_o,
    // natv if
    output logic        natv_valid_o,
    output logic [31:0] natv_addr_o,
    output logic [31:0] natv_wdata_o,
    output logic [ 3:0] natv_wstrb_o,
    input  logic [31:0] natv_rdata_i,
    input  logic        natv_ready_i,
    // mmap if
    output logic        mmap_valid_o,
    output logic [31:0] mmap_addr_o,
    output logic [31:0] mmap_wdata_o,
    output logic [ 3:0] mmap_wstrb_o,
    input  logic [31:0] mmap_rdata_i,
    input  logic        mmap_ready_i,
    // psram if
    output logic        psram_valid_o,
    output logic [31:0] psram_addr_o,
    output logic [31:0] psram_wdata_o,
    output logic [ 3:0] psram_wstrb_o,
    input  logic [31:0] psram_rdata_i,
    input  logic        psram_ready_i
);

  logic s_natv_sel, s_mmap_sel, s_psram_sel;

  assign s_natv_sel    = core_addr_i[31:24] == `NATV_IP_START;
  assign natv_valid_o  = core_valid_i && s_natv_sel;
  assign natv_addr_o   = core_addr_i;
  assign natv_wdata_o  = core_wdata_i;
  assign natv_wstrb_o  = core_wstrb_i;

  assign s_mmap_sel    = core_addr_i[31:24] == `FLASH_START || core_addr_i[31:24] == `CUST_IP_START;
  assign mmap_valid_o  = core_valid_i && s_mmap_sel;
  assign mmap_addr_o   = core_addr_i;
  assign mmap_wdata_o  = core_wdata_i;
  assign mmap_wstrb_o  = core_wstrb_i;

  assign s_psram_sel   = core_addr_i[31:24] == `PSRAM_START;
  assign psram_valid_o = core_valid_i && s_psram_sel;
  assign psram_addr_o  = core_addr_i;
  assign psram_wdata_o = core_wdata_i;
  assign psram_wstrb_o = core_wstrb_i;


  // verilog_format: off
  assign core_ready_o = (natv_valid_o && natv_ready_i) ||
                        (mmap_valid_o && mmap_ready_i) ||
                        (psram_valid_o && psram_ready_i);

  assign core_rdata_o = (natv_valid_o && natv_ready_i) ? natv_rdata_i:
                        (mmap_valid_o && mmap_ready_i) ? mmap_rdata_i :
                        (psram_valid_o && psram_ready_i) ? psram_rdata_i : '0;
  // verilog_format: on
endmodule
