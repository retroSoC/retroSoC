// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.
// See LICENSE for the complete license text.

`ifndef SV_ASSRT_DISABLE
`ifndef SYNTHESIS

// The design uses rst_n_i asynchronously in state registers while SVA samples
// it synchronously in disable iff. This is intentional assertion semantics.
/* verilator lint_off SYNCASYNCNET */

module axi4_interconnect_sva #(
    parameter int NumMasters   = 5,
    parameter int NumTargets   = 10,
    parameter int MASTER_WIDTH = $clog2(NumMasters),
    parameter int TARGET_WIDTH = $clog2(NumTargets)
) (
    input logic                                    clk_i,
    input logic                                    rst_n_i,
    input logic [NumMasters-1:0][             1:0] master_state_i,
    input logic [NumMasters-1:0][TARGET_WIDTH-1:0] master_target_i,
    input logic [NumTargets-1:0]                   target_valid_i,
    input logic [NumTargets-1:0]                   target_addr_sent_i,
    input logic [NumTargets-1:0][MASTER_WIDTH-1:0] target_owner_i,
    input logic                                    user_bus_enable_i,
    input logic                                    user_awready_i,
    input logic                                    user_arready_i
);
  localparam logic [1:0] MASTER_IDLE = 2'd0;
  localparam logic [1:0] MASTER_ACTIVE = 2'd2;

  for (genvar target = 0; target < NumTargets; target++) begin : GEN_TARGET_OWNERSHIP
    assert property (@(posedge clk_i) disable iff (!rst_n_i)
        target_addr_sent_i[target] |-> target_valid_i[target]);
    assert property (@(posedge clk_i) disable iff (!rst_n_i)
        target_valid_i[target] |->
            master_state_i[target_owner_i[target]] == MASTER_ACTIVE &&
            master_target_i[target_owner_i[target]] == TARGET_WIDTH'(target));

    for (genvar other = target + 1; other < NumTargets; other++) begin : GEN_UNIQUE_OWNER
      assert property (@(posedge clk_i) disable iff (!rst_n_i)
          target_valid_i[target] && target_valid_i[other] |->
              target_owner_i[target] != target_owner_i[other]);
    end
  end

  assert property (@(posedge clk_i) disable iff (!rst_n_i)
      !user_bus_enable_i && master_state_i[1] == MASTER_IDLE |->
          !user_awready_i && !user_arready_i);
endmodule

bind axi4_interconnect axi4_interconnect_sva #(
    .NumMasters(NumMasters),
    .NumTargets(NumTargets)
) u_axi4_interconnect_sva (
    .clk_i             (clk_i),
    .rst_n_i           (rst_n_i),
    .master_state_i    (s_master_state),
    .master_target_i   (s_master_target),
    .target_valid_i    (s_target_valid),
    .target_addr_sent_i(s_target_addr_sent),
    .target_owner_i    (s_target_owner),
    .user_bus_enable_i (user_bus_enable_i),
    .user_awready_i    (m_awready[1]),
    .user_arready_i    (m_arready[1])
);

/* verilator lint_on SYNCASYNCNET */

`endif
`endif
