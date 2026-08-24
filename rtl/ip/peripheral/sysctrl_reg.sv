// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module sysctrl_reg (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic        clk_i,
    input  logic        rst_n_i,
    apb4_if.slave       apb4,
    output logic        write_valid_o,
    output logic [7:0]  write_offset_o,
    output logic [31:0] write_data_o,
    output logic [3:0]  write_strobe_o,
    output logic [7:0]  read_offset_o,
    input  logic        read_data_valid_i,
    input  logic [31:0] read_data_i
    // verilog_format: on
);

  logic        s_req_accept;
  logic        s_read_accept;
  logic        s_apb4_ready_d;
  logic        s_apb4_ready_q;
  logic [31:0] s_apb4_rdata_d;
  logic [31:0] s_apb4_rdata_q;

  assign s_req_accept   = apb4.psel && apb4.penable && !s_apb4_ready_q;
  assign s_read_accept  = s_req_accept && !(|apb4.pstrb);
  assign write_valid_o  = s_req_accept && (|apb4.pstrb);
  assign write_offset_o = apb4.paddr[7:0];
  assign write_data_o   = apb4.pwdata;
  assign write_strobe_o = apb4.pstrb;
  assign read_offset_o  = apb4.paddr[7:0];
  assign apb4.pready    = s_apb4_ready_q;
  assign apb4.pslverr   = 1'b0;
  assign apb4.prdata    = s_apb4_rdata_q;
  assign s_apb4_ready_d = s_req_accept;
  assign s_apb4_rdata_d = read_data_valid_i ? read_data_i : s_apb4_rdata_q;

  dffr #(
      .DATA_WIDTH(1)
  ) u_apb4_ready_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_apb4_ready_d),
      .dat_o  (s_apb4_ready_q)
  );

  dffer #(
      .DATA_WIDTH(32)
  ) u_apb4_rdata_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_read_accept),
      .dat_i  (s_apb4_rdata_d),
      .dat_o  (s_apb4_rdata_q)
  );

endmodule
