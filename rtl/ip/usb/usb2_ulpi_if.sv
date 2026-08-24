// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

interface usb2_ulpi_if;
  logic [7:0] data_di_i;
  logic [7:0] data_do_o;
  logic       data_oe_o;
  logic       dir_i;
  logic       nxt_i;
  logic       stp_o;
  logic       reset_n_o;

  modport dut(
      input data_di_i,
      input dir_i,
      input nxt_i,
      output data_do_o,
      output data_oe_o,
      output stp_o,
      output reset_n_o
  );

  modport phy(
      output data_di_i,
      output dir_i,
      output nxt_i,
      input data_do_o,
      input data_oe_o,
      input stp_o,
      input reset_n_o
  );
endinterface
