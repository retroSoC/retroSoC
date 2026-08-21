// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`timescale 1ns / 1ps

module sdio_dma_descriptor #(
    parameter int DescCount = 16
) (
    input  logic [31:0] buffer_addr_i,
    input  logic [31:0] byte_count_i,
    input  logic [31:0] next_addr_i,
    input  logic [31:0] control_status_i,
    input  logic [15:0] desc_index_i,
    output logic        own_o,
    output logic        chain_o,
    output logic        end_o,
    output logic        irq_o,
    output logic        valid_o,
    output logic        error_o,
    output logic        address_error_o,
    output logic        length_error_o,
    output logic        chain_error_o
);
  logic s_last_allowed;
  logic s_control_valid;

  assign own_o = control_status_i[sdio_pkg::SDIO_DESC_OWN];
  assign chain_o = control_status_i[sdio_pkg::SDIO_DESC_CHAIN];
  assign end_o = control_status_i[sdio_pkg::SDIO_DESC_END];
  assign irq_o = control_status_i[sdio_pkg::SDIO_DESC_IRQ];
  assign s_last_allowed = desc_index_i + 1'b1 < DescCount;
  assign s_control_valid = own_o && !control_status_i[31:18];
  assign address_error_o = (buffer_addr_i[1:0] != 2'b00) ||
                           ((!end_o || chain_o) && ((next_addr_i[3:0] != 4'b0000) ||
                                                    (next_addr_i[11:0] >= 12'hFF0)));
  assign length_error_o = (byte_count_i == 32'd0);
  assign chain_error_o = end_o ? (next_addr_i != 32'd0) :
                         (!chain_o || (next_addr_i == 32'd0) || !s_last_allowed);
  assign error_o = !s_control_valid || address_error_o || length_error_o || chain_error_o;
  assign valid_o = !error_o;

`ifndef SYNTHESIS
  initial begin
    if (DescCount < 1) begin
      $fatal(1, "sdio_dma_descriptor: DescCount must be positive");
    end
  end
`endif
endmodule
