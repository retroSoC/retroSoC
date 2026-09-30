// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0
`timescale 1ns / 1ps

// Pin-level 0xEB NOR model: 8 command bits, 24 quad address bits, 8 mode
// bits and four dummy clocks. Unsupported commands fail closed. This model
// verifies reset-read transport; program/erase and analog NOR timing are not
// represented. Both simulators use exactly this same serial model.
module tiny_qspi_nor (
    input logic       sck_i,
    input logic       cs_n_i,
    inout wire  [3:0] data_io
);
  typedef enum logic [2:0] {
    Command,
    Address,
    Mode,
    Dummy,
    Data
  } state_e;
  state_e        s_state;
  logic   [ 7:0] s_memory   [0:16777215];
  logic   [ 7:0] s_command;
  logic   [23:0] s_address;
  logic   [ 3:0] s_output;
  integer        s_count;
  integer        s_nibble;
  string         s_firmware;

  assign data_io = (!cs_n_i && (s_state == Data)) ? s_output : 4'bzzzz;
  initial begin
    s_state   = Command;
    s_count   = 0;
    s_command = '0;
    s_address = '0;
    if (!$value$plusargs("firmware=%s", s_firmware)) $fatal(1, "Missing +firmware hex image");
    $readmemh(s_firmware, s_memory);
  end
  always @(posedge sck_i or posedge cs_n_i) begin
    if (cs_n_i) begin
      s_state   = Command;
      s_count   = 0;
      s_command = '0;
      s_address = '0;
    end else begin
      case (s_state)
        Command: begin
          s_command = {s_command[6:0], data_io[0]};
          if (s_count == 7) begin
            if (s_command != 8'heb) $fatal(1, "Unsupported NOR command %02x", s_command);
            s_state = Address;
            s_count = 0;
          end else s_count = s_count + 1;
        end
        Address: begin
          s_address = {s_address[19:0], data_io};
          if (s_count == 5) begin
            s_state = Mode;
            s_count = 0;
          end else s_count = s_count + 1;
        end
        Mode: begin
          if (s_count == 1) begin
            s_state = Dummy;
            s_count = 0;
          end else s_count = s_count + 1;
        end
        Dummy: begin
          if (s_count == 3) s_state = Data;
          else s_count = s_count + 1;
        end
        Data: begin
        end
        default: $fatal(1, "Invalid NOR state");
      endcase
    end
  end
  always @(negedge sck_i or posedge cs_n_i) begin
    if (cs_n_i) begin
      s_nibble = 0;
      s_output = '0;
    end else if (s_state == Data) begin
      if ((s_nibble & 1) == 0) s_output = s_memory[s_address+(s_nibble/2)][7:4];
      else s_output = s_memory[s_address+(s_nibble/2)][3:0];
      s_nibble = s_nibble + 1;
    end else begin
      s_nibble = 0;
      s_output = '0;
    end
  end
endmodule
