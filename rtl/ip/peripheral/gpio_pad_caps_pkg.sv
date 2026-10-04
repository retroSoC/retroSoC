// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

package gpio_pad_caps_pkg;

  // These capabilities describe the selected technology IO cell, not the
  // digital GPIO controller. Unsupported electrical features remain visible
  // in the ABI and are rejected rather than emulated in RTL.
`ifdef PDK_BEHAV
  localparam bit HasInputCmos = 1'b0;
  localparam bit HasPullUp = 1'b0;
  localparam bit HasPullDown = 1'b0;
`elsif PDK_GF180
  localparam bit HasInputCmos = 1'b1;
  localparam bit HasPullUp = 1'b1;
  localparam bit HasPullDown = 1'b1;
`elsif PDK_ICS55
  localparam bit HasInputCmos = 1'b1;
  localparam bit HasPullUp = 1'b1;
  localparam bit HasPullDown = 1'b1;
`elsif PDK_SKY130
  localparam bit HasInputCmos = 1'b1;
  localparam bit HasPullUp = 1'b0;
  localparam bit HasPullDown = 1'b0;
`else
  localparam bit HasInputCmos = 1'b0;
  localparam bit HasPullUp = 1'b0;
  localparam bit HasPullDown = 1'b0;
`endif

endpackage
