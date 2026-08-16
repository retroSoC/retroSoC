// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

`include "gpio_define.svh"

module gpio_reg #(
    parameter int          PinNum        = 32,
    parameter logic [31:0] UserBaseAddr  = 32'h1000_0000,
    parameter logic [31:0] AdminBaseAddr = 32'h1001_4000,
    parameter bit          HasInputCmos  = 1'b0,
    parameter bit          HasPullUp     = 1'b0,
    parameter bit          HasPullDown   = 1'b0
) (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic              clk_i,
    input  logic              rst_n_i,
    apb4_if.slave             apb4,
    input  logic [PinNum-1:0] data_in_i,
    input  logic [PinNum-1:0] intr_event_i,
    output logic [PinNum-1:0] data_out_o,
    output logic [PinNum-1:0] output_enable_o,
    output logic [PinNum-1:0] open_drain_o,
    output logic [PinNum-1:0] input_cmos_o,
    output logic [PinNum-1:0] pull_up_o,
    output logic [PinNum-1:0] pull_down_o,
    output logic [PinNum-1:0] alt_enable_o,
    output logic [PinNum-1:0] alt_select_o,
    output logic [PinNum-1:0] user_select_o,
    output logic [PinNum-1:0] user_handoff_o,
    output logic [PinNum-1:0] filter_enable_o,
    output logic [15:0]       filter_div_o,
    output logic [3:0]        filter_count_o,
    output logic [PinNum-1:0] intr_rise_enable_o,
    output logic [PinNum-1:0] intr_fall_enable_o,
    output logic [PinNum-1:0] intr_high_enable_o,
    output logic [PinNum-1:0] intr_low_enable_o,
    output logic              irq_o
    // verilog_format: on
);

  localparam logic [31:0] IP_VERSION = 32'h0002_0000;
  localparam logic [31:0] CAPABILITY = 32'h007F_0000 | (32'(4) << 12) | (32'(2) << 8) | 32'(PinNum);
  localparam logic [31:0] PAD_CAPABILITY = {29'd0, HasPullDown, HasPullUp, HasInputCmos};

  logic s_req, s_write, s_req_accept;
  logic s_public_window, s_admin_window, s_aligned;
  logic [      11:0] s_offset;
  logic [      31:0] s_byte_mask;
  logic [      31:0] s_write_word;
  logic [PinNum-1:0] s_write_bits;
  logic              s_access_err;
  logic [31:0] s_apb4_rdata_d, s_apb4_rdata_q;
  logic s_apb4_ready_q;
  logic s_apb4_resp_err_d, s_apb4_resp_err_q;

  logic [PinNum-1:0] s_data_out_d, s_data_out_q;
  logic [PinNum-1:0] s_output_en_d, s_output_en_q;
  logic [PinNum-1:0] s_open_drain_d, s_open_drain_q;
  logic [PinNum-1:0] s_input_cmos_d, s_input_cmos_q;
  logic [PinNum-1:0] s_pull_up_d, s_pull_up_q;
  logic [PinNum-1:0] s_pull_down_d, s_pull_down_q;
  logic [PinNum-1:0] s_alt_en_d, s_alt_en_q;
  logic [PinNum-1:0] s_alt_sel_d, s_alt_sel_q;
  logic [PinNum-1:0] s_user_sel_d, s_user_sel_q;
  logic [PinNum-1:0] s_user_lock_d, s_user_lock_q;
  logic [PinNum-1:0] s_user_handoff_d, s_user_handoff_q;
  logic [PinNum-1:0] s_user_access_d, s_user_access_q;
  logic [PinNum-1:0] s_intr_rise_d, s_intr_rise_q;
  logic [PinNum-1:0] s_intr_fall_d, s_intr_fall_q;
  logic [PinNum-1:0] s_intr_high_d, s_intr_high_q;
  logic [PinNum-1:0] s_intr_low_d, s_intr_low_q;
  logic [PinNum-1:0] s_intr_en_d, s_intr_en_q;
  logic [PinNum-1:0] s_intr_state_d, s_intr_state_q;
  logic [PinNum-1:0] s_filter_en_d, s_filter_en_q;
  logic [PinNum-1:0] s_config_lock_d, s_config_lock_q;
  logic [15:0] s_filter_div_d, s_filter_div_q;
  logic [3:0] s_filter_count_d, s_filter_count_q;

  logic s_data_out_en, s_output_en_en, s_open_drain_en, s_input_cmos_en;
  logic s_pull_up_en, s_pull_down_en, s_alt_en_en, s_alt_sel_en;
  logic s_user_sel_en, s_user_lock_en, s_user_access_en;
  logic s_intr_rise_en, s_intr_fall_en, s_intr_high_en, s_intr_low_en;
  logic s_intr_en_en, s_intr_state_en, s_filter_en_en, s_config_lock_en;
  logic s_filter_div_en, s_filter_count_en;
  logic [PinNum-1:0] s_intr_clear, s_intr_test;

  function automatic logic [31:0] merge_wstrb(input logic [31:0] current, input logic [31:0] value,
                                              input logic [3:0] strobe);
    logic [31:0] mask;
    begin
      mask = {{8{strobe[3]}}, {8{strobe[2]}}, {8{strobe[1]}}, {8{strobe[0]}}};
      return (current & ~mask) | (value & mask);
    end
  endfunction

  function automatic logic [PinNum-1:0] merge_pins(
      input logic [PinNum-1:0] current, input logic [31:0] value, input logic [3:0] strobe);
    logic [31:0] current_word;
    logic [31:0] merged_word;
    begin
      current_word             = '0;
      current_word[PinNum-1:0] = current;
      merged_word              = merge_wstrb(current_word, value, strobe);
      return merged_word[PinNum-1:0];
    end
  endfunction

  function automatic logic [31:0] extend_pins(input logic [PinNum-1:0] value);
    logic [31:0] result;
    begin
      result             = '0;
      result[PinNum-1:0] = value;
      return result;
    end
  endfunction

  function automatic logic irq_config_valid(
      input logic [PinNum-1:0] rise, input logic [PinNum-1:0] fall, input logic [PinNum-1:0] high,
      input logic [PinNum-1:0] low);
    logic [PinNum-1:0] edge_mode;
    logic [PinNum-1:0] level_mode;
    begin
      edge_mode  = rise | fall;
      level_mode = high | low;
      return !((|(high & low)) || (|(edge_mode & level_mode)));
    end
  endfunction

`ifndef SYNTHESIS
  initial begin
    if ((PinNum < 1) || (PinNum > 32)) begin
      $fatal(1, "gpio_reg: PinNum must be between 1 and 32");
    end
    if ((UserBaseAddr[11:0] != 12'd0) || (AdminBaseAddr[11:0] != 12'd0) ||
        (UserBaseAddr == AdminBaseAddr)) begin
      $fatal(1, "gpio_reg: register window bases must be distinct and 4 KiB aligned");
    end
  end
