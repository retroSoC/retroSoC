// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

`include "xpi_define.svh"

module xpi_core (
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

  typedef enum logic [3:0] {
    Idle,
    CsSetup,
    Fetch,
    Shift,
    Dummy,
    RxPresent,
    CsHold,
    CsHigh,
    Complete
  } xpi_core_state_e;

  logic [3:0] s_state_bits_q;
  xpi_core_state_e s_state_d, s_state_q;
  logic [2:0] s_pc_d, s_pc_q;
  logic [2:0] s_resume_pc_d, s_resume_pc_q;
  logic s_resume_d, s_resume_q;
  logic [3:0] s_active_opcode_bits_q;
  xpi_instr_opcode_e s_active_opcode_d, s_active_opcode_q;
  logic [1:0] s_active_pads_d, s_active_pads_q;
  logic s_nss_active_d, s_nss_active_q;
  logic s_sclk_en_d, s_sclk_en_q;
  logic [31:0] s_shift_d, s_shift_q;
  logic [5:0] s_bit_cnt_d, s_bit_cnt_q;
  logic [7:0] s_phase_cnt_d, s_phase_cnt_q;
  logic [15:0] s_data_remaining_d, s_data_remaining_q;
  logic [31:0] s_timeout_cnt_d, s_timeout_cnt_q;
  logic s_rx_valid_d, s_rx_valid_q;
  logic [7:0] s_rx_data_d, s_rx_data_q;
  logic [3:0] s_err_code_bits_q;
  xpi_error_e s_err_code_d, s_err_code_q;
  logic [2:0] s_err_pc_d, s_err_pc_q;

  logic              [15:0] s_instr;
  xpi_instr_opcode_e        s_opcode;
  logic              [ 1:0] s_pads;
  logic              [ 7:0] s_operand;
  logic              [ 2:0] s_instr_pad_count;
  logic              [ 2:0] s_active_pad_count;
  logic                     s_sample_edge;
  logic                     s_shift_edge;
  logic              [31:0] s_rx_shifted;
  logic                     s_timeout_expired;
  logic                     s_transmit_phase;

  assign s_state_q = xpi_core_state_e'(s_state_bits_q);
  assign s_active_opcode_q = xpi_instr_opcode_e'(s_active_opcode_bits_q);
  assign s_err_code_q = xpi_error_e'(s_err_code_bits_q);
  assign s_instr = lut_i[s_pc_q];
  assign s_opcode = xpi_instr_opcode_e'(s_instr[15:12]);
  assign s_pads = s_instr[11:10];
  assign s_operand = s_instr[7:0];
  assign s_instr_pad_count = xpi_pad_count(s_pads);
  assign s_active_pad_count = xpi_pad_count(s_active_pads_q);
  assign s_timeout_expired = (timeout_i != 32'd0) && (s_timeout_cnt_q >= timeout_i - 1'b1);
  assign s_transmit_phase = (s_active_opcode_q == XpiInstrCommand) ||
                            (s_active_opcode_q == XpiInstrAddress) ||
                            (s_active_opcode_q == XpiInstrMode) ||
                            (s_active_opcode_q == XpiInstrTransmit);

  always_comb begin
    unique case (s_active_pad_count)
      3'd1:    s_rx_shifted = {s_shift_q[30:0], xpi.io_di_i[1]};
      3'd2:    s_rx_shifted = {s_shift_q[29:0], xpi.io_di_i[1:0]};
      3'd4:    s_rx_shifted = {s_shift_q[27:0], xpi.io_di_i[3:0]};
      default: s_rx_shifted = s_shift_q;
    endcase
  end

  always_comb begin
    xpi.nss_o = 4'b1111;
    if (s_nss_active_q) begin
      xpi.nss_o[slot_i] = 1'b0;
    end
  end

  always_comb begin
    xpi.io_oe_o = '0;
    xpi.io_do_o = '0;
    if ((s_state_q == Shift) && s_transmit_phase) begin
      unique case (s_active_pad_count)
        3'd1: begin
          xpi.io_oe_o[0] = 1'b1;
          xpi.io_do_o[0] = s_shift_q[31];
        end
        3'd2: begin
          xpi.io_oe_o[1:0] = 2'b11;
          xpi.io_do_o[1:0] = s_shift_q[31:30];
        end
        3'd4: begin
          xpi.io_oe_o = 4'b1111;
          xpi.io_do_o = s_shift_q[31:28];
        end
        default: begin
        end
      endcase
    end
  end

  assign busy_o       = (s_state_q != Idle) && (s_state_q != Complete);
  assign done_o       = s_state_q == Complete;
  assign error_o      = done_o && (s_err_code_q != XpiErrorNone);
  assign error_code_o = s_err_code_q;
  assign error_pc_o   = s_err_pc_q;
  assign rx_valid_o   = (s_state_q == RxPresent) && s_rx_valid_q;
  assign rx_data_o    = s_rx_data_q;
  xpi_clkgen u_xpi_clkgen (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .mode3_i      (mode3_i),
      .div_i        (clkdiv_i),
      .enable_i     (s_sclk_en_q),
      .sclk_o       (xpi.sck_o),
      .sample_edge_o(s_sample_edge),
      .shift_edge_o (s_shift_edge)
  );

  always_comb begin
    s_state_d          = s_state_q;
    s_pc_d             = s_pc_q;
    s_resume_pc_d      = s_resume_pc_q;
    s_resume_d         = s_resume_q;
    s_active_opcode_d  = s_active_opcode_q;
    s_active_pads_d    = s_active_pads_q;
    s_nss_active_d     = s_nss_active_q;
    s_sclk_en_d        = s_sclk_en_q;
    s_shift_d          = s_shift_q;
    s_bit_cnt_d        = s_bit_cnt_q;
    s_phase_cnt_d      = s_phase_cnt_q;
    s_data_remaining_d = s_data_remaining_q;
    s_timeout_cnt_d    = busy_o ? s_timeout_cnt_q + 1'b1 : '0;
    s_rx_valid_d       = s_rx_valid_q;
    s_rx_data_d        = s_rx_data_q;
    s_err_code_d       = s_err_code_q;
    s_err_pc_d         = s_err_pc_q;
    tx_ready_o         = 1'b0;
    phy_byte_event_o   = 1'b0;

    if (abort_i && busy_o) begin
      s_state_d      = Complete;
      s_nss_active_d = 1'b0;
      s_sclk_en_d    = 1'b0;
      s_rx_valid_d   = 1'b0;
      s_err_code_d   = XpiErrorAborted;
      s_err_pc_d     = s_pc_q;
    end else if (s_timeout_expired && busy_o) begin
      s_state_d      = Complete;
      s_nss_active_d = 1'b0;
      s_sclk_en_d    = 1'b0;
      s_rx_valid_d   = 1'b0;
      s_err_code_d   = XpiErrorTimeout;
      s_err_pc_d     = s_pc_q;
    end else begin
      unique case (s_state_q)
        Idle: begin
          if (start_i) begin
            s_state_d          = CsSetup;
            s_pc_d             = '0;
            s_resume_d         = 1'b0;
            s_nss_active_d     = 1'b1;
            s_sclk_en_d        = 1'b0;
            s_phase_cnt_d      = cs_setup_i;
            s_data_remaining_d = '0;
            s_timeout_cnt_d    = '0;
            s_err_code_d       = XpiErrorNone;
            s_err_pc_d         = '0;
          end
        end

        CsSetup: begin
          if (s_phase_cnt_q == 8'd0) begin
            s_state_d = Fetch;
          end else begin
            s_phase_cnt_d = s_phase_cnt_q - 1'b1;
          end
        end

        Fetch: begin
          if (s_instr[9:8] != 2'b00 || s_instr_pad_count == 3'd0) begin
            s_state_d     = CsHold;
            s_phase_cnt_d = cs_hold_i;
            s_err_code_d  = XpiErrorSequence;
            s_err_pc_d    = s_pc_q;
          end else if ((s_pc_q == 3'd7) && (s_opcode != XpiInstrStop) &&
                       (s_opcode != XpiInstrJumpOnCs)) begin
            s_state_d     = CsHold;
            s_phase_cnt_d = cs_hold_i;
            s_err_code_d  = XpiErrorSequence;
            s_err_pc_d    = s_pc_q;
          end else begin
            unique case (s_opcode)
              XpiInstrStop: begin
                s_state_d     = CsHold;
                s_phase_cnt_d = cs_hold_i;
                s_resume_d    = 1'b0;
              end
              XpiInstrCommand, XpiInstrMode: begin
                s_active_opcode_d = s_opcode;
                s_active_pads_d   = s_pads;
                s_shift_d         = {s_operand, 24'd0};
                s_bit_cnt_d       = 6'd8;
                s_sclk_en_d       = 1'b1;
                s_pc_d            = s_pc_q + 1'b1;
                s_state_d         = Shift;
              end
              XpiInstrAddress: begin
                if ((s_operand == 8'd8) || (s_operand == 8'd16) ||
                    (s_operand == 8'd24) || (s_operand == 8'd32)) begin
                  s_active_opcode_d = s_opcode;
                  s_active_pads_d   = s_pads;
                  s_shift_d         = address_i << (32 - s_operand);
                  s_bit_cnt_d       = 6'(s_operand);
                  s_sclk_en_d       = 1'b1;
                  s_pc_d            = s_pc_q + 1'b1;
                  s_state_d         = Shift;
                end else begin
                  s_state_d     = CsHold;
                  s_phase_cnt_d = cs_hold_i;
                  s_err_code_d  = XpiErrorSequence;
                  s_err_pc_d    = s_pc_q;
                end
              end
              XpiInstrDummy: begin
                if (s_operand == 8'd0) begin
                  s_pc_d = s_pc_q + 1'b1;
                end else begin
                  s_phase_cnt_d = s_operand;
                  s_sclk_en_d   = 1'b1;
                  s_pc_d        = s_pc_q + 1'b1;
                  s_state_d     = Dummy;
                end
              end
              XpiInstrTransmit: begin
                if (s_data_remaining_q == 16'd0) begin
                  s_data_remaining_d = (s_operand == 8'd0) ? data_len_i : {8'd0, s_operand};
                end
                if (((s_data_remaining_q == 16'd0) &&
                     (((s_operand == 8'd0) ? data_len_i : {8'd0, s_operand}) == 16'd0))) begin
                  s_pc_d = s_pc_q + 1'b1;
                end else if (tx_valid_i) begin
                  s_active_opcode_d = s_opcode;
                  s_active_pads_d   = s_pads;
                  tx_ready_o        = 1'b1;
                  s_shift_d         = {tx_data_i, 24'd0};
                  s_bit_cnt_d       = 6'd8;
                  s_sclk_en_d       = 1'b1;
                  s_state_d         = Shift;
                end
              end
              XpiInstrReceive: begin
                if (s_data_remaining_q == 16'd0) begin
                  s_data_remaining_d = (s_operand == 8'd0) ? data_len_i : {8'd0, s_operand};
                  if (((s_operand == 8'd0) ? data_len_i : {8'd0, s_operand}) == 16'd0) begin
                    s_pc_d = s_pc_q + 1'b1;
                  end else begin
                    s_active_opcode_d = s_opcode;
                    s_active_pads_d   = s_pads;
                    s_shift_d         = '0;
                    s_bit_cnt_d       = 6'd8;
                    s_sclk_en_d       = 1'b1;
                    s_state_d         = Shift;
                  end
                end else begin
                  s_active_opcode_d = s_opcode;
                  s_active_pads_d   = s_pads;
                  s_shift_d         = '0;
                  s_bit_cnt_d       = 6'd8;
                  s_sclk_en_d       = 1'b1;
                  s_state_d         = Shift;
                end
              end
              XpiInstrJumpOnCs: begin
                if (s_operand[7:3] != 5'd0) begin
                  s_err_code_d = XpiErrorSequence;
                  s_err_pc_d   = s_pc_q;
                  s_resume_d   = 1'b0;
                end else begin
                  s_resume_pc_d = s_operand[2:0];
                  s_resume_d    = 1'b1;
                end
                s_phase_cnt_d = cs_hold_i;
                s_state_d     = CsHold;
              end
              default: begin
                s_state_d     = CsHold;
                s_phase_cnt_d = cs_hold_i;
                s_err_code_d  = XpiErrorSequence;
                s_err_pc_d    = s_pc_q;
              end
            endcase
          end
        end

        Shift: begin
          if (s_active_opcode_q == XpiInstrReceive) begin
            if (s_sample_edge) begin
              s_shift_d   = s_rx_shifted;
              s_bit_cnt_d = s_bit_cnt_q - 6'(s_active_pad_count);
              if (s_bit_cnt_q <= 6'(s_active_pad_count)) begin
                s_rx_data_d      = s_rx_shifted[7:0];
                s_rx_valid_d     = 1'b1;
                phy_byte_event_o = 1'b1;
              end
            end
            if (s_shift_edge && (s_bit_cnt_q == 6'd0)) begin
              s_sclk_en_d = 1'b0;
              s_state_d   = RxPresent;
            end
          end else if (s_shift_edge) begin
            s_shift_d   = s_shift_q << s_active_pad_count;
            s_bit_cnt_d = s_bit_cnt_q - 6'(s_active_pad_count);
            if (s_bit_cnt_q <= 6'(s_active_pad_count)) begin
              s_sclk_en_d = 1'b0;
              s_state_d   = Fetch;
              if (s_active_opcode_q == XpiInstrTransmit) begin
                phy_byte_event_o = 1'b1;
                if (s_data_remaining_q <= 16'd1) begin
                  s_data_remaining_d = '0;
                  s_pc_d             = s_pc_q + 1'b1;
                end else begin
                  s_data_remaining_d = s_data_remaining_q - 1'b1;
                end
              end
            end
          end
        end

        Dummy: begin
          if (s_shift_edge) begin
            if (s_phase_cnt_q <= 8'd1) begin
              s_phase_cnt_d = '0;
              s_sclk_en_d   = 1'b0;
              s_state_d     = Fetch;
            end else begin
              s_phase_cnt_d = s_phase_cnt_q - 1'b1;
            end
          end
        end

        RxPresent: begin
          if (s_rx_valid_q && rx_ready_i) begin
            s_rx_valid_d = 1'b0;
            if (s_data_remaining_q <= 16'd1) begin
              s_data_remaining_d = '0;
              s_pc_d             = s_pc_q + 1'b1;
            end else begin
              s_data_remaining_d = s_data_remaining_q - 1'b1;
            end
            s_state_d = Fetch;
          end
        end

        CsHold: begin
          if (s_phase_cnt_q == 8'd0) begin
            s_nss_active_d = 1'b0;
            s_phase_cnt_d  = cs_high_i;
            s_state_d      = CsHigh;
          end else begin
            s_phase_cnt_d = s_phase_cnt_q - 1'b1;
          end
        end

        CsHigh: begin
          if (s_phase_cnt_q == 8'd0) begin
            if (s_resume_q && (s_err_code_q == XpiErrorNone)) begin
              s_pc_d         = s_resume_pc_q;
              s_resume_d     = 1'b0;
              s_nss_active_d = 1'b1;
              s_phase_cnt_d  = cs_setup_i;
              s_state_d      = CsSetup;
            end else begin
              s_state_d = Complete;
            end
          end else begin
            s_phase_cnt_d = s_phase_cnt_q - 1'b1;
          end
        end

        Complete: begin
          s_state_d = Idle;
        end

        default: begin
          s_state_d      = Complete;
          s_nss_active_d = 1'b0;
          s_sclk_en_d    = 1'b0;
          s_err_code_d   = XpiErrorIllegal;
        end
      endcase
    end
  end

  dffrc #(
      .DATA_WIDTH(4),
      .RESET_VAL (Idle)
  ) u_state_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_pc_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_pc_d),
      .dat_o  (s_pc_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_resume_pc_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_resume_pc_d),
      .dat_o  (s_resume_pc_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_resume_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_resume_d),
      .dat_o  (s_resume_q)
  );
  dffrc #(
      .DATA_WIDTH(4),
      .RESET_VAL (XpiInstrStop)
  ) u_active_opcode_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_active_opcode_d),
      .dat_o  (s_active_opcode_bits_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_active_pads_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_active_pads_d),
      .dat_o  (s_active_pads_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_nss_active_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_nss_active_d),
      .dat_o  (s_nss_active_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_sclk_enable_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_sclk_en_d),
      .dat_o  (s_sclk_en_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_shift_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_shift_d),
      .dat_o  (s_shift_q)
  );
  dffr #(
      .DATA_WIDTH(6)
  ) u_bit_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_bit_cnt_d),
      .dat_o  (s_bit_cnt_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_phase_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_phase_cnt_d),
      .dat_o  (s_phase_cnt_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_data_remaining_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_data_remaining_d),
      .dat_o  (s_data_remaining_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_timeout_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_timeout_cnt_d),
      .dat_o  (s_timeout_cnt_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_rx_valid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_valid_d),
      .dat_o  (s_rx_valid_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_rx_data_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_data_d),
      .dat_o  (s_rx_data_q)
  );
  dffrc #(
      .DATA_WIDTH(4),
      .RESET_VAL (XpiErrorNone)
  ) u_error_code_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_code_d),
      .dat_o  (s_err_code_bits_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_error_pc_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_pc_d),
      .dat_o  (s_err_pc_q)
  );

`ifndef SV_ASSRT_DISABLE
`ifndef SYNTHESIS
  a_xpi_read_pad_released :
  assert property (@(posedge clk_i) disable iff (!rst_n_i)
      ((s_state_q == Dummy) ||
       ((s_state_q == Shift) && (s_active_opcode_q == XpiInstrReceive)))
      |-> (xpi.io_oe_o == 4'b0000));
  a_xpi_nss_onehot :
  assert property (@(posedge clk_i) disable iff (!rst_n_i) $onehot0(~xpi.nss_o));
  a_xpi_idle_clock :
  assert property (@(posedge clk_i) disable iff (!rst_n_i) !s_sclk_en_q |-> (xpi.sck_o == mode3_i));
`endif
`endif

endmodule
