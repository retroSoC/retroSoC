// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef INC_MMAP_DEFINE_SVH
`define INC_MMAP_DEFINE_SVH

`define FLASH_START_ADDR 32'h0000_0000
`define FLASH_END_ADDR   32'h0FFF_FFFF

`define FLASH_START   8'h00
`define NATV_IP_START 8'h10
`define APB_IP_START  8'h20
`define SRAM_START    8'h30
`define PSRAM0_START  8'h40
`define PSRAM1_START  8'h41
`define SPISD_START0  4'h5
`define SPISD_START1  4'h6
`define SPISD_START2  4'h7
`define SPISD_START3  4'h8

`endif