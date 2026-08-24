// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Armin Berger <bergerar@ethz.ch>
// Stephan Keck <kecks@ethz.ch>
// Thomas Benz <tbenz@iis.ee.ethz.ch>
// Paul Scheffler <paulsc@iis.ee.ethz.ch>
//
// Adapted from PULP Platform HyperBus v0.0.4 (src/hyperbus_phy.sv) at commit
// 80de8df600edc5d7956a94c9d42f911d6e61efd7.
// Modified by retroSoC for OPI/xSPI, single-clock HyperBus, project-local
// interfaces and primitives, reset conventions, and technology mapping.
//
// -- Adaptable modifications are redistributed under compatible License --
//
// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module opipsram_phy (
    // verilog_format: off -- preserve reviewed port alignment
    input  logic        clk_phy_i,
    input  logic        rst_phy_n_i,
    input  logic        cmd_valid_i,
    output logic        cmd_ready_o,
    input  logic        cmd_profile_hyper_i,
    input  logic        cmd_write_i,
    input  logic        cmd_indirect_register_i,
    input  logic [31:0] cmd_addr_i,
    input  logic [3:0]  cmd_len_i,
    input  logic [63:0] cmd_wdata_i,
    input  logic [15:0] cmd_opi_cmd_i,
    input  logic        cmd_opi_width16_i,
    input  logic [31:0] cmd_opi_timing_i,
    input  logic [31:0] cmd_hyper_timing_i,
    input  logic [31:0] cmd_cs_timing_i,
    input  logic [31:0] cmd_clk_config_i,
    input  logic [7:0]  cmd_rx_delay_i,
    input  logic [31:0] cmd_timeout_i,
    input  logic        abort_i,
    output logic        rsp_valid_o,
    input  logic        rsp_ready_i,
    output logic        rsp_error_o,
    output logic [63:0] rsp_rdata_o,
    output logic        ck_o,
    output logic        cs_n_o,
    output logic [7:0]  dq_oe_o,
    input  logic [7:0]  dq_i,
    output logic [7:0]  dq_o,
    output logic        rwds_oe_o,
    input  logic        rwds_i,
    output logic        rwds_o
    // verilog_format: on
);

  typedef enum logic [3:0] {
    PhyIdle     = 4'd0,
    PhySetup    = 4'd1,
    PhyCommand  = 4'd2,
    PhyAddress  = 4'd3,
    PhyWait     = 4'd4,
    PhyHyperCa  = 4'd5,
    PhyData     = 4'd6,
    PhyPostData = 4'd7,
    PhyHold     = 4'd8,
    PhyHigh     = 4'd9
  } opipsram_phy_state_e;

  logic [3:0] s_state_bits_q;
  opipsram_phy_state_e s_state_d, s_state_q;
  logic s_profile_hyper_d, s_profile_hyper_q;
  logic s_write_d, s_write_q;
  logic s_indirect_register_d, s_indirect_register_q;
  logic [31:0] s_addr_d, s_addr_q;
  logic [3:0] s_len_d, s_len_q;
  logic [63:0] s_wdata_d, s_wdata_q;
  logic [15:0] s_opi_cmd_d, s_opi_cmd_q;
  logic s_opi_width16_d, s_opi_width16_q;
  logic [31:0] s_opi_timing_d, s_opi_timing_q;
  logic [31:0] s_hyper_timing_d, s_hyper_timing_q;
  logic [31:0] s_cs_timing_d, s_cs_timing_q;
  logic [31:0] s_clk_config_d, s_clk_config_q;
  logic [7:0] s_rx_delay_d, s_rx_delay_q;
  logic [31:0] s_timeout_d, s_timeout_q;
  logic [31:0] s_phase_count_d, s_phase_count_q;
  logic [31:0] s_timeout_count_d, s_timeout_count_q;
  logic [9:0] s_units_d, s_units_q;
  logic [3:0] s_data_index_d, s_data_index_q;
  logic [4:0] s_rx_accept_count_d, s_rx_accept_count_q;
  logic [63:0] s_shift_d, s_shift_q;
  logic [63:0] s_rdata_d, s_rdata_q;
  logic s_ck_d, s_ck_q;
  logic s_cs_n_d, s_cs_n_q;
  logic s_cs_n_out_q;
  logic s_rsp_valid_d, s_rsp_valid_q;
  logic s_rsp_err_d, s_rsp_err_q;
  logic s_rsp_seen_d, s_rsp_seen_q;
  logic [31:0] s_div_count_d, s_div_count_q;

  logic [47:0] s_hyper_ca;
  logic [ 1:0] s_opi_cmd_count;
  logic [ 7:0] s_opi_cmd_first;
  logic [ 7:0] s_opi_cmd_second;
  logic [ 2:0] s_opi_addr_bytes;
  logic [31:0] s_opi_addr_shift;
  logic [ 9:0] s_opi_wait_phases;
  logic [ 9:0] s_hyper_wait_phases;
  logic        s_opi_dqs_read;
  logic        s_opi_dqs_write;
  logic        s_phase_tick;
  logic [15:0] s_phase_div;
  logic        s_tx_enable;
  logic [ 7:0] s_tx_data;
  logic        s_tx_rwds_enable;
  logic        s_tx_rwds_value;
  logic [ 9:0] s_data_phase_count;
  logic        s_rx_flush;
  logic        s_rx_enable;
  logic        s_rx_byte_valid;
  logic        s_rx_byte_ready;
  logic [ 7:0] s_rx_byte;
  logic        s_rx_overflow;
  logic        s_rwds_delayed;
  logic        s_rx_strobe;

  assign s_state_q = opipsram_phy_state_e'(s_state_bits_q);

  function automatic logic [63:0] pack_write_data(input logic [63:0] data);
    logic [63:0] s_packed;
    begin
      s_packed = {
        data[7:0],
        data[15:8],
        data[23:16],
        data[31:24],
        data[39:32],
        data[47:40],
        data[55:48],
        data[63:56]
      };
      return s_packed;
    end
  endfunction

  function automatic logic [7:0] hyper_write_byte(
      input logic [63:0] data, input logic [3:0] physical_index, input logic start_odd);
    logic [4:0] payload_index;
    begin
      if ({1'b0, physical_index} < {4'd0, start_odd}) return 8'd0;
      payload_index = {1'b0, physical_index} - {4'd0, start_odd};
      if (payload_index >= 5'd8) return 8'd0;
      return data[(payload_index*8)+:8];
    end
  endfunction

  function automatic logic [9:0] data_phase_count(input logic hyper, input logic [3:0] len,
                                                  input logic start_odd);
    logic [4:0] hyper_bytes;
    begin
      if (hyper) begin
        hyper_bytes = {1'b0, len} + {4'd0, start_odd};
        return {5'd0, ((hyper_bytes + 5'd1) & 5'h1E)};
      end
      return {6'd0, len};
    end
  endfunction

  assign s_phase_div = (s_clk_config_q[15:0] == 16'd0) ? 16'd1 : s_clk_config_q[15:0];
  assign s_phase_tick = s_div_count_q == ({16'd0, s_phase_div} - 32'd1);
  assign s_tx_enable = (s_state_q == PhyCommand) || (s_state_q == PhyAddress) ||
      (s_state_q == PhyHyperCa) || ((s_state_q == PhyData) && s_write_q);
  assign s_tx_data = ((s_state_q == PhyData) && s_profile_hyper_q) ? hyper_write_byte(
      s_wdata_q, s_data_index_q, s_addr_q[0]
  ) : s_shift_q[63:56];
  assign s_tx_rwds_enable = (s_state_q == PhyData) && s_write_q &&
      (s_profile_hyper_q ? !s_indirect_register_q : s_opi_dqs_write);
  assign s_tx_rwds_value = s_profile_hyper_q ?
      (({1'b0, s_data_index_q} < {4'd0, s_addr_q[0]}) ||
       ({1'b0, s_data_index_q} >= ({4'd0, s_addr_q[0]} + {1'b0, s_len_q}))) :
      s_ck_q;
  assign s_data_phase_count = data_phase_count(s_profile_hyper_q, s_len_q, s_addr_q[0]);
  assign s_rx_flush = !s_rx_enable;
  assign s_rx_enable = (s_state_q == PhyData) && !s_write_q;
  assign s_rx_byte_ready = s_rx_enable && !s_rsp_err_q;
  assign s_rx_strobe = (s_profile_hyper_q || s_opi_dqs_read) ? rwds_i : s_ck_q;
  assign cmd_ready_o = s_state_q == PhyIdle;
  assign rsp_valid_o = s_rsp_valid_q;
  assign rsp_error_o = s_rsp_err_q;
  assign rsp_rdata_o = s_rdata_q;
  assign ck_o = s_cs_n_out_q ? 1'b0 : s_ck_q;
  assign cs_n_o = s_cs_n_out_q;

  opipsram_protocol u_protocol (
      .write_i            (s_write_q),
      .indirect_register_i(s_indirect_register_q),
      .addr_i             (s_addr_q),
      .opi_cmd_i          (s_opi_cmd_q),
      .opi_width16_i      (s_opi_width16_q),
      .opi_timing_i       (s_opi_timing_q),
      .hyper_timing_i     (s_hyper_timing_q),
      .hyper_ca_o         (s_hyper_ca),
      .opi_cmd_count_o    (s_opi_cmd_count),
      .opi_cmd_first_o    (s_opi_cmd_first),
      .opi_cmd_second_o   (s_opi_cmd_second),
      .opi_addr_bytes_o   (s_opi_addr_bytes),
      .opi_addr_shift_o   (s_opi_addr_shift),
      .opi_wait_phases_o  (s_opi_wait_phases),
      .hyper_wait_phases_o(s_hyper_wait_phases),
      .opi_dqs_read_o     (s_opi_dqs_read),
      .opi_dqs_write_o    (s_opi_dqs_write)
  );

  opipsram_trx u_trx (
      .clk_phy_i       (clk_phy_i),
      .rst_phy_n_i     (rst_phy_n_i),
      .rx_flush_i      (s_rx_flush),
      .rx_enable_i     (s_rx_enable),
      .rx_delay_i      (s_rx_delay_q),
      .cs_n_i          (s_cs_n_out_q),
      .dq_i            (dq_i),
      .rwds_i          (s_rx_strobe),
      .tx_enable_i     (s_tx_enable),
      .tx_data_i       (s_tx_data),
      .tx_rwds_enable_i(s_tx_rwds_enable),
      .tx_rwds_i       (s_tx_rwds_value),
      .dq_oe_o         (dq_oe_o),
      .dq_o            (dq_o),
      .rwds_oe_o       (rwds_oe_o),
      .rwds_o          (rwds_o),
      .rwds_delayed_o  (s_rwds_delayed),
      .rx_byte_valid_o (s_rx_byte_valid),
      .rx_byte_ready_i (s_rx_byte_ready),
      .rx_byte_o       (s_rx_byte),
      .rx_overflow_o   (s_rx_overflow)
  );

  always_comb begin
    s_state_d             = s_state_q;
    s_profile_hyper_d     = s_profile_hyper_q;
    s_write_d             = s_write_q;
    s_indirect_register_d = s_indirect_register_q;
    s_addr_d              = s_addr_q;
    s_len_d               = s_len_q;
    s_wdata_d             = s_wdata_q;
    s_opi_cmd_d           = s_opi_cmd_q;
    s_opi_width16_d       = s_opi_width16_q;
    s_opi_timing_d        = s_opi_timing_q;
    s_hyper_timing_d      = s_hyper_timing_q;
    s_cs_timing_d         = s_cs_timing_q;
    s_clk_config_d        = s_clk_config_q;
    s_rx_delay_d          = s_rx_delay_q;
    s_timeout_d           = s_timeout_q;
    s_phase_count_d       = s_phase_count_q;
    s_timeout_count_d     = s_timeout_count_q;
    s_units_d             = s_units_q;
    s_data_index_d        = s_data_index_q;
    s_rx_accept_count_d   = s_rx_accept_count_q;
    s_shift_d             = s_shift_q;
    s_rdata_d             = s_rdata_q;
    s_ck_d                = s_ck_q;
    s_cs_n_d              = s_cs_n_q;
    s_rsp_valid_d         = s_rsp_valid_q;
    s_rsp_err_d           = s_rsp_err_q;
    s_rsp_seen_d          = s_rsp_seen_q;
    s_div_count_d         = s_div_count_q;

    if (s_state_q == PhyIdle) begin
      s_div_count_d     = 32'd0;
      s_phase_count_d   = 32'd0;
      s_timeout_count_d = 32'd0;
      s_ck_d            = 1'b0;
      s_cs_n_d          = 1'b1;
      s_rsp_valid_d     = 1'b0;
      s_rsp_err_d       = 1'b0;
      s_rsp_seen_d      = 1'b0;
      if (cmd_valid_i && cmd_ready_o && (cmd_len_i != 4'd0) && (cmd_len_i <= 4'd8)) begin
        s_profile_hyper_d     = cmd_profile_hyper_i;
        s_write_d             = cmd_write_i;
        s_indirect_register_d = cmd_indirect_register_i;
        s_addr_d              = cmd_addr_i;
        s_len_d               = cmd_len_i;
        s_wdata_d             = cmd_wdata_i;
        s_opi_cmd_d           = cmd_opi_cmd_i;
        s_opi_width16_d       = cmd_opi_width16_i;
        s_opi_timing_d        = cmd_opi_timing_i;
        s_hyper_timing_d      = cmd_hyper_timing_i;
        s_cs_timing_d         = cmd_cs_timing_i;
        s_clk_config_d        = cmd_clk_config_i;
        s_rx_delay_d          = cmd_rx_delay_i;
        s_timeout_d           = cmd_timeout_i;
        s_rdata_d             = 64'd0;
        s_data_index_d        = 4'd0;
        s_rx_accept_count_d   = 5'd0;
        s_cs_n_d              = 1'b0;
        s_state_d             = PhySetup;
      end else if (cmd_valid_i && cmd_ready_o) begin
        s_rsp_err_d   = 1'b1;
        s_rsp_valid_d = 1'b1;
        s_state_d     = PhyHigh;
      end
    end else begin
      if (s_phase_tick) begin
        s_div_count_d     = 32'd0;
        s_phase_count_d   = s_phase_count_q + 32'd1;
        s_timeout_count_d = s_timeout_count_q + 32'd1;
        if ((s_state_q == PhyCommand) || (s_state_q == PhyAddress) ||
            (s_state_q == PhyHyperCa) || (s_state_q == PhyWait) ||
            (s_state_q == PhyData)) begin
          s_ck_d = ~s_ck_q;
        end else begin
          s_ck_d = 1'b0;
        end
        if ((s_state_q != PhyHigh) && (s_timeout_d != 32'd0) &&
            (s_timeout_count_q >= s_timeout_d)) begin
          s_rsp_err_d     = 1'b1;
          s_rsp_valid_d   = 1'b1;
          s_cs_n_d        = 1'b1;
          s_ck_d          = 1'b0;
          s_phase_count_d = 32'd0;
          s_state_d       = PhyHigh;
        end else begin
          unique case (s_state_q)
            PhySetup: begin
              if (s_phase_count_q >= {24'd0, s_cs_timing_q[7:0]}) begin
                s_phase_count_d = 32'd0;
                if (s_profile_hyper_q) begin
                  s_shift_d = {s_hyper_ca, 16'd0};
                  s_units_d = 10'd6;
                  s_state_d = PhyHyperCa;
                end else begin
                  s_shift_d = {s_opi_cmd_first, s_opi_cmd_second, 48'd0};
                  s_units_d = {8'd0, s_opi_cmd_count};
                  s_state_d = PhyCommand;
                end
              end
            end

            PhyCommand: begin
              if (s_units_q == 10'd1) begin
                s_shift_d = {s_opi_addr_shift, 32'd0};
                s_units_d = {7'd0, s_opi_addr_bytes};
                s_state_d = PhyAddress;
              end else begin
                s_units_d = s_units_q - 10'd1;
                s_shift_d = {s_shift_q[55:0], 8'd0};
              end
            end

            PhyAddress: begin
              if (s_units_q == 10'd1) begin
                s_units_d       = s_opi_wait_phases;
                s_phase_count_d = 32'd0;
                if (s_opi_wait_phases == 10'd0) begin
                  s_units_d      = s_data_phase_count;
                  s_data_index_d = 4'd0;
                  s_shift_d      = pack_write_data(s_wdata_q);
                  s_state_d      = PhyData;
                end else begin
                  s_shift_d = pack_write_data(s_wdata_q);
                  s_state_d = PhyWait;
                end
              end else begin
                s_units_d = s_units_q - 10'd1;
                s_shift_d = {s_shift_q[55:0], 8'd0};
              end
            end

            PhyHyperCa: begin
              if (s_units_q == 10'd1) begin
                s_units_d = s_hyper_wait_phases +
                    ((s_hyper_timing_q[31] && s_rwds_delayed) ?
                     ({2'd0, s_hyper_timing_q[15:8]} << 1) : 10'd0);
                s_phase_count_d = 32'd0;
                if (s_indirect_register_q && s_write_q) begin
                  s_units_d      = s_data_phase_count;
                  s_data_index_d = 4'd0;
                  s_shift_d      = pack_write_data(s_wdata_q);
                  s_state_d      = PhyData;
                end else if (s_units_d == 10'd0) begin
                  s_units_d      = s_data_phase_count;
                  s_data_index_d = 4'd0;
                  s_shift_d      = pack_write_data(s_wdata_q);
                  s_state_d      = PhyData;
                end else begin
                  s_shift_d = pack_write_data(s_wdata_q);
                  s_state_d = PhyWait;
                end
              end else begin
                s_units_d = s_units_q - 10'd1;
                s_shift_d = {s_shift_q[55:0], 8'd0};
              end
            end

            PhyWait: begin
              if (s_units_q == 10'd1) begin
                s_units_d      = s_data_phase_count;
                s_data_index_d = 4'd0;
                s_shift_d      = pack_write_data(s_wdata_q);
                s_state_d      = PhyData;
              end else begin
                s_units_d = s_units_q - 10'd1;
              end
            end

            PhyData: begin
              if (s_rx_overflow) begin
                s_rsp_err_d     = 1'b1;
                s_rsp_valid_d   = 1'b1;
                s_cs_n_d        = 1'b1;
                s_ck_d          = 1'b0;
                s_phase_count_d = 32'd0;
                s_state_d       = PhyHigh;
              end else if (s_write_q) begin
                if (s_units_q == 10'd1) begin
                  s_phase_count_d = 32'd0;
                  s_data_index_d  = s_data_index_q + 4'd1;
                  s_state_d       = PhyPostData;
                end else begin
                  s_units_d      = s_units_q - 10'd1;
                  s_shift_d      = {s_shift_q[55:0], 8'd0};
                  s_data_index_d = s_data_index_q + 4'd1;
                end
              end else if (s_rx_byte_valid && s_rx_byte_ready) begin
                if (s_profile_hyper_q) begin
                  if (({1'b0, s_data_index_q} >= {4'd0, s_addr_q[0]}) &&
                      ({1'b0, s_data_index_q} <
                       ({4'd0, s_addr_q[0]} + {1'b0, s_len_q}))) begin
                    s_rdata_d[((s_data_index_q-{3'd0, s_addr_q[0]})*8)+:8] = s_rx_byte;
                    s_rx_accept_count_d = s_rx_accept_count_q + 5'd1;
                  end
                  if ({6'd0, s_data_index_q} == (s_data_phase_count - 10'd1)) begin
                    s_phase_count_d = 32'd0;
                    s_state_d       = PhyPostData;
                  end else begin
                    s_data_index_d = s_data_index_q + 4'd1;
                  end
                end else begin
                  s_rdata_d[(s_data_index_q*8)+:8] = s_rx_byte;
                  s_rx_accept_count_d              = s_rx_accept_count_q + 5'd1;
                  if (s_data_index_q >= (s_len_q - 4'd1)) begin
                    s_phase_count_d = 32'd0;
                    s_state_d       = PhyPostData;
                  end else begin
                    s_data_index_d = s_data_index_q + 4'd1;
                  end
                end
              end
            end

            PhyPostData: begin
              s_ck_d    = 1'b0;
              s_state_d = PhyHold;
            end

            PhyHold: begin
              if (s_phase_count_q >= {24'd0, s_cs_timing_q[15:8]}) begin
`ifndef SYNTHESIS
`ifndef SV_ASSRT_DISABLE
                if (!s_write_q && !s_rsp_err_q && (s_len_q == 4'd8))
                  assert (s_rx_accept_count_q == 5'd8);
`endif
`endif
                s_phase_count_d = 32'd0;
                s_cs_n_d        = 1'b1;
                s_ck_d          = 1'b0;
                s_rsp_err_d     = 1'b0;
                s_rsp_valid_d   = 1'b1;
                s_state_d       = PhyHigh;
              end
            end

            PhyHigh: begin
              if (s_phase_count_q < {24'd0, s_cs_timing_q[23:16]}) begin
                s_phase_count_d = s_phase_count_q + 32'd1;
              end
              if (s_phase_count_q >= {24'd0, s_cs_timing_q[23:16]} && s_rsp_seen_q) begin
                s_state_d       = PhyIdle;
                s_phase_count_d = 32'd0;
              end
            end

            default: s_state_d = PhyIdle;
          endcase
        end
      end else begin
        s_div_count_d = s_div_count_q + 32'd1;
      end

      if (abort_i && (s_state_q != PhyIdle) && (s_state_q != PhyHigh)) begin
        s_rsp_err_d     = 1'b1;
        s_rsp_valid_d   = 1'b1;
        s_cs_n_d        = 1'b1;
        s_ck_d          = 1'b0;
        s_phase_count_d = 32'd0;
        s_state_d       = PhyHigh;
      end
    end

    if ((s_state_q == PhyHigh) && s_rsp_valid_q && rsp_ready_i) begin
      s_rsp_valid_d = 1'b0;
      s_rsp_seen_d  = 1'b1;
    end

    // CK is a qualified output: it is never allowed to be high while CS# is
    // inactive, including the half-cycle CS# output-register handoff.
    if (s_cs_n_q || s_cs_n_d) s_ck_d = 1'b0;
  end

`ifndef SYNTHESIS
`ifndef SV_ASSRT_DISABLE
  always_ff @(posedge clk_phy_i) begin
    if (rst_phy_n_i) begin
      if ((s_state_q == PhySetup) || (s_state_q == PhyHold) || (s_state_q == PhyHigh))
        assert (!ck_o);
    end
  end
`endif
`endif

  dfferc #(
      .DATA_WIDTH(4),
      .RESET_VAL (PhyIdle)
  ) u_state_dfferc (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .en_i   (1'b1),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_profile_hyper_dffr (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .dat_i  (s_profile_hyper_d),
      .dat_o  (s_profile_hyper_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_write_dffr (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .dat_i  (s_write_d),
      .dat_o  (s_write_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_indirect_register_dffr (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .dat_i  (s_indirect_register_d),
      .dat_o  (s_indirect_register_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_addr_dffr (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .dat_i  (s_addr_d),
      .dat_o  (s_addr_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_len_dffr (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .dat_i  (s_len_d),
      .dat_o  (s_len_q)
  );
  dffr #(
      .DATA_WIDTH(64)
  ) u_wdata_dffr (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .dat_i  (s_wdata_d),
      .dat_o  (s_wdata_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_opi_cmd_dffr (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .dat_i  (s_opi_cmd_d),
      .dat_o  (s_opi_cmd_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_opi_width16_dffr (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .dat_i  (s_opi_width16_d),
      .dat_o  (s_opi_width16_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_opi_timing_dffr (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .dat_i  (s_opi_timing_d),
      .dat_o  (s_opi_timing_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_hyper_timing_dffr (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .dat_i  (s_hyper_timing_d),
      .dat_o  (s_hyper_timing_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_cs_timing_dffr (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .dat_i  (s_cs_timing_d),
      .dat_o  (s_cs_timing_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_clk_config_dffr (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .dat_i  (s_clk_config_d),
      .dat_o  (s_clk_config_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_rx_delay_dffr (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .dat_i  (s_rx_delay_d),
      .dat_o  (s_rx_delay_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_timeout_dffr (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .dat_i  (s_timeout_d),
      .dat_o  (s_timeout_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_phase_count_dffr (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .dat_i  (s_phase_count_d),
      .dat_o  (s_phase_count_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_timeout_count_dffr (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .dat_i  (s_timeout_count_d),
      .dat_o  (s_timeout_count_q)
  );
  dffr #(
      .DATA_WIDTH(10)
  ) u_units_dffr (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .dat_i  (s_units_d),
      .dat_o  (s_units_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_data_index_dffr (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .dat_i  (s_data_index_d),
      .dat_o  (s_data_index_q)
  );
  dffr #(
      .DATA_WIDTH(5)
  ) u_rx_accept_count_dffr (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .dat_i  (s_rx_accept_count_d),
      .dat_o  (s_rx_accept_count_q)
  );
  dffr #(
      .DATA_WIDTH(64)
  ) u_shift_dffr (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .dat_i  (s_shift_d),
      .dat_o  (s_shift_q)
  );
  dffr #(
      .DATA_WIDTH(64)
  ) u_rdata_dffr (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .dat_i  (s_rdata_d),
      .dat_o  (s_rdata_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_ck_dffr (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .dat_i  (s_ck_d),
      .dat_o  (s_ck_q)
  );
`ifdef SV_ASSRT_DISABLE
  `define RETROSOC_OPIPSRAM__PHY_CS_EDGE posedge clk_phy_i
`else
  `define RETROSOC_OPIPSRAM__PHY_CS_EDGE negedge clk_phy_i
`endif
  always_ff @(`RETROSOC_OPIPSRAM__PHY_CS_EDGE or negedge rst_phy_n_i) begin
    if (!rst_phy_n_i) begin
      s_cs_n_out_q <= 1'b1;
    end else if (!s_cs_n_q) begin
      s_cs_n_out_q <= 1'b0;
    end else if (!s_ck_q) begin
      s_cs_n_out_q <= 1'b1;
    end else begin
      s_cs_n_out_q <= s_cs_n_out_q;
    end
  end
  `undef RETROSOC_OPIPSRAM__PHY_CS_EDGE

  dffrc #(
      .DATA_WIDTH(1),
      .RESET_VAL (1'b1)
  ) u_cs_n_dffrc (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .dat_i  (s_cs_n_d),
      .dat_o  (s_cs_n_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_rsp_valid_dffr (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .dat_i  (s_rsp_valid_d),
      .dat_o  (s_rsp_valid_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_rsp_err_dffr (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .dat_i  (s_rsp_err_d),
      .dat_o  (s_rsp_err_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_rsp_seen_dffr (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .dat_i  (s_rsp_seen_d),
      .dat_o  (s_rsp_seen_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_div_count_dffr (
      .clk_i  (clk_phy_i),
      .rst_n_i(rst_phy_n_i),
      .dat_i  (s_div_count_d),
      .dat_o  (s_div_count_q)
  );

endmodule
