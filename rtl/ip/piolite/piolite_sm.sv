`include "piolite_define.svh"

module piolite_sm (
    input  logic                            clk_i,
    input  logic                            rst_n_i,
    input  piolite_pkg::sm_config_t         cfg_i,
    input  logic                            start_i,
    input  logic                            pause_i,
    input  logic                            resume_i,
    input  logic                            disable_i,
    input  logic                            abort_i,
    input  logic                            sm_reset_i,
    input  logic                            block_reset_i,
`ifdef PIOLITE_EXHAUSTIVE_DV
    input  logic                            counter_load_i,
`endif
    input  logic                     [ 5:0] event_clear_i,
    input  logic                            guard_fault_i,
    input  logic                     [ 7:0] guard_fault_code_i,
    input  logic                            stream_fault_i,
    input  logic                     [15:0] instruction_i,
    input  logic                            instruction_valid_i,
    output logic                     [ 4:0] instruction_addr_o,
    input  logic                     [31:0] flags_i,
    input  logic                     [31:0] pin_inputs_i,
    output logic                     [ 3:0] flag_set_o,
    output logic                     [ 3:0] flag_clear_o,
    input  logic                            tx_empty_i,
    input  logic                     [31:0] tx_data_i,
    output logic                            tx_pop_o,
    input  logic                            rx_full_i,
    output logic                            rx_push_o,
    output logic                     [31:0] rx_data_o,
`ifdef PIOLITE_FORMAL_TOP
    output logic                            formal_commit_o,
