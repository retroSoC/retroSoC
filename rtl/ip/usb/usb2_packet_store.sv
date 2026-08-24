// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module usb2_packet_store (
    // verilog_format: off -- preserve DMA fill/drain and protocol client groups
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        fill_start_valid_i,
    output logic        fill_start_ready_o,
    input  logic [11:0] fill_base_i,
    input  logic [14:0] fill_bytes_i,
    input  logic        fill_valid_i,
    output logic        fill_ready_o,
    input  logic [31:0] fill_data_i,
    input  logic [3:0]  fill_strb_i,
    input  logic        fill_last_i,
    output logic        fill_done_o,
    output logic        fill_error_o,
    input  logic        drain_start_valid_i,
    output logic        drain_start_ready_o,
    input  logic [11:0] drain_base_i,
    input  logic [14:0] drain_bytes_i,
    output logic        drain_valid_o,
    input  logic        drain_ready_i,
    output logic [31:0] drain_data_o,
    output logic [3:0]  drain_strb_o,
    output logic        drain_last_o,
    output logic        drain_done_o,
    input  logic        rx_start_valid_i,
    output logic        rx_start_ready_o,
    input  logic [11:0] rx_base_i,
    input  logic [14:0] rx_limit_i,
    input  logic        rx_valid_i,
    output logic        rx_ready_o,
    input  logic [7:0]  rx_data_i,
    input  logic        rx_commit_i,
    input  logic        rx_cancel_i,
    output logic        rx_done_o,
    output logic [14:0] rx_bytes_o,
    output logic        rx_overflow_o,
    input  logic        tx_start_valid_i,
    output logic        tx_start_ready_o,
    input  logic [11:0] tx_base_i,
    input  logic [14:0] tx_bytes_i,
    output logic        tx_valid_o,
    input  logic        tx_ready_i,
    output logic [7:0]  tx_data_o,
    output logic        tx_done_o,
    output logic        busy_o,
    output logic        ecc_corrected_o,
    output logic        ecc_uncorrectable_o
    // verilog_format: on
);
  typedef enum logic [3:0] {
    Idle,
    Fill,
    DrainIssue,
    DrainWait,
    DrainSend,
    Receive,
    ReceiveFlush,
    TransmitIssue,
    TransmitWait,
    TransmitSend
  } store_state_e;

  store_state_e s_state_d, s_state_q;
  logic [3:0] s_state_bits_q;
  logic [11:0] s_addr_d, s_addr_q;
  logic [14:0] s_count_d, s_count_q;
  logic [14:0] s_limit_d, s_limit_q;
  logic [31:0] s_word_d, s_word_q;
  logic [1:0] s_lane_d, s_lane_q;
  logic s_overflow_d, s_overflow_q;
  logic s_fill_done_d, s_fill_done_q;
  logic s_fill_err_d, s_fill_err_q;
  logic s_drain_done_d, s_drain_done_q;
  logic s_rx_done_d, s_rx_done_q;
  logic s_tx_done_d, s_tx_done_q;
  logic        s_ram_write;
  logic        s_ram_read;
  logic [11:0] s_ram_addr;
  logic [31:0] s_ram_write_data;
  logic [31:0] s_ram_read_data;
  logic [31:0] s_read_word_q;
  logic        s_ram_read_valid;
  logic        s_ram_corrected;
  logic        s_ram_uncorrectable;
  logic [ 2:0] s_active_bytes;
  logic [ 3:0] s_expected_strb;
  logic        s_fill_last_expected;
  logic        s_receive_full_word;

  function automatic logic [2:0] active_bytes(input logic [14:0] bytes_i);
    if (bytes_i >= 15'd4) begin
      return 3'd4;
    end
    return {1'b0, bytes_i[1:0]};
  endfunction

  function automatic logic [3:0] low_strobe(input logic [2:0] bytes_i);
    unique case (bytes_i)
      3'd0:    return 4'b0000;
      3'd1:    return 4'b0001;
      3'd2:    return 4'b0011;
      3'd3:    return 4'b0111;
      default: return 4'b1111;
    endcase
  endfunction

  function automatic logic range_valid(input logic [11:0] base_i, input logic [14:0] bytes_i);
    logic [15:0] words;
    logic [15:0] end_word;
    begin
      words    = ({1'b0, bytes_i} + 16'd3) >> 2;
      end_word = {4'd0, base_i} + words;
      return (bytes_i != 15'd0) && (end_word <= 16'd4096);
    end
  endfunction

  assign s_state_q            = store_state_e'(s_state_bits_q);
  assign s_active_bytes       = active_bytes(s_limit_q - s_count_q);
  assign s_expected_strb      = low_strobe(s_active_bytes);
  assign s_fill_last_expected = (s_count_q + {12'd0, s_active_bytes}) >= s_limit_q;
  assign s_receive_full_word  = s_lane_q == 2'd3;

  assign fill_start_ready_o   = s_state_q == Idle;
  assign drain_start_ready_o  = s_state_q == Idle;
  assign rx_start_ready_o     = s_state_q == Idle;
  assign tx_start_ready_o     = s_state_q == Idle;
  assign fill_ready_o         = s_state_q == Fill;
  assign drain_valid_o        = s_state_q == DrainSend;
  assign drain_data_o         = s_read_word_q;
  assign drain_strb_o         = s_expected_strb;
  assign drain_last_o         = s_fill_last_expected;
  assign rx_ready_o           = s_state_q == Receive;
  assign rx_bytes_o           = s_count_q;
  assign rx_overflow_o        = s_overflow_q;
  assign tx_valid_o           = s_state_q == TransmitSend;
  assign tx_data_o            = s_read_word_q[(s_lane_q*8)+:8];
  assign busy_o               = s_state_q != Idle;
  assign fill_done_o          = s_fill_done_q;
  assign fill_error_o         = s_fill_err_q;
  assign drain_done_o         = s_drain_done_q;
  assign rx_done_o            = s_rx_done_q;
  assign tx_done_o            = s_tx_done_q;
  assign ecc_corrected_o      = s_ram_read_valid && s_ram_corrected;
  assign ecc_uncorrectable_o  = s_ram_read_valid && s_ram_uncorrectable;

  always_comb begin
    s_ram_write      = 1'b0;
    s_ram_read       = 1'b0;
    s_ram_addr       = s_addr_q;
    s_ram_write_data = s_word_q;
    if ((s_state_q == Fill) && fill_valid_i && fill_ready_o) begin
      s_ram_write      = 1'b1;
      s_ram_write_data = fill_data_i;
    end else if ((s_state_q == Receive) && rx_valid_i && rx_ready_o &&
                 !s_overflow_q && s_receive_full_word) begin
      s_ram_write             = 1'b1;
      s_ram_write_data        = s_word_q;
      s_ram_write_data[31:24] = rx_data_i;
    end else if (s_state_q == ReceiveFlush) begin
      s_ram_write = 1'b1;
    end else if ((s_state_q == DrainIssue) || (s_state_q == TransmitIssue)) begin
      s_ram_read = 1'b1;
    end
  end

  always_comb begin
    s_state_d      = s_state_q;
    s_addr_d       = s_addr_q;
    s_count_d      = s_count_q;
    s_limit_d      = s_limit_q;
    s_word_d       = s_word_q;
    s_lane_d       = s_lane_q;
    s_overflow_d   = s_overflow_q;
    s_fill_done_d  = 1'b0;
    s_fill_err_d   = 1'b0;
    s_drain_done_d = 1'b0;
    s_rx_done_d    = 1'b0;
    s_tx_done_d    = 1'b0;

    unique case (s_state_q)
      Idle: begin
        s_count_d    = '0;
        s_lane_d     = '0;
        s_word_d     = '0;
        s_overflow_d = 1'b0;
        if (fill_start_valid_i && fill_start_ready_o) begin
          s_addr_d  = fill_base_i;
          s_limit_d = fill_bytes_i;
          if (!range_valid(fill_base_i, fill_bytes_i)) begin
            s_fill_done_d = 1'b1;
            s_fill_err_d  = 1'b1;
          end else begin
            s_state_d = Fill;
          end
        end else if (drain_start_valid_i && drain_start_ready_o) begin
          s_addr_d  = drain_base_i;
          s_limit_d = drain_bytes_i;
          if (!range_valid(drain_base_i, drain_bytes_i)) begin
            s_drain_done_d = 1'b1;
          end else begin
            s_state_d = DrainIssue;
          end
        end else if (rx_start_valid_i && rx_start_ready_o) begin
          s_addr_d  = rx_base_i;
          s_limit_d = rx_limit_i;
          s_state_d = Receive;
        end else if (tx_start_valid_i && tx_start_ready_o) begin
          s_addr_d  = tx_base_i;
          s_limit_d = tx_bytes_i;
          if (!range_valid(tx_base_i, tx_bytes_i)) begin
            s_tx_done_d = 1'b1;
          end else begin
            s_state_d = TransmitIssue;
          end
        end
      end
      Fill: begin
        if (fill_valid_i && fill_ready_o) begin
          s_count_d = s_count_q + {12'd0, s_active_bytes};
          s_addr_d  = s_addr_q + 1'b1;
          if ((fill_strb_i != s_expected_strb) || (fill_last_i != s_fill_last_expected)) begin
            s_fill_err_d  = 1'b1;
            s_fill_done_d = 1'b1;
            s_state_d     = Idle;
          end else if (s_fill_last_expected) begin
            s_fill_done_d = 1'b1;
            s_state_d     = Idle;
          end
        end
      end
      DrainIssue:    s_state_d = DrainWait;
      DrainWait: begin
        if (s_ram_read_valid) begin
          s_state_d = DrainSend;
        end
      end
      DrainSend: begin
        if (drain_valid_o && drain_ready_i) begin
          s_count_d = s_count_q + {12'd0, s_active_bytes};
          s_addr_d  = s_addr_q + 1'b1;
          if (s_fill_last_expected) begin
            s_drain_done_d = 1'b1;
            s_state_d      = Idle;
          end else begin
            s_state_d = DrainIssue;
          end
        end
      end
      Receive: begin
        if (rx_valid_i && rx_ready_o) begin
          if (s_count_q >= s_limit_q) begin
            s_overflow_d = 1'b1;
          end else begin
            s_word_d[(s_lane_q*8)+:8] = rx_data_i;
            s_count_d                 = s_count_q + 1'b1;
            if (s_receive_full_word) begin
              s_addr_d = s_addr_q + 1'b1;
              s_lane_d = '0;
              s_word_d = '0;
            end else begin
              s_lane_d = s_lane_q + 1'b1;
            end
          end
        end
        if (rx_cancel_i) begin
          s_rx_done_d = 1'b1;
          s_count_d   = '0;
          s_state_d   = Idle;
        end else if (rx_commit_i) begin
          if ((s_lane_d != '0) && !s_overflow_d) begin
            s_state_d = ReceiveFlush;
          end else begin
            s_rx_done_d = 1'b1;
            s_state_d   = Idle;
          end
        end
      end
      ReceiveFlush: begin
        s_rx_done_d = 1'b1;
        s_state_d   = Idle;
      end
      TransmitIssue: s_state_d = TransmitWait;
      TransmitWait: begin
        if (s_ram_read_valid) begin
          s_state_d = TransmitSend;
        end
      end
      TransmitSend: begin
        if (tx_valid_o && tx_ready_i) begin
          s_count_d = s_count_q + 1'b1;
          if ((s_count_q + 1'b1) >= s_limit_q) begin
            s_tx_done_d = 1'b1;
            s_state_d   = Idle;
          end else if (s_lane_q == 2'd3) begin
            s_lane_d  = '0;
            s_addr_d  = s_addr_q + 1'b1;
            s_state_d = TransmitIssue;
          end else begin
            s_lane_d = s_lane_q + 1'b1;
          end
        end
      end
      default:       s_state_d = Idle;
    endcase
  end

  usb2_packet_ram u_packet_ram (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .write_i        (s_ram_write),
      .read_i         (s_ram_read),
      .addr_i         (s_ram_addr),
      .write_data_i   (s_ram_write_data),
      .inject_single_i(1'b0),
      .inject_double_i(1'b0),
      .read_data_o    (s_ram_read_data),
      .read_valid_o   (s_ram_read_valid),
      .corrected_o    (s_ram_corrected),
      .uncorrectable_o(s_ram_uncorrectable)
  );

  dffer #(
      .DATA_WIDTH(32)
  ) u_read_word_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_ram_read_valid),
      .dat_i  (s_ram_read_data),
      .dat_o  (s_read_word_q)
  );

  dffr #(
      .DATA_WIDTH(4)
  ) u_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
  dffr #(
      .DATA_WIDTH(12)
  ) u_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_addr_d),
      .dat_o  (s_addr_q)
  );
  dffr #(
      .DATA_WIDTH(15)
  ) u_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_count_d),
      .dat_o  (s_count_q)
  );
  dffr #(
      .DATA_WIDTH(15)
  ) u_limit_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_limit_d),
      .dat_o  (s_limit_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_word_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_word_d),
      .dat_o  (s_word_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_lane_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_lane_d),
      .dat_o  (s_lane_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_overflow_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_overflow_d),
      .dat_o  (s_overflow_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_fill_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fill_done_d),
      .dat_o  (s_fill_done_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_fill_error_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fill_err_d),
      .dat_o  (s_fill_err_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_drain_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_drain_done_d),
      .dat_o  (s_drain_done_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_rx_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_done_d),
      .dat_o  (s_rx_done_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_tx_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_tx_done_d),
      .dat_o  (s_tx_done_q)
  );

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (rst_n_i && (s_state_q == Idle) &&
        ((fill_start_valid_i &&
          (drain_start_valid_i || rx_start_valid_i || tx_start_valid_i)) ||
         (drain_start_valid_i && (rx_start_valid_i || tx_start_valid_i)) ||
         (rx_start_valid_i && tx_start_valid_i))) begin
      $error("usb2_packet_store: simultaneous client start requests (%b)", {
             fill_start_valid_i, drain_start_valid_i, rx_start_valid_i, tx_start_valid_i});
    end
  end
`endif
endmodule
