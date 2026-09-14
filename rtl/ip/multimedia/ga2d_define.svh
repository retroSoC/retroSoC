// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`ifndef RETROSOC_GA2D_DEFINE_SVH
`define RETROSOC_GA2D_DEFINE_SVH

// verilog_format: off -- keep the handwritten hardware/software ABI columns aligned
`define APB4_GA2D__IP_ID                       12'h000
`define APB4_GA2D__IP_VERSION                  12'h004
`define APB4_GA2D__CAPABILITY                  12'h008
`define APB4_GA2D__LIMITS                      12'h00c
`define APB4_GA2D__COMMAND                     12'h010
`define APB4_GA2D__STATUS                      12'h014
`define APB4_GA2D__IRQ_STATE                   12'h018
`define APB4_GA2D__IRQ_ENABLE                  12'h01c
`define APB4_GA2D__IRQ_TEST                    12'h020
`define APB4_GA2D__ERROR_STATUS                12'h024
`define APB4_GA2D__ERROR_ADDRESS               12'h028
`define APB4_GA2D__TIMEOUT_CYCLES              12'h02c
`define APB4_GA2D__JOB_CONFIG                  12'h030
`define APB4_GA2D__GLOBAL_ALPHA                12'h034
`define APB4_GA2D__COLOR                       12'h038
`define APB4_GA2D__SIZE                        12'h03c
`define APB4_GA2D__FG_ADDRESS                  12'h040
`define APB4_GA2D__FG_PITCH                    12'h044
`define APB4_GA2D__FG_FORMAT                   12'h048
`define APB4_GA2D__BG_ADDRESS                  12'h04c
`define APB4_GA2D__BG_PITCH                    12'h050
`define APB4_GA2D__BG_FORMAT                   12'h054
`define APB4_GA2D__DST_ADDRESS                 12'h058
`define APB4_GA2D__DST_PITCH                   12'h05c
`define APB4_GA2D__DST_FORMAT                  12'h060
`define APB4_GA2D__PERF_SNAPSHOT               12'h064
`define APB4_GA2D__FORMAT_CAPABILITY           12'h068
`define APB4_GA2D__SNAP_CYCLES_LO              12'h080
`define APB4_GA2D__SNAP_CYCLES_HI              12'h084
`define APB4_GA2D__SNAP_READ_BYTES_LO          12'h088
`define APB4_GA2D__SNAP_READ_BYTES_HI          12'h08c
`define APB4_GA2D__SNAP_WRITE_BYTES_LO         12'h090
`define APB4_GA2D__SNAP_WRITE_BYTES_HI         12'h094
`define APB4_GA2D__SNAP_READ_STALL_LO          12'h098
`define APB4_GA2D__SNAP_READ_STALL_HI          12'h09c
`define APB4_GA2D__SNAP_WRITE_STALL_LO         12'h0a0
`define APB4_GA2D__SNAP_WRITE_STALL_HI         12'h0a4
`define APB4_GA2D__SNAP_PIPE_STALL_LO          12'h0a8
`define APB4_GA2D__SNAP_PIPE_STALL_HI          12'h0ac
`define APB4_GA2D__SNAP_LINES_DONE             12'h0b0

`define APB4_GA2D__IP_ID_VALUE                 32'h4741_3244
`define APB4_GA2D__IP_VERSION_VALUE            32'h0001_0000
`define APB4_GA2D__CAPABILITY_P4               32'h0000_03e3
`define APB4_GA2D__LIMITS_P4                   32'h0820_2010
`define APB4_GA2D__FORMAT_CAPABILITY_P4        32'h000f_000f
`define APB4_GA2D__TIMEOUT_CYCLES_RESET        32'h0010_0000
`define APB4_GA2D__GLOBAL_ALPHA_RESET          32'h0000_00ff

