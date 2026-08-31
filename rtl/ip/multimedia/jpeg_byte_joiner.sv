// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

module jpeg_byte_joiner #(
    parameter int unsigned DataWidth = 64
) (
    // verilog_format: off -- preserve input byte beat and AXI output columns
    input  logic                  clk_i,
    input  logic                  rst_n_i,
    input  logic [DataWidth-1:0]  input_data_i,
    input  logic [DataWidth/8-1:0] input_keep_i,
    input  logic                  input_valid_i,
    output logic                  input_ready_o,
    input  logic                  input_last_i,
    axi4_stream_if.source         output_axis,
    output logic                  error_o
    // verilog_format: on
);
  localparam int unsigned BeatBytes = DataWidth / 8;
  localparam int unsigned BufferBytes = BeatBytes * 2;
  localparam int unsigned CountWidth = $clog2(BufferBytes + 1);
  localparam logic [CountWidth-1:0] BeatBytesCount = CountWidth'(BeatBytes);
  localparam logic [CountWidth-1:0] BufferBytesCount = CountWidth'(BufferBytes);

  logic [BufferBytes*8-1:0] s_buffer_d;
  logic [BufferBytes*8-1:0] s_buffer_q;
  logic [   CountWidth-1:0] s_byte_cnt_d;
  logic [   CountWidth-1:0] s_byte_cnt_q;
  logic                     s_last_pending_d;
  logic                     s_last_pending_q;
  logic                     s_err_d;
  logic                     s_err_q;
  logic [   CountWidth-1:0] s_input_byte_cnt;
  logic                     s_keep_legal;
  logic [BufferBytes*8-1:0] s_append_buffer;
  logic [   CountWidth-1:0] s_append_cnt;

  function automatic logic [BeatBytes-1:0] keep_mask(input logic [CountWidth-1:0] count_i);
    logic [BeatBytes:0] s_mask;
    begin
      s_mask = ((BeatBytes + 1)'(1) << count_i) - 1'b1;
      return s_mask[BeatBytes-1:0];
    end
  endfunction

  always_comb begin
    s_input_byte_cnt = '0;
    s_keep_legal     = input_keep_i != '0;
    for (int unsigned lane = 0; lane < BeatBytes; lane++) begin
      if (input_keep_i[lane]) begin
        s_input_byte_cnt += 1'b1;
      end else if ((lane < (BeatBytes - 1)) && input_keep_i[lane+1]) begin
        s_keep_legal = 1'b0;
      end
    end
  end

  assign input_ready_o = !s_last_pending_q && s_keep_legal &&
                         (s_input_byte_cnt <= BufferBytesCount - s_byte_cnt_q);
  assign output_axis.tdata = s_buffer_q[0+:DataWidth];
  assign output_axis.tkeep = (s_byte_cnt_q >= BeatBytesCount) ? '1 : keep_mask(s_byte_cnt_q);
  assign output_axis.tstrb = output_axis.tkeep;
  assign output_axis.tlast = s_last_pending_q && (s_byte_cnt_q <= BeatBytesCount);
  assign output_axis.tid = '0;
  assign output_axis.tdest = '0;
  assign output_axis.tuser = '0;
  assign output_axis.tvalid = (s_byte_cnt_q >= BeatBytesCount) ||
                              (s_last_pending_q && (s_byte_cnt_q != '0));
  assign error_o = s_err_q;

  always_comb begin
    s_buffer_d       = s_buffer_q;
    s_byte_cnt_d     = s_byte_cnt_q;
    s_last_pending_d = s_last_pending_q;
    s_err_d          = s_err_q;
    s_append_buffer  = s_buffer_q;
    s_append_cnt     = s_byte_cnt_q;

    if (output_axis.tvalid && output_axis.tready) begin
      if (s_byte_cnt_q > BeatBytesCount) begin
        s_buffer_d   = s_buffer_q >> DataWidth;
        s_byte_cnt_d = s_byte_cnt_q - BeatBytesCount;
      end else begin
        s_buffer_d       = '0;
        s_byte_cnt_d     = '0;
        s_last_pending_d = 1'b0;
      end
    end
    if (input_valid_i) begin
      if (!input_ready_o) begin
        s_err_d = 1'b1;
      end else begin
        s_append_buffer = s_buffer_d;
        s_append_cnt    = s_byte_cnt_d;
        for (int unsigned lane = 0; lane < BeatBytes; lane++) begin
          if (input_keep_i[lane]) begin
            s_append_buffer[s_append_cnt*8+:8] = input_data_i[lane*8+:8];
            s_append_cnt += 1'b1;
          end
        end
        s_buffer_d   = s_append_buffer;
        s_byte_cnt_d = s_append_cnt;
        if (input_last_i) begin
          s_last_pending_d = 1'b1;
        end
      end
    end
  end

  dffr #(
      .DATA_WIDTH(BufferBytes * 8)
  ) u_buffer_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_buffer_d),
      .dat_o  (s_buffer_q)
  );
  dffr #(
      .DATA_WIDTH(CountWidth)
  ) u_byte_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_byte_cnt_d),
      .dat_o  (s_byte_cnt_q)
  );
  dffr u_last_pending_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_last_pending_d),
      .dat_o  (s_last_pending_q)
  );
  dffr u_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_d),
      .dat_o  (s_err_q)
  );

`ifndef SYNTHESIS
  initial begin
    if (DataWidth != 64) begin
      $fatal(1, "jpeg_byte_joiner: data width must be 64 bits");
    end
  end
`endif
endmodule
