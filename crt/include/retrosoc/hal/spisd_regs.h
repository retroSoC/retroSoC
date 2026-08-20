#ifndef RETROSOC_HAL_SPISD_REGS_H
#define RETROSOC_HAL_SPISD_REGS_H

#include <stdint.h>

/* Handwritten mirror of spisd_define.svh; checked by test_spisd_register_parity.py. */
#define RS_SPISD_ABI_IP_ID                      UINT32_C(0x000)
#define RS_SPISD_ABI_IP_VERSION                 UINT32_C(0x004)
#define RS_SPISD_ABI_CAPABILITY                 UINT32_C(0x008)
#define RS_SPISD_ABI_HOST_CTRL                  UINT32_C(0x00C)
#define RS_SPISD_ABI_CLOCK_CTRL                 UINT32_C(0x010)
#define RS_SPISD_ABI_CLOCK_ACTUAL               UINT32_C(0x014)
#define RS_SPISD_ABI_TIMEOUT_CMD                UINT32_C(0x018)
#define RS_SPISD_ABI_TIMEOUT_DATA               UINT32_C(0x01C)
#define RS_SPISD_ABI_TIMEOUT_BUSY               UINT32_C(0x020)
#define RS_SPISD_ABI_STATUS                     UINT32_C(0x024)
#define RS_SPISD_ABI_CMD_ARG                    UINT32_C(0x040)
#define RS_SPISD_ABI_CMD_CFG                    UINT32_C(0x044)
#define RS_SPISD_ABI_CMD_START                  UINT32_C(0x048)
#define RS_SPISD_ABI_CMD_STATUS                 UINT32_C(0x04C)
#define RS_SPISD_ABI_RESP0                      UINT32_C(0x050)
#define RS_SPISD_ABI_RESP1                      UINT32_C(0x054)
#define RS_SPISD_ABI_BLOCK_SIZE                 UINT32_C(0x080)
#define RS_SPISD_ABI_BLOCK_COUNT                UINT32_C(0x084)
#define RS_SPISD_ABI_DATA_CFG                   UINT32_C(0x088)
#define RS_SPISD_ABI_PIO_DATA                   UINT32_C(0x08C)
#define RS_SPISD_ABI_DATA_STATUS                UINT32_C(0x090)
#define RS_SPISD_ABI_FIFO_STATUS                UINT32_C(0x094)
#define RS_SPISD_ABI_DESC_BASE                  UINT32_C(0x0C0)
#define RS_SPISD_ABI_DESC_COUNT                 UINT32_C(0x0C4)
#define RS_SPISD_ABI_DMA_CTRL                   UINT32_C(0x0C8)
#define RS_SPISD_ABI_DMA_STATUS                 UINT32_C(0x0CC)
#define RS_SPISD_ABI_CURRENT_DESC               UINT32_C(0x0D0)
#define RS_SPISD_ABI_BYTES_DONE                 UINT32_C(0x0D4)
#define RS_SPISD_ABI_DMA_ERROR_ADDR             UINT32_C(0x0D8)
#define RS_SPISD_ABI_DMA_ERROR                  UINT32_C(0x0DC)
#define RS_SPISD_ABI_IRQ_STATUS                 UINT32_C(0x100)
#define RS_SPISD_ABI_IRQ_ENABLE                 UINT32_C(0x104)
#define RS_SPISD_ABI_IRQ_TEST                   UINT32_C(0x108)
#define RS_SPISD_ABI_ERROR_STATUS               UINT32_C(0x10C)
#define RS_SPISD_ABI_LAST_CMD                   UINT32_C(0x110)
#define RS_SPISD_ABI_CRC_ERROR_COUNT            UINT32_C(0x114)
#define RS_SPISD_ABI_TIMEOUT_COUNT              UINT32_C(0x118)
#define RS_SPISD_ABI_AXI_ERROR_COUNT            UINT32_C(0x11C)
#define RS_SPISD_ABI_STALL_COUNT                UINT32_C(0x120)

