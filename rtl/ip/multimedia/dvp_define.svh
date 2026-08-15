// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

`ifndef RIBP_DVP_DEFINE_SVH
`define RIBP_DVP_DEFINE_SVH

// verilog_format: off -- preserve reviewed column alignment
`define RIBP_DVP_CTRL                    12'h000
`define RIBP_DVP_RXDATA                  12'h004
`define RIBP_DVP_STATUS                  12'h008
`define RIBP_DVP_STREAM_CTRL             12'h00C
`define RIBP_DVP_FORMAT                  12'h010
`define RIBP_DVP_SYNC_CFG                12'h014
`define RIBP_DVP_FRAME_SIZE              12'h018
`define RIBP_DVP_CROP_START              12'h01C
`define RIBP_DVP_CROP_SIZE               12'h020
`define RIBP_DVP_FRAME_COUNT             12'h024
`define RIBP_DVP_LINE_COUNT              12'h028
`define RIBP_DVP_PIXEL_COUNT             12'h02C
`define RIBP_DVP_WORD_COUNT              12'h030
`define RIBP_DVP_DROP_COUNT              12'h034
`define RIBP_DVP_ERROR_STATUS            12'h038
`define RIBP_DVP_INTR_STATE              12'h03C
`define RIBP_DVP_INTR_ENABLE             12'h040
`define RIBP_DVP_INTR_STATUS             12'h044
`define RIBP_DVP_INTR_TEST               12'h048
`define RIBP_DVP_COMMAND                 12'h04C
`define RIBP_DVP_IP_VERSION              12'h0F8
`define RIBP_DVP_CAPABILITY              12'h0FC

`define RIBP_DVP__CTRL_ENABLE            0
`define RIBP_DVP__CTRL_SNAPSHOT          1
`define RIBP_DVP__CTRL_CROP_ENABLE       2
`define RIBP_DVP__STREAM_ENABLE          0
`define RIBP_DVP__FORMAT_SELECT          1:0
`define RIBP_DVP__FORMAT_BYTE_SWAP       2
`define RIBP_DVP__FORMAT_PIXEL_SWAP      3
`define RIBP_DVP__SYNC_VSYNC_LOW         0
`define RIBP_DVP__SYNC_HREF_LOW          1
`define RIBP_DVP__SYNC_PCLK_FALLING      2

`define RIBP_DVP__INTR_FRAME_START       0
`define RIBP_DVP__INTR_LINE_DONE         1
`define RIBP_DVP__INTR_FRAME_DONE        2
`define RIBP_DVP__INTR_OVERFLOW          3
`define RIBP_DVP__INTR_SYNC_ERROR        4
`define RIBP_DVP__INTR_CONFIG_ERROR      5
`define RIBP_DVP__INTR_ABORTED           6
`define RIBP_DVP__INTR_ALL               7'h7F

`define RIBP_DVP__ERROR_OVERFLOW         0
`define RIBP_DVP__ERROR_SYNC             1
`define RIBP_DVP__ERROR_SIZE             2
`define RIBP_DVP__ERROR_PARTIAL          3
`define RIBP_DVP__ERROR_CONFIG           4
`define RIBP_DVP__ERROR_ABORT            5
`define RIBP_DVP__ERROR_ALL              6'h3F

`define RIBP_DVP__COMMAND_ABORT          0
`define RIBP_DVP__COMMAND_FLUSH          1
// verilog_format: on

`endif
