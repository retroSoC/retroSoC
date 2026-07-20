// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

interface pll_ctrl_if ();
  logic [2:0] req_sel_o;
  logic       req_valid_o;
  logic       req_ready_i;

  logic [2:0] rsp_active_sel_i;
  logic       rsp_active_valid_i;
  logic       rsp_safe_clk_i;
  logic       rsp_pll_lock_i;
  logic [1:0] rsp_error_i;
  logic       rsp_valid_i;
  logic       rsp_ready_o;
  logic       capable_i;

  modport sysctrl(
      output req_sel_o,
      output req_valid_o,
      output rsp_ready_o,
      input req_ready_i,
      input rsp_active_sel_i,
      input rsp_active_valid_i,
      input rsp_safe_clk_i,
      input rsp_pll_lock_i,
      input rsp_error_i,
      input rsp_valid_i,
      input capable_i
  );

  modport rcu(
      input req_sel_o,
      input req_valid_o,
      input rsp_ready_o,
      output req_ready_i,
      output rsp_active_sel_i,
      output rsp_active_valid_i,
      output rsp_safe_clk_i,
      output rsp_pll_lock_i,
      output rsp_error_i,
      output rsp_valid_i,
      output capable_i
  );
endinterface
