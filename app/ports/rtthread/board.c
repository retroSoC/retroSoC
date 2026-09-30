#include "board.h"
#include "hp_boot_bundle.h"

#include <rthw.h>

#define RS_RTT_UART    UINT32_C(0x10018000)
#define RS_RTT_CLINT   UINT32_C(0x02000000)
#define RS_RTT_PLIC    UINT32_C(0x0C000000)
#define RS_RTT_MAILBOX UINT32_C(0x10019000)

static struct rt_semaphore s_mailbox_sem;
static volatile uint32_t s_irq_command;
static volatile uint32_t s_irq_argument;
static volatile uint32_t s_irq_sequence;
static uint64_t s_next_tick;

static uint32_t rs_read32(uint32_t address) {
    return *(volatile const uint32_t *)(uintptr_t)address;
}

static void rs_write32(uint32_t address, uint32_t value) {
    *(volatile uint32_t *)(uintptr_t)address = value;
}

static uint64_t rs_time(void) {
    uint32_t high;
    uint32_t low;
    do {
        high = rs_read32(RS_RTT_CLINT + UINT32_C(0xBFFC));
        low = rs_read32(RS_RTT_CLINT + UINT32_C(0xBFF8));
    } while (high != rs_read32(RS_RTT_CLINT + UINT32_C(0xBFFC)));
    return ((uint64_t)high << 32U) | low;
}

static void rs_set_timer(uint64_t value) {
    rs_write32(RS_RTT_CLINT + UINT32_C(0x4008), UINT32_MAX);
    rs_write32(RS_RTT_CLINT + UINT32_C(0x400C), (uint32_t)(value >> 32U));
    rs_write32(RS_RTT_CLINT + UINT32_C(0x4008), (uint32_t)value);
    __asm__ volatile("fence iorw, iorw" ::: "memory");
}

void rt_hw_console_output(const char *text) {
    while (*text != '\0') {
        uint32_t budget = UINT32_C(1000000);
        while ((rs_read32(RS_RTT_UART + UINT32_C(0x18)) & UINT32_C(0x20)) != 0U) {
            if (--budget == 0U) {
                (void)rt_hw_interrupt_disable();
                rs_rtt_publish(3U, 90U, 2U);
                /* Keep the failure publication stable until LP terminates. */
                for (;;) {
                    __asm__ volatile("wfi");
                }
            }
        }
        rs_write32(RS_RTT_UART + UINT32_C(0x10), (uint8_t)*text);
        ++text;
    }
}

void rs_rtt_publish(uint32_t event, uint32_t argument, uint32_t sequence) {
    rs_write32(RS_RTT_MAILBOX + UINT32_C(0x20), event);
    rs_write32(RS_RTT_MAILBOX + UINT32_C(0x24), argument);
    rs_write32(RS_RTT_MAILBOX + UINT32_C(0x28), sequence);
    __asm__ volatile("fence iorw, iorw" ::: "memory");
    rs_write32(RS_RTT_MAILBOX + UINT32_C(0x2C), 1U);
}

void rs_rtt_fail(uint32_t code) {
    (void)rt_hw_interrupt_disable();
    rt_kprintf("RTTHREAD_TEST_FAIL code=%u\n", code);
    rs_rtt_publish(3U, code, 2U);
    for (;;) {
        __asm__ volatile("wfi");
    }
}

static void rs_assert(const char *expression, const char *function, rt_size_t line) {
    (void)expression;
    (void)function;
    (void)line;
    rs_rtt_fail(91U);
}

void rt_trigger_software_interrupt(void) {
    rs_write32(RS_RTT_CLINT + UINT32_C(4), 1U);
}

void rt_hw_do_after_save_above(void) {
    rs_write32(RS_RTT_CLINT + UINT32_C(4), 0U);
}

