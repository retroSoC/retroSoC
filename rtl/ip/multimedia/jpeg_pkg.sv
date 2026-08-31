// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

package jpeg_pkg;
  typedef enum logic {
    JpegEncode,
    JpegDecode
  } jpeg_mode_e;

  typedef enum logic [2:0] {
    JpegGray8,
    JpegRgb565,
    JpegRgb888,
    JpegYuyv422,
    JpegNv12
  } jpeg_pixel_format_e;

  typedef enum logic [1:0] {
    JpegSamplingGray,
    JpegSampling444,
    JpegSampling422,
    JpegSampling420
  } jpeg_sampling_e;

  typedef enum logic [4:0] {
    JpegErrorNone,
    JpegErrorConfig,
    JpegErrorDescriptor,
    JpegErrorTable,
    JpegErrorUnsupportedMarker,
    JpegErrorUnsupportedProcess,
    JpegErrorUnsupportedPrecision,
    JpegErrorUnsupportedSampling,
    JpegErrorMalformedMarker,
    JpegErrorMalformedHuffman,
    JpegErrorTruncated,
    JpegErrorRestart,
    JpegErrorOutputOverflow,
    JpegErrorAxiRead,
    JpegErrorAxiWrite,
    JpegErrorAxiDescriptor,
    JpegErrorTimeout,
    JpegErrorAborted,
    JpegErrorInternal
  } jpeg_error_e;

  typedef enum logic [3:0] {
    JpegStageIdle,
    JpegStageDescriptor,
    JpegStageHeader,
    JpegStageInputDma,
    JpegStageColor,
    JpegStageTransform,
    JpegStageQuantize,
    JpegStageEntropy,
    JpegStageOutputDma,
    JpegStageWriteback
  } jpeg_stage_e;

  typedef struct packed {
    logic [31:0]  control;
    logic [31:0]  status;
    logic [31:0]  image_size;
    logic [31:0]  encode_config;
    logic [31:0]  restart_interval;
    logic [31:0]  bitstream_addr;
    logic [31:0]  bitstream_size;
    logic [31:0]  result_size;
    logic [31:0]  plane0_addr;
    logic [31:0]  plane0_stride;
    logic [31:0]  plane1_addr;
    logic [31:0]  plane1_stride;
    logic [31:0]  plane2_addr;
    logic [31:0]  plane2_stride;
    logic [31:0]  metadata_addr;
    logic [31:0]  metadata_length;
    logic [31:0]  cookie_lo;
    logic [31:0]  cookie_hi;
    logic [31:0]  result_image_size;
    logic [31:0]  result_format;
    logic [31:0]  cycles_lo;
    logic [31:0]  cycles_hi;
    logic [31:0]  input_bytes;
    logic [31:0]  output_bytes;
    logic [255:0] reserved;
  } jpeg_descriptor_t;

  function automatic logic pixel_format_valid(input logic [2:0] format_i);
    return format_i <= JpegNv12;
  endfunction

endpackage
