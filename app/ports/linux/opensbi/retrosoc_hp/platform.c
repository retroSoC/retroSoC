/* SPDX-License-Identifier: BSD-2-Clause */
/* Copyright (c) 2026 Yuchi Miao */

#include <sbi/riscv_asm.h>
#include <sbi/riscv_encoding.h>
#include <sbi/riscv_io.h>
#include <sbi/sbi_console.h>
#include <sbi/sbi_platform.h>
#include <sbi/sbi_timer.h>
#include <sbi_utils/ipi/aclint_mswi.h>

/* Internal C906 CLINT (thead,c900-clint), decoded by the core BIU. */
#define RETROSOC_HP_CLINT_BASE           0x0C000000UL
#define RETROSOC_HP_CLINT_MTIMECMP_LO    0x4000UL
#define RETROSOC_HP_CLINT_MTIMECMP_HI    0x4004UL
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
    .addr = RETROSOC_HP_CLINT_BASE,
    .size = ACLINT_MSWI_SIZE,
    .first_hartid = 1U,
    .hart_count = 1U,
};

/* No memory-mapped mtime: the SoC drives mtime into the core. */
static u64 retrosoc_hp_timer_value(void) {
    return csr_read(CSR_TIME);
}

static void retrosoc_hp_mtimecmp_write(u64 value) {
    writel_relaxed((u32)-1, (void *)(RETROSOC_HP_CLINT_BASE + RETROSOC_HP_CLINT_MTIMECMP_LO));
    writel_relaxed((u32)(value >> 32U),
                   (void *)(RETROSOC_HP_CLINT_BASE + RETROSOC_HP_CLINT_MTIMECMP_HI));
    writel_relaxed((u32)value, (void *)(RETROSOC_HP_CLINT_BASE + RETROSOC_HP_CLINT_MTIMECMP_LO));
}

static void retrosoc_hp_timer_event_start(u64 next_event) {
    retrosoc_hp_mtimecmp_write(next_event);
}

static void retrosoc_hp_timer_event_stop(void) {
    retrosoc_hp_mtimecmp_write(~0ULL);
}

static int retrosoc_hp_timer_warm_init(void) {
    retrosoc_hp_timer_event_stop();
    return 0;
}

static struct sbi_timer_device s_timer = {
    .name = "retrosoc-hp-c906-clint",
    .timer_freq = 1000000UL,
    .timer_value = retrosoc_hp_timer_value,
    .timer_event_start = retrosoc_hp_timer_event_start,
    .timer_event_stop = retrosoc_hp_timer_event_stop,
    .warm_init = retrosoc_hp_timer_warm_init,
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
    sbi_timer_set_device(&s_timer);
    return 0;
}

static const struct sbi_platform_operations s_platform_operations = {
    .early_init = retrosoc_hp_early_init,
    .timer_init = retrosoc_hp_timer_init,
};

const struct sbi_platform platform = {
    .opensbi_version = OPENSBI_VERSION,
    .platform_version = SBI_PLATFORM_VERSION(1U, 0U),
    .name = "retroSoC OpenC906 HP",
    .features = SBI_PLATFORM_DEFAULT_FEATURES,
    .hart_count = 1U,
    .hart_stack_size = SBI_PLATFORM_DEFAULT_HART_STACK_SIZE,
    .heap_size = SBI_PLATFORM_DEFAULT_HEAP_SIZE(1U),
    .platform_ops_addr = (unsigned long)&s_platform_operations,
    .hart_index2id = s_hart_index_to_id,
};
