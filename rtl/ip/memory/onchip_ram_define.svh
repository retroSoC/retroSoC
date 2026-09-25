// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef RETROSOC_ONCHIP_RAM_DEFINE_SVH
`define RETROSOC_ONCHIP_RAM_DEFINE_SVH

// verilog_format: off -- preserve the handwritten register ABI alignment
`define APB4_ONCHIP_RAM__IP_ID                12'h000
`define APB4_ONCHIP_RAM__IP_VERSION           12'h004
`define APB4_ONCHIP_RAM__CAPABILITY           12'h008
`define APB4_ONCHIP_RAM__MEMORY_BYTES         12'h00C
`define APB4_ONCHIP_RAM__BANK_COUNT           12'h010
`define APB4_ONCHIP_RAM__BANK_BYTES           12'h014
`define APB4_ONCHIP_RAM__PERF_READ_REQUESTS   12'h020
`define APB4_ONCHIP_RAM__PERF_WRITE_REQUESTS  12'h024
`define APB4_ONCHIP_RAM__PERF_READ_BEATS      12'h028
`define APB4_ONCHIP_RAM__PERF_WRITE_BEATS     12'h02C
`define APB4_ONCHIP_RAM__PERF_STALL_CYCLES    12'h030
`define APB4_ONCHIP_RAM__PERF_ERROR_RESPONSES 12'h034

`define APB4_ONCHIP_RAM__CAP_PRESENT          0
`define APB4_ONCHIP_RAM__CAP_NATIVE_AXI4      1
`define APB4_ONCHIP_RAM__CAP_BYTE_WRITE       2
`define APB4_ONCHIP_RAM__CAP_FIXED            3
`define APB4_ONCHIP_RAM__CAP_INCR             4
`define APB4_ONCHIP_RAM__CAP_WRAP             5
`define APB4_ONCHIP_RAM__CAP_PERFORMANCE      6
`define APB4_ONCHIP_RAM__CAP_MAX_BEATS_LSB    8
`define APB4_ONCHIP_RAM__CAP_DATA_BYTES_LSB   16
// verilog_format: on

`endif
