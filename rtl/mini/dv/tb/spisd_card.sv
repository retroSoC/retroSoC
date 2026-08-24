// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.
// See LICENSE for the complete license text.

`timescale 1ns / 1ps

module spisd_card #(
    parameter int unsigned StorageBlocks  = 4,
    parameter int unsigned Acmd41Attempts = 2
) (
    // verilog_format: off -- preserve the reviewed SPI-model port alignment
    input  logic  sck,
    input  logic  cs_n,
    input  logic  mosi,
    output logic  miso,
    input  logic  power_on
    // verilog_format: on
);
  import spisd_pkg::*;

  localparam int unsigned BlockSize = 512;
  localparam int unsigned TxDepth = BlockSize + 16;

  localparam logic [5:0] Cmd0 = 6'd0;
  localparam logic [5:0] Cmd6 = 6'd6;
  localparam logic [5:0] Cmd8 = 6'd8;
  localparam logic [5:0] Cmd9 = 6'd9;
  localparam logic [5:0] Cmd12 = 6'd12;
  localparam logic [5:0] Cmd16 = 6'd16;
  localparam logic [5:0] Cmd17 = 6'd17;
  localparam logic [5:0] Cmd24 = 6'd24;
  localparam logic [5:0] Cmd55 = 6'd55;
  localparam logic [5:0] Cmd58 = 6'd58;
  localparam logic [5:0] Acmd41 = 6'd41;

  // These controls are intentionally visible to testbenches through hierarchy.
  logic          force_command_timeout;
  logic          force_data_crc_error;
  logic          force_write_reject;

  logic          sck_q;
  logic          power_on_q;
  logic          initialized;
  logic          app_command;
  logic   [ 7:0] rx_shift;
  logic   [ 2:0] rx_bit_count;
  logic   [ 2:0] command_byte_count;
  logic   [ 5:0] command_index;
  logic   [31:0] command_argument;
  logic   [ 7:0] tx_data               [                  0:TxDepth-1];
  integer        tx_read_index;
  integer        tx_write_index;
  logic   [ 2:0] tx_bit_count;
  logic   [ 7:0] storage               [0:(StorageBlocks*BlockSize)-1];
  logic   [ 7:0] csd                   [                         0:15];
  integer        acmd41_count;
  logic   [ 2:0] write_state;
  integer        write_byte_count;
  integer        write_block;
  logic   [15:0] write_crc;
  logic   [ 7:0] write_crc_high;

  task automatic queue_clear;
    begin
      tx_read_index  = 0;
      tx_write_index = 0;
      tx_bit_count   = 3'd0;
    end
  endtask

  task automatic queue_byte(input logic [7:0] data);
    begin
      if (tx_write_index >= TxDepth) $fatal(1, "SPI-SD model transmit queue overflow");
      tx_data[tx_write_index] = data;
      tx_write_index          = tx_write_index + 1;
    end
  endtask

  task automatic queue_r1(input logic [7:0] response);
    begin
      queue_clear();
      queue_byte(8'hFF);
      queue_byte(response);
    end
  endtask

  task automatic queue_data_block(input integer block_index, input integer byte_count,
                                  input logic use_csd);
    logic [15:0] crc;
    logic [ 7:0] data;
    begin
      queue_clear();
      queue_byte(8'hFF);
      queue_byte(initialized ? 8'h00 : 8'h01);
      queue_byte(8'hFF);
      queue_byte(8'hFE);
      crc = 16'd0;
      for (int index = 0; index < byte_count; index++) begin
        if (use_csd) data = csd[index];
        else data = storage[(block_index*BlockSize)+index];
        queue_byte(data);
        crc = spisd_crc16_byte(crc, data);
      end
      if (force_data_crc_error) crc = crc ^ 16'h0001;
      queue_byte(crc[15:8]);
      queue_byte(crc[7:0]);
    end
  endtask

  task automatic process_command(input logic [5:0] index, input logic [31:0] argument);
    logic   [ 7:0] r1;
    logic   [ 7:0] status_data;
    logic   [15:0] data_crc;
    integer        block_index;
    logic          was_app_command;
    begin
      if (force_command_timeout) begin
        queue_clear();
      end else begin
        r1              = initialized ? 8'h00 : 8'h01;
        was_app_command = app_command;
        app_command     = 1'b0;
        unique case (index)
          Cmd0: begin
            initialized  = 1'b0;
            app_command  = 1'b0;
            acmd41_count = 0;
            queue_r1(8'h01);
          end
          Cmd8: begin
            queue_clear();
            queue_byte(8'hFF);
            queue_byte(r1);
            queue_byte(8'h00);
            queue_byte(8'h00);
            queue_byte(8'h01);
            queue_byte(argument[7:0]);
          end
          Cmd9: begin
            queue_data_block(0, 16, 1'b1);
          end
          Cmd12: begin
            queue_clear();
            queue_byte(8'hFF);
            queue_byte(r1);
            queue_byte(8'h00);
            queue_byte(8'h00);
            queue_byte(8'hFF);
          end
          Cmd16: begin
            queue_r1((argument == BlockSize) ? r1 : (r1 | 8'h40));
          end
          Cmd17: begin
            block_index = initialized ? (argument % StorageBlocks) : 0;
            if (initialized) queue_data_block(block_index, BlockSize, 1'b0);
            else queue_r1(8'h05);
          end
          Cmd24: begin
            if (initialized) begin
              queue_r1(8'h00);
              write_state      = 3'd1;
              write_byte_count = 0;
              write_block      = argument % StorageBlocks;
              write_crc        = 16'd0;
            end else begin
              queue_r1(8'h05);
            end
          end
          Cmd55: begin
            app_command = 1'b1;
            queue_r1(r1);
          end
          Acmd41: begin
            if (was_app_command) begin
              if (acmd41_count < Acmd41Attempts) acmd41_count = acmd41_count + 1;
              if (acmd41_count >= Acmd41Attempts) initialized = 1'b1;
              queue_r1(initialized ? 8'h00 : 8'h01);
            end else begin
              queue_r1(r1 | 8'h04);
            end
          end
          Cmd58: begin
            queue_clear();
            queue_byte(8'hFF);
            queue_byte(r1);
            queue_byte(initialized ? 8'hC0 : 8'h40);
            queue_byte(8'hFF);
            queue_byte(8'h80);
            queue_byte(8'h00);
          end
          Cmd6: begin
            queue_clear();
            queue_byte(8'hFF);
            queue_byte(r1);
            queue_byte(8'hFF);
            queue_byte(8'hFE);
            data_crc = 16'd0;
            for (int byte_index = 0; byte_index < 64; byte_index++) begin
              status_data = (byte_index == 16) ? 8'h01 : 8'h00;
              queue_byte(status_data);
              data_crc = spisd_crc16_byte(data_crc, status_data);
            end
            if (force_data_crc_error) data_crc = data_crc ^ 16'h0001;
            queue_byte(data_crc[15:8]);
            queue_byte(data_crc[7:0]);
          end
          default: queue_r1(r1 | 8'h04);
        endcase
      end
    end
  endtask

  task automatic process_write_byte(input logic [7:0] data);
    begin
      unique case (write_state)
        3'd1: begin
          if (data == 8'hFE) begin
            write_state      = 3'd2;
            write_byte_count = 0;
            write_crc        = 16'd0;
          end
        end
        3'd2: begin
          storage[(write_block*BlockSize)+write_byte_count] = data;
          write_crc                                         = spisd_crc16_byte(write_crc, data);
          if (write_byte_count == (BlockSize - 1)) write_state = 3'd3;
          else write_byte_count = write_byte_count + 1;
        end
        3'd3: begin
          write_crc_high = data;
          write_state    = 3'd4;
        end
        3'd4: begin
          queue_clear();
          if (force_write_reject || ({write_crc_high, data} != write_crc)) begin
            queue_byte(8'h0B);
          end else begin
            queue_byte(8'h05);
            queue_byte(8'h00);
            queue_byte(8'h00);
            queue_byte(8'hFF);
          end
          write_state = 3'd0;
        end
        default: write_state = 3'd0;
      endcase
    end
  endtask

  task automatic process_rx_byte(input logic [7:0] data);
    begin
      if ((write_state != 3'd0) && (tx_read_index >= tx_write_index)) begin
        process_write_byte(data);
      end else if (tx_read_index >= tx_write_index) begin
        unique case (command_byte_count)
          3'd0: begin
            if (data[7:6] == 2'b01) begin
              command_index      = data[5:0];
              command_byte_count = 3'd1;
            end
          end
          3'd1, 3'd2, 3'd3, 3'd4: begin
            command_argument   = {command_argument[23:0], data};
            command_byte_count = command_byte_count + 1'b1;
          end
          3'd5: begin
            command_byte_count = 3'd0;
            process_command(command_index, command_argument);
          end
          default: command_byte_count = 3'd0;
        endcase
      end
    end
  endtask

  task automatic transaction_reset;
    begin
      miso               = 1'b1;
      rx_shift           = 8'hFF;
      rx_bit_count       = 3'd0;
      command_byte_count = 3'd0;
      command_argument   = 32'd0;
      tx_read_index      = 0;
      tx_write_index     = 0;
      tx_bit_count       = 3'd0;
      write_state        = 3'd0;
      write_byte_count   = 0;
      write_crc          = 16'd0;
      write_crc_high     = 8'd0;
    end
  endtask

  task automatic model_reset;
    begin
      initialized           = 1'b0;
      app_command           = 1'b0;
      acmd41_count          = 0;
      force_command_timeout = 1'b0;
      force_data_crc_error  = 1'b0;
      force_write_reject    = 1'b0;
      transaction_reset();
    end
  endtask

  initial begin
    sck_q      = 1'b0;
    power_on_q = 1'b0;
    csd[0]     = 8'h40;
    csd[1]     = 8'h0E;
    csd[2]     = 8'h00;
    csd[3]     = 8'h32;
    csd[4]     = 8'h5B;
    csd[5]     = 8'h59;
    csd[6]     = 8'h00;
    csd[7]     = 8'h00;
    csd[8]     = 8'h1F;
    csd[9]     = 8'h7F;
    csd[10]    = 8'h80;
    csd[11]    = 8'h0A;
    csd[12]    = 8'h40;
    csd[13]    = 8'h00;
    csd[14]    = 8'h00;
    csd[15]    = 8'h00;
    for (int index = 0; index < (StorageBlocks * BlockSize); index++) begin
      storage[index] = index[7:0];
    end
    model_reset();
  end

  // A single event process avoids races between independent edge processes in
  // this behavioral model. The card samples MOSI on rising edges and changes
  // MISO only on falling edges, matching SPI mode 0.
  always @(sck or cs_n or power_on) begin
    if (power_on && !power_on_q) model_reset();
    if (cs_n) begin
      transaction_reset();
    end else if (!sck_q && sck) begin
      rx_shift = {rx_shift[6:0], mosi};
      if (rx_bit_count == 3'd7) begin
        process_rx_byte(rx_shift);
        rx_bit_count = 3'd0;
      end else begin
        rx_bit_count = rx_bit_count + 1'b1;
      end
    end else if (sck_q && !sck) begin
      if (tx_read_index < tx_write_index) begin
        miso = tx_data[tx_read_index][7-tx_bit_count];
        if (tx_bit_count == 3'd7) begin
          tx_bit_count  = 3'd0;
          tx_read_index = tx_read_index + 1;
        end else begin
          tx_bit_count = tx_bit_count + 1'b1;
        end
      end else begin
        miso = 1'b1;
      end
    end
    sck_q      = sck;
    power_on_q = power_on;
  end

endmodule
