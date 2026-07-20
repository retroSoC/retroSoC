// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef NMI_I2S_DEF_SV
`define NMI_I2S_DEF_SV

// verilog_format: off
`define NMI_I2S_MODE     8'h00
`define NMI_I2S_FORMAT   8'h04
`define NMI_I2S_UPBOUND  8'h08
`define NMI_I2S_LOWBOUND 8'h0C
`define NMI_I2S_RECVEN   8'h10
`define NMI_I2S_TXDATA   8'h14
`define NMI_I2S_RXDATA   8'h18
`define NMI_I2S_STATUS   8'h1C
// verilog_format: on

`define I2S_16b_48K 2'd0
`define I2S_16b_96K 2'd1
`define I2S_24b_48K 2'd2
`define I2S_24b_96K 2'd3

`endif