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

// Small, protocol-oriented OPI PSRAM/one-clock HyperBus model.
//
// This model intentionally describes only the digital transaction contract:
// it is not an electrical, timing, refresh, or vendor-device model.
module opipsram_model #(
    parameter integer        MEMORY_BYTES          = 4096,
    parameter integer        INITIALIZE_MEMORY     = 1,
    parameter         [ 7:0] INITIAL_MEMORY_VALUE  = 8'h00,
    parameter integer        OPI_ADDRESS_BYTES     = 3,
    parameter integer        OPI_READ_DUMMY_BYTES  = 16,
    parameter integer        OPI_WRITE_DUMMY_BYTES = 16,
    parameter         [15:0] OPI_READ_COMMAND      = 16'hEE11,
    parameter         [15:0] OPI_WRITE_COMMAND     = 16'h12ED,
    parameter integer        HYPER_LATENCY         = 12,
    parameter integer        HYPER_RWDS_LATENCY    = 4,
    parameter integer        HYPER_RWDS_REQUEST    = 0,
    parameter integer        INJECT_MISSING_DEVICE = 0,
    parameter integer        INJECT_TIMEOUT        = 0,
    parameter integer        EXPECTED_DIVIDER      = 1
) (
    input logic       source_clk_i,
    input logic       ck_i,
    input logic       cs_n_i,
    input logic [7:0] dq_oe_i,
    input logic [7:0] dq_o_i,
    inout wire  [7:0] dq_io,
    input logic       rwds_oe_i,
    input logic       rwds_o_i,
    inout wire        rwds_io
);

  typedef enum logic [3:0] {
    ModelDetect     = 4'd0,
    ModelOpiAddr    = 4'd1,
    ModelOpiDummy   = 4'd2,
    ModelOpiWrite   = 4'd3,
    ModelOpiRead    = 4'd4,
    ModelHyperCa    = 4'd5,
    ModelHyperWait  = 4'd6,
    ModelHyperWrite = 4'd7,
    ModelHyperRead  = 4'd8
  } model_state_e;

  model_state_e        state;
  logic         [ 7:0] mem_array                  [0:MEMORY_BYTES-1];
  logic         [ 7:0] register_array             [           0:255];
  logic         [ 7:0] drive_data;
  logic                drive_enable;
  logic                rwds_drive_enable;
  logic                rwds_drive_data;
  logic                rwds_clock_output;
  logic         [15:0] command_shift;
  logic         [31:0] address_shift;
  logic         [31:0] hyper_word_address;
  logic         [31:0] current_address;
  logic         [ 7:0] ca_bytes                   [             0:5];
  logic         [ 7:0] transaction_length;
  logic         [ 7:0] byte_count;
  logic         [31:0] dummy_count;
  logic         [31:0] latency_count;
  logic                transaction_write;
  logic                transaction_register;
  logic                hyper_transaction;
  logic                read_first_edge_pending;
  logic                read_data_advance_pending;
  time                 last_tx_change_time;
  time                 last_source_edge_time;
  logic                source_edge_seen;
  integer              index;
  integer              transaction_count;
  integer              hyper_write_physical_count;
  integer              hyper_write_masked_count;

  assign dq_io = (drive_enable && (INJECT_MISSING_DEVICE == 0) &&
                  (INJECT_TIMEOUT == 0))
      ? drive_data : 8'hzz;
  assign rwds_io = (rwds_drive_enable && (INJECT_MISSING_DEVICE == 0) &&
                    (INJECT_TIMEOUT == 0))
      ? (rwds_clock_output ? ck_i : rwds_drive_data) : 1'bz;

  function automatic integer memory_index(input logic [31:0] address);
    integer address_value;
    begin
      if (MEMORY_BYTES <= 0) begin
        memory_index = 0;
      end else begin
        address_value = address;
        memory_index  = address_value % MEMORY_BYTES;
      end
    end
  endfunction

  function automatic logic [31:0] next_address(input logic [31:0] address);
    begin
      if (address == 32'hFFFF_FFFF) next_address = 32'd0;
      else next_address = address + 32'd1;
    end
  endfunction

  function automatic logic [7:0] read_byte(input logic [31:0] address);
    begin
      read_byte = transaction_register ? register_array[address[7:0]] :
          mem_array[memory_index(address)];
    end
  endfunction

  task automatic write_byte(input logic [31:0] address, input logic [7:0] value);
    begin
      if ((INJECT_MISSING_DEVICE == 0) && (INJECT_TIMEOUT == 0)) begin
        if (transaction_register) register_array[address[7:0]] = value;
        else mem_array[memory_index(address)] = value;
      end
    end
  endtask

  task automatic begin_read;
    begin
      drive_enable              = 1'b1;
      drive_data                = read_byte(current_address);
      rwds_drive_enable         = 1'b1;
      rwds_clock_output         = 1'b0;
      rwds_drive_data           = 1'b0;
      read_first_edge_pending   = 1'b1;
      read_data_advance_pending = 1'b0;
    end
  endtask

  task automatic begin_data_phase;
    begin
      byte_count = 8'd0;
      if (transaction_write) begin
        drive_enable      = 1'b0;
        rwds_drive_enable = 1'b0;
        rwds_clock_output = 1'b0;
        if (hyper_transaction) begin
          hyper_write_physical_count = 0;
          hyper_write_masked_count   = 0;
        end
        read_first_edge_pending   = 1'b0;
        read_data_advance_pending = 1'b0;
        state                     = hyper_transaction ? ModelHyperWrite : ModelOpiWrite;
      end else begin
        state = hyper_transaction ? ModelHyperRead : ModelOpiRead;
        begin_read();
      end
    end
  endtask

  always @(posedge source_clk_i) begin
    last_source_edge_time = $time;
    source_edge_seen      = 1'b1;
    if ((cs_n_i === 1'b0) && ((state == ModelOpiRead) || (state == ModelHyperRead))) begin
      if (read_data_advance_pending) begin
        read_data_advance_pending = 1'b0;
        current_address           = next_address(current_address);
        byte_count                = byte_count + 1'b1;
        drive_data                = read_byte(current_address);
      end
    end
  end

  always @(negedge source_clk_i) begin
    if ((cs_n_i === 1'b0) && ((state == ModelOpiRead) || (state == ModelHyperRead))) begin
      if (read_first_edge_pending) begin
        read_first_edge_pending = 1'b0;
      end else begin
        rwds_drive_data           = ~rwds_drive_data;
        read_data_advance_pending = 1'b1;
      end
    end
  end

  always @(dq_oe_i or dq_o_i) begin
    if ((cs_n_i === 1'b0) && (dq_oe_i === 8'hFF)) last_tx_change_time = $time;
  end

  always @(posedge ck_i or negedge ck_i) begin
    if (cs_n_i === 1'b0) begin
      // The model samples only after a complete source-clock setup interval;
      // same-timestamp transmit changes are a protocol race, not timing slack.
      if (((EXPECTED_DIVIDER == 1) && !source_edge_seen) ||
          ((EXPECTED_DIVIDER == 1) && (last_source_edge_time != $time)))
        $fatal(1, "opipsram_model: divider=1 CK edge is not aligned to the 2x source clock");
      if ((dq_oe_i === 8'hFF) && (last_tx_change_time == $time))
        $fatal(1, "opipsram_model: transmit DQ changed on the sampled CK edge (state=%0d)", state);
    end
  end

  always @(posedge cs_n_i or negedge cs_n_i or posedge ck_i or negedge ck_i) begin
    if (cs_n_i === 1'b1) begin
      state                     = ModelDetect;
      drive_enable              = 1'b0;
      rwds_drive_enable         = 1'b0;
      rwds_clock_output         = 1'b0;
      command_shift             = 16'd0;
      address_shift             = 32'd0;
      hyper_word_address        = 32'd0;
      current_address           = 32'd0;
      transaction_length        = 8'd0;
      byte_count                = 8'd0;
      dummy_count               = 32'd0;
      latency_count             = 32'd0;
      transaction_write         = 1'b0;
      transaction_register      = 1'b0;
      hyper_transaction         = 1'b0;
      read_first_edge_pending   = 1'b0;
      read_data_advance_pending = 1'b0;
    end else if (cs_n_i === 1'b0) begin
      if ((dq_oe_i === 8'hFF) && (state != ModelOpiRead) &&
          (state != ModelHyperRead) && (state != ModelOpiDummy) &&
          (state != ModelHyperWait)) begin
        if (state == ModelDetect) begin
          if (byte_count == 8'd0) begin
            command_shift = {8'd0, dq_o_i};
            if (dq_o_i == OPI_READ_COMMAND[7:0]) begin
              transaction_write    = 1'b0;
              transaction_register = 1'b0;
              hyper_transaction    = 1'b0;
              address_shift        = 32'd0;
              state                = ModelOpiAddr;
            end else if (dq_o_i == OPI_WRITE_COMMAND[7:0]) begin
              transaction_write    = 1'b1;
              transaction_register = 1'b0;
              hyper_transaction    = 1'b0;
              address_shift        = 32'd0;
              state                = ModelOpiAddr;
            end else begin
              byte_count = 8'd1;
            end
          end else begin
            command_shift = {command_shift[7:0], dq_o_i};
            byte_count    = 8'd0;
            if (command_shift == OPI_READ_COMMAND) begin
              transaction_write         = 1'b0;
              transaction_register      = 1'b0;
              hyper_transaction         = 1'b0;
              read_first_edge_pending   = 1'b0;
              read_data_advance_pending = 1'b0;
              address_shift             = 32'd0;
              state                     = ModelOpiAddr;
            end else if (command_shift == OPI_WRITE_COMMAND) begin
              transaction_write    = 1'b1;
              transaction_register = 1'b0;
              hyper_transaction    = 1'b0;
              address_shift        = 32'd0;
              state                = ModelOpiAddr;
            end else begin
              ca_bytes[0]          = command_shift[15:8];
              ca_bytes[1]          = command_shift[7:0];
              transaction_write    = !command_shift[15];
              transaction_register = command_shift[14];
              hyper_transaction    = 1'b1;
              byte_count           = 8'd2;
              if (HYPER_RWDS_REQUEST != 0) begin
                rwds_drive_enable = 1'b1;
                rwds_clock_output = 1'b0;
                rwds_drive_data   = 1'b1;
              end
              state = ModelHyperCa;
            end
          end
        end else if (state == ModelOpiAddr) begin
          address_shift = (address_shift << 8) | {24'd0, dq_o_i};
          if (({24'd0, byte_count} + 32'd1) >= OPI_ADDRESS_BYTES) begin
            if (OPI_ADDRESS_BYTES == 3) current_address = {8'd0, address_shift[23:0]};
            else current_address = address_shift;
            dummy_count = transaction_write ? OPI_WRITE_DUMMY_BYTES : OPI_READ_DUMMY_BYTES;
            byte_count  = 8'd0;
            if (dummy_count == 0) begin
              begin_data_phase();
            end else begin
              state = ModelOpiDummy;
            end
          end else begin
            byte_count = byte_count + 1'b1;
          end
        end else if ((state == ModelOpiWrite) || (state == ModelHyperWrite)) begin
          if (state == ModelHyperWrite) begin
            hyper_write_physical_count = hyper_write_physical_count + 1;
            if (rwds_io === 1'b1) hyper_write_masked_count = hyper_write_masked_count + 1;
            else write_byte(current_address, dq_o_i);
          end else begin
            write_byte(current_address, dq_o_i);
          end
          current_address = next_address(current_address);
          byte_count      = byte_count + 1'b1;
        end else if (state == ModelHyperCa) begin
          ca_bytes[byte_count[2:0]] = dq_o_i;
          if (byte_count == 8'd5) begin
            transaction_write = !ca_bytes[0][7];
            transaction_register = ca_bytes[0][6];
            hyper_word_address = {
              ca_bytes[0][4:0], ca_bytes[1], ca_bytes[2], ca_bytes[3], ca_bytes[5][2:0]
            };
            current_address = hyper_word_address << 1;
            transaction_length = 8'd0;
            latency_count = (transaction_register && transaction_write) ? 0 : HYPER_LATENCY;
            if ((HYPER_RWDS_REQUEST != 0) && (HYPER_RWDS_LATENCY > 0))
              latency_count = latency_count + HYPER_RWDS_LATENCY;
            byte_count = 8'd0;
            if (latency_count == 0) begin
              begin_data_phase();
            end else begin
              state = ModelHyperWait;
            end
          end else begin
            byte_count = byte_count + 1'b1;
          end
        end
      end else if (state == ModelOpiDummy) begin
        if (transaction_write && (dq_oe_i === 8'hFF)) begin
          begin_data_phase();
          write_byte(current_address, dq_o_i);
          current_address = next_address(current_address);
          byte_count      = 8'd1;
        end else begin
          if (dummy_count > 0) dummy_count = dummy_count - 1'b1;
          if (dummy_count <= 1) begin
            begin_data_phase();
          end
        end
      end else if (state == ModelHyperWait) begin
        if (latency_count > 0) latency_count = latency_count - 1'b1;
        if (latency_count <= 1) begin
          begin_data_phase();
        end
      end

    end
  end

  initial begin
    if (MEMORY_BYTES <= 0) $fatal(1, "opipsram_model MEMORY_BYTES must be positive");
    if ((OPI_ADDRESS_BYTES < 3) || (OPI_ADDRESS_BYTES > 4))
      $fatal(1, "opipsram_model OPI_ADDRESS_BYTES must be 3 or 4");
    if ((OPI_READ_DUMMY_BYTES < 0) || (OPI_WRITE_DUMMY_BYTES < 0))
      $fatal(1, "opipsram_model dummy cycles must be non-negative");
    if ((HYPER_LATENCY < 0) || (HYPER_RWDS_LATENCY < 0))
      $fatal(1, "opipsram_model latency must be non-negative");
    if (EXPECTED_DIVIDER < 1) $fatal(1, "opipsram_model EXPECTED_DIVIDER must be positive");
    state                      = ModelDetect;
    drive_enable               = 1'b0;
    rwds_drive_enable          = 1'b0;
    rwds_clock_output          = 1'b0;
    command_shift              = 16'd0;
    address_shift              = 32'd0;
    current_address            = 32'd0;
    transaction_length         = 8'd0;
    byte_count                 = 8'd0;
    dummy_count                = 32'd0;
    latency_count              = 32'd0;
    transaction_write          = 1'b0;
    transaction_register       = 1'b0;
    hyper_transaction          = 1'b0;
    last_tx_change_time        = 0;
    last_source_edge_time      = 0;
    source_edge_seen           = 1'b0;
    transaction_count          = 0;
    hyper_write_physical_count = 0;
    hyper_write_masked_count   = 0;
    drive_data                 = 8'd0;
    rwds_drive_data            = 1'b0;
    for (index = 0; index < 6; index = index + 1) ca_bytes[index] = 8'd0;
    for (index = 0; index < 256; index = index + 1) register_array[index] = 8'd0;
    if (INITIALIZE_MEMORY != 0) begin
      for (index = 0; index < MEMORY_BYTES; index = index + 1)
      mem_array[index] = INITIAL_MEMORY_VALUE;
    end
  end

  always @(negedge cs_n_i) begin
    transaction_count = transaction_count + 1;
  end

endmodule