`endif

  assign s_req = apb4.psel && apb4.penable && !s_apb4_ready_q;
  assign s_write = apb4.pwrite;
  assign s_req_accept = s_req;
  assign s_public_window = apb4.paddr[31:12] == UserBaseAddr[31:12];
  assign s_admin_window = apb4.paddr[31:12] == AdminBaseAddr[31:12];
  assign s_aligned = apb4.paddr[1:0] == 2'b00;
  assign s_offset = apb4.paddr[11:0];
  assign s_byte_mask = {
    {8{apb4.pstrb[3]}}, {8{apb4.pstrb[2]}}, {8{apb4.pstrb[1]}}, {8{apb4.pstrb[0]}}
  };
  assign s_write_word = apb4.pwdata & s_byte_mask;
  assign s_write_bits = s_write_word[PinNum-1:0];

  assign apb4.pready = s_apb4_ready_q;
  assign apb4.prdata = s_apb4_rdata_q;
  assign apb4.pslverr = s_apb4_resp_err_q;
  assign irq_o = |(s_intr_state_q & s_intr_en_q);

  always_comb begin
    s_access_err      = !s_aligned || !(s_public_window || s_admin_window);
    s_apb4_rdata_d    = '0;
    s_data_out_en     = 1'b0;
    s_output_en_en    = 1'b0;
    s_open_drain_en   = 1'b0;
    s_input_cmos_en   = 1'b0;
    s_pull_up_en      = 1'b0;
    s_pull_down_en    = 1'b0;
    s_alt_en_en       = 1'b0;
    s_alt_sel_en      = 1'b0;
    s_user_sel_en     = 1'b0;
    s_user_lock_en    = 1'b0;
    s_user_access_en  = 1'b0;
    s_intr_rise_en    = 1'b0;
    s_intr_fall_en    = 1'b0;
    s_intr_high_en    = 1'b0;
    s_intr_low_en     = 1'b0;
    s_intr_en_en      = 1'b0;
    s_filter_en_en    = 1'b0;
    s_config_lock_en  = 1'b0;
    s_filter_div_en   = 1'b0;
    s_filter_count_en = 1'b0;
    s_intr_clear      = '0;
    s_intr_test       = '0;

    s_data_out_d      = s_data_out_q;
    s_output_en_d     = s_output_en_q;
    s_open_drain_d    = s_open_drain_q;
    s_input_cmos_d    = s_input_cmos_q;
    s_pull_up_d       = s_pull_up_q;
    s_pull_down_d     = s_pull_down_q;
    s_alt_en_d        = s_alt_en_q;
    s_alt_sel_d       = s_alt_sel_q;
    s_user_sel_d      = s_user_sel_q;
    s_user_lock_d     = s_user_lock_q;
    s_user_access_d   = s_user_access_q;
    s_intr_rise_d     = s_intr_rise_q;
    s_intr_fall_d     = s_intr_fall_q;
    s_intr_high_d     = s_intr_high_q;
    s_intr_low_d      = s_intr_low_q;
    s_intr_en_d       = s_intr_en_q;
    s_filter_en_d     = s_filter_en_q;
    s_config_lock_d   = s_config_lock_q;
    s_filter_div_d    = s_filter_div_q;
    s_filter_count_d  = s_filter_count_q;

    if (s_req && !s_access_err) begin
      if (s_public_window) begin
        if (s_write) begin
          unique case (s_offset)
            `APB4_GPIO_USER_DATA_OUT: begin
              s_data_out_en = 1'b1;
              s_data_out_d = (s_data_out_q & ~s_user_access_q) |
                  (merge_pins(s_data_out_q, apb4.pwdata, apb4.pstrb) & s_user_access_q);
            end
            `APB4_GPIO_USER_OUT_SET: begin
              s_data_out_en = 1'b1;
              s_data_out_d  = s_data_out_q | (s_write_bits & s_user_access_q);
            end
            `APB4_GPIO_USER_OUT_CLEAR: begin
              s_data_out_en = 1'b1;
              s_data_out_d  = s_data_out_q & ~(s_write_bits & s_user_access_q);
            end
            `APB4_GPIO_USER_OUT_TOGGLE: begin
              s_data_out_en = 1'b1;
              s_data_out_d  = s_data_out_q ^ (s_write_bits & s_user_access_q);
            end
            `APB4_GPIO_USER_INTR_STATE: begin
              s_intr_clear = s_write_bits & s_user_access_q;
            end
            `APB4_GPIO_USER_INTR_ENABLE: begin
              s_intr_en_en = 1'b1;
              s_intr_en_d = (s_intr_en_q & ~s_user_access_q) |
                  (merge_pins(s_intr_en_q, apb4.pwdata, apb4.pstrb) & s_user_access_q);
            end
            `APB4_GPIO_USER_INTR_ENABLE_SET: begin
              s_intr_en_en = 1'b1;
              s_intr_en_d  = s_intr_en_q | (s_write_bits & s_user_access_q);
            end
            `APB4_GPIO_USER_INTR_ENABLE_CLEAR: begin
              s_intr_en_en = 1'b1;
              s_intr_en_d  = s_intr_en_q & ~(s_write_bits & s_user_access_q);
            end
            default: s_access_err = 1'b1;
          endcase
        end else begin
          unique case (s_offset)
            `APB4_GPIO_USER_DATA_IN: s_apb4_rdata_d = extend_pins(data_in_i & s_user_access_q);
            `APB4_GPIO_USER_DATA_OUT: s_apb4_rdata_d = extend_pins(s_data_out_q & s_user_access_q);
            `APB4_GPIO_USER_INTR_STATE:
            s_apb4_rdata_d = extend_pins(s_intr_state_q & s_user_access_q);
            `APB4_GPIO_USER_INTR_STATUS:
            s_apb4_rdata_d = extend_pins(s_intr_state_q & s_intr_en_q & s_user_access_q);
            `APB4_GPIO_USER_INTR_ENABLE:
            s_apb4_rdata_d = extend_pins(s_intr_en_q & s_user_access_q);
            `APB4_GPIO_IP_VERSION: s_apb4_rdata_d = IP_VERSION;
            `APB4_GPIO_CAPABILITY: s_apb4_rdata_d = CAPABILITY;
            default: s_access_err = 1'b1;
          endcase
        end
      end else if (s_write) begin
        unique case (s_offset)
          `APB4_GPIO_ADMIN_DATA_OUT: begin
            s_data_out_en = 1'b1;
            s_data_out_d  = merge_pins(s_data_out_q, apb4.pwdata, apb4.pstrb);
          end
          `APB4_GPIO_ADMIN_OUT_SET: begin
            s_data_out_en = 1'b1;
            s_data_out_d  = s_data_out_q | s_write_bits;
          end
          `APB4_GPIO_ADMIN_OUT_CLEAR: begin
            s_data_out_en = 1'b1;
            s_data_out_d  = s_data_out_q & ~s_write_bits;
          end
          `APB4_GPIO_ADMIN_OUT_TOGGLE: begin
            s_data_out_en = 1'b1;
            s_data_out_d  = s_data_out_q ^ s_write_bits;
          end
          `APB4_GPIO_ADMIN_OUTPUT_ENABLE,
          `APB4_GPIO_ADMIN_OE_SET,
          `APB4_GPIO_ADMIN_OE_CLEAR,
          `APB4_GPIO_ADMIN_OE_TOGGLE: begin
            if (s_offset == `APB4_GPIO_ADMIN_OUTPUT_ENABLE) begin
              s_output_en_d = merge_pins(s_output_en_q, apb4.pwdata, apb4.pstrb);
            end else if (s_offset == `APB4_GPIO_ADMIN_OE_SET) begin
              s_output_en_d = s_output_en_q | s_write_bits;
            end else if (s_offset == `APB4_GPIO_ADMIN_OE_CLEAR) begin
              s_output_en_d = s_output_en_q & ~s_write_bits;
            end else begin
              s_output_en_d = s_output_en_q ^ s_write_bits;
            end
            if (|((s_output_en_d ^ s_output_en_q) & s_config_lock_q)) begin
              s_access_err = 1'b1;
            end else s_output_en_en = 1'b1;
          end
          `APB4_GPIO_ADMIN_OPEN_DRAIN: begin
            s_open_drain_d = merge_pins(s_open_drain_q, apb4.pwdata, apb4.pstrb);
            if (|((s_open_drain_d ^ s_open_drain_q) & s_config_lock_q)) s_access_err = 1'b1;
            else s_open_drain_en = 1'b1;
          end
          `APB4_GPIO_ADMIN_INPUT_CMOS: begin
            s_input_cmos_d = merge_pins(s_input_cmos_q, apb4.pwdata, apb4.pstrb);
            if ((!HasInputCmos && (|s_input_cmos_d)) ||
                (|((s_input_cmos_d ^ s_input_cmos_q) & s_config_lock_q))) begin
              s_access_err = 1'b1;
            end else s_input_cmos_en = 1'b1;
          end
          `APB4_GPIO_ADMIN_PULL_UP: begin
            s_pull_up_d = merge_pins(s_pull_up_q, apb4.pwdata, apb4.pstrb);
            if ((!HasPullUp && (|s_pull_up_d)) || (|(s_pull_up_d & s_pull_down_q)) ||
                (|((s_pull_up_d ^ s_pull_up_q) & s_config_lock_q))) begin
              s_access_err = 1'b1;
            end else s_pull_up_en = 1'b1;
          end
          `APB4_GPIO_ADMIN_PULL_DOWN: begin
            s_pull_down_d = merge_pins(s_pull_down_q, apb4.pwdata, apb4.pstrb);
            if ((!HasPullDown && (|s_pull_down_d)) || (|(s_pull_down_d & s_pull_up_q)) ||
                (|((s_pull_down_d ^ s_pull_down_q) & s_config_lock_q))) begin
              s_access_err = 1'b1;
            end else s_pull_down_en = 1'b1;
          end
          `APB4_GPIO_ADMIN_ALT_ENABLE: begin
            s_alt_en_d = merge_pins(s_alt_en_q, apb4.pwdata, apb4.pstrb);
            if (|((s_alt_en_d ^ s_alt_en_q) & s_config_lock_q)) s_access_err = 1'b1;
            else s_alt_en_en = 1'b1;
          end
          `APB4_GPIO_ADMIN_ALT_SELECT: begin
            s_alt_sel_d = merge_pins(s_alt_sel_q, apb4.pwdata, apb4.pstrb);
            if (|((s_alt_sel_d ^ s_alt_sel_q) & s_config_lock_q)) s_access_err = 1'b1;
            else s_alt_sel_en = 1'b1;
          end
          `APB4_GPIO_ADMIN_USER_SELECT: begin
            s_user_sel_d = merge_pins(s_user_sel_q, apb4.pwdata, apb4.pstrb);
            if (|((s_user_sel_d ^ s_user_sel_q) & s_user_lock_q)) s_access_err = 1'b1;
            else s_user_sel_en = 1'b1;
          end
          `APB4_GPIO_ADMIN_USER_LOCK: begin
            s_user_lock_en = 1'b1;
            s_user_lock_d  = s_user_lock_q | s_write_bits;
          end
          `APB4_GPIO_ADMIN_USER_ACCESS_MASK: begin
            s_user_access_d = merge_pins(s_user_access_q, apb4.pwdata, apb4.pstrb);
            if (|((s_user_access_d ^ s_user_access_q) & s_config_lock_q)) s_access_err = 1'b1;
            else s_user_access_en = 1'b1;
          end
          `APB4_GPIO_ADMIN_INTR_RISE_ENABLE,
          `APB4_GPIO_ADMIN_INTR_FALL_ENABLE,
          `APB4_GPIO_ADMIN_INTR_HIGH_ENABLE,
          `APB4_GPIO_ADMIN_INTR_LOW_ENABLE: begin
            if (s_offset == `APB4_GPIO_ADMIN_INTR_RISE_ENABLE) begin
              s_intr_rise_d = merge_pins(s_intr_rise_q, apb4.pwdata, apb4.pstrb);
            end else if (s_offset == `APB4_GPIO_ADMIN_INTR_FALL_ENABLE) begin
              s_intr_fall_d = merge_pins(s_intr_fall_q, apb4.pwdata, apb4.pstrb);
            end else if (s_offset == `APB4_GPIO_ADMIN_INTR_HIGH_ENABLE) begin
              s_intr_high_d = merge_pins(s_intr_high_q, apb4.pwdata, apb4.pstrb);
            end else begin
              s_intr_low_d = merge_pins(s_intr_low_q, apb4.pwdata, apb4.pstrb);
            end
            if (!irq_config_valid(
                    s_intr_rise_d, s_intr_fall_d, s_intr_high_d, s_intr_low_d
                ) || (|(((s_intr_rise_d ^ s_intr_rise_q) | (s_intr_fall_d ^ s_intr_fall_q) |
                         (s_intr_high_d ^ s_intr_high_q) | (s_intr_low_d ^ s_intr_low_q)) &
                        s_config_lock_q))) begin
              s_access_err = 1'b1;
            end else begin
              s_intr_rise_en = s_offset == `APB4_GPIO_ADMIN_INTR_RISE_ENABLE;
              s_intr_fall_en = s_offset == `APB4_GPIO_ADMIN_INTR_FALL_ENABLE;
              s_intr_high_en = s_offset == `APB4_GPIO_ADMIN_INTR_HIGH_ENABLE;
              s_intr_low_en  = s_offset == `APB4_GPIO_ADMIN_INTR_LOW_ENABLE;
            end
          end
          `APB4_GPIO_ADMIN_INTR_ENABLE: begin
            s_intr_en_en = 1'b1;
            s_intr_en_d  = merge_pins(s_intr_en_q, apb4.pwdata, apb4.pstrb);
          end
          `APB4_GPIO_ADMIN_INTR_STATE: s_intr_clear = s_write_bits;
          `APB4_GPIO_ADMIN_INTR_TEST:  s_intr_test = s_write_bits;
          `APB4_GPIO_ADMIN_FILTER_ENABLE: begin
            s_filter_en_d = merge_pins(s_filter_en_q, apb4.pwdata, apb4.pstrb);
            if (((|s_filter_en_d) && (s_filter_count_q == 4'd0)) ||
                (|((s_filter_en_d ^ s_filter_en_q) & s_config_lock_q))) begin
              s_access_err = 1'b1;
            end else s_filter_en_en = 1'b1;
          end
          `APB4_GPIO_ADMIN_FILTER_DIV: begin
            if (|s_filter_en_q) begin
              s_access_err = 1'b1;
            end else begin
              s_apb4_rdata_d = merge_wstrb({16'd0, s_filter_div_q}, apb4.pwdata, apb4.pstrb);
              if (|s_apb4_rdata_d[31:16]) s_access_err = 1'b1;
              else begin
                s_filter_div_en = 1'b1;
                s_filter_div_d  = s_apb4_rdata_d[15:0];
              end
            end
          end
          `APB4_GPIO_ADMIN_FILTER_COUNT: begin
            if (|s_filter_en_q) begin
              s_access_err = 1'b1;
            end else begin
              s_apb4_rdata_d = merge_wstrb({28'd0, s_filter_count_q}, apb4.pwdata, apb4.pstrb);
              if ((|s_apb4_rdata_d[31:4]) || (s_apb4_rdata_d[3:0] == 4'd0)) begin
                s_access_err = 1'b1;
              end else begin
                s_filter_count_en = 1'b1;
                s_filter_count_d  = s_apb4_rdata_d[3:0];
              end
            end
          end
          `APB4_GPIO_ADMIN_CONFIG_LOCK: begin
            s_config_lock_en = 1'b1;
            s_config_lock_d  = s_config_lock_q | s_write_bits;
          end
          default:                     s_access_err = 1'b1;
        endcase
      end else begin
        unique case (s_offset)
          `APB4_GPIO_ADMIN_DATA_IN: s_apb4_rdata_d = extend_pins(data_in_i);
          `APB4_GPIO_ADMIN_DATA_OUT: s_apb4_rdata_d = extend_pins(s_data_out_q);
          `APB4_GPIO_ADMIN_OUTPUT_ENABLE: s_apb4_rdata_d = extend_pins(s_output_en_q);
          `APB4_GPIO_ADMIN_OPEN_DRAIN: s_apb4_rdata_d = extend_pins(s_open_drain_q);
          `APB4_GPIO_ADMIN_INPUT_CMOS: s_apb4_rdata_d = extend_pins(s_input_cmos_q);
          `APB4_GPIO_ADMIN_PULL_UP: s_apb4_rdata_d = extend_pins(s_pull_up_q);
          `APB4_GPIO_ADMIN_PULL_DOWN: s_apb4_rdata_d = extend_pins(s_pull_down_q);
          `APB4_GPIO_ADMIN_ALT_ENABLE: s_apb4_rdata_d = extend_pins(s_alt_en_q);
          `APB4_GPIO_ADMIN_ALT_SELECT: s_apb4_rdata_d = extend_pins(s_alt_sel_q);
          `APB4_GPIO_ADMIN_USER_SELECT: s_apb4_rdata_d = extend_pins(s_user_sel_q);
          `APB4_GPIO_ADMIN_USER_LOCK: s_apb4_rdata_d = extend_pins(s_user_lock_q);
          `APB4_GPIO_ADMIN_USER_STATUS:
          s_apb4_rdata_d = extend_pins(s_user_sel_q & ~s_user_handoff_q);
          `APB4_GPIO_ADMIN_USER_ACCESS_MASK: s_apb4_rdata_d = extend_pins(s_user_access_q);
          `APB4_GPIO_ADMIN_INTR_RISE_ENABLE: s_apb4_rdata_d = extend_pins(s_intr_rise_q);
          `APB4_GPIO_ADMIN_INTR_FALL_ENABLE: s_apb4_rdata_d = extend_pins(s_intr_fall_q);
          `APB4_GPIO_ADMIN_INTR_HIGH_ENABLE: s_apb4_rdata_d = extend_pins(s_intr_high_q);
          `APB4_GPIO_ADMIN_INTR_LOW_ENABLE: s_apb4_rdata_d = extend_pins(s_intr_low_q);
          `APB4_GPIO_ADMIN_INTR_ENABLE: s_apb4_rdata_d = extend_pins(s_intr_en_q);
          `APB4_GPIO_ADMIN_INTR_STATE: s_apb4_rdata_d = extend_pins(s_intr_state_q);
          `APB4_GPIO_ADMIN_INTR_STATUS: s_apb4_rdata_d = extend_pins(s_intr_state_q & s_intr_en_q);
          `APB4_GPIO_ADMIN_FILTER_ENABLE: s_apb4_rdata_d = extend_pins(s_filter_en_q);
          `APB4_GPIO_ADMIN_FILTER_DIV: s_apb4_rdata_d = {16'd0, s_filter_div_q};
          `APB4_GPIO_ADMIN_FILTER_COUNT: s_apb4_rdata_d = {28'd0, s_filter_count_q};
          `APB4_GPIO_ADMIN_CONFIG_LOCK: s_apb4_rdata_d = extend_pins(s_config_lock_q);
          `APB4_GPIO_PAD_CAPABILITY: s_apb4_rdata_d = PAD_CAPABILITY;
          `APB4_GPIO_IP_VERSION: s_apb4_rdata_d = IP_VERSION;
          `APB4_GPIO_CAPABILITY: s_apb4_rdata_d = CAPABILITY;
          default: s_access_err = 1'b1;
        endcase
      end
    end
  end

  assign s_user_handoff_d = s_user_sel_en ? (s_user_sel_d ^ s_user_sel_q) : '0;
  assign s_intr_state_d   = (s_intr_state_q & ~s_intr_clear) | intr_event_i | s_intr_test;
  assign s_intr_state_en  = (|s_intr_clear) || (|intr_event_i) || (|s_intr_test);

  dffer #(
      .DATA_WIDTH(PinNum)
  ) u_data_out_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_data_out_en),
      .dat_i  (s_data_out_d),
      .dat_o  (s_data_out_q)
  );
  dffer #(
      .DATA_WIDTH(PinNum)
  ) u_output_enable_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_output_en_en),
      .dat_i  (s_output_en_d),
      .dat_o  (s_output_en_q)
  );
  dffer #(
      .DATA_WIDTH(PinNum)
  ) u_open_drain_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_open_drain_en),
      .dat_i  (s_open_drain_d),
      .dat_o  (s_open_drain_q)
  );
  dffer #(
      .DATA_WIDTH(PinNum)
  ) u_input_cmos_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_input_cmos_en),
      .dat_i  (s_input_cmos_d),
      .dat_o  (s_input_cmos_q)
  );
  dffer #(
      .DATA_WIDTH(PinNum)
  ) u_pull_up_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_pull_up_en),
      .dat_i  (s_pull_up_d),
      .dat_o  (s_pull_up_q)
  );
  dffer #(
      .DATA_WIDTH(PinNum)
  ) u_pull_down_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_pull_down_en),
      .dat_i  (s_pull_down_d),
      .dat_o  (s_pull_down_q)
  );
  dffer #(
      .DATA_WIDTH(PinNum)
  ) u_alt_enable_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_alt_en_en),
      .dat_i  (s_alt_en_d),
      .dat_o  (s_alt_en_q)
  );
  dffer #(
      .DATA_WIDTH(PinNum)
  ) u_alt_select_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_alt_sel_en),
      .dat_i  (s_alt_sel_d),
      .dat_o  (s_alt_sel_q)
  );
  dffer #(
      .DATA_WIDTH(PinNum)
  ) u_user_select_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_user_sel_en),
      .dat_i  (s_user_sel_d),
      .dat_o  (s_user_sel_q)
  );
  dffer #(
      .DATA_WIDTH(PinNum)
  ) u_user_lock_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_user_lock_en),
      .dat_i  (s_user_lock_d),
      .dat_o  (s_user_lock_q)
  );
  dffer #(
      .DATA_WIDTH(PinNum)
  ) u_user_access_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_user_access_en),
      .dat_i  (s_user_access_d),
      .dat_o  (s_user_access_q)
  );
  dffer #(
      .DATA_WIDTH(PinNum)
  ) u_intr_rise_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_intr_rise_en),
      .dat_i  (s_intr_rise_d),
      .dat_o  (s_intr_rise_q)
  );
  dffer #(
      .DATA_WIDTH(PinNum)
  ) u_intr_fall_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_intr_fall_en),
      .dat_i  (s_intr_fall_d),
      .dat_o  (s_intr_fall_q)
  );
  dffer #(
      .DATA_WIDTH(PinNum)
  ) u_intr_high_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_intr_high_en),
      .dat_i  (s_intr_high_d),
      .dat_o  (s_intr_high_q)
  );
  dffer #(
      .DATA_WIDTH(PinNum)
  ) u_intr_low_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_intr_low_en),
      .dat_i  (s_intr_low_d),
      .dat_o  (s_intr_low_q)
  );
  dffer #(
      .DATA_WIDTH(PinNum)
  ) u_intr_enable_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_intr_en_en),
      .dat_i  (s_intr_en_d),
      .dat_o  (s_intr_en_q)
  );
  dffer #(
      .DATA_WIDTH(PinNum)
  ) u_intr_state_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_intr_state_en),
      .dat_i  (s_intr_state_d),
      .dat_o  (s_intr_state_q)
  );
  dffer #(
      .DATA_WIDTH(PinNum)
  ) u_filter_enable_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_filter_en_en),
      .dat_i  (s_filter_en_d),
      .dat_o  (s_filter_en_q)
  );
  dffer #(
      .DATA_WIDTH(PinNum)
  ) u_config_lock_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_config_lock_en),
      .dat_i  (s_config_lock_d),
      .dat_o  (s_config_lock_q)
  );
  dffer #(
      .DATA_WIDTH(16)
  ) u_filter_div_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_filter_div_en),
      .dat_i  (s_filter_div_d),
      .dat_o  (s_filter_div_q)
  );
  dffer #(
      .DATA_WIDTH(4)
  ) u_filter_count_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_filter_count_en),
      .dat_i  (s_filter_count_d),
      .dat_o  (s_filter_count_q)
  );

  dffr #(
      .DATA_WIDTH(PinNum)
  ) u_user_handoff_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_user_handoff_d),
      .dat_o  (s_user_handoff_q)
  );

  dffr #(
      .DATA_WIDTH(1)
  ) u_apb4_ready_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_req_accept),
      .dat_o  (s_apb4_ready_q)
  );
  assign s_apb4_resp_err_d = s_access_err;
  dffer #(
      .DATA_WIDTH(1)
  ) u_apb4_resp_err_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_req_accept),
      .dat_i  (s_apb4_resp_err_d),
      .dat_o  (s_apb4_resp_err_q)
  );
  dffer #(
      .DATA_WIDTH(32)
  ) u_apb4_rdata_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_req_accept),
      .dat_i  (s_apb4_rdata_d),
      .dat_o  (s_apb4_rdata_q)
  );

  assign data_out_o         = s_data_out_q;
  assign output_enable_o    = s_output_en_q;
  assign open_drain_o       = s_open_drain_q;
  assign input_cmos_o       = s_input_cmos_q;
  assign pull_up_o          = s_pull_up_q;
  assign pull_down_o        = s_pull_down_q;
  assign alt_enable_o       = s_alt_en_q;
  assign alt_select_o       = s_alt_sel_q;
  assign user_select_o      = s_user_sel_q;
  assign user_handoff_o     = s_user_handoff_q;
  assign filter_enable_o    = s_filter_en_q;
  assign filter_div_o       = s_filter_div_q;
  assign filter_count_o     = s_filter_count_q;
  assign intr_rise_enable_o = s_intr_rise_q;
  assign intr_fall_enable_o = s_intr_fall_q;
  assign intr_high_enable_o = s_intr_high_q;
  assign intr_low_enable_o  = s_intr_low_q;
endmodule
