// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// common is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

// NOTE: BUFFER_DEPTH Must be a power of 2 for this logic
module fifo #(
    parameter int DATA_WIDTH   = 32,
    parameter int BUFFER_DEPTH = 8,
    parameter int ADDR_WIDTH   = $clog2(BUFFER_DEPTH)
) (
    input  logic                  clk_i,
    input  logic                  rst_n_i,
    input  logic                  flush_i,
    input  logic                  push_i,
    output logic                  full_o,
    input  logic [DATA_WIDTH-1:0] dat_i,
    input  logic                  pop_i,
    output logic                  empty_o,
    output logic [DATA_WIDTH-1:0] dat_o,
    output logic [  ADDR_WIDTH:0] cnt_o
);

  // Pointers are 1 bit wider than the address
  logic [ADDR_WIDTH:0] s_wr_ptr_d, s_wr_ptr_q;
  logic [ADDR_WIDTH:0] s_rd_ptr_d, s_rd_ptr_q;
  logic [DATA_WIDTH-1:0] r_mem[0:BUFFER_DEPTH-1];
  logic push_hdshk, pop_hdshk;

  // verilog_format: off
  assign push_hdshk = push_i & ~full_o;
  assign pop_hdshk  = pop_i & ~empty_o;
  assign dat_o      = r_mem[s_rd_ptr_q[ADDR_WIDTH-1:0]];
  assign cnt_o      = s_wr_ptr_q - s_rd_ptr_q;
  assign empty_o    = s_wr_ptr_q == s_rd_ptr_q;
  assign full_o     = (s_wr_ptr_q[ADDR_WIDTH]     != s_rd_ptr_q[ADDR_WIDTH]) &&
                      (s_wr_ptr_q[ADDR_WIDTH-1:0] == s_rd_ptr_q[ADDR_WIDTH-1:0]);
  // verilog_format: on

  assign s_wr_ptr_d = flush_i ? '0 : (push_hdshk ? s_wr_ptr_q + 1'b1 : s_wr_ptr_q);
  dffr #(ADDR_WIDTH + 1) u_wr_ptr_dffr (
      clk_i,
      rst_n_i,
      s_wr_ptr_d,
      s_wr_ptr_q
  );

  assign s_rd_ptr_d = flush_i ? '0 : (pop_hdshk ? s_rd_ptr_q + 1'b1 : s_rd_ptr_q);
  dffr #(ADDR_WIDTH + 1) u_rd_ptr_dffr (
      clk_i,
      rst_n_i,
      s_rd_ptr_d,
      s_rd_ptr_q
  );


  always_ff @(posedge clk_i) begin
    if (push_hdshk) begin
      r_mem[s_wr_ptr_q[ADDR_WIDTH-1:0]] <= dat_i;
    end
  end


`ifndef SYNTHESIS
  initial begin
    if ((2 ** ADDR_WIDTH) != BUFFER_DEPTH) begin
      $error("Error: BUFFER_DEPTH (%0d) must be a power of 2 for pointer-comparison logic.",
             BUFFER_DEPTH);
    end
  end
`endif

endmodule
