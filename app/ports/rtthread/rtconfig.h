#ifndef RETROSOC_RTTHREAD_CONFIG_H
#define RETROSOC_RTTHREAD_CONFIG_H

#define ARCH_CPU_64BIT
#define RT_CPUS_NR             1
#define RT_NAME_MAX            12
#define RT_ALIGN_SIZE          16
#define RT_THREAD_PRIORITY_MAX 32
#define RT_TICK_PER_SECOND     1000
#define RT_USING_OVERFLOW_CHECK
#define RT_DEBUG
#define RT_DEBUGING_ASSERT
#define RT_BACKTRACE_LEVEL_MAX_NR 32
#define RT_USING_SEMAPHORE
#define RT_USING_MESSAGEQUEUE
#define RT_USING_CONSOLE
#define RT_CONSOLEBUF_SIZE     256
#define IDLE_THREAD_STACK_SIZE 2048
#define RT_KLIBC_USING_VSNPRINTF_LONGLONG
/* No scanf caller is linked; avoid the heap-dependent internal scanner. */
#define RT_KLIBC_USING_LIBC_VSSCANF

#endif
