// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module gpio_core #(
    parameter int PIN_NUM = 32
) (
    // verilog_format: off
    input  logic               clk_i,
    input  logic               rst_n_i,
    input  logic [PIN_NUM-1:0] data_out_i,
    input  logic [PIN_NUM-1:0] output_enable_i,
    input  logic [PIN_NUM-1:0] open_drain_i,
    input  logic [PIN_NUM-1:0] input_cmos_i,
    input  logic [PIN_NUM-1:0] pull_up_i,
    input  logic [PIN_NUM-1:0] pull_down_i,
    input  logic [PIN_NUM-1:0] alt_enable_i,
    input  logic [PIN_NUM-1:0] alt_select_i,
    input  logic [PIN_NUM-1:0] user_select_i,
    input  logic [PIN_NUM-1:0] user_handoff_i,
    input  logic [PIN_NUM-1:0] filter_enable_i,
    input  logic [15:0]        filter_div_i,
    input  logic [3:0]         filter_count_i,
    input  logic [PIN_NUM-1:0] intr_rise_enable_i,
    input  logic [PIN_NUM-1:0] intr_fall_enable_i,
    input  logic [PIN_NUM-1:0] intr_high_enable_i,
    input  logic [PIN_NUM-1:0] intr_low_enable_i,
    input  logic               irq_i,
    output logic [PIN_NUM-1:0] data_in_o,
    output logic [PIN_NUM-1:0] intr_event_o,
    gpio_if.dut                gpio,
    user_gpio_if.padctrl       user_gpio
    // verilog_format: on
);

  logic [       15:0] s_sample_count;
  logic               s_sample_tick;
  logic               s_sample_overflow;
  logic [PIN_NUM-1:0] s_input_sync;
  logic [PIN_NUM-1:0] s_input_filtered_d, s_input_filtered_q;
  logic [3:0] s_stable_count_d[0:PIN_NUM-1];
  logic [3:0] s_stable_count_q[0:PIN_NUM-1];
  logic [PIN_NUM-1:0] s_input_rise, s_input_fall;
  logic [PIN_NUM-1:0] s_alt_data, s_alt_oe;
  logic [PIN_NUM-1:0] s_native_data, s_native_oe;
  logic [PIN_NUM-1:0] s_selected_data, s_selected_oe;

  initial begin
    if ((PIN_NUM < 1) || (PIN_NUM > 32)) begin
      $fatal(1, "gpio_core: PIN_NUM must be between 1 and 32");
    end
  end

  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(PIN_NUM)
  ) u_input_cdc_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (gpio.di_i),
      .dat_o  (s_input_sync)
  );

  assign s_sample_tick = (s_sample_count == 16'd0) && !s_sample_overflow;
  rs_counter #(
      .DATA_WIDTH(16)
  ) u_filter_sample_counter (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .clr_i  (1'b0),
      .en_i   (!s_sample_tick),
      .load_i (s_sample_tick),
      .down_i (1'b1),
      .dat_i  (filter_div_i),
      .dat_o  (s_sample_count),
      .ovf_o  (s_sample_overflow)
  );

  always_comb begin
    s_input_filtered_d = s_input_filtered_q;
    for (int pin = 0; pin < PIN_NUM; pin++) begin
      s_stable_count_d[pin] = s_stable_count_q[pin];
      if (!filter_enable_i[pin]) begin
        s_input_filtered_d[pin] = s_input_sync[pin];
        s_stable_count_d[pin]   = 4'd0;
      end else if (s_sample_tick) begin
        if (s_input_sync[pin] == s_input_filtered_q[pin]) begin
          s_stable_count_d[pin] = 4'd0;
        end else if ((s_stable_count_q[pin] + 1'b1) >= filter_count_i) begin
          s_input_filtered_d[pin] = s_input_sync[pin];
          s_stable_count_d[pin]   = 4'd0;
        end else begin
          s_stable_count_d[pin] = s_stable_count_q[pin] + 1'b1;
        end
      end
    end
  end

  dffr #(
      .DATA_WIDTH(PIN_NUM)
  ) u_input_filtered_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_input_filtered_d),
      .dat_o  (s_input_filtered_q)
  );
  for (genvar pin = 0; pin < PIN_NUM; pin++) begin : gen_stable_count
    dffr #(
        .DATA_WIDTH(4)
    ) u_stable_count_dffr (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .dat_i  (s_stable_count_d[pin]),
        .dat_o  (s_stable_count_q[pin])
    );
  end

  edge_det_sync #(
      .DATA_WIDTH(PIN_NUM)
  ) u_filtered_edge_det (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_input_filtered_q),
      .re_o   (s_input_rise),
      .fe_o   (s_input_fall)
  );

  assign data_in_o = s_input_filtered_q;
  assign user_gpio.di_i = s_input_filtered_q;
  assign intr_event_o = (s_input_rise & intr_rise_enable_i) |
                        (s_input_fall & intr_fall_enable_i) |
                        (s_input_filtered_q & intr_high_enable_i) |
                        (~s_input_filtered_q & intr_low_enable_i);

  for (genvar pin = 0; pin < PIN_NUM; pin++) begin : gen_output_mux
    assign s_alt_data[pin] = alt_select_i[pin] ? gpio.alt1_do_i[pin] : gpio.alt0_do_i[pin];
    assign s_alt_oe[pin] = alt_select_i[pin] ? gpio.alt1_oe_i[pin] : gpio.alt0_oe_i[pin];
    assign s_native_data[pin] = alt_enable_i[pin] ? s_alt_data[pin] : data_out_i[pin];
    assign s_native_oe[pin] = alt_enable_i[pin] ? s_alt_oe[pin] : output_enable_i[pin];
    assign s_selected_data[pin] = user_select_i[pin] ? user_gpio.do_o[pin] : s_native_data[pin];
    assign s_selected_oe[pin] = user_select_i[pin] ? user_gpio.oe_o[pin] : s_native_oe[pin];
    assign gpio.do_o[pin] = open_drain_i[pin] ? 1'b0 : s_selected_data[pin];
    assign gpio.oe_o[pin] = !user_handoff_i[pin] && s_selected_oe[pin] &&
                            !(open_drain_i[pin] && s_selected_data[pin]);
  end

  assign gpio.cs_o  = input_cmos_i;
  assign gpio.pu_o  = pull_up_i;
  assign gpio.pd_o  = pull_down_i;
  assign gpio.irq_o = irq_i;

endmodule
