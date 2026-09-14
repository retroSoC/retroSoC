// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module ga2d_addr_gen (
    input  logic [ 2:0] read_address_lsb_i,
    input  logic [31:0] read_remaining_i,
    input  logic [31:0] write_address_i,
    input  logic [ 7:0] write_byte_i,
    output logic [ 3:0] read_bytes_o,
    output logic [ 2:0] read_size_o,
    output logic [31:0] write_address_o,
    output logic [63:0] write_data_o,
    output logic [ 7:0] write_strobe_o
);
  logic [3:0] s_read_to_alignment;

  always_comb begin
    s_read_to_alignment = 4'd8 - {1'b0, read_address_lsb_i};
    read_bytes_o        = 4'd1;
    if ((read_address_lsb_i == 3'd0) && (read_remaining_i >= 32'd8)) begin
      read_bytes_o = 4'd8;
    end else if ((read_address_lsb_i[1:0] == 2'd0) && (s_read_to_alignment >= 4'd4) &&
                 (read_remaining_i >= 32'd4)) begin
      read_bytes_o = 4'd4;
    end else if ((read_address_lsb_i[0] == 1'b0) && (s_read_to_alignment >= 4'd2) &&
                 (read_remaining_i >= 32'd2)) begin
      read_bytes_o = 4'd2;
    end

    unique case (read_bytes_o)
      4'd8:    read_size_o = 3'd3;
      4'd4:    read_size_o = 3'd2;
      4'd2:    read_size_o = 3'd1;
      default: read_size_o = 3'd0;
    endcase

    write_address_o = {write_address_i[31:3], 3'b000};
    write_data_o    = ({56'd0, write_byte_i} << {write_address_i[2:0], 3'b000});
    write_strobe_o  = (8'b0000_0001 << write_address_i[2:0]);
  end
endmodule
