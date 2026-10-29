`include "piolite_define.svh"

module piolite_gpio_guard (
    input  piolite_pkg::sm_config_t         cfg_i           [0:1],
    input  piolite_pkg::sm_runtime_t        runtime_i       [0:1],
    input  logic                     [ 1:0] session_live_i,
    input  logic                     [31:0] user_select_i,
    input  logic                     [31:0] user_status_i,
    input  logic                     [31:0] filter_enable_i,
    input  logic                            gpio_ready_i,
    output logic                     [ 1:0] start_guard_ok_o,
    output logic                     [ 1:0] cpu_guard_ok_o,
    output logic                     [ 1:0] fault_valid_o,
    output logic                     [ 7:0] fault_code_o    [0:1],
    output logic                     [31:0] gpio_value_o,
    output logic                     [31:0] gpio_oe_o
);
  logic [31:0] s_claimed_ready;
  logic [ 1:0] s_ownership_ok;
  logic [ 1:0] s_ready_ok;

  assign s_claimed_ready = user_select_i & user_status_i & ~filter_enable_i;
  always_comb begin
    start_guard_ok_o = 2'd0;
    cpu_guard_ok_o   = 2'd0;
    fault_valid_o    = 2'd0;
    fault_code_o[0]  = 8'd0;
    fault_code_o[1]  = 8'd0;
    s_ownership_ok   = 2'd0;
    s_ready_ok       = 2'd0;
    gpio_value_o     = runtime_i[0].output_value | runtime_i[1].output_value;
    gpio_oe_o        = 32'd0;
    for (integer index = 0; index < 2; index++) begin
      s_ownership_ok[index] = ((cfg_i[index].claim_mask & ~user_select_i) == 32'd0) &&
          ((cfg_i[index].claim_mask & filter_enable_i) == 32'd0);
      s_ready_ok[index] = gpio_ready_i && ((cfg_i[index].claim_mask & ~user_status_i) == 32'd0);
      start_guard_ok_o[index] = s_ownership_ok[index] && s_ready_ok[index];
      cpu_guard_ok_o[index] = start_guard_ok_o[index];
      fault_valid_o[index] = session_live_i[index] && !(s_ownership_ok[index] && s_ready_ok[index]);
      if (!s_ownership_ok[index]) fault_code_o[index] = `PIOLITE_FAULT_OWNERSHIP_FILTER;
      else if (!s_ready_ok[index]) fault_code_o[index] = `PIOLITE_FAULT_GPIO_READY;
      gpio_oe_o |= runtime_i[index].output_oe & cfg_i[index].claim_mask &
          cfg_i[index].output_mask & s_claimed_ready & {32{gpio_ready_i}};
    end
  end
endmodule
