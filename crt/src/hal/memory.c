#include <stddef.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/memory.h>
#include <retrosoc/hal/onchip_sram.h>
#include <retrosoc/hal/opipsram.h>
#include <retrosoc/hal/psram.h>
#include <retrosoc/hal/sdram.h>
#include <retrosoc/hal/xpi.h>

#define RS_MEMORY_PAD_MODE_MASK UINT32_C(0x00000003)

static volatile uint32_t *rs_memory_sysctrl_register(uint32_t offset) {
    return (volatile uint32_t *)(RS_SOC_APB4_SYSCTRL_BASE + (uintptr_t)offset);
}

static rs_memory_pad_mode_t rs_memory_pad_mode(void) {
    const uint32_t value =
        *rs_memory_sysctrl_register(RS_SOC_SYSCTRL_MEM_PAD_STATUS_OFFSET) & RS_MEMORY_PAD_MODE_MASK;
    return (rs_memory_pad_mode_t)value;
}

static void rs_memory_static_info(rs_memory_target_t target, rs_memory_info_t *info) {
    info->target = target;
    info->controller_present = true;
    info->cacheable = true;
    info->dma_visible = true;
    switch (target) {
    case RS_MEMORY_SRAM:
        info->base = (uintptr_t)RS_SOC_SRAM_BASE;
        info->size = RS_SOC_SRAM_END - RS_SOC_SRAM_BASE + UINT32_C(1);
        info->latency = RS_MEMORY_LATENCY_ONCHIP;
        break;
    case RS_MEMORY_SDRAM:
        info->base = (uintptr_t)RS_SOC_SDRAM_BASE;
        info->size = RS_SOC_SDRAM_END - RS_SOC_SDRAM_BASE + UINT32_C(1);
        info->latency = RS_MEMORY_LATENCY_PARALLEL;
        break;
    case RS_MEMORY_QPI_PSRAM:
        info->base = (uintptr_t)RS_SOC_PSRAM_BASE;
        info->size = RS_SOC_PSRAM_END - RS_SOC_PSRAM_BASE + UINT32_C(1);
        info->latency = RS_MEMORY_LATENCY_SERIAL;
        break;
    case RS_MEMORY_OPI_PSRAM:
        info->base = (uintptr_t)RS_SOC_OPIPSRAM_BASE;
        info->size = RS_SOC_OPIPSRAM_END - RS_SOC_OPIPSRAM_BASE + UINT32_C(1);
        info->latency = RS_MEMORY_LATENCY_SERIAL;
        break;
    case RS_MEMORY_XPI:
        info->base = (uintptr_t)RS_SOC_XPI_BASE;
        info->size = RS_SOC_XPI_END - RS_SOC_XPI_BASE + UINT32_C(1);
        info->latency = RS_MEMORY_LATENCY_SERIAL;
        break;
    default:
        info->controller_present = false;
        break;
    }
}

rs_status_t rs_memory_get_info(rs_memory_target_t target, rs_memory_info_t *info) {
    rs_status_t result = RS_OK;

    if ((info == NULL) || (target > RS_MEMORY_XPI)) {
        return RS_EINVAL;
    }
    *info = (rs_memory_info_t){0};
    rs_memory_static_info(target, info);
    info->pad_mode = rs_memory_pad_mode();

    switch (target) {
    case RS_MEMORY_SRAM: {
        rs_onchip_sram_info_t status;
        result = rs_onchip_sram_probe(&status);
        if (result == RS_OK) {
            info->controller_present = status.present;
            info->device_present = status.present;
            info->initialized = status.present;
            info->ready = status.present;
            info->active = status.present;
            info->size = status.memory_bytes;
        }
        break;
    }
    case RS_MEMORY_SDRAM: {
        rs_sdram_status_t status;
        result = rs_sdram_get_status(&status);
        if (result == RS_OK) {
            info->device_present = status.ready;
            info->initialized = status.ready;
            info->ready = status.ready;
            info->active = status.ready;
            info->fault = status.error;
            info->fault_code = (uint32_t)status.last_error;
        }
        break;
    }
    case RS_MEMORY_QPI_PSRAM: {
        rs_psram_status_t status;
        result = rs_psram_get_status(&status);
        if (result == RS_OK) {
            info->device_present = status.chip_present != UINT8_C(0);
            info->initialized = status.chip_ready != UINT8_C(0);
            info->ready = status.ready;
            info->active = status.ready && (info->pad_mode == RS_MEMORY_PAD_QPI);
            info->fault = status.chip_error != UINT8_C(0);
            info->fault_code = (uint32_t)status.last_error;
        }
        break;
    }
    case RS_MEMORY_OPI_PSRAM: {
        rs_opipsram_status_t status;
        result = rs_opipsram_get_status(&status);
        if (result == RS_OK) {
            info->device_present = status.initialized;
            info->initialized = status.initialized;
            info->ready = status.ready;
            info->active = status.ready && (info->pad_mode == RS_MEMORY_PAD_OPI);
            info->fault = status.error;
            info->fault_code = status.last_error;
        }
        break;
    }
    case RS_MEMORY_XPI:
        result = rs_xpi_probe();
        info->device_present = result == RS_OK;
        info->initialized = result == RS_OK;
        info->ready = result == RS_OK;
        info->active = result == RS_OK;
        info->fault = result != RS_OK;
        break;
    default:
        result = RS_EINVAL;
        break;
    }
    return result;
}
