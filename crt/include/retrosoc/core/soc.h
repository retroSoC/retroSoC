#ifndef _RETROSOC_DEF_H_
#define _RETROSOC_DEF_H_

#include <stdint.h>
#include <stdbool.h>

#include <retrosoc/generated/memory_map.h>
#include <retrosoc/generated/user_extensions.h>

#define HW_CORE                    "Management Hazard3"

#define CPU_FREQ                   72     // unit: MHz
#define UART_BPS                   921600 // unit: bps
#define SPFS_MEM_START             RS_SOC_FLASH_BASE
#define SPFS_MEM_OFFST             RS_SOC_FLASH_SIZE
#define SRAM_MEM_START             RS_SOC_SRAM_BASE
#define SRAM_MEM_OFFST             RS_SOC_SRAM_SIZE
#define SDRAM_MEM_START            RS_SOC_SDRAM_BASE
#define SDRAM_MEM_OFFST            RS_SOC_SDRAM_SIZE
#define PSRAM_MEM_START            RS_SOC_PSRAM_BASE
#define PSRAM_MEM_OFFST            RS_SOC_PSRAM_SIZE
#define XPI_MEM_START              RS_SOC_XPI_BASE
#define XPI_MEM_OFFST              RS_SOC_XPI_SIZE
#define TF_CARD_START              RS_SOC_SPISD_BASE
#define TF_CARD_OFFST              RS_SOC_SPISD_SIZE

#define RS_SOC_REG32(base, offset) (*(volatile uint32_t *)(uintptr_t)((base) + (offset)))

#define reg_user_ip_reg0           RS_SOC_REG32(RS_SOC_APB4_USER_IP_BASE, UINT32_C(0x00))
#define reg_user_ip_reg1           RS_SOC_REG32(RS_SOC_APB4_USER_IP_BASE, UINT32_C(0x04))
#define reg_user_ip_reg2           RS_SOC_REG32(RS_SOC_APB4_USER_IP_BASE, UINT32_C(0x08))
#define reg_user_ip_reg3           RS_SOC_REG32(RS_SOC_APB4_USER_IP_BASE, UINT32_C(0x0C))
#define reg_user_ip_reg4           RS_SOC_REG32(RS_SOC_APB4_USER_IP_BASE, UINT32_C(0x10))
#define reg_user_ip_reg5           RS_SOC_REG32(RS_SOC_APB4_USER_IP_BASE, UINT32_C(0x14))
#define reg_user_ip_reg6           RS_SOC_REG32(RS_SOC_APB4_USER_IP_BASE, UINT32_C(0x18))
#endif
