#ifndef RETROSOC_HAL_USB2_REGS_H
#define RETROSOC_HAL_USB2_REGS_H

#include <stdint.h>

/* Hand-maintained mirror of rtl/ip/usb/usb2_define.svh. */
#define RS_USB2_ABI_IP_ID                         UINT32_C(0x000)
#define RS_USB2_ABI_IP_VERSION                    UINT32_C(0x004)
#define RS_USB2_ABI_CAPABILITY0                   UINT32_C(0x008)
#define RS_USB2_ABI_CAPABILITY1                   UINT32_C(0x00C)
#define RS_USB2_ABI_GLOBAL_CTRL                   UINT32_C(0x010)
#define RS_USB2_ABI_GLOBAL_STATUS                 UINT32_C(0x014)
#define RS_USB2_ABI_ROLE_CTRL                     UINT32_C(0x018)
#define RS_USB2_ABI_ROLE_STATUS                   UINT32_C(0x01C)
#define RS_USB2_ABI_PHY_CTRL                      UINT32_C(0x020)
#define RS_USB2_ABI_PHY_STATUS                    UINT32_C(0x024)
#define RS_USB2_ABI_ULPI_VIEWPORT                 UINT32_C(0x028)
#define RS_USB2_ABI_ULPI_VIEWPORT_DATA            UINT32_C(0x02C)
#define RS_USB2_ABI_TIMEOUT                       UINT32_C(0x030)
#define RS_USB2_ABI_FRAME                         UINT32_C(0x034)
#define RS_USB2_ABI_TEST_CTRL                     UINT32_C(0x038)
#define RS_USB2_ABI_PIO_DATA                      UINT32_C(0x03C)
#define RS_USB2_ABI_IRQ_STATUS                    UINT32_C(0x040)
#define RS_USB2_ABI_IRQ_ENABLE                    UINT32_C(0x044)
#define RS_USB2_ABI_IRQ_TEST                      UINT32_C(0x048)
#define RS_USB2_ABI_ERROR_STATUS                  UINT32_C(0x04C)
#define RS_USB2_ABI_ERROR_CODE                    UINT32_C(0x050)
#define RS_USB2_ABI_ERROR_INFO                    UINT32_C(0x054)
#define RS_USB2_ABI_ERROR_DESC_ADDR               UINT32_C(0x058)
#define RS_USB2_ABI_ERROR_BUFFER_ADDR             UINT32_C(0x05C)
#define RS_USB2_ABI_PERF_TX_BYTES                 UINT32_C(0x060)
#define RS_USB2_ABI_PERF_RX_BYTES                 UINT32_C(0x064)
#define RS_USB2_ABI_PERF_PACKETS                  UINT32_C(0x068)
#define RS_USB2_ABI_PERF_RETRIES                  UINT32_C(0x06C)
#define RS_USB2_ABI_PERF_AXI_STALL                UINT32_C(0x070)
#define RS_USB2_ABI_PERF_RAM_STALL                UINT32_C(0x074)
#define RS_USB2_ABI_PERF_IRQ_COUNT                UINT32_C(0x078)
#define RS_USB2_ABI_PERF_CTRL                     UINT32_C(0x07C)
#define RS_USB2_ABI_DEVICE_CTRL                   UINT32_C(0x100)
#define RS_USB2_ABI_DEVICE_ADDR                   UINT32_C(0x104)
#define RS_USB2_ABI_DEVICE_STATUS                 UINT32_C(0x108)
#define RS_USB2_ABI_SETUP0                        UINT32_C(0x10C)
#define RS_USB2_ABI_SETUP1                        UINT32_C(0x110)
#define RS_USB2_ABI_ENDPOINT_PENDING_IN           UINT32_C(0x114)
#define RS_USB2_ABI_ENDPOINT_PENDING_OUT          UINT32_C(0x118)
#define RS_USB2_ABI_ENDPOINT_COMPLETE_IN          UINT32_C(0x11C)
#define RS_USB2_ABI_ENDPOINT_COMPLETE_OUT         UINT32_C(0x120)
#define RS_USB2_ABI_ENDPOINT_BASE                 UINT32_C(0x200)
#define RS_USB2_ABI_ENDPOINT_STRIDE               UINT32_C(0x040)
#define RS_USB2_ABI_ENDPOINT_CFG                  UINT32_C(0x000)
#define RS_USB2_ABI_ENDPOINT_RAM_IN               UINT32_C(0x004)
#define RS_USB2_ABI_ENDPOINT_RAM_OUT              UINT32_C(0x008)
#define RS_USB2_ABI_ENDPOINT_DESC_IN              UINT32_C(0x00C)
#define RS_USB2_ABI_ENDPOINT_DESC_OUT             UINT32_C(0x010)
#define RS_USB2_ABI_ENDPOINT_COMMAND              UINT32_C(0x014)
#define RS_USB2_ABI_ENDPOINT_STATUS               UINT32_C(0x018)
#define RS_USB2_ABI_ENDPOINT_BYTES_IN             UINT32_C(0x01C)
#define RS_USB2_ABI_ENDPOINT_BYTES_OUT            UINT32_C(0x020)
#define RS_USB2_ABI_HOST_CTRL                     UINT32_C(0x400)
#define RS_USB2_ABI_HOST_STATUS                   UINT32_C(0x404)
#define RS_USB2_ABI_PORT_CTRL                     UINT32_C(0x408)
#define RS_USB2_ABI_PORT_STATUS                   UINT32_C(0x40C)
#define RS_USB2_ABI_SCHEDULE_CTRL                 UINT32_C(0x410)
#define RS_USB2_ABI_SCHEDULE_STATUS               UINT32_C(0x414)
#define RS_USB2_ABI_CHANNEL_BASE                  UINT32_C(0x500)
#define RS_USB2_ABI_CHANNEL_STRIDE                UINT32_C(0x040)
#define RS_USB2_ABI_CHANNEL_CFG                   UINT32_C(0x000)
#define RS_USB2_ABI_CHANNEL_TARGET                UINT32_C(0x004)
#define RS_USB2_ABI_CHANNEL_INTERVAL              UINT32_C(0x008)
#define RS_USB2_ABI_CHANNEL_RAM                   UINT32_C(0x00C)
#define RS_USB2_ABI_CHANNEL_DESC                  UINT32_C(0x010)
#define RS_USB2_ABI_CHANNEL_COMMAND               UINT32_C(0x014)
#define RS_USB2_ABI_CHANNEL_STATUS                UINT32_C(0x018)
#define RS_USB2_ABI_CHANNEL_BYTES                 UINT32_C(0x01C)
#define RS_USB2_ABI_RAM_CTRL                      UINT32_C(0x900)
#define RS_USB2_ABI_RAM_STATUS                    UINT32_C(0x904)
#define RS_USB2_ABI_ECC_STATUS                    UINT32_C(0x908)
#define RS_USB2_ABI_ECC_CORRECTED_COUNT           UINT32_C(0x90C)
#define RS_USB2_ABI_ECC_UNCORRECTABLE_COUNT       UINT32_C(0x910)
#define RS_USB2_ABI_RAM_BIST                      UINT32_C(0x914)
#define RS_USB2_ABI_DEBUG_STATUS                  UINT32_C(0x918)

