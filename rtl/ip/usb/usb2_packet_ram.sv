// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module usb2_packet_ram #(
    parameter bit EnableFaultInjection = 1'b0
) (
    // verilog_format: off -- preserve the memory request/response grouping
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        write_i,
    input  logic        read_i,
    input  logic [11:0] addr_i,
    input  logic [31:0] write_data_i,
    input  logic        inject_single_i,
    input  logic        inject_double_i,
    output logic [31:0] read_data_o,
    output logic        read_valid_o,
    output logic        corrected_o,
    output logic        uncorrectable_o
    // verilog_format: on
);
  logic [38:0] s_write_code;
  logic [38:0] s_write_code_injected;
  logic [39:0] s_physical_write;
  logic [39:0] s_physical_read;
  logic [38:0] s_read_code;
  logic        s_read_pending_d;
  logic        s_read_pending_q;
  logic        s_decode_corrected;
  logic        s_decode_uncorrectable;
  logic        s_overall_parity_err;
  logic [ 5:0] s_syndrome;

  secded_encode #(
      .DATA_WIDTH(32)
  ) u_encode (
      .data_i(write_data_i),
      .code_o(s_write_code)
  );

  always_comb begin
    s_write_code_injected = s_write_code;
    if (EnableFaultInjection && inject_single_i) begin
      s_write_code_injected[0] = ~s_write_code[0];
    end
    if (EnableFaultInjection && inject_double_i) begin
      s_write_code_injected[0] = ~s_write_code[0];
      s_write_code_injected[1] = ~s_write_code[1];
    end
  end

  assign s_physical_write = {1'b0, s_write_code_injected};
  assign s_read_code = s_physical_read[38:0];
  assign s_read_pending_d = read_i;
  assign read_valid_o = s_read_pending_q;
  assign corrected_o = s_read_pending_q &&
                       (s_decode_corrected || s_overall_parity_err || s_physical_read[39]);
  assign uncorrectable_o = s_read_pending_q && s_decode_uncorrectable && (s_syndrome != 6'd0);

  tc_usb2_packet_ram u_packet_ram (
      .clk_i  (clk_i),
      .cs_i   (write_i || read_i),
      .write_i(write_i),
      .addr_i (addr_i),
      .data_i (s_physical_write),
      .data_o (s_physical_read)
  );

  secded_decode #(
      .DATA_WIDTH(32)
  ) u_decode (
      .code_i                (s_read_code),
      .data_o                (read_data_o),
      .syndrome_o            (s_syndrome),
      .corrected_o           (s_decode_corrected),
      .overall_parity_error_o(s_overall_parity_err),
      .uncorrectable_o       (s_decode_uncorrectable)
  );

  dffr #(
      .DATA_WIDTH(1)
  ) u_read_pending_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_pending_d),
      .dat_o  (s_read_pending_q)
  );

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (rst_n_i && write_i && read_i) begin
      $error("usb2_packet_ram: simultaneous read and write request");
    end
  end
`endif
endmodule
