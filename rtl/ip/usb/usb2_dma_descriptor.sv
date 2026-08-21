// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module usb2_dma_descriptor #(
    parameter int MaxDescriptors = 256
) (
    // verilog_format: off -- descriptor ABI ports are kept in word order
    input  logic [31:0]                 buffer_addr_i,
    input  logic [31:0]                 byte_length_i,
    input  logic [31:0]                 next_addr_i,
    input  logic [31:0]                 control_i,
    input  logic [31:0]                 actual_length_i,
    input  logic [31:0]                 status_i,
    // Bits 26:0 are software scheduling metadata.
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0]                 frame_i,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [31:0]                 reserved_i,
    input
        logic [$clog2(MaxDescriptors)-1:0]    desc_index_i,
    output logic                        own_o,
    output logic                        chain_o,
    output logic                        end_o,
    output logic                        irq_o,
    output logic                        short_ok_o,
    output logic                        zero_packet_o,
    output logic                        valid_o,
    output usb2_pkg::usb2_desc_error_e  error_o
    // verilog_format: on
);
  logic                            s_control_reserved;
  logic                            s_runtime_dirty;
  logic                            s_next_required;
  logic                            s_last_allowed;
  logic [$clog2(MaxDescriptors):0] s_descriptor_position;

  assign own_o = control_i[usb2_pkg::USB2_DESC_OWN];
  assign chain_o = control_i[usb2_pkg::USB2_DESC_CHAIN];
  assign end_o = control_i[usb2_pkg::USB2_DESC_END];
  assign irq_o = control_i[usb2_pkg::USB2_DESC_IRQ];
  assign short_ok_o = control_i[usb2_pkg::USB2_DESC_SHORT_OK];
  assign zero_packet_o = control_i[usb2_pkg::USB2_DESC_ZERO_PACKET];
  assign s_control_reserved = (control_i[15:6] != 10'd0) || (control_i[31:24] != 8'd0);
  assign s_runtime_dirty = (actual_length_i != 32'd0) || (status_i != 32'd0);
  assign s_next_required = !end_o || chain_o;
  assign s_descriptor_position = {1'b0, desc_index_i} + 1'b1;
  assign s_last_allowed = s_descriptor_position < ($clog2(MaxDescriptors) + 1)'(MaxDescriptors);

  always_comb begin
    error_o = usb2_pkg::Usb2DescOk;
    if (!own_o) begin
      error_o = usb2_pkg::Usb2DescNotOwned;
    end else if (s_control_reserved || s_runtime_dirty || (reserved_i != 32'd0)) begin
      error_o = usb2_pkg::Usb2DescReserved;
    end else if (buffer_addr_i[1:0] != 2'b00) begin
      error_o = usb2_pkg::Usb2DescBufferAlign;
    end else if (byte_length_i == 32'd0) begin
      error_o = usb2_pkg::Usb2DescLength;
    end else if (usb2_pkg::usb2_range_wraps(buffer_addr_i, byte_length_i)) begin
      error_o = usb2_pkg::Usb2DescAddressWrap;
    end else if (s_next_required &&
                 ((next_addr_i[4:0] != 5'd0) || (next_addr_i[11:0] > 12'hFE0))) begin
      error_o = usb2_pkg::Usb2DescNextAlign;
    end else if (end_o ? ((next_addr_i != 32'd0) || chain_o) :
                           (!chain_o || (next_addr_i == 32'd0) || !s_last_allowed)) begin
      error_o = usb2_pkg::Usb2DescChain;
    end else if (frame_i[31:27] != 5'd0) begin
      error_o = usb2_pkg::Usb2DescFrameReserved;
    end
  end

  assign valid_o = error_o == usb2_pkg::Usb2DescOk;

`ifndef SYNTHESIS
  initial begin
    if (MaxDescriptors < 2) begin
      $fatal(1, "usb2_dma_descriptor: MaxDescriptors must be at least two");
    end
  end
`endif
endmodule