#define RS_USB2_ABI_GLOBAL_CTRL_ENABLE            0U
#define RS_USB2_ABI_GLOBAL_CTRL_SOFT_RESET        1U
#define RS_USB2_ABI_GLOBAL_CTRL_ABORT             2U
#define RS_USB2_ABI_GLOBAL_CTRL_IRQ_ENABLE        3U
#define RS_USB2_ABI_ROLE_CTRL_FORCE_LSB           0U
#define RS_USB2_ABI_ROLE_CTRL_AUTO                2U
#define RS_USB2_ABI_ROLE_IDLE                     0U
#define RS_USB2_ABI_ROLE_DEVICE                   1U
#define RS_USB2_ABI_ROLE_HOST                     2U
#define RS_USB2_ABI_PHY_CTRL_RESET_N              0U
#define RS_USB2_ABI_PHY_CTRL_SUSPEND              1U
#define RS_USB2_ABI_PHY_CTRL_REMOTE_WAKE          2U
#define RS_USB2_ABI_PHY_CTRL_VIEWPORT_START       31U
#define RS_USB2_ABI_PHY_CTRL_VIEWPORT_WRITE       30U
#define RS_USB2_ABI_PHY_CTRL_VIEWPORT_ADDR_LSB    16U
#define RS_USB2_ABI_PHY_CTRL_VIEWPORT_DATA_LSB    0U
#define RS_USB2_ABI_IRQ_ROLE_CHANGE               0U
#define RS_USB2_ABI_IRQ_PORT_CHANGE               1U
#define RS_USB2_ABI_IRQ_BUS_RESET                 2U
#define RS_USB2_ABI_IRQ_SUSPEND                   3U
#define RS_USB2_ABI_IRQ_RESUME                    4U
#define RS_USB2_ABI_IRQ_SETUP                     5U
#define RS_USB2_ABI_IRQ_ENDPOINT                  6U
#define RS_USB2_ABI_IRQ_CHANNEL                   7U
#define RS_USB2_ABI_IRQ_DMA_DONE                  8U
#define RS_USB2_ABI_IRQ_DMA_ERROR                 9U
#define RS_USB2_ABI_IRQ_PHY_ERROR                 10U
#define RS_USB2_ABI_IRQ_ULPI_ERROR                11U
#define RS_USB2_ABI_IRQ_ECC_CORRECTED             12U
#define RS_USB2_ABI_IRQ_ECC_UNCORRECTABLE         13U
#define RS_USB2_ABI_IRQ_TIMEOUT                   14U
#define RS_USB2_ABI_IRQ_FATAL                     15U
#define RS_USB2_ABI_ENDPOINT_CFG_IN_ENABLE        0U
#define RS_USB2_ABI_ENDPOINT_CFG_OUT_ENABLE       1U
#define RS_USB2_ABI_ENDPOINT_CFG_IN_STALL         2U
#define RS_USB2_ABI_ENDPOINT_CFG_OUT_STALL        3U
#define RS_USB2_ABI_ENDPOINT_CFG_TYPE_LSB         4U
#define RS_USB2_ABI_ENDPOINT_CFG_MAX_PACKET_LSB   16U
#define RS_USB2_ABI_ENDPOINT_COMMAND_PRIME_IN     0U
#define RS_USB2_ABI_ENDPOINT_COMMAND_ARM_OUT      1U
#define RS_USB2_ABI_ENDPOINT_COMMAND_CANCEL       2U
#define RS_USB2_ABI_ENDPOINT_COMMAND_RESET_TOGGLE 3U
#define RS_USB2_ABI_CHANNEL_CFG_ENABLE            0U
#define RS_USB2_ABI_CHANNEL_CFG_DIRECTION_IN      1U
#define RS_USB2_ABI_CHANNEL_CFG_TYPE_LSB          2U
#define RS_USB2_ABI_CHANNEL_CFG_LOW_SPEED         4U
#define RS_USB2_ABI_CHANNEL_CFG_SETUP             5U
#define RS_USB2_ABI_CHANNEL_CFG_PING_ENABLE       6U
#define RS_USB2_ABI_CHANNEL_CFG_MAX_PACKET_LSB    16U
#define RS_USB2_ABI_CHANNEL_TARGET_ADDR_LSB       0U
#define RS_USB2_ABI_CHANNEL_TARGET_ENDPOINT_LSB   8U
#define RS_USB2_ABI_CHANNEL_TARGET_TOGGLE         12U
#define RS_USB2_ABI_CHANNEL_COMMAND_START         0U
#define RS_USB2_ABI_CHANNEL_COMMAND_CANCEL        1U
#define RS_USB2_ABI_RAM_REGION_BASE_LSB           2U
#define RS_USB2_ABI_RAM_REGION_LENGTH_LSB         16U
#define RS_USB2_ABI_DESC_OWN                      0U
#define RS_USB2_ABI_DESC_CHAIN                    1U
#define RS_USB2_ABI_DESC_END                      2U
#define RS_USB2_ABI_DESC_IRQ                      3U
#define RS_USB2_ABI_DESC_SHORT_OK                 4U
#define RS_USB2_ABI_DESC_ZERO_PACKET              5U
#define RS_USB2_ABI_DESC_DONE                     16U
#define RS_USB2_ABI_DESC_SHORT                    17U
#define RS_USB2_ABI_DESC_STALL                    18U
#define RS_USB2_ABI_DESC_TIMEOUT                  19U
#define RS_USB2_ABI_DESC_CRC_ERROR                20U
#define RS_USB2_ABI_DESC_PROTOCOL_ERROR           21U
#define RS_USB2_ABI_DESC_AXI_ERROR                22U
#define RS_USB2_ABI_DESC_ABORTED                  23U

