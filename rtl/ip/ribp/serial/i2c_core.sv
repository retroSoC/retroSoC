// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module i2c_core (
    // verilog_format: off
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        enable_i,
    input  logic [15:0] scl_low_cycles_i,
    input  logic [15:0] scl_high_cycles_i,
    input  logic [15:0] start_hold_cycles_i,
    input  logic [15:0] start_setup_cycles_i,
    input  logic [15:0] data_hold_cycles_i,
    input  logic [15:0] data_setup_cycles_i,
    input  logic [15:0] stop_setup_cycles_i,
    input  logic [15:0] bus_free_cycles_i,
    input  logic [23:0] stretch_timeout_i,
    input  logic [23:0] bus_idle_timeout_i,
    input  logic [23:0] command_timeout_i,
    input  logic [ 9:0] target_addr_i,
    input  logic        ten_bit_i,
    input  logic        abort_i,
    input  logic        recover_i,
    input  logic        cmd_valid_i,
    input  logic [11:0] cmd_data_i,
    output logic        cmd_pop_o,
    output logic        cmd_flush_o,
    input  logic        rx_full_i,
    output logic        rx_push_o,
    output logic [ 7:0] rx_data_o,
    input  logic        scl_i,
    input  logic        sda_i,
    output logic        scl_pull_low_o,
    output logic        sda_pull_low_o,
    output logic        busy_o,
    output logic        recovery_active_o,
    output logic        done_event_o,
    output logic        addr_nack_event_o,
    output logic        data_nack_event_o,
    output logic        arb_lost_event_o,
    output logic        stretch_timeout_event_o,
    output logic        bus_timeout_event_o,
    output logic        command_timeout_event_o,
    output logic        command_error_event_o,
    output logic        rx_overflow_event_o,
    output logic        aborted_event_o,
    output logic        recovery_done_event_o,
    output logic        recovery_failed_event_o
    // verilog_format: on
);

  typedef enum logic [4:0] {
    FSM_IDLE,
    FSM_BUS_WAIT,
    FSM_RESTART_LOW,
    FSM_START_SETUP,
    FSM_START_HOLD,
    FSM_BIT_LOW,
    FSM_BIT_HIGH_WAIT,
    FSM_BIT_HIGH,
    FSM_HOLD,
    FSM_STOP_LOW,
    FSM_STOP_HIGH_WAIT,
    FSM_STOP_SETUP,
    FSM_BUS_FREE,
    FSM_RECOVERY_LOW,
    FSM_RECOVERY_HIGH_WAIT,
    FSM_RECOVERY_HIGH
  } i2c_fsm_t;

  typedef enum logic [1:0] {
    BIT_TX,
    BIT_RX,
    BIT_TARGET_ACK,
    BIT_CONTROLLER_ACK
  } i2c_bit_action_t;

  typedef enum logic [2:0] {
    BYTE_ADDR_7,
    BYTE_ADDR_10_HEADER_W,
    BYTE_ADDR_10_LOW,
    BYTE_ADDR_10_HEADER_R,
    BYTE_WRITE,
    BYTE_READ
  } i2c_byte_role_t;

  localparam int unsigned COUNTER_WIDTH = 24;

  i2c_fsm_t s_fsm_d, s_fsm_q;
  i2c_bit_action_t s_bit_action_d, s_bit_action_q;
  i2c_byte_role_t s_byte_role_d, s_byte_role_q;
  logic [$bits(i2c_fsm_t)-1:0] s_fsm_d_raw, s_fsm_q_raw;
  logic [$bits(i2c_bit_action_t)-1:0] s_bit_action_d_raw, s_bit_action_q_raw;
  logic [$bits(i2c_byte_role_t)-1:0] s_byte_role_d_raw, s_byte_role_q_raw;
  logic [23:0] s_phase_count_d, s_phase_count_q;
  logic [23:0] s_stretch_count_d, s_stretch_count_q;
  logic [23:0] s_command_count_d, s_command_count_q;
  logic [11:0] s_command_d, s_command_q;
  logic [7:0] s_tx_byte_d, s_tx_byte_q;
  logic [7:0] s_rx_byte_d, s_rx_byte_q;
  logic [2:0] s_bit_index_d, s_bit_index_q;
  logic [3:0] s_recovery_pulse_d, s_recovery_pulse_q;
  logic s_command_active_d, s_command_active_q;
  logic s_bus_owned_d, s_bus_owned_q;
  logic s_recovery_d, s_recovery_q;
  logic s_read_header_only_d, s_read_header_only_q;
  logic s_rx_overflow_d, s_rx_overflow_q;
  logic [16:0] s_data_low_cycles;
  logic        s_tx_bit;
  logic        s_phase_done;
  logic        s_low_phase_done;
  logic        s_stretch_timeout;
  logic        s_bus_idle_timeout;
  logic        s_command_timeout;
  logic        s_arbitration_lost;

  function automatic logic timeout_expired(input logic [23:0] count, input logic [23:0] limit);
    return (limit != 24'd0) && (count >= (limit - 1'b1));
  endfunction

  function automatic logic timing_expired(input logic [23:0] count, input logic [15:0] limit);
    return (limit == 16'd0) || (count >= ({8'd0, limit} - 1'b1));
  endfunction

  assign s_data_low_cycles = {1'b0, data_hold_cycles_i} + {1'b0, data_setup_cycles_i};
  assign s_fsm_d_raw = s_fsm_d;
  assign s_fsm_q = i2c_fsm_t'(s_fsm_q_raw);
  assign s_bit_action_d_raw = s_bit_action_d;
  assign s_bit_action_q = i2c_bit_action_t'(s_bit_action_q_raw);
  assign s_byte_role_d_raw = s_byte_role_d;
  assign s_byte_role_q = i2c_byte_role_t'(s_byte_role_q_raw);
  assign s_tx_bit = s_tx_byte_q[s_bit_index_q];
  assign s_phase_done = timing_expired(s_phase_count_q, scl_high_cycles_i);
  assign s_low_phase_done = timing_expired(
      s_phase_count_q, scl_low_cycles_i
  ) && ((s_data_low_cycles == 17'd0) ||
        ({1'b0, s_phase_count_q[15:0]} >= (s_data_low_cycles - 1'b1)));
  assign s_stretch_timeout = timeout_expired(s_stretch_count_q, stretch_timeout_i);
  assign s_bus_idle_timeout = timeout_expired(s_phase_count_q, bus_idle_timeout_i);
  assign s_command_timeout = timeout_expired(s_command_count_q, command_timeout_i);
  assign s_arbitration_lost = (s_bit_action_q == BIT_TX) && s_tx_bit && !sda_i;

  assign busy_o = (s_fsm_q != FSM_IDLE) || s_command_active_q || s_recovery_q;
  assign recovery_active_o = s_recovery_q;
  assign rx_data_o = s_rx_byte_q;

  always_comb begin
    scl_pull_low_o = 1'b0;
    sda_pull_low_o = 1'b0;

    unique case (s_fsm_q)
      FSM_START_HOLD: begin
        sda_pull_low_o = 1'b1;
      end
      FSM_BIT_LOW, FSM_BIT_HIGH_WAIT, FSM_BIT_HIGH: begin
        scl_pull_low_o = s_fsm_q == FSM_BIT_LOW;
        unique case (s_bit_action_q)
          BIT_TX:             sda_pull_low_o = !s_tx_bit;
          BIT_CONTROLLER_ACK: sda_pull_low_o = !s_command_q[11] && !s_rx_overflow_q;
          default:            sda_pull_low_o = 1'b0;
        endcase
      end
      FSM_HOLD, FSM_RESTART_LOW: begin
        scl_pull_low_o = 1'b1;
      end
      FSM_STOP_LOW: begin
        scl_pull_low_o = 1'b1;
        sda_pull_low_o = 1'b1;
      end
      FSM_STOP_HIGH_WAIT, FSM_STOP_SETUP: begin
        sda_pull_low_o = 1'b1;
      end
      FSM_RECOVERY_LOW: begin
        scl_pull_low_o = 1'b1;
      end
      default: begin
        scl_pull_low_o = 1'b0;
        sda_pull_low_o = 1'b0;
      end
    endcase
  end

  always_comb begin
    s_fsm_d                 = s_fsm_q;
    s_bit_action_d          = s_bit_action_q;
    s_byte_role_d           = s_byte_role_q;
    s_phase_count_d         = s_phase_count_q;
    s_stretch_count_d       = s_stretch_count_q;
    s_command_count_d       = s_command_count_q;
    s_command_d             = s_command_q;
    s_tx_byte_d             = s_tx_byte_q;
    s_rx_byte_d             = s_rx_byte_q;
    s_bit_index_d           = s_bit_index_q;
    s_recovery_pulse_d      = s_recovery_pulse_q;
    s_command_active_d      = s_command_active_q;
    s_bus_owned_d           = s_bus_owned_q;
    s_recovery_d            = s_recovery_q;
    s_read_header_only_d    = s_read_header_only_q;
    s_rx_overflow_d         = s_rx_overflow_q;
    cmd_pop_o               = 1'b0;
    cmd_flush_o             = 1'b0;
    rx_push_o               = 1'b0;
    done_event_o            = 1'b0;
    addr_nack_event_o       = 1'b0;
    data_nack_event_o       = 1'b0;
    arb_lost_event_o        = 1'b0;
    stretch_timeout_event_o = 1'b0;
    bus_timeout_event_o     = 1'b0;
    command_timeout_event_o = 1'b0;
    command_error_event_o   = 1'b0;
    rx_overflow_event_o     = 1'b0;
    aborted_event_o         = 1'b0;
    recovery_done_event_o   = 1'b0;
    recovery_failed_event_o = 1'b0;

    if ((s_fsm_q != FSM_IDLE) && (s_fsm_q != FSM_BUS_FREE) &&
        (s_fsm_q != FSM_RECOVERY_LOW) && (s_fsm_q != FSM_RECOVERY_HIGH_WAIT) &&
        (s_fsm_q != FSM_RECOVERY_HIGH)) begin
      if (!s_command_timeout) begin
        s_command_count_d = s_command_count_q + 1'b1;
      end
    end else begin
      s_command_count_d = '0;
    end

    if (abort_i && (s_fsm_q != FSM_IDLE)) begin
      s_command_active_d = 1'b0;
      s_recovery_d       = 1'b0;
      s_rx_overflow_d    = 1'b0;
      cmd_flush_o        = 1'b1;
      aborted_event_o    = 1'b1;
      if (s_bus_owned_q) begin
        s_fsm_d         = FSM_STOP_LOW;
        s_phase_count_d = '0;
      end else begin
        s_fsm_d       = FSM_IDLE;
        s_bus_owned_d = 1'b0;
      end
    end else if (s_command_timeout && (s_fsm_q != FSM_IDLE) && !s_recovery_q &&
                 (s_fsm_q != FSM_STOP_LOW) && (s_fsm_q != FSM_STOP_HIGH_WAIT) &&
                 (s_fsm_q != FSM_STOP_SETUP) && (s_fsm_q != FSM_BUS_FREE)) begin
      s_command_active_d      = 1'b0;
      s_rx_overflow_d         = 1'b0;
      cmd_flush_o             = 1'b1;
      command_timeout_event_o = 1'b1;
      s_fsm_d                 = s_bus_owned_q ? FSM_STOP_LOW : FSM_IDLE;
      s_phase_count_d         = '0;
    end else begin
      unique case (s_fsm_q)
        FSM_IDLE: begin
          s_phase_count_d      = '0;
          s_stretch_count_d    = '0;
          s_command_count_d    = '0;
          s_command_active_d   = 1'b0;
          s_bus_owned_d        = 1'b0;
          s_recovery_d         = 1'b0;
          s_read_header_only_d = 1'b0;
          s_rx_overflow_d      = 1'b0;
          if (recover_i && enable_i) begin
            s_recovery_d       = 1'b1;
            s_recovery_pulse_d = '0;
            s_fsm_d            = FSM_RECOVERY_LOW;
          end else if (cmd_valid_i && enable_i) begin
            s_command_d        = cmd_data_i;
            s_command_active_d = 1'b1;
            cmd_pop_o          = 1'b1;
            s_fsm_d            = FSM_BUS_WAIT;
          end
        end

        FSM_BUS_WAIT: begin
          if (scl_i && sda_i) begin
            if (timing_expired(s_phase_count_q, bus_free_cycles_i)) begin
              s_phase_count_d = '0;
              s_fsm_d         = FSM_START_SETUP;
            end else begin
              s_phase_count_d = s_phase_count_q + 1'b1;
            end
          end else if (s_bus_idle_timeout) begin
            s_command_active_d  = 1'b0;
            cmd_flush_o         = 1'b1;
            bus_timeout_event_o = 1'b1;
            s_fsm_d             = FSM_IDLE;
          end else begin
            s_phase_count_d = s_phase_count_q + 1'b1;
          end
        end

        FSM_RESTART_LOW: begin
          if (sda_i && timing_expired(s_phase_count_q, data_setup_cycles_i)) begin
            s_phase_count_d = '0;
            s_fsm_d         = FSM_START_SETUP;
          end else begin
            s_phase_count_d = s_phase_count_q + 1'b1;
          end
        end

        FSM_START_SETUP: begin
          if (!scl_i) begin
            s_phase_count_d = '0;
            if (s_stretch_timeout) begin
              s_command_active_d      = 1'b0;
              s_bus_owned_d           = 1'b0;
              cmd_flush_o             = 1'b1;
              stretch_timeout_event_o = 1'b1;
              s_fsm_d                 = FSM_IDLE;
            end else begin
              s_stretch_count_d = s_stretch_count_q + 1'b1;
            end
          end else if (!sda_i) begin
            s_phase_count_d   = '0;
            s_stretch_count_d = '0;
            if (s_bus_owned_q) begin
              s_command_active_d = 1'b0;
              s_bus_owned_d      = 1'b0;
              cmd_flush_o        = 1'b1;
              arb_lost_event_o   = 1'b1;
              s_fsm_d            = FSM_IDLE;
            end else begin
              s_fsm_d = FSM_BUS_WAIT;
            end
          end else if (timing_expired(s_phase_count_q, start_setup_cycles_i)) begin
            s_phase_count_d   = '0;
            s_stretch_count_d = '0;
            s_bus_owned_d     = 1'b1;
            s_fsm_d           = FSM_START_HOLD;
          end else begin
            s_phase_count_d = s_phase_count_q + 1'b1;
          end
        end

        FSM_START_HOLD: begin
          if (timing_expired(s_phase_count_q, start_hold_cycles_i)) begin
            s_phase_count_d = '0;
            s_bit_index_d   = 3'd7;
            s_bit_action_d  = BIT_TX;
            if (!ten_bit_i) begin
              s_tx_byte_d   = {target_addr_i[6:0], s_command_q[8]};
              s_byte_role_d = BYTE_ADDR_7;
            end else if (s_read_header_only_q) begin
              s_tx_byte_d          = {5'b11110, target_addr_i[9:8], 1'b1};
              s_byte_role_d        = BYTE_ADDR_10_HEADER_R;
              s_read_header_only_d = 1'b0;
            end else begin
              s_tx_byte_d   = {5'b11110, target_addr_i[9:8], 1'b0};
              s_byte_role_d = BYTE_ADDR_10_HEADER_W;
            end
            s_fsm_d = FSM_BIT_LOW;
          end else begin
            s_phase_count_d = s_phase_count_q + 1'b1;
          end
        end

        FSM_BIT_LOW: begin
          if (s_low_phase_done) begin
            s_phase_count_d   = '0;
            s_stretch_count_d = '0;
            s_fsm_d           = FSM_BIT_HIGH_WAIT;
          end else begin
            s_phase_count_d = s_phase_count_q + 1'b1;
          end
        end

        FSM_BIT_HIGH_WAIT: begin
          if (scl_i) begin
            s_phase_count_d   = '0;
            s_stretch_count_d = '0;
            if (s_bit_action_q == BIT_RX) begin
              s_rx_byte_d[s_bit_index_q] = sda_i;
            end
            if (s_arbitration_lost) begin
              s_command_active_d = 1'b0;
              s_bus_owned_d      = 1'b0;
              cmd_flush_o        = 1'b1;
              arb_lost_event_o   = 1'b1;
              s_fsm_d            = FSM_IDLE;
            end else begin
              s_fsm_d = FSM_BIT_HIGH;
            end
          end else if (s_stretch_timeout) begin
            s_command_active_d      = 1'b0;
            s_bus_owned_d           = 1'b0;
            cmd_flush_o             = 1'b1;
            stretch_timeout_event_o = 1'b1;
            s_fsm_d                 = FSM_IDLE;
          end else begin
            s_stretch_count_d = s_stretch_count_q + 1'b1;
          end
        end

        FSM_BIT_HIGH: begin
          if (s_arbitration_lost) begin
            s_command_active_d = 1'b0;
            s_bus_owned_d      = 1'b0;
            cmd_flush_o        = 1'b1;
            arb_lost_event_o   = 1'b1;
            s_fsm_d            = FSM_IDLE;
          end else if (s_phase_done) begin
            s_phase_count_d = '0;
            if ((s_bit_action_q == BIT_TX) || (s_bit_action_q == BIT_RX)) begin
              if (s_bit_index_q != 3'd0) begin
                s_bit_index_d = s_bit_index_q - 1'b1;
                s_fsm_d       = FSM_BIT_LOW;
              end else if (s_bit_action_q == BIT_RX) begin
                s_bit_action_d  = BIT_CONTROLLER_ACK;
                s_bit_index_d   = '0;
                s_rx_overflow_d = rx_full_i;
                s_fsm_d         = FSM_BIT_LOW;
              end else begin
                s_bit_action_d = BIT_TARGET_ACK;
                s_bit_index_d  = '0;
                s_fsm_d        = FSM_BIT_LOW;
              end
            end else if (s_bit_action_q == BIT_TARGET_ACK) begin
              if (sda_i) begin
                if (s_byte_role_q == BYTE_WRITE) begin
                  data_nack_event_o = 1'b1;
                end else begin
                  addr_nack_event_o = 1'b1;
                end
                s_command_active_d = 1'b0;
                s_rx_overflow_d    = 1'b0;
                cmd_flush_o        = 1'b1;
                s_fsm_d            = FSM_STOP_LOW;
              end else begin
                unique case (s_byte_role_q)
                  BYTE_ADDR_7, BYTE_ADDR_10_HEADER_R: begin
                    s_bit_index_d = 3'd7;
                    if (s_command_q[8]) begin
                      s_bit_action_d = BIT_RX;
                      s_byte_role_d  = BYTE_READ;
                      s_rx_byte_d    = '0;
                    end else begin
                      s_bit_action_d = BIT_TX;
                      s_byte_role_d  = BYTE_WRITE;
                      s_tx_byte_d    = s_command_q[7:0];
                    end
                    s_fsm_d = FSM_BIT_LOW;
                  end
                  BYTE_ADDR_10_HEADER_W: begin
                    s_bit_action_d = BIT_TX;
                    s_byte_role_d  = BYTE_ADDR_10_LOW;
                    s_tx_byte_d    = target_addr_i[7:0];
                    s_bit_index_d  = 3'd7;
                    s_fsm_d        = FSM_BIT_LOW;
                  end
                  BYTE_ADDR_10_LOW: begin
                    if (s_command_q[8]) begin
                      s_read_header_only_d = 1'b1;
                      s_fsm_d              = FSM_RESTART_LOW;
                    end else begin
                      s_bit_action_d = BIT_TX;
                      s_byte_role_d  = BYTE_WRITE;
                      s_tx_byte_d    = s_command_q[7:0];
                      s_bit_index_d  = 3'd7;
                      s_fsm_d        = FSM_BIT_LOW;
                    end
                  end
                  BYTE_WRITE: begin
                    s_command_active_d = 1'b0;
                    if (s_command_q[10]) begin
                      s_fsm_d = FSM_STOP_LOW;
                    end else if (cmd_valid_i) begin
                      s_command_d        = cmd_data_i;
                      s_command_active_d = 1'b1;
                      s_command_count_d  = '0;
                      cmd_pop_o          = 1'b1;
                      if (cmd_data_i[9] || (cmd_data_i[8] != s_command_q[8])) begin
                        s_read_header_only_d = 1'b0;
                        s_fsm_d              = FSM_RESTART_LOW;
                      end else begin
                        s_tx_byte_d    = cmd_data_i[7:0];
                        s_bit_index_d  = 3'd7;
                        s_bit_action_d = BIT_TX;
                        s_byte_role_d  = BYTE_WRITE;
                        s_fsm_d        = FSM_BIT_LOW;
                      end
                    end else begin
                      s_fsm_d = FSM_HOLD;
                    end
                  end
                  default: begin
                    s_command_active_d    = 1'b0;
                    cmd_flush_o           = 1'b1;
                    command_error_event_o = 1'b1;
                    s_fsm_d               = FSM_STOP_LOW;
                  end
                endcase
              end
            end else begin
              if (s_rx_overflow_q) begin
                s_command_active_d  = 1'b0;
                s_rx_overflow_d     = 1'b0;
                cmd_flush_o         = 1'b1;
                rx_overflow_event_o = 1'b1;
                s_fsm_d             = FSM_STOP_LOW;
              end else begin
                rx_push_o          = 1'b1;
                s_command_active_d = 1'b0;
                s_rx_overflow_d    = 1'b0;
                if (s_command_q[10]) begin
                  s_fsm_d = FSM_STOP_LOW;
                end else if (cmd_valid_i) begin
                  if (s_command_q[11] && !cmd_data_i[9]) begin
                    cmd_flush_o           = 1'b1;
                    command_error_event_o = 1'b1;
                    s_fsm_d               = FSM_STOP_LOW;
                  end else begin
                    s_command_d        = cmd_data_i;
                    s_command_active_d = 1'b1;
                    s_command_count_d  = '0;
                    cmd_pop_o          = 1'b1;
                    if (cmd_data_i[9] || !cmd_data_i[8]) begin
                      s_read_header_only_d = 1'b0;
                      s_fsm_d              = FSM_RESTART_LOW;
                    end else begin
                      s_bit_action_d = BIT_RX;
                      s_byte_role_d  = BYTE_READ;
                      s_bit_index_d  = 3'd7;
                      s_rx_byte_d    = '0;
                      s_fsm_d        = FSM_BIT_LOW;
                    end
                  end
                end else begin
                  s_fsm_d = FSM_HOLD;
                end
              end
            end
          end else begin
            s_phase_count_d = s_phase_count_q + 1'b1;
          end
        end

        FSM_HOLD: begin
          if (cmd_valid_i) begin
            s_command_d        = cmd_data_i;
            s_command_active_d = 1'b1;
            s_command_count_d  = '0;
            cmd_pop_o          = 1'b1;
            if (cmd_data_i[9]) begin
              s_read_header_only_d = 1'b0;
              s_fsm_d              = FSM_RESTART_LOW;
            end else if (cmd_data_i[8]) begin
              s_bit_action_d = BIT_RX;
              s_byte_role_d  = BYTE_READ;
              s_bit_index_d  = 3'd7;
              s_rx_byte_d    = '0;
              s_fsm_d        = FSM_BIT_LOW;
            end else begin
              s_bit_action_d = BIT_TX;
              s_byte_role_d  = BYTE_WRITE;
              s_tx_byte_d    = cmd_data_i[7:0];
              s_bit_index_d  = 3'd7;
              s_fsm_d        = FSM_BIT_LOW;
            end
          end
        end

        FSM_STOP_LOW: begin
          if (timing_expired(s_phase_count_q, scl_low_cycles_i)) begin
            s_phase_count_d   = '0;
            s_stretch_count_d = '0;
            s_fsm_d           = FSM_STOP_HIGH_WAIT;
          end else begin
            s_phase_count_d = s_phase_count_q + 1'b1;
          end
        end

        FSM_STOP_HIGH_WAIT: begin
          if (scl_i) begin
            s_phase_count_d   = '0;
            s_stretch_count_d = '0;
            s_fsm_d           = FSM_STOP_SETUP;
          end else if (s_stretch_timeout) begin
            s_command_active_d      = 1'b0;
            s_bus_owned_d           = 1'b0;
            s_recovery_d            = 1'b0;
            cmd_flush_o             = 1'b1;
            stretch_timeout_event_o = 1'b1;
            recovery_failed_event_o = s_recovery_q;
            s_fsm_d                 = FSM_IDLE;
          end else begin
            s_stretch_count_d = s_stretch_count_q + 1'b1;
          end
        end

        FSM_STOP_SETUP: begin
          if (timing_expired(s_phase_count_q, stop_setup_cycles_i)) begin
            s_phase_count_d = '0;
            s_bus_owned_d   = 1'b0;
            s_fsm_d         = FSM_BUS_FREE;
          end else begin
            s_phase_count_d = s_phase_count_q + 1'b1;
          end
        end

        FSM_BUS_FREE: begin
          if (scl_i && sda_i) begin
            if (timing_expired(s_phase_count_q, bus_free_cycles_i)) begin
              s_phase_count_d = '0;
              if (s_recovery_q) begin
                recovery_done_event_o = 1'b1;
                s_recovery_d          = 1'b0;
              end else begin
                done_event_o = 1'b1;
              end
              s_fsm_d = FSM_IDLE;
            end else begin
              s_phase_count_d = s_phase_count_q + 1'b1;
            end
          end else if (s_bus_idle_timeout) begin
            if (s_recovery_q) begin
              recovery_failed_event_o = 1'b1;
              s_recovery_d            = 1'b0;
            end else begin
              bus_timeout_event_o = 1'b1;
            end
            cmd_flush_o = 1'b1;
            s_fsm_d     = FSM_IDLE;
          end else begin
            s_phase_count_d = s_phase_count_q + 1'b1;
          end
        end

        FSM_RECOVERY_LOW: begin
          if (timing_expired(s_phase_count_q, scl_low_cycles_i)) begin
            s_phase_count_d   = '0;
            s_stretch_count_d = '0;
            s_fsm_d           = FSM_RECOVERY_HIGH_WAIT;
          end else begin
            s_phase_count_d = s_phase_count_q + 1'b1;
          end
        end

        FSM_RECOVERY_HIGH_WAIT: begin
          if (scl_i) begin
            s_phase_count_d   = '0;
            s_stretch_count_d = '0;
            s_fsm_d           = FSM_RECOVERY_HIGH;
          end else if (s_stretch_timeout) begin
            s_recovery_d            = 1'b0;
            recovery_failed_event_o = 1'b1;
            stretch_timeout_event_o = 1'b1;
            s_fsm_d                 = FSM_IDLE;
          end else begin
            s_stretch_count_d = s_stretch_count_q + 1'b1;
          end
        end

        FSM_RECOVERY_HIGH: begin
          if (s_phase_done) begin
            s_phase_count_d = '0;
            if (s_recovery_pulse_q == 4'd8) begin
              s_bus_owned_d = 1'b1;
              s_fsm_d       = FSM_STOP_LOW;
            end else begin
              s_recovery_pulse_d = s_recovery_pulse_q + 1'b1;
              s_fsm_d            = FSM_RECOVERY_LOW;
            end
          end else begin
            s_phase_count_d = s_phase_count_q + 1'b1;
          end
        end

        default: begin
          s_fsm_d = FSM_IDLE;
        end
      endcase
    end
  end

  dffr #($bits(
      i2c_fsm_t
  )) u_fsm_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fsm_d_raw),
      .dat_o  (s_fsm_q_raw)
  );

  dffr #($bits(
      i2c_bit_action_t
  )) u_bit_action_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_bit_action_d_raw),
      .dat_o  (s_bit_action_q_raw)
  );

  dffr #($bits(
      i2c_byte_role_t
  )) u_byte_role_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_byte_role_d_raw),
      .dat_o  (s_byte_role_q_raw)
  );

  dffr #(COUNTER_WIDTH) u_phase_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_phase_count_d),
      .dat_o  (s_phase_count_q)
  );

  dffr #(COUNTER_WIDTH) u_stretch_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_stretch_count_d),
      .dat_o  (s_stretch_count_q)
  );

  dffr #(COUNTER_WIDTH) u_command_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_command_count_d),
      .dat_o  (s_command_count_q)
  );

  dffr #(12) u_command_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_command_d),
      .dat_o  (s_command_q)
  );

  dffr #(8) u_tx_byte_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_byte_d),
      .dat_o  (s_tx_byte_q)
  );

  dffr #(8) u_rx_byte_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_byte_d),
      .dat_o  (s_rx_byte_q)
  );

  dffr #(3) u_bit_index_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_bit_index_d),
      .dat_o  (s_bit_index_q)
  );

  dffr #(4) u_recovery_pulse_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_recovery_pulse_d),
      .dat_o  (s_recovery_pulse_q)
  );

  dffr #(1) u_command_active_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_command_active_d),
      .dat_o  (s_command_active_q)
  );

  dffr #(1) u_bus_owned_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_bus_owned_d),
      .dat_o  (s_bus_owned_q)
  );

  dffr #(1) u_recovery_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_recovery_d),
      .dat_o  (s_recovery_q)
  );

  dffr #(1) u_read_header_only_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_header_only_d),
      .dat_o  (s_read_header_only_q)
  );

  dffr #(1) u_rx_overflow_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_overflow_d),
      .dat_o  (s_rx_overflow_q)
  );

endmodule
