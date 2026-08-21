// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

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
