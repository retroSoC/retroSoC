// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module gpio_pad_bridge (
    gpio_if.pad     inner,
    gpio_if.soc_pad outer
);

  assign outer.oe_o = inner.oe_o;
  assign outer.cs_o = inner.cs_o;
  assign outer.pu_o = inner.pu_o;
  assign outer.pd_o = inner.pd_o;
  assign outer.do_o = inner.do_o;
  assign inner.di_i = outer.di_i;

endmodule
