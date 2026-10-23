// Private read-only GPIO qualification; never drives or changes another owner.
module spi_gpio_guard (
    input  logic [ 4:0] session_i,
    input  logic [31:0] user_select_i,
    handoff_i,
    alt_enable_i,
    alt_select_i,
    input  logic [31:0] output_enable_i,
    open_drain_i,
    input  logic        gpio_ready_i,
    output logic [31:0] claim_o,
    ready_o,
    output logic        handback_o
);
  logic [31:0] s_native, s_route;
  // Session timing and unrelated ALT selectors are outside this guard's scope.
  logic s_unused;
  assign s_unused = ^{session_i[2:0], alt_select_i[29], alt_select_i[26:0]};
  assign claim_o  = (session_i[3] || session_i[4]) ? 32'hd800_0000 : 32'h9800_0000;
  assign s_native = ~(user_select_i | handoff_i | open_drain_i);
  always_comb begin
    s_route = '0;
    s_route[27] = alt_enable_i[27] && !alt_select_i[27];
    s_route[28] = alt_enable_i[28] && alt_select_i[28];
    s_route[31] = alt_enable_i[31] && alt_select_i[31];
    s_route[30] = session_i[4] ? (!alt_enable_i[30] && output_enable_i[30]) :
                               (alt_enable_i[30] && alt_select_i[30]);
  end
  assign ready_o = gpio_ready_i ? (claim_o & s_native & s_route) : 32'd0;
  assign handback_o = gpio_ready_i &&
      ((claim_o & (user_select_i | handoff_i | alt_enable_i | output_enable_i)) == 32'd0);
endmodule
