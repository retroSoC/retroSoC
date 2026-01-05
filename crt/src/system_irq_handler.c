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
#include <system_base.h>
#include <tinyprintf.h>

#define SYSTEM_EXC_MAX_NUM      16
#define SYSTEM_IRQ_CORE_MAX_NUM 12
#define SYSTEM_IRQ_EXTN_MAX_NUM 30

static unsigned long SystemEXCHandlers[SYSTEM_EXC_MAX_NUM];
static unsigned long SystemIRQCoreHandlers[SYSTEM_IRQ_CORE_MAX_NUM];
static unsigned long SystemIRQExtnHandlers[SYSTEM_IRQ_EXTN_MAX_NUM];


typedef void (*EXC_HANDLER) (unsigned long mcause, unsigned long sp);
typedef void (*IRQ_HANDLER) (unsigned long mcause, unsigned long sp);

/**
 * \brief      System Default Exception Handler
 * \details
 * This function provided a default exception handling code for all exception ids.
 * By default, It will just print some information for debug, Vendor can customize it according to its requirements.
 */
static void system_default_exc_handler(unsigned long mcause, unsigned long sp) {
    printf("Trap in Exception\r\n");
    printf("sp: 0x%x\r\n", sp);
    printf("mcause: 0x%x\r\n", mcause);
    // printf("mepc  : 0x%x\r\n", _READ_CSR(CSR_MEPC));
    // printf("mtval : 0x%x\r\n", _READ_CSR(CSR_MBADADDR));
    while(1);
}

/**
 * \brief      System Default Interrupt Handler
 * \details
 * This function provided a default interrupt handling code for all interrupt ids.
 */
static void system_default_irq_handler(unsigned long mcause, unsigned long sp) {
    printf("Trap in Interrupt\r\n");
    printf("sp: 0x%x\r\n", sp);
    printf("mcause: 0x%x\r\n", mcause);
    // printf("mepc  : 0x%x\r\n", _READ_CSR(CSR_MEPC));
    // printf("mtval : 0x%x\r\n", _READ_CSR(CSR_MBADADDR));
}

/**
 * \brief      Initialize all the default core exception handlers
 * \details
 * The core exception handler for each exception id will be initialized to \ref system_default_exception_handler.
 * \note
 * Called in \ref _init function, used to initialize default exception handlers for all exception IDs
 */
static void init_system_exception(void) {
    for (int i = 0; i < SYSTEM_EXC_MAX_NUM; i++) {
        SystemEXCHandlers[i] = (unsigned long)system_default_exc_handler;
    }
}

/**
 * \brief      Initialize all the default interrupt handlers
 * \details
 * The interrupt handler for each exception id will be initialized to \ref system_default_interrupt_handler.
 * \note
 * Called in \ref _init function, used to initialize default interrupt handlers for all interrupt IDs
 */
static void init_system_irq(void) {
    for (int i = 0; i < SYSTEM_IRQ_CORE_MAX_NUM; i++) {
        SystemIRQCoreHandlers[i] = (unsigned long)system_default_irq_handler;
    }

    for (int i = 0; i < SYSTEM_IRQ_EXTN_MAX_NUM; i++) {
        SystemIRQExtnHandlers[i] = (unsigned long)system_default_irq_handler;
    }
}

/**
 * \brief       Register an exception handler for exception code EXCn
 * \details
 * * For EXCn < \ref MAX_SYSTEM_EXCEPTION_NUM, it will be registered into SystemExceptionHandlers[EXCn-1].
 * \param   EXCn    See \ref EXCn_Type
 * \param   exc_handler     The exception handler for this exception code EXCn
 */
void register_system_exception(uint32_t id, unsigned long exc_handler) {
    if (id < SYSTEM_EXC_MAX_NUM) {
        SystemEXCHandlers[id] = exc_handler;
    }
}

/**
 * \brief       Register an core interrupt handler for core interrupt number
 * \details
 * * For irqn <=  10, it will be registered into SystemCoreInterruptHandlers[irqn-1].
 * \param   irqn    See \ref IRQn
 * \param   int_handler     The core interrupt handler for this interrupt code irqn
 */
void register_system_core_irq(uint32_t id, unsigned long irq_handler) {
    if (id <= SYSTEM_IRQ_CORE_MAX_NUM) {
        SystemIRQCoreHandlers[id] = irq_handler;
    }
}

/**
 * \brief       Register an external interrupt handler for plic external interrupt number
 * \details
 * * For irqn <= \ref __PLIC_INTNUM, it will be registered into SystemExtInterruptHandlers[irqn-1].
 * \param   irqn    See \ref IRQn
 * \param   int_handler     The external interrupt handler for this interrupt code irqn
 */
void register_system_extn_irq(uint32_t id, unsigned long irq_handler) {
    if (id <= SYSTEM_IRQ_EXTN_MAX_NUM) {
        SystemIRQExtnHandlers[id] = irq_handler;
    }
}

/**
 * \brief       Get an core interrupt handler for core interrupt number
 * \param   irqn    See \ref IRQn
 * \return
 * The core interrupt handler for this interrupt code irqn
 */
unsigned long get_system_exception(uint32_t id) {
    if (id < SYSTEM_EXC_MAX_NUM) {
        return SystemEXCHandlers[id];
    }
    return 0;
}

/**
 * \brief       Get an external interrupt handler for external interrupt number
 * \param   irqn    See \ref IRQn
 * \return
 * The external interrupt handler for this interrupt code irqn
 */
unsigned long get_system_core_irq(uint32_t id) {
    if (id <= SYSTEM_IRQ_CORE_MAX_NUM) {
        return SystemIRQCoreHandlers[id];
    }
    return 0;
}

/**
 * \brief       Get current exception handler for exception code EXCn
 * \details
 * * For EXCn < \ref MAX_SYSTEM_EXCEPTION_NUM, it will return SystemExceptionHandlers[EXCn-1].
 * \param   EXCn    See \ref EXCn_Type
 * \return  Current exception handler for exception code EXCn, if not found, return 0.
 */
unsigned long get_system_extn_irq(uint32_t id) {
    if (id <= SYSTEM_IRQ_EXTN_MAX_NUM) {
        return SystemIRQExtnHandlers[id];
    }
    return 0;
}

/**
 * \brief      Common trap entry
 * \details
 * This function provided a command entry for trap. Silicon Vendor could modify
 * this template implementation according to requirement.
 * \remarks
 * - RISCV provided common entry for all types of exception including exception and interrupt.
 *   This is proposed code template for exception entry function, Silicon Vendor could modify the implementation.
 * - If you want to register core exception handler, please use \ref Exception_Register_EXC
 * - If you want to register core interrupt handler, please use \ref Interrupt_Register_CoreIRQ
 * - If you want to register external interrupt handler, please use \ref Interrupt_Register_ExtIRQ
 */
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

int32_t register_system_core_irq_factory(uint32_t id, void *handler)
{
    if (id > SYSTEM_IRQ_CORE_MAX_NUM) return -1;

    if (handler != NULL) {
        /* register interrupt handler entry to core handlers */
        register_system_core_irq(id, (unsigned long)handler);
    }
    switch (id) {
        case IRQ_M_SOFT:
            __enable_sw_irq();
            break;
        case IRQ_M_TIMER:
            __enable_timer_irq();
            break;
        default:
            break;
    }

    return 0;
}


void _premain_init(void) {
    // gpio_iof_config(GPIOA, IOF_UART_MASK);
    // uart_init(SOC_DEBUG_UART, 115200);
    /* Initialize exception default handlers */
    init_system_exception();
    /* Initialize Interrupt default handlers */
    init_system_irq();
}