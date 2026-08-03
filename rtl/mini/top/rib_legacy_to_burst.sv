// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

// Compatibility adapter for ClusterIP's status-less legacy rib_if.
module rib_legacy_to_burst #(
    parameter bit SYNC_RESET = 1'b0
) (
    input logic                   clk_i,
    input logic                   rst_n_i,
          rib_if.slave            legacy,
          soc_rib_burst_if.master burst
);

  soc_rib_if u_soc_legacy_if ();

  assign u_soc_legacy_if.valid = legacy.valid;
  assign u_soc_legacy_if.addr  = legacy.addr;
  assign u_soc_legacy_if.wdata = legacy.wdata;
  assign u_soc_legacy_if.wstrb = legacy.wstrb;
  assign legacy.ready          = u_soc_legacy_if.ready;
  assign legacy.rdata          = u_soc_legacy_if.rdata;

  soc_rib_legacy_to_burst #(
      .SYNC_RESET(SYNC_RESET)
  ) u_soc_rib_legacy_to_burst (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .legacy (u_soc_legacy_if),
      .burst  (burst)
  );

endmodule
