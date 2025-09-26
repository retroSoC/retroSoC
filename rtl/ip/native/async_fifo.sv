// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module async_fifo #(
    parameter int DATA_WIDTH  = 32,
    parameter int DEPTH_POWER = 4
) (
    input  logic                  wr_clk_i,
    input  logic                  wr_rst_n_i,
    input  logic                  wr_en_i,
    input  logic [DATA_WIDTH-1:0] wr_data_i,
    output logic                  wr_full_o,
    input  logic                  rd_clk_i,
    input  logic                  rd_rst_n_i,
    input  logic                  rd_en_i,
    output logic [DATA_WIDTH-1:0] rd_data_o,
    output logic                  rd_empty_o
);

  localparam int FIFO_DEPTH = 2 ** DEPTH_POWER;
  localparam int PTR_WIDTH = DEPTH_POWER + 1;  // extra bit for empty/full check

  logic [DATA_WIDTH-1:0] r_mem[0:FIFO_DEPTH-1];
  logic [PTR_WIDTH-1:0] r_wr_ptr_bin, r_rd_ptr_bin;
  logic [PTR_WIDTH-1:0] r_wr_ptr_gray, r_rd_ptr_gray;
  logic [PTR_WIDTH-1:0] r_wr_ptr_gray_sync[0:1];
  logic [PTR_WIDTH-1:0] r_rd_ptr_gray_sync[0:1];

  // wr logic
  always_ff @(posedge wr_clk_i or negedge wr_rst_n_i) begin
    if (!wr_rst_n_i) begin
      r_wr_ptr_bin  <= '0;
      r_wr_ptr_gray <= '0;
    end else if (wr_en_i && !wr_full_o) begin
      r_mem[r_wr_ptr_bin[DEPTH_POWER-1:0]] <= wr_data_i;
      r_wr_ptr_bin                         <= r_wr_ptr_bin + 1'b1;
      r_wr_ptr_gray                        <= bin2gray(r_wr_ptr_bin + 1'b1);
    end
  end

  // rd logic
  always_ff @(posedge rd_clk_i or negedge rd_rst_n_i) begin
    if (!rd_rst_n_i) begin
      r_rd_ptr_bin  <= '0;
      r_rd_ptr_gray <= '0;
      rd_data_o     <= '0;
    end else if (rd_en_i && !rd_empty_o) begin
      rd_data_o     <= r_mem[r_rd_ptr_bin[DEPTH_POWER-1:0]];
      r_rd_ptr_bin  <= r_rd_ptr_bin + 1'b1;
      r_rd_ptr_gray <= bin2gray(r_rd_ptr_bin + 1'b1);
    end
  end


  always_ff @(posedge rd_clk_i or negedge rd_rst_n_i) begin
    if (!rd_rst_n_i) begin
      r_wr_ptr_gray_sync[0] <= '0;
      r_wr_ptr_gray_sync[1] <= '0;
    end else begin
      r_wr_ptr_gray_sync[0] <= r_wr_ptr_gray;
      r_wr_ptr_gray_sync[1] <= r_wr_ptr_gray_sync[0];
    end
  end

  always_ff @(posedge wr_clk_i or negedge wr_rst_n_i) begin
    if (!wr_rst_n_i) begin
      r_rd_ptr_gray_sync[0] <= '0;
      r_rd_ptr_gray_sync[1] <= '0;
    end else begin
      r_rd_ptr_gray_sync[0] <= r_rd_ptr_gray;
      r_rd_ptr_gray_sync[1] <= r_rd_ptr_gray_sync[0];
    end
  end

  assign wr_full_o = r_wr_ptr_gray == {~r_rd_ptr_gray_sync[1][PTR_WIDTH-1:PTR_WIDTH-2],
                                        r_rd_ptr_gray_sync[1][PTR_WIDTH-3:0]};

  assign rd_empty_o = r_rd_ptr_gray == r_wr_ptr_gray_sync[1];

  function automatic logic [PTR_WIDTH-1:0] bin2gray(input logic [PTR_WIDTH-1:0] bin);
    return (bin >> 1) ^ bin;
  endfunction

  initial begin
    if (DEPTH_POWER < 1 || DEPTH_POWER > 10) $error("DEPTH_POWER ERROR");
    if (DATA_WIDTH < 1 || DATA_WIDTH > 256) $error("DATA_WIDTH ERROR");
  end

endmodule
