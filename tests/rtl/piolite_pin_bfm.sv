module piolite_pin_bfm (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic [31:0] value_i,
    input  logic [31:0] oe_i,
    output logic [31:0] cycle_count_o,
    output logic [31:0] transition_count_o
);
  logic [31:0] s_value_q;
  logic [31:0] s_oe_q;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      cycle_count_o      <= 32'd0;
      transition_count_o <= 32'd0;
      s_value_q          <= 32'd0;
      s_oe_q             <= 32'd0;
    end else begin
      cycle_count_o <= cycle_count_o + 32'd1;
      s_value_q     <= value_i;
      s_oe_q        <= oe_i;
      if ((value_i != s_value_q) || (oe_i != s_oe_q))
        transition_count_o <= transition_count_o + 32'd1;
    end
  end

  task automatic expect_pins(input logic [31:0] expected_value, input logic [31:0] expected_oe);
    if ((value_i !== expected_value) || (oe_i !== expected_oe))
      $fatal(
          1,
          "PIOLITE pin value/OE got=%h/%h expected=%h/%h",
          value_i,
          oe_i,
          expected_value,
          expected_oe
      );
  endtask

  task automatic expect_quiescent;
    if (oe_i !== 32'd0) $fatal(1, "PIOLITE output OE is not clamped: %h", oe_i);
  endtask
endmodule
