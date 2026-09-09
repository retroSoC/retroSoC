// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "apu_define.svh"

module apu_local_sram #(
    parameter int unsigned MemoryWordCount = `APB4_APU__LOCAL_DATA_BYTES / 4
) (
    // verilog_format: off -- preserve loader and codec port columns
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        image_valid_i,
    input  logic [15:0] table_bytes_i,
    input  logic        epoch_clear_i,
    input  logic        loader_active_i,
    input  logic        loader_req_i,
    input  logic [16:0] loader_addr_i,
    input  logic [31:0] loader_data_i,
    input  logic [ 3:0] loader_strb_i,
    output logic        loader_ready_o,
    input  logic        codec_req_i,
    input  logic        codec_write_i,
    input  logic [16:0] codec_addr_i,
    input  logic [31:0] codec_data_i,
    input  logic [ 3:0] codec_strb_i,
    output logic        codec_ready_o,
    output logic [31:0] codec_data_o,
    output logic        codec_valid_o,
    output logic        codec_access_err_o
    // verilog_format: on
);
  localparam logic [14:0] MemoryWordCountValue = 15'(MemoryWordCount);

  logic                       s_req;
  logic                       s_write;
  logic [               16:0] s_addr;
  logic [               31:0] s_write_data;
  logic [                3:0] s_write_strb;
  logic [               14:0] s_word_addr;
  logic                       s_codec_range_ok;
  logic                       s_codec_table;
  logic                       s_codec_mutable_valid;
  logic                       s_codec_access_err;
  logic [MemoryWordCount-1:0] s_mutable_valid_q;
  logic s_read_q, s_read_codec_q, s_read_err_q;
  logic [31:0] s_read_data;
  logic        s_unused;

  assign loader_ready_o = loader_active_i;
  assign codec_ready_o = !loader_active_i;
  assign s_req = loader_active_i ? loader_req_i : codec_req_i;
  assign s_write = loader_active_i || codec_write_i;
  assign s_addr = loader_active_i ? loader_addr_i : codec_addr_i;
  assign s_write_data = loader_active_i ? loader_data_i : codec_data_i;
  assign s_write_strb = loader_active_i ? loader_strb_i : codec_strb_i;
  assign s_word_addr = s_addr[16:2];
  assign s_codec_range_ok = (codec_addr_i[1:0] == 2'd0) &&
      ((codec_addr_i < `APB4_APU__LOCAL_CODEC_BYTES) ||
       ((codec_addr_i >= `APB4_APU__LOCAL_INTERNAL_BASE) &&
        (codec_addr_i < `APB4_APU__LOCAL_DATA_BYTES)));
  assign s_codec_table = codec_addr_i < {1'b0, table_bytes_i};
  assign s_codec_mutable_valid = (s_word_addr < MemoryWordCountValue) &&
      s_mutable_valid_q[s_word_addr];
  assign s_codec_access_err = codec_req_i &&
      ((s_word_addr >= MemoryWordCountValue) || !s_codec_range_ok ||
       (codec_write_i && s_codec_table) ||
       (!codec_write_i && (s_codec_table ? !image_valid_i : !s_codec_mutable_valid)));
  assign codec_data_o = s_read_data;
  assign codec_valid_o = s_read_q && s_read_codec_q;
  assign codec_access_err_o = (codec_req_i && codec_ready_o && s_codec_access_err) ||
      (codec_valid_o && s_read_err_q);

`ifdef HAVE_SRAM_MACRO
  localparam int unsigned BankCount = 28;

  logic [          4:0]       s_bank;
  logic [          9:0]       s_bank_addr;
  logic [BankCount-1:0][31:0] s_bank_data;
  logic [          4:0]       s_read_bank_q;

  assign s_bank      = s_word_addr[14:10];
  assign s_bank_addr = s_word_addr[9:0];

  for (genvar bank = 0; bank < BankCount; bank++) begin : gen_local_bank
    tc_sram_1024x32 u_local_sram (
        .clk_i (clk_i),
        .cs_i  (s_req && (s_bank == 5'(bank)) && (loader_active_i || !s_codec_access_err)),
        .addr_i(s_bank_addr),
        .data_i(s_write_data),
        .mask_i(s_write_strb),
        .wren_i(s_write),
        .data_o(s_bank_data[bank])
    );
  end

  assign s_read_data = s_bank_data[s_read_bank_q];

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_read_bank_q <= 5'd0;
    end else if (s_req && !s_write && (loader_active_i || !s_codec_access_err)) begin
      s_read_bank_q <= s_bank;
    end
  end
`else
  logic [31:0] mem           [0:MemoryWordCount-1];
  logic [31:0] s_read_data_q;

  assign s_read_data = s_read_data_q;

  always_ff @(posedge clk_i) begin
    if (s_req && (loader_active_i || !s_codec_access_err)) begin
      if (s_write) begin
        if (s_write_strb[0]) mem[s_word_addr][7:0] <= s_write_data[7:0];
        if (s_write_strb[1]) mem[s_word_addr][15:8] <= s_write_data[15:8];
        if (s_write_strb[2]) mem[s_word_addr][23:16] <= s_write_data[23:16];
        if (s_write_strb[3]) mem[s_word_addr][31:24] <= s_write_data[31:24];
      end else begin
        s_read_data_q <= mem[s_word_addr];
      end
    end
  end
`endif

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      for (int word_index = 0; word_index < MemoryWordCount; word_index++) begin
        s_mutable_valid_q[word_index] <= 1'b0;
      end
      s_read_q       <= 1'b0;
      s_read_codec_q <= 1'b0;
      s_read_err_q   <= 1'b0;
    end else begin
      s_read_q       <= s_req && !s_write;
      s_read_codec_q <= !loader_active_i;
      s_read_err_q   <= !loader_active_i && s_codec_access_err;
      if (epoch_clear_i) begin
        for (int word_index = 0; word_index < MemoryWordCount; word_index++) begin
          s_mutable_valid_q[word_index] <= 1'b0;
        end
      end else if (!loader_active_i && codec_req_i && codec_ready_o && codec_write_i &&
                   !s_codec_access_err && (s_word_addr < MemoryWordCountValue)) begin
        s_mutable_valid_q[s_word_addr] <= 1'b1;
      end
    end
  end

  assign s_unused = ^s_addr[1:0] && 1'b0;
endmodule