`define APB4_GA2D__COMMAND_START               0
`define APB4_GA2D__COMMAND_ABORT               1
`define APB4_GA2D__COMMAND_SOFT_RESET          2

`define APB4_GA2D__STATUS_BUSY                 0
`define APB4_GA2D__STATUS_DRAINING             1
`define APB4_GA2D__STATUS_QUIESCED             2
`define APB4_GA2D__STATUS_DATA_READY           3
`define APB4_GA2D__STATUS_DONE                 4
`define APB4_GA2D__STATUS_ABORTED              5
`define APB4_GA2D__STATUS_ERROR                6
`define APB4_GA2D__STATUS_RECOVERY_REQUIRED    7

`define APB4_GA2D__IRQ_DONE                    0
`define APB4_GA2D__IRQ_ERROR                   1
`define APB4_GA2D__IRQ_ABORT_DONE              2
`define APB4_GA2D__IRQ_ALL                     3'h7

`define APB4_GA2D__ERROR_STATUS_VALID          0
`define APB4_GA2D__ERROR_STATUS_CODE           1
`define APB4_GA2D__ERROR_STATUS_STAGE          8
`define APB4_GA2D__ERROR_STATUS_AXI_RESPONSE   12

`define APB4_GA2D__JOB_CONFIG_OPERATION        0
`define APB4_GA2D__GLOBAL_ALPHA_VALUE          0
`define APB4_GA2D__SIZE_WIDTH                  0
`define APB4_GA2D__SIZE_HEIGHT                 16
`define APB4_GA2D__FG_FORMAT_VALUE             0
`define APB4_GA2D__BG_FORMAT_VALUE             0
`define APB4_GA2D__DST_FORMAT_VALUE            0
`define APB4_GA2D__FORMAT_CAPABILITY_FOREGROUND 0
`define APB4_GA2D__FORMAT_CAPABILITY_BACKGROUND 8
`define APB4_GA2D__FORMAT_CAPABILITY_DESTINATION 16

`define APB4_GA2D__CAPABILITY_FILL             0
`define APB4_GA2D__CAPABILITY_COPY             1
`define APB4_GA2D__CAPABILITY_CONVERT          2
`define APB4_GA2D__CAPABILITY_BLEND            3
`define APB4_GA2D__CAPABILITY_A8_MASK          4
`define APB4_GA2D__CAPABILITY_PRIVATE_DMA      5
`define APB4_GA2D__CAPABILITY_IRQ              6
`define APB4_GA2D__CAPABILITY_SNAPSHOT         7
`define APB4_GA2D__CAPABILITY_TWO_DIMENSIONAL_PITCH 8
`define APB4_GA2D__CAPABILITY_BYTE_EDGES       9
`define APB4_GA2D__CAPABILITY_INPLACE_BACKGROUND 10

`define APB4_GA2D__OP_FILL                     0
`define APB4_GA2D__OP_COPY                     1
`define APB4_GA2D__OP_CONVERT                  2
`define APB4_GA2D__OP_BLEND                    3

`define APB4_GA2D__FORMAT_RGB565               0
`define APB4_GA2D__FORMAT_RGB888               1
`define APB4_GA2D__FORMAT_XRGB8888             2
`define APB4_GA2D__FORMAT_ARGB8888             3
`define APB4_GA2D__FORMAT_A8                   4

`define APB4_GA2D__ERROR_NONE                  0
`define APB4_GA2D__ERROR_INVALID_SIZE          1
`define APB4_GA2D__ERROR_INVALID_FORMAT        2
`define APB4_GA2D__ERROR_INVALID_PITCH         3
`define APB4_GA2D__ERROR_INVALID_ALIGNMENT     4
`define APB4_GA2D__ERROR_ADDRESS_OVERFLOW      5
`define APB4_GA2D__ERROR_ADDRESS_RANGE         6
`define APB4_GA2D__ERROR_OVERLAP               7
`define APB4_GA2D__ERROR_AXI_READ              8
`define APB4_GA2D__ERROR_AXI_WRITE             9
`define APB4_GA2D__ERROR_AXI_PROTOCOL          10
`define APB4_GA2D__ERROR_TIMEOUT               11
`define APB4_GA2D__ERROR_EPOCH_LOST            12
`define APB4_GA2D__ERROR_INTERNAL              13

`define APB4_GA2D__ERROR_STAGE_NONE            0
`define APB4_GA2D__ERROR_STAGE_VALIDATE        1
`define APB4_GA2D__ERROR_STAGE_FOREGROUND      2
`define APB4_GA2D__ERROR_STAGE_BACKGROUND      3
`define APB4_GA2D__ERROR_STAGE_DESTINATION     4
`define APB4_GA2D__ERROR_STAGE_LIFECYCLE       5
// verilog_format: on

`endif
