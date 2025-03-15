// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// common is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef INC_FIFO_SV
`define INC_FIFO_SV

//NOTE: buffer depth need to be 2^x val
module fifo #(
    parameter DATA_WIDTH       = 32,
    parameter BUFFER_DEPTH     = 8,
    parameter LOG_BUFFER_DEPTH = (BUFFER_DEPTH > 1) ? $clog2(BUFFER_DEPTH) : 1
) (
    input                       clk_i,
    input                       rst_n_i,
    input                       flush_i,
    output                      full_o,
    output                      empty_o,
    output [LOG_BUFFER_DEPTH:0] cnt_o,
    input  [    DATA_WIDTH-1:0] dat_i,
    input                       push_i,
    output [    DATA_WIDTH-1:0] dat_o,
    input                       pop_i
);

  reg  [LOG_BUFFER_DEPTH - 1:0]                 s_rd_ptr_d;
  wire [LOG_BUFFER_DEPTH - 1:0]                 s_rd_ptr_q;
  reg  [LOG_BUFFER_DEPTH - 1:0]                 s_wr_ptr_d;
  wire [LOG_BUFFER_DEPTH - 1:0]                 s_wr_ptr_q;
  reg  [    LOG_BUFFER_DEPTH:0]                 s_cnt_d;
  wire [    LOG_BUFFER_DEPTH:0]                 s_cnt_q;
  reg  [    BUFFER_DEPTH - 1:0][DATA_WIDTH-1:0] s_mem_d;
  wire [    BUFFER_DEPTH - 1:0][DATA_WIDTH-1:0] s_mem_q;
  wire push_hdshk, pop_hdshk;

  assign push_hdshk = push_i & ~full_o;
  assign pop_hdshk  = pop_i & ~empty_o;
  assign cnt_o      = s_cnt_q;
  assign empty_o    = s_cnt_q == 0;
  assign full_o     = s_cnt_q == BUFFER_DEPTH;
  assign dat_o      = s_mem_q[s_rd_ptr_q];

  always @(*) begin
    s_rd_ptr_d = s_rd_ptr_q;
    if (flush_i) begin
      s_rd_ptr_d = {LOG_BUFFER_DEPTH{1'b0}};
    end else if (pop_hdshk) begin
      s_rd_ptr_d = s_rd_ptr_q + 1'b1;
    end
  end
  dffr #(LOG_BUFFER_DEPTH) u_rd_ptr_dffr (
      clk_i,
      rst_n_i,
      s_rd_ptr_d,
      s_rd_ptr_q
  );

  always @(*) begin
    s_wr_ptr_d = s_wr_ptr_q;
    if (flush_i) begin
      s_wr_ptr_d = {LOG_BUFFER_DEPTH{1'b0}};
    end else if (push_hdshk) begin
      s_wr_ptr_d = s_wr_ptr_q + 1'b1;
    end
  end
  dffr #(LOG_BUFFER_DEPTH) u_wr_ptr_dffr (
      clk_i,
      rst_n_i,
      s_wr_ptr_d,
      s_wr_ptr_q
  );

  // push, pop in the meantime, s_cnt_d will not change
  always @(*) begin
    s_cnt_d = s_cnt_q;
    if (flush_i) begin
      s_cnt_d = {(LOG_BUFFER_DEPTH + 1) {1'b0}};
    end else if (push_hdshk && ~pop_hdshk) begin
      s_cnt_d = s_cnt_q + 1'b1;
    end else if (~push_hdshk && pop_hdshk) begin
      s_cnt_d = s_cnt_q - 1'b1;
    end
  end
  dffr #(LOG_BUFFER_DEPTH + 1) u_cnt_dffr (
      clk_i,
      rst_n_i,
      s_cnt_d,
      s_cnt_q
  );

  always @(*) begin
    s_mem_d = s_mem_q;
    if (push_hdshk) begin
      s_mem_d[s_wr_ptr_q] = dat_i;
    end
  end

  dffr #(BUFFER_DEPTH * DATA_WIDTH) u_mem_dffr (
      clk_i,
      rst_n_i,
      s_mem_d,
      s_mem_q
  );

endmodule
`endif