#define RS_SPISD_ABI_HOST_CTRL_ENABLE           0U
#define RS_SPISD_ABI_HOST_CTRL_ABORT            1U
#define RS_SPISD_ABI_HOST_CTRL_IRQ              2U
#define RS_SPISD_ABI_CLOCK_CTRL_ENABLE          0U
#define RS_SPISD_ABI_CLOCK_CTRL_TRAIN           1U
#define RS_SPISD_ABI_CLOCK_CTRL_HALF_PERIOD_LSB 8U
#define RS_SPISD_ABI_CMD_CFG_INDEX_LSB          0U
#define RS_SPISD_ABI_CMD_CFG_RESP_LSB           8U
#define RS_SPISD_ABI_CMD_CFG_STUFF_BYTE         12U
#define RS_SPISD_ABI_CMD_CFG_DATA_PRESENT       13U
#define RS_SPISD_ABI_CMD_CFG_AUTO_STOP          14U
#define RS_SPISD_ABI_RESP_NONE                  0U
#define RS_SPISD_ABI_RESP_R1                    1U
#define RS_SPISD_ABI_RESP_R1B                   2U
#define RS_SPISD_ABI_RESP_R2                    3U
#define RS_SPISD_ABI_RESP_R3                    4U
#define RS_SPISD_ABI_RESP_R7                    5U
#define RS_SPISD_ABI_DATA_CFG_DIRECTION         0U
#define RS_SPISD_ABI_DATA_CFG_DMA               4U
#define RS_SPISD_ABI_DATA_CFG_MULTI_BLOCK       5U
#define RS_SPISD_ABI_DATA_CFG_CRC_CHECK         6U
#define RS_SPISD_ABI_DMA_CTRL_START             0U
#define RS_SPISD_ABI_DMA_CTRL_ABORT             1U
#define RS_SPISD_ABI_DESC_OWN                   0U
#define RS_SPISD_ABI_DESC_CHAIN                 1U
#define RS_SPISD_ABI_DESC_END                   2U
#define RS_SPISD_ABI_DESC_IRQ                   3U
#define RS_SPISD_ABI_DESC_DONE                  16U
#define RS_SPISD_ABI_DESC_ERROR                 17U
#define RS_SPISD_ABI_IRQ_CMD_DONE               0U
#define RS_SPISD_ABI_IRQ_DATA_DONE              1U
#define RS_SPISD_ABI_IRQ_DMA_DONE               2U
#define RS_SPISD_ABI_IRQ_CMD_ERROR              3U
#define RS_SPISD_ABI_IRQ_DATA_ERROR             4U
#define RS_SPISD_ABI_IRQ_DMA_ERROR              5U
#define RS_SPISD_ABI_IRQ_ABORT                  6U
#define RS_SPISD_ABI_CAP_SD_MEMORY_V2           0U
#define RS_SPISD_ABI_CAP_SPI_MODE_0             1U
#define RS_SPISD_ABI_CAP_SDR                    2U
#define RS_SPISD_ABI_CAP_SG_DMA                 3U
#define RS_SPISD_ABI_CAP_PIO                    4U
#define RS_SPISD_ABI_CAP_CRC                    5U
#define RS_SPISD_ABI_CAP_MULTI_BLOCK            6U
#define RS_SPISD_ABI_CAP_MAX_BURST_16           7U

#define RS_SPISD_REG_IP_ID                      UINT32_C(0x000)
#define RS_SPISD_REG_IP_VERSION                 UINT32_C(0x004)
#define RS_SPISD_REG_CAPABILITY                 UINT32_C(0x008)
#define RS_SPISD_REG_HOST_CTRL                  UINT32_C(0x00C)
#define RS_SPISD_REG_CLOCK_CTRL                 UINT32_C(0x010)
#define RS_SPISD_REG_CLOCK_ACTUAL               UINT32_C(0x014)
#define RS_SPISD_REG_TIMEOUT_CMD                UINT32_C(0x018)
#define RS_SPISD_REG_TIMEOUT_DATA               UINT32_C(0x01C)
#define RS_SPISD_REG_TIMEOUT_BUSY               UINT32_C(0x020)
#define RS_SPISD_REG_STATUS                     UINT32_C(0x024)
#define RS_SPISD_REG_CMD_ARG                    UINT32_C(0x040)
#define RS_SPISD_REG_CMD_CFG                    UINT32_C(0x044)
#define RS_SPISD_REG_CMD_START                  UINT32_C(0x048)
#define RS_SPISD_REG_CMD_STATUS                 UINT32_C(0x04C)
#define RS_SPISD_REG_RESP0                      UINT32_C(0x050)
#define RS_SPISD_REG_RESP1                      UINT32_C(0x054)
#define RS_SPISD_REG_BLOCK_SIZE                 UINT32_C(0x080)
#define RS_SPISD_REG_BLOCK_COUNT                UINT32_C(0x084)
#define RS_SPISD_REG_DATA_CFG                   UINT32_C(0x088)
#define RS_SPISD_REG_PIO_DATA                   UINT32_C(0x08C)
#define RS_SPISD_REG_DATA_STATUS                UINT32_C(0x090)
#define RS_SPISD_REG_FIFO_STATUS                UINT32_C(0x094)
#define RS_SPISD_REG_DESC_BASE                  UINT32_C(0x0C0)
#define RS_SPISD_REG_DESC_COUNT                 UINT32_C(0x0C4)
#define RS_SPISD_REG_DMA_CTRL                   UINT32_C(0x0C8)
#define RS_SPISD_REG_DMA_STATUS                 UINT32_C(0x0CC)
#define RS_SPISD_REG_CURRENT_DESC               UINT32_C(0x0D0)
#define RS_SPISD_REG_BYTES_DONE                 UINT32_C(0x0D4)
#define RS_SPISD_REG_DMA_ERROR_ADDR             UINT32_C(0x0D8)
#define RS_SPISD_REG_DMA_ERROR                  UINT32_C(0x0DC)
#define RS_SPISD_REG_IRQ_STATUS                 UINT32_C(0x100)
#define RS_SPISD_REG_IRQ_ENABLE                 UINT32_C(0x104)
#define RS_SPISD_REG_IRQ_TEST                   UINT32_C(0x108)
#define RS_SPISD_REG_ERROR_STATUS               UINT32_C(0x10C)
#define RS_SPISD_REG_LAST_CMD                   UINT32_C(0x110)
#define RS_SPISD_REG_CRC_ERROR_COUNT            UINT32_C(0x114)
#define RS_SPISD_REG_TIMEOUT_COUNT              UINT32_C(0x118)
#define RS_SPISD_REG_AXI_ERROR_COUNT            UINT32_C(0x11C)
#define RS_SPISD_REG_STALL_COUNT                UINT32_C(0x120)

