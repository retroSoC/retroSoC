// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

module jpeg_bit_reader #(
    parameter int unsigned ReservoirWidth = 128,
    parameter int unsigned WindowWidth    = 32
) (
    // verilog_format: off -- preserve byte, bit-window, and marker interface columns
    input  logic                                  clk_i,
    input  logic                                  rst_n_i,
    input  logic [7:0]                            byte_i,
    input  logic                                  byte_valid_i,
    output logic                                  byte_ready_o,
    input  logic                                  byte_last_i,
    input  logic [$clog2(WindowWidth+1)-1:0]      bit_consume_i,
    input  logic                                  bit_consume_valid_i,
    input  logic                                  align_i,
    output logic [WindowWidth-1:0]                bit_window_o,
    output logic [$clog2(WindowWidth+1)-1:0]      bit_count_o,
    output logic                                  marker_valid_o,
    output logic [7:0]                            marker_o,
    input  logic                                  marker_ready_i,
    output logic                                  error_o
    // verilog_format: on
);
  localparam int unsigned CountWidth = $clog2(ReservoirWidth + 1);
  localparam int unsigned WindowCountWidth = $clog2(WindowWidth + 1);
  localparam logic [CountWidth-1:0] WindowCount = CountWidth'(WindowWidth);
  localparam logic [CountWidth-1:0] CapacityCount = CountWidth'(ReservoirWidth - 8);

  logic [ReservoirWidth-1:0] s_reservoir_d;
  logic [ReservoirWidth-1:0] s_reservoir_q;
  logic [    CountWidth-1:0] s_bit_cnt_d;
  logic [    CountWidth-1:0] s_bit_cnt_q;
  logic                      s_ff_pending_d;
  logic                      s_ff_pending_q;
  logic                      s_marker_valid_d;
  logic                      s_marker_valid_q;
  logic [               7:0] s_marker_d;
  logic [               7:0] s_marker_q;
  logic                      s_err_d;
  logic                      s_err_q;
  logic                      s_append_byte;
  logic [               7:0] s_append_value;

  assign byte_ready_o   = !s_marker_valid_q && (s_bit_cnt_q <= CapacityCount);
  assign marker_valid_o = s_marker_valid_q;
  assign marker_o       = s_marker_q;
  assign error_o        = s_err_q;

  always_comb begin
    if (s_bit_cnt_q >= WindowCount) begin
      bit_window_o = WindowWidth'(s_reservoir_q >> (s_bit_cnt_q - WindowCount));
      bit_count_o  = WindowCountWidth'(WindowWidth);
    end else begin
      bit_window_o = WindowWidth'(s_reservoir_q << (WindowCount - s_bit_cnt_q));
      bit_count_o  = WindowCountWidth'(s_bit_cnt_q);
    end
  end

  always_comb begin
    s_reservoir_d    = s_reservoir_q;
    s_bit_cnt_d      = s_bit_cnt_q;
    s_ff_pending_d   = s_ff_pending_q;
    s_marker_valid_d = s_marker_valid_q;
    s_marker_d       = s_marker_q;
    s_err_d          = s_err_q;
    s_append_byte    = 1'b0;
    s_append_value   = byte_i;

    if (bit_consume_valid_i) begin
      if (CountWidth'(bit_consume_i) > s_bit_cnt_d) begin
        s_err_d = 1'b1;
      end else begin
        s_bit_cnt_d -= CountWidth'(bit_consume_i);
      end
    end
    if (align_i) begin
      s_bit_cnt_d   = '0;
      s_reservoir_d = '0;
    end
    if (s_marker_valid_q && marker_ready_i) begin
      s_marker_valid_d = 1'b0;
    end
    if (byte_valid_i && byte_ready_o) begin
      if (s_ff_pending_q) begin
        if (byte_i == 8'h00) begin
          s_append_byte  = 1'b1;
          s_append_value = 8'hff;
          s_ff_pending_d = 1'b0;
        end else if (byte_i == 8'hff) begin
          s_ff_pending_d = 1'b1;
        end else begin
          s_marker_valid_d = 1'b1;
          s_marker_d       = byte_i;
          s_ff_pending_d   = 1'b0;
          if (!((byte_i >= 8'hd0 && byte_i <= 8'hd7) || (byte_i == 8'hd9))) begin
            s_err_d = 1'b1;
          end
        end
      end else if (byte_i == 8'hff) begin
        s_ff_pending_d = 1'b1;
      end else begin
        s_append_byte = 1'b1;
      end
      if (byte_last_i && (byte_i != 8'hd9)) begin
        s_err_d = 1'b1;
      end
    end
    if (s_append_byte) begin
      s_reservoir_d = (s_reservoir_d << 8) | ReservoirWidth'(s_append_value);
      s_bit_cnt_d += CountWidth'(8);
    end
  end

  dffr #(
      .DATA_WIDTH(ReservoirWidth)
  ) u_reservoir_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_reservoir_d),
      .dat_o  (s_reservoir_q)
  );
  dffr #(
      .DATA_WIDTH(CountWidth)
  ) u_bit_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_bit_cnt_d),
      .dat_o  (s_bit_cnt_q)
  );
  dffr u_ff_pending_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ff_pending_d),
      .dat_o  (s_ff_pending_q)
  );
  dffr u_marker_valid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_marker_valid_d),
      .dat_o  (s_marker_valid_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_marker_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_marker_d),
      .dat_o  (s_marker_q)
  );
  dffr u_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_d),
      .dat_o  (s_err_q)
  );

`ifndef SYNTHESIS
  initial begin
    if (ReservoirWidth < 64 || WindowWidth < 27 || WindowWidth > ReservoirWidth) begin
      $fatal(1, "jpeg_bit_reader: invalid reservoir or window width");
    end
  end
`endif
endmodule
