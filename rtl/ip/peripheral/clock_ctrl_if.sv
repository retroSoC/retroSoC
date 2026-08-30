// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

interface clock_ctrl_if ();
  logic [31:0] req_data_o;
  logic        req_valid_o;
  logic        req_ready_i;
  logic [31:0] rsp_data_i;
  logic        rsp_valid_i;
  logic        rsp_ready_o;
  logic [31:0] current_i;
  logic [31:0] fault_i;
  logic [31:0] memory_i;

  modport sysctrl(
      output req_data_o,
      output req_valid_o,
      input req_ready_i,
      input rsp_data_i,
      input rsp_valid_i,
      output rsp_ready_o,
      input current_i,
      input fault_i,
      input memory_i
  );

  modport rcu(
      input req_data_o,
      input req_valid_o,
      output req_ready_i,
      output rsp_data_i,
      output rsp_valid_i,
      input rsp_ready_o,
      output current_i,
      output fault_i,
      output memory_i
  );
endinterface