#define RS_SPISD_IP_ID_VALUE                    UINT32_C(0x53504953)
#define RS_SPISD_IP_VERSION_VALUE               UINT32_C(0x00010000)

#define RS_SPISD_CAP_SD_MEMORY_V2               (UINT32_C(1) << RS_SPISD_ABI_CAP_SD_MEMORY_V2)
#define RS_SPISD_CAP_SPI_MODE_0                 (UINT32_C(1) << RS_SPISD_ABI_CAP_SPI_MODE_0)
#define RS_SPISD_CAP_SDR                        (UINT32_C(1) << RS_SPISD_ABI_CAP_SDR)
#define RS_SPISD_CAP_SG_DMA                     (UINT32_C(1) << RS_SPISD_ABI_CAP_SG_DMA)
#define RS_SPISD_CAP_PIO                        (UINT32_C(1) << RS_SPISD_ABI_CAP_PIO)
#define RS_SPISD_CAP_CRC                        (UINT32_C(1) << RS_SPISD_ABI_CAP_CRC)
#define RS_SPISD_CAP_MULTI_BLOCK                (UINT32_C(1) << RS_SPISD_ABI_CAP_MULTI_BLOCK)
#define RS_SPISD_CAP_MAX_BURST_16               (UINT32_C(1) << RS_SPISD_ABI_CAP_MAX_BURST_16)
#define RS_SPISD_CAP_REQUIRED                                                                      \
    (RS_SPISD_CAP_SD_MEMORY_V2 | RS_SPISD_CAP_SPI_MODE_0 | RS_SPISD_CAP_SDR |                      \
     RS_SPISD_CAP_SG_DMA | RS_SPISD_CAP_PIO | RS_SPISD_CAP_CRC | RS_SPISD_CAP_MULTI_BLOCK |        \
     RS_SPISD_CAP_MAX_BURST_16)

#define RS_SPISD_HOST_CTRL_ENABLE_BIT      0U
#define RS_SPISD_HOST_CTRL_ABORT_BIT       1U
#define RS_SPISD_HOST_CTRL_IRQ_BIT         2U
#define RS_SPISD_CLOCK_ENABLE_BIT          0U
#define RS_SPISD_CLOCK_TRAIN_BIT           1U
#define RS_SPISD_CLOCK_HALF_PERIOD_LSB     8U
#define RS_SPISD_CLOCK_HALF_PERIOD_MASK    UINT32_C(0x00FFFF00)

#define RS_SPISD_CMD_CFG_INDEX_LSB         0U
#define RS_SPISD_CMD_CFG_RESP_LSB          8U
#define RS_SPISD_CMD_CFG_STUFF_BIT         12U
#define RS_SPISD_CMD_CFG_DATA_BIT          13U
#define RS_SPISD_CMD_CFG_AUTO_STOP_BIT     14U
#define RS_SPISD_CMD_CFG_INDEX_MASK        UINT32_C(0x0000003F)
#define RS_SPISD_CMD_CFG_RESP_MASK         UINT32_C(0x00000700)

