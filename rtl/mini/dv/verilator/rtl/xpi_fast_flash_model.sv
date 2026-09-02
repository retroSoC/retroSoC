// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of the License at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.

module xpi_fast_flash_model (
    // verilog_format: off -- preserve reviewed port alignment
    input  logic                    clk_i,
    input  logic                    rst_n_i,
    input  logic                    start_i,
    input  logic                    abort_i,
    input  logic [              1:0] slot_i,
    input  logic [             31:0] timeout_i,
    input  logic [             31:0] address_i,
    input  logic [             15:0] data_len_i,
    input  logic [             15:0] lut_i [0:7],
    output logic                    rx_valid_o,
    input  logic                    rx_ready_i,
    output logic [              7:0] rx_data_o,
    output logic                    busy_o,
    output logic                    done_o,
    output logic                    error_o,
    output xpi_pkg::xpi_error_e     error_code_o,
    output logic [              2:0] error_pc_o,
    output logic                    phy_byte_event_o
    // verilog_format: on
);

  import xpi_pkg::*;

  typedef enum logic [1:0] {
    Idle,
    Setup,
    Read,
    Complete
  } xpi_fast_flash_state_e;

  logic [1:0] s_state_bits_q;
  xpi_fast_flash_state_e s_state_d, s_state_q;
  logic [31:0] s_address_d, s_address_q;
  logic [15:0] s_remaining_d, s_remaining_q;
  logic [31:0] s_timeout_count_d, s_timeout_count_q;
  logic s_rx_valid_d, s_rx_valid_q;
  logic [3:0] s_error_code_bits_q;
  xpi_error_e s_error_code_d, s_error_code_q;
  logic [2:0] s_error_pc_d, s_error_pc_q;

  logic s_sequence_supported;
  logic s_timeout_expired;
  logic s_read_enable;

  assign s_state_q = xpi_fast_flash_state_e'(s_state_bits_q);
  assign s_error_code_q = xpi_error_e'(s_error_code_bits_q);
  assign s_sequence_supported = (slot_i == 2'd0) && (lut_i[0] == xpi_instr(
      XpiInstrCommand, 2'd0, 8'hEB
  )) && (lut_i[1] == xpi_instr(
      XpiInstrAddress, 2'd2, 8'd24
  )) && (lut_i[2] == xpi_instr(
      XpiInstrMode, 2'd2, 8'hF0
  )) && (lut_i[3] == xpi_instr(
      XpiInstrDummy, 2'd0, 8'd4
  )) && (lut_i[4] == xpi_instr(
      XpiInstrReceive, 2'd2, 8'd0
  )) && (lut_i[5] == xpi_instr(
      XpiInstrStop, 2'd0, 8'd0
  )) && (lut_i[6] == xpi_instr(
      XpiInstrStop, 2'd0, 8'd0
  )) && (lut_i[7] == xpi_instr(
      XpiInstrStop, 2'd0, 8'd0
  ));
  assign s_timeout_expired = (timeout_i != 32'd0) && (s_timeout_count_q >= (timeout_i - 1'b1));
  assign s_read_enable = (s_state_q == Read) && (!s_rx_valid_q || rx_ready_i) &&
                         (s_remaining_q != 16'd0);

  assign rx_valid_o = (s_state_q == Read) && s_rx_valid_q;
  assign busy_o = (s_state_q == Setup) || (s_state_q == Read);
  assign done_o = s_state_q == Complete;
  assign error_o = done_o && (s_error_code_q != XpiErrorNone);
  assign error_code_o = s_error_code_q;
  assign error_pc_o = s_error_pc_q;
  assign phy_byte_event_o = rx_valid_o && rx_ready_i;

  flash_read_byte_binder u_flash_read_byte_binder (
      .clk_i  (clk_i),
      .rd_en_i(s_read_enable),
      .addr_i (s_address_q),
      .data_o (rx_data_o)
  );

  always_comb begin
    s_state_d         = s_state_q;
    s_address_d       = s_address_q;
    s_remaining_d     = s_remaining_q;
    s_timeout_count_d = busy_o ? s_timeout_count_q + 1'b1 : '0;
    s_rx_valid_d      = s_rx_valid_q;
    s_error_code_d    = s_error_code_q;
    s_error_pc_d      = s_error_pc_q;

    if (abort_i && busy_o) begin
      s_state_d      = Complete;
      s_rx_valid_d   = 1'b0;
      s_error_code_d = XpiErrorAborted;
      s_error_pc_d   = 3'd0;
    end else if (s_timeout_expired && busy_o) begin
      s_state_d      = Complete;
      s_rx_valid_d   = 1'b0;
      s_error_code_d = XpiErrorTimeout;
      s_error_pc_d   = 3'd0;
    end else begin
      unique case (s_state_q)
        Idle: begin
          if (start_i) begin
            s_state_d         = Setup;
            s_timeout_count_d = '0;
            s_rx_valid_d      = 1'b0;
            s_error_code_d    = XpiErrorNone;
            s_error_pc_d      = '0;
          end
        end

        Setup: begin
          if (!s_sequence_supported) begin
            s_state_d      = Complete;
            s_error_code_d = XpiErrorSequence;
            s_error_pc_d   = 3'd0;
          end else if (data_len_i == 16'd0) begin
            s_state_d = Complete;
          end else begin
            s_state_d     = Read;
            s_address_d   = address_i;
            s_remaining_d = data_len_i;
          end
        end

        Read: begin
          if (!s_rx_valid_q || rx_ready_i) begin
            if (s_remaining_q == 16'd0) begin
              s_state_d    = Complete;
              s_rx_valid_d = 1'b0;
            end else begin
              s_address_d   = s_address_q + 1'b1;
              s_remaining_d = s_remaining_q - 1'b1;
              s_rx_valid_d  = 1'b1;
            end
          end
        end

        Complete: begin
          s_state_d = Idle;
        end

        default: begin
          s_state_d      = Complete;
          s_rx_valid_d   = 1'b0;
          s_error_code_d = XpiErrorIllegal;
          s_error_pc_d   = 3'd0;
        end
      endcase
    end
  end

  dffrc #(
      .DATA_WIDTH(2),
      .RESET_VAL (Idle)
  ) u_state_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_address_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_address_d),
      .dat_o  (s_address_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_remaining_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_remaining_d),
      .dat_o  (s_remaining_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_timeout_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_timeout_count_d),
      .dat_o  (s_timeout_count_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_rx_valid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_valid_d),
      .dat_o  (s_rx_valid_q)
  );
  dffrc #(
      .DATA_WIDTH(4),
      .RESET_VAL (XpiErrorNone)
  ) u_error_code_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_error_code_d),
      .dat_o  (s_error_code_bits_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_error_pc_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_error_pc_d),
      .dat_o  (s_error_pc_q)
  );

endmodule
