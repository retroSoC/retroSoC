// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of the Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`timescale 1ns / 1ps
`include "axi4_define.svh"

// Deterministic AXI4 memory target for SDIO standalone verification.
// It models the actual Mini-fabric contract: one transaction per direction,
// 32-bit data, INCR/FIXED bursts, and no outstanding IDs.
module sdio_axi_memory_responder #(
    parameter int DepthWords = 16384
) (
    input logic         clk_i,
    input logic         rst_n_i,
          axi4_if.slave axi4
);
  logic   [31:0] s_memory              [0:DepthWords-1];

  logic          s_read_active_q;
  logic   [31:0] s_read_addr_q;
  logic   [ 7:0] s_read_len_q;
  logic   [ 7:0] s_read_index_q;
  logic          s_read_error_q;
  logic          s_read_bad_id_q;
  logic          s_read_bad_last_q;
  logic          s_write_active_q;
  logic   [31:0] s_write_addr_q;
  logic   [ 7:0] s_write_len_q;
  logic   [ 7:0] s_write_index_q;
  logic          s_write_error_q;
  logic          s_write_bad_id_q;
  logic          s_aw_stall_q;
  logic          s_ar_stall_q;
  logic          s_w_stall_q;
  logic          s_b_stall_q;
  integer        s_read_error_address;
  integer        s_write_error_address;
  integer        s_aw_stall_cycles;
  integer        s_ar_stall_cycles;
  integer        s_w_stall_cycles;
  integer        s_b_stall_cycles;

  integer        read_burst_count;
  integer        write_burst_count;
  integer        max_read_beats;
  integer        max_write_beats;

  function automatic integer word_index(input logic [31:0] address_i);
    integer index;
    begin
      index = address_i >> 2;
      if ((index < 0) || (index >= DepthWords)) begin
        index = 0;
      end
      return index;
    end
  endfunction

  task automatic clear_memory;
    begin
      for (integer index = 0; index < DepthWords; index++) begin
        s_memory[index] = 32'd0;
      end
    end
  endtask

  task automatic write_word(input logic [31:0] address_i, input logic [31:0] data_i);
    begin
      s_memory[word_index(address_i)] = data_i;
    end
  endtask

  function automatic logic [31:0] read_word(input logic [31:0] address_i);
    begin
      read_word = s_memory[word_index(address_i)];
    end
  endfunction

  task automatic set_backpressure(input integer aw_cycles_i, input integer ar_cycles_i,
                                  input integer w_cycles_i, input integer b_cycles_i);
    begin
      s_aw_stall_cycles = (aw_cycles_i < 0) ? 0 : aw_cycles_i;
      s_ar_stall_cycles = (ar_cycles_i < 0) ? 0 : ar_cycles_i;
      s_w_stall_cycles  = (w_cycles_i < 0) ? 0 : w_cycles_i;
      s_b_stall_cycles  = (b_cycles_i < 0) ? 0 : b_cycles_i;
    end
  endtask

  task automatic inject_read_error(input integer address_i);
    begin
      s_read_error_address = address_i;
    end
  endtask

  task automatic inject_write_error(input integer address_i);
    begin
      s_write_error_address = address_i;
    end
  endtask

  task automatic inject_read_bad_id;
    begin
      s_read_bad_id_q = 1'b1;
    end
  endtask

  task automatic inject_read_bad_last;
    begin
      s_read_bad_last_q = 1'b1;
    end
  endtask

  task automatic inject_write_bad_id;
    begin
      s_write_bad_id_q = 1'b1;
    end
  endtask

  task automatic clear_errors;
    begin
      s_read_error_address  = -1;
      s_write_error_address = -1;
      s_read_bad_id_q       = 1'b0;
      s_write_bad_id_q      = 1'b0;
      s_read_bad_last_q     = 1'b0;
    end
  endtask

  assign axi4.arready = !s_read_active_q && !s_ar_stall_q;
  assign axi4.rid = s_read_bad_id_q ? '1 : '0;
  assign axi4.rdata = s_memory[word_index(
      s_read_addr_q+((axi4.arburst==`AXI4_BURST_TYPE_FIXED)?32'd0 : ({24'd0, s_read_index_q}<<2))
  )];
  assign axi4.rresp = (s_read_error_q) ? `AXI4_RESP_SLAVE_ERROR : `AXI4_RESP_OKAY;
  assign axi4.rlast = s_read_bad_last_q || ((s_read_index_q + 1'b1) >= (s_read_len_q + 1'b1));
  assign axi4.ruser = '0;
  assign axi4.rvalid = s_read_active_q;

  assign axi4.awready = !s_write_active_q && !axi4.bvalid && !s_aw_stall_q;
  assign axi4.wready = s_write_active_q && !s_w_stall_q;
  assign axi4.bid = s_write_bad_id_q ? '1 : '0;
  assign axi4.bresp = s_write_error_q ? `AXI4_RESP_SLAVE_ERROR : `AXI4_RESP_OKAY;
  assign axi4.buser = '0;
  assign axi4.bvalid = s_write_active_q && !s_b_stall_q &&
                       (s_write_index_q >= s_write_len_q + 1'b1);

  always @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_read_active_q   <= 1'b0;
      s_read_addr_q     <= 32'd0;
      s_read_len_q      <= 8'd0;
      s_read_index_q    <= 8'd0;
      s_read_error_q    <= 1'b0;
      s_read_bad_id_q   <= 1'b0;
      s_read_bad_last_q <= 1'b0;
      s_write_active_q  <= 1'b0;
      s_write_addr_q    <= 32'd0;
      s_write_len_q     <= 8'd0;
      s_write_index_q   <= 8'd0;
      s_write_error_q   <= 1'b0;
      s_write_bad_id_q  <= 1'b0;
      s_aw_stall_q      <= 1'b0;
      s_ar_stall_q      <= 1'b0;
      s_w_stall_q       <= 1'b0;
      s_b_stall_q       <= 1'b0;
      s_read_error_address  = -1;
      s_write_error_address = -1;
      s_aw_stall_cycles     = 0;
      s_ar_stall_cycles     = 0;
      s_w_stall_cycles      = 0;
      s_b_stall_cycles      = 0;
      read_burst_count      = 0;
      write_burst_count     = 0;
      max_read_beats        = 0;
      max_write_beats       = 0;
    end else begin
      if (s_aw_stall_cycles > 0) begin
        s_aw_stall_cycles = s_aw_stall_cycles - 1;
        s_aw_stall_q      = 1'b1;
      end else begin
        s_aw_stall_q = 1'b0;
      end
      if (s_ar_stall_cycles > 0) begin
        s_ar_stall_cycles = s_ar_stall_cycles - 1;
        s_ar_stall_q      = 1'b1;
      end else begin
        s_ar_stall_q = 1'b0;
      end
      if (s_w_stall_cycles > 0) begin
        s_w_stall_cycles = s_w_stall_cycles - 1;
        s_w_stall_q      = 1'b1;
      end else begin
        s_w_stall_q = 1'b0;
      end
      if (s_b_stall_cycles > 0) begin
        s_b_stall_cycles = s_b_stall_cycles - 1;
        s_b_stall_q      = 1'b1;
      end else begin
        s_b_stall_q = 1'b0;
      end

      if (axi4.arvalid && axi4.arready) begin
        s_read_active_q   = 1'b1;
        s_read_addr_q     = axi4.araddr;
        s_read_len_q      = axi4.arlen;
        s_read_index_q    = 8'd0;
        s_read_error_q    = (s_read_error_address >= 0) && (axi4.araddr == s_read_error_address);
        s_read_bad_last_q = 1'b0;
        read_burst_count  = read_burst_count + 1;
        if (({24'd0, axi4.arlen} + 32'd1) > max_read_beats) begin
          max_read_beats = {24'd0, axi4.arlen} + 32'd1;
        end
      end
      if (axi4.rvalid && axi4.rready) begin
        if (axi4.rlast) begin
          s_read_active_q = 1'b0;
          if (s_read_error_q) begin
            s_read_error_address = -1;
          end
        end else begin
          s_read_index_q = s_read_index_q + 1'b1;
        end
      end

      if (axi4.awvalid && axi4.awready) begin
        s_write_active_q  = 1'b1;
        s_write_addr_q    = axi4.awaddr;
        s_write_len_q     = axi4.awlen;
        s_write_index_q   = 8'd0;
        s_write_error_q   = (s_write_error_address >= 0) && (axi4.awaddr == s_write_error_address);
        write_burst_count = write_burst_count + 1;
        if (({24'd0, axi4.awlen} + 32'd1) > max_write_beats) begin
          max_write_beats = {24'd0, axi4.awlen} + 32'd1;
        end
      end
      if (axi4.wvalid && axi4.wready) begin
        for (integer byte_index = 0; byte_index < 4; byte_index++) begin
          if (axi4.wstrb[byte_index]) begin
            s_memory[word_index(s_write_addr_q + ((axi4.awburst == `AXI4_BURST_TYPE_FIXED)
                                      ? 32'd0
                                      : ({24'd0, s_write_index_q} << 2)))][byte_index*8+:8] <=
                axi4.wdata[byte_index*8+:8];
          end
        end
        s_write_index_q = s_write_index_q + 1'b1;
      end
      if (axi4.bvalid && axi4.bready) begin
        s_write_active_q = 1'b0;
        if (s_write_error_q) begin
          s_write_error_address = -1;
        end
      end
    end
  end

  initial begin
    clear_memory();
    clear_errors();
  end
endmodule
