// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module apb4_uart_tx (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic       clk_i,
    input  logic       rst_n_i,
    input  logic       sample_tick_i,
    input  logic       enable_i,
    input  logic       start_allowed_i,
    input  logic       break_i,
    input  logic [1:0] data_bits_i,
    input  logic       stop2_i,
    input  logic [1:0] parity_i,
    input  logic       data_valid_i,
    input  logic [7:0] data_i,
    output logic       data_pop_o,
    output logic       busy_o,
    output logic       done_o,
    output logic       tx_o
    // verilog_format: on
);

  localparam logic [2:0] STATE_IDLE = 3'd0;
  localparam logic [2:0] STATE_START = 3'd1;
  localparam logic [2:0] STATE_DATA = 3'd2;
  localparam logic [2:0] STATE_PARITY = 3'd3;
  localparam logic [2:0] STATE_STOP1 = 3'd4;
  localparam logic [2:0] STATE_STOP2 = 3'd5;

  logic [2:0] s_state_d, s_state_q;
  logic [3:0] s_sample_d, s_sample_q;
  logic [2:0] s_bit_d, s_bit_q;
  logic [7:0] s_shift_d, s_shift_q;
  logic s_parity_d, s_parity_q;
  logic [2:0] s_last_bit;
  logic [7:0] s_data_mask;

  always_comb begin
    unique case (data_bits_i)
      2'd0:    s_data_mask = 8'h1F;
      2'd1:    s_data_mask = 8'h3F;
      2'd2:    s_data_mask = 8'h7F;
      default: s_data_mask = 8'hFF;
    endcase
  end

  assign s_last_bit = 3'd4 + {1'b0, data_bits_i};
  assign busy_o     = s_state_q != STATE_IDLE;

  always_comb begin
    unique case (s_state_q)
      STATE_START:  tx_o = 1'b0;
      STATE_DATA:   tx_o = s_shift_q[0];
      STATE_PARITY: tx_o = s_parity_q;
      default:      tx_o = 1'b1;
    endcase
    if (break_i) begin
      tx_o = 1'b0;
    end
  end

  always_comb begin
    s_state_d  = s_state_q;
    s_sample_d = s_sample_q;
    s_bit_d    = s_bit_q;
    s_shift_d  = s_shift_q;
    s_parity_d = s_parity_q;
    data_pop_o = 1'b0;
    done_o     = 1'b0;

    if ((s_state_q == STATE_IDLE) && enable_i && start_allowed_i && !break_i && data_valid_i &&
        sample_tick_i) begin
      s_state_d  = STATE_START;
      s_sample_d = '0;
      s_bit_d    = '0;
      s_shift_d  = data_i;
      s_parity_d = (parity_i == 2'd2) ? ~^(data_i & s_data_mask) : ^(data_i & s_data_mask);
      data_pop_o = 1'b1;
    end else if ((s_state_q != STATE_IDLE) && sample_tick_i) begin
      if (s_sample_q != 4'd15) begin
        s_sample_d = s_sample_q + 1'b1;
      end else begin
        s_sample_d = '0;
        unique case (s_state_q)
          STATE_START:  s_state_d = STATE_DATA;
          STATE_DATA: begin
            s_shift_d = {1'b0, s_shift_q[7:1]};
            if (s_bit_q == s_last_bit) begin
              s_state_d = (parity_i == 2'd0) ? STATE_STOP1 : STATE_PARITY;
            end else begin
              s_bit_d = s_bit_q + 1'b1;
            end
          end
          STATE_PARITY: s_state_d = STATE_STOP1;
          STATE_STOP1: begin
            if (stop2_i) begin
              s_state_d = STATE_STOP2;
            end else begin
              s_state_d = STATE_IDLE;
              done_o    = 1'b1;
            end
          end
          STATE_STOP2: begin
            s_state_d = STATE_IDLE;
            done_o    = 1'b1;
          end
          default:      s_state_d = STATE_IDLE;
        endcase
      end
    end
  end

  dffr #(
      .DATA_WIDTH(3)
  ) u_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_sample_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_sample_d),
      .dat_o  (s_sample_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_bit_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_bit_d),
      .dat_o  (s_bit_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_shift_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_shift_d),
      .dat_o  (s_shift_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_parity_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_parity_d),
      .dat_o  (s_parity_q)
  );

endmodule
