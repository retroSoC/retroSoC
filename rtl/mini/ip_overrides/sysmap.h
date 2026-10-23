// retroSoC controlled override of the vendored OpenC906 sysmap.h.
//
// Source: openc906 dependency (dependencies.lock.json "openc906"),
//   C906_RTL_FACTORY/gen_rtl/mmu/rtl/sysmap.h
//   revision b0c06eb1f8b3bae663bd8b87eac89ff48e68a57f
// License: Apache-2.0 (T-Head Semiconductor)
//
// retroSoC change: the upstream default region table targets a 40-bit
// reference map and marks the entire low 2.4 GiB (including the Mini
// peripheral window) as cacheable/bufferable memory. The OpenC906 user
// manual (section 3, sysmap.h) requires the integrator to configure address
// attributes per SoC and explicitly requires CLINT/PLIC regions to be
// non-cacheable devices. This override maps the Mini address map:
//
//   region 0: 0x0000_0000-0x01FF_FFFF  flash XIP        -> normal cacheable
//   region 1: 0x0200_0000-0x2FFF_FFFF  MMIO window (incl. the core-internal
//             CLINT/PLIC window 0x0800_0000-0x0FFF_FFFF) -> device SO/NC/NB
//   region 2: 0x3000_0000-0x4FFF_FFFF  SRAM/SDRAM/PSRAM/OPI -> cacheable
//   region 3: 0x5000_0000-0x5FFF_FFFF  XPI window       -> normal cacheable
//   region 4: 0x6000_0000-0x7FFF_FFFF  reserved          -> device SO/NC/NB
//   region 5-7: everything above       -> device SO/NC/NB (also the
//             out-of-table default per the user manual)
//
// Flag bit layout (aq_mmu_utlb.v: utlb_so=flg[9]=pma[4], utlb_ca=pma[3]):
//   flag[4]=SO (strong order)  flag[3]=C (cacheable)  flag[2]=B (bufferable)
//   flag[1]=shareable          flag[0]=security (unused without TEE)
//
// Keep in sync when the lock revision changes.

/*Copyright 2020-2021 T-Head Semiconductor Co., Ltd.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

// ADDR is 28-bit, 4K address
// Flag includes: Strong Order, Cacheable, Bufferable, Shareable, Security

  `define SYSMAP_BASE_ADDR0  28'h02000
  `define SYSMAP_FLG0        5'b01111

  `define SYSMAP_BASE_ADDR1  28'h30000
  `define SYSMAP_FLG1        5'b10011

  `define SYSMAP_BASE_ADDR2  28'h50000
  `define SYSMAP_FLG2        5'b01111

  `define SYSMAP_BASE_ADDR3  28'h60000
  `define SYSMAP_FLG3        5'b01111

  `define SYSMAP_BASE_ADDR4  28'h80000
  `define SYSMAP_FLG4        5'b10011

  `define SYSMAP_BASE_ADDR5  28'hC0000
  `define SYSMAP_FLG5        5'b10011

  `define SYSMAP_BASE_ADDR6  28'hFF00000
  `define SYSMAP_FLG6        5'b10011

  `define SYSMAP_BASE_ADDR7  28'hFFFFFFF
  `define SYSMAP_FLG7        5'b10011

//End ct_mmu_sysmap
