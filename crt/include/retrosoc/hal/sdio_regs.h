#ifndef RETROSOC_HAL_SDIO_REGS_H
#define RETROSOC_HAL_SDIO_REGS_H

#include <stdint.h>

/*
 * The ABI names below are a direct hand-maintained C mirror of
 * rtl/ip/storage/sdio_define.svh.  Keep the ABI prefix stable so the parity
 * test can compare the two files without a generated register description.
 */
#define RS_SDIO_ABI_IP_ID                      UINT32_C(0x000)
#define RS_SDIO_ABI_IP_VERSION                 UINT32_C(0x004)
#define RS_SDIO_ABI_CAPABILITY                 UINT32_C(0x008)
#define RS_SDIO_ABI_HOST_CTRL                  UINT32_C(0x00C)
#define RS_SDIO_ABI_CLOCK_CTRL                 UINT32_C(0x010)
#define RS_SDIO_ABI_CLOCK_ACTUAL               UINT32_C(0x014)
#define RS_SDIO_ABI_BUS_CTRL                   UINT32_C(0x018)
#define RS_SDIO_ABI_TIMEOUT_CMD                UINT32_C(0x01C)
#define RS_SDIO_ABI_TIMEOUT_DATA               UINT32_C(0x020)
#define RS_SDIO_ABI_TIMEOUT_BUSY               UINT32_C(0x024)
#define RS_SDIO_ABI_STATUS                     UINT32_C(0x028)
#define RS_SDIO_ABI_PRESENT                    UINT32_C(0x02C)

#define RS_SDIO_ABI_CMD_ARG                    UINT32_C(0x040)
#define RS_SDIO_ABI_CMD_CFG                    UINT32_C(0x044)
#define RS_SDIO_ABI_CMD_START                  UINT32_C(0x048)
#define RS_SDIO_ABI_CMD_STATUS                 UINT32_C(0x04C)
#define RS_SDIO_ABI_RESP0                      UINT32_C(0x050)
#define RS_SDIO_ABI_RESP1                      UINT32_C(0x054)
#define RS_SDIO_ABI_RESP2                      UINT32_C(0x058)
#define RS_SDIO_ABI_RESP3                      UINT32_C(0x05C)
#define RS_SDIO_ABI_RESP4                      UINT32_C(0x060)

#define RS_SDIO_ABI_BLOCK_SIZE                 UINT32_C(0x080)
#define RS_SDIO_ABI_BLOCK_COUNT                UINT32_C(0x084)
#define RS_SDIO_ABI_DATA_CFG                   UINT32_C(0x088)
#define RS_SDIO_ABI_DATA_START                 UINT32_C(0x08C)
#define RS_SDIO_ABI_PIO_DATA                   UINT32_C(0x090)
#define RS_SDIO_ABI_FIFO_STATUS                UINT32_C(0x094)
#define RS_SDIO_ABI_FIFO_WATERMARK             UINT32_C(0x098)

#define RS_SDIO_ABI_DESC_BASE                  UINT32_C(0x0C0)
#define RS_SDIO_ABI_DESC_COUNT                 UINT32_C(0x0C4)
#define RS_SDIO_ABI_DMA_CTRL                   UINT32_C(0x0C8)
#define RS_SDIO_ABI_DMA_STATUS                 UINT32_C(0x0CC)
#define RS_SDIO_ABI_CURRENT_DESC               UINT32_C(0x0D0)
#define RS_SDIO_ABI_BYTES_DONE                 UINT32_C(0x0D4)
#define RS_SDIO_ABI_DMA_ERROR_ADDR             UINT32_C(0x0D8)
#define RS_SDIO_ABI_DMA_ERROR                  UINT32_C(0x0DC)

