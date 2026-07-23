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

module soc_bus_sva (
    input logic clk_i,
    input logic rst_n_i,
    input logic fault_sel_i,
    input logic fault_valid_i,
    input logic arb_locked_i,
    input logic arb_dma_owner_i,
    input logic core_valid_i,
    input logic dma_valid_i
);

  // A decode miss must be reported and terminate the transaction locally.
  assert property (@(posedge clk_i) disable iff (!rst_n_i) fault_sel_i |-> fault_valid_i);

  // Retain the documented DMA-over-core arbitration policy while idle.
  assert property (@(posedge clk_i) disable iff (!rst_n_i)
      !arb_locked_i && dma_valid_i |=> arb_locked_i && arb_dma_owner_i);

  // A sole core request must acquire ownership rather than being dropped.
  assert property (@(posedge clk_i) disable iff (!rst_n_i)
      !arb_locked_i && core_valid_i && !dma_valid_i |=> arb_locked_i && !arb_dma_owner_i);

endmodule

bind bus soc_bus_sva u_soc_bus_sva (
    .clk_i          (clk_i),
    .rst_n_i        (rst_n_i),
    .fault_sel_i    (s_fault_sel),
    .fault_valid_i  (fault_valid_o),
    .arb_locked_i   (s_mstr_lock_q),
    .arb_dma_owner_i(s_mstr_id_q),
    .core_valid_i   (core_nmi.valid),
    .dma_valid_i    (dma_nmi.valid)
);

module soc_nmi2apb_sva #(
    parameter int NSLV = 1
) (
    input logic            clk_i,
    input logic            rst_n_i,
    input logic [NSLV-1:0] psel_comb_i,
    input logic [NSLV-1:0] psel_q_i,
    input logic            nmi_ready_i,
    input logic            xfer_ready_i
);

  // Address regions are disjoint and only the registered select drives a response.
  assert property (@(posedge clk_i) disable iff (!rst_n_i) $onehot0(psel_comb_i));
  assert property (@(posedge clk_i) disable iff (!rst_n_i) $onehot0(psel_q_i));
  assert property (@(posedge clk_i) disable iff (!rst_n_i) nmi_ready_i |-> xfer_ready_i);

endmodule

bind nmi2apb soc_nmi2apb_sva #(
    .NSLV(NSLV)
) u_soc_nmi2apb_sva (
    .clk_i       (clk_i),
    .rst_n_i     (rst_n_i),
    .psel_comb_i (s_psel_comb),
    .psel_q_i    (s_psel_q),
    .nmi_ready_i (nmi.ready),
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

`ifdef IP_MDD
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
    input logic [DATA_WIDTH-1:0] gpio_oe_i,
    input logic [DATA_WIDTH-1:0] gpio_do_i
);

  // A changing owner first drives output-enable low for a full handoff cycle.
  assert property (@(posedge clk_i) disable iff (!rst_n_i)
      gpio_oe_i == ((~user_handoff_i & user_sel_i & user_oe_i) |
                    (~user_handoff_i & ~user_sel_i & native_oe_i)));
  assert property (@(posedge clk_i) disable iff (!rst_n_i)
      gpio_do_i == ((user_sel_i & user_do_i) | (~user_sel_i & native_do_i)));

endmodule

bind nmi_gpio soc_gpio_user_handoff_sva #(
    .DATA_WIDTH(`NMI_GPIO_NUM)
) u_soc_gpio_user_handoff_sva (
    .clk_i         (clk_i),
    .rst_n_i       (rst_n_i),
    .user_sel_i    (s_gpio_user_sel_q),
    .user_handoff_i(s_gpio_user_handoff_q),
    .user_oe_i     (user_gpio.oe_o),
    .user_do_i     (user_gpio.do_o),
    .native_oe_i   (s_gpio_native_oe),
    .native_do_i   (s_gpio_native_out),
    .gpio_oe_i     (gpio.oe_o),
    .gpio_do_i     (gpio.do_o)
);
`endif
`endif

`endif
