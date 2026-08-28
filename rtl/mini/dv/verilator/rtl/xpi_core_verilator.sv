// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of the License at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.

import "DPI-C" function bit flash_fast_enabled();

module xpi_core_verilator (
    // verilog_format: off -- preserve reviewed port alignment
    input  logic                    clk_i,
    input  logic                    rst_n_i,
    input  logic                    start_i,
    input  logic                    abort_i,
    input  logic [              1:0] slot_i,
    input  logic                    mode3_i,
    input  logic [              7:0] clkdiv_i,
    input  logic [              7:0] cs_setup_i,
    input  logic [              7:0] cs_hold_i,
    input  logic [              7:0] cs_high_i,
    input  logic [             31:0] timeout_i,
    input  logic [             31:0] address_i,
    input  logic [             15:0] data_len_i,
    input  logic [             15:0] lut_i [0:7],
    input  logic                    tx_valid_i,
    output logic                    tx_ready_o,
    input  logic [              7:0] tx_data_i,
    output logic                    rx_valid_o,
    input  logic                    rx_ready_i,
    output logic [              7:0] rx_data_o,
    output logic                    busy_o,
    output logic                    done_o,
    output logic                    error_o,
    output xpi_pkg::xpi_error_e     error_code_o,
    output logic [              2:0] error_pc_o,
    output logic                    phy_byte_event_o,
    xpi_if.dut                      xpi
    // verilog_format: on
);

  import xpi_pkg::*;

  logic             s_fast_mode;
  logic             s_phy_tx_ready;
  logic             s_phy_rx_valid;
  logic       [7:0] s_phy_rx_data;
  logic             s_phy_busy;
  logic             s_phy_done;
  logic             s_phy_error;
  xpi_error_e       s_phy_error_code;
  logic       [2:0] s_phy_error_pc;
  logic             s_phy_byte_event;
  logic             s_fast_rx_valid;
  logic       [7:0] s_fast_rx_data;
  logic             s_fast_busy;
  logic             s_fast_done;
  logic             s_fast_error;
  xpi_error_e       s_fast_error_code;
  logic       [2:0] s_fast_error_pc;
  logic             s_fast_byte_event;

  initial begin
    s_fast_mode = flash_fast_enabled();
  end

  assign tx_ready_o       = s_fast_mode ? 1'b0 : s_phy_tx_ready;
  assign rx_valid_o       = s_fast_mode ? s_fast_rx_valid : s_phy_rx_valid;
  assign rx_data_o        = s_fast_mode ? s_fast_rx_data : s_phy_rx_data;
  assign busy_o           = s_fast_mode ? s_fast_busy : s_phy_busy;
  assign done_o           = s_fast_mode ? s_fast_done : s_phy_done;
  assign error_o          = s_fast_mode ? s_fast_error : s_phy_error;
  assign error_code_o     = s_fast_mode ? s_fast_error_code : s_phy_error_code;
  assign error_pc_o       = s_fast_mode ? s_fast_error_pc : s_phy_error_pc;
  assign phy_byte_event_o = s_fast_mode ? s_fast_byte_event : s_phy_byte_event;

  xpi_core u_xpi_core (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .start_i         (start_i && !s_fast_mode),
      .abort_i         (abort_i),
      .slot_i          (slot_i),
      .mode3_i         (mode3_i),
      .clkdiv_i        (clkdiv_i),
      .cs_setup_i      (cs_setup_i),
      .cs_hold_i       (cs_hold_i),
      .cs_high_i       (cs_high_i),
      .timeout_i       (timeout_i),
      .address_i       (address_i),
      .data_len_i      (data_len_i),
      .lut_i           (lut_i),
      .tx_valid_i      (tx_valid_i),
      .tx_ready_o      (s_phy_tx_ready),
      .tx_data_i       (tx_data_i),
      .rx_valid_o      (s_phy_rx_valid),
      .rx_ready_i      (rx_ready_i),
      .rx_data_o       (s_phy_rx_data),
      .busy_o          (s_phy_busy),
      .done_o          (s_phy_done),
      .error_o         (s_phy_error),
      .error_code_o    (s_phy_error_code),
      .error_pc_o      (s_phy_error_pc),
      .phy_byte_event_o(s_phy_byte_event),
      .xpi             (xpi)
  );

  xpi_fast_flash_model u_xpi_fast_flash_model (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .start_i         (start_i && s_fast_mode),
      .abort_i         (abort_i),
      .slot_i          (slot_i),
      .timeout_i       (timeout_i),
      .address_i       (address_i),
      .data_len_i      (data_len_i),
      .lut_i           (lut_i),
      .rx_valid_o      (s_fast_rx_valid),
      .rx_ready_i      (rx_ready_i),
      .rx_data_o       (s_fast_rx_data),
      .busy_o          (s_fast_busy),
      .done_o          (s_fast_done),
      .error_o         (s_fast_error),
      .error_code_o    (s_fast_error_code),
      .error_pc_o      (s_fast_error_pc),
      .phy_byte_event_o(s_fast_byte_event)
  );

endmodule
