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

#ifndef __SYSTEM_CSR_H__
#define __SYSTEM_CSR_H__

#include <system_bit.h>

#define MSTATUS_UIE         0x00000001
#define MSTATUS_SIE         0x00000002
#define MSTATUS_HIE         0x00000004
#define MSTATUS_MIE         0x00000008
#define MSTATUS_UPIE        0x00000010
#define MSTATUS_SPIE        0x00000020
#define MSTATUS_HPIE        0x00000040
#define MSTATUS_MPIE        0x00000080
#define MSTATUS_SPP         0x00000100
#define MSTATUS_MPP         0x00001800
#define MSTATUS_FS          0x00006000
#define MSTATUS_XS          0x00018000
#define MSTATUS_MPRV        0x00020000
#define MSTATUS_PUM         0x00040000
#define MSTATUS_MXR         0x00080000
#define MSTATUS_VM          0x1F000000
#define MSTATUS32_SD        0x80000000
#define MSTATUS64_SD        0x8000000000000000

#define MSTATUS_FS_INITIAL  0x00002000
#define MSTATUS_FS_CLEAN    0x00004000
#define MSTATUS_FS_DIRTY    0x00006000

#define SSTATUS_UIE         0x00000001
#define SSTATUS_SIE         0x00000002
#define SSTATUS_UPIE        0x00000010
#define SSTATUS_SPIE        0x00000020
#define SSTATUS_SPP         0x00000100
#define SSTATUS_FS          0x00006000
#define SSTATUS_XS          0x00018000
#define SSTATUS_PUM         0x00040000
#define SSTATUS32_SD        0x80000000
#define SSTATUS64_SD        0x8000000000000000


#define MCAUSE_INTERRUPT        (1ULL<<((__riscv_xlen)-1))

#define MIP_SSIP                (1 << IRQ_S_SOFT)
#define MIP_HSIP                (1 << IRQ_H_SOFT)
#define MIP_MSIP                (1 << IRQ_M_SOFT)
#define MIP_STIP                (1 << IRQ_S_TIMER)
#define MIP_HTIP                (1 << IRQ_H_TIMER)
#define MIP_MTIP                (1 << IRQ_M_TIMER)
#define MIP_SEIP                (1 << IRQ_S_EXT)
#define MIP_HEIP                (1 << IRQ_H_EXT)
#define MIP_MEIP                (1 << IRQ_M_EXT)

#define MIE_SSIE                MIP_SSIP
#define MIE_HSIE                MIP_HSIP
#define MIE_MSIE                MIP_MSIP
#define MIE_STIE                MIP_STIP
#define MIE_HTIE                MIP_HTIP
#define MIE_MTIE                MIP_MTIP
#define MIE_SEIE                MIP_SEIP
#define MIE_HEIE                MIP_HEIP
#define MIE_MEIE                MIP_MEIP

#define WFE_WFE                 0x1

#define MCOUNTINHIBIT_IR        (1<<2)
#define MCOUNTINHIBIT_CY        (1<<0)

#define MMISC_CTL_NMI_CAUSE_FFF (1<<9)
#define MMISC_CTL_MISALIGN      (1<<6)
#define MMISC_CTL_BPU           (1<<3)

#define SIP_SSIP MIP_SSIP
#define SIP_STIP MIP_STIP

#define PRV_U        0
#define PRV_S        1
#define PRV_H        2
#define PRV_M        3

#define VM_MBARE     0
#define VM_MBB       1
#define VM_MBBID     2
#define VM_SV32      8
#define VM_SV39      9
#define VM_SV48      10

#define IRQ_S_SOFT   1
#define IRQ_H_SOFT   2
#define IRQ_M_SOFT   3
#define IRQ_S_TIMER  5
#define IRQ_H_TIMER  6
#define IRQ_M_TIMER  7
#define IRQ_S_EXT    9
#define IRQ_H_EXT    10
#define IRQ_M_EXT    11
#define IRQ_COP      12
#define IRQ_HOST     13