#define RS_SDIO_ABI_IRQ_STATUS                 UINT32_C(0x100)
#define RS_SDIO_ABI_IRQ_ENABLE                 UINT32_C(0x104)
#define RS_SDIO_ABI_IRQ_TEST                   UINT32_C(0x108)
#define RS_SDIO_ABI_ERROR_STATUS               UINT32_C(0x10C)
#define RS_SDIO_ABI_ERROR_ABORT                7U
#define RS_SDIO_ABI_LAST_CMD                   UINT32_C(0x110)
#define RS_SDIO_ABI_CRC_ERROR_COUNT            UINT32_C(0x114)
#define RS_SDIO_ABI_TIMEOUT_COUNT              UINT32_C(0x118)
#define RS_SDIO_ABI_AXI_ERROR_COUNT            UINT32_C(0x11C)
#define RS_SDIO_ABI_STALL_COUNT                UINT32_C(0x120)
#define RS_SDIO_ABI_DEBUG                      UINT32_C(0x124)

#define RS_SDIO_ABI_HOST_CTRL_ENABLE           0U
#define RS_SDIO_ABI_HOST_CTRL_ABORT            1U
#define RS_SDIO_ABI_HOST_CTRL_IRQ              2U
#define RS_SDIO_ABI_CLOCK_CTRL_ENABLE          0U
#define RS_SDIO_ABI_CLOCK_CTRL_HALF_PERIOD_LSB 8U
#define RS_SDIO_ABI_BUS_CTRL_WIDTH_LSB         0U
#define RS_SDIO_ABI_BUS_CTRL_WIDTH_1           0U
#define RS_SDIO_ABI_BUS_CTRL_WIDTH_4           1U
#define RS_SDIO_ABI_CMD_CFG_INDEX_LSB          0U
#define RS_SDIO_ABI_CMD_CFG_RESP_LSB           8U
#define RS_SDIO_ABI_CMD_CFG_CRC_CHECK          12U
#define RS_SDIO_ABI_CMD_CFG_INDEX_CHECK        13U

#define RS_SDIO_ABI_RESP_NONE                  0U
#define RS_SDIO_ABI_RESP_R1                    1U
#define RS_SDIO_ABI_RESP_R1B                   2U
#define RS_SDIO_ABI_RESP_R2                    3U
#define RS_SDIO_ABI_RESP_R3                    4U
#define RS_SDIO_ABI_RESP_R4                    5U
#define RS_SDIO_ABI_RESP_R5                    6U
#define RS_SDIO_ABI_RESP_R6                    7U
#define RS_SDIO_ABI_RESP_R7                    8U

#define RS_SDIO_ABI_DATA_CFG_DIRECTION         0U
#define RS_SDIO_ABI_DATA_CFG_WIDTH_LSB         1U
#define RS_SDIO_ABI_DATA_CFG_DMA               4U
#define RS_SDIO_ABI_DATA_CFG_BLOCK             5U
#define RS_SDIO_ABI_DATA_CFG_FIXED             6U
#define RS_SDIO_ABI_DMA_CTRL_START             0U
#define RS_SDIO_ABI_DMA_CTRL_ABORT             1U

#define RS_SDIO_ABI_DESC_OWN                   0U
#define RS_SDIO_ABI_DESC_CHAIN                 1U
#define RS_SDIO_ABI_DESC_END                   2U
#define RS_SDIO_ABI_DESC_IRQ                   3U
#define RS_SDIO_ABI_DESC_DONE                  16U
#define RS_SDIO_ABI_DESC_ERROR                 17U

#define RS_SDIO_ABI_IRQ_CMD_DONE               0U
#define RS_SDIO_ABI_IRQ_DATA_DONE              1U
#define RS_SDIO_ABI_IRQ_DMA_DONE               2U
#define RS_SDIO_ABI_IRQ_CMD_ERROR              3U
#define RS_SDIO_ABI_IRQ_DATA_ERROR             4U
#define RS_SDIO_ABI_IRQ_DMA_ERROR              5U
#define RS_SDIO_ABI_IRQ_DAT1                   6U
#define RS_SDIO_ABI_IRQ_ABORT                  7U