`endif
    output piolite_pkg::sm_runtime_t        runtime_o
);
  piolite_pkg::sm_runtime_t         s_runtime_d;
  piolite_pkg::sm_runtime_t         s_runtime_q;
  piolite_pkg::sm_runtime_t         s_candidate;
  piolite_pkg::sm_runtime_t         s_tick_base;
  piolite_pkg::instruction_t        s_instruction;
  piolite_pkg::stall_kind_e         s_stall_kind;
  logic                      [ 5:0] s_count;
  logic                      [ 6:0] s_result_count;
  logic                      [ 5:0] s_shift;
  logic                      [ 5:0] s_successor_pc;
  logic                      [31:0] s_value;
  logic                      [31:0] s_chunk;
  logic                      [31:0] s_update_mask;
  logic                      [31:0] s_source_value;
  logic                      [ 3:0] s_instr_flag_set;
  logic                      [ 3:0] s_instr_flag_clear;
  logic                      [ 7:0] s_fault_code;
  logic                             s_fault;
  logic                             s_stall;
  logic                             s_halted;
  logic                             s_taken;
  logic                             s_need_tx_pop;
  logic                             s_need_rx_push;
  logic                      [31:0] s_push_data;
  logic                             s_commit;
  logic                             s_unused;
  piolite_pkg::pin_window_t         s_in_pins;
  piolite_pkg::pin_window_t         s_out_pins;
  piolite_pkg::pin_window_t         s_set_pins;
  typedef piolite_pkg::sm_runtime_t sm_runtime_t;

  function automatic sm_runtime_t fault_runtime(input sm_runtime_t runtime, input logic [7:0] code);
    piolite_pkg::sm_runtime_t result;
    result = runtime;
    if (runtime.fault_code == `PIOLITE_FAULT_NONE) begin
      result.fault_code = code;
      result.fault_pc   = runtime.pc;
    end
    result.state                         = piolite_pkg::Closing;
    result.output_oe                     = 32'd0;
    result.stall                         = piolite_pkg::StallNone;
    result.events[`PIOLITE_EVENTS_FAULT] = 1'b1;
    return result;
  endfunction

  assign instruction_addr_o = s_runtime_q.pc;
  assign runtime_o          = s_runtime_q;
`ifdef PIOLITE_FORMAL_TOP
  assign formal_commit_o = s_commit;
`endif
  assign s_unused   = ^{cfg_i.tx_low, cfg_i.rx_high};
  assign s_in_pins  = cfg_i.in_pins;
  assign s_out_pins = cfg_i.out_pins;
  assign s_set_pins = cfg_i.set_pins;

  always_comb begin
    s_runtime_d        = s_runtime_q;
    s_runtime_d.events = s_runtime_q.events & ~event_clear_i;
`ifdef PIOLITE_EXHAUSTIVE_DV
    if (counter_load_i) begin
      s_runtime_d.tick_count     = 32'hffff_ffff;
      s_runtime_d.tx_stall_count = 32'hffff_ffff;
      s_runtime_d.rx_stall_count = 32'hffff_ffff;
      s_runtime_d.retired_count  = 32'hffff_ffff;
    end
`endif
    s_candidate        = s_runtime_d;
    s_tick_base        = s_runtime_d;
    s_instruction      = piolite_pkg::decode_instruction(instruction_i);
    s_stall_kind       = piolite_pkg::StallNone;
    s_count            = 6'd0;
    s_result_count     = 7'd0;
    s_shift            = 6'd0;
    s_successor_pc     = 6'd0;
    s_value            = 32'd0;
    s_chunk            = 32'd0;
    s_update_mask      = 32'd0;
    s_source_value     = 32'd0;
    s_instr_flag_set   = 4'd0;
    s_instr_flag_clear = 4'd0;
    s_fault_code       = 8'd0;
    s_fault            = 1'b0;
    s_stall            = 1'b0;
    s_halted           = 1'b0;
    s_taken            = 1'b0;
    s_need_tx_pop      = 1'b0;
    s_need_rx_push     = 1'b0;
    s_push_data        = 32'd0;
    s_commit           = 1'b0;
    flag_set_o         = 4'd0;
    flag_clear_o       = 4'd0;
    tx_pop_o           = 1'b0;
    rx_push_o          = 1'b0;
    rx_data_o          = 32'd0;

    if (sm_reset_i || block_reset_i) begin
      s_runtime_d = '0;
      if (sm_reset_i && !block_reset_i) begin
        s_runtime_d.pc                = cfg_i.entry;
        s_runtime_d.divider_remaining = cfg_i.divider;
      end
    end else begin
      if (guard_fault_i || stream_fault_i) begin
        s_fault_code = guard_fault_i ? guard_fault_code_i : `PIOLITE_FAULT_STREAM_BEAT;
        s_runtime_d  = fault_runtime(s_runtime_d, s_fault_code);
      end
      if (abort_i) begin
        // Review: ABORT is accepted in every state, including resource-bearing DISABLED
        // and idempotently in CLOSING; every accepted command sets EVENT_ABORT.
        s_runtime_d.state                         = piolite_pkg::Closing;
        s_runtime_d.output_oe                     = 32'd0;
        s_runtime_d.stall                         = piolite_pkg::StallNone;
        s_runtime_d.events[`PIOLITE_EVENTS_ABORT] = 1'b1;
      end
      if (!guard_fault_i && !stream_fault_i && !abort_i) begin
        if (pause_i) begin
          s_runtime_d.state = piolite_pkg::Paused;
          s_runtime_d.stall = piolite_pkg::StallNone;
        end else if (disable_i) begin
          s_runtime_d.state     = piolite_pkg::Disabled;
          s_runtime_d.output_oe = 32'd0;
          s_runtime_d.stall     = piolite_pkg::StallNone;
        end else if (start_i) begin
          s_candidate                   = '0;
          s_candidate.state             = piolite_pkg::Running;
          s_candidate.pc                = cfg_i.entry;
          s_candidate.x                 = cfg_i.initial_x;
          s_candidate.y                 = cfg_i.initial_y;
          s_candidate.divider_remaining = cfg_i.divider;
          s_candidate.events            = s_runtime_d.events;
          s_candidate.output_value      = cfg_i.initial_value;
          s_candidate.output_oe         = cfg_i.initial_oe;
          s_runtime_d                   = s_candidate;
        end else if (resume_i) begin
          s_runtime_d.state = piolite_pkg::Running;
        end else if (s_runtime_q.state == piolite_pkg::Running) begin
          if (s_runtime_q.divider_remaining > 16'd1) begin
            s_candidate.divider_remaining = s_runtime_q.divider_remaining - 16'd1;
            s_runtime_d                   = s_candidate;
          end else begin
            s_candidate.divider_remaining = cfg_i.divider;
            s_candidate.tick_count        = piolite_pkg::sat_increment(s_runtime_d.tick_count);
            s_tick_base                   = s_candidate;
            if (s_candidate.delay_remaining != 4'd0) begin
              s_candidate.delay_remaining = s_candidate.delay_remaining - 4'd1;
              s_candidate.stall           = piolite_pkg::StallNone;
              s_runtime_d                 = s_candidate;
            end else if ((s_candidate.pc < cfg_i.base) ||
                ({1'b0, s_candidate.pc} >= ({1'b0, cfg_i.base} + cfg_i.length))) begin
              s_runtime_d = fault_runtime(s_tick_base, `PIOLITE_FAULT_PROGRAM_BOUNDS);
            end else if (!instruction_valid_i) begin
              s_runtime_d = fault_runtime(s_tick_base, `PIOLITE_FAULT_INVALID_FETCH);
            end else if (!piolite_pkg::instruction_legal(s_instruction)) begin
              s_runtime_d = fault_runtime(s_tick_base, `PIOLITE_FAULT_ILLEGAL_INSTRUCTION);
            end else begin
              unique case (s_instruction.opcode)
                `PIOLITE_OPCODE_CTRL: begin
                  if (s_instruction.operand[7:5] == `PIOLITE_CTRL_CLEAR_ISR) begin
                    s_candidate.isr       = 32'd0;
                    s_candidate.isr_count = 6'd0;
                  end else if (s_instruction.operand[7:5] == `PIOLITE_CTRL_CLEAR_OSR) begin
                    s_candidate.osr       = 32'd0;
                    s_candidate.osr_count = 6'd0;
                  end
                end
                `PIOLITE_OPCODE_SET_PIN, `PIOLITE_OPCODE_SET_DIR: begin
                  if ((s_set_pins.width == 6'd0) || ((piolite_pkg::window_mask(
                          s_set_pins
                      ) & ~(cfg_i.claim_mask & cfg_i.output_mask)) != 32'd0)) begin
                    s_fault      = 1'b1;
                    s_fault_code = `PIOLITE_FAULT_PIN_AUTHORIZATION;
                  end else begin
                    s_value = ({24'd0, s_instruction.operand} &
                               piolite_pkg::bit_mask(s_set_pins.width)) << s_set_pins.base;
                    s_update_mask = piolite_pkg::window_mask(s_set_pins);
                    if (s_instruction.opcode == `PIOLITE_OPCODE_SET_PIN)
                      s_candidate.output_value =
                          (s_candidate.output_value & ~s_update_mask) | s_value;
                    else s_candidate.output_oe = (s_candidate.output_oe & ~s_update_mask) | s_value;
                  end
                end
                `PIOLITE_OPCODE_SET_COUNT: begin
                  if (s_instruction.operand[7]) s_candidate.y = {9'd0, s_instruction.operand[6:0]};
                  else s_candidate.x = {9'd0, s_instruction.operand[6:0]};
                end
                `PIOLITE_OPCODE_IN: begin
                  s_count        = piolite_pkg::encoded_count(s_instruction.operand[4:0]);
                  s_result_count = {1'b0, s_candidate.isr_count} + {1'b0, s_count};
                  if (s_result_count > {1'b0, (cfg_i.options[`PIOLITE_CONFIG_AUTOPUSH] ?
                      cfg_i.rx_bits : 6'd32)}) begin
                    s_fault      = 1'b1;
                    s_fault_code = `PIOLITE_FAULT_SHIFT_BOUNDS;
                  end else if (cfg_i.options[`PIOLITE_CONFIG_AUTOPUSH] &&
                      (s_result_count == {1'b0, cfg_i.rx_bits}) && rx_full_i) begin
                    s_stall      = 1'b1;
                    s_stall_kind = piolite_pkg::StallRx;
                  end else begin
                    unique case (s_instruction.operand[7:5])
                      `PIOLITE_IN_PINS: begin
                        if ((s_count > s_in_pins.width) || ((piolite_pkg::window_mask(
                                s_in_pins
                            ) & ~cfg_i.claim_mask) != 32'd0)) begin
                          s_fault      = 1'b1;
                          s_fault_code = `PIOLITE_FAULT_PIN_AUTHORIZATION;
                        end else
                          s_source_value = (pin_inputs_i >> s_in_pins.base) & piolite_pkg::bit_mask(
                            s_count
                          );
                      end
                      `PIOLITE_IN_X:
                      s_source_value = {16'd0, s_candidate.x} & piolite_pkg::bit_mask(s_count);
                      `PIOLITE_IN_Y:
                      s_source_value = {16'd0, s_candidate.y} & piolite_pkg::bit_mask(s_count);
                      default: s_source_value = 32'd0;
                    endcase
                    if (!s_fault) begin
                      if (cfg_i.options[`PIOLITE_CONFIG_RX_RIGHT])
                        s_candidate.isr = (s_candidate.isr >> s_count) |
                            (s_source_value << (6'd32 - s_count));
                      else s_candidate.isr = (s_candidate.isr << s_count) | s_source_value;
                      s_candidate.isr_count = s_result_count[5:0];
                      if (cfg_i.options[`PIOLITE_CONFIG_AUTOPUSH] &&
                          (s_result_count == {1'b0, cfg_i.rx_bits})) begin
                        if (cfg_i.options[`PIOLITE_CONFIG_RX_RIGHT])
                          s_push_data = s_candidate.isr >> (6'd32 - s_candidate.isr_count);
                        else
                          s_push_data = s_candidate.isr & piolite_pkg::bit_mask(
                            s_candidate.isr_count
                          );
                        s_candidate.isr              = 32'd0;
                        s_candidate.isr_count        = 6'd0;
                        s_candidate.last_fifo_failed = 1'b0;
                        s_need_rx_push               = 1'b1;
                      end
                    end
                  end
                end
                `PIOLITE_OPCODE_OUT: begin
                  s_count = piolite_pkg::encoded_count(s_instruction.operand[4:0]);
                  if (s_candidate.osr_count == 6'd0) begin
                    if (!cfg_i.options[`PIOLITE_CONFIG_AUTOPULL] || (s_count > cfg_i.tx_bits)) begin
                      s_fault      = 1'b1;
                      s_fault_code = `PIOLITE_FAULT_SHIFT_BOUNDS;
                    end else if (tx_empty_i) begin
                      s_stall      = 1'b1;
                      s_stall_kind = piolite_pkg::StallTx;
                    end else begin
                      s_candidate.osr = tx_data_i & piolite_pkg::bit_mask(cfg_i.tx_bits);
                      s_candidate.osr_count = cfg_i.tx_bits;
                      s_candidate.last_fifo_failed = 1'b0;
                      s_need_tx_pop = 1'b1;
                    end
                  end else if (s_candidate.osr_count < s_count) begin
                    s_fault      = 1'b1;
                    s_fault_code = `PIOLITE_FAULT_SHIFT_BOUNDS;
                  end
                  if (!s_fault && !s_stall) begin
                    if (cfg_i.options[`PIOLITE_CONFIG_TX_RIGHT]) begin
                      s_chunk = s_candidate.osr & piolite_pkg::bit_mask(s_count);
                      s_candidate.osr = (s_candidate.osr >> s_count) &
                          piolite_pkg::bit_mask(s_candidate.osr_count - s_count);
                    end else begin
                      s_shift = s_candidate.osr_count - s_count;
                      s_chunk = (s_candidate.osr >> s_shift) & piolite_pkg::bit_mask(s_count);
                      s_candidate.osr = s_candidate.osr & piolite_pkg::bit_mask(s_shift);
                    end
                    s_candidate.osr_count = s_candidate.osr_count - s_count;
                    unique case (s_instruction.operand[7:5])
                      `PIOLITE_OUT_PINS, `PIOLITE_OUT_DIRECTIONS: begin
                        if ((s_count > s_out_pins.width) || ((piolite_pkg::window_mask(
                                s_out_pins
                            ) & ~(cfg_i.claim_mask & cfg_i.output_mask)) != 32'd0)) begin
                          s_fault      = 1'b1;
                          s_fault_code = `PIOLITE_FAULT_PIN_AUTHORIZATION;
                        end else begin
                          s_value       = s_chunk << s_out_pins.base;
                          s_update_mask = piolite_pkg::bit_mask(s_count) << s_out_pins.base;
                          if (s_instruction.operand[7:5] == `PIOLITE_OUT_PINS)
                            s_candidate.output_value =
                                (s_candidate.output_value & ~s_update_mask) | s_value;
                          else
                            s_candidate.output_oe =
                                (s_candidate.output_oe & ~s_update_mask) | s_value;
                        end
                      end
                      `PIOLITE_OUT_X: s_candidate.x = s_chunk[15:0];
                      `PIOLITE_OUT_Y: s_candidate.y = s_chunk[15:0];
                      default:        ;
                    endcase
                  end
                end
                `PIOLITE_OPCODE_MOVE: begin
                  unique case (s_instruction.operand[5:3])
                    `PIOLITE_MOVE_ISR:  s_source_value = s_candidate.isr;
                    `PIOLITE_MOVE_OSR:  s_source_value = s_candidate.osr;
                    `PIOLITE_MOVE_X:    s_source_value = {16'd0, s_candidate.x};
                    `PIOLITE_MOVE_Y:    s_source_value = {16'd0, s_candidate.y};
                    `PIOLITE_MOVE_ZERO: s_source_value = 32'd0;
                    default:            s_source_value = 32'hffff_ffff;
                  endcase
                  unique case (s_instruction.operand[7:6])
                    `PIOLITE_MOVE_ISR: begin
                      s_candidate.isr       = s_source_value;
                      s_candidate.isr_count = 6'd32;
                    end
                    `PIOLITE_MOVE_OSR: begin
                      s_candidate.osr       = s_source_value;
                      s_candidate.osr_count = 6'd32;
                    end
                    `PIOLITE_MOVE_X: s_candidate.x = s_source_value[15:0];
                    default:         s_candidate.y = s_source_value[15:0];
                  endcase
                end
                `PIOLITE_OPCODE_FIFO: begin
                  if (s_instruction.operand[7] == `PIOLITE_FIFO_PULL) begin
                    if (tx_empty_i) begin
                      if (s_instruction.operand[6] == `PIOLITE_FIFO_BLOCKING) begin
                        s_stall      = 1'b1;
                        s_stall_kind = piolite_pkg::StallTx;
                      end else begin
                        s_candidate.last_fifo_failed                  = 1'b1;
                        s_candidate.events[`PIOLITE_EVENTS_FIFO_FAIL] = 1'b1;
                      end
                    end else begin
                      s_candidate.osr = tx_data_i & piolite_pkg::bit_mask(cfg_i.tx_bits);
                      s_candidate.osr_count = cfg_i.tx_bits;
                      s_candidate.last_fifo_failed = 1'b0;
                      s_need_tx_pop = 1'b1;
                    end
                  end else begin
                    if (s_candidate.isr_count == 6'd0) begin
                      s_fault      = 1'b1;
                      s_fault_code = `PIOLITE_FAULT_SHIFT_BOUNDS;
                    end else if (rx_full_i) begin
                      if (s_instruction.operand[6] == `PIOLITE_FIFO_BLOCKING) begin
                        s_stall      = 1'b1;
                        s_stall_kind = piolite_pkg::StallRx;
                      end else begin
                        s_candidate.last_fifo_failed                  = 1'b1;
                        s_candidate.events[`PIOLITE_EVENTS_FIFO_FAIL] = 1'b1;
                      end
                    end else begin
                      if (cfg_i.options[`PIOLITE_CONFIG_RX_RIGHT])
                        s_push_data = s_candidate.isr >> (6'd32 - s_candidate.isr_count);
                      else
                        s_push_data = s_candidate.isr & piolite_pkg::bit_mask(
                          s_candidate.isr_count
                        );
                      s_candidate.isr              = 32'd0;
                      s_candidate.isr_count        = 6'd0;
                      s_candidate.last_fifo_failed = 1'b0;
                      s_need_rx_push               = 1'b1;
                    end
                  end
                end
                `PIOLITE_OPCODE_WAIT: begin
                  if (!s_instruction.operand[7]) begin
                    if ((cfg_i.claim_mask & (32'd1 << s_instruction.operand[5:1])) == 32'd0) begin
                      s_fault      = 1'b1;
                      s_fault_code = `PIOLITE_FAULT_PIN_AUTHORIZATION;
                    end else if (pin_inputs_i[s_instruction.operand[5:1]] !=
                        s_instruction.operand[6]) begin
                      s_stall      = 1'b1;
                      s_stall_kind = piolite_pkg::StallPin;
                    end
                  end else if (flags_i[{2'd0, s_instruction.operand[3:1]}] !=
                      s_instruction.operand[6]) begin
                    s_stall      = 1'b1;
                    s_stall_kind = piolite_pkg::StallFlag;
                  end
                end
                `PIOLITE_OPCODE_BRANCH: begin
                  if ((s_instruction.operand[7:5] == `PIOLITE_BRANCH_DEC_X_NONZERO) &&
                      (s_candidate.x != 16'd0))
                    s_candidate.x = s_candidate.x - 16'd1;
                  else if ((s_instruction.operand[7:5] == `PIOLITE_BRANCH_DEC_Y_NONZERO) &&
                      (s_candidate.y != 16'd0))
                    s_candidate.y = s_candidate.y - 16'd1;
                end
                default: begin
                  if (s_instruction.operand[7] == `PIOLITE_FLAG_SET)
                    s_instr_flag_set = 4'd1 << s_instruction.operand[6:5];
                  else s_instr_flag_clear = 4'd1 << s_instruction.operand[6:5];
                end
              endcase

              if (!s_stall) begin
                s_successor_pc = {1'b0, s_candidate.pc} + 6'd1;
                if ((s_instruction.opcode == `PIOLITE_OPCODE_CTRL) &&
                    (s_instruction.operand[7:5] == `PIOLITE_CTRL_HALT)) begin
                  s_halted = 1'b1;
                end else begin
                  if (s_instruction.opcode == `PIOLITE_OPCODE_BRANCH) begin
                    if (({1'b0, s_instruction.operand[4:0]} < {1'b0, cfg_i.base}) ||
                        ({1'b0, s_instruction.operand[4:0]} >=
                         ({1'b0, cfg_i.base} + cfg_i.length))) begin
                      if (!s_fault || (`PIOLITE_FAULT_PROGRAM_BOUNDS < s_fault_code))
                        s_fault_code = `PIOLITE_FAULT_PROGRAM_BOUNDS;
                      s_fault = 1'b1;
                    end
                    unique case (s_instruction.operand[7:5])
                      `PIOLITE_BRANCH_ALWAYS:      s_taken = 1'b1;
                      `PIOLITE_BRANCH_X_ZERO:      s_taken = (s_candidate.x == 16'd0);
                      `PIOLITE_BRANCH_Y_ZERO:      s_taken = (s_candidate.y == 16'd0);
                      `PIOLITE_BRANCH_DEC_X_NONZERO, `PIOLITE_BRANCH_DEC_Y_NONZERO: begin
                        s_taken = (s_instruction.operand[7:5] == `PIOLITE_BRANCH_DEC_X_NONZERO) ?
                            (s_candidate.x != 16'd0) : (s_candidate.y != 16'd0);
                      end
                      `PIOLITE_BRANCH_TEST_PIN_HIGH: begin
                        if (!cfg_i.options[`PIOLITE_CONFIG_TEST_PIN_ENABLE] ||
                            ((cfg_i.claim_mask & (32'd1 << cfg_i.test_pin)) == 32'd0)) begin
                          if (!s_fault || (`PIOLITE_FAULT_PIN_AUTHORIZATION < s_fault_code))
                            s_fault_code = `PIOLITE_FAULT_PIN_AUTHORIZATION;
                          s_fault = 1'b1;
                        end
                        s_taken = pin_inputs_i[cfg_i.test_pin];
                      end
                      `PIOLITE_BRANCH_FIFO_FAILED: s_taken = s_candidate.last_fifo_failed;
                      default:                     s_taken = flags_i[{3'd0, cfg_i.test_flag}];
                    endcase
                    if (s_taken) s_successor_pc = {1'b0, s_instruction.operand[4:0]};
                    else if (s_candidate.pc == cfg_i.wrap_top)
                      s_successor_pc = {1'b0, cfg_i.wrap_bottom};
                  end else if (s_candidate.pc == cfg_i.wrap_top) begin
                    s_successor_pc = {1'b0, cfg_i.wrap_bottom};
                  end
                  if (!s_taken && ((s_successor_pc < {1'b0, cfg_i.base}) ||
                      (s_successor_pc >= ({1'b0, cfg_i.base} + cfg_i.length)))) begin
                    if (!s_fault || (`PIOLITE_FAULT_PROGRAM_BOUNDS < s_fault_code))
                      s_fault_code = `PIOLITE_FAULT_PROGRAM_BOUNDS;
                    s_fault = 1'b1;
                  end
                end
              end

              if (s_stall) begin
                s_runtime_d       = s_tick_base;
                s_runtime_d.stall = s_stall_kind;
                if (s_stall_kind == piolite_pkg::StallTx) begin
                  s_runtime_d.events[`PIOLITE_EVENTS_TX_STALL] = 1'b1;
                  s_runtime_d.tx_stall_count =
                      piolite_pkg::sat_increment(s_tick_base.tx_stall_count);
                end else if (s_stall_kind == piolite_pkg::StallRx) begin
                  s_runtime_d.events[`PIOLITE_EVENTS_RX_STALL] = 1'b1;
                  s_runtime_d.rx_stall_count =
                      piolite_pkg::sat_increment(s_tick_base.rx_stall_count);
                end
              end else if (s_fault) begin
                s_runtime_d = fault_runtime(s_tick_base, s_fault_code);
              end else begin
                s_commit                    = 1'b1;
                s_candidate.delay_remaining = s_instruction.delay;
                s_candidate.stall           = piolite_pkg::StallNone;
                s_candidate.retired_count   = piolite_pkg::sat_increment(s_candidate.retired_count);
                if (s_halted) begin
                  s_candidate.state                        = piolite_pkg::Halted;
                  s_candidate.events[`PIOLITE_EVENTS_HALT] = 1'b1;
                end else begin
                  s_candidate.pc = s_successor_pc[4:0];
                end
                s_runtime_d = s_candidate;
              end
            end
          end
        end
      end
    end

    if (s_commit) begin
      flag_set_o   = s_instr_flag_set;
      flag_clear_o = s_instr_flag_clear;
      tx_pop_o     = s_need_tx_pop;
      rx_push_o    = s_need_rx_push;
      rx_data_o    = s_push_data;
    end
  end

  dffr #(
      .DATA_WIDTH($bits(piolite_pkg::sm_runtime_t))
  ) u_runtime (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_runtime_d),
      .dat_o  (s_runtime_q)
  );
`ifdef FORMAL
  logic s_formal_past_q;
  always_ff @(posedge clk_i) begin
    if (!rst_n_i) s_formal_past_q <= 1'b0;
    else begin
      s_formal_past_q <= 1'b1;
      assert (!tx_pop_o || s_commit);
      assert (!rx_push_o || s_commit);
      if (s_formal_past_q && $past(s_stall)) begin
        assert (s_runtime_q.pc == $past(s_runtime_q.pc));
        assert (s_runtime_q.isr == $past(s_runtime_q.isr));
        assert (s_runtime_q.osr == $past(s_runtime_q.osr));
        assert (s_runtime_q.x == $past(s_runtime_q.x) && s_runtime_q.y == $past(s_runtime_q.y));
        assert (s_runtime_q.isr_count == $past(s_runtime_q.isr_count));
        assert (s_runtime_q.osr_count == $past(s_runtime_q.osr_count));
        assert (s_runtime_q.retired_count == $past(s_runtime_q.retired_count));
      end
      if (s_formal_past_q && !$past(
              sm_reset_i || block_reset_i
          ) && ($past(
              s_runtime_q.fault_code
          ) != `PIOLITE_FAULT_NONE)) begin
        assert (s_runtime_q.fault_code == $past(s_runtime_q.fault_code));
        assert (s_runtime_q.fault_pc == $past(s_runtime_q.fault_pc));
      end
      if (s_formal_past_q && !$past(
              sm_reset_i || block_reset_i
          ) && $past(
              guard_fault_i || stream_fault_i
          ) && ($past(
              s_runtime_q.fault_code
          ) == `PIOLITE_FAULT_NONE)) begin
        if ($past(guard_fault_i)) begin
          assert (s_runtime_q.fault_code == $past(guard_fault_code_i));
        end else begin
          assert (s_runtime_q.fault_code == `PIOLITE_FAULT_STREAM_BEAT);
        end
      end
    end
  end
`endif
endmodule