/* === FPU FRM Rounding Mode === */
/** FPU Round to Nearest, ties to Even*/
#define FRM_RNDMODE_RNE     0x0
/** FPU Round Towards Zero */
#define FRM_RNDMODE_RTZ     0x1
/** FPU Round Down (towards -inf) */
#define FRM_RNDMODE_RDN     0x2
/** FPU Round Up (towards +inf) */
#define FRM_RNDMODE_RUP     0x3
/** FPU Round to nearest, ties to Max Magnitude */
#define FRM_RNDMODE_RMM     0x4
/**
 * In instruction's rm, selects dynamic rounding mode.
 * In Rounding Mode register, Invalid */
#define FRM_RNDMODE_DYN     0x7

/* === FPU FFLAGS Accrued Exceptions === */
/** FPU Inexact */
#define FFLAGS_AE_NX        (1<<0)
/** FPU Underflow */
#define FFLAGS_AE_UF        (1<<1)
/** FPU Overflow */
#define FFLAGS_AE_OF        (1<<2)
/** FPU Divide by Zero */
#define FFLAGS_AE_DZ        (1<<3)
/** FPU Invalid Operation */
#define FFLAGS_AE_NV        (1<<4)
/** Floating Point Register f0-f31, eg. f0 -> FREG(0) */
#define FREG(idx)           f##idx


#ifdef __riscv

#ifdef __riscv64
# define MSTATUS_SD MSTATUS64_SD
# define SSTATUS_SD SSTATUS64_SD
# define RISCV_PGLEVEL_BITS 9
#else
# define MSTATUS_SD MSTATUS32_SD
# define SSTATUS_SD SSTATUS32_SD
# define RISCV_PGLEVEL_BITS 10
#endif /* __riscv64 */

#define RISCV_PGSHIFT 12
#define RISCV_PGSIZE (1 << RISCV_PGSHIFT)

#endif

/* === Standard RISC-V CSR Registers === */
#define CSR_USTATUS	    0x0
#define CSR_FFLAGS      0x1
#define CSR_FRM         0x2
#define CSR_FCSR        0x3
#define CSR_CYCLE       0xc00
#define CSR_TIME        0xc01
#define CSR_INSTRET     0xc02
#define CSR_SSTATUS     0x100
#define CSR_SIE         0x104
#define CSR_STVEC       0x105
#define CSR_SSCRATCH    0x140
#define CSR_SEPC        0x141
#define CSR_SCAUSE      0x142
#define CSR_SBADADDR    0x143
#define CSR_SIP         0x144
#define CSR_SPTBR       0x180
#define CSR_MSTATUS     0x300
#define CSR_MISA        0x301
#define CSR_MEDELEG     0x302
#define CSR_MIDELEG     0x303
#define CSR_MIE         0x304
#define CSR_MTVEC       0x305
#define CSR_MCOUNTEREN  0x306
#define CSR_MSCRATCH    0x340
#define CSR_MEPC        0x341
#define CSR_MCAUSE      0x342
#define CSR_MBADADDR    0x343
#define CSR_MIP         0x344
#define CSR_MCYCLE      0xb00
#define CSR_MINSTRET    0xb02
#define CSR_MUCOUNTEREN 0x320
#define CSR_MSCOUNTEREN 0x321

#define CSR_MVENDORID     0xf11
#define CSR_MARCHID       0xf12
#define CSR_MIMPID        0xf13
#define CSR_MHARTID       0xf14
#define CSR_CYCLEH        0xc80
#define CSR_TIMEH         0xc81
#define CSR_INSTRETH      0xc82
#define CSR_MCYCLEH       0xb80
#define CSR_MINSTRETH     0xb82

/* Exception Code in MCAUSE CSR */
#define CAUSE_MISALIGNED_FETCH    0x0
#define CAUSE_FAULT_FETCH         0x1
#define CAUSE_ILLEGAL_INSTRUCTION 0x2
#define CAUSE_BREAKPOINT          0x3
#define CAUSE_MISALIGNED_LOAD     0x4
#define CAUSE_FAULT_LOAD          0x5
#define CAUSE_MISALIGNED_STORE    0x6
#define CAUSE_FAULT_STORE         0x7
#define CAUSE_USER_ECALL          0x8
#define CAUSE_SUPERVISOR_ECALL    0x9
#define CAUSE_HYPERVISOR_ECALL    0xa
#define CAUSE_MACHINE_ECALL       0xb

#endif