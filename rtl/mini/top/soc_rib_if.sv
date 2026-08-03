// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef RETROSOC_SOC_RIB_IF_SV
`define RETROSOC_SOC_RIB_IF_SV

`include "soc_rib_defs.svh"

// SoC-owned RIB fabric contract. RIB IP remains on ClusterIP's rib_if;
// this interface adds a response status only on the SoC master side.
interface soc_rib_if ();

  logic        valid;
  logic [31:0] addr;
  logic [31:0] wdata;
  logic [ 3:0] wstrb;
  logic [31:0] rdata;
  logic        ready;
  logic        resp_err;

  modport slave(
      input valid,
      input addr,
      input wdata,
      input wstrb,
      output rdata,
      output ready,
      output resp_err
  );
  modport master(
      output valid,
      output addr,
      output wdata,
      output wstrb,
      input rdata,
      input ready,
      input resp_err
  );

endinterface

`endif
