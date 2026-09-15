// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "ga2d_define.svh"

module ga2d_pixel (
    input  logic [ 1:0] operation_i,
    input  logic [31:0] foreground_pixel_i,
    input  logic [31:0] background_pixel_i,
    input  logic [31:0] color_i,
    input  logic [ 7:0] global_alpha_i,
    input  logic [ 2:0] foreground_format_i,
    input  logic [ 2:0] background_format_i,
    input  logic [ 2:0] destination_format_i,
    output logic [31:0] pixel_o,
    output logic [ 2:0] bytes_per_pixel_o,
    output logic        format_valid_o
);
  logic [31:0] s_foreground_rgba;
  logic [31:0] s_background_rgba;
  logic [ 7:0] s_foreground_alpha;
  logic [15:0] s_alpha_product;
  logic [ 7:0] s_effective_alpha;
  logic [ 7:0] s_red;
  logic [ 7:0] s_green;
  logic [ 7:0] s_blue;
  logic [ 7:0] s_alpha;

  function automatic logic [31:0] unpack_color(input logic [31:0] pixel_i,
                                               input logic [2:0] format_i);
    logic [7:0] s_red;
    logic [7:0] s_green;
    logic [7:0] s_blue;
    logic [7:0] s_alpha;
    begin
      s_red   = '0;
      s_green = '0;
      s_blue  = '0;
      s_alpha = 8'hff;
      unique case (format_i)
        `APB4_GA2D__FORMAT_RGB565: begin
          s_red   = {pixel_i[15:11], pixel_i[15:13]};
          s_green = {pixel_i[10:5], pixel_i[10:9]};
          s_blue  = {pixel_i[4:0], pixel_i[4:2]};
        end
        `APB4_GA2D__FORMAT_RGB888: begin
          s_red   = pixel_i[7:0];
          s_green = pixel_i[15:8];
          s_blue  = pixel_i[23:16];
        end
        `APB4_GA2D__FORMAT_XRGB8888: begin
          s_red   = pixel_i[23:16];
          s_green = pixel_i[15:8];
          s_blue  = pixel_i[7:0];
        end
        `APB4_GA2D__FORMAT_ARGB8888: begin
          s_red   = pixel_i[23:16];
          s_green = pixel_i[15:8];
          s_blue  = pixel_i[7:0];
          s_alpha = pixel_i[31:24];
        end
        default: begin
        end
      endcase
      return {s_alpha, s_red, s_green, s_blue};
    end
  endfunction

  function automatic logic [7:0] blend_channel(
      input logic [7:0] foreground_i, input logic [7:0] background_i, input logic [7:0] alpha_i);
    logic [16:0] s_foreground_term;
    logic [16:0] s_background_term;
    logic [16:0] s_numerator;
    begin
      s_foreground_term = {9'd0, foreground_i} * {9'd0, alpha_i};
      s_background_term = {9'd0, background_i} * ({9'd0, 8'hff} - {9'd0, alpha_i});
      s_numerator       = s_foreground_term + s_background_term + 17'd127;
      return s_numerator / 17'd255;
    end
  endfunction

  always_comb begin
    pixel_o            = '0;
    bytes_per_pixel_o  = '0;
    format_valid_o     = 1'b1;
    s_foreground_rgba  = unpack_color(foreground_pixel_i, foreground_format_i);
    s_background_rgba  = unpack_color(background_pixel_i, background_format_i);
    s_foreground_alpha = s_foreground_rgba[31:24];
    s_alpha_product    = {8'd0, s_foreground_alpha} * {8'd0, global_alpha_i};
    s_effective_alpha  = (s_alpha_product + 16'd127) / 16'd255;
    s_red              = color_i[23:16];
    s_green            = color_i[15:8];
    s_blue             = color_i[7:0];
    s_alpha            = color_i[31:24];

    if (operation_i == `APB4_GA2D__OP_COPY) begin
      pixel_o = foreground_pixel_i;
    end else if (operation_i == `APB4_GA2D__OP_CONVERT) begin
      s_red = s_foreground_rgba[23:16];
      s_green = s_foreground_rgba[15:8];
      s_blue = s_foreground_rgba[7:0];
      s_alpha = ((foreground_format_i == `APB4_GA2D__FORMAT_ARGB8888) &&
                 (destination_format_i == `APB4_GA2D__FORMAT_ARGB8888)) ?
          s_foreground_rgba[31:24] : 8'hff;
    end else if (operation_i == `APB4_GA2D__OP_BLEND) begin
      if (foreground_format_i == `APB4_GA2D__FORMAT_A8) begin
        s_foreground_alpha = foreground_pixel_i[7:0];
        s_red              = color_i[23:16];
        s_green            = color_i[15:8];
        s_blue             = color_i[7:0];
      end else begin
        s_red   = s_foreground_rgba[23:16];
        s_green = s_foreground_rgba[15:8];
        s_blue  = s_foreground_rgba[7:0];
      end
      s_alpha_product   = {8'd0, s_foreground_alpha} * {8'd0, global_alpha_i};
      s_effective_alpha = (s_alpha_product + 16'd127) / 16'd255;
      s_red             = blend_channel(s_red, s_background_rgba[23:16], s_effective_alpha);
      s_green           = blend_channel(s_green, s_background_rgba[15:8], s_effective_alpha);
      s_blue            = blend_channel(s_blue, s_background_rgba[7:0], s_effective_alpha);
      s_alpha           = 8'hff;
    end

    unique case (destination_format_i)
      `APB4_GA2D__FORMAT_RGB565: begin
        if (operation_i != `APB4_GA2D__OP_COPY) begin
          pixel_o = {16'd0, s_red[7:3], s_green[7:2], s_blue[7:3]};
        end
        bytes_per_pixel_o = 3'd2;
      end
      `APB4_GA2D__FORMAT_RGB888: begin
        if (operation_i != `APB4_GA2D__OP_COPY) begin
          pixel_o = {8'd0, s_blue, s_green, s_red};
        end
        bytes_per_pixel_o = 3'd3;
      end
      `APB4_GA2D__FORMAT_XRGB8888: begin
        if (operation_i != `APB4_GA2D__OP_COPY) begin
          pixel_o = {8'hff, s_red, s_green, s_blue};
        end
        bytes_per_pixel_o = 3'd4;
      end
      `APB4_GA2D__FORMAT_ARGB8888: begin
        if (operation_i != `APB4_GA2D__OP_COPY) begin
          pixel_o = {s_alpha, s_red, s_green, s_blue};
        end
        bytes_per_pixel_o = 3'd4;
      end
      default: begin
        format_valid_o = 1'b0;
      end
    endcase
  end
endmodule
