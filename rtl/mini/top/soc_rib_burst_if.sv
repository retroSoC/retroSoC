// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef RETROSOC_SOC_RIB_BURST_IF_SV
`define RETROSOC_SOC_RIB_BURST_IF_SV

// SoC-owned split-channel RIB contract. Version 1 supports one outstanding
// 32-bit INCR1 or INCR4 transaction and does not carry transaction IDs.
interface soc_rib_burst_if ();

  logic        cmd_valid;
  logic        cmd_ready;
  logic [31:0] cmd_addr;
  logic        cmd_write;
  logic [ 1:0] cmd_len;

  logic        w_valid;
  logic        w_ready;
  logic [31:0] wdata;
  logic [ 3:0] wstrb;
  logic        wlast;

  logic        rsp_valid;
  logic        rsp_ready;
  logic [31:0] rdata;
  logic        resp_err;
  logic [ 2:0] resp_code;
  logic [ 1:0] rsp_beat;
  logic        rsp_last;

  modport slave(
      input cmd_valid,
      output cmd_ready,
      input cmd_addr,
      input cmd_write,
      input cmd_len,
      input w_valid,
      output w_ready,
      input wdata,
      input wstrb,
      input wlast,
      output rsp_valid,
      input rsp_ready,
      output rdata,
      output resp_err,
      output resp_code,
      output rsp_beat,
      output rsp_last
  );

  modport master(
      output cmd_valid,
      input cmd_ready,
      output cmd_addr,
      output cmd_write,
      output cmd_len,
      output w_valid,
      input w_ready,
      output wdata,
      output wstrb,
      output wlast,
      input rsp_valid,
      output rsp_ready,
      input rdata,
      input resp_err,
      input resp_code,
      input rsp_beat,
      input rsp_last
  );

endinterface

`endif