#define RS_SDIO_ABI_CAP_SD_MEMORY_V2           0U
#define RS_SDIO_ABI_CAP_SDIO_V2                1U
#define RS_SDIO_ABI_CAP_BUS_1BIT               2U
#define RS_SDIO_ABI_CAP_BUS_4BIT               3U
#define RS_SDIO_ABI_CAP_SDR                    4U
#define RS_SDIO_ABI_CAP_SG_DMA                 5U
#define RS_SDIO_ABI_CAP_PIO                    6U
#define RS_SDIO_ABI_CAP_CRC                    7U
#define RS_SDIO_ABI_CAP_MAX_BURST_16           8U

#define RS_SDIO_REG_IP_ID                      RS_SDIO_ABI_IP_ID
#define RS_SDIO_REG_IP_VERSION                 RS_SDIO_ABI_IP_VERSION
#define RS_SDIO_REG_CAPABILITY                 RS_SDIO_ABI_CAPABILITY
#define RS_SDIO_REG_HOST_CTRL                  RS_SDIO_ABI_HOST_CTRL
#define RS_SDIO_REG_CLOCK_CTRL                 RS_SDIO_ABI_CLOCK_CTRL
#define RS_SDIO_REG_CLOCK_ACTUAL               RS_SDIO_ABI_CLOCK_ACTUAL
#define RS_SDIO_REG_BUS_CTRL                   RS_SDIO_ABI_BUS_CTRL
#define RS_SDIO_REG_TIMEOUT_CMD                RS_SDIO_ABI_TIMEOUT_CMD
#define RS_SDIO_REG_TIMEOUT_DATA               RS_SDIO_ABI_TIMEOUT_DATA
#define RS_SDIO_REG_TIMEOUT_BUSY               RS_SDIO_ABI_TIMEOUT_BUSY
#define RS_SDIO_REG_STATUS                     RS_SDIO_ABI_STATUS
#define RS_SDIO_REG_PRESENT                    RS_SDIO_ABI_PRESENT
#define RS_SDIO_REG_CMD_ARG                    RS_SDIO_ABI_CMD_ARG
#define RS_SDIO_REG_CMD_CFG                    RS_SDIO_ABI_CMD_CFG
#define RS_SDIO_REG_CMD_START                  RS_SDIO_ABI_CMD_START
#define RS_SDIO_REG_CMD_STATUS                 RS_SDIO_ABI_CMD_STATUS
#define RS_SDIO_REG_RESP0                      RS_SDIO_ABI_RESP0
#define RS_SDIO_REG_RESP1                      RS_SDIO_ABI_RESP1
#define RS_SDIO_REG_RESP2                      RS_SDIO_ABI_RESP2
#define RS_SDIO_REG_RESP3                      RS_SDIO_ABI_RESP3
#define RS_SDIO_REG_RESP4                      RS_SDIO_ABI_RESP4
#define RS_SDIO_REG_BLOCK_SIZE                 RS_SDIO_ABI_BLOCK_SIZE
#define RS_SDIO_REG_BLOCK_COUNT                RS_SDIO_ABI_BLOCK_COUNT
#define RS_SDIO_REG_DATA_CFG                   RS_SDIO_ABI_DATA_CFG
#define RS_SDIO_REG_DATA_START                 RS_SDIO_ABI_DATA_START
#define RS_SDIO_REG_PIO_DATA                   RS_SDIO_ABI_PIO_DATA
#define RS_SDIO_REG_FIFO_STATUS                RS_SDIO_ABI_FIFO_STATUS
#define RS_SDIO_REG_FIFO_WATERMARK             RS_SDIO_ABI_FIFO_WATERMARK
#define RS_SDIO_REG_DESC_BASE                  RS_SDIO_ABI_DESC_BASE
#define RS_SDIO_REG_DESC_COUNT                 RS_SDIO_ABI_DESC_COUNT
#define RS_SDIO_REG_DMA_CTRL                   RS_SDIO_ABI_DMA_CTRL
#define RS_SDIO_REG_DMA_STATUS                 RS_SDIO_ABI_DMA_STATUS
#define RS_SDIO_REG_CURRENT_DESC               RS_SDIO_ABI_CURRENT_DESC
#define RS_SDIO_REG_BYTES_DONE                 RS_SDIO_ABI_BYTES_DONE
#define RS_SDIO_REG_DMA_ERROR_ADDR             RS_SDIO_ABI_DMA_ERROR_ADDR
#define RS_SDIO_REG_DMA_ERROR                  RS_SDIO_ABI_DMA_ERROR
#define RS_SDIO_REG_IRQ_STATUS                 RS_SDIO_ABI_IRQ_STATUS
#define RS_SDIO_REG_IRQ_ENABLE                 RS_SDIO_ABI_IRQ_ENABLE
#define RS_SDIO_REG_IRQ_TEST                   RS_SDIO_ABI_IRQ_TEST
#define RS_SDIO_REG_ERROR_STATUS               RS_SDIO_ABI_ERROR_STATUS
#define RS_SDIO_REG_LAST_CMD                   RS_SDIO_ABI_LAST_CMD
#define RS_SDIO_REG_CRC_ERROR_COUNT            RS_SDIO_ABI_CRC_ERROR_COUNT
#define RS_SDIO_REG_TIMEOUT_COUNT              RS_SDIO_ABI_TIMEOUT_COUNT
#define RS_SDIO_REG_AXI_ERROR_COUNT            RS_SDIO_ABI_AXI_ERROR_COUNT
#define RS_SDIO_REG_STALL_COUNT                RS_SDIO_ABI_STALL_COUNT
#define RS_SDIO_REG_DEBUG                      RS_SDIO_ABI_DEBUG

