// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

module jpeg_byte_unpacker #(
    parameter int unsigned DataWidth = 64
) (
    // verilog_format: off -- preserve AXI stream and byte interface columns
    input  logic              clk_i,
    input  logic              rst_n_i,
    axi4_stream_if.sink       input_axis,
    output logic [7:0]        byte_o,
    output logic              byte_valid_o,
    input  logic              byte_ready_i,
    output logic              byte_last_o,
    output logic              error_o
    // verilog_format: on
);
  localparam int unsigned ByteCount = DataWidth / 8;
  localparam int unsigned IndexWidth = $clog2(ByteCount);

  logic [ DataWidth-1:0] s_data_d;
  logic [ DataWidth-1:0] s_data_q;
  logic [ ByteCount-1:0] s_keep_d;
  logic [ ByteCount-1:0] s_keep_q;
  logic [IndexWidth-1:0] s_index_d;
  logic [IndexWidth-1:0] s_index_q;
  logic                  s_last_d;
  logic                  s_last_q;
  logic                  s_valid_d;
  logic                  s_valid_q;
  logic                  s_err_d;
  logic                  s_err_q;
  logic [IndexWidth-1:0] s_last_index;
  logic                  s_keep_legal;

  always_comb begin
    s_last_index = '0;
    s_keep_legal = input_axis.tkeep != '0;
    for (int unsigned index = 0; index < ByteCount; index++) begin
      if (s_keep_q[index]) begin
        s_last_index = IndexWidth'(index);
      end
      if (!input_axis.tkeep[index] && index < (ByteCount - 1) && input_axis.tkeep[index+1]) begin
        s_keep_legal = 1'b0;
      end
    end
    if (input_axis.tkeep != input_axis.tstrb) begin
      s_keep_legal = 1'b0;
    end
  end

  assign input_axis.tready = !s_valid_q ||
                             (byte_valid_o && byte_ready_i && (s_index_q == s_last_index));
  assign byte_o = s_data_q[s_index_q*8+:8];
  assign byte_valid_o = s_valid_q;
  assign byte_last_o = s_last_q && (s_index_q == s_last_index);
  assign error_o = s_err_q;

  always_comb begin
    s_data_d  = s_data_q;
    s_keep_d  = s_keep_q;
    s_index_d = s_index_q;
    s_last_d  = s_last_q;
    s_valid_d = s_valid_q;
    s_err_d   = s_err_q;

    if (byte_valid_o && byte_ready_i) begin
      if (s_index_q == s_last_index) begin
        s_valid_d = 1'b0;
      end else begin
        s_index_d = s_index_q + 1'b1;
      end
    end
    if (input_axis.tvalid && input_axis.tready) begin
      s_data_d  = input_axis.tdata;
      s_keep_d  = input_axis.tkeep;
      s_index_d = '0;
      s_last_d  = input_axis.tlast;
      s_valid_d = s_keep_legal;
      if (!s_keep_legal) begin
        s_err_d = 1'b1;
      end
    end
  end

  dffr #(
      .DATA_WIDTH(DataWidth)
  ) u_data_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_data_d),
      .dat_o  (s_data_q)
  );
  dffr #(
      .DATA_WIDTH(ByteCount)
  ) u_keep_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_keep_d),
      .dat_o  (s_keep_q)
  );
  dffr #(
      .DATA_WIDTH(IndexWidth)
  ) u_index_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_index_d),
      .dat_o  (s_index_q)
  );
  dffr u_last_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_last_d),
      .dat_o  (s_last_q)
  );
  dffr u_valid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_valid_d),
      .dat_o  (s_valid_q)
  );
  dffr u_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_d),
      .dat_o  (s_err_q)
  );

`ifndef SYNTHESIS
  initial begin
    if ((DataWidth < 8) || ((DataWidth % 8) != 0) || ((DataWidth & (DataWidth - 1)) != 0)) begin
      $fatal(1, "jpeg_byte_unpacker: data width must be a power-of-two byte multiple");
    end
  end
`endif
endmodule
