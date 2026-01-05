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

#ifndef __SYSTEM_TIMER_H__
#define __SYSTEM_TIMER_H__

#include <system_gcc.h>

typedef struct {
    __IOM uint32_t clkdiv;
    __IOM uint64_t mtime;
    __IOM uint64_t mtimecmp;
    __IOM uint32_t msip;
} SysTimer_Type;


/* Timer Control / Status Register Definitions */
#define SysTimer_MSIP_MSIP_POS              0U                                          /*!< SysTick Timer msip: msip bit Position */
#define SysTimer_MSIP_MSIP_MASK             (1UL << SysTimer_MSIP_MSIP_POS)             /*!< SysTick Timer msip: msip Mask */

#define SysTimer_MTIMER_MASK                (0xFFFFFFFFFFFFFFFFULL)                     /*!< SysTick Timer MTIMER value Mask */
#define SysTimer_MTIMERCMP_MASK             (0xFFFFFFFFFFFFFFFFULL)                     /*!< SysTick Timer MTIMERCMP value Mask */
#define SysTimer_MSIP_MASK                  (0xFFFFFFFFUL)                              /*!< SysTick Timer msip   value Mask */

#define __SYSTIMER_BASEADDR                 0x1000C000
#ifndef __SYSTIMER_BASEADDR
/* Base address of SYSTIMER(__SYSTIMER_BASEADDR) should be defined in <Device.h> */
#error "__SYSTIMER_BASEADDR is not defined, please check!"
#endif
/* System Timer Memory mapping of Device */
#define SysTimer_BASE                       __SYSTIMER_BASEADDR                         /*!< SysTick Base Address */
#define SysTimer                            ((SysTimer_Type *) SysTimer_BASE)           /*!< SysTick configuration struct */


/**
 * \defgroup NMSIS_Core_SysTimer SysTimer Functions
 * \brief    Functions that configure the Core System Timer.
 * @{
 */
/**
 * \brief  Set system timer load value
 * \details
 * This function set the system timer load value in MTIMER register.
 * \param [in]  value   value to set system timer MTIMER register.
 * \remarks
 * - Load value is 64bits wide.
 * - \ref SysTimer_GetLoadValue
 */
__STATIC_FORCEINLINE void SysTimer_SetMtimeValue(uint64_t value) {
    SysTimer->mtime = value;
}

/**
 * \brief  Get system timer load value
 * \details
 * This function get the system timer current value in MTIMER register.
 * \return  current value(64bit) of system timer MTIMER register.
 * \remarks
 * - Load value is 64bits wide.
 * - \ref SysTimer_SetLoadValue
 */
__STATIC_FORCEINLINE uint64_t SysTimer_GetMtimeValue(void) {
    return SysTimer->mtime;
}

/**
 * \brief  Set system timer compare value
 * \details
 * This function set the system Timer compare value in MTIMERCMP register.
 * \param [in]  value   compare value to set system timer MTIMERCMP register.
 * \remarks
 * - Compare value is 64bits wide.
 * - If compare value is larger than current value timer interrupt generate.
 * - Modify the load value or compare value less to clear the interrupt.
 * - \ref SysTimer_GetCompareValue
 */
__STATIC_FORCEINLINE void SysTimer_SetMtimecmpValue(uint64_t value) {
    SysTimer->mtimecmp = value;
}

/**
 * \brief  Get system timer compare value
 * \details
 * This function get the system timer compare value in MTIMERCMP register.
 * \return  compare value of system timer MTIMERCMP register.
 * \remarks
 * - Compare value is 64bits wide.
 * - \ref SysTimer_SetCompareValue
 */
__STATIC_FORCEINLINE uint64_t SysTimer_GetMtimecmpValue(void) {
    return SysTimer->mtimecmp;
}

/**
 * \brief  Trigger or set software interrupt via system timer
 * \details
 * This function set the system timer MSIP bit in MSIP register.
 * \remarks
 * - Set system timer MSIP bit and generate a SW interrupt.
 * - \ref SysTimer_ClearSWIRQ
 * - \ref SysTimer_GetMsipValue
 */
__STATIC_FORCEINLINE void SysTimer_SetSoftwareIRQ(void) {
    SysTimer->msip |= SysTimer_MSIP_MSIP_MASK;
}

/**
 * \brief  Clear system timer software interrupt pending request
 * \details
 * This function clear the system timer MSIP bit in MSIP register.
 * \remarks
 * - Clear system timer MSIP bit in MSIP register to clear the software interrupt pending.
 * - \ref SysTimer_SetSWIRQ
 * - \ref SysTimer_GetMsipValue
 */
__STATIC_FORCEINLINE void SysTimer_ClearSoftwareIRQ(void) {
    SysTimer->msip &= ~SysTimer_MSIP_MSIP_MASK;
}

/**
 * \brief  Get system timer MSIP register value
 * \details
 * This function get the system timer MSIP register value.
 * \return    Value of Timer MSIP register.
 * \remarks
 * - Bit0 is SW interrupt flag.
 *   Bit0 is 1 then SW interrupt set. Bit0 is 0 then SW interrupt clear.
 * - \ref SysTimer_SetSWIRQ
 * - \ref SysTimer_ClearSWIRQ
 */
__STATIC_FORCEINLINE uint32_t SysTimer_GetMsipValue(void) {
    return (uint32_t)(SysTimer->msip & SysTimer_MSIP_MASK);
}

/**
 * \brief  Set system timer MSIP register value
 * \details
 * This function set the system timer MSIP register value.
 * \param [in]  msip   value to set MSIP register
 */
__STATIC_FORCEINLINE void SysTimer_SetMsipValue(uint32_t msip) {
    SysTimer->msip = (msip & SysTimer_MSIP_MASK);
}

/**
 * \brief   System Tick Configuration
 * \details Initializes the System Timer and its non-vector interrupt, and starts the System Tick Timer.
 *
 *  In our default implementation, the timer counter will be set to zero, and it will start a timer compare non-vector interrupt
 *  when it matchs the ticks user set, during the timer interrupt user should reload the system tick using \ref SysTick_Reload function
 *  or similar function written by user, so it can produce period timer interrupt.
 * \param [in]  ticks  Number of ticks between two interrupts.
 * \return          0  Function succeeded.
 * \return          1  Function failed.
 * \sa
 * - \ref SysTimer_SetCompareValue; SysTimer_SetLoadValue
 */
__STATIC_INLINE uint32_t SysTick_Config(uint64_t ticks) {
    SysTimer_SetMtimeValue(0);
    SysTimer_SetMtimecmpValue(ticks);
    __enable_timer_irq();
    return (0UL);
}

/**
 * \brief   System Tick Reload
 * \details Reload the System Timer Tick when the MTIMECMP reached TIME value
 *
 * \param [in]  ticks  Number of ticks between two interrupts.
 * \return          0  Function succeeded.
 * \return          1  Function failed.
 * \sa
 * - \ref SysTimer_SetCompareValue
 * - \ref SysTimer_SetLoadValue
 */
__STATIC_FORCEINLINE uint32_t SysTick_Reload(uint64_t ticks) {
    uint64_t cur_ticks = SysTimer->mtime;
    uint64_t reload_ticks = ticks + cur_ticks;

    if (__USUALLY(reload_ticks > cur_ticks)) {
        SysTimer->mtimecmp = reload_ticks;
    } else {
        /* When added the ticks value, then the MTIMERCMP < TIMER,
         * which means the MTIMERCMP is overflowed,
         * so we need to reset the counter to zero */
        SysTimer->mtime = 0;
        SysTimer->mtimecmp = ticks;
    }

    return (0UL);
}

#endif
