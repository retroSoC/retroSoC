/*
 * Copyright (c) 2019 Nuclei Limited. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Licensed under the Apache License, Version 2.0 (the License); you may
 * not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an AS IS BASIS, WITHOUT
 * WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
// -- Adaptable modifications are redistributed under compatible License --
//
// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

#include <stdint.h>
#include <system_csr.h>
#include <tinyprintf.h>

#define SYSTEM_EXC_MAX_NUM      16
#define SYSTEM_IRQ_CORE_MAX_NUM 12
#define SYSTEM_IRQ_EXTN_MAX_NUM 30

static unsigned long SystemEXCHandlers[SYSTEM_EXC_MAX_NUM];
static unsigned long SystemIRQCoreHandlers[SYSTEM_IRQ_CORE_MAX_NUM];
static unsigned long SystemIRQExtnHandlers[SYSTEM_IRQ_EXTN_MAX_NUM];


typedef void (*EXC_HANDLER) (unsigned long mcause, unsigned long sp);
typedef void (*IRQ_HANDLER) (unsigned long mcause, unsigned long sp);


static void system_default_exc_handler(unsigned long mcause, unsigned long sp) {
    printf("Trap in Exception\r\n");
    printf("sp: 0x%x\r\n", sp);
    printf("mcause: 0x%x\r\n", mcause);
    // printf("mepc  : 0x%x\r\n", _READ_CSR(CSR_MEPC));
    // printf("mtval : 0x%x\r\n", _READ_CSR(CSR_MBADADDR));
    while(1);
}


static void system_default_irq_handler(unsigned long mcause, unsigned long sp) {
    printf("Trap in Interrupt\r\n");
    printf("sp: 0x%x\r\n", sp);
    printf("mcause: 0x%x\r\n", mcause);
    // printf("mepc  : 0x%x\r\n", _READ_CSR(CSR_MEPC));
    // printf("mtval : 0x%x\r\n", _READ_CSR(CSR_MBADADDR));
}


static void init_system_exception(void) {
    for (int i = 0; i < SYSTEM_EXC_MAX_NUM; i++) {
        SystemEXCHandlers[i] = (unsigned long)system_default_exc_handler;
    }
}


static void init_system_irq(void) {
    for (int i = 0; i < SYSTEM_IRQ_CORE_MAX_NUM; i++) {
        SystemIRQCoreHandlers[i] = (unsigned long)system_default_irq_handler;
    }

    for (int i = 0; i < SYSTEM_IRQ_EXTN_MAX_NUM; i++) {
        SystemIRQExtnHandlers[i] = (unsigned long)system_default_irq_handler;
    }
}


void register_system_exception(uint32_t id, unsigned long exc_handler) {
    if (id < SYSTEM_EXC_MAX_NUM) {
        SystemEXCHandlers[id] = exc_handler;
    }
}


void register_system_core_irq(uint32_t id, unsigned long irq_handler) {
    if (id <= SYSTEM_IRQ_CORE_MAX_NUM) {
        SystemIRQCoreHandlers[id] = irq_handler;
    }
}


void register_system_extn_irq(uint32_t id, unsigned long irq_handler) {
    if (id <= SYSTEM_IRQ_EXTN_MAX_NUM) {
        SystemIRQExtnHandlers[id] = irq_handler;
    }
}


unsigned long get_system_exception(uint32_t id) {
    if (id < SYSTEM_EXC_MAX_NUM) {
        return SystemEXCHandlers[id];
    }
    return 0;
}


unsigned long get_system_core_irq(uint32_t id) {
    if (id <= SYSTEM_IRQ_CORE_MAX_NUM) {
        return SystemIRQCoreHandlers[id];
    }
    return 0;
}


unsigned long get_system_extn_irq(uint32_t id) {
    if (id <= SYSTEM_IRQ_EXTN_MAX_NUM) {
        return SystemIRQExtnHandlers[id];
    }
    return 0;
}


uint32_t system_trap_handler(unsigned long mcause, unsigned long sp) {
    if (mcause & MCAUSE_INTERRUPT) {
        IRQ_HANDLER irq_handler = NULL;
        uint32_t id = (uint32_t)(mcause & 0X00000fff);
        if (id == IRQ_M_EXT) {
            printf("extn irq trigger!\n");
        } else {
            irq_handler = (IRQ_HANDLER)get_system_core_irq(id);
            if (irq_handler != NULL) irq_handler(mcause, sp);
        }
        return 0;
    } else {
        EXC_HANDLER exc_handler;
        uint32_t id = (uint32_t)(mcause & 0X00000fff);
        exc_handler = (EXC_HANDLER)get_system_exception(id);
        if (exc_handler != NULL) exc_handler(mcause, sp);
        return 0;
    }
}

// int32_t Core_Register_IRQ(uint32_t id, void *handler)
// {
//     if ((id > 10)) {
//         return -1;
//     }

//     if (handler != NULL) {
//         /* register interrupt handler entry to core handlers */
//         register_system_core_irq(id, (unsigned long)handler);
//     }
//     switch (id) {
//         case SysTimerSW_IRQn:
//             __enable_sw_irq();
//             break;
//         case SysTimer_IRQn:
//             __enable_timer_irq();
//             break;
//         default:
//             break;
//     }

//     return 0;
// }


void _premain_init(void) {
    // gpio_iof_config(GPIOA, IOF_UART_MASK);
    // uart_init(SOC_DEBUG_UART, 115200);

    /* Initialize exception default handlers */
    init_system_exception();
    /* Initialize Interrupt default handlers */
    init_system_irq();
}