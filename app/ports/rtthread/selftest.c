#include "board.h"
#include "hp_boot_bundle.h"

#include <rthw.h>

static struct rt_thread s_controller;
static struct rt_thread s_producer;
static struct rt_thread s_consumer;
static struct rt_semaphore s_done;
static struct rt_messagequeue s_queue;
static uint8_t s_controller_stack[4096] __attribute__((aligned(16)));
static uint8_t s_producer_stack[4096] __attribute__((aligned(16)));
static uint8_t s_consumer_stack[4096] __attribute__((aligned(16)));
static uint8_t s_queue_pool[128] __attribute__((aligned(16)));
static volatile uint32_t s_busy_iterations;
static volatile uint32_t s_preempted;
static volatile uint64_t s_memory_probe;

static void rs_require(bool condition, uint32_t code) {
    if (!condition) {
        rs_rtt_fail(code);
    }
}

static void rs_producer(void *argument) {
    rt_tick_t start = rt_tick_get();
    (void)argument;
    while (s_preempted == 0U) {
        ++s_busy_iterations;
        rs_require((rt_tick_get() - start) < 100U, 10U);
    }
    rs_require(rs_rtt_context_probe(UINT64_C(0xFEDCBA9876543210)) == 0U, 11U);
    for (uint64_t index = 0U; index < 8U; ++index) {
        uint64_t value = UINT64_C(0x1234567800000000) | index;
        rs_require(rt_mq_send_wait(&s_queue, &value, sizeof(value), 100) == RT_EOK, 12U);
    }
    rs_require(rt_sem_release(&s_done) == RT_EOK, 13U);
}

static void rs_consumer(void *argument) {
    (void)argument;
    rs_require(rt_thread_delay(2) == RT_EOK, 20U);
    rs_require(s_busy_iterations != 0U, 21U);
    s_preempted = 1U;
    rs_require(rs_rtt_context_probe(UINT64_C(0x13579BDF2468ACE0)) == 0U, 22U);
    for (uint64_t index = 0U; index < 8U; ++index) {
        uint64_t value = 0U;
        rs_require(rt_mq_recv(&s_queue, &value, sizeof(value), 100) == (rt_ssize_t)sizeof(value),
                   23U);
        rs_require(value == (UINT64_C(0x1234567800000000) | index), 24U);
    }
    rs_require(rt_sem_release(&s_done) == RT_EOK, 25U);
}

static void rs_controller(void *argument) {
    uint64_t input = UINT64_C(0x123456789ABCDEF0);
    uint64_t value = 0U;
    rt_tick_t start;
    (void)argument;
    s_memory_probe = input;
    rs_require(((s_memory_probe >> 32U) == UINT64_C(0x12345678)) &&
                   ((s_memory_probe * 3U) / 3U == input),
               1U);
    rt_kprintf("RTTHREAD_RV64_PASS\n");
    rs_require(rt_sem_init(&s_done, "done", 0U, RT_IPC_FLAG_FIFO) == RT_EOK, 2U);
    rs_require(rt_mq_init(&s_queue, "mq", s_queue_pool, sizeof(value), sizeof(s_queue_pool),
                          RT_IPC_FLAG_FIFO) == RT_EOK,
               3U);
    start = rt_tick_get();
    rs_require(rt_sem_take(&s_done, 2) == -RT_ETIMEOUT, 4U);
    rs_require((rt_tick_get() - start) >= 2U, 5U);
    rs_require(rt_mq_recv(&s_queue, &value, sizeof(value), 2) == -RT_ETIMEOUT, 6U);
    rt_kprintf("RTTHREAD_TIMEOUT_PASS\n");
    rs_require(rt_thread_startup(&s_consumer) == RT_EOK, 7U);
    rs_require(rt_thread_startup(&s_producer) == RT_EOK, 8U);
    rs_require(rt_sem_take(&s_done, 200) == RT_EOK, 30U);
    rs_require(rt_sem_take(&s_done, 200) == RT_EOK, 31U);
    rs_require(s_preempted == 1U, 32U);
    rt_kprintf("RTTHREAD_PREEMPT_PASS\nRTTHREAD_CONTEXT_PASS\nRTTHREAD_IPC_PASS\n");
    rs_rtt_publish(1U, RS_HP_RTTHREAD_READY_ARG, 1U);
    rs_require(rs_rtt_wait_mailbox(1000) == RT_EOK, 33U);
    rt_kprintf("RTTHREAD_MAILBOX_IRQ_PASS\nRTTHREAD_TEST_PASS\n");
    rs_rtt_publish(2U, RS_HP_RTTHREAD_READY_ARG, 2U);
    for (;;) {
        (void)rt_thread_delay(100);
    }
}

void rs_rtt_selftest_init(void) {
    rs_require(rt_thread_init(&s_controller, "test", rs_controller, RT_NULL, s_controller_stack,
                              sizeof(s_controller_stack), 5U, 1U) == RT_EOK,
               40U);
    rs_require(rt_thread_init(&s_consumer, "recv", rs_consumer, RT_NULL, s_consumer_stack,
                              sizeof(s_consumer_stack), 10U, 1U) == RT_EOK,
               41U);
    rs_require(rt_thread_init(&s_producer, "send", rs_producer, RT_NULL, s_producer_stack,
                              sizeof(s_producer_stack), 20U, 1U) == RT_EOK,
               42U);
    rs_require(rt_thread_startup(&s_controller) == RT_EOK, 43U);
}
