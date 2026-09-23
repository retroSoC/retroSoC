#ifndef RETROSOC_HAL_GA2D_REGS_H
#define RETROSOC_HAL_GA2D_REGS_H

#include <stdint.h>

#include <retrosoc/core/soc.h>

#define RS_GA2D_REG_IP_ID                           UINT32_C(0x000)
#define RS_GA2D_REG_IP_VERSION                      UINT32_C(0x004)
#define RS_GA2D_REG_CAPABILITY                      UINT32_C(0x008)
#define RS_GA2D_REG_LIMITS                          UINT32_C(0x00C)
#define RS_GA2D_REG_COMMAND                         UINT32_C(0x010)
#define RS_GA2D_REG_STATUS                          UINT32_C(0x014)
#define RS_GA2D_REG_IRQ_STATE                       UINT32_C(0x018)
#define RS_GA2D_REG_IRQ_ENABLE                      UINT32_C(0x01C)
#define RS_GA2D_REG_IRQ_TEST                        UINT32_C(0x020)
#define RS_GA2D_REG_ERROR_STATUS                    UINT32_C(0x024)
#define RS_GA2D_REG_ERROR_ADDRESS                   UINT32_C(0x028)
#define RS_GA2D_REG_TIMEOUT_CYCLES                  UINT32_C(0x02C)
#define RS_GA2D_REG_JOB_CONFIG                      UINT32_C(0x030)
#define RS_GA2D_REG_GLOBAL_ALPHA                    UINT32_C(0x034)
#define RS_GA2D_REG_COLOR                           UINT32_C(0x038)
#define RS_GA2D_REG_SIZE                            UINT32_C(0x03C)
#define RS_GA2D_REG_FG_ADDRESS                      UINT32_C(0x040)
#define RS_GA2D_REG_FG_PITCH                        UINT32_C(0x044)
#define RS_GA2D_REG_FG_FORMAT                       UINT32_C(0x048)
#define RS_GA2D_REG_BG_ADDRESS                      UINT32_C(0x04C)
#define RS_GA2D_REG_BG_PITCH                        UINT32_C(0x050)
#define RS_GA2D_REG_BG_FORMAT                       UINT32_C(0x054)
#define RS_GA2D_REG_DST_ADDRESS                     UINT32_C(0x058)
#define RS_GA2D_REG_DST_PITCH                       UINT32_C(0x05C)
#define RS_GA2D_REG_DST_FORMAT                      UINT32_C(0x060)
#define RS_GA2D_REG_PERF_SNAPSHOT                   UINT32_C(0x064)
#define RS_GA2D_REG_FORMAT_CAPABILITY               UINT32_C(0x068)
#define RS_GA2D_REG_SNAP_CYCLES_LO                  UINT32_C(0x080)
#define RS_GA2D_REG_SNAP_CYCLES_HI                  UINT32_C(0x084)
#define RS_GA2D_REG_SNAP_READ_BYTES_LO              UINT32_C(0x088)
#define RS_GA2D_REG_SNAP_READ_BYTES_HI              UINT32_C(0x08C)
#define RS_GA2D_REG_SNAP_WRITE_BYTES_LO             UINT32_C(0x090)
#define RS_GA2D_REG_SNAP_WRITE_BYTES_HI             UINT32_C(0x094)
#define RS_GA2D_REG_SNAP_READ_STALL_LO              UINT32_C(0x098)
#define RS_GA2D_REG_SNAP_READ_STALL_HI              UINT32_C(0x09C)
#define RS_GA2D_REG_SNAP_WRITE_STALL_LO             UINT32_C(0x0A0)
#define RS_GA2D_REG_SNAP_WRITE_STALL_HI             UINT32_C(0x0A4)
#define RS_GA2D_REG_SNAP_PIPE_STALL_LO              UINT32_C(0x0A8)
#define RS_GA2D_REG_SNAP_PIPE_STALL_HI              UINT32_C(0x0AC)
#define RS_GA2D_REG_SNAP_LINES_DONE                 UINT32_C(0x0B0)

