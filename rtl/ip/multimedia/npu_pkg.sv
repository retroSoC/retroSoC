// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

package npu_pkg;
  // Frozen compute geometry: 8 output positions x 8 output channels dense,
  // eight depthwise lanes, one pipelined scalar requantizer.
  localparam int unsigned SpatialLanes = 8;
  localparam int unsigned ChannelLanes = 8;
  localparam int unsigned DenseMacCount = SpatialLanes * ChannelLanes;
  localparam int unsigned DepthwiseLanes = 8;
  localparam int unsigned MaxTilePositions = 8;
  localparam int unsigned MaxKSlice = 1024;
  // Sixteen 1024x32 banks = 64 KiB private storage, frozen partition map:
  // raw gather 0x0000..0x3fff, packed A 0x4000..0x7fff, packed W 0x8000..0xbfff,
  // output staging 0xc000..0xdfff, descriptor/parameter 0xe000..0xffff.
  localparam int unsigned BankCount = 16;
  localparam int unsigned BankAddrWidth = 10;
  localparam int unsigned BankBytes = 4096;
  localparam int unsigned LocalBytes = BankCount * BankBytes;
  localparam int unsigned RawBankFirst = 0;
  localparam int unsigned PackABankFirst = 4;
  localparam int unsigned PackWBankFirst = 8;
  localparam int unsigned OutBankFirst = 12;
  localparam int unsigned ParamBankFirst = 14;
  // Two accumulator contexts, each 8x8 checked INT32 sums.
  localparam int unsigned AccContextCount = 2;
  localparam int unsigned AccSumCount = DenseMacCount;
  // Numerical profile 1 widths: centered signed nine-bit activations,
  // signed eight-bit weights, signed 9x8 products, checked INT32 sums.
  localparam int unsigned CenteredWidth = 9;
  localparam int unsigned WeightWidth = 8;
  localparam int unsigned AccWidth = 32;
  localparam int unsigned ProductWidth = 17;

  typedef logic signed [CenteredWidth-1:0] centered_t;
  typedef logic signed [WeightWidth-1:0] weight_t;
  typedef logic signed [AccWidth-1:0] acc_t;
  typedef logic signed [ProductWidth-1:0] product_t;

  typedef enum logic [0:0] {
    PackDense,
    PackDepthwise
  } pack_mode_e;
endpackage