#define RS_SDIO_HOST_CTRL_ENABLE_BIT           RS_SDIO_ABI_HOST_CTRL_ENABLE
#define RS_SDIO_HOST_CTRL_ABORT_BIT            RS_SDIO_ABI_HOST_CTRL_ABORT
#define RS_SDIO_HOST_CTRL_IRQ_BIT              RS_SDIO_ABI_HOST_CTRL_IRQ
#define RS_SDIO_CLOCK_CTRL_ENABLE_BIT          RS_SDIO_ABI_CLOCK_CTRL_ENABLE
#define RS_SDIO_CLOCK_CTRL_HALF_PERIOD_LSB     RS_SDIO_ABI_CLOCK_CTRL_HALF_PERIOD_LSB
#define RS_SDIO_BUS_CTRL_WIDTH_LSB             RS_SDIO_ABI_BUS_CTRL_WIDTH_LSB
#define RS_SDIO_BUS_CTRL_WIDTH_1               RS_SDIO_ABI_BUS_CTRL_WIDTH_1
#define RS_SDIO_BUS_CTRL_WIDTH_4               RS_SDIO_ABI_BUS_CTRL_WIDTH_4
#define RS_SDIO_CMD_CFG_INDEX_LSB              RS_SDIO_ABI_CMD_CFG_INDEX_LSB
#define RS_SDIO_CMD_CFG_RESP_LSB               RS_SDIO_ABI_CMD_CFG_RESP_LSB
#define RS_SDIO_CMD_CFG_CRC_CHECK_BIT          RS_SDIO_ABI_CMD_CFG_CRC_CHECK
#define RS_SDIO_CMD_CFG_INDEX_CHECK_BIT        RS_SDIO_ABI_CMD_CFG_INDEX_CHECK

#define RS_SDIO_RESP_NONE                      RS_SDIO_ABI_RESP_NONE
#define RS_SDIO_RESP_R1                        RS_SDIO_ABI_RESP_R1
#define RS_SDIO_RESP_R1B                       RS_SDIO_ABI_RESP_R1B
#define RS_SDIO_RESP_R2                        RS_SDIO_ABI_RESP_R2
#define RS_SDIO_RESP_R3                        RS_SDIO_ABI_RESP_R3
#define RS_SDIO_RESP_R4                        RS_SDIO_ABI_RESP_R4
#define RS_SDIO_RESP_R5                        RS_SDIO_ABI_RESP_R5
#define RS_SDIO_RESP_R6                        RS_SDIO_ABI_RESP_R6
#define RS_SDIO_RESP_R7                        RS_SDIO_ABI_RESP_R7

