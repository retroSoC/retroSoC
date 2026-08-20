// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

package dma_pkg;
  localparam logic [2:0] DMA_KIND_MM_TO_MM = 3'd0;
  localparam logic [2:0] DMA_KIND_MM_TO_STREAM = 3'd1;
  localparam logic [2:0] DMA_KIND_STREAM_TO_MM = 3'd2;

  localparam logic [1:0] DMA_WIDTH_32 = 2'd2;

  localparam logic [3:0] DMA_REQUEST_SOFTWARE = 4'd0;
  localparam logic [3:0] DMA_REQUEST_I2S_TX = 4'd1;
  localparam logic [3:0] DMA_REQUEST_I2S_RX = 4'd2;
  localparam logic [3:0] DMA_REQUEST_QSPI_TX = 4'd3;
  localparam logic [3:0] DMA_REQUEST_QSPI_RX = 4'd4;
  localparam logic [3:0] DMA_REQUEST_UART_TX = 4'd5;
  localparam logic [3:0] DMA_REQUEST_UART_RX = 4'd6;
  localparam logic [3:0] DMA_REQUEST_I2C0_TX = 4'd7;
  localparam logic [3:0] DMA_REQUEST_I2C0_RX = 4'd8;
  localparam logic [3:0] DMA_REQUEST_I2C1_TX = 4'd9;
  localparam logic [3:0] DMA_REQUEST_I2C1_RX = 4'd10;
  localparam logic [3:0] DMA_REQUEST_DVP_RX = 4'd11;
  localparam logic [3:0] DMA_REQUEST_CRYPTO_IN = 4'd12;
  localparam logic [3:0] DMA_REQUEST_CRYPTO_OUT = 4'd13;

  localparam logic [3:0] DMA_ERROR_NONE = 4'd0;
  localparam logic [3:0] DMA_ERROR_CONFIG = 4'd1;
  localparam logic [3:0] DMA_ERROR_ALIGNMENT = 4'd2;
  localparam logic [3:0] DMA_ERROR_AXI_READ = 4'd3;
  localparam logic [3:0] DMA_ERROR_AXI_WRITE = 4'd4;
  localparam logic [3:0] DMA_ERROR_AXI_PROTOCOL = 4'd5;
  localparam logic [3:0] DMA_ERROR_STREAM = 4'd6;
  localparam logic [3:0] DMA_ERROR_ABORT = 4'd7;
endpackage
