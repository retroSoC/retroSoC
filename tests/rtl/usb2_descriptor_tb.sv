// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module usb2_descriptor_tb;
  logic                       [31:0] s_buffer_addr;
  logic                       [31:0] s_byte_length;
  logic                       [31:0] s_next_addr;
  logic                       [31:0] s_control;
  logic                       [31:0] s_actual_length;
  logic                       [31:0] s_status;
  logic                       [31:0] s_frame;
  logic                       [31:0] s_reserved;
  logic                       [ 3:0] s_desc_index;
  logic                              s_valid;
  usb2_pkg::usb2_desc_error_e        s_error;

  usb2_dma_descriptor #(
      .MaxDescriptors(16)
  ) u_descriptor (
      .buffer_addr_i  (s_buffer_addr),
      .byte_length_i  (s_byte_length),
      .next_addr_i    (s_next_addr),
      .control_i      (s_control),
      .actual_length_i(s_actual_length),
      .status_i       (s_status),
      .frame_i        (s_frame),
      .reserved_i     (s_reserved),
      .desc_index_i   (s_desc_index),
      .own_o          (),
      .chain_o        (),
      .end_o          (),
      .irq_o          (),
      .short_ok_o     (),
      .zero_packet_o  (),
      .valid_o        (s_valid),
      .error_o        (s_error)
  );

  initial begin
    s_buffer_addr   = 32'h2000_0000;
    s_byte_length   = 32'd512;
    s_next_addr     = 32'd0;
    s_control       = 32'h0000_000D;
    s_actual_length = 32'd0;
    s_status        = 32'd0;
    s_frame         = 32'd0;
    s_reserved      = 32'd0;
    s_desc_index    = 4'd0;
    #1;
    if (!s_valid || (s_error != usb2_pkg::Usb2DescOk)) begin
      $fatal(1, "USB2 terminal descriptor rejected");
    end

    s_buffer_addr = 32'h2000_0001;
    #1;
    if (s_valid || (s_error != usb2_pkg::Usb2DescBufferAlign)) begin
      $fatal(1, "USB2 unaligned buffer accepted");
    end

    s_buffer_addr = 32'hFFFF_FFFC;
    s_byte_length = 32'd8;
    #1;
    if (s_valid || (s_error != usb2_pkg::Usb2DescAddressWrap)) begin
      $fatal(1, "USB2 wrapping buffer accepted");
    end

    s_buffer_addr = 32'h2000_0000;
    s_byte_length = 32'd512;
    s_control     = 32'h0000_0003;
    s_next_addr   = 32'h2000_0FE0;
    #1;
    if (!s_valid) begin
      $fatal(1, "USB2 aligned chained descriptor rejected");
    end

    s_next_addr = 32'h2000_0FF0;
    #1;
    if (s_valid || (s_error != usb2_pkg::Usb2DescNextAlign)) begin
      $fatal(1, "USB2 descriptor crossing 4 KiB boundary accepted");
    end
    $display("USB2 descriptor validation passed");
    $finish;
  end
endmodule