#define RS_USB2_REG_IP_ID                         RS_USB2_ABI_IP_ID
#define RS_USB2_REG_IP_VERSION                    RS_USB2_ABI_IP_VERSION
#define RS_USB2_REG_CAPABILITY0                   RS_USB2_ABI_CAPABILITY0
#define RS_USB2_REG_CAPABILITY1                   RS_USB2_ABI_CAPABILITY1
#define RS_USB2_REG_GLOBAL_CTRL                   RS_USB2_ABI_GLOBAL_CTRL
#define RS_USB2_REG_GLOBAL_STATUS                 RS_USB2_ABI_GLOBAL_STATUS
#define RS_USB2_REG_ROLE_CTRL                     RS_USB2_ABI_ROLE_CTRL
#define RS_USB2_REG_ROLE_STATUS                   RS_USB2_ABI_ROLE_STATUS
#define RS_USB2_REG_PHY_CTRL                      RS_USB2_ABI_PHY_CTRL
#define RS_USB2_REG_PHY_STATUS                    RS_USB2_ABI_PHY_STATUS
#define RS_USB2_REG_ULPI_VIEWPORT                 RS_USB2_ABI_ULPI_VIEWPORT
#define RS_USB2_REG_ULPI_VIEWPORT_DATA            RS_USB2_ABI_ULPI_VIEWPORT_DATA
#define RS_USB2_REG_TIMEOUT                       RS_USB2_ABI_TIMEOUT
#define RS_USB2_REG_FRAME                         RS_USB2_ABI_FRAME
#define RS_USB2_REG_IRQ_STATUS                    RS_USB2_ABI_IRQ_STATUS
#define RS_USB2_REG_IRQ_ENABLE                    RS_USB2_ABI_IRQ_ENABLE
#define RS_USB2_REG_IRQ_TEST                      RS_USB2_ABI_IRQ_TEST
#define RS_USB2_REG_ERROR_STATUS                  RS_USB2_ABI_ERROR_STATUS
#define RS_USB2_REG_ENDPOINT_PENDING_IN           RS_USB2_ABI_ENDPOINT_PENDING_IN
#define RS_USB2_REG_ENDPOINT_PENDING_OUT          RS_USB2_ABI_ENDPOINT_PENDING_OUT
#define RS_USB2_REG_ENDPOINT_COMPLETE_IN          RS_USB2_ABI_ENDPOINT_COMPLETE_IN
#define RS_USB2_REG_ENDPOINT_COMPLETE_OUT         RS_USB2_ABI_ENDPOINT_COMPLETE_OUT
#define RS_USB2_REG_DEVICE_ADDR                   RS_USB2_ABI_DEVICE_ADDR
#define RS_USB2_REG_HOST_STATUS                   RS_USB2_ABI_HOST_STATUS
#define RS_USB2_REG_PORT_CTRL                     RS_USB2_ABI_PORT_CTRL
#define RS_USB2_REG_PORT_STATUS                   RS_USB2_ABI_PORT_STATUS

