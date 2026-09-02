// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

`ifndef RETROSOC_JPEG_DEFINE_SVH
`define RETROSOC_JPEG_DEFINE_SVH

// verilog_format: off -- keep the handwritten hardware/software ABI column aligned
`define APB4_JPEG__IP_ID                  12'h000
`define APB4_JPEG__IP_VERSION             12'h004
`define APB4_JPEG__CAPABILITY0            12'h008
`define APB4_JPEG__CAPABILITY1            12'h00c
`define APB4_JPEG__COMMAND                12'h010
`define APB4_JPEG__STATUS                 12'h014
`define APB4_JPEG__IRQ_STATE              12'h018
`define APB4_JPEG__IRQ_ENABLE             12'h01c
`define APB4_JPEG__IRQ_TEST               12'h020
`define APB4_JPEG__ERROR_STATUS           12'h024
`define APB4_JPEG__ERROR_ADDRESS          12'h028
`define APB4_JPEG__ERROR_DETAIL           12'h02c
`define APB4_JPEG__PERF_CONTROL           12'h030
`define APB4_JPEG__CYCLES_LO              12'h034
`define APB4_JPEG__CYCLES_HI              12'h038
`define APB4_JPEG__PIXELS                 12'h03c
`define APB4_JPEG__INPUT_BYTES            12'h040
`define APB4_JPEG__OUTPUT_BYTES           12'h044
`define APB4_JPEG__READ_STALL             12'h048
`define APB4_JPEG__WRITE_STALL            12'h04c

`define APB4_JPEG__JOB_CONFIG             12'h080
`define APB4_JPEG__IMAGE_SIZE             12'h084
`define APB4_JPEG__INPUT_FORMAT           12'h088
`define APB4_JPEG__OUTPUT_FORMAT          12'h08c
`define APB4_JPEG__ENCODE_CONFIG          12'h090
`define APB4_JPEG__RESTART_INTERVAL       12'h094
`define APB4_JPEG__BITSTREAM_ADDR         12'h098
`define APB4_JPEG__BITSTREAM_SIZE         12'h09c
`define APB4_JPEG__PLANE0_ADDR            12'h0a0
`define APB4_JPEG__PLANE0_STRIDE          12'h0a4
`define APB4_JPEG__PLANE1_ADDR            12'h0a8
`define APB4_JPEG__PLANE1_STRIDE          12'h0ac
`define APB4_JPEG__PLANE2_ADDR            12'h0b0
`define APB4_JPEG__PLANE2_STRIDE          12'h0b4
`define APB4_JPEG__METADATA_ADDR          12'h0b8
`define APB4_JPEG__METADATA_LENGTH        12'h0bc
`define APB4_JPEG__RESULT_SIZE            12'h0c0
`define APB4_JPEG__RESULT_IMAGE_SIZE      12'h0c4
`define APB4_JPEG__RESULT_FORMAT          12'h0c8
`define APB4_JPEG__RESULT_MARKERS         12'h0cc

`define APB4_JPEG__RING_BASE              12'h100
`define APB4_JPEG__RING_SIZE              12'h104
`define APB4_JPEG__RING_HEAD              12'h108
`define APB4_JPEG__RING_TAIL              12'h10c
`define APB4_JPEG__RING_CONTROL           12'h110
`define APB4_JPEG__RING_STATUS            12'h114
`define APB4_JPEG__IRQ_COALESCE           12'h118
`define APB4_JPEG__DOORBELL               12'h11c

`define APB4_JPEG__TABLE_CONTEXT          12'h200
`define APB4_JPEG__TABLE_KIND             12'h204
`define APB4_JPEG__TABLE_INDEX            12'h208
`define APB4_JPEG__TABLE_DATA             12'h20c
`define APB4_JPEG__TABLE_COMMAND          12'h210
`define APB4_JPEG__TABLE_STATUS           12'h214

`define APB4_JPEG__COMMAND_START          0
`define APB4_JPEG__COMMAND_ABORT          1
`define APB4_JPEG__COMMAND_SOFT_RESET     2
`define APB4_JPEG__COMMAND_RING_KICK      3

`define APB4_JPEG__STATUS_BUSY            0
`define APB4_JPEG__STATUS_RING_ACTIVE     1
`define APB4_JPEG__STATUS_ENCODE          2
`define APB4_JPEG__STATUS_IDLE            3

`define APB4_JPEG__IRQ_JOB_DONE           0
`define APB4_JPEG__IRQ_RING_EVENT         1
`define APB4_JPEG__IRQ_HEADER_READY       2
`define APB4_JPEG__IRQ_ABORT_DONE         3
`define APB4_JPEG__IRQ_ERROR              4

`define APB4_JPEG__JOB_CONFIG_ENCODE      0
`define APB4_JPEG__JOB_CONFIG_AUTO_HEADER 1
`define APB4_JPEG__JOB_CONFIG_STRICT      2
`define APB4_JPEG__JOB_CONFIG_METADATA    3
`define APB4_JPEG__JOB_CONFIG_TABLE       8

`define APB4_JPEG__DESCRIPTOR_OWN         0
`define APB4_JPEG__DESCRIPTOR_IOC         1
`define APB4_JPEG__DESCRIPTOR_ENCODE      2
`define APB4_JPEG__DESCRIPTOR_AUTO_HEADER 3
`define APB4_JPEG__DESCRIPTOR_STRICT      4
`define APB4_JPEG__DESCRIPTOR_METADATA    5
`define APB4_JPEG__DESCRIPTOR_TABLE       8
`define APB4_JPEG__DESCRIPTOR_INPUT_FMT   12
`define APB4_JPEG__DESCRIPTOR_OUTPUT_FMT  16
`define APB4_JPEG__DESCRIPTOR_SAMPLING    20
`define APB4_JPEG__DESCRIPTOR_STATUS_DONE 0
`define APB4_JPEG__DESCRIPTOR_STATUS_ERR  1
`define APB4_JPEG__DESCRIPTOR_STATUS_ABORT 2
`define APB4_JPEG__DESCRIPTOR_STATUS_CODE 8

`define APB4_JPEG__RING_CONTROL_ENABLE    0
`define APB4_JPEG__RING_CONTROL_STOP_ERR  1
`define APB4_JPEG__RING_STATUS_ACTIVE     0
`define APB4_JPEG__RING_STATUS_EMPTY      1
`define APB4_JPEG__RING_STATUS_STALLED    2
`define APB4_JPEG__RING_STATUS_ERROR      3

`define APB4_JPEG__TABLE_COMMAND_COMMIT   0
`define APB4_JPEG__TABLE_COMMAND_DEFAULT  1
`define APB4_JPEG__TABLE_COMMAND_CLEAR    2
// verilog_format: on

`endif
