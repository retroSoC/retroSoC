// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "ga2d_define.svh"

package ga2d_pkg;
  typedef enum logic [1:0] {
    Fill    = `APB4_GA2D__OP_FILL,
    Copy    = `APB4_GA2D__OP_COPY,
    Convert = `APB4_GA2D__OP_CONVERT,
    Blend   = `APB4_GA2D__OP_BLEND
  } ga2d_operation_e;

  typedef enum logic [2:0] {
    Rgb565   = `APB4_GA2D__FORMAT_RGB565,
    Rgb888   = `APB4_GA2D__FORMAT_RGB888,
    Xrgb8888 = `APB4_GA2D__FORMAT_XRGB8888,
    Argb8888 = `APB4_GA2D__FORMAT_ARGB8888,
    A8       = `APB4_GA2D__FORMAT_A8
  } ga2d_format_e;

  typedef struct packed {
    logic [31:0] timeout_cycles;
    logic [31:0] job_config;
    logic [31:0] global_alpha;
    logic [31:0] color;
    logic [31:0] size;
    logic [31:0] fg_address;
    logic [31:0] fg_pitch;
    logic [31:0] fg_format;
    logic [31:0] bg_address;
    logic [31:0] bg_pitch;
    logic [31:0] bg_format;
    logic [31:0] dst_address;
    logic [31:0] dst_pitch;
    logic [31:0] dst_format;
  } ga2d_config_t;

  typedef struct packed {
    logic        valid;
    logic [6:0]  code;
    logic [3:0]  stage;
    logic [1:0]  axi_response;
    logic [31:0] address;
  } ga2d_error_t;

  typedef struct packed {
    logic [31:0] address;
    logic [31:0] pitch;
    logic [2:0]  format;
  } ga2d_plane_t;
endpackage