#define RS_GA2D_IP_ID_VALUE                         UINT32_C(0x47413244)
#define RS_GA2D_IP_VERSION_VALUE                    UINT32_C(0x00010000)
#define RS_GA2D_IP_VERSION_MAJOR_MASK               UINT32_C(0xFFFF0000)
#define RS_GA2D_IP_VERSION_MAJOR_1                  UINT32_C(0x00010000)
#define RS_GA2D_CAPABILITY_P4                       UINT32_C(0x000003E3)
#define RS_GA2D_LIMITS_P4                           UINT32_C(0x08202010)
#define RS_GA2D_FORMAT_CAPABILITY_P4                UINT32_C(0x000F000F)
#define RS_GA2D_CAPABILITY_P5                       UINT32_C(0x000007FF)
#define RS_GA2D_LIMITS_P5                           UINT32_C(0x08202010)
#define RS_GA2D_FORMAT_CAPABILITY_P5                UINT32_C(0x000F0F1F)
#define RS_GA2D_TIMEOUT_CYCLES_RESET                UINT32_C(0x00100000)
#define RS_GA2D_GLOBAL_ALPHA_RESET                  UINT32_C(0x000000FF)

#define RS_GA2D_COMMAND_START                       UINT32_C(0x00000001)
#define RS_GA2D_COMMAND_ABORT                       UINT32_C(0x00000002)
#define RS_GA2D_COMMAND_SOFT_RESET                  UINT32_C(0x00000004)

#define RS_GA2D_STATUS_BUSY                         UINT32_C(0x00000001)
#define RS_GA2D_STATUS_DRAINING                     UINT32_C(0x00000002)
#define RS_GA2D_STATUS_QUIESCED                     UINT32_C(0x00000004)
#define RS_GA2D_STATUS_DATA_READY                   UINT32_C(0x00000008)
#define RS_GA2D_STATUS_DONE                         UINT32_C(0x00000010)
#define RS_GA2D_STATUS_ABORTED                      UINT32_C(0x00000020)
#define RS_GA2D_STATUS_ERROR                        UINT32_C(0x00000040)
#define RS_GA2D_STATUS_RECOVERY_REQUIRED            UINT32_C(0x00000080)

#define RS_GA2D_IRQ_DONE                            UINT32_C(0x00000001)
#define RS_GA2D_IRQ_ERROR                           UINT32_C(0x00000002)
#define RS_GA2D_IRQ_ABORT_DONE                      UINT32_C(0x00000004)
#define RS_GA2D_IRQ_ALL                             UINT32_C(0x00000007)

#define RS_GA2D_ERROR_STATUS_VALID                  UINT32_C(0x00000001)
#define RS_GA2D_ERROR_STATUS_CODE_SHIFT             1U
#define RS_GA2D_ERROR_STATUS_CODE_MASK              UINT32_C(0x000000FE)
#define RS_GA2D_ERROR_STATUS_STAGE_SHIFT            8U
#define RS_GA2D_ERROR_STATUS_STAGE_MASK             UINT32_C(0x00000F00)
#define RS_GA2D_ERROR_STATUS_AXI_RESPONSE_SHIFT     12U
#define RS_GA2D_ERROR_STATUS_AXI_RESPONSE_MASK      UINT32_C(0x00003000)

