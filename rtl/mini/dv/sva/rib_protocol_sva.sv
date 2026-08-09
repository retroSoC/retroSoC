// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef SV_ASSRT_DISABLE
`ifndef SYNTHESIS

module rib_bus_sva (
    input logic       clk_i,
    input logic       rst_n_i,
    input logic       fault_cmd_accept_i,
    input logic       fault_valid_i,
    input logic       access_denied_i,
    input logic       cmd_accepted_i,
    input logic       arb_locked_i,
    input logic [1:0] arb_owner_i,
    input logic       mgmt_valid_i,
    input logic       user_valid_i,
    input logic       dma_valid_i
);

  // Fault commands remain active until their local terminal response.
  assert property (@(posedge clk_i) disable iff (!rst_n_i) fault_cmd_accept_i |=> cmd_accepted_i);
  assert property (@(posedge clk_i) disable iff (!rst_n_i) fault_valid_i |-> cmd_accepted_i);

  // A sole management request must acquire ownership rather than being dropped.
  assert property (@(posedge clk_i) disable iff (!rst_n_i)
      !arb_locked_i && mgmt_valid_i && !user_valid_i && !dma_valid_i |=>
          arb_locked_i && arb_owner_i == 2'd0);

  // A denied user command can only be accepted by the local error responder.
  assert property (@(posedge clk_i) disable iff (!rst_n_i)
      access_denied_i && !cmd_accepted_i |-> fault_cmd_accept_i);

endmodule

bind bus rib_bus_sva u_rib_bus_sva (
    .clk_i             (clk_i),
    .rst_n_i           (rst_n_i),
    .fault_cmd_accept_i(s_fault_cmd_hdshk),
    .fault_valid_i     (fault_valid_o),
    .arb_locked_i      (s_mstr_lock_q),
    .access_denied_i   (s_access_denied),
    .cmd_accepted_i    (s_cmd_accepted_q),
    .arb_owner_i       (s_mstr_id_q),
    .mgmt_valid_i      (mgmt_ribp.valid),
    .user_valid_i      (user_rib.cmd_valid),
    .dma_valid_i       (dma_rib.cmd_valid)
);

module rib2apb_sva #(
    parameter int NSLV = 1
) (
    input logic            clk_i,
    input logic            rst_n_i,
    input logic [NSLV-1:0] psel_comb_i,
    input logic [NSLV-1:0] psel_q_i,
    input logic [     2:0] fsm_q_i,
    input logic            rsp_valid_i,
    input logic [     1:0] rsp_beat_i,
    input logic            rsp_last_i,
    input logic            xfer_ready_i
);

  // Address regions are disjoint and only the registered select drives a response.
  assert property (@(posedge clk_i) disable iff (!rst_n_i) $onehot0(psel_comb_i));
  assert property (@(posedge clk_i) disable iff (!rst_n_i) $onehot0(psel_q_i));
  assert property (@(posedge clk_i) disable iff (!rst_n_i)
      fsm_q_i == 3'd3 && !xfer_ready_i |=> fsm_q_i == 3'd3);
  assert property (@(posedge clk_i) disable iff (!rst_n_i)
      rsp_valid_i |-> rsp_beat_i == 2'd0 && rsp_last_i);

endmodule

bind rib2apb rib2apb_sva #(
    .NSLV(NSLV)
) u_rib2apb_sva (
    .clk_i       (clk_i),
    .rst_n_i     (rst_n_i),
    .psel_comb_i (s_psel_comb),
    .psel_q_i    (s_psel_q),
    .fsm_q_i     (s_fsm_q),
    .rsp_valid_i (rib.rsp_valid),
    .rsp_beat_i  (rib.rsp_beat),
    .rsp_last_i  (rib.rsp_last),
    .xfer_ready_i(s_xfer_ready)
);

module soc_pll_rcu_sva (
    input logic       clk_i,
    input logic       rst_n_i,
    input logic [2:0] state_i,
    input logic       pll_capable_i,
    input logic       pll_apply_i,
    input logic       select_ext_clk_i
);

  localparam logic [2:0] PLL_SAFE = 3'd1;
  localparam logic [2:0] PLL_APPLY = 3'd2;
  localparam logic [2:0] PLL_WAIT_LOCK = 3'd3;
  localparam logic [2:0] PLL_RESPOND = 3'd5;

  // The output remains on the external clock until the PLL switch stage completes.
  assert property (@(posedge clk_i) disable iff (!rst_n_i)
      state_i == PLL_SAFE |-> select_ext_clk_i);
  assert property (@(posedge clk_i) disable iff (!rst_n_i)
      pll_apply_i |-> state_i inside {PLL_APPLY, PLL_WAIT_LOCK});
  assert property (@(posedge clk_i) disable iff (!rst_n_i)
      state_i == PLL_SAFE && !pll_capable_i |=> state_i == PLL_RESPOND);

endmodule

bind pll_rcu_controller soc_pll_rcu_sva u_soc_pll_rcu_sva (
    .clk_i           (ext_clk_i),
    .rst_n_i         (ext_rst_n_i),
    .state_i         (s_state_q),
    .pll_capable_i   (pll_capable_i),
    .pll_apply_i     (pll_apply_o),
    .select_ext_clk_i(select_ext_clk_o)
);

module soc_gpio_user_handoff_sva #(
    parameter int DATA_WIDTH = 1
) (
    input logic                  clk_i,
    input logic                  rst_n_i,
    input logic [DATA_WIDTH-1:0] user_sel_i,
    input logic [DATA_WIDTH-1:0] user_handoff_i,
    input logic [DATA_WIDTH-1:0] user_oe_i,
    input logic [DATA_WIDTH-1:0] user_do_i,
    input logic [DATA_WIDTH-1:0] native_oe_i,
    input logic [DATA_WIDTH-1:0] native_do_i,
    input logic [DATA_WIDTH-1:0] open_drain_i,
    input logic [DATA_WIDTH-1:0] selected_oe_i,
    input logic [DATA_WIDTH-1:0] selected_do_i,
    input logic [DATA_WIDTH-1:0] gpio_oe_i,
    input logic [DATA_WIDTH-1:0] gpio_do_i
);

  // A changing owner first drives output-enable low for a full handoff cycle.
  assert property (@(posedge clk_i) disable iff (!rst_n_i)
      selected_oe_i == ((user_sel_i & user_oe_i) | (~user_sel_i & native_oe_i)));
  assert property (@(posedge clk_i) disable iff (!rst_n_i)
      selected_do_i == ((user_sel_i & user_do_i) | (~user_sel_i & native_do_i)));
  assert property (@(posedge clk_i) disable iff (!rst_n_i)
      gpio_do_i == (selected_do_i & ~open_drain_i));
  assert property (@(posedge clk_i) disable iff (!rst_n_i)
      gpio_oe_i == (~user_handoff_i & selected_oe_i &
                    ~(open_drain_i & selected_do_i)));

endmodule

bind gpio_core soc_gpio_user_handoff_sva #(
    .DATA_WIDTH(PIN_NUM)
) u_soc_gpio_user_handoff_sva (
    .clk_i         (clk_i),
    .rst_n_i       (rst_n_i),
    .user_sel_i    (user_select_i),
    .user_handoff_i(user_handoff_i),
    .user_oe_i     (user_gpio.oe_o),
    .user_do_i     (user_gpio.do_o),
    .native_oe_i   (s_native_oe),
    .native_do_i   (s_native_data),
    .open_drain_i  (open_drain_i),
    .selected_oe_i (s_selected_oe),
    .selected_do_i (s_selected_data),
    .gpio_oe_i     (gpio.oe_o),
    .gpio_do_i     (gpio.do_o)
);

`include "soc_irq_sva.svh"
`endif

`endif
