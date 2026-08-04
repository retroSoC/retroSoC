// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

// Compatibility adapter for ClusterIP's status-less RIBP interface.
module ribp2rib #(
    parameter bit SYNC_RESET = 1'b0
) (
    input logic             clk_i,
    input logic             rst_n_i,
          ribp_if.slave     ribp,
          soc_rib_if.master rib
);

  soc_ribl_if u_soc_ribl_if ();

  assign u_soc_ribl_if.valid = ribp.valid;
  assign u_soc_ribl_if.addr  = ribp.addr;
  assign u_soc_ribl_if.wdata = ribp.wdata;
  assign u_soc_ribl_if.wstrb = ribp.wstrb;
  assign ribp.ready          = u_soc_ribl_if.ready;
  assign ribp.rdata          = u_soc_ribl_if.rdata;

  soc_ribl2rib #(
      .SYNC_RESET(SYNC_RESET)
  ) u_soc_ribl2rib (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .ribl   (u_soc_ribl_if),
      .rib    (rib)
  );

endmodule
