// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module timer_core #(
    parameter int CounterWidth  = 32,
    parameter int PrescaleWidth = 16
) (
    // verilog_format: off
    input  logic                      clk_i,
    input  logic                      rst_n_i,
    input  logic                      enable_i,
    input  logic [1:0]                mode_i,
    input  logic                      direction_i,
    input  logic                      debug_freeze_enable_i,
    input  logic                      debug_halted_i,
    input  logic                      compare0_enable_i,
    input  logic                      compare1_enable_i,
    input  logic [PrescaleWidth-1:0] prescale_i,
    input  logic [CounterWidth-1:0]  load_i,
    input  logic [CounterWidth-1:0]  compare0_i,
    input  logic [CounterWidth-1:0]  compare1_i,
    input  logic                      start_i,
    input  logic                      stop_i,
    input  logic                      load_now_i,
    output logic [CounterWidth-1:0]  value_o,
    output logic                      debug_frozen_o,
    output logic                      timeout_event_o,
    output logic                      compare0_event_o,
    output logic                      compare1_event_o,
    output logic                      one_shot_done_o
    // verilog_format: on
);

  localparam logic [1:0] MODE_FREE_RUNNING = 2'b00;
  localparam logic [1:0] MODE_PERIODIC = 2'b01;
  localparam logic [1:0] MODE_ONE_SHOT = 2'b10;

  logic [PrescaleWidth-1:0] s_prescale_count;
  logic                     s_prescale_load;
  logic                     s_prescale_en;
  logic                     s_tick;
  logic                     s_terminal;
  logic                     s_prescale_overflow;
  logic [CounterWidth-1:0] s_value_d, s_value_q;

  initial begin
    if (CounterWidth < 1 || PrescaleWidth < 1) begin
      $fatal(1, "timer_core: parameter widths must be positive");
    end
  end

  assign debug_frozen_o = enable_i && debug_freeze_enable_i && debug_halted_i;
  assign value_o = s_value_q;
  assign s_tick          = enable_i && !debug_frozen_o && !start_i && !stop_i && !load_now_i &&
                           (s_prescale_count == '0) && !s_prescale_overflow;
  assign s_prescale_load = start_i || (enable_i && load_now_i) || s_tick;
  assign s_prescale_en = enable_i && !debug_frozen_o && !start_i && !stop_i && !load_now_i &&
                             !s_tick;

  rs_counter #(
      .DATA_WIDTH(PrescaleWidth)
  ) u_prescale_counter (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .clr_i  (1'b0),
      .en_i   (s_prescale_en),
      .load_i (s_prescale_load),
      .down_i (1'b1),
      .dat_i  (prescale_i),
      .dat_o  (s_prescale_count),
      .ovf_o  (s_prescale_overflow)
  );

  always_comb begin
    unique case (mode_i)
      MODE_FREE_RUNNING: s_terminal = direction_i ? s_value_q == '0 : s_value_q == '1;
      MODE_PERIODIC, MODE_ONE_SHOT: begin
        s_terminal = direction_i ? s_value_q == '0 : s_value_q >= load_i;
      end
      default:           s_terminal = 1'b0;
    endcase
  end

  always_comb begin
    timeout_event_o  = 1'b0;
    compare0_event_o = 1'b0;
    compare1_event_o = 1'b0;
    one_shot_done_o  = 1'b0;

    if (s_tick) begin
      compare0_event_o = compare0_enable_i && (s_value_q == compare0_i);
      compare1_event_o = compare1_enable_i && (s_value_q == compare1_i);
      timeout_event_o  = s_terminal;
      one_shot_done_o  = s_terminal && (mode_i == MODE_ONE_SHOT);
    end
  end

  always_comb begin
    s_value_d = s_value_q;
    if (load_now_i) begin
      s_value_d = direction_i ? load_i : '0;
    end else if (s_tick) begin
      unique case (mode_i)
        MODE_FREE_RUNNING: s_value_d = direction_i ? s_value_q - 1'b1 : s_value_q + 1'b1;
        MODE_PERIODIC: begin
          if (s_terminal) s_value_d = direction_i ? load_i : '0;
          else s_value_d = direction_i ? s_value_q - 1'b1 : s_value_q + 1'b1;
        end
        MODE_ONE_SHOT: begin
          if (!s_terminal) s_value_d = direction_i ? s_value_q - 1'b1 : s_value_q + 1'b1;
        end
        default:           s_value_d = s_value_q;
      endcase
    end
  end

  dffr #(
      .DATA_WIDTH(CounterWidth)
  ) u_value_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_value_d),
      .dat_o  (s_value_q)
  );

endmodule
