// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module psram_phy (
    // verilog_format: off -- preserve reviewed port alignment
    input  logic                     clk_i,
    input  logic                     rst_n_i,
    input  logic                     abort_i,
    input  logic                     req_valid_i,
    output logic                     req_ready_o,
    input  psram_pkg::psram_cmd_e    req_command_i,
    input  logic [1:0]               req_chip_i,
    input  logic                     req_qpi_i,
    input  logic [22:0]              req_addr_i,
    input  logic [5:0]               req_length_i,
    input  logic [63:0]              req_wdata_i,
    output logic                     busy_o,
    output logic                     done_o,
    output logic                     error_o,
    output logic [255:0]             rdata_o,
    input  logic [15:0]              cfg_half_period_i,
    input  logic [15:0]              cfg_cs_setup_i,
    input  logic [15:0]              cfg_cs_high_i,
    input  logic [15:0]              cfg_cs_hold_i,
    input  logic [31:0]              cfg_cs_max_low_i,
    input  logic [31:0]              cfg_access_timeout_i,
    output logic                     psram_sclk_o,
    output logic [3:0]               psram_nss_o,
    output logic [3:0]               psram_io_oe_o,
    input  logic [3:0]               psram_io_di_i,
    output logic [3:0]               psram_io_do_o
    // verilog_format: on
);

  import psram_pkg::*;

  typedef enum logic [3:0] {
    PhyIdle    = 4'd0,
    PhySetup   = 4'd1,
    PhyCommand = 4'd2,
    PhyAddress = 4'd3,
    PhyDummy   = 4'd4,
    PhyRead    = 4'd5,
    PhyWrite   = 4'd6,
    PhyHold    = 4'd7,
    PhyHigh    = 4'd8
  } psram_phy_state_e;

  logic             [  3:0] s_state_bits_q;
  logic             [  3:0] s_cmd_bits_q;
  psram_phy_state_e         s_state_q;
  psram_cmd_e               s_cmd_q;
  logic                     s_qpi_q;
  logic             [ 22:0] s_addr_q;
  logic             [  5:0] s_len_q;
  logic             [ 63:0] s_wdata_q;
  logic             [255:0] s_rdata_q;
  logic             [ 62:0] s_tx_shift_q;
  logic             [  7:0] s_read_byte_q;
  logic             [  6:0] s_units_left_q;
  logic             [  4:0] s_byte_index_q;
  logic             [  2:0] s_bit_index_q;
  logic                     s_nibble_phase_q;
  logic                     s_stage_done_q;
  logic                     s_tx_quad_q;
  logic                     s_rx_quad_q;
  logic             [ 15:0] s_half_count_q;
  logic             [ 15:0] s_delay_count_q;
  logic             [ 31:0] s_cs_low_count_q;
  logic             [ 31:0] s_access_count_q;
  logic                     s_sclk_q;
  logic             [  3:0] s_nss_q;
  logic             [  3:0] s_io_oe_q;
  logic             [  3:0] s_io_do_q;

  assign s_state_q = psram_phy_state_e'(s_state_bits_q);
  assign s_cmd_q   = psram_cmd_e'(s_cmd_bits_q);

  psram_phy_state_e         s_state_d;
  psram_cmd_e               s_cmd_d;
  logic                     s_qpi_d;
  logic             [ 22:0] s_addr_d;
  logic             [  5:0] s_len_d;
  logic             [ 63:0] s_wdata_d;
  logic             [255:0] s_rdata_d;
  logic             [ 62:0] s_tx_shift_d;
  logic             [  7:0] s_read_byte_d;
  logic             [  6:0] s_units_left_d;
  logic             [  4:0] s_byte_index_d;
  logic             [  2:0] s_bit_index_d;
  logic                     s_nibble_phase_d;
  logic                     s_stage_done_d;
  logic                     s_tx_quad_d;
  logic                     s_rx_quad_d;
  logic             [ 15:0] s_half_count_d;
  logic             [ 15:0] s_delay_count_d;
  logic             [ 31:0] s_cs_low_count_d;
  logic             [ 31:0] s_access_count_d;
  logic                     s_sclk_d;
  logic             [  3:0] s_nss_d;
  logic             [  3:0] s_io_oe_d;
  logic             [  3:0] s_io_do_d;
  logic s_done_d, s_done_q;
  logic s_err_d, s_err_q;

  function automatic logic command_address_quad(input psram_cmd_e command, input logic qpi);
    return qpi || (command == PsramCmdQuadRead) || (command == PsramCmdQuadWrite);
  endfunction

  function automatic logic command_data_quad(input psram_cmd_e command, input logic qpi);
    return qpi || (command == PsramCmdQuadRead) || (command == PsramCmdQuadWrite);
  endfunction

  function automatic logic [3:0] command_dummy_cycles(input psram_cmd_e command);
    if (command == PsramCmdFastRead) return 4'd8;
    if (command == PsramCmdQuadRead) return 4'd6;
    return 4'd0;
  endfunction

  function automatic logic [62:0] pack_write_remainder(input logic [63:0] data,
                                                       input logic [5:0] length, input logic quad);
    logic [62:0] packed_data;
    begin
      packed_data        = '0;
      packed_data[62:56] = data[6:0];
      for (int byte_index = 1; byte_index < 8; byte_index++) begin
        if (byte_index < length) begin
          packed_data[63-(byte_index*8)-:8] = data[(byte_index*8)+:8];
        end
      end
      if (quad) return {3'd0, packed_data[59:0]};
      return packed_data;
    end
  endfunction

  assign req_ready_o   = s_state_q == PhyIdle;
  assign busy_o        = (s_state_q != PhyIdle) && (s_state_q != PhyHigh);
  assign rdata_o       = s_rdata_q;
  assign psram_sclk_o  = s_sclk_q;
  assign psram_nss_o   = s_nss_q;
  assign psram_io_oe_o = s_io_oe_q;
  assign psram_io_do_o = s_io_do_q;

  logic [7:0] s_opcode;
  assign s_opcode = psram_opcode(s_cmd_q);

  always_comb begin
    s_state_d        = s_state_q;
    s_cmd_d          = s_cmd_q;
    s_qpi_d          = s_qpi_q;
    s_addr_d         = s_addr_q;
    s_len_d          = s_len_q;
    s_wdata_d        = s_wdata_q;
    s_rdata_d        = s_rdata_q;
    s_tx_shift_d     = s_tx_shift_q;
    s_read_byte_d    = s_read_byte_q;
    s_units_left_d   = s_units_left_q;
    s_byte_index_d   = s_byte_index_q;
    s_bit_index_d    = s_bit_index_q;
    s_nibble_phase_d = s_nibble_phase_q;
    s_stage_done_d   = s_stage_done_q;
    s_tx_quad_d      = s_tx_quad_q;
    s_rx_quad_d      = s_rx_quad_q;
    s_half_count_d   = s_half_count_q;
    s_delay_count_d  = s_delay_count_q;
    s_cs_low_count_d = s_cs_low_count_q;
    s_access_count_d = s_access_count_q;
    s_sclk_d         = s_sclk_q;
    s_nss_d          = s_nss_q;
    s_io_oe_d        = s_io_oe_q;
    s_io_do_d        = s_io_do_q;
    s_done_d         = 1'b0;
    s_err_d          = 1'b0;
    s_done_d         = 1'b0;
    s_err_d          = 1'b0;

    if ((s_state_q != PhyIdle) && (s_state_q != PhyHigh)) begin
      s_cs_low_count_d = s_cs_low_count_q + 1'b1;
      s_access_count_d = s_access_count_q + 1'b1;
    end

    if (abort_i && (s_state_q != PhyIdle)) begin
      s_state_d       = PhyHigh;
      s_sclk_d        = 1'b0;
      s_nss_d         = 4'hF;
      s_io_oe_d       = 4'hF;
      s_io_do_d       = 4'h0;
      s_delay_count_d = '0;
      s_done_d        = 1'b1;
      s_err_d         = 1'b1;
    end else if (((cfg_cs_max_low_i != 32'd0) &&
                    (s_cs_low_count_q >= cfg_cs_max_low_i)) ||
                   ((cfg_access_timeout_i != 32'd0) &&
                    (s_access_count_q >= cfg_access_timeout_i))) begin
      s_state_d       = PhyHigh;
      s_sclk_d        = 1'b0;
      s_nss_d         = 4'hF;
      s_io_oe_d       = 4'hF;
      s_io_do_d       = 4'h0;
      s_delay_count_d = '0;
      s_done_d        = 1'b1;
      s_err_d         = 1'b1;
    end else begin
      unique case (s_state_q)
        PhyIdle: begin
          s_sclk_d         = 1'b0;
          s_nss_d          = 4'hF;
          s_io_oe_d        = 4'hF;
          s_io_do_d        = 4'h0;
          s_half_count_d   = '0;
          s_delay_count_d  = '0;
          s_cs_low_count_d = '0;
          s_access_count_d = '0;
          if (req_valid_i && req_ready_o) begin
            if ((req_length_i == 6'd0) || (req_length_i > 6'd32) || (psram_command_is_write(
                    req_command_i
                ) && (req_length_i > 6'd8)) || (cfg_half_period_i == 16'd0)) begin
              s_done_d = 1'b1;
              s_err_d  = 1'b1;
            end else begin
              s_cmd_d          = req_command_i;
              s_qpi_d          = req_qpi_i;
              s_addr_d         = req_addr_i;
              s_len_d          = req_length_i;
              s_wdata_d        = req_wdata_i;
              s_rdata_d        = '0;
              s_byte_index_d   = '0;
              s_bit_index_d    = '0;
              s_nibble_phase_d = 1'b0;
              s_stage_done_d   = 1'b0;
              s_nss_d          = ~(4'b0001 << req_chip_i);
              s_delay_count_d  = '0;
              s_state_d        = PhySetup;
            end
          end
        end

        PhySetup: begin
          if (s_delay_count_q >= cfg_cs_setup_i) begin
            s_state_d      = PhyCommand;
            s_tx_quad_d    = s_qpi_q;
            s_tx_shift_d   = s_qpi_q ? {3'd0, s_opcode[3:0], 56'd0} : {s_opcode[6:0], 56'd0};
            s_units_left_d = s_qpi_q ? 7'd2 : 7'd8;
            s_io_oe_d      = s_qpi_q ? 4'hF : 4'h1;
            s_io_do_d      = s_qpi_q ? s_opcode[7:4] : {3'd0, s_opcode[7]};
            s_half_count_d = '0;
          end else begin
            s_delay_count_d = s_delay_count_q + 1'b1;
          end
        end

        PhyCommand, PhyAddress, PhyDummy, PhyRead, PhyWrite: begin
          if (s_half_count_q == (cfg_half_period_i - 1'b1)) begin
            s_half_count_d = '0;
            if (!s_sclk_q) begin
              s_sclk_d = 1'b1;
              if (s_state_q == PhyRead) begin
                if (s_rx_quad_q) begin
                  if (!s_nibble_phase_q) begin
                    s_read_byte_d[7:4] = psram_io_di_i;
                    s_nibble_phase_d   = 1'b1;
                  end else begin
                    s_rdata_d[(s_byte_index_q*8)+:8] = {s_read_byte_q[7:4], psram_io_di_i};
                    s_nibble_phase_d                 = 1'b0;
                    s_byte_index_d                   = s_byte_index_q + 1'b1;
                  end
                end else begin
                  s_read_byte_d = {s_read_byte_q[6:0], psram_io_di_i[1]};
                  if (s_bit_index_q == 3'd7) begin
                    s_rdata_d[(s_byte_index_q*8)+:8] = {s_read_byte_q[6:0], psram_io_di_i[1]};
                    s_bit_index_d                    = '0;
                    s_byte_index_d                   = s_byte_index_q + 1'b1;
                  end else begin
                    s_bit_index_d = s_bit_index_q + 1'b1;
                  end
                end
              end
              if (s_units_left_q == 7'd1) begin
                s_stage_done_d = 1'b1;
              end
              s_units_left_d = s_units_left_q - 1'b1;
            end else begin
              s_sclk_d = 1'b0;
              if (s_stage_done_q) begin
                s_stage_done_d = 1'b0;
                unique case (s_state_q)
                  PhyCommand: begin
                    if (psram_command_has_address(s_cmd_q)) begin
                      s_state_d = PhyAddress;
                      s_tx_quad_d = command_address_quad(s_cmd_q, s_qpi_q);
                      s_tx_shift_d = command_address_quad(s_cmd_q, s_qpi_q) ?
                          {3'd0, s_addr_q[19:0], 40'd0} : {s_addr_q, 40'd0};
                      s_units_left_d = command_address_quad(s_cmd_q, s_qpi_q) ? 7'd6 : 7'd24;
                      s_io_oe_d = command_address_quad(s_cmd_q, s_qpi_q) ? 4'hF : 4'h1;
                      s_io_do_d = command_address_quad(s_cmd_q, s_qpi_q) ?
                          {1'b0, s_addr_q[22:20]} : {3'd0, 1'b0};
                    end else begin
                      s_state_d       = PhyHold;
                      s_delay_count_d = '0;
                    end
                  end
                  PhyAddress: begin
                    if (command_dummy_cycles(s_cmd_q) != 4'd0) begin
                      s_state_d      = PhyDummy;
                      s_units_left_d = {3'd0, command_dummy_cycles(s_cmd_q)};
                      s_io_oe_d      = 4'h0;
                      s_io_do_d      = 4'h0;
                    end else if (psram_command_is_read(s_cmd_q)) begin
                      s_state_d = PhyRead;
                      s_rx_quad_d = command_data_quad(s_cmd_q, s_qpi_q);
                      s_units_left_d = command_data_quad(s_cmd_q, s_qpi_q) ? 7'(s_len_q << 1) :
                          7'(s_len_q << 3);
                      s_io_oe_d = 4'h0;
                      s_byte_index_d = '0;
                      s_bit_index_d = '0;
                      s_nibble_phase_d = 1'b0;
                    end else if (psram_command_is_write(s_cmd_q)) begin
                      s_state_d = PhyWrite;
                      s_tx_quad_d = command_data_quad(s_cmd_q, s_qpi_q);
                      s_tx_shift_d = pack_write_remainder(s_wdata_q, s_len_q,
                                                          command_data_quad(s_cmd_q, s_qpi_q));
                      s_units_left_d = command_data_quad(s_cmd_q, s_qpi_q) ? 7'(s_len_q << 1) :
                          7'(s_len_q << 3);
                      s_io_oe_d = command_data_quad(s_cmd_q, s_qpi_q) ? 4'hF : 4'h1;
                      s_io_do_d = command_data_quad(s_cmd_q, s_qpi_q) ?
                          s_wdata_q[7:4] : {3'd0, s_wdata_q[7]};
                    end else begin
                      s_state_d       = PhyHold;
                      s_delay_count_d = '0;
                    end
                  end
                  PhyDummy: begin
                    s_state_d = PhyRead;
                    s_rx_quad_d = command_data_quad(s_cmd_q, s_qpi_q);
                    s_units_left_d = command_data_quad(s_cmd_q, s_qpi_q) ? 7'(s_len_q << 1) :
                        7'(s_len_q << 3);
                    s_io_oe_d = 4'h0;
                    s_byte_index_d = '0;
                    s_bit_index_d = '0;
                    s_nibble_phase_d = 1'b0;
                  end
                  default: begin
                    s_state_d       = PhyHold;
                    s_delay_count_d = '0;
                  end
                endcase
              end else if ((s_state_q == PhyCommand) ||
                             (s_state_q == PhyAddress) ||
                             (s_state_q == PhyWrite)) begin
                if (s_tx_quad_q) begin
                  s_tx_shift_d = {s_tx_shift_q[58:0], 4'd0};
                  s_io_do_d    = s_tx_shift_q[59:56];
                end else begin
                  s_tx_shift_d = {s_tx_shift_q[61:0], 1'b0};
                  s_io_do_d    = {3'd0, s_tx_shift_q[62]};
                end
              end
            end
          end else begin
            s_half_count_d = s_half_count_q + 1'b1;
          end
        end

        PhyHold: begin
          s_sclk_d = 1'b0;
          if (s_delay_count_q >= cfg_cs_hold_i) begin
            s_nss_d         = 4'hF;
            s_io_oe_d       = 4'hF;
            s_io_do_d       = 4'h0;
            s_delay_count_d = '0;
            s_state_d       = PhyHigh;
            s_done_d        = 1'b1;
          end else begin
            s_delay_count_d = s_delay_count_q + 1'b1;
          end
        end

        PhyHigh: begin
          s_sclk_d = 1'b0;
          s_nss_d  = 4'hF;
          if (s_delay_count_q >= cfg_cs_high_i) begin
            s_delay_count_d = '0;
            s_state_d       = PhyIdle;
          end else begin
            s_delay_count_d = s_delay_count_q + 1'b1;
          end
        end

        default: s_state_d = PhyIdle;
      endcase
    end
  end
  dffrc #(
      .DATA_WIDTH($bits(psram_phy_state_e)),
      .RESET_VAL (PhyIdle)
  ) u_state_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
  dffrc #(
      .DATA_WIDTH($bits(psram_cmd_e)),
      .RESET_VAL (PsramCmdRead)
  ) u_cmd_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_cmd_d),
      .dat_o  (s_cmd_bits_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_qpi_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_qpi_d),
      .dat_o  (s_qpi_q)
  );
  dffr #(
      .DATA_WIDTH(23)
  ) u_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_addr_d),
      .dat_o  (s_addr_q)
  );
  dffr #(
      .DATA_WIDTH(6)
  ) u_len_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_len_d),
      .dat_o  (s_len_q)
  );
  dffr #(
      .DATA_WIDTH(64)
  ) u_wdata_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_wdata_d),
      .dat_o  (s_wdata_q)
  );
  dffr #(
      .DATA_WIDTH(256)
  ) u_rdata_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rdata_d),
      .dat_o  (s_rdata_q)
  );
  dffr #(
      .DATA_WIDTH(63)
  ) u_tx_shift_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_shift_d),
      .dat_o  (s_tx_shift_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_read_byte_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_byte_d),
      .dat_o  (s_read_byte_q)
  );
  dffr #(
      .DATA_WIDTH(7)
  ) u_units_left_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_units_left_d),
      .dat_o  (s_units_left_q)
  );
  dffr #(
      .DATA_WIDTH(5)
  ) u_byte_index_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_byte_index_d),
      .dat_o  (s_byte_index_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_bit_index_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_bit_index_d),
      .dat_o  (s_bit_index_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_nibble_phase_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_nibble_phase_d),
      .dat_o  (s_nibble_phase_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_stage_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_stage_done_d),
      .dat_o  (s_stage_done_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_tx_quad_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_quad_d),
      .dat_o  (s_tx_quad_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_rx_quad_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_quad_d),
      .dat_o  (s_rx_quad_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_half_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_half_count_d),
      .dat_o  (s_half_count_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_delay_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_delay_count_d),
      .dat_o  (s_delay_count_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_cs_low_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_cs_low_count_d),
      .dat_o  (s_cs_low_count_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_access_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_access_count_d),
      .dat_o  (s_access_count_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_sclk_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_sclk_d),
      .dat_o  (s_sclk_q)
  );
  dffrc #(
      .DATA_WIDTH(4),
      .RESET_VAL (4'hF)
  ) u_nss_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_nss_d),
      .dat_o  (s_nss_q)
  );
  dffrc #(
      .DATA_WIDTH(4),
      .RESET_VAL (4'hF)
  ) u_io_oe_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_io_oe_d),
      .dat_o  (s_io_oe_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_io_do_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_io_do_d),
      .dat_o  (s_io_do_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_done_d),
      .dat_o  (s_done_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_d),
      .dat_o  (s_err_q)
  );

  assign done_o  = s_done_q;
  assign error_o = s_err_q;

endmodule
