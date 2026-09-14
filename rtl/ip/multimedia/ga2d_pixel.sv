// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "ga2d_define.svh"

module ga2d_pixel (
    input  logic [31:0] color_i,
    input  logic [ 2:0] format_i,
    output logic [31:0] pixel_o,
    output logic [ 2:0] bytes_per_pixel_o,
    output logic        format_valid_o
);
  always_comb begin
    pixel_o           = '0;
    bytes_per_pixel_o = '0;
    format_valid_o    = 1'b1;
    unique case (format_i)
      `APB4_GA2D__FORMAT_RGB565: begin
        pixel_o           = {16'd0, color_i[23:19], color_i[15:10], color_i[7:3]};
        bytes_per_pixel_o = 3'd2;
      end
      `APB4_GA2D__FORMAT_RGB888: begin
        pixel_o           = {8'd0, color_i[7:0], color_i[15:8], color_i[23:16]};
        bytes_per_pixel_o = 3'd3;
      end
      `APB4_GA2D__FORMAT_XRGB8888: begin
        pixel_o           = {8'hff, color_i[23:0]};
        bytes_per_pixel_o = 3'd4;
      end
      `APB4_GA2D__FORMAT_ARGB8888: begin
        pixel_o           = color_i;
        bytes_per_pixel_o = 3'd4;
      end
      default: begin
        format_valid_o = 1'b0;
      end
    endcase
  end
endmodule
