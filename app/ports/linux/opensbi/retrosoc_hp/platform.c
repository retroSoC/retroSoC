/* SPDX-License-Identifier: BSD-2-Clause */
/* Copyright (c) 2026 Yuchi Miao */

#include <sbi/riscv_io.h>
#include <sbi/sbi_console.h>
#include <sbi/sbi_platform.h>
#include <sbi_utils/ipi/aclint_mswi.h>
#include <sbi_utils/timer/aclint_mtimer.h>

#define RETROSOC_HP_ACLINT_BASE          0x02000000UL
#define RETROSOC_HP_UART_BASE            0x10018000UL
#define RETROSOC_HP_UART_BAUD_INT        78U
#define RETROSOC_HP_UART_BAUD_FRAC       32U
#define RETROSOC_HP_UART_BAUD_INT_REG    0x00UL
#define RETROSOC_HP_UART_BAUD_FRAC_REG   0x04UL
#define RETROSOC_HP_UART_LINE_CTRL_REG   0x08UL
#define RETROSOC_HP_UART_CTRL_REG        0x0CUL
#define RETROSOC_HP_UART_TXDATA_REG      0x10UL
#define RETROSOC_HP_UART_RXDATA_REG      0x14UL
#define RETROSOC_HP_UART_STATUS_REG      0x18UL
#define RETROSOC_HP_UART_FIFO_CTRL_REG   0x20UL
#define RETROSOC_HP_UART_ERROR_REG       0x30UL
#define RETROSOC_HP_UART_INTR_ENABLE_REG 0x38UL
#define RETROSOC_HP_UART_TX_FULL         0x20U
#define RETROSOC_HP_UART_RX_EMPTY        0x40U
#define RETROSOC_HP_UART_ENABLE          0x03U
#define RETROSOC_HP_UART_FIFO_FLUSH      0x03U
#define RETROSOC_HP_UART_ERROR_ALL       0x7FU

static const u32 s_hart_index_to_id[] = {1U};

static struct aclint_mswi_data s_mswi = {
    .addr = RETROSOC_HP_ACLINT_BASE,
    .size = ACLINT_MSWI_SIZE,
    .first_hartid = 0U,
    .hart_count = 2U,
};

static struct aclint_mtimer_data s_mtimer = {
    .mtime_freq = 1000000UL,
    .mtime_addr = RETROSOC_HP_ACLINT_BASE + 0xBFF8UL,
    .mtime_size = ACLINT_DEFAULT_MTIME_SIZE,
    .mtimecmp_addr = RETROSOC_HP_ACLINT_BASE + 0x4000UL,
    .mtimecmp_size = ACLINT_DEFAULT_MTIMECMP_SIZE,
    .first_hartid = 0U,
    .hart_count = 2U,
    .has_64bit_mmio = false,
};

static void retrosoc_hp_uart_write(u32 offset, u32 value) {
    writel(value, (void *)(RETROSOC_HP_UART_BASE + offset));
}

static u32 retrosoc_hp_uart_read(u32 offset) {
    return readl((const void *)(RETROSOC_HP_UART_BASE + offset));
}

static void retrosoc_hp_console_putc(char value) {
    while ((retrosoc_hp_uart_read(RETROSOC_HP_UART_STATUS_REG) & RETROSOC_HP_UART_TX_FULL) != 0U) {
    }
    retrosoc_hp_uart_write(RETROSOC_HP_UART_TXDATA_REG, (u32)(unsigned char)value);
}

static int retrosoc_hp_console_getc(void) {
    if ((retrosoc_hp_uart_read(RETROSOC_HP_UART_STATUS_REG) & RETROSOC_HP_UART_RX_EMPTY) != 0U) {
        return -1;
    }
    return (int)(retrosoc_hp_uart_read(RETROSOC_HP_UART_RXDATA_REG) & 0xFFU);
}

static struct sbi_console_device s_console = {
    .name = "retrosoc-uart1",
    .console_putc = retrosoc_hp_console_putc,
    .console_getc = retrosoc_hp_console_getc,
};

static int retrosoc_hp_early_init(bool cold_boot) {
    if (!cold_boot) {
        return 0;
    }

    retrosoc_hp_uart_write(RETROSOC_HP_UART_CTRL_REG, 0U);
    retrosoc_hp_uart_write(RETROSOC_HP_UART_FIFO_CTRL_REG, RETROSOC_HP_UART_FIFO_FLUSH);
    retrosoc_hp_uart_write(RETROSOC_HP_UART_ERROR_REG, RETROSOC_HP_UART_ERROR_ALL);
    retrosoc_hp_uart_write(RETROSOC_HP_UART_INTR_ENABLE_REG, 0U);
    retrosoc_hp_uart_write(RETROSOC_HP_UART_BAUD_INT_REG, RETROSOC_HP_UART_BAUD_INT);
    retrosoc_hp_uart_write(RETROSOC_HP_UART_BAUD_FRAC_REG, RETROSOC_HP_UART_BAUD_FRAC);
    retrosoc_hp_uart_write(RETROSOC_HP_UART_LINE_CTRL_REG, 3U);
    retrosoc_hp_uart_write(RETROSOC_HP_UART_CTRL_REG, RETROSOC_HP_UART_ENABLE);
    sbi_console_set_device(&s_console);

    return aclint_mswi_cold_init(&s_mswi);
}

static int retrosoc_hp_timer_init(void) {
    return aclint_mtimer_cold_init(&s_mtimer, NULL);
}

static const struct sbi_platform_operations s_platform_operations = {
    .early_init = retrosoc_hp_early_init,
    .timer_init = retrosoc_hp_timer_init,
};

const struct sbi_platform platform = {
    .opensbi_version = OPENSBI_VERSION,
    .platform_version = SBI_PLATFORM_VERSION(1U, 0U),
    .name = "retroSoC RV32 HP",
    .features = SBI_PLATFORM_DEFAULT_FEATURES,
    .hart_count = 1U,
    .hart_stack_size = SBI_PLATFORM_DEFAULT_HART_STACK_SIZE,
    .heap_size = SBI_PLATFORM_DEFAULT_HEAP_SIZE(1U),
    .platform_ops_addr = (unsigned long)&s_platform_operations,
    .hart_index2id = s_hart_index_to_id,
};
