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
// NOTE: need to set a right value for software!
`define IRQ_HANDLER_START_ADDR 32'h0000_0000

`define FLASH_START    4'h0
`define NATV_IP_START  4'h1
`define APB_IP_START   4'h2
`define SRAM_START     4'h3
`define PSRAM_START    4'h4
`define QSPI_MEM_START 4'h5
`define SPISD_START0   4'h6
`define SPISD_START1   4'h7
`define SPISD_START2   4'h8
`define SPISD_START3   4'h9

// NMI IP REG ADDR
`define NMI_GPIO_START     8'h00
`define NMI_UART_START     8'h10
`define NMI_TIM0_START     8'h20
`define NMI_TIM1_START     8'h30
`define NMI_PSRAM_START    8'h40
`define NMI_SPISD_START    8'h50
`define NMI_I2C_START      8'h60
`define NMI_I2S_START      8'h70
`define NMI_ONEWIRE_START  8'h80
`define NMI_QSPI_START     8'h90
`define NMI_DMA_START      8'hA0
`define NMI_SYSCTRL_START  8'hB0
// APB IP REG ADDR
`define APB_ARCHINFO_START 8'h00
`define APB_RNG_START      8'h10
`define APB_UART_START     8'h20
`define APB_PWM_START      8'h30
`define APB_PS2_START      8'h40
`define APB_I2C_START      8'h50
`define APB_QSPI_START     8'h60
`define APB_RTC_START      8'h70
`define APB_WDG_START      8'h80
`define APB_CRC_START      8'h90
`define APB_TMR_START      8'hA0
`define APB_USR_START      8'hF0
`endif