void handle_trap(rt_ubase_t cause, rt_ubase_t epc, void *frame) {
    (void)frame;
    if ((cause >> 63U) == 0U) {
        rt_kprintf("RTTHREAD_TRAP cause=%lx epc=%lx\n", cause, epc);
        rs_rtt_fail(92U);
    }
    switch (cause & UINT64_C(0x7FFFFFFFFFFFFFFF)) {
    case 3U:
        rt_hw_do_after_save_above();
        break;
    case 7U:
        s_next_tick += UINT64_C(1000);
        if (s_next_tick <= rs_time()) {
            s_next_tick = rs_time() + UINT64_C(1000);
        }
        rs_set_timer(s_next_tick);
        rt_tick_increase();
        break;
    case 11U: {
        uint32_t claim = rs_read32(RS_RTT_PLIC + UINT32_C(0x200004));
        if (claim != 2U) {
            rs_rtt_fail(93U);
        }
        s_irq_command = rs_read32(RS_RTT_MAILBOX + UINT32_C(0x10));
        s_irq_argument = rs_read32(RS_RTT_MAILBOX + UINT32_C(0x14));
        s_irq_sequence = rs_read32(RS_RTT_MAILBOX + UINT32_C(0x18));
        rs_write32(RS_RTT_MAILBOX + UINT32_C(0x40), 1U);
        __asm__ volatile("fence iorw, iorw" ::: "memory");
        rs_write32(RS_RTT_PLIC + UINT32_C(0x200004), claim);
        if (rt_sem_release(&s_mailbox_sem) != RT_EOK) {
            rs_rtt_fail(94U);
        }
        break;
    }
    default:
        rs_rtt_fail(95U);
        break;
    }
}

rt_err_t rs_rtt_wait_mailbox(rt_int32_t timeout) {
    rt_err_t result = rt_sem_take(&s_mailbox_sem, timeout);
    if (result != RT_EOK) {
        return result;
    }
    return ((s_irq_command == RS_HP_RTTHREAD_IRQ_COMMAND) &&
            (s_irq_argument == RS_HP_RTTHREAD_IRQ_ARG) && (s_irq_sequence == 1U))
               ? RT_EOK
               : -RT_ERROR;
}

void rt_hw_board_init(void) {
    rs_write32(RS_RTT_UART + UINT32_C(0x0C), 0U);
    rs_write32(RS_RTT_UART + UINT32_C(0x20), 3U);
    rs_write32(RS_RTT_UART + UINT32_C(0x30), UINT32_C(0x7F));
    rs_write32(RS_RTT_UART + UINT32_C(0x38), 0U);
    rs_write32(RS_RTT_UART, 78U);
    rs_write32(RS_RTT_UART + UINT32_C(4), 32U);
    rs_write32(RS_RTT_UART + UINT32_C(8), 3U);
    rs_write32(RS_RTT_UART + UINT32_C(0x0C), 3U);
    rs_write32(RS_RTT_CLINT + UINT32_C(4), 0U);
    rs_write32(RS_RTT_MAILBOX + UINT32_C(0x40), 1U);
    rs_write32(RS_RTT_MAILBOX + UINT32_C(0x44), 1U);
    rs_write32(RS_RTT_PLIC + UINT32_C(8), 1U);
    rs_write32(RS_RTT_PLIC + UINT32_C(0x2000), 4U);
    rs_write32(RS_RTT_PLIC + UINT32_C(0x200000), 0U);
    s_next_tick = rs_time() + UINT64_C(1000);
    rs_set_timer(s_next_tick);
    __asm__ volatile("csrw mie, %0" : : "r"(UINT64_C(0x888)) : "memory");
}

void rt_hw_cpu_shutdown(void) {
    rs_rtt_fail(96U);
}

void rs_rtt_start(void) {
    uint64_t hart;
    _Static_assert(sizeof(rt_ubase_t) == 8U, "RT-Thread must use RV64 contexts");
    _Static_assert(IDLE_THREAD_STACK_SIZE >= 1024, "Idle stack must fit RV64+D frame and calls");
    __asm__ volatile("csrr %0, mhartid" : "=r"(hart));
    rt_assert_set_hook(rs_assert);
    rt_system_timer_init();
    rt_system_scheduler_init();
    if ((hart != 1U) || (rt_sem_init(&s_mailbox_sem, "hp_irq", 0U, RT_IPC_FLAG_FIFO) != RT_EOK)) {
        rs_rtt_fail(97U);
    }
    rt_hw_board_init();
    rt_show_version();
    rt_kprintf("HP_RTTHREAD_BOOT hart=1 xlen=64 mode=M\n");
    rs_rtt_selftest_init();
    rt_thread_idle_init();
    rt_system_scheduler_start();
    rs_rtt_fail(98U);
}
