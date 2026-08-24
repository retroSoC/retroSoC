// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "xpi_define.svh"

interface xpi_if ();
  logic                    sck_o;
  logic [`XPI_NSS_NUM-1:0] nss_o;
  logic [             3:0] io_oe_o;
  logic [             3:0] io_di_i;
  logic [             3:0] io_do_o;

  modport dut(output sck_o, output nss_o, output io_oe_o, input io_di_i, output io_do_o);
endinterface
