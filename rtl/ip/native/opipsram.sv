// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

interface opipsram_if ();
  logic       sck_o;
  logic       ce_o;
  logic [7:0] io_oe_o;
  logic [7:0] io_di_i;
  logic [7:0] io_do_o;
  logic       dqs_oe_o;
  logic       dqs_di_i;
  logic       dqs_do_o;
  logic       irq_o;

  modport dut(
      output sck_o,
      output ce_o,
      output io_oe_o,
      input io_di_i,
      output io_do_o,
      output dqs_oe_o,
      input dqs_di_i,
      output dqs_do_o,
      output irq_o
  );
endinterface

module nmi_opipsram (
    // verilog_format: off
    input logic     clk_i,
    input logic     rst_n_i,
    nmi_if.slave    nmi,
    opipsram_if.dut psram
    // verilog_format: on
);

  // nmi
  assign nmi.rdata      = '0;
  assign nmi.ready      = '0;
  // psram
  assign psram.sck_o    = '0;
  assign psram.ce_o     = '0;
  assign psram.io_oe_o  = '0;
  assign psram.io_do_o  = '0;
  assign psram.dqs_oe_o = '0;
  assign psram.dqs_do_o = '0;
  assign prram.irq_o    = '0;

endmodule
