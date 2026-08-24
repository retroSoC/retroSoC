// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "onchip_ram_define.svh"

module onchip_ram_reg #(
    parameter bit          Present     = 1'b1,
    parameter int unsigned CapacityKiB = 128
) (
    // verilog_format: off -- preserve the register input grouping
    input  logic        clk_i,
    input  logic        rst_n_i,
    apb4_if.slave       apb4,
    input  logic [31:0] perf_read_requests_i,
    input  logic [31:0] perf_write_requests_i,
    input  logic [31:0] perf_read_beats_i,
    input  logic [31:0] perf_write_beats_i,
    input  logic [31:0] perf_stall_cycles_i,
    input  logic [31:0] perf_error_responses_i
    // verilog_format: on
);
  localparam logic [31:0] IpId = 32'h5352_414D;
  localparam logic [31:0] IpVersion = 32'h0001_0000;
  localparam int unsigned BankBytes = 4096;
  localparam int unsigned BankCount = CapacityKiB / 4;
  localparam logic [31:0] Capability =
      32'(4 << `APB4_ONCHIP_RAM__CAP_DATA_BYTES_LSB) |
      32'(16 << `APB4_ONCHIP_RAM__CAP_MAX_BEATS_LSB) |
      32'h0000_007E | 32'(Present);

  logic        s_req;
  logic        s_aligned;
  logic        s_offset_valid;
  logic        s_access_err;
  logic        s_ready_d;
  logic        s_ready_q;
  logic        s_resp_err_d;
  logic        s_resp_err_q;
  logic [31:0] s_rdata_d;
  logic [31:0] s_rdata_q;

  assign s_req        = apb4.psel && apb4.penable && !s_ready_q;
  assign s_aligned    = apb4.paddr[1:0] == 2'b00;
  assign s_access_err = !s_aligned || apb4.pwrite || !s_offset_valid;
  assign s_ready_d    = s_req;
  assign s_resp_err_d = s_req && s_access_err;
  assign apb4.pready  = s_ready_q;
  assign apb4.prdata  = s_rdata_q;
  assign apb4.pslverr = s_resp_err_q;

  always_comb begin
    s_offset_valid = 1'b1;
    s_rdata_d      = 32'd0;
    unique case (apb4.paddr[11:0])
      `APB4_ONCHIP_RAM__IP_ID:                s_rdata_d = IpId;
      `APB4_ONCHIP_RAM__IP_VERSION:           s_rdata_d = IpVersion;
      `APB4_ONCHIP_RAM__CAPABILITY:           s_rdata_d = Capability;
      `APB4_ONCHIP_RAM__MEMORY_BYTES:         s_rdata_d = Present ? 32'(CapacityKiB * 1024) : 32'd0;
      `APB4_ONCHIP_RAM__BANK_COUNT:           s_rdata_d = Present ? 32'(BankCount) : 32'd0;
      `APB4_ONCHIP_RAM__BANK_BYTES:           s_rdata_d = 32'(BankBytes);
      `APB4_ONCHIP_RAM__PERF_READ_REQUESTS:   s_rdata_d = perf_read_requests_i;
      `APB4_ONCHIP_RAM__PERF_WRITE_REQUESTS:  s_rdata_d = perf_write_requests_i;
      `APB4_ONCHIP_RAM__PERF_READ_BEATS:      s_rdata_d = perf_read_beats_i;
      `APB4_ONCHIP_RAM__PERF_WRITE_BEATS:     s_rdata_d = perf_write_beats_i;
      `APB4_ONCHIP_RAM__PERF_STALL_CYCLES:    s_rdata_d = perf_stall_cycles_i;
      `APB4_ONCHIP_RAM__PERF_ERROR_RESPONSES: s_rdata_d = perf_error_responses_i;
      default: begin
        s_offset_valid = 1'b0;
        s_rdata_d      = 32'd0;
      end
    endcase
  end

  dffr #(
      .DATA_WIDTH(1)
  ) u_ready_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ready_d),
      .dat_o  (s_ready_q)
  );

  dffr #(
      .DATA_WIDTH(1)
  ) u_resp_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_resp_err_d),
      .dat_o  (s_resp_err_q)
  );

  dffer #(
      .DATA_WIDTH(32)
  ) u_rdata_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_req),
      .dat_i  (s_rdata_d),
      .dat_o  (s_rdata_q)
  );
endmodule
