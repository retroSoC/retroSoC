// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module apb4_uart_rx (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        sample_tick_i,
    input  logic        enable_i,
    input  logic [ 1:0] data_bits_i,
    input  logic        stop2_i,
    input  logic [ 1:0] parity_i,
    input  logic        rx_i,
    output logic        active_o,
    output logic        data_valid_o,
    output logic [11:0] data_o
    // verilog_format: on
);

  localparam logic [2:0] STATE_IDLE = 3'd0;
  localparam logic [2:0] STATE_START = 3'd1;
  localparam logic [2:0] STATE_DATA = 3'd2;
  localparam logic [2:0] STATE_PARITY = 3'd3;
  localparam logic [2:0] STATE_STOP1 = 3'd4;
  localparam logic [2:0] STATE_STOP2 = 3'd5;

  logic s_rx_meta_d, s_rx_meta_q;
  logic s_rx_sync_d, s_rx_sync_q;
  logic [2:0] s_state_d, s_state_q;
  logic [3:0] s_sample_d, s_sample_q;
  logic [2:0] s_bit_d, s_bit_q;
  logic [1:0] s_sample_sum_d, s_sample_sum_q;
  logic s_sample_and_d, s_sample_and_q;
  logic s_sample_or_d, s_sample_or_q;
  logic s_sample_value_d, s_sample_value_q;
  logic [7:0] s_data_d, s_data_q;
  logic s_parity_err_d, s_parity_err_q;
  logic s_frame_err_d, s_frame_err_q;
  logic s_noise_d, s_noise_q;
  logic [2:0] s_last_bit;
  logic [7:0] s_data_mask;
  logic       s_majority;
  logic       s_samples_mixed;
  logic       s_expected_parity;

  assign s_rx_meta_d     = rx_i;
  assign s_rx_sync_d     = s_rx_meta_q;
  assign s_last_bit      = 3'd4 + {1'b0, data_bits_i};
  assign s_majority      = (s_sample_sum_q + s_rx_sync_q) >= 2'd2;
  assign s_samples_mixed = (s_sample_and_q & s_rx_sync_q) != (s_sample_or_q | s_rx_sync_q);
  assign active_o        = s_state_q != STATE_IDLE;

  always_comb begin
    unique case (data_bits_i)
      2'd0:    s_data_mask = 8'h1F;
      2'd1:    s_data_mask = 8'h3F;
      2'd2:    s_data_mask = 8'h7F;
      default: s_data_mask = 8'hFF;
    endcase
  end
  assign s_expected_parity = (parity_i == 2'd2) ? ~^(s_data_q & s_data_mask) :
                                                    ^(s_data_q & s_data_mask);

  always_comb begin
    s_state_d = s_state_q;
    s_sample_d = s_sample_q;
    s_bit_d = s_bit_q;
    s_sample_sum_d = s_sample_sum_q;
    s_sample_and_d = s_sample_and_q;
    s_sample_or_d = s_sample_or_q;
    s_sample_value_d = s_sample_value_q;
    s_data_d = s_data_q;
    s_parity_err_d = s_parity_err_q;
    s_frame_err_d = s_frame_err_q;
    s_noise_d = s_noise_q;
    data_valid_o = 1'b0;
    data_o = {
      s_noise_q, (s_frame_err_q && (s_data_q == 8'd0)), s_frame_err_q, s_parity_err_q, s_data_q
    };

    if (!enable_i) begin
      s_state_d      = STATE_IDLE;
      s_sample_d     = '0;
      s_bit_d        = '0;
      s_parity_err_d = 1'b0;
      s_frame_err_d  = 1'b0;
      s_noise_d      = 1'b0;
    end else if ((s_state_q == STATE_IDLE) && !s_rx_sync_q) begin
      s_state_d      = STATE_START;
      s_sample_d     = '0;
      s_bit_d        = '0;
      s_data_d       = '0;
      s_parity_err_d = 1'b0;
      s_frame_err_d  = 1'b0;
      s_noise_d      = 1'b0;
    end else if ((s_state_q != STATE_IDLE) && sample_tick_i) begin
      if (s_sample_q == 4'd7) begin
        s_sample_sum_d = {1'b0, s_rx_sync_q};
        s_sample_and_d = s_rx_sync_q;
        s_sample_or_d  = s_rx_sync_q;
      end else if (s_sample_q == 4'd8) begin
        s_sample_sum_d = s_sample_sum_q + s_rx_sync_q;
        s_sample_and_d = s_sample_and_q & s_rx_sync_q;
        s_sample_or_d  = s_sample_or_q | s_rx_sync_q;
      end else if (s_sample_q == 4'd9) begin
        s_sample_value_d = s_majority;
        s_noise_d        = s_noise_q | s_samples_mixed;
        unique case (s_state_q)
          STATE_DATA:   s_data_d[s_bit_q] = s_majority;
          STATE_PARITY: s_parity_err_d = s_majority != s_expected_parity;
          STATE_STOP1:  s_frame_err_d = !s_majority;
          STATE_STOP2:  s_frame_err_d = s_frame_err_q | !s_majority;
          default: begin
          end
        endcase
      end

      if (s_sample_q != 4'd15) begin
        s_sample_d = s_sample_q + 1'b1;
      end else begin
        s_sample_d = '0;
        unique case (s_state_q)
          STATE_START: begin
            if (s_sample_value_q) begin
              s_state_d = STATE_IDLE;
            end else begin
              s_state_d = STATE_DATA;
            end
          end
          STATE_DATA: begin
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
              s_state_d    = STATE_IDLE;
              data_valid_o = 1'b1;
            end
          end
          STATE_STOP2: begin
            s_state_d    = STATE_IDLE;
            data_valid_o = 1'b1;
          end
          default:      s_state_d = STATE_IDLE;
        endcase
      end
    end
  end

  dffr #(
      .DATA_WIDTH(1)
  ) u_rx_meta_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_meta_d),
      .dat_o  (s_rx_meta_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_rx_sync_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_sync_d),
      .dat_o  (s_rx_sync_q)
  );
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
      .DATA_WIDTH(2)
  ) u_sample_sum_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_sample_sum_d),
      .dat_o  (s_sample_sum_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_sample_and_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_sample_and_d),
      .dat_o  (s_sample_and_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_sample_or_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_sample_or_d),
      .dat_o  (s_sample_or_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_sample_value_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_sample_value_d),
      .dat_o  (s_sample_value_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_data_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_data_d),
      .dat_o  (s_data_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_parity_error_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_parity_err_d),
      .dat_o  (s_parity_err_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_frame_error_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_frame_err_d),
      .dat_o  (s_frame_err_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_noise_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_noise_d),
      .dat_o  (s_noise_q)
  );

endmodule
