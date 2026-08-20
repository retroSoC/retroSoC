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

// Verification-only native SD/SDIO card model.  The model intentionally
// implements only public command/data behavior exercised by this repository;
// it is not a normative-specification replacement.
module sdio_native_card_model #(
    parameter bit SdioOnly      = 1'b0,
    parameter bit HighCapacity  = 1'b1,
    parameter int BlockBytes    = 512,
    parameter int BlockCount    = 128,
    parameter int FunctionCount = 1,
    parameter int FunctionBytes = 4096,
    parameter int BusyCycles    = 2
) (
    input  logic       rst_n_i,
    input  logic       sck_i,
    input  logic       cmd_oe_i,
    input  logic       cmd_do_i,
    output logic       cmd_do_o,
    input  logic [3:0] dat_oe_i,
    input  logic [3:0] dat_do_i,
    output logic [3:0] dat_do_o,
    output logic       irq_o
);
  localparam int MemoryBytes = BlockBytes * BlockCount;
  localparam int FunctionStorageBytes = FunctionCount * FunctionBytes;

  typedef enum logic [3:0] {
    DataIdle,
    DataDelay,
    DataToken,
    DataPayload,
    DataCrc,
    WriteWait,
    WritePayload,
    WriteCrc,
    WriteResponse,
    WriteBusy
  } data_state_e;

  logic        [  7:0] s_memory                 [         0:MemoryBytes-1];
  logic        [  7:0] s_function_memory        [0:FunctionStorageBytes-1];

  logic        [ 47:0] s_cmd_shift;
  integer              s_cmd_bits;
  logic                s_cmd_response_active;
  logic        [135:0] s_cmd_response;
  integer              s_cmd_response_length;
  integer              s_cmd_response_index;
  integer              s_cmd_response_delay;
  integer              s_response_delay;
  integer              s_data_delay_cfg;
  logic                s_inject_crc_error;
  logic                s_inject_timeout;
  logic                s_inject_write_error;
  logic                s_next_cmd_crc_error;

  logic        [  5:0] s_last_cmd;
  logic        [ 31:0] s_last_arg;
  logic                s_last_cmd_write;
  logic                s_last_cmd_data;
  logic                s_pending_busy;
  integer              s_busy_count;

  data_state_e         s_data_state;
  logic                s_data_width4;
  logic                s_data_fixed;
  integer              s_data_address;
  integer              s_data_bytes;
  integer              s_data_byte_index;
  integer              s_data_bit_index;
  integer              s_data_nibble_index;
  integer              s_data_crc_index;
  integer              s_data_delay;
  logic        [ 15:0] s_read_crc;
  logic        [ 15:0] s_read_crc_lane          [                     0:3];
  logic        [ 15:0] s_write_crc;
  logic        [ 15:0] s_write_crc_lane         [                     0:3];
  logic        [ 15:0] s_received_crc;
  logic        [ 15:0] s_received_crc_lane      [                     0:3];
  logic        [  7:0] s_write_byte;
  logic        [  7:0] s_write_byte_lane        [                     0:3];
  integer              s_write_bit_count;
  integer              s_write_nibble_count;
  logic        [  4:0] s_write_response_token;
  integer              s_write_response_index;
  logic                s_write_response_started;
  logic                s_data_crc_error;
  logic                s_data_timeout;
  logic                s_irq_pending;
  logic        [  2:0] s_cmd_function;
  logic        [ 31:0] s_cmd_address;
  logic                s_cmd_fixed_address;
  integer              s_cmd_count;

  function automatic logic [6:0] crc7_40(input logic [39:0] data_i);
    logic [6:0] crc;
    logic       feedback;
    begin
      crc = 7'd0;
      for (integer index = 39; index >= 0; index--) begin
        feedback = data_i[index] ^ crc[6];
        crc      = {crc[5:0], 1'b0};
        if (feedback) begin
          crc = crc ^ 7'h09;
        end
      end
      return crc;
    end
  endfunction

  function automatic logic [6:0] crc7_next(input logic [6:0] crc_i, input logic data_i);
    logic feedback;
    begin
      feedback  = data_i ^ crc_i[6];
      crc7_next = {crc_i[5:0], 1'b0};
      if (feedback) begin
        crc7_next = crc7_next ^ 7'h09;
      end
    end
  endfunction

  function automatic logic [15:0] crc16_next(input logic [15:0] crc_i, input logic data_i);
    logic feedback;
    begin
      feedback   = data_i ^ crc_i[15];
      crc16_next = {crc_i[14:0], 1'b0};
      if (feedback) begin
        crc16_next = crc16_next ^ 16'h1021;
      end
    end
  endfunction

  function automatic integer card_address(input logic [31:0] argument_i);
    integer address;
    begin
      if (HighCapacity) begin
        address = argument_i * BlockBytes;
      end else begin
        address = argument_i;
      end
      if (address < 0) begin
        address = 0;
      end
      if (address >= MemoryBytes) begin
        address = MemoryBytes - 1;
      end
      return address;
    end
  endfunction

  function automatic integer function_address(input logic [2:0] function_i,
                                              input logic [31:0] address_i);
    integer address;
    begin
      address = (function_i * FunctionBytes) + address_i;
      if (address < 0) begin
        address = 0;
      end
      if (address >= FunctionStorageBytes) begin
        address = FunctionStorageBytes - 1;
      end
      return address;
    end
  endfunction

  function automatic logic command_frame_valid(input logic [47:0] frame_i);
    begin
      command_frame_valid = (frame_i[47:46] == 2'b01) &&
                            (frame_i[0] == 1'b1) &&
                            (frame_i[7:1] == crc7_40(frame_i[47:8]));
    end
  endfunction

  function automatic logic [7:0] backing_read(input integer address_i);
    integer address;
    begin
      address = address_i;
      if (address < 0) begin
        address = 0;
      end
      if (SdioOnly) begin
        if (address >= FunctionStorageBytes) begin
          address = FunctionStorageBytes - 1;
        end
        backing_read = s_function_memory[address];
      end else begin
        if (address >= MemoryBytes) begin
          address = MemoryBytes - 1;
        end
        backing_read = s_memory[address];
      end
    end
  endfunction

  task automatic backing_write(input integer address_i, input logic [7:0] data_i);
    integer address;
    begin
      address = address_i;
      if (address < 0) begin
        address = 0;
      end
      if (SdioOnly) begin
        if (address < FunctionStorageBytes) begin
          s_function_memory[address] = data_i;
        end
      end else if (address < MemoryBytes) begin
        s_memory[address] = data_i;
      end
    end
  endtask

  task automatic set_response_delay(input integer cycles_i);
    begin
      s_response_delay = (cycles_i < 0) ? 0 : cycles_i;
    end
  endtask

  task automatic set_data_delay(input integer cycles_i);
    begin
      s_data_delay_cfg = (cycles_i < 0) ? 0 : cycles_i;
    end
  endtask

  task automatic inject_next_crc_error;
    begin
      s_inject_crc_error = 1'b1;
    end
  endtask

  task automatic inject_next_timeout;
    begin
      s_inject_timeout = 1'b1;
    end
  endtask

  task automatic inject_next_write_error;
    begin
      s_inject_write_error = 1'b1;
    end
  endtask

  task automatic fill_memory(input logic [7:0] seed_i);
    begin
      if (SdioOnly) begin
        for (integer index = 0; index < FunctionStorageBytes; index++) begin
          s_function_memory[index] = seed_i + index[7:0];
        end
      end else begin
        for (integer index = 0; index < MemoryBytes; index++) begin
          s_memory[index] = seed_i + index[7:0];
        end
      end
    end
  endtask

  task automatic write_backing(input integer address_i, input logic [7:0] data_i);
    begin
      backing_write(address_i, data_i);
    end
  endtask

  function automatic logic [7:0] read_backing(input integer address_i);
    begin
      read_backing = backing_read(address_i);
    end
  endfunction

  task automatic set_irq;
    begin
      s_irq_pending = 1'b1;
      dat_do_o[1]   = 1'b0;
      irq_o         = 1'b1;
    end
  endtask

  task automatic clear_irq;
    begin
      s_irq_pending = 1'b0;
      dat_do_o[1]   = 1'b1;
      irq_o         = 1'b0;
    end
  endtask

  task automatic arm_read(input integer address_i, input integer bytes_i, input logic width4_i,
                          input logic fixed_address_i);
    begin
      s_data_address      = address_i;
      s_data_bytes        = (bytes_i < 1) ? 1 : bytes_i;
      s_data_width4       = width4_i;
      s_data_fixed        = fixed_address_i;
      s_data_byte_index   = 0;
      s_data_bit_index    = 0;
      s_data_nibble_index = 0;
      s_data_crc_index    = 0;
      s_read_crc          = 16'd0;
      s_received_crc      = 16'd0;
      for (integer lane = 0; lane < 4; lane++) begin
        s_read_crc_lane[lane]     = 16'd0;
        s_received_crc_lane[lane] = 16'd0;
      end
      s_data_delay = s_data_delay_cfg;
      if (s_inject_timeout) begin
        s_data_state     = DataIdle;
        s_data_timeout   = 1'b1;
        s_inject_timeout = 1'b0;
      end else begin
        s_data_state = DataDelay;
      end
      dat_do_o = 4'b1111;
    end
  endtask

  task automatic arm_write(input integer address_i, input integer bytes_i, input logic width4_i,
                           input logic fixed_address_i);
    begin
      s_data_address           = address_i;
      s_data_bytes             = (bytes_i < 1) ? 1 : bytes_i;
      s_data_width4            = width4_i;
      s_data_fixed             = fixed_address_i;
      s_data_byte_index        = 0;
      s_data_bit_index         = 0;
      s_data_nibble_index      = 0;
      s_data_crc_index         = 0;
      s_write_byte             = 8'd0;
      s_write_bit_count        = 0;
      s_write_nibble_count     = 0;
      s_write_response_started = 1'b0;
      for (integer lane = 0; lane < 4; lane++) begin
        s_write_byte_lane[lane] = 8'd0;
      end
      s_write_crc    = 16'd0;
      s_received_crc = 16'd0;
      for (integer lane = 0; lane < 4; lane++) begin
        s_write_crc_lane[lane]    = 16'd0;
        s_received_crc_lane[lane] = 16'd0;
      end
      s_data_crc_error = 1'b0;
      s_data_timeout   = 1'b0;
      s_data_state     = WriteWait;
      dat_do_o         = 4'b1111;
    end
  endtask

  task automatic make_r1_response(input logic [5:0] index_i, input logic [31:0] payload_i,
                                  input logic crc_error_i);
    logic [39:0] body;
    logic [ 6:0] crc;
    begin
      body = {1'b0, 1'b1, index_i, payload_i};
      crc  = crc7_40(body);
      if (crc_error_i) begin
        crc[0] = ~crc[0];
      end
      s_cmd_response        = '0;
      s_cmd_response[47:0]  = {body, crc, 1'b1};
      s_cmd_response_length = 48;
    end
  endtask

  task automatic make_r2_response(input logic [127:0] payload_i);
    logic [127:0] body;
    logic [  6:0] crc;
    begin
      body = payload_i;
      crc  = 7'd0;
      for (integer index = 127; index >= 0; index--) begin
        crc = crc7_next(crc, body[index]);
      end
      s_cmd_response        = '0;
      s_cmd_response[135:0] = {body, crc, 1'b1};
      s_cmd_response_length = 136;
    end
  endtask

  task automatic queue_response(input logic [5:0] index_i, input logic [31:0] payload_i,
                                input logic r2_i, input logic crc_error_i);
    begin
      if (r2_i) begin
        make_r2_response({96'd0, payload_i});
      end else begin
        make_r1_response(index_i, payload_i, crc_error_i);
      end
      s_cmd_response_active = 1'b1;
      s_cmd_response_index  = 0;
      s_cmd_response_delay  = s_response_delay;
      s_cmd_response[0]     = 1'b1;
      if (s_cmd_response_delay == 0) begin
        cmd_do_o = s_cmd_response[s_cmd_response_length-1];
      end else begin
        cmd_do_o = 1'b1;
      end
    end
  endtask

  task automatic command_received(input logic [47:0] frame_i);
    logic   [ 5:0] index;
    logic   [31:0] argument;
    logic   [ 6:0] expected_crc;
    logic   [39:0] body;
    logic   [31:0] response_payload;
    integer        address;
    begin
      index               = frame_i[45:40];
      argument            = frame_i[39:8];
      body                = frame_i[47:8];
      expected_crc        = crc7_40(body);
      s_last_cmd          = index;
      s_last_arg          = argument;
      s_last_cmd_data     = 1'b0;
      s_last_cmd_write    = 1'b0;
      s_cmd_function      = argument[30:28];
      s_cmd_address       = {15'd0, argument[25:9]};
      s_cmd_fixed_address = !argument[26];
      s_cmd_count         = {23'd0, argument[8:0]};
      if (s_cmd_count == 0) begin
        s_cmd_count = argument[27] ? 512 : 1;
      end
      if (s_inject_timeout || (frame_i[7:1] != expected_crc) || (frame_i[0] != 1'b1)) begin
        s_inject_timeout      = 1'b0;
        s_cmd_response_active = 1'b0;
        cmd_do_o              = 1'b1;
      end else if (SdioOnly) begin
        response_payload = 32'd0;
        case (index)
          6'd5: begin
            response_payload = 32'h80FF_8000;
            queue_response(index, response_payload, 1'b0, 1'b0);
          end
          6'd52: begin
            if (argument[31]) begin
              backing_write(function_address(argument[30:28], {15'd0, argument[25:9]}),
                            argument[7:0]);
              response_payload[7:0] = argument[7:0];
            end else begin
              response_payload[7:0] =
                  backing_read(function_address(argument[30:28], {15'd0, argument[25:9]}));
            end
            response_payload[31:28] = {1'b0, argument[30:28]};
            queue_response(index, response_payload, 1'b0, s_inject_crc_error);
            s_inject_crc_error = 1'b0;
          end
          6'd53: begin
            s_last_cmd_data         = 1'b1;
            s_last_cmd_write        = argument[31];
            response_payload[7:0]   = 8'h00;
            response_payload[31:28] = {1'b0, argument[30:28]};
            queue_response(index, response_payload, 1'b0, s_inject_crc_error);
            s_inject_crc_error = 1'b0;
          end
          default: begin
            queue_response(index, 32'h0000_0100, 1'b0, s_inject_crc_error);
            s_inject_crc_error = 1'b0;
          end
        endcase
      end else begin
        response_payload = 32'h0000_0100;
        case (index)
          6'd0: begin
            s_cmd_response_active = 1'b0;
            cmd_do_o              = 1'b1;
          end
          6'd2, 6'd9: begin
            make_r2_response(index == 6'd9 ? {HighCapacity ? 1'b0 : 1'b0, 127'd0} : 128'd0);
            s_cmd_response_active = 1'b1;
            s_cmd_response_index  = 0;
            s_cmd_response_delay  = s_response_delay;
            cmd_do_o              = (s_cmd_response_delay == 0) ? s_cmd_response[135] : 1'b1;
          end
          6'd8: begin
            queue_response(index, argument, 1'b0, s_inject_crc_error);
            s_inject_crc_error = 1'b0;
          end
          6'd3: begin
            queue_response(index, 32'h0001_0000, 1'b0, s_inject_crc_error);
            s_inject_crc_error = 1'b0;
          end
          6'd7, 6'd12: begin
            queue_response(index, response_payload, 1'b0, s_inject_crc_error);
            s_inject_crc_error = 1'b0;
            s_pending_busy     = 1'b1;
            s_busy_count       = BusyCycles;
          end
          6'd16, 6'd55, 6'd41, 6'd6, 6'd13: begin
            queue_response(index, response_payload, 1'b0, s_inject_crc_error);
            s_inject_crc_error = 1'b0;
          end
          6'd17, 6'd18: begin
            s_last_cmd_data  = 1'b1;
            s_last_cmd_write = 1'b0;
            address          = card_address(argument);
            s_cmd_address    = address;
            s_cmd_count      = (index == 6'd18) ? BlockBytes : BlockBytes;
            queue_response(index, response_payload, 1'b0, s_inject_crc_error);
            s_inject_crc_error = 1'b0;
          end
          6'd24, 6'd25: begin
            s_last_cmd_data  = 1'b1;
            s_last_cmd_write = 1'b1;
            address          = card_address(argument);
            s_cmd_address    = address;
            s_cmd_count      = BlockBytes;
            queue_response(index, response_payload, 1'b0, s_inject_crc_error);
            s_inject_crc_error = 1'b0;
          end
          default: begin
            queue_response(index, response_payload, 1'b0, s_inject_crc_error);
            s_inject_crc_error = 1'b0;
          end
        endcase
      end
    end
  endtask

  task automatic decode_command_frame(input logic [47:0] raw_i);
    begin
      if (command_frame_valid(raw_i)) begin
        command_received(raw_i);
      end else begin
        $fatal(1, "SDIO card observed an invalid command frame: %h", raw_i);
      end
    end
  endtask

  task automatic drive_read_data;
    integer       address;
    logic   [7:0] byte_value;
    begin
      if (s_data_width4) begin
        dat_do_o = 4'b1111;
        for (integer lane = 0; lane < 4; lane++) begin
          if (lane < (s_data_bytes - s_data_byte_index)) begin
            address        = s_data_address + (s_data_fixed ? 0 : s_data_byte_index + lane);
            byte_value     = backing_read(address);
            dat_do_o[lane] = byte_value[7-(s_data_bit_index%8)];
          end
        end
      end else begin
        address     = s_data_address + (s_data_fixed ? 0 : s_data_byte_index);
        byte_value  = backing_read(address);
        dat_do_o    = 4'b1111;
        dat_do_o[0] = byte_value[7-(s_data_bit_index%8)];
      end
    end
  endtask

  task automatic advance_read_crc;
    integer       address;
    logic   [7:0] byte_value;
    begin
      if (s_data_width4) begin
        for (integer lane = 0; lane < 4; lane++) begin
          if (lane < (s_data_bytes - s_data_byte_index)) begin
            address = s_data_address + (s_data_fixed ? 0 : s_data_byte_index + lane);
            byte_value = backing_read(address);
            s_read_crc_lane[lane] =
                crc16_next(s_read_crc_lane[lane], byte_value[7-(s_data_bit_index%8)]);
          end
        end
        s_data_bit_index = s_data_bit_index + 1;
        if (s_data_bit_index >= 8) begin
          s_data_byte_index = s_data_byte_index + 4;
          if (s_data_byte_index > s_data_bytes) begin
            s_data_byte_index = s_data_bytes;
          end
          if (s_data_byte_index < s_data_bytes) begin
            s_data_bit_index = 0;
          end
        end
      end else begin
        address    = s_data_address + (s_data_fixed ? 0 : s_data_byte_index);
        byte_value = backing_read(address);
        s_read_crc = crc16_next(s_read_crc, byte_value[7-(s_data_bit_index%8)]);
        if ((s_data_bit_index % 8) == 7) begin
          s_data_byte_index = s_data_byte_index + 1;
        end
        s_data_bit_index = s_data_bit_index + 1;
      end
    end
  endtask

  task automatic sample_write_payload(input logic [3:0] bits_i);
    begin
      if (s_data_width4) begin
        for (integer lane = 0; lane < 4; lane++) begin
          if (lane < (s_data_bytes - s_data_byte_index)) begin
            s_write_byte_lane[lane] = {s_write_byte_lane[lane][6:0], bits_i[lane]};
            s_write_crc_lane[lane]  = crc16_next(s_write_crc_lane[lane], bits_i[lane]);
          end
        end
        s_write_bit_count = s_write_bit_count + 1;
        if (s_write_bit_count == 8) begin
          for (integer lane = 0; lane < 4; lane++) begin
            if (lane < (s_data_bytes - s_data_byte_index)) begin
              backing_write(s_data_address + (s_data_fixed ? 0 : s_data_byte_index + lane),
                            s_write_byte_lane[lane]);
            end
          end
          s_data_byte_index = s_data_byte_index + 4;
          if (s_data_byte_index > s_data_bytes) begin
            s_data_byte_index = s_data_bytes;
          end
          s_write_bit_count = 0;
          for (integer lane = 0; lane < 4; lane++) begin
            s_write_byte_lane[lane] = 8'd0;
          end
        end
      end else begin
        s_write_byte      = {s_write_byte[6:0], bits_i[0]};
        s_write_bit_count = s_write_bit_count + 1;
        s_write_crc       = crc16_next(s_write_crc, bits_i[0]);
        if (s_write_bit_count == 8) begin
          backing_write(s_data_address + (s_data_fixed ? 0 : s_data_byte_index), s_write_byte);
          s_data_byte_index = s_data_byte_index + 1;
          s_write_bit_count = 0;
        end
      end
      if (s_data_byte_index >= s_data_bytes) begin
        s_data_state     = WriteCrc;
        s_data_crc_index = 0;
        s_received_crc   = 16'd0;
        for (integer lane = 0; lane < 4; lane++) begin
          s_received_crc_lane[lane] = 16'd0;
        end
      end
    end
  endtask

  always @(posedge sck_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_cmd_shift           = '0;
      s_cmd_bits            = 0;
      s_cmd_response_active = 1'b0;
      s_cmd_response        = '0;
      s_cmd_response_length = 48;
      s_cmd_response_index  = 0;
      s_cmd_response_delay  = 0;
      s_response_delay      = 0;
      s_inject_crc_error    = 1'b0;
      s_inject_timeout      = 1'b0;
      s_inject_write_error  = 1'b0;
      s_next_cmd_crc_error  = 1'b0;
      s_last_cmd            = 6'd0;
      s_last_arg            = 32'd0;
      s_last_cmd_write      = 1'b0;
      s_last_cmd_data       = 1'b0;
      s_pending_busy        = 1'b0;
      s_busy_count          = 0;
    end else if (cmd_oe_i) begin
      if (s_cmd_bits == 0) begin
        s_cmd_shift = {{47{1'b0}}, cmd_do_i};
        s_cmd_bits  = 1;
      end else if (s_cmd_bits != 0) begin
        s_cmd_shift = {s_cmd_shift[46:0], cmd_do_i};
        if (s_cmd_bits == 47) begin
          decode_command_frame(s_cmd_shift);
          s_cmd_bits = 0;
        end else begin
          s_cmd_bits = s_cmd_bits + 1;
        end
      end
    end else begin
      s_cmd_bits = 0;
    end
  end

  always @(negedge sck_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_cmd_response_active = 1'b0;
      s_cmd_response_index  = 0;
      s_cmd_response_delay  = 0;
    end else if (s_cmd_response_active) begin
      if (s_cmd_response_delay > 0) begin
        s_cmd_response_delay = s_cmd_response_delay - 1;
        cmd_do_o             = 1'b1;
        if (s_cmd_response_delay == 0) begin
          cmd_do_o = s_cmd_response[s_cmd_response_length-1];
        end
      end else if (s_cmd_response_index + 1 >= s_cmd_response_length) begin
        s_cmd_response_active = 1'b0;
        cmd_do_o              = 1'b1;
      end else begin
        cmd_do_o             = s_cmd_response[s_cmd_response_length-1-(s_cmd_response_index+1)];
        s_cmd_response_index = s_cmd_response_index + 1;
        if (s_cmd_response_index + 1 >= s_cmd_response_length) begin
          s_cmd_response_active = 1'b0;
        end
      end
    end
  end

  always @(posedge sck_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_cmd_shift           = '0;
      s_cmd_bits            = 0;
      s_cmd_response_active = 1'b0;
      s_cmd_response        = '0;
      s_cmd_response_length = 48;
      s_cmd_response_index  = 0;
      s_cmd_response_delay  = 0;
      s_response_delay      = 0;
      s_inject_crc_error    = 1'b0;
      s_inject_timeout      = 1'b0;
      s_inject_write_error  = 1'b0;
      s_next_cmd_crc_error  = 1'b0;
      s_last_cmd            = 6'd0;
      s_last_arg            = 32'd0;
      s_last_cmd_write      = 1'b0;
      s_last_cmd_data       = 1'b0;
      s_pending_busy        = 1'b0;
      s_busy_count          = 0;
      s_data_state          = DataIdle;
      s_data_width4         = 1'b0;
      s_data_fixed          = 1'b0;
      s_data_address        = 0;
      s_data_bytes          = 0;
      s_data_byte_index     = 0;
      s_data_bit_index      = 0;
      s_data_nibble_index   = 0;
      s_data_crc_index      = 0;
      s_data_delay          = 0;
      s_read_crc            = 16'd0;
      s_write_crc           = 16'd0;
      s_received_crc        = 16'd0;
      s_write_byte          = 8'd0;
      for (integer lane = 0; lane < 4; lane++) begin
        s_write_byte_lane[lane] = 8'd0;
      end
      s_write_bit_count        = 0;
      s_write_nibble_count     = 0;
      s_write_response_token   = 5'b00101;
      s_write_response_index   = 0;
      s_write_response_started = 1'b0;
      s_data_crc_error         = 1'b0;
      s_data_timeout           = 1'b0;
      s_irq_pending            = 1'b0;
      s_cmd_function           = 3'd0;
      s_cmd_address            = 32'd0;
      s_cmd_fixed_address      = 1'b0;
      s_cmd_count              = 0;
      cmd_do_o                 = 1'b1;
      dat_do_o                 = 4'b1111;
      irq_o                    = 1'b0;
    end else begin
      if (s_pending_busy) begin
        dat_do_o[0] = 1'b0;
        if (s_busy_count > 0) begin
          s_busy_count = s_busy_count - 1;
        end else begin
          s_pending_busy = 1'b0;
          dat_do_o[0]    = 1'b1;
        end
      end

      if (s_data_state == WriteBusy) begin
        dat_do_o[0] = 1'b0;
        if (s_busy_count > 0) begin
          s_busy_count = s_busy_count - 1;
        end else begin
          s_data_state = DataIdle;
          dat_do_o[0]  = 1'b1;
        end
      end

      case (s_data_state)
        DataDelay: begin
          dat_do_o = 4'b1111;
          if (s_data_delay > 0) begin
            s_data_delay = s_data_delay - 1;
          end else begin
            s_data_state = DataToken;
            dat_do_o     = 4'b0000;
          end
        end
        DataToken: begin
          s_data_byte_index   = 0;
          s_data_bit_index    = 0;
          s_data_nibble_index = 0;
          s_data_crc_index    = 0;
          s_read_crc          = 16'd0;
          for (integer lane = 0; lane < 4; lane++) begin
            s_read_crc_lane[lane] = 16'd0;
          end
          s_data_state = DataPayload;
          drive_read_data();
        end
        DataPayload: begin
          advance_read_crc();
          if (s_data_width4) begin
            if (s_data_bit_index >= 8 && s_data_byte_index >= s_data_bytes) begin
              s_data_state     = DataCrc;
              s_data_crc_index = 0;
              dat_do_o         = 4'b1111;
              for (integer lane = 0; lane < 4; lane++) begin
                if (lane < s_data_bytes) begin
                  dat_do_o[lane] = s_read_crc_lane[lane][15];
                end
              end
            end else begin
              drive_read_data();
            end
          end else if (s_data_bit_index >= (s_data_bytes * 8)) begin
            s_data_state     = DataCrc;
            s_data_crc_index = 0;
            dat_do_o         = 4'b1111;
            dat_do_o[0]      = s_read_crc[15];
          end else begin
            drive_read_data();
          end
        end
        DataCrc: begin
          if (s_data_width4) begin
            if (s_data_crc_index == 15) begin
              s_data_state = DataIdle;
              dat_do_o     = 4'b1111;
            end else begin
              s_data_crc_index = s_data_crc_index + 1;
              dat_do_o         = 4'b1111;
              for (integer lane = 0; lane < 4; lane++) begin
                if (lane < s_data_bytes) begin
                  dat_do_o[lane] = s_read_crc_lane[lane][15-(s_data_crc_index+1)];
                end
              end
            end
          end else if (s_data_crc_index == 15) begin
            s_data_state = DataIdle;
            dat_do_o     = 4'b1111;
          end else begin
            s_data_crc_index = s_data_crc_index + 1;
            dat_do_o         = 4'b1111;
            dat_do_o[0]      = s_read_crc[15-(s_data_crc_index+1)];
          end
        end
        WriteResponse: begin
          dat_do_o = 4'b1111;
          if (!s_write_response_started) begin
            s_write_response_started = 1'b1;
            dat_do_o[0]              = s_write_response_token[4];
          end else if (s_write_response_index < 4) begin
            s_write_response_index = s_write_response_index + 1;
            dat_do_o[0]            = s_write_response_token[4-s_write_response_index];
          end else begin
            s_data_state = (s_write_response_token == 5'b00101) ? WriteBusy : DataIdle;
            s_busy_count = BusyCycles;
            dat_do_o[0]  = (s_write_response_token == 5'b00101) ? 1'b0 : 1'b1;
          end
        end
        default: begin
        end
      endcase

      if ((s_data_state != DataPayload) && (s_data_state != DataCrc)) begin
        if (s_irq_pending && !s_pending_busy) begin
          dat_do_o[1] = 1'b0;
        end else if (s_data_state == DataIdle) begin
          dat_do_o[1] = 1'b1;
        end
      end
      irq_o = s_irq_pending;
    end
  end

  always @(negedge sck_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_received_crc       = 16'd0;
      s_write_byte         = 8'd0;
      s_write_bit_count    = 0;
      s_write_nibble_count = 0;
    end else begin
      case (s_data_state)
        WriteWait: begin
          if ((dat_oe_i != 4'b0000) && (dat_do_i == 4'b0000)) begin
            s_data_state         = WritePayload;
            s_write_bit_count    = 0;
            s_write_nibble_count = 0;
            s_write_byte         = 8'd0;
          end else if (dat_oe_i != 4'b0000) begin
            $fatal(1, "SDIO card observed a missing data token: %b", dat_do_i);
          end
        end
        WritePayload: begin
          sample_write_payload(dat_do_i);
        end
        WriteCrc: begin
          if (s_data_width4) begin
            for (integer lane = 0; lane < 4; lane++) begin
              s_received_crc_lane[lane] = {s_received_crc_lane[lane][14:0], dat_do_i[lane]};
            end
          end else begin
            s_received_crc = {s_received_crc[14:0], dat_do_i[0]};
          end
          if (s_data_crc_index == 15) begin
            s_data_crc_error = 1'b0;
            if (s_data_width4) begin
              for (integer lane = 0; lane < 4; lane++) begin
                if (s_received_crc_lane[lane] != s_write_crc_lane[lane]) begin
                  s_data_crc_error = 1'b1;
                end
              end
            end else if (s_received_crc != s_write_crc) begin
              s_data_crc_error = 1'b1;
            end
            if (s_inject_crc_error) begin
              s_data_crc_error   = 1'b1;
              s_inject_crc_error = 1'b0;
            end
            if (s_inject_write_error) begin
              s_write_response_token = 5'b01101;
              s_inject_write_error   = 1'b0;
            end else if (s_data_crc_error) begin
              s_write_response_token = 5'b01011;
            end else begin
              s_write_response_token = 5'b00101;
            end
            s_write_response_index   = 0;
            s_write_response_started = 1'b0;
            s_data_state             = WriteResponse;
            dat_do_o                 = 4'b1111;
            dat_do_o[0]              = s_write_response_token[4];
          end else begin
            s_data_crc_index = s_data_crc_index + 1;
          end
        end
        default: begin
        end
      endcase
    end
  end

  initial begin
    if ((BlockBytes < 1) || (BlockCount < 1) || (FunctionCount < 1) || (FunctionBytes < 256)) begin
      $fatal(1, "sdio_native_card_model: invalid storage geometry");
    end
    cmd_do_o              = 1'b1;
    dat_do_o              = 4'b1111;
    irq_o                 = 1'b0;
    s_cmd_shift           = '0;
    s_cmd_bits            = 0;
    s_cmd_response_active = 1'b0;
    s_cmd_response        = '0;
    s_cmd_response_length = 48;
    s_cmd_response_index  = 0;
    s_cmd_response_delay  = 0;
    s_last_cmd            = 6'd0;
    s_last_arg            = 32'd0;
    s_last_cmd_write      = 1'b0;
    s_last_cmd_data       = 1'b0;
    s_pending_busy        = 1'b0;
    s_busy_count          = 0;
    s_data_state          = DataIdle;
    s_data_width4         = 1'b0;
    s_data_fixed          = 1'b0;
    s_data_address        = 0;
    s_data_bytes          = 0;
    s_data_byte_index     = 0;
    s_data_bit_index      = 0;
    s_data_nibble_index   = 0;
    s_data_crc_index      = 0;
    s_data_delay          = 0;
    s_read_crc            = 16'd0;
    s_write_crc           = 16'd0;
    s_received_crc        = 16'd0;
    s_write_byte          = 8'd0;
    for (integer lane = 0; lane < 4; lane++) begin
      s_write_byte_lane[lane] = 8'd0;
    end
    s_write_bit_count        = 0;
    s_write_nibble_count     = 0;
    s_write_response_token   = 5'b00101;
    s_write_response_index   = 0;
    s_write_response_started = 1'b0;
    s_data_crc_error         = 1'b0;
    s_data_timeout           = 1'b0;
    s_irq_pending            = 1'b0;
    s_cmd_function           = 3'd0;
    s_cmd_address            = 32'd0;
    s_cmd_fixed_address      = 1'b0;
    s_cmd_count              = 0;
    s_response_delay         = 0;
    s_data_delay_cfg         = 0;
    s_data_delay             = 0;
    s_inject_crc_error       = 1'b0;
    s_inject_timeout         = 1'b0;
    s_inject_write_error     = 1'b0;
    s_irq_pending            = 1'b0;
    for (integer index = 0; index < MemoryBytes; index++) begin
      s_memory[index] = 8'd0;
    end
    for (integer index = 0; index < FunctionStorageBytes; index++) begin
      s_function_memory[index] = 8'd0;
    end
    if (SdioOnly) begin
      s_function_memory[0]  = 8'h03;
      s_function_memory[2]  = 8'h01;
      s_function_memory[3]  = 8'h01;
      s_function_memory[4]  = 8'h00;
      s_function_memory[5]  = 8'h00;
      s_function_memory[6]  = 8'h00;
      s_function_memory[7]  = 8'h00;
      s_function_memory[8]  = 8'h00;
      s_function_memory[9]  = 8'h00;
      s_function_memory[10] = 8'h02;
      s_function_memory[11] = 8'h00;
      s_function_memory[19] = 8'h01;
      for (integer function_index = 1; function_index < FunctionCount; function_index++) begin
        s_function_memory[function_index*FunctionBytes] = 8'h01;
      end
    end
  end
endmodule

module sdio_sd_memory_model #(
    parameter bit HighCapacity = 1'b1,
    parameter int BlockBytes   = 512,
    parameter int BlockCount   = 128,
    parameter int BusyCycles   = 2
) (
    input  logic       rst_n_i,
    input  logic       sck_i,
    input  logic       cmd_oe_i,
    input  logic       cmd_do_i,
    output logic       cmd_do_o,
    input  logic [3:0] dat_oe_i,
    input  logic [3:0] dat_do_i,
    output logic [3:0] dat_do_o,
    output logic       irq_o
);
  sdio_native_card_model #(
      .SdioOnly    (1'b0),
      .HighCapacity(HighCapacity),
      .BlockBytes  (BlockBytes),
      .BlockCount  (BlockCount),
      .BusyCycles  (BusyCycles)
  ) u_model (
      .rst_n_i (rst_n_i),
      .sck_i   (sck_i),
      .cmd_oe_i(cmd_oe_i),
      .cmd_do_i(cmd_do_i),
      .cmd_do_o(cmd_do_o),
      .dat_oe_i(dat_oe_i),
      .dat_do_i(dat_do_i),
      .dat_do_o(dat_do_o),
      .irq_o   (irq_o)
  );

  task automatic set_response_delay(input integer cycles_i);
    u_model.set_response_delay(cycles_i);
  endtask
  task automatic set_data_delay(input integer cycles_i);
    u_model.set_data_delay(cycles_i);
  endtask
  task automatic inject_next_crc_error;
    u_model.inject_next_crc_error();
  endtask
  task automatic inject_next_timeout;
    u_model.inject_next_timeout();
  endtask
  task automatic inject_next_write_error;
    u_model.inject_next_write_error();
  endtask
  task automatic fill_memory(input logic [7:0] seed_i);
    u_model.fill_memory(seed_i);
  endtask
  task automatic arm_read(input integer address_i, input integer bytes_i, input logic width4_i,
                          input logic fixed_address_i);
    u_model.arm_read(address_i, bytes_i, width4_i, fixed_address_i);
  endtask
  task automatic arm_write(input integer address_i, input integer bytes_i, input logic width4_i,
                           input logic fixed_address_i);
    u_model.arm_write(address_i, bytes_i, width4_i, fixed_address_i);
  endtask
  function automatic logic [7:0] read_backing(input integer address_i);
    read_backing = u_model.read_backing(address_i);
  endfunction
  task automatic write_backing(input integer address_i, input logic [7:0] data_i);
    u_model.write_backing(address_i, data_i);
  endtask
endmodule

module sdio_sdio_model #(
    parameter int FunctionCount = 2,
    parameter int FunctionBytes = 4096,
    parameter int BusyCycles    = 2
) (
    input  logic       rst_n_i,
    input  logic       sck_i,
    input  logic       cmd_oe_i,
    input  logic       cmd_do_i,
    output logic       cmd_do_o,
    input  logic [3:0] dat_oe_i,
    input  logic [3:0] dat_do_i,
    output logic [3:0] dat_do_o,
    output logic       irq_o
);
  sdio_native_card_model #(
      .SdioOnly     (1'b1),
      .FunctionCount(FunctionCount),
      .FunctionBytes(FunctionBytes),
      .BusyCycles   (BusyCycles)
  ) u_model (
      .rst_n_i (rst_n_i),
      .sck_i   (sck_i),
      .cmd_oe_i(cmd_oe_i),
      .cmd_do_i(cmd_do_i),
      .cmd_do_o(cmd_do_o),
      .dat_oe_i(dat_oe_i),
      .dat_do_i(dat_do_i),
      .dat_do_o(dat_do_o),
      .irq_o   (irq_o)
  );

  task automatic set_response_delay(input integer cycles_i);
    u_model.set_response_delay(cycles_i);
  endtask
  task automatic set_data_delay(input integer cycles_i);
    u_model.set_data_delay(cycles_i);
  endtask
  task automatic inject_next_crc_error;
    u_model.inject_next_crc_error();
  endtask
  task automatic inject_next_timeout;
    u_model.inject_next_timeout();
  endtask
  task automatic inject_next_write_error;
    u_model.inject_next_write_error();
  endtask
  task automatic arm_read(input integer address_i, input integer bytes_i, input logic width4_i,
                          input logic fixed_address_i);
    u_model.arm_read(address_i, bytes_i, width4_i, fixed_address_i);
  endtask
  task automatic arm_write(input integer address_i, input integer bytes_i, input logic width4_i,
                           input logic fixed_address_i);
    u_model.arm_write(address_i, bytes_i, width4_i, fixed_address_i);
  endtask
  task automatic set_irq;
    u_model.set_irq();
  endtask
  task automatic clear_irq;
    u_model.clear_irq();
  endtask
  function automatic logic [7:0] read_backing(input integer address_i);
    read_backing = u_model.read_backing(address_i);
  endfunction
  task automatic write_backing(input integer address_i, input logic [7:0] data_i);
    u_model.write_backing(address_i, data_i);
  endtask
endmodule
