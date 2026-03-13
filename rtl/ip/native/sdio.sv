// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

interface sdio_if ();
  logic       sck_o;
  logic       cmd_oe_o;
  logic       cmd_di_i;
  logic       cmd_do_o;
  logic [3:0] dat_oe_o;
  logic [3:0] dat_di_i;
  logic [3:0] dat_do_o;
  logic       irq_o;

  modport dut(
      output sck_o,
      output cmd_oe_o,
      input cmd_di_i,
      output cmd_do_o,
      output dat_oe_o,
      input dat_di_i,
      output dat_do_o,
      output irq_o
  );
endinterface


module nmi_sdio (
    // verilog_format: off
    input logic  clk_i,
    input logic  rst_n_i,
    nmi_if.slave nmi,
    sdio_if.dut  sdio
    // verilog_format: on
);

  // nmi
  assign nmi.rdata     = '0;
  assign nmi.ready     = '0;
  // sdio
  assign sdio.sck_o    = '0;
  assign sdio.cmd_oe_o = '0;
  assign sdio.cmd_do_o = '0;
  assign sdio.dat_oe_o = '0;
  assign sdio.dat_do_o = '0;
  assign sdio.irq_o    = '0;

endmodule
