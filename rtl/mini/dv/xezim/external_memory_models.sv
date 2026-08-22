// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of the Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.
//
// Compact models for the optional Xezim and CVC flows.
// The production Icarus/VCS testbench continues to use the vendor models.

`timescale 1ns / 1ps

module W25Q128JVxIM (
    input wire CSn,
    input wire CLK,
    inout wire DIO,
    inout wire DO,
    inout wire WPn,
    inout wire HOLDn
);
  localparam integer MEMORY_BYTES = 65536;
  localparam [7:0] CMD_QUAD_READ = 8'hEB;
  localparam [7:0] CMD_READ = 8'h03;
  localparam [7:0] CMD_FAST_READ = 8'h0B;
  localparam [7:0] CMD_READ_ID = 8'h9F;

  reg [ 7:0] memory        [0:MEMORY_BYTES - 1];
  reg [ 7:0] command;
  reg [23:0] address;
  reg [ 7:0] mode;
  reg [ 7:0] output_byte;
  reg [ 3:0] output_nibble;
  reg [ 2:0] bit_count;
  reg [ 2:0] nibble_count;
  reg [ 3:0] dummy_count;
  reg [ 2:0] state;
  reg        output_enable;
  reg        output_quad;

  localparam [2:0] STATE_COMMAND = 3'd0;
  localparam [2:0] STATE_ADDRESS = 3'd1;
  localparam [2:0] STATE_MODE = 3'd2;
  localparam [2:0] STATE_DUMMY = 3'd3;
  localparam [2:0] STATE_READ = 3'd4;

  assign DIO   = (output_enable && output_quad) ? output_nibble[0] : 1'bz;
  assign DO    = output_enable ? (output_quad ? output_nibble[1] : output_nibble[0]) : 1'bz;
  assign WPn   = (output_enable && output_quad) ? output_nibble[2] : 1'bz;
  assign HOLDn = (output_enable && output_quad) ? output_nibble[3] : 1'bz;

  initial begin
    $readmemh("MEM.TXT", memory);
    command       = 8'h00;
    address       = 24'h000000;
    mode          = 8'h00;
    output_byte   = 8'h00;
    output_nibble = 4'h0;
    bit_count     = 3'd0;
    nibble_count  = 3'd0;
    dummy_count   = 3'd0;
    state         = STATE_COMMAND;
    output_enable = 1'b0;
    output_quad   = 1'b0;
  end

  always @(negedge CSn) begin
    state         = STATE_COMMAND;
    bit_count     = 3'd0;
    nibble_count  = 3'd0;
    dummy_count   = 3'd0;
    output_enable = 1'b0;
    output_quad   = 1'b0;
  end

  always @(posedge CLK) begin
    if (!CSn) begin
      case (state)
        STATE_COMMAND: begin
          command = {command[6:0], DIO};
          if (bit_count == 3'd7) begin
            bit_count = 3'd0;
            if ({command[6:0], DIO} == CMD_READ_ID) begin
              output_byte = 8'hEF;
              state       = STATE_READ;
              output_quad = 1'b0;
            end else begin
              state       = STATE_ADDRESS;
              output_quad = ({command[6:0], DIO} == CMD_QUAD_READ);
            end
          end else begin
            bit_count = bit_count + 1'b1;
          end
        end
        STATE_ADDRESS: begin
          if (output_quad) begin
            address = {address[19:0], DIO, DO, WPn, HOLDn};
            if (nibble_count == 3'd5) begin
              nibble_count = 3'd0;
              mode         = 8'h00;
              state        = STATE_MODE;
            end else begin
              nibble_count = nibble_count + 1'b1;
            end
          end else begin
            address = {address[22:0], DIO};
            if (bit_count == 3'd7) begin
              bit_count   = 3'd0;
              state       = (command == CMD_FAST_READ) ? STATE_DUMMY : STATE_READ;
              dummy_count = (command == CMD_FAST_READ) ? 4'd8 : 4'd0;
            end else begin
              bit_count = bit_count + 1'b1;
            end
          end
        end
        STATE_MODE: begin
          mode = {mode[3:0], DIO, DO, WPn, HOLDn};
          if (nibble_count == 3'd1) begin
            nibble_count = 3'd0;
            dummy_count  = 3'd4;
            state        = STATE_DUMMY;
          end else begin
            nibble_count = nibble_count + 1'b1;
          end
        end
        STATE_DUMMY: begin
          if (dummy_count == 3'd1) begin
            output_byte  = memory[address[15:0]];
            nibble_count = 3'd0;
            state        = STATE_READ;
          end else begin
            dummy_count = dummy_count - 1'b1;
          end
        end
        STATE_READ: begin
          if (nibble_count == 3'd1) begin
            nibble_count = 3'd0;
            address      = address + 1'b1;
            output_byte  = memory[address[15:0]+1'b1];
          end else begin
            nibble_count = nibble_count + 1'b1;
          end
        end
        default: state = STATE_COMMAND;
      endcase
    end
  end

  always @(negedge CLK) begin
    if (!CSn && (state == STATE_READ)) begin
      output_enable = 1'b1;
      if (command == CMD_READ_ID) begin
        output_quad      = 1'b0;
        output_nibble[0] = (nibble_count == 3'd0) ? 1'b0 : 1'b0;
      end else if (output_quad) begin
        output_nibble = (nibble_count == 3'd0) ? output_byte[7:4] : output_byte[3:0];
      end else begin
        output_nibble[0] = output_byte[7];
        output_byte      = {output_byte[6:0], 1'b0};
      end
    end else begin
      output_enable = 1'b0;
    end
  end
endmodule

module ESP_PSRAM64H #(
    parameter integer ID = 0
) (
    input wire       sclk,
    input wire       csn,
    inout wire [3:0] sio
);
  localparam integer MEMORY_BYTES = 128 * 1024;
  localparam [7:0] CMD_READ = 8'h03;
  localparam [7:0] CMD_FAST_READ = 8'h0B;
  localparam [7:0] CMD_QUAD_READ = 8'hEB;
  localparam [7:0] CMD_WRITE = 8'h02;
  localparam [7:0] CMD_QUAD_WRITE = 8'h38;
  localparam [7:0] CMD_ENTER_QPI = 8'h35;
  localparam [7:0] CMD_RESET = 8'h99;
  localparam [7:0] CMD_READ_ID = 8'h9F;

  reg [ 7:0] memory        [0:MEMORY_BYTES - 1];
  reg [ 7:0] command;
  reg [23:0] address;
  reg [ 7:0] output_byte;
  reg [ 3:0] output_nibble;
  reg [ 2:0] bit_count;
  reg [ 2:0] nibble_count;
  reg [ 3:0] dummy_count;
  reg [ 2:0] state;
  reg        qpi_mode;
  reg        output_enable;
  reg        output_quad;
  reg        write_mode;

  localparam [2:0] STATE_COMMAND = 3'd0;
  localparam [2:0] STATE_ADDRESS = 3'd1;
  localparam [2:0] STATE_DUMMY = 3'd2;
  localparam [2:0] STATE_READ = 3'd3;
  localparam [2:0] STATE_WRITE = 3'd4;

  assign sio = output_enable ? (output_quad ? output_nibble : {2'bzz, output_nibble[1:0]}) : 4'bz;

  initial begin
    command       = 8'h00;
    address       = 24'h000000;
    output_byte   = 8'h00;
    output_nibble = 4'h0;
    bit_count     = 3'd0;
    nibble_count  = 3'd0;
    dummy_count   = 4'd0;
    state         = STATE_COMMAND;
    qpi_mode      = 1'b1;
    output_enable = 1'b0;
    output_quad   = 1'b0;
    write_mode    = 1'b0;
  end

  always @(negedge csn) begin
    state         = STATE_COMMAND;
    bit_count     = 3'd0;
    nibble_count  = 3'd0;
    dummy_count   = 4'd0;
    output_enable = 1'b0;
    output_quad   = qpi_mode;
    write_mode    = 1'b0;
  end

  always @(posedge sclk) begin
    if (!csn) begin
      case (state)
        STATE_COMMAND: begin
          if (qpi_mode) begin
            if (nibble_count == 3'd0) begin
              command[7:4] = sio;
              nibble_count = 3'd1;
            end else begin
              command[3:0] = sio;
              nibble_count = 3'd0;
              if ((command == CMD_RESET) || (command == CMD_ENTER_QPI)) begin
                state = STATE_READ;
              end else begin
                state = STATE_ADDRESS;
              end
            end
          end else begin
            command = {command[6:0], sio[0]};
            if (bit_count == 3'd7) begin
              bit_count = 3'd0;
              if ((command == CMD_RESET) || (command == CMD_ENTER_QPI)) begin
                state = STATE_READ;
              end else begin
                state = STATE_ADDRESS;
              end
            end else begin
              bit_count = bit_count + 1'b1;
            end
          end
        end
        STATE_ADDRESS: begin
          if (qpi_mode) begin
            address = {address[19:0], sio};
            if (nibble_count == 3'd5) begin
              nibble_count = 3'd0;
              if (command == CMD_QUAD_READ) begin
                dummy_count = 4'd6;
                state       = STATE_DUMMY;
              end else if ((command == CMD_READ_ID) || (command == CMD_READ) ||
                                         (command == CMD_FAST_READ)) begin
                output_byte = (command == CMD_READ_ID) ? 8'h00 : memory[address[16:0]];
                state       = STATE_READ;
              end else begin
                write_mode = (command == CMD_QUAD_WRITE);
                state      = STATE_WRITE;
              end
            end else begin
              nibble_count = nibble_count + 1'b1;
            end
          end else begin
            address = {address[22:0], sio[0]};
            if (bit_count == 3'd7) begin
              bit_count   = 3'd0;
              output_byte = (command == CMD_READ_ID) ? 8'h00 : memory[address[16:0]];
              state       = STATE_READ;
            end else begin
              bit_count = bit_count + 1'b1;
            end
          end
        end
        STATE_DUMMY: begin
          if (dummy_count == 4'd1) begin
            output_byte  = memory[address[16:0]];
            nibble_count = 3'd0;
            state        = STATE_READ;
          end else begin
            dummy_count = dummy_count - 1'b1;
          end
        end
        STATE_READ: begin
          if (output_quad) begin
            if (nibble_count == 3'd1) begin
              nibble_count = 3'd0;
              address      = address + 1'b1;
              output_byte  = memory[address[16:0]+1'b1];
            end else begin
              nibble_count = nibble_count + 1'b1;
            end
          end
        end
        STATE_WRITE: begin
          if (qpi_mode || write_mode) begin
            if (nibble_count == 3'd0) begin
              memory[address[16:0]][7:4] = sio;
              nibble_count               = 3'd1;
            end else begin
              memory[address[16:0]][3:0] = sio;
              nibble_count               = 3'd0;
              address                    = address + 1'b1;
            end
          end else begin
            memory[address[16:0]] = {memory[address[16:0]][6:0], sio[0]};
          end
        end
        default: state = STATE_COMMAND;
      endcase
    end
  end

  always @(negedge sclk) begin
    if (!csn && (state == STATE_READ)) begin
      output_enable = 1'b1;
      if (command == CMD_READ_ID) begin
        output_quad   = qpi_mode;
        output_nibble = (address[2:0] == 3'd0) ? 4'h0 : (address[2:0] == 3'd1) ? 4'h5 : 4'h2;
      end else if (output_quad) begin
        output_nibble = (nibble_count == 3'd0) ? output_byte[7:4] : output_byte[3:0];
      end else begin
        output_nibble[1] = output_byte[7];
        output_byte      = {output_byte[6:0], 1'b0};
      end
    end else begin
      output_enable = 1'b0;
    end
  end

  always @(posedge csn) begin
    output_enable = 1'b0;
    if (command == CMD_ENTER_QPI) qpi_mode = 1'b1;
    if (command == CMD_RESET) qpi_mode = 1'b0;
  end
endmodule

module sdr (
    inout wire [15:0] Dq,
    input wire [12:0] Addr,
    input wire [ 1:0] Ba,
    input wire        Clk,
    input wire        Cke,
    input wire        Cs_n,
    input wire        Ras_n,
    input wire        Cas_n,
    input wire        We_n,
    input wire [ 1:0] Dqm
);
  reg     [15:0] memory      [0:65535];
  reg     [12:0] active_row  [    0:3];
  reg     [15:0] read_data;
  reg            read_enable;
  integer        index;

  assign Dq = read_enable ? read_data : 16'bz;

  initial begin
    read_enable = 1'b0;
    read_data   = 16'h0000;
    for (index = 0; index < 4; index = index + 1) active_row[index] = 13'h0000;
  end

  always @(posedge Clk) begin
    read_enable = 1'b0;
    if (Cke && !Cs_n) begin
      if (!Ras_n && Cas_n && We_n) begin
        active_row[Ba] = Addr;
      end else if (Ras_n && !Cas_n && !We_n) begin
        if (!Dqm[0]) memory[{Ba, active_row[Ba][7:0], Addr[5:0]}][7:0] = Dq[7:0];
        if (!Dqm[1]) memory[{Ba, active_row[Ba][7:0], Addr[5:0]}][15:8] = Dq[15:8];
      end else if (Ras_n && !Cas_n && We_n) begin
        read_data   = memory[{Ba, active_row[Ba][7:0], Addr[5:0]}];
        read_enable = 1'b1;
      end
    end
  end
endmodule

module AT24C04 (
    input wire WP,
    input wire SCL,
    inout wire SDA
);
  assign SDA = 1'bz;
endmodule

module dvp_camera (
    output wire       pclk_o,
    output wire       href_o,
    output wire       vsync_o,
    output wire [7:0] dat_o
);
  reg pclk;
  assign pclk_o  = pclk;
  assign href_o  = 1'b0;
  assign vsync_o = 1'b0;
  assign dat_o   = 8'h00;
  initial pclk = 1'b0;
  always #5 pclk = ~pclk;
endmodule