#define RS_SPISD_DATA_DIRECTION_BIT        0U
#define RS_SPISD_DATA_DMA_BIT              4U
#define RS_SPISD_DATA_MULTI_BIT            5U
#define RS_SPISD_DATA_CRC_BIT              6U

#define RS_SPISD_STATUS_BUSY               UINT32_C(0x00000001)
#define RS_SPISD_STATUS_CMD_BUSY           UINT32_C(0x00000002)
#define RS_SPISD_STATUS_DATA_BUSY          UINT32_C(0x00000004)
#define RS_SPISD_STATUS_DMA_BUSY           UINT32_C(0x00000008)
#define RS_SPISD_CMD_STATUS_ERROR          UINT32_C(0x00000002)
#define RS_SPISD_CMD_STATUS_TIMEOUT        UINT32_C(0x00000004)
#define RS_SPISD_DATA_STATUS_ERROR         UINT32_C(0x00000002)
#define RS_SPISD_DATA_STATUS_TIMEOUT       UINT32_C(0x00000004)
#define RS_SPISD_DATA_STATUS_CRC_ERROR     UINT32_C(0x00000008)
#define RS_SPISD_DATA_STATUS_BUSY_TIMEOUT  UINT32_C(0x00000010)
#define RS_SPISD_DMA_STATUS_BUSY           UINT32_C(0x00000001)
#define RS_SPISD_DMA_STATUS_DONE           UINT32_C(0x00000002)
#define RS_SPISD_DMA_STATUS_ERROR          UINT32_C(0x00000004)

#define RS_SPISD_FIFO_TX_COUNT_MASK        UINT32_C(0x0000001F)
#define RS_SPISD_FIFO_TX_EMPTY             UINT32_C(0x00000020)
#define RS_SPISD_FIFO_TX_FULL              UINT32_C(0x00000040)
#define RS_SPISD_FIFO_RX_COUNT_LSB         13U
#define RS_SPISD_FIFO_RX_COUNT_MASK        UINT32_C(0x0003E000)
#define RS_SPISD_FIFO_RX_EMPTY             UINT32_C(0x00040000)
#define RS_SPISD_FIFO_RX_FULL              UINT32_C(0x00080000)

#define RS_SPISD_IRQ_CMD_DONE              (UINT32_C(1) << 0U)
#define RS_SPISD_IRQ_DATA_DONE             (UINT32_C(1) << 1U)
#define RS_SPISD_IRQ_DMA_DONE              (UINT32_C(1) << 2U)
#define RS_SPISD_IRQ_CMD_ERROR             (UINT32_C(1) << 3U)
#define RS_SPISD_IRQ_DATA_ERROR            (UINT32_C(1) << 4U)
#define RS_SPISD_IRQ_DMA_ERROR             (UINT32_C(1) << 5U)
#define RS_SPISD_IRQ_ABORT                 (UINT32_C(1) << 6U)
#define RS_SPISD_IRQ_ALL                   UINT32_C(0x0000007F)
#define RS_SPISD_ERROR_ALL                 UINT32_C(0x000000FF)

#define RS_SPISD_DESC_OWN                  (UINT32_C(1) << 0U)
#define RS_SPISD_DESC_CHAIN                (UINT32_C(1) << 1U)
#define RS_SPISD_DESC_END                  (UINT32_C(1) << 2U)
#define RS_SPISD_DESC_IRQ                  (UINT32_C(1) << 3U)
#define RS_SPISD_DESC_DONE                 (UINT32_C(1) << 16U)
#define RS_SPISD_DESC_ERROR                (UINT32_C(1) << 17U)

#define RS_SPISD_MAX_DESCRIPTOR_COUNT      UINT32_C(16)
#define RS_SPISD_DESCRIPTOR_ALIGNMENT      UINT32_C(16)
#define RS_SPISD_DESCRIPTOR_RESERVED_MASK  UINT32_C(0xFFFCFFF0)
#define RS_SPISD_DESCRIPTOR_WRITEBACK_MASK (RS_SPISD_DESC_DONE | RS_SPISD_DESC_ERROR)

typedef struct {
    uint32_t buffer_address;
    uint32_t byte_count;
    uint32_t next_address;
    uint32_t control_status;
} rs_spisd_descriptor_t;

_Static_assert(sizeof(rs_spisd_descriptor_t) == 16U, "SPISD descriptor ABI size");

#endif
