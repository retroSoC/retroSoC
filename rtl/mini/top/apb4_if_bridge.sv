// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module apb4_if_bridge (
    apb4_pure_if.slave apb_pure,
    apb4_if.master     timed
);

  assign timed.paddr      = apb_pure.paddr;
  assign timed.pprot      = apb_pure.pprot;
  assign timed.psel       = apb_pure.psel;
  assign timed.penable    = apb_pure.penable;
  assign timed.pwrite     = apb_pure.pwrite;
  assign timed.pwdata     = apb_pure.pwdata;
  assign timed.pstrb      = apb_pure.pstrb;

  assign apb_pure.pready  = timed.pready;
  assign apb_pure.prdata  = timed.prdata;
  assign apb_pure.pslverr = timed.pslverr;

endmodule
