// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// See LICENSE for the complete license text.

`ifndef RETROSOC_SPISD_DEFINE_SVH
`define RETROSOC_SPISD_DEFINE_SVH

// verilog_format: off -- preserve the reviewed APB ABI column alignment
`define APB4_SPISD__IP_ID                    12'h000
`define APB4_SPISD__IP_VERSION               12'h004
`define APB4_SPISD__CAPABILITY               12'h008
`define APB4_SPISD__HOST_CTRL                12'h00C
`define APB4_SPISD__CLOCK_CTRL               12'h010
`define APB4_SPISD__CLOCK_ACTUAL             12'h014
`define APB4_SPISD__TIMEOUT_CMD              12'h018
`define APB4_SPISD__TIMEOUT_DATA             12'h01C
`define APB4_SPISD__TIMEOUT_BUSY             12'h020
`define APB4_SPISD__STATUS                   12'h024

`define APB4_SPISD__CMD_ARG                  12'h040
`define APB4_SPISD__CMD_CFG                  12'h044
`define APB4_SPISD__CMD_START                12'h048
`define APB4_SPISD__CMD_STATUS               12'h04C
`define APB4_SPISD__RESP0                    12'h050
`define APB4_SPISD__RESP1                    12'h054

`define APB4_SPISD__BLOCK_SIZE               12'h080
`define APB4_SPISD__BLOCK_COUNT              12'h084
`define APB4_SPISD__DATA_CFG                 12'h088
`define APB4_SPISD__PIO_DATA                 12'h08C
`define APB4_SPISD__DATA_STATUS              12'h090
`define APB4_SPISD__FIFO_STATUS              12'h094

`define APB4_SPISD__DESC_BASE                12'h0C0
`define APB4_SPISD__DESC_COUNT               12'h0C4
`define APB4_SPISD__DMA_CTRL                 12'h0C8
`define APB4_SPISD__DMA_STATUS               12'h0CC
`define APB4_SPISD__CURRENT_DESC             12'h0D0
`define APB4_SPISD__BYTES_DONE               12'h0D4
`define APB4_SPISD__DMA_ERROR_ADDR            12'h0D8
`define APB4_SPISD__DMA_ERROR                 12'h0DC

`define APB4_SPISD__IRQ_STATUS               12'h100
`define APB4_SPISD__IRQ_ENABLE               12'h104
`define APB4_SPISD__IRQ_TEST                 12'h108
`define APB4_SPISD__ERROR_STATUS             12'h10C
`define APB4_SPISD__LAST_CMD                 12'h110
`define APB4_SPISD__CRC_ERROR_COUNT          12'h114
`define APB4_SPISD__TIMEOUT_COUNT            12'h118
`define APB4_SPISD__AXI_ERROR_COUNT          12'h11C
`define APB4_SPISD__STALL_COUNT              12'h120

`define APB4_SPISD__HOST_CTRL_ENABLE         0
`define APB4_SPISD__HOST_CTRL_ABORT          1
`define APB4_SPISD__HOST_CTRL_IRQ            2
`define APB4_SPISD__CLOCK_CTRL_ENABLE        0
`define APB4_SPISD__CLOCK_CTRL_TRAIN         1
`define APB4_SPISD__CLOCK_CTRL_HALF_PERIOD_LSB 8
`define APB4_SPISD__CMD_CFG_INDEX_LSB        0
`define APB4_SPISD__CMD_CFG_RESP_LSB         8
`define APB4_SPISD__CMD_CFG_STUFF_BYTE       12
`define APB4_SPISD__CMD_CFG_DATA_PRESENT     13
`define APB4_SPISD__CMD_CFG_AUTO_STOP        14
`define APB4_SPISD__RESP_NONE                0
`define APB4_SPISD__RESP_R1                  1
`define APB4_SPISD__RESP_R1B                 2
`define APB4_SPISD__RESP_R2                  3
`define APB4_SPISD__RESP_R3                  4
`define APB4_SPISD__RESP_R7                  5
`define APB4_SPISD__DATA_CFG_DIRECTION       0
`define APB4_SPISD__DATA_CFG_DMA             4
`define APB4_SPISD__DATA_CFG_MULTI_BLOCK     5
`define APB4_SPISD__DATA_CFG_CRC_CHECK       6
`define APB4_SPISD__DMA_CTRL_START           0
`define APB4_SPISD__DMA_CTRL_ABORT           1

`define APB4_SPISD__DESC_OWN                 0
`define APB4_SPISD__DESC_CHAIN               1
`define APB4_SPISD__DESC_END                 2
`define APB4_SPISD__DESC_IRQ                 3
`define APB4_SPISD__DESC_DONE                16
`define APB4_SPISD__DESC_ERROR               17

`define APB4_SPISD__IRQ_CMD_DONE             0
`define APB4_SPISD__IRQ_DATA_DONE            1
`define APB4_SPISD__IRQ_DMA_DONE             2
`define APB4_SPISD__IRQ_CMD_ERROR            3
`define APB4_SPISD__IRQ_DATA_ERROR           4
`define APB4_SPISD__IRQ_DMA_ERROR            5
`define APB4_SPISD__IRQ_ABORT                6

`define APB4_SPISD__CAP_SD_MEMORY_V2         0
`define APB4_SPISD__CAP_SPI_MODE_0           1
`define APB4_SPISD__CAP_SDR                  2
`define APB4_SPISD__CAP_SG_DMA               3
`define APB4_SPISD__CAP_PIO                  4
`define APB4_SPISD__CAP_CRC                  5
`define APB4_SPISD__CAP_MULTI_BLOCK          6
`define APB4_SPISD__CAP_MAX_BURST_16         7
// verilog_format: on

`endif
