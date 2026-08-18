// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.


// Zero-delay SDRAM model for the Verilator performance harness.
//
// The production Icarus testbench uses the Micron timing model. Verilator's
// no-timing mode cannot elaborate that tri-state timing model, so this model
// implements the controller-visible ACT/READ/WRITE burst protocol instead.
module sdram_verilator_model (
    input logic        clk_i,
    input logic        cke_i,
    input logic        cs_n_i,
    input logic        ras_n_i,
    input logic        cas_n_i,
    input logic        we_n_i,
    input logic [ 1:0] ba_i,
    // The Micron x16 model used by Icarus exposes a 12-bit row address.
    // verilator lint_off UNUSEDSIGNAL
    input logic [12:0] addr_i,
    // verilator lint_on UNUSEDSIGNAL
    input logic [ 1:0] dqm_i,
    inout wire  [15:0] dq_io
);

  localparam int unsigned MEMORY_WORDS = 1 << 25;
  localparam logic [3:0] CMD_MRS = 4'b0000;
  localparam logic [3:0] CMD_ACTIVE = 4'b0011;
  localparam logic [3:0] CMD_READ = 4'b0101;
  localparam logic [3:0] CMD_WRITE = 4'b0100;

  logic [12:0] s_row_q          [             0:3];
  logic [15:0] s_memory         [0:MEMORY_WORDS-1];
  logic [ 3:0] s_burst_len_q;
  logic [ 3:0] s_write_left_q;
  logic [24:0] s_write_addr_q;
  logic [ 3:0] s_read_left_q;
  logic        s_read_pending_q;
  logic        s_read_drive_q;
  logic [24:0] s_read_addr_q;
  logic [15:0] s_read_data_q;
  logic [ 3:0] s_command;

  assign s_command = {cs_n_i, ras_n_i, cas_n_i, we_n_i};
  assign dq_io     = s_read_drive_q ? s_read_data_q : 'z;

  initial begin
    s_burst_len_q    = 4'd2;
    s_write_left_q   = 4'd0;
    s_read_left_q    = 4'd0;
    s_read_pending_q = 1'b0;
    s_read_drive_q   = 1'b0;
    s_write_addr_q   = '0;
    s_read_addr_q    = '0;
    s_read_data_q    = '0;
    for (int unsigned bank = 0; bank < 4; ++bank) begin
      s_row_q[bank] = '0;
    end
  end

  function automatic logic [24:0] sdram_address(input logic [1:0] bank, input logic [12:0] row,
                                                input logic [9:0] column);
    sdram_address = {bank, row, column};
  endfunction

  function automatic logic [3:0] mrs_burst_length(input logic [2:0] encoded);
    begin
      unique case (encoded)
        3'b011:  return 4'd8;
        3'b010:  return 4'd4;
        default: return 4'd2;
      endcase
    end
  endfunction

  task automatic write_beat(input logic [24:0] address);
    begin
      if (!dqm_i[0]) s_memory[address][7:0] <= dq_io[7:0];
      if (!dqm_i[1]) s_memory[address][15:8] <= dq_io[15:8];
    end
  endtask

  always_ff @(posedge clk_i) begin
    if (cke_i) begin
      if (s_read_drive_q) begin
        if (s_read_left_q != 4'd0) begin
          s_read_data_q <= s_memory[s_read_addr_q];
          s_read_addr_q <= s_read_addr_q + 1'b1;
          s_read_left_q <= s_read_left_q - 4'd1;
        end else begin
          s_read_drive_q <= 1'b0;
        end
      end else if (s_read_pending_q) begin
        s_read_data_q    <= s_memory[s_read_addr_q];
        s_read_addr_q    <= s_read_addr_q + 1'b1;
        s_read_left_q    <= s_read_left_q - 4'd1;
        s_read_pending_q <= 1'b0;
        s_read_drive_q   <= 1'b1;
      end

      if (s_write_left_q != 4'd0) begin
        write_beat(s_write_addr_q);
        s_write_addr_q <= s_write_addr_q + 1'b1;
        s_write_left_q <= s_write_left_q - 4'd1;
      end

      unique case (s_command)
        CMD_MRS: begin
          s_burst_len_q <= mrs_burst_length(addr_i[2:0]);
        end
        CMD_ACTIVE: begin
          s_row_q[ba_i] <= addr_i[12:0];
        end
        CMD_READ: begin
          s_read_addr_q    <= sdram_address(ba_i, s_row_q[ba_i], addr_i[9:0]);
          s_read_left_q    <= s_burst_len_q;
          s_read_pending_q <= 1'b1;
        end
        CMD_WRITE: begin
          write_beat(sdram_address(ba_i, s_row_q[ba_i], addr_i[9:0]));
          s_write_addr_q <= sdram_address(ba_i, s_row_q[ba_i], addr_i[9:0]) + 1'b1;
          s_write_left_q <= s_burst_len_q - 4'd1;
        end
        default: begin
        end
      endcase
    end
  end

endmodule