#define RS_SDIO_DATA_CFG_DIRECTION_BIT         RS_SDIO_ABI_DATA_CFG_DIRECTION
#define RS_SDIO_DATA_CFG_WIDTH_LSB             RS_SDIO_ABI_DATA_CFG_WIDTH_LSB
#define RS_SDIO_DATA_CFG_DMA_BIT               RS_SDIO_ABI_DATA_CFG_DMA
#define RS_SDIO_DATA_CFG_BLOCK_BIT             RS_SDIO_ABI_DATA_CFG_BLOCK
#define RS_SDIO_DATA_CFG_FIXED_BIT             RS_SDIO_ABI_DATA_CFG_FIXED
#define RS_SDIO_DMA_CTRL_START_BIT             RS_SDIO_ABI_DMA_CTRL_START
#define RS_SDIO_DMA_CTRL_ABORT_BIT             RS_SDIO_ABI_DMA_CTRL_ABORT

#define RS_SDIO_DESC_OWN_BIT                   RS_SDIO_ABI_DESC_OWN
#define RS_SDIO_DESC_CHAIN_BIT                 RS_SDIO_ABI_DESC_CHAIN
#define RS_SDIO_DESC_END_BIT                   RS_SDIO_ABI_DESC_END
#define RS_SDIO_DESC_IRQ_BIT                   RS_SDIO_ABI_DESC_IRQ
#define RS_SDIO_DESC_DONE_BIT                  RS_SDIO_ABI_DESC_DONE
#define RS_SDIO_DESC_ERROR_BIT                 RS_SDIO_ABI_DESC_ERROR

#define RS_SDIO_IRQ_CMD_DONE                   (UINT32_C(1) << RS_SDIO_ABI_IRQ_CMD_DONE)
#define RS_SDIO_IRQ_DATA_DONE                  (UINT32_C(1) << RS_SDIO_ABI_IRQ_DATA_DONE)
#define RS_SDIO_IRQ_DMA_DONE                   (UINT32_C(1) << RS_SDIO_ABI_IRQ_DMA_DONE)
#define RS_SDIO_IRQ_CMD_ERROR                  (UINT32_C(1) << RS_SDIO_ABI_IRQ_CMD_ERROR)
#define RS_SDIO_IRQ_DATA_ERROR                 (UINT32_C(1) << RS_SDIO_ABI_IRQ_DATA_ERROR)
#define RS_SDIO_IRQ_DMA_ERROR                  (UINT32_C(1) << RS_SDIO_ABI_IRQ_DMA_ERROR)
#define RS_SDIO_IRQ_DAT1                       (UINT32_C(1) << RS_SDIO_ABI_IRQ_DAT1)
#define RS_SDIO_IRQ_ABORT                      (UINT32_C(1) << RS_SDIO_ABI_IRQ_ABORT)
#define RS_SDIO_IRQ_ALL                        UINT32_C(0x000000FF)

#define RS_SDIO_CAP_SD_MEMORY_V2               (UINT32_C(1) << RS_SDIO_ABI_CAP_SD_MEMORY_V2)
#define RS_SDIO_CAP_SDIO_V2                    (UINT32_C(1) << RS_SDIO_ABI_CAP_SDIO_V2)
#define RS_SDIO_CAP_BUS_1BIT                   (UINT32_C(1) << RS_SDIO_ABI_CAP_BUS_1BIT)
#define RS_SDIO_CAP_BUS_4BIT                   (UINT32_C(1) << RS_SDIO_ABI_CAP_BUS_4BIT)
#define RS_SDIO_CAP_SDR                        (UINT32_C(1) << RS_SDIO_ABI_CAP_SDR)
#define RS_SDIO_CAP_SG_DMA                     (UINT32_C(1) << RS_SDIO_ABI_CAP_SG_DMA)
#define RS_SDIO_CAP_PIO                        (UINT32_C(1) << RS_SDIO_ABI_CAP_PIO)
#define RS_SDIO_CAP_CRC                        (UINT32_C(1) << RS_SDIO_ABI_CAP_CRC)
#define RS_SDIO_CAP_MAX_BURST_16               (UINT32_C(1) << RS_SDIO_ABI_CAP_MAX_BURST_16)