#define RS_USB2_IP_ID_VALUE                       UINT32_C(0x55534232)
#define RS_USB2_IP_VERSION_VALUE                  UINT32_C(0x00010000)
#define RS_USB2_CAPABILITY0_REQUIRED              UINT32_C(0x00001FFF)
#define RS_USB2_CAPABILITY0_VALUE                 UINT32_C(0x0F071FFF)
#define RS_USB2_CAPABILITY1_VALUE                 UINT32_C(0x00104000)
#define RS_USB2_NUM_ENDPOINTS                     UINT32_C(8)
#define RS_USB2_NUM_CHANNELS                      UINT32_C(16)
#define RS_USB2_PACKET_RAM_BYTES                  UINT32_C(16384)
#define RS_USB2_MAX_TRANSFER_BYTES                UINT32_C(32767)
#define RS_USB2_DESCRIPTOR_ALIGNMENT              UINT32_C(32)
#define RS_USB2_DESCRIPTOR_SIZE                   UINT32_C(32)
#define RS_USB2_MAX_DESCRIPTOR_COUNT              UINT32_C(256)

#define RS_USB2_GLOBAL_CTRL_ENABLE                (UINT32_C(1) << RS_USB2_ABI_GLOBAL_CTRL_ENABLE)
#define RS_USB2_GLOBAL_CTRL_SOFT_RESET            (UINT32_C(1) << RS_USB2_ABI_GLOBAL_CTRL_SOFT_RESET)
#define RS_USB2_GLOBAL_CTRL_ABORT                 (UINT32_C(1) << RS_USB2_ABI_GLOBAL_CTRL_ABORT)
#define RS_USB2_GLOBAL_CTRL_IRQ_ENABLE            (UINT32_C(1) << RS_USB2_ABI_GLOBAL_CTRL_IRQ_ENABLE)
#define RS_USB2_GLOBAL_STATUS_ENABLED             UINT32_C(0x00000001)
#define RS_USB2_GLOBAL_STATUS_BUSY                UINT32_C(0x00000002)
#define RS_USB2_GLOBAL_STATUS_ROLE_MASK           UINT32_C(0x0000000C)
#define RS_USB2_GLOBAL_STATUS_LINK_READY          UINT32_C(0x00000010)
#define RS_USB2_GLOBAL_STATUS_DMA_BUSY            UINT32_C(0x00000020)
#define RS_USB2_ROLE_CTRL_AUTO                    (UINT32_C(1) << RS_USB2_ABI_ROLE_CTRL_AUTO)
#define RS_USB2_PHY_CTRL_RESET_N                  (UINT32_C(1) << RS_USB2_ABI_PHY_CTRL_RESET_N)
#define RS_USB2_PHY_CTRL_SUSPEND                  (UINT32_C(1) << RS_USB2_ABI_PHY_CTRL_SUSPEND)
#define RS_USB2_PHY_CTRL_REMOTE_WAKE              (UINT32_C(1) << RS_USB2_ABI_PHY_CTRL_REMOTE_WAKE)
#define RS_USB2_VIEWPORT_START                    (UINT32_C(1) << RS_USB2_ABI_PHY_CTRL_VIEWPORT_START)
#define RS_USB2_VIEWPORT_WRITE                    (UINT32_C(1) << RS_USB2_ABI_PHY_CTRL_VIEWPORT_WRITE)
#define RS_USB2_VIEWPORT_ERROR                    UINT32_C(0x00000100)

