// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

interface dma_req_if ();
  logic i2s_tx_proc;
  logic i2s_rx_proc;
  logic qspi_tx_proc;
  logic qspi_rx_proc;
  logic uart_tx_proc;
  logic uart_rx_proc;
  logic i2c0_tx_proc;
  logic i2c0_rx_proc;
  logic i2c1_tx_proc;
  logic i2c1_rx_proc;
  logic crypto_in_proc;
  logic crypto_out_proc;

  modport dut(
      input i2s_tx_proc,
      input i2s_rx_proc,
      input qspi_tx_proc,
      input qspi_rx_proc,
      input uart_tx_proc,
      input uart_rx_proc,
      input i2c0_tx_proc,
      input i2c0_rx_proc,
      input i2c1_tx_proc,
      input i2c1_rx_proc,
      input crypto_in_proc,
      input crypto_out_proc
  );
endinterface