#define RS_SDIO_IP_ID_VALUE                    UINT32_C(0x5344494F)
#define RS_SDIO_IP_VERSION_VALUE               UINT32_C(0x00010000)
#define RS_SDIO_CAPABILITY_VALUE               UINT32_C(0x000001FF)
#define RS_SDIO_PRESENT_CARD                   UINT32_C(0x00000001)
#define RS_SDIO_FIFO_WATERMARK_DEFAULT         UINT32_C(0x00000001)
#define RS_SDIO_LAST_CMD_MASK                  UINT32_C(0x0000003F)
#define RS_SDIO_RESPONSE_R2_HIGH_MASK          UINT32_C(0x000000FF)
#define RS_SDIO_DEBUG_PIO_VALID                UINT32_C(0x00000001)
#define RS_SDIO_DEBUG_PIO_READY                UINT32_C(0x00000002)

#define RS_SDIO_HOST_CTRL_ENABLE               (UINT32_C(1) << RS_SDIO_HOST_CTRL_ENABLE_BIT)
#define RS_SDIO_HOST_CTRL_ABORT                (UINT32_C(1) << RS_SDIO_HOST_CTRL_ABORT_BIT)
#define RS_SDIO_HOST_CTRL_IRQ                  (UINT32_C(1) << RS_SDIO_HOST_CTRL_IRQ_BIT)
#define RS_SDIO_CLOCK_CTRL_ENABLE              (UINT32_C(1) << RS_SDIO_CLOCK_CTRL_ENABLE_BIT)
#define RS_SDIO_CLOCK_CTRL_HALF_PERIOD_MASK    UINT32_C(0x00FFFF00)
#define RS_SDIO_BUS_CTRL_WIDTH_MASK            UINT32_C(0x00000003)
#define RS_SDIO_CMD_CFG_INDEX_MASK             UINT32_C(0x0000003F)
#define RS_SDIO_CMD_CFG_RESP_MASK              UINT32_C(0x00000F00)
#define RS_SDIO_CMD_CFG_CRC_CHECK              (UINT32_C(1) << RS_SDIO_CMD_CFG_CRC_CHECK_BIT)
#define RS_SDIO_CMD_CFG_INDEX_CHECK            (UINT32_C(1) << RS_SDIO_CMD_CFG_INDEX_CHECK_BIT)
#define RS_SDIO_DATA_CFG_DIRECTION             (UINT32_C(1) << RS_SDIO_DATA_CFG_DIRECTION_BIT)
#define RS_SDIO_DATA_CFG_WIDTH_MASK            UINT32_C(0x00000006)
#define RS_SDIO_DATA_CFG_DMA                   (UINT32_C(1) << RS_SDIO_DATA_CFG_DMA_BIT)
#define RS_SDIO_DATA_CFG_BLOCK                 (UINT32_C(1) << RS_SDIO_DATA_CFG_BLOCK_BIT)
#define RS_SDIO_DATA_CFG_FIXED                 (UINT32_C(1) << RS_SDIO_DATA_CFG_FIXED_BIT)
#define RS_SDIO_DMA_CTRL_START                 (UINT32_C(1) << RS_SDIO_DMA_CTRL_START_BIT)
#define RS_SDIO_DMA_CTRL_ABORT                 (UINT32_C(1) << RS_SDIO_DMA_CTRL_ABORT_BIT)

#define RS_SDIO_STATUS_BUSY                    UINT32_C(0x00000001)
#define RS_SDIO_STATUS_CMD_BUSY                UINT32_C(0x00000002)
#define RS_SDIO_STATUS_DATA_BUSY               UINT32_C(0x00000004)
#define RS_SDIO_STATUS_DMA_BUSY                UINT32_C(0x00000008)
#define RS_SDIO_STATUS_PIO_READY               UINT32_C(0x00000010)
#define RS_SDIO_STATUS_DATA_FIXED              UINT32_C(0x00000020)
#define RS_SDIO_STATUS_DATA_BLOCK              UINT32_C(0x00000040)
#define RS_SDIO_STATUS_DAT1_HIGH               UINT32_C(0x00000080)
#define RS_SDIO_STATUS_CLOCK_RUNNING           UINT32_C(0x00000100)

