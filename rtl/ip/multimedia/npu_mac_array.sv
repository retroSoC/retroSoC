// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

// Dense numerical-profile-1 MAC row: 8 output positions x 8 output channels.
// One request presents eight raw INT8 activation bytes, eight raw INT8 weight
// bytes, the signed input zero point, and per-lane valid masks. An accepted
// request centers each activation to signed nine bits,
// a9 = sign_extend(byte) - sign_extend(zero point), range -255..255, and
// registers the 64 signed 9x8 products one cycle later. Masked lanes produce
// exactly zero and never raise arithmetic faults. Weight bytes are consumed
// directly as signed INT8 (zero point 0). The single registered output stage
// applies backpressure with req_ready_o = resp_ready_i || !resp_valid_o.
module npu_mac_array (
    input  logic                                                                     clk_i,
    input  logic                                                                     rst_n_i,
    input  logic                                                                     req_valid_i,
    output logic                                                                     req_ready_o,
    input  logic        [npu_pkg::SpatialLanes-1:0][                      7:0]       req_a_bytes_i,
    input  logic        [npu_pkg::ChannelLanes-1:0][                      7:0]       req_w_bytes_i,
    input  logic signed [                      7:0]                                  req_in_zero_i,
    input  logic        [npu_pkg::SpatialLanes-1:0]                                  req_a_valid_i,
    input  logic        [npu_pkg::ChannelLanes-1:0]                                  req_w_valid_i,
    output logic                                                                     resp_valid_o,
    input  logic                                                                     resp_ready_i,
    output logic        [npu_pkg::SpatialLanes-1:0][npu_pkg::ChannelLanes-1:0][16:0] resp_products_o
);
  logic [npu_pkg::SpatialLanes-1:0][npu_pkg::ChannelLanes-1:0][npu_pkg::ProductWidth-1:0]
      s_products_d;
  logic [npu_pkg::SpatialLanes-1:0][npu_pkg::ChannelLanes-1:0][npu_pkg::ProductWidth-1:0]
      s_products_q;
  logic s_resp_valid_q;

  function automatic logic signed [npu_pkg::ProductWidth-1:0] lane_product(
      input logic [7:0] a_byte_i, input logic [7:0] w_byte_i, input logic signed [7:0] in_zero_i,
      input logic lanes_valid_i);
    logic signed [npu_pkg::CenteredWidth-1:0] s_a_ext;
    logic signed [npu_pkg::CenteredWidth-1:0] s_zero_ext;
    logic signed [npu_pkg::CenteredWidth-1:0] s_centered;
    logic signed [ npu_pkg::ProductWidth-1:0] s_product;
    begin
      s_a_ext    = {a_byte_i[7], a_byte_i};
      s_zero_ext = {in_zero_i[7], in_zero_i};
      s_centered = s_a_ext - s_zero_ext;
      s_product  = s_centered * $signed(w_byte_i);
      return lanes_valid_i ? s_product : '0;
    end
  endfunction

  for (genvar position = 0; position < npu_pkg::SpatialLanes; position++) begin : gen_position
    for (genvar channel = 0; channel < npu_pkg::ChannelLanes; channel++) begin : gen_channel
      assign s_products_d[position][channel] = lane_product(
          req_a_bytes_i[position],
          req_w_bytes_i[channel],
          req_in_zero_i,
          req_a_valid_i[position] && req_w_valid_i[channel]
      );
    end
  end

  assign req_ready_o     = resp_ready_i || !s_resp_valid_q;
  assign resp_valid_o    = s_resp_valid_q;
  assign resp_products_o = s_products_q;

  // The product register is fully overwritten on every acceptance, so only the
  // handshake state needs reset.
  always_ff @(posedge clk_i) begin
    if (req_valid_i && req_ready_o) begin
      s_products_q <= s_products_d;
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_resp_valid_q <= 1'b0;
    end else if (req_valid_i && req_ready_o) begin
      s_resp_valid_q <= 1'b1;
    end else if (resp_ready_i) begin
      s_resp_valid_q <= 1'b0;
    end
  end

`ifndef SV_ASSRT_DISABLE
  logic s_req_stall_q;
  logic s_resp_stall_q;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_req_stall_q  <= 1'b0;
      s_resp_stall_q <= 1'b0;
    end else begin
      s_req_stall_q  <= req_valid_i && !req_ready_o;
      s_resp_stall_q <= resp_valid_o && !resp_ready_i;
      if (s_req_stall_q) begin
        assert ($stable(req_a_bytes_i));
        assert ($stable(req_w_bytes_i));
        assert ($stable(req_in_zero_i));
        assert ($stable(req_a_valid_i));
        assert ($stable(req_w_valid_i));
      end
      if (s_resp_stall_q) begin
        assert ($stable(resp_products_o));
      end
    end
  end
`endif
endmodule