#define RS_USB2_IRQ_ROLE_CHANGE                   (UINT32_C(1) << RS_USB2_ABI_IRQ_ROLE_CHANGE)
#define RS_USB2_IRQ_PORT_CHANGE                   (UINT32_C(1) << RS_USB2_ABI_IRQ_PORT_CHANGE)
#define RS_USB2_IRQ_BUS_RESET                     (UINT32_C(1) << RS_USB2_ABI_IRQ_BUS_RESET)
#define RS_USB2_IRQ_SUSPEND                       (UINT32_C(1) << RS_USB2_ABI_IRQ_SUSPEND)
#define RS_USB2_IRQ_RESUME                        (UINT32_C(1) << RS_USB2_ABI_IRQ_RESUME)
#define RS_USB2_IRQ_SETUP                         (UINT32_C(1) << RS_USB2_ABI_IRQ_SETUP)
#define RS_USB2_IRQ_ENDPOINT                      (UINT32_C(1) << RS_USB2_ABI_IRQ_ENDPOINT)
#define RS_USB2_IRQ_CHANNEL                       (UINT32_C(1) << RS_USB2_ABI_IRQ_CHANNEL)
#define RS_USB2_IRQ_DMA_DONE                      (UINT32_C(1) << RS_USB2_ABI_IRQ_DMA_DONE)
#define RS_USB2_IRQ_DMA_ERROR                     (UINT32_C(1) << RS_USB2_ABI_IRQ_DMA_ERROR)
#define RS_USB2_IRQ_PHY_ERROR                     (UINT32_C(1) << RS_USB2_ABI_IRQ_PHY_ERROR)
#define RS_USB2_IRQ_ULPI_ERROR                    (UINT32_C(1) << RS_USB2_ABI_IRQ_ULPI_ERROR)
#define RS_USB2_IRQ_ECC_CORRECTED                 (UINT32_C(1) << RS_USB2_ABI_IRQ_ECC_CORRECTED)
#define RS_USB2_IRQ_ECC_UNCORRECTABLE             (UINT32_C(1) << RS_USB2_ABI_IRQ_ECC_UNCORRECTABLE)
#define RS_USB2_IRQ_TIMEOUT                       (UINT32_C(1) << RS_USB2_ABI_IRQ_TIMEOUT)
#define RS_USB2_IRQ_FATAL                         (UINT32_C(1) << RS_USB2_ABI_IRQ_FATAL)
#define RS_USB2_IRQ_ALL                           UINT32_C(0x0000FFFF)