#define RS_SDIO_CMD_STATUS_BUSY                UINT32_C(0x00000001)
#define RS_SDIO_CMD_STATUS_ERROR               UINT32_C(0x00000002)
#define RS_SDIO_CMD_STATUS_TIMEOUT             UINT32_C(0x00000004)
#define RS_SDIO_CMD_STATUS_CRC_ERROR           UINT32_C(0x00000008)
#define RS_SDIO_CMD_STATUS_INDEX_ERROR         UINT32_C(0x00000010)

#define RS_SDIO_DATA_STATUS_BUSY               UINT32_C(0x00000001)
#define RS_SDIO_DATA_STATUS_ERROR              UINT32_C(0x00000002)
#define RS_SDIO_DATA_STATUS_TIMEOUT            UINT32_C(0x00000004)
#define RS_SDIO_DATA_STATUS_CRC_ERROR          UINT32_C(0x00000008)
#define RS_SDIO_DATA_STATUS_BUSY_TIMEOUT       UINT32_C(0x00000010)

#define RS_SDIO_DMA_STATUS_BUSY                UINT32_C(0x00000001)
#define RS_SDIO_DMA_STATUS_DONE                UINT32_C(0x00000002)
#define RS_SDIO_DMA_STATUS_ERROR               UINT32_C(0x00000004)
#define RS_SDIO_DMA_STATUS_ERROR_CODE_SHIFT    3U
#define RS_SDIO_DMA_STATUS_ERROR_CODE_MASK     UINT32_C(0x000007F8)

#define RS_SDIO_ERROR_CMD_CRC                  UINT32_C(0x00000001)
#define RS_SDIO_ERROR_DATA_CRC                 UINT32_C(0x00000002)
#define RS_SDIO_ERROR_CMD_TIMEOUT              UINT32_C(0x00000004)
#define RS_SDIO_ERROR_DATA_TIMEOUT             UINT32_C(0x00000008)
#define RS_SDIO_ERROR_CMD                      UINT32_C(0x00000010)
#define RS_SDIO_ERROR_DATA                     UINT32_C(0x00000020)
#define RS_SDIO_ERROR_DMA                      UINT32_C(0x00000040)
#define RS_SDIO_ERROR_ABORT                    (UINT32_C(1) << RS_SDIO_ABI_ERROR_ABORT)
#define RS_SDIO_ERROR_ALL                      UINT32_C(0x000000FF)

#define RS_SDIO_DMA_ERROR_INVALID_START        UINT32_C(0x01)
#define RS_SDIO_DMA_ERROR_DESCRIPTOR           UINT32_C(0x02)
#define RS_SDIO_DMA_ERROR_AXI                  UINT32_C(0x04)
#define RS_SDIO_DMA_ERROR_ABORT                UINT32_C(0x08)
#define RS_SDIO_DMA_ERROR_PAYLOAD              UINT32_C(0x10)
#define RS_SDIO_DMA_ERROR_INTERNAL             UINT32_C(0x80)

#define RS_SDIO_DESCRIPTOR_ALIGNMENT           UINT32_C(16)
#define RS_SDIO_DESCRIPTOR_SIZE                UINT32_C(16)
#define RS_SDIO_MAX_DESCRIPTOR_COUNT           UINT32_C(16)
#define RS_SDIO_MAX_BURST_BEATS                UINT32_C(16)
#define RS_SDIO_DESCRIPTOR_RESERVED_MASK       UINT32_C(0xFFFC0000)
#define RS_SDIO_DESCRIPTOR_WRITEBACK_MASK      UINT32_C(0x00030000)

typedef struct {
    uint32_t buffer_addr;
    uint32_t byte_count;
    uint32_t next_addr;
    uint32_t control_status;
} rs_sdio_descriptor_t;

_Static_assert(sizeof(rs_sdio_descriptor_t) == 16U, "SDIO descriptor ABI size");

#endif
