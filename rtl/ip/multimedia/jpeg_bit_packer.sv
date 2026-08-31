// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

module jpeg_bit_packer #(
    parameter int unsigned TokenSlots     = 4,
    parameter int unsigned TokenWidth     = 32,
    parameter int unsigned OutputBytes    = 8,
    parameter int unsigned ReservoirWidth = 256
) (
    // verilog_format: off -- preserve token, flush, and byte-stream interface columns
    input  logic                                      clk_i,
    input  logic                                      rst_n_i,
    input  logic [TokenSlots*TokenWidth-1:0]          token_bits_i,
    input  logic [TokenSlots*6-1:0]                   token_length_i,
    input  logic [$clog2(TokenSlots+1)-1:0]           token_count_i,
    input  logic                                      token_valid_i,
    output logic                                      token_ready_o,
    input  logic                                      flush_i,
    output logic                                      flush_ready_o,
    output logic                                      flush_done_o,
    output logic [OutputBytes*8-1:0]                  byte_data_o,
    output logic [OutputBytes-1:0]                    byte_keep_o,
    output logic                                      byte_valid_o,
    output logic                                      byte_last_o,
    input  logic                                      byte_ready_i,
    output logic                                      error_o
    // verilog_format: on
);
  typedef enum logic {
    Running,
    Flushing
  } state_e;

  localparam int unsigned CountWidth = $clog2(ReservoirWidth + 1);
  localparam int unsigned TokenCountWidth = $clog2(TokenSlots + 1);

  state_e                             s_state_d;
  state_e                             s_state_q;
  logic                               s_state_bits_q;
  logic   [       ReservoirWidth-1:0] s_reservoir_d;
  logic   [       ReservoirWidth-1:0] s_reservoir_q;
  logic   [           CountWidth-1:0] s_bit_count_d;
  logic   [           CountWidth-1:0] s_bit_count_q;
  logic                               s_stuff_pending_d;
  logic                               s_stuff_pending_q;
  logic                               s_empty_flush_d;
  logic                               s_empty_flush_q;
  logic                               s_err_d;
  logic                               s_err_q;
  logic   [       ReservoirWidth-1:0] s_output_reservoir;
  logic   [           CountWidth-1:0] s_output_count;
  logic                               s_output_stuff_pending;
  logic   [$clog2(OutputBytes+1)-1:0] s_output_byte_count;
  logic   [                      7:0] s_output_byte;
  logic   [           CountWidth-1:0] s_input_bit_count;
  logic   [       ReservoirWidth-1:0] s_append_reservoir;
  logic   [           CountWidth-1:0] s_append_count;
  logic   [                      5:0] s_token_length;
  logic   [           TokenWidth-1:0] s_token_bits;

  function automatic logic [ReservoirWidth-1:0] expanded_token(input logic [TokenWidth-1:0] bits_i,
                                                               input logic [5:0] length_i);
    logic [TokenWidth-1:0] s_mask;
    begin
      s_mask = (TokenWidth'(1) << length_i) - 1'b1;
      return ReservoirWidth'(bits_i & s_mask);
    end
  endfunction

  always_comb begin
    s_input_bit_count = '0;
    for (int unsigned token = 0; token < TokenSlots; token++) begin
      if (token < token_count_i) begin
        s_input_bit_count += CountWidth'(token_length_i[token*6+:6]);
      end
    end
  end

  assign s_state_q = state_e'(s_state_bits_q);
  assign byte_valid_o = (s_bit_count_q >= CountWidth'(OutputBytes * 8)) ||
                        ((s_state_q == Flushing) &&
                         ((s_bit_count_q != '0) || s_stuff_pending_q));
  assign token_ready_o = (s_state_q == Running) && !flush_i &&
                         (s_input_bit_count <= CountWidth'(ReservoirWidth) - s_bit_count_q);
  assign flush_ready_o = (s_state_q == Running) && !token_valid_i;
  assign flush_done_o = s_empty_flush_q || (byte_valid_o && byte_ready_i && byte_last_o);
  assign error_o = s_err_q;

  always_comb begin
    byte_data_o            = '0;
    byte_keep_o            = '0;
    s_output_reservoir     = s_reservoir_q;
    s_output_count         = s_bit_count_q;
    s_output_stuff_pending = s_stuff_pending_q;
    s_output_byte_count    = '0;
    s_output_byte          = '0;
    for (int unsigned lane = 0; lane < OutputBytes; lane++) begin
      if (s_output_stuff_pending) begin
        byte_data_o[lane*8+:8] = 8'h00;
        byte_keep_o[lane]      = 1'b1;
        s_output_stuff_pending = 1'b0;
        s_output_byte_count += 1'b1;
      end else if (s_output_count >= CountWidth'(8)) begin
        s_output_byte          = 8'(s_output_reservoir >> (s_output_count - 8));
        byte_data_o[lane*8+:8] = s_output_byte;
        byte_keep_o[lane]      = 1'b1;
        s_output_count -= CountWidth'(8);
        if (s_output_byte == 8'hff) begin
          s_output_stuff_pending = 1'b1;
        end
        s_output_byte_count += 1'b1;
      end
    end
    byte_last_o = (s_state_q == Flushing) && (s_output_count == '0) &&
                  !s_output_stuff_pending && (s_output_byte_count != '0);
  end

  always_comb begin
    s_state_d          = s_state_q;
    s_reservoir_d      = s_reservoir_q;
    s_bit_count_d      = s_bit_count_q;
    s_stuff_pending_d  = s_stuff_pending_q;
    s_empty_flush_d    = 1'b0;
    s_err_d            = s_err_q;
    s_append_reservoir = s_reservoir_q;
    s_append_count     = s_bit_count_q;
    s_token_length     = '0;
    s_token_bits       = '0;

    if (byte_valid_o && byte_ready_i) begin
      s_reservoir_d     = s_output_reservoir;
      s_bit_count_d     = s_output_count;
      s_stuff_pending_d = s_output_stuff_pending;
      if (byte_last_o) begin
        s_state_d = Running;
      end
    end

    if (token_valid_i && token_ready_o) begin
      s_append_reservoir = s_reservoir_d;
      s_append_count     = s_bit_count_d;
      if ((token_count_i == '0) || (token_count_i > TokenCountWidth'(TokenSlots))) begin
        s_err_d = 1'b1;
      end
      for (int unsigned token = 0; token < TokenSlots; token++) begin
        if (token < token_count_i) begin
          s_token_length = token_length_i[token*6+:6];
          s_token_bits   = token_bits_i[token*TokenWidth+:TokenWidth];
          if ((s_token_length == 6'd0) || (s_token_length > 6'(TokenWidth))) begin
            s_err_d = 1'b1;
          end else begin
            s_append_reservoir = (s_append_reservoir << s_token_length) |
                expanded_token(s_token_bits, s_token_length);
            s_append_count += CountWidth'(s_token_length);
          end
        end
      end
      s_reservoir_d = s_append_reservoir;
      s_bit_count_d = s_append_count;
    end

    if (flush_i && flush_ready_o) begin
      if (s_bit_count_d[2:0] != 3'd0) begin
        s_token_length = 6'(8 - s_bit_count_d[2:0]);
        s_reservoir_d = (s_reservoir_d << s_token_length) |
                        ((ReservoirWidth'(1) << s_token_length) - 1'b1);
        s_bit_count_d += CountWidth'(s_token_length);
      end
      if ((s_bit_count_d == '0) && !s_stuff_pending_d) begin
        s_empty_flush_d = 1'b1;
        s_state_d       = Running;
      end else begin
        s_state_d = Flushing;
      end
    end
  end

  dffr #(
      .DATA_WIDTH(1)
  ) u_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
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
  ) u_bit_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_bit_count_d),
      .dat_o  (s_bit_count_q)
  );
  dffr u_stuff_pending_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_stuff_pending_d),
      .dat_o  (s_stuff_pending_q)
  );
  dffr u_empty_flush_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_empty_flush_d),
      .dat_o  (s_empty_flush_q)
  );
  dffr u_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_d),
      .dat_o  (s_err_q)
  );

`ifndef SYNTHESIS
  initial begin
    if (TokenSlots < 1 || TokenWidth < 27 || OutputBytes < 1 || ReservoirWidth < 128) begin
      $fatal(1, "jpeg_bit_packer: invalid interface or reservoir width");
    end
  end
`endif
endmodule
