`include "piolite_define.svh"

package piolite_pkg;
  typedef enum logic [2:0] {
    Disabled = 3'd0,
    Running  = 3'd1,
    Paused   = 3'd2,
    Halted   = 3'd3,
    Closing  = 3'd4
  } sm_state_e;

  typedef enum logic [2:0] {
    StallNone = 3'd0,
    StallPin  = 3'd1,
    StallFlag = 3'd2,
    StallTx   = 3'd3,
    StallRx   = 3'd4
  } stall_kind_e;

  typedef struct packed {
    logic [4:0] base;
    logic [5:0] width;
  } pin_window_t;

  typedef struct packed {
    logic [4:0]  options;
    logic [15:0] divider;
    logic [4:0]  base;
    logic [5:0]  length;
    logic [4:0]  entry;
    logic [4:0]  wrap_bottom;
    logic [4:0]  wrap_top;
    pin_window_t in_pins;
    pin_window_t out_pins;
    pin_window_t set_pins;
    logic [31:0] claim_mask;
    logic [31:0] output_mask;
    logic [31:0] initial_value;
    logic [31:0] initial_oe;
    logic [15:0] initial_x;
    logic [15:0] initial_y;
    logic [5:0]  tx_bits;
    logic [5:0]  rx_bits;
    logic [4:0]  test_pin;
    logic [1:0]  test_flag;
    logic [3:0]  tx_low;
    logic [3:0]  rx_high;
  } sm_config_t;

  typedef struct packed {
    sm_state_e   state;
    stall_kind_e stall;
    logic        last_fifo_failed;
    logic [7:0]  fault_code;
    logic [4:0]  fault_pc;
    logic [4:0]  pc;
    logic [31:0] isr;
    logic [31:0] osr;
    logic [5:0]  isr_count;
    logic [5:0]  osr_count;
    logic [15:0] x;
    logic [15:0] y;
    logic [15:0] divider_remaining;
    logic [3:0]  delay_remaining;
    logic [31:0] tick_count;
    logic [31:0] tx_stall_count;
    logic [31:0] rx_stall_count;
    logic [31:0] retired_count;
    logic [5:0]  events;
    logic [31:0] output_value;
    logic [31:0] output_oe;
  } sm_runtime_t;

  typedef struct packed {
    logic [3:0] opcode;
    logic [3:0] delay;
    logic [7:0] operand;
  } instruction_t;

  function automatic instruction_t decode_instruction(input logic [15:0] word);
    instruction_t decoded;
    decoded.opcode  = word[15:12];
    decoded.delay   = word[11:8];
    decoded.operand = word[7:0];
    return decoded;
  endfunction

  function automatic logic instruction_legal(input instruction_t instruction);
    logic legal;
    legal = 1'b1;
    unique case (instruction.opcode)
      `PIOLITE_OPCODE_CTRL: begin
        if ((instruction.operand[4:0] != 5'd0) || (instruction.operand[7:5] > 3'd3)) legal = 1'b0;
        if ((instruction.operand[7:5] == `PIOLITE_CTRL_HALT) && (instruction.delay != 4'd0))
          legal = 1'b0;
      end
      `PIOLITE_OPCODE_SET_PIN, `PIOLITE_OPCODE_SET_DIR, `PIOLITE_OPCODE_SET_COUNT: ;
      `PIOLITE_OPCODE_IN: begin
        if (instruction.operand[7:5] > 3'd3) legal = 1'b0;
      end
      `PIOLITE_OPCODE_OUT: begin
        if (instruction.operand[7:5] > 3'd4) legal = 1'b0;
        if ((instruction.operand[7:5] inside {3'd2, 3'd3}) &&
            ((instruction.operand[4:0] == 5'd0) || (instruction.operand[4:0] > 5'd16)))
          legal = 1'b0;
      end
      `PIOLITE_OPCODE_MOVE: begin
        if ((instruction.operand[2:0] != 3'd0) || (instruction.operand[5:3] > 3'd5)) legal = 1'b0;
      end
      `PIOLITE_OPCODE_FIFO: begin
        if (instruction.operand[5:0] != 6'd0) legal = 1'b0;
      end
      `PIOLITE_OPCODE_WAIT: begin
        if (instruction.operand[0] != 1'b0) legal = 1'b0;
        if (instruction.operand[7] && (instruction.operand[5:1] > 5'd3)) legal = 1'b0;
      end
      `PIOLITE_OPCODE_BRANCH:                                                      ;
      `PIOLITE_OPCODE_FLAG: begin
        if (instruction.operand[4:0] != 5'd0) legal = 1'b0;
      end
      default:                                                                     legal = 1'b0;
    endcase
    return legal;
  endfunction

  function automatic logic [5:0] encoded_count(input logic [4:0] field_value);
    return (field_value == 5'd0) ? 6'd32 : {1'b0, field_value};
  endfunction

  function automatic logic [31:0] bit_mask(input logic [5:0] width);
    return (width == 6'd0) ? 32'd0 :
        ((width >= 6'd32) ? 32'hffff_ffff : ((32'd1 << width) - 32'd1));
  endfunction

  function automatic logic [31:0] window_mask(input pin_window_t window);
    return (window.width == 6'd0) ? 32'd0 : (bit_mask(window.width) << window.base);
  endfunction

  function automatic logic [31:0] sat_increment(input logic [31:0] value);
    return (value == 32'hffff_ffff) ? value : (value + 32'd1);
  endfunction

  function automatic logic config_scalar_legal(input sm_config_t cfg);
    logic        legal;
    pin_window_t in_window;
    pin_window_t out_window;
    pin_window_t set_window;
    in_window  = cfg.in_pins;
    out_window = cfg.out_pins;
    set_window = cfg.set_pins;
    legal      = 1'b1;
    if ((cfg.divider == 16'd0) || (cfg.length == 6'd0) || (cfg.length > 6'd32)) legal = 1'b0;
    if (({1'b0, cfg.base} + cfg.length) > 7'd32) legal = 1'b0;
    if ((cfg.entry < cfg.base) || ({1'b0, cfg.entry} >= ({1'b0, cfg.base} + cfg.length)))
      legal = 1'b0;
    if ((cfg.wrap_bottom < cfg.base) ||
        ({1'b0, cfg.wrap_bottom} >= ({1'b0, cfg.base} + cfg.length)) ||
        (cfg.wrap_top < cfg.base) ||
        ({1'b0, cfg.wrap_top} >= ({1'b0, cfg.base} + cfg.length)) ||
        (cfg.wrap_bottom > cfg.wrap_top))
      legal = 1'b0;
    if ((cfg.tx_bits == 6'd0) || (cfg.tx_bits > 6'd32) ||
        (cfg.rx_bits == 6'd0) || (cfg.rx_bits > 6'd32))
      legal = 1'b0;
    if (({1'b0, in_window.base} + in_window.width) > 7'd32 ||
        ({1'b0, out_window.base} + out_window.width) > 7'd32 ||
        ({1'b0, set_window.base} + set_window.width) > 7'd32 ||
        (set_window.width > 6'd8))
      legal = 1'b0;
    if (((window_mask(
            in_window
        ) | window_mask(
            out_window
        ) | window_mask(
            set_window
        )) & ~cfg.claim_mask) != 32'd0)
      legal = 1'b0;
    if (((window_mask(out_window) | window_mask(set_window)) & ~cfg.output_mask) != 32'd0)
      legal = 1'b0;
    if (((cfg.output_mask & ~cfg.claim_mask) | (cfg.initial_value & ~cfg.output_mask) |
         (cfg.initial_oe & ~cfg.output_mask)) != 32'd0)
      legal = 1'b0;
    if (cfg.options[`PIOLITE_CONFIG_TEST_PIN_ENABLE] &&
        ((cfg.claim_mask & (32'd1 << cfg.test_pin)) == 32'd0))
      legal = 1'b0;
    return legal;
  endfunction
endpackage
