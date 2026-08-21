// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module async_fifo #(
    parameter int DataWidth  = 32,
    parameter int DepthPower = 4
) (
    input  logic                 wr_clk_i,
    input  logic                 wr_rst_n_i,
    input  logic                 wr_en_i,
    input  logic [DataWidth-1:0] wr_data_i,
    output logic                 wr_full_o,
    input  logic                 rd_clk_i,
    input  logic                 rd_rst_n_i,
    input  logic                 rd_en_i,
    output logic [DataWidth-1:0] rd_data_o,
    output logic                 rd_empty_o,
    output logic [ DepthPower:0] elem_num_o
);

  localparam int signed FifoDepth = 2 ** DepthPower;
  localparam int signed PtrWidth = DepthPower + 1;  // extra bit for empty/full check

  logic [DataWidth-1:0] s_mem[0:FifoDepth-1];
  logic [PtrWidth-1:0] s_wr_ptr_bin, s_rd_ptr_bin;
  logic [PtrWidth-1:0] s_wr_ptr_gray, s_rd_ptr_gray;
  logic [PtrWidth-1:0] s_wr_ptr_gray_sync[0:1];
  logic [PtrWidth-1:0] s_rd_ptr_gray_sync[0:1];
  logic [PtrWidth-1:0] s_rd_ptr_bin_sync;

  // CDC storage: write-domain data is retained for the independent read domain.
  // Resets are independently asserted in their respective domains; Gray pointers
  // cross through two-flop synchronizers and the extra bounded index bit detects
  // empty/full. These always_ff blocks preserve inferred dual-clock RAM, pointer,
  // and synchronizer semantics and cannot be replaced by single-clock Common DFFs.
  // Write-domain memory process.
  always_ff @(posedge wr_clk_i) begin
    if (wr_en_i && !wr_full_o) begin
      s_mem[s_wr_ptr_bin[DepthPower-1:0]] <= wr_data_i;
    end
  end
  always_ff @(posedge wr_clk_i or negedge wr_rst_n_i) begin
    if (!wr_rst_n_i) begin
      s_wr_ptr_bin  <= '0;
      s_wr_ptr_gray <= '0;
    end else if (wr_en_i && !wr_full_o) begin
      s_wr_ptr_bin  <= s_wr_ptr_bin + 1'b1;
      s_wr_ptr_gray <= bin2gray(s_wr_ptr_bin + 1'b1);
    end
  end

  // Read-domain memory and pointer processes.
  always_ff @(posedge rd_clk_i or negedge rd_rst_n_i) begin
    if (!rd_rst_n_i) begin
      rd_data_o <= '0;
    end else if (rd_en_i && !rd_empty_o) begin
      rd_data_o <= s_mem[s_rd_ptr_bin[DepthPower-1:0]];
    end
  end
  always_ff @(posedge rd_clk_i or negedge rd_rst_n_i) begin
    if (!rd_rst_n_i) begin
      s_rd_ptr_bin  <= '0;
      s_rd_ptr_gray <= '0;
    end else if (rd_en_i && !rd_empty_o) begin
      s_rd_ptr_bin  <= s_rd_ptr_bin + 1'b1;
      s_rd_ptr_gray <= bin2gray(s_rd_ptr_bin + 1'b1);
    end
  end


  always_ff @(posedge rd_clk_i or negedge rd_rst_n_i) begin
    if (!rd_rst_n_i) begin
      s_wr_ptr_gray_sync[0] <= '0;
      s_wr_ptr_gray_sync[1] <= '0;
    end else begin
      s_wr_ptr_gray_sync[0] <= s_wr_ptr_gray;
      s_wr_ptr_gray_sync[1] <= s_wr_ptr_gray_sync[0];
    end
  end

  always_ff @(posedge wr_clk_i or negedge wr_rst_n_i) begin
    if (!wr_rst_n_i) begin
      s_rd_ptr_gray_sync[0] <= '0;
      s_rd_ptr_gray_sync[1] <= '0;
    end else begin
      s_rd_ptr_gray_sync[0] <= s_rd_ptr_gray;
      s_rd_ptr_gray_sync[1] <= s_rd_ptr_gray_sync[0];
    end
  end

  assign wr_full_o = s_wr_ptr_gray == {~s_rd_ptr_gray_sync[1][PtrWidth-1:PtrWidth-2],
                                        s_rd_ptr_gray_sync[1][PtrWidth-3:0]};

  assign rd_empty_o = s_rd_ptr_gray == s_wr_ptr_gray_sync[1];

  assign elem_num_o = s_wr_ptr_bin - s_rd_ptr_bin_sync;

  function automatic logic [PtrWidth-1:0] bin2gray(input logic [PtrWidth-1:0] bin);
    return (bin >> 1) ^ bin;
  endfunction

  gray2bin #(
      .DATA_WIDTH(PtrWidth)
  ) u_gray2bin (
      .gray_i(s_rd_ptr_gray_sync[1]),
      .bin_o (s_rd_ptr_bin_sync)
  );

`ifndef SYNTHESIS
  initial begin
    if (DepthPower < 1 || DepthPower > 10) $error("DepthPower ERROR");
    if (DataWidth < 1 || DataWidth > 256) $error("DataWidth ERROR");
  end
`endif

endmodule
