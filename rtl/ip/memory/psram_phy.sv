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

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q        <= PhyIdle;
      s_cmd_q          <= PsramCmdRead;
      s_qpi_q          <= 1'b0;
      s_addr_q         <= '0;
      s_len_q          <= '0;
      s_wdata_q        <= '0;
      s_rdata_q        <= '0;
      s_tx_shift_q     <= '0;
      s_read_byte_q    <= '0;
      s_units_left_q   <= '0;
      s_byte_index_q   <= '0;
      s_bit_index_q    <= '0;
      s_nibble_phase_q <= 1'b0;
      s_stage_done_q   <= 1'b0;
      s_tx_quad_q      <= 1'b0;
      s_rx_quad_q      <= 1'b0;
      s_half_count_q   <= '0;
      s_delay_count_q  <= '0;
      s_cs_low_count_q <= '0;
      s_access_count_q <= '0;
      s_sclk_q         <= 1'b0;
      s_nss_q          <= 4'hF;
      s_io_oe_q        <= 4'hF;
      s_io_do_q        <= 4'h0;
      done_o           <= 1'b0;
      error_o          <= 1'b0;
    end else begin
      done_o  <= 1'b0;
      error_o <= 1'b0;

      if ((s_state_q != PhyIdle) && (s_state_q != PhyHigh)) begin
        s_cs_low_count_q <= s_cs_low_count_q + 1'b1;
        s_access_count_q <= s_access_count_q + 1'b1;
      end

      if (abort_i && (s_state_q != PhyIdle)) begin
        s_state_q       <= PhyHigh;
        s_sclk_q        <= 1'b0;
        s_nss_q         <= 4'hF;
        s_io_oe_q       <= 4'hF;
        s_io_do_q       <= 4'h0;
        s_delay_count_q <= '0;
        done_o          <= 1'b1;
        error_o         <= 1'b1;
      end else if (((cfg_cs_max_low_i != 32'd0) &&
                    (s_cs_low_count_q >= cfg_cs_max_low_i)) ||
                   ((cfg_access_timeout_i != 32'd0) &&
                    (s_access_count_q >= cfg_access_timeout_i))) begin
        s_state_q       <= PhyHigh;
        s_sclk_q        <= 1'b0;
        s_nss_q         <= 4'hF;
        s_io_oe_q       <= 4'hF;
        s_io_do_q       <= 4'h0;
        s_delay_count_q <= '0;
        done_o          <= 1'b1;
        error_o         <= 1'b1;
      end else begin
        unique case (s_state_q)
          PhyIdle: begin
            s_sclk_q         <= 1'b0;
            s_nss_q          <= 4'hF;
            s_io_oe_q        <= 4'hF;
            s_io_do_q        <= 4'h0;
            s_half_count_q   <= '0;
            s_delay_count_q  <= '0;
            s_cs_low_count_q <= '0;
            s_access_count_q <= '0;
            if (req_valid_i && req_ready_o) begin
              if ((req_length_i == 6'd0) || (req_length_i > 6'd32) || (psram_command_is_write(
                      req_command_i
                  ) && (req_length_i > 6'd8)) || (cfg_half_period_i == 16'd0)) begin
                done_o  <= 1'b1;
                error_o <= 1'b1;
              end else begin
                s_cmd_q          <= req_command_i;
                s_qpi_q          <= req_qpi_i;
                s_addr_q         <= req_addr_i;
                s_len_q          <= req_length_i;
                s_wdata_q        <= req_wdata_i;
                s_rdata_q        <= '0;
                s_byte_index_q   <= '0;
                s_bit_index_q    <= '0;
                s_nibble_phase_q <= 1'b0;
                s_stage_done_q   <= 1'b0;
                s_nss_q          <= ~(4'b0001 << req_chip_i);
                s_delay_count_q  <= '0;
                s_state_q        <= PhySetup;
              end
            end
          end

          PhySetup: begin
            if (s_delay_count_q >= cfg_cs_setup_i) begin
              s_state_q      <= PhyCommand;
              s_tx_quad_q    <= s_qpi_q;
              s_tx_shift_q   <= s_qpi_q ? {3'd0, s_opcode[3:0], 56'd0} : {s_opcode[6:0], 56'd0};
              s_units_left_q <= s_qpi_q ? 7'd2 : 7'd8;
              s_io_oe_q      <= s_qpi_q ? 4'hF : 4'h1;
              s_io_do_q      <= s_qpi_q ? s_opcode[7:4] : {3'd0, s_opcode[7]};
              s_half_count_q <= '0;
            end else begin
              s_delay_count_q <= s_delay_count_q + 1'b1;
            end
          end

          PhyCommand, PhyAddress, PhyDummy, PhyRead, PhyWrite: begin
            if (s_half_count_q == (cfg_half_period_i - 1'b1)) begin
              s_half_count_q <= '0;
              if (!s_sclk_q) begin
                s_sclk_q <= 1'b1;
                if (s_state_q == PhyRead) begin
                  if (s_rx_quad_q) begin
                    if (!s_nibble_phase_q) begin
                      s_read_byte_q[7:4] <= psram_io_di_i;
                      s_nibble_phase_q   <= 1'b1;
                    end else begin
                      s_rdata_q[(s_byte_index_q*8)+:8] <= {s_read_byte_q[7:4], psram_io_di_i};
                      s_nibble_phase_q                 <= 1'b0;
                      s_byte_index_q                   <= s_byte_index_q + 1'b1;
                    end
                  end else begin
                    s_read_byte_q <= {s_read_byte_q[6:0], psram_io_di_i[1]};
                    if (s_bit_index_q == 3'd7) begin
                      s_rdata_q[(s_byte_index_q*8)+:8] <= {s_read_byte_q[6:0], psram_io_di_i[1]};
                      s_bit_index_q                    <= '0;
                      s_byte_index_q                   <= s_byte_index_q + 1'b1;
                    end else begin
                      s_bit_index_q <= s_bit_index_q + 1'b1;
                    end
                  end
                end
                if (s_units_left_q == 7'd1) begin
                  s_stage_done_q <= 1'b1;
                end
                s_units_left_q <= s_units_left_q - 1'b1;
              end else begin
                s_sclk_q <= 1'b0;
                if (s_stage_done_q) begin
                  s_stage_done_q <= 1'b0;
                  unique case (s_state_q)
                    PhyCommand: begin
                      if (psram_command_has_address(s_cmd_q)) begin
                        s_state_q <= PhyAddress;
                        s_tx_quad_q <= command_address_quad(s_cmd_q, s_qpi_q);
                        s_tx_shift_q <= command_address_quad(
                            s_cmd_q, s_qpi_q
                        ) ? {3'd0, s_addr_q[19:0], 40'd0} : {s_addr_q, 40'd0};
                        s_units_left_q <= command_address_quad(s_cmd_q, s_qpi_q) ? 7'd6 : 7'd24;
                        s_io_oe_q <= command_address_quad(s_cmd_q, s_qpi_q) ? 4'hF : 4'h1;
                        s_io_do_q <= command_address_quad(
                            s_cmd_q, s_qpi_q
                        ) ? {1'b0, s_addr_q[22:20]} : {3'd0, 1'b0};
                      end else begin
                        s_state_q       <= PhyHold;
                        s_delay_count_q <= '0;
                      end
                    end
                    PhyAddress: begin
                      if (command_dummy_cycles(s_cmd_q) != 4'd0) begin
                        s_state_q      <= PhyDummy;
                        s_units_left_q <= {3'd0, command_dummy_cycles(s_cmd_q)};
                        s_io_oe_q      <= 4'h0;
                        s_io_do_q      <= 4'h0;
                      end else if (psram_command_is_read(s_cmd_q)) begin
                        s_state_q <= PhyRead;
                        s_rx_quad_q <= command_data_quad(s_cmd_q, s_qpi_q);
                        s_units_left_q <= command_data_quad(
                            s_cmd_q, s_qpi_q
                        ) ? 7'(s_len_q << 1) : 7'(s_len_q << 3);
                        s_io_oe_q <= 4'h0;
                        s_byte_index_q <= '0;
                        s_bit_index_q <= '0;
                        s_nibble_phase_q <= 1'b0;
                      end else if (psram_command_is_write(s_cmd_q)) begin
                        s_state_q <= PhyWrite;
                        s_tx_quad_q <= command_data_quad(s_cmd_q, s_qpi_q);
                        s_tx_shift_q <= pack_write_remainder(
                            s_wdata_q, s_len_q, command_data_quad(s_cmd_q, s_qpi_q)
                        );
                        s_units_left_q <= command_data_quad(
                            s_cmd_q, s_qpi_q
                        ) ? 7'(s_len_q << 1) : 7'(s_len_q << 3);
                        s_io_oe_q <= command_data_quad(s_cmd_q, s_qpi_q) ? 4'hF : 4'h1;
                        s_io_do_q <= command_data_quad(
                            s_cmd_q, s_qpi_q
                        ) ? s_wdata_q[7:4] : {3'd0, s_wdata_q[7]};
                      end else begin
                        s_state_q       <= PhyHold;
                        s_delay_count_q <= '0;
                      end
                    end
                    PhyDummy: begin
                      s_state_q <= PhyRead;
                      s_rx_quad_q <= command_data_quad(s_cmd_q, s_qpi_q);
                      s_units_left_q <= command_data_quad(
                          s_cmd_q, s_qpi_q
                      ) ? 7'(s_len_q << 1) : 7'(s_len_q << 3);
                      s_io_oe_q <= 4'h0;
                      s_byte_index_q <= '0;
                      s_bit_index_q <= '0;
                      s_nibble_phase_q <= 1'b0;
                    end
                    default: begin
                      s_state_q       <= PhyHold;
                      s_delay_count_q <= '0;
                    end
                  endcase
                end else if ((s_state_q == PhyCommand) ||
                             (s_state_q == PhyAddress) ||
                             (s_state_q == PhyWrite)) begin
                  if (s_tx_quad_q) begin
                    s_tx_shift_q <= {s_tx_shift_q[58:0], 4'd0};
                    s_io_do_q    <= s_tx_shift_q[59:56];
                  end else begin
                    s_tx_shift_q <= {s_tx_shift_q[61:0], 1'b0};
                    s_io_do_q    <= {3'd0, s_tx_shift_q[62]};
                  end
                end
              end
            end else begin
              s_half_count_q <= s_half_count_q + 1'b1;
            end
          end

          PhyHold: begin
            s_sclk_q <= 1'b0;
            if (s_delay_count_q >= cfg_cs_hold_i) begin
              s_nss_q         <= 4'hF;
              s_io_oe_q       <= 4'hF;
              s_io_do_q       <= 4'h0;
              s_delay_count_q <= '0;
              s_state_q       <= PhyHigh;
              done_o          <= 1'b1;
            end else begin
              s_delay_count_q <= s_delay_count_q + 1'b1;
            end
          end

          PhyHigh: begin
            s_sclk_q <= 1'b0;
            s_nss_q  <= 4'hF;
            if (s_delay_count_q >= cfg_cs_high_i) begin
              s_delay_count_q <= '0;
              s_state_q       <= PhyIdle;
            end else begin
              s_delay_count_q <= s_delay_count_q + 1'b1;
            end
          end

          default: s_state_q <= PhyIdle;
        endcase
      end
    end
  end

endmodule