#define RS_GA2D_JOB_CONFIG_OPERATION_SHIFT          0U
#define RS_GA2D_JOB_CONFIG_OPERATION_MASK           UINT32_C(0x00000003)
#define RS_GA2D_GLOBAL_ALPHA_VALUE_SHIFT            0U
#define RS_GA2D_GLOBAL_ALPHA_VALUE_MASK             UINT32_C(0x000000FF)
#define RS_GA2D_SIZE_WIDTH_SHIFT                    0U
#define RS_GA2D_SIZE_WIDTH_MASK                     UINT32_C(0x0000FFFF)
#define RS_GA2D_SIZE_HEIGHT_SHIFT                   16U
#define RS_GA2D_SIZE_HEIGHT_MASK                    UINT32_C(0xFFFF0000)
#define RS_GA2D_FG_FORMAT_VALUE_SHIFT               0U
#define RS_GA2D_BG_FORMAT_VALUE_SHIFT               0U
#define RS_GA2D_DST_FORMAT_VALUE_SHIFT              0U
#define RS_GA2D_FORMAT_VALUE_MASK                   UINT32_C(0x00000007)
#define RS_GA2D_FORMAT_CAPABILITY_FOREGROUND_SHIFT  0U
#define RS_GA2D_FORMAT_CAPABILITY_BACKGROUND_SHIFT  8U
#define RS_GA2D_FORMAT_CAPABILITY_DESTINATION_SHIFT 16U
#define RS_GA2D_FORMAT_CAPABILITY_MASK              UINT32_C(0x0000001F)

#define RS_GA2D_CAPABILITY_FILL                     UINT32_C(0x00000001)
#define RS_GA2D_CAPABILITY_COPY                     UINT32_C(0x00000002)
#define RS_GA2D_CAPABILITY_CONVERT                  UINT32_C(0x00000004)
#define RS_GA2D_CAPABILITY_BLEND                    UINT32_C(0x00000008)
#define RS_GA2D_CAPABILITY_A8_MASK                  UINT32_C(0x00000010)
#define RS_GA2D_CAPABILITY_PRIVATE_DMA              UINT32_C(0x00000020)
#define RS_GA2D_CAPABILITY_IRQ                      UINT32_C(0x00000040)
#define RS_GA2D_CAPABILITY_SNAPSHOT                 UINT32_C(0x00000080)
#define RS_GA2D_CAPABILITY_TWO_DIMENSIONAL_PITCH    UINT32_C(0x00000100)
#define RS_GA2D_CAPABILITY_BYTE_EDGES               UINT32_C(0x00000200)
#define RS_GA2D_CAPABILITY_INPLACE_BACKGROUND       UINT32_C(0x00000400)

#define RS_GA2D_ERROR_CODE_NONE                     0U
#define RS_GA2D_ERROR_CODE_INVALID_SIZE             1U
#define RS_GA2D_ERROR_CODE_INVALID_FORMAT           2U
#define RS_GA2D_ERROR_CODE_INVALID_PITCH            3U
#define RS_GA2D_ERROR_CODE_INVALID_ALIGNMENT        4U
#define RS_GA2D_ERROR_CODE_ADDRESS_OVERFLOW         5U
#define RS_GA2D_ERROR_CODE_ADDRESS_RANGE            6U
#define RS_GA2D_ERROR_CODE_OVERLAP                  7U
#define RS_GA2D_ERROR_CODE_AXI_READ                 8U
#define RS_GA2D_ERROR_CODE_AXI_WRITE                9U
#define RS_GA2D_ERROR_CODE_AXI_PROTOCOL             10U
#define RS_GA2D_ERROR_CODE_TIMEOUT                  11U
#define RS_GA2D_ERROR_CODE_EPOCH_LOST               12U
#define RS_GA2D_ERROR_CODE_INTERNAL                 13U

#define RS_GA2D_ERROR_STAGE_NONE                    0U
#define RS_GA2D_ERROR_STAGE_VALIDATE                1U
#define RS_GA2D_ERROR_STAGE_FOREGROUND              2U
#define RS_GA2D_ERROR_STAGE_BACKGROUND              3U
#define RS_GA2D_ERROR_STAGE_DESTINATION             4U
#define RS_GA2D_ERROR_STAGE_LIFECYCLE               5U

#define RS_GA2D_REG(offset)                         RS_SOC_REG32(RS_SOC_APB4_GA2D_BASE, (offset))

#endif