#define RS_USB2_ENDPOINT_COMMAND_PRIME_IN         (UINT32_C(1) << RS_USB2_ABI_ENDPOINT_COMMAND_PRIME_IN)
#define RS_USB2_ENDPOINT_COMMAND_ARM_OUT          (UINT32_C(1) << RS_USB2_ABI_ENDPOINT_COMMAND_ARM_OUT)
#define RS_USB2_ENDPOINT_COMMAND_CANCEL           (UINT32_C(1) << RS_USB2_ABI_ENDPOINT_COMMAND_CANCEL)
#define RS_USB2_ENDPOINT_COMMAND_RESET_TOGGLE                                                      \
    (UINT32_C(1) << RS_USB2_ABI_ENDPOINT_COMMAND_RESET_TOGGLE)
#define RS_USB2_CHANNEL_COMMAND_START      (UINT32_C(1) << RS_USB2_ABI_CHANNEL_COMMAND_START)
#define RS_USB2_CHANNEL_COMMAND_CANCEL     (UINT32_C(1) << RS_USB2_ABI_CHANNEL_COMMAND_CANCEL)
#define RS_USB2_PORT_CTRL_FORCE_FULL_SPEED UINT32_C(0x00000001)

#define RS_USB2_DESC_OWN                   (UINT32_C(1) << RS_USB2_ABI_DESC_OWN)
#define RS_USB2_DESC_CHAIN                 (UINT32_C(1) << RS_USB2_ABI_DESC_CHAIN)
#define RS_USB2_DESC_END                   (UINT32_C(1) << RS_USB2_ABI_DESC_END)
#define RS_USB2_DESC_IRQ                   (UINT32_C(1) << RS_USB2_ABI_DESC_IRQ)
#define RS_USB2_DESC_SHORT_OK              (UINT32_C(1) << RS_USB2_ABI_DESC_SHORT_OK)
#define RS_USB2_DESC_ZERO_PACKET           (UINT32_C(1) << RS_USB2_ABI_DESC_ZERO_PACKET)
#define RS_USB2_DESC_WRITEBACK_MASK        UINT32_C(0x00FF0000)
#define RS_USB2_DESC_RESERVED_MASK         UINT32_C(0xFF00FFC0)
#define RS_USB2_DESC_FRAME_RESERVED_MASK   UINT32_C(0xF8000000)

typedef struct {
    uint32_t buffer_addr;
    uint32_t byte_length;
    uint32_t next_addr;
    uint32_t control;
    uint32_t actual_length;
    uint32_t status;
    uint32_t frame;
    uint32_t reserved;
} rs_usb2_descriptor_t;

_Static_assert(sizeof(rs_usb2_descriptor_t) == 32U, "USB2 descriptor ABI size");

#endif
