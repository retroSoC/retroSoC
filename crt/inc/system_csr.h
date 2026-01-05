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

#if __riscv_xlen == 64
# define SLL32                  sllw
# define STORE                  sd
# define LOAD                   ld
# define LWU                    lwu
# define LOG_REGBYTES           3
#else
# define SLL32                  sll
# define STORE                  sw
# define LOAD                   lw
# define LWU                    lw
# define LOG_REGBYTES           2
#endif /* __riscv_xlen */

#define REGBYTES (1 << LOG_REGBYTES)

#define __rv_likely(x)          __builtin_expect((x), 1)
#define __rv_unlikely(x)        __builtin_expect((x), 0)

#define __RV_ROUNDUP(a, b)      ((((a)-1)/(b)+1)*(b))
#define __RV_ROUNDDOWN(a, b)    ((a)/(b)*(b))

#define __RV_MAX(a, b)          ((a) > (b) ? (a) : (b))
#define __RV_MIN(a, b)          ((a) < (b) ? (a) : (b))
#define __RV_CLAMP(a, lo, hi)   MIN(MAX(a, lo), hi)

#define __RV_EXTRACT_FIELD(val, which)                  (((val) & (which)) / ((which) & ~((which)-1)))
#define __RV_INSERT_FIELD(val, which, fieldval)         (((val) & ~(which)) | ((fieldval) * ((which) & ~((which)-1))))

#ifdef __ASSEMBLY__
#define _AC(X,Y)                X
#define _AT(T,X)                X
#else
#define __AC(X,Y)               (X##Y)
#define _AC(X,Y)                __AC(X,Y)
#define _AT(T,X)                ((T)(X))
#endif /* __ASSEMBLY__ */

#define _UL(x)                  (_AC(x, UL))
#define _ULL(x)                 (_AC(x, ULL))

#define _BITUL(x)               (_UL(1) << (x))
#define _BITULL(x)              (_ULL(1) << (x))

#define UL(x)                   (_UL(x))
#define ULL(x)                  (_ULL(x))

#define STR(x)                  XSTR(x)
#define XSTR(x)                 #x
#define __STR(s)                #s
#define STRINGIFY(s)            __STR(s)


#define _WRITE_CSR(name, data) ({ asm volatile ("csrw " #name ", %0" : : "r" (data)); })
#define _SET_CSR(name, data)   ({ asm volatile ("csrs " #name ", %0" : : "r" (data)); })
#define _CLEAR_CSR(name, data) ({ asm volatile ("csrc " #name ", %0" : : "r" (data)); })

#define _READ_CSR(name) ({ \
  uint32_t __csr_val_u32; \
  asm volatile ("csrr %0, " #name : "=r" (__csr_val_u32)); \
  __csr_val_u32; \
})

#define _RDWR_CSR(name, data) ({ \
  uint32_t __csr_val_u32; \
  asm volatile ("csrrw %0, " #name ", %1" : "=r" (__csr_val_u32) : "r" (data)); \
  __csr_val_u32; \
})

#define _RDSET_CSR(name, data) ({ \
  uint32_t __csr_val_u32; \
  asm volatile ("csrrs %0, " #name ", %1" : "=r" (__csr_val_u32) : "r" (data)); \
  __csr_val_u32; \
})

#define _RDCLR_CSR(name, data) ({ \
  uint32_t __csr_val_u32; \
  asm volatile ("csrrc %0, " #name ", %1" : "=r" (__csr_val_u32) : "r" (data)); \
  __csr_val_u32; \
})


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

#define MCAUSE_INTERRUPT    (1ULL<<((__riscv_xlen)-1))

#define MIP_MSIP            (1 << IRQ_M_SOFT)
#define MIP_MTIP            (1 << IRQ_M_TIMER)
#define MIP_MEIP            (1 << IRQ_M_EXT)

#define MIE_MSIE            MIP_MSIP
#define MIE_MTIE            MIP_MTIP
#define MIE_MEIE            MIP_MEIP

#define MCOUNTINHIBIT_IR    (1<<2)
#define MCOUNTINHIBIT_CY    (1<<0)

#define PRV_M        3
#define IRQ_M_SOFT   3
#define IRQ_M_TIMER  7
#define IRQ_M_EXT    11

#define CSR_CYCLE      0xc00
#define CSR_TIME       0xc01
#define CSR_INSTRET    0xc02
#define CSR_MSTATUS    0x300
#define CSR_MISA       0x301
#define CSR_MEDELEG    0x302
#define CSR_MIDELEG    0x303
#define CSR_MIE        0x304
#define CSR_MTVEC      0x305
#define CSR_MCOUNTEREN 0x306
#define CSR_MSCRATCH   0x340
#define CSR_MEPC       0x341
#define CSR_MCAUSE     0x342
#define CSR_MBADADDR   0x343
#define CSR_MIP        0x344
#define CSR_MCYCLE     0xb00
#define CSR_MINSTRET   0xb02
#define CSR_MVENDORID  0xf11
#define CSR_MARCHID    0xf12
#define CSR_MIMPID     0xf13
#define CSR_MHARTID    0xf14
#define CSR_CYCLEH     0xc80
#define CSR_TIMEH      0xc81
#define CSR_INSTRETH   0xc82
#define CSR_MCYCLEH    0xb80
#define CSR_MINSTRETH  0xb82


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
