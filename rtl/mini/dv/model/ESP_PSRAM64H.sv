// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of the Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.
//
// Behavioral model for the external ESP-PSRAM64H 64-Mbit PSRAM.
// Only SDR SPI and QPI transactions are modeled.  The model intentionally
// does not initialize the memory array unless INITIALIZE_MEMORY is enabled.

`timescale 1 ns / 1 ps

/* verilator lint_off WIDTHTRUNC */
module ESP_PSRAM64H #(
    parameter integer        ID                      = 0,
    parameter integer        MEMORY_BYTES            = 8 * 1024 * 1024,
    parameter integer        INITIALIZE_MEMORY       = 0,
    parameter         [ 7:0] INITIAL_MEMORY_VALUE    = 8'h00,
    parameter integer        POWER_UP_CHECK          = 1,
    parameter time           POWER_UP_TIME_NS        = 150000,
    parameter integer        TIMING_CHECK            = 1,
    parameter time           MIN_SCLK_HIGH_NS        = 3,
    parameter time           MIN_SCLK_LOW_NS         = 3,
    parameter time           MIN_CS_HIGH_NS          = 2,
    parameter time           MIN_CS_LOW_NS           = 2,
    parameter integer        TIMING_VIOLATION_FATAL  = 0,
    parameter integer        INJECT_MISSING_DEVICE   = 0,
    parameter integer        INJECT_FAILED_DEVICE    = 0,
    parameter integer        INJECT_TIMING_VIOLATION = 0,
    parameter integer        DEFAULT_WRAP32          = 0,
    parameter         [ 7:0] MANUFACTURER_ID         = 8'h0d,
    parameter         [ 7:0] KGD                     = 8'h5d,
    parameter         [ 7:0] DENSITY                 = 8'h26,
    parameter         [23:0] EXTENDED_ID             = 24'h000000
) (
    input wire       sclk,
    input wire       csn,
    inout wire [3:0] sio
);

  localparam [4:0] ST_IDLE = 5'd0;
  localparam [4:0] ST_SPI_CMD = 5'd1;
  localparam [4:0] ST_QPI_CMD = 5'd2;
  localparam [4:0] ST_SPI_ADDR = 5'd3;
  localparam [4:0] ST_QUAD_ADDR = 5'd4;
  localparam [4:0] ST_ID_ADDR = 5'd5;
  localparam [4:0] ST_DUMMY = 5'd6;
  localparam [4:0] ST_READ = 5'd7;
  localparam [4:0] ST_WRITE = 5'd8;
  localparam [4:0] ST_ID = 5'd9;

  localparam [3:0] DUMMY_FAST_READ = 4'd8;
  localparam [3:0] DUMMY_QUAD_READ = 4'd6;

  reg  [ 7:0] mem_array                [0:MEMORY_BYTES-1];

  reg  [ 4:0] r_state;
  reg         r_csn_active;
  reg         r_qpi_mode;
  reg         r_reset_armed;
  reg         r_wrap32;
  reg         r_power_up_done;

  reg  [ 7:0] r_command;
  reg  [ 7:0] r_command_shift;
  reg  [ 2:0] r_command_bit_count;
  reg         r_command_nibble_count;
  reg  [23:0] r_address_shift;
  reg  [23:0] r_current_address;
  reg  [ 4:0] r_address_count;
  reg  [ 3:0] r_dummy_count;
  reg  [ 3:0] r_dummy_length;
  reg  [ 7:0] r_write_shift;
  reg  [ 2:0] r_write_count;

  reg         r_output_enable;
  reg         r_output_quad;
  reg  [ 3:0] r_output_nibble;
  reg         r_output_bit;
  reg  [ 2:0] r_output_bit_count;
  reg  [ 2:0] r_output_nibble_count;
  reg  [ 5:0] r_id_bit_count;

  reg         r_timing_reported;
  reg         r_timing_injected;

  time        r_last_csn_rise_time;
  time        r_last_csn_fall_time;
  time        r_last_sclk_posedge_time;
  time        r_last_sclk_negedge_time;
  reg         r_have_csn_rise;
  reg         r_have_csn_fall;
  reg         r_have_sclk_posedge;
  reg         r_have_sclk_negedge;

  wire [47:0] w_id_value;
  wire        w_device_present;
  wire        w_power_ready;

  assign w_id_value = {
    MANUFACTURER_ID, (INJECT_FAILED_DEVICE != 0) ? 8'h55 : KGD, DENSITY, EXTENDED_ID
  };
  assign w_device_present = INJECT_MISSING_DEVICE == 0;
  assign w_power_ready = r_power_up_done;

  assign sio[0] = (w_device_present && (csn === 1'b0) && r_output_enable &&
                   r_output_quad)
                      ? r_output_nibble[0]
                      : 1'bz;
  assign sio[1] = (w_device_present && (csn === 1'b0) && r_output_enable)
                      ? (r_output_quad ? r_output_nibble[1] : r_output_bit)
                      : 1'bz;
  assign sio[2] = (w_device_present && (csn === 1'b0) && r_output_enable &&
                   r_output_quad)
                      ? r_output_nibble[2]
                      : 1'bz;
  assign sio[3] = (w_device_present && (csn === 1'b0) && r_output_enable &&
                   r_output_quad)
                      ? r_output_nibble[3]
                      : 1'bz;

  function integer memory_index;
    input [23:0] address;
    integer address_value;
    begin
      if (MEMORY_BYTES <= 0) begin
        memory_index = 0;
      end else begin
        address_value = {8'd0, address};
        memory_index  = address_value % MEMORY_BYTES;
      end
    end
  endfunction

  function [23:0] next_address;
    input [23:0] address;
    input wrap32;
    integer address_value;
    integer address_offset;
    begin
      if (MEMORY_BYTES <= 0) begin
        next_address = 24'd0;
      end else begin
        address_value = {8'd0, address};
        address_value = address_value % MEMORY_BYTES;
        if (wrap32) begin
          address_offset = address_value & 31;
          if (address_offset == 31) address_value = address_value - 31;
          else address_value = address_value + 1;
        end else begin
          address_offset = address_value & 1023;
          if (address_offset == 1023) address_value = address_value - 1023;
          else address_value = address_value + 1;
        end
        if (address_value >= MEMORY_BYTES) address_value = 0;
        next_address = address_value;
      end
    end
  endfunction

  task report_timing_violation;
    begin
      if (!r_timing_reported) begin
        r_timing_reported <= 1'b1;
        if (TIMING_VIOLATION_FATAL != 0)
          $fatal(1, "ESP_PSRAM64H[%0d]: timing violation at %0t", ID, $time);
        else $display("ESP_PSRAM64H[%0d]: timing violation at %0t", ID, $time);
      end
    end
  endtask

  always @(posedge sclk or negedge sclk or negedge csn or posedge csn) begin
    if (csn === 1'b1) begin
      if (r_csn_active) begin
        if (TIMING_CHECK != 0 && r_have_csn_fall &&
            (MIN_CS_LOW_NS > 0) &&
            (($time - r_last_csn_fall_time) < MIN_CS_LOW_NS))
          report_timing_violation();
        r_last_csn_rise_time <= $time;
        r_have_csn_rise      <= 1'b1;
      end
      r_csn_active           <= 1'b0;
      r_state                <= ST_IDLE;
      r_output_enable        <= 1'b0;
      r_command_bit_count    <= 3'd0;
      r_command_nibble_count <= 1'b0;
      r_address_count        <= 5'd0;
      r_write_count          <= 3'd0;
      r_dummy_count          <= 4'd0;
    end else if (csn === 1'b0) begin
      if (!r_csn_active) begin
        if (TIMING_CHECK != 0 && r_have_csn_rise &&
            (MIN_CS_HIGH_NS > 0) &&
            (($time - r_last_csn_rise_time) < MIN_CS_HIGH_NS))
          report_timing_violation();
        if (INJECT_TIMING_VIOLATION != 0 && !r_timing_injected) begin
          r_timing_injected <= 1'b1;
          report_timing_violation();
        end
        r_last_csn_fall_time   <= $time;
        r_have_csn_fall        <= 1'b1;
        r_have_sclk_posedge    <= 1'b0;
        r_have_sclk_negedge    <= 1'b0;
        r_csn_active           <= 1'b1;
        r_output_enable        <= 1'b0;
        r_command_shift        <= 8'd0;
        r_command              <= 8'd0;
        r_command_bit_count    <= 3'd0;
        r_command_nibble_count <= 1'b0;
        r_address_shift        <= 24'd0;
        r_address_count        <= 5'd0;
        r_write_shift          <= 8'd0;
        r_write_count          <= 3'd0;
        r_dummy_count          <= 4'd0;
        r_output_bit_count     <= 3'd0;
        r_output_nibble_count  <= 3'd0;
        r_id_bit_count         <= 6'd0;
        if (!w_power_ready || !w_device_present) begin
          r_state <= ST_IDLE;
        end else if (r_qpi_mode) begin
          r_state <= ST_QPI_CMD;
        end else begin
          r_state <= ST_SPI_CMD;
        end
      end else if (!r_power_up_done && !w_power_ready) begin
        r_state <= ST_IDLE;
      end else if (sclk === 1'b1) begin
        if (TIMING_CHECK != 0 && r_have_sclk_negedge &&
            (MIN_SCLK_LOW_NS > 0) &&
            (($time - r_last_sclk_negedge_time) < MIN_SCLK_LOW_NS))
          report_timing_violation();
        r_last_sclk_posedge_time <= $time;
        r_have_sclk_posedge      <= 1'b1;

        case (r_state)
          ST_SPI_CMD: begin
            r_command_shift <= {r_command_shift[6:0], sio[0]};
            if (r_command_bit_count == 3'd7) begin
              r_command           <= {r_command_shift[6:0], sio[0]};
              r_command_bit_count <= 3'd0;
              case ({
                r_command_shift[6:0], sio[0]
              })
                8'h03: begin
                  r_address_count <= 5'd0;
                  r_state         <= ST_SPI_ADDR;
                end
                8'h0b: begin
                  r_address_count <= 5'd0;
                  r_state         <= ST_SPI_ADDR;
                end
                8'heb: begin
                  r_address_count <= 5'd0;
                  r_state         <= ST_QUAD_ADDR;
                end
                8'h02: begin
                  r_address_count <= 5'd0;
                  r_state         <= ST_SPI_ADDR;
                end
                8'h38: begin
                  r_address_count <= 5'd0;
                  r_state         <= ST_QUAD_ADDR;
                end
                8'h35: begin
                  r_qpi_mode <= 1'b1;
                  r_state    <= ST_IDLE;
                end
                8'h9f: begin
                  r_address_count <= 5'd0;
                  r_state         <= ST_ID_ADDR;
                end
                8'h66: begin
                  r_reset_armed <= 1'b1;
                  r_state       <= ST_IDLE;
                end
                8'h99: begin
                  if (r_reset_armed) begin
                    r_qpi_mode <= 1'b0;
                    r_wrap32   <= (DEFAULT_WRAP32 != 0);
                  end
                  r_reset_armed <= 1'b0;
                  r_state       <= ST_IDLE;
                end
                8'hc0: begin
                  r_wrap32 <= ~r_wrap32;
                  r_state  <= ST_IDLE;
                end
                default: begin
                  r_state <= ST_IDLE;
                end
              endcase
            end else begin
              r_command_bit_count <= r_command_bit_count + 1'b1;
            end
          end

          ST_QPI_CMD: begin
            if (!r_command_nibble_count) begin
              r_command_shift[7:4]   <= sio;
              r_command_nibble_count <= 1'b1;
            end else begin
              r_command_shift[3:0]   <= sio;
              r_command              <= {r_command_shift[7:4], sio};
              r_command_nibble_count <= 1'b0;
              case ({
                r_command_shift[7:4], sio
              })
                8'heb: begin
                  r_address_count <= 5'd0;
                  r_state         <= ST_QUAD_ADDR;
                end
                8'h02: begin
                  r_address_count <= 5'd0;
                  r_state         <= ST_QUAD_ADDR;
                end
                8'h38: begin
                  r_address_count <= 5'd0;
                  r_state         <= ST_QUAD_ADDR;
                end
                8'hf5: begin
                  r_qpi_mode <= 1'b0;
                  r_state    <= ST_IDLE;
                end
                8'h66: begin
                  r_reset_armed <= 1'b1;
                  r_state       <= ST_IDLE;
                end
                8'h99: begin
                  if (r_reset_armed) begin
                    r_qpi_mode <= 1'b0;
                    r_wrap32   <= (DEFAULT_WRAP32 != 0);
                  end
                  r_reset_armed <= 1'b0;
                  r_state       <= ST_IDLE;
                end
                8'hc0: begin
                  r_wrap32 <= ~r_wrap32;
                  r_state  <= ST_IDLE;
                end
                default: begin
                  r_state <= ST_IDLE;
                end
              endcase
            end
          end

          ST_SPI_ADDR: begin
            r_address_shift <= (r_address_shift << 1) | {23'd0, sio[0]};
            if (r_address_count == 5'd23) begin
              r_current_address <= {r_address_shift[22:0], sio[0]};
              r_address_count   <= 5'd0;
              if (r_command == 8'h03) begin
                r_output_quad      <= 1'b0;
                r_output_bit_count <= 3'd0;
                r_state            <= ST_READ;
              end else if (r_command == 8'h0b) begin
                r_output_quad  <= 1'b0;
                r_dummy_length <= DUMMY_FAST_READ;
                r_dummy_count  <= 4'd0;
                r_state        <= ST_DUMMY;
              end else if (r_command == 8'h02) begin
                r_write_count <= 3'd0;
                r_state       <= ST_WRITE;
              end else begin
                r_state <= ST_IDLE;
              end
            end else begin
              r_address_count <= r_address_count + 1'b1;
            end
          end

          ST_QUAD_ADDR: begin
            r_address_shift <= (r_address_shift << 4) | {20'd0, sio};
            if (r_address_count == 5'd5) begin
              r_current_address <= {r_address_shift[19:0], sio};
              r_address_count   <= 5'd0;
              if (r_command == 8'heb) begin
                r_output_quad  <= 1'b1;
                r_dummy_length <= DUMMY_QUAD_READ;
                r_dummy_count  <= 4'd0;
                r_state        <= ST_DUMMY;
              end else if ((r_command == 8'h02) || (r_command == 8'h38)) begin
                r_write_count <= 3'd0;
                r_state       <= ST_WRITE;
              end else begin
                r_state <= ST_IDLE;
              end
            end else begin
              r_address_count <= r_address_count + 1'b1;
            end
          end

          ST_ID_ADDR: begin
            r_address_shift <= (r_address_shift << 1) | {23'd0, sio[0]};
            if (r_address_count == 5'd23) begin
              r_address_count <= 5'd0;
              r_id_bit_count  <= 6'd0;
              r_output_quad   <= 1'b0;
              r_state         <= ST_ID;
            end else begin
              r_address_count <= r_address_count + 1'b1;
            end
          end

          ST_DUMMY: begin
            if ((r_dummy_count + 1'b1) >= r_dummy_length) begin
              r_dummy_count         <= 4'd0;
              r_output_bit_count    <= 3'd0;
              r_output_nibble_count <= 3'd0;
              r_state               <= ST_READ;
            end else begin
              r_dummy_count <= r_dummy_count + 1'b1;
            end
          end

          ST_WRITE: begin
            if ((r_command == 8'h02) && !r_qpi_mode) begin
              r_write_shift <= {r_write_shift[6:0], sio[0]};
              if (r_write_count == 3'd7) begin
                if (w_device_present)
                  mem_array[memory_index(r_current_address)] <= {r_write_shift[6:0], sio[0]};
                r_write_count     <= 3'd0;
                r_current_address <= next_address(r_current_address, r_wrap32);
              end else begin
                r_write_count <= r_write_count + 1'b1;
              end
            end else begin
              if (r_write_count == 3'd0) begin
                r_write_shift[7:4] <= sio;
                r_write_count      <= 3'd1;
              end else begin
                if (w_device_present)
                  mem_array[memory_index(r_current_address)] <= {r_write_shift[7:4], sio};
                r_write_count     <= 3'd0;
                r_current_address <= next_address(r_current_address, r_wrap32);
              end
            end
          end

          ST_READ: begin
            r_state <= ST_READ;
          end

          ST_ID: begin
            r_state <= ST_ID;
          end

          default: begin
            r_state <= ST_IDLE;
          end
        endcase
      end else begin
        if (TIMING_CHECK != 0 && r_have_sclk_posedge &&
            (MIN_SCLK_HIGH_NS > 0) &&
            (($time - r_last_sclk_posedge_time) < MIN_SCLK_HIGH_NS))
          report_timing_violation();
        r_last_sclk_negedge_time <= $time;
        r_have_sclk_negedge      <= 1'b1;

        case (r_state)
          ST_READ: begin
            r_output_enable <= 1'b1;
            if (r_output_quad) begin
              if (r_output_nibble_count == 3'd0) begin
                r_output_nibble       <= mem_array[memory_index(r_current_address)][7:4];
                r_output_nibble_count <= 3'd1;
              end else begin
                r_output_nibble       <= mem_array[memory_index(r_current_address)][3:0];
                r_output_nibble_count <= 3'd0;
                r_current_address     <= next_address(r_current_address, r_wrap32);
              end
            end else begin
              r_output_bit <= mem_array[memory_index(r_current_address)][3'd7-r_output_bit_count];
              if (r_output_bit_count == 3'd7) begin
                r_output_bit_count <= 3'd0;
                r_current_address  <= next_address(r_current_address, r_wrap32);
              end else begin
                r_output_bit_count <= r_output_bit_count + 1'b1;
              end
            end
          end

          ST_ID: begin
            r_output_enable <= 1'b1;
            r_output_bit    <= w_id_value[6'd47-r_id_bit_count];
            if (r_id_bit_count == 6'd47) r_id_bit_count <= 6'd0;
            else r_id_bit_count <= r_id_bit_count + 1'b1;
          end

          default: begin
            r_output_enable <= 1'b0;
          end
        endcase
      end
    end
  end

  integer i;
  /* verilator lint_off STMTDLY */
  initial begin : POWER_UP_BLOCK
    if ((POWER_UP_CHECK != 0) && (POWER_UP_TIME_NS > 0)) begin
      #(POWER_UP_TIME_NS);
      r_power_up_done = 1'b1;
    end
  end
  /* verilator lint_on STMTDLY */

  initial begin
    r_state                  = ST_IDLE;
    r_csn_active             = 1'b0;
    r_qpi_mode               = 1'b0;
    r_reset_armed            = 1'b0;
    r_wrap32                 = (DEFAULT_WRAP32 != 0);
    r_power_up_done          = (POWER_UP_CHECK == 0) || (POWER_UP_TIME_NS <= 0);
    r_timing_reported        = 1'b0;
    r_timing_injected        = 1'b0;
    r_command                = 8'd0;
    r_command_shift          = 8'd0;
    r_command_bit_count      = 3'd0;
    r_command_nibble_count   = 1'b0;
    r_address_shift          = 24'd0;
    r_current_address        = 24'd0;
    r_address_count          = 5'd0;
    r_dummy_count            = 4'd0;
    r_dummy_length           = 4'd0;
    r_write_shift            = 8'd0;
    r_write_count            = 3'd0;
    r_output_enable          = 1'b0;
    r_output_quad            = 1'b0;
    r_output_nibble          = 4'd0;
    r_output_bit             = 1'b0;
    r_output_bit_count       = 3'd0;
    r_output_nibble_count    = 3'd0;
    r_id_bit_count           = 6'd0;
    r_have_csn_rise          = 1'b0;
    r_have_csn_fall          = 1'b0;
    r_have_sclk_posedge      = 1'b0;
    r_have_sclk_negedge      = 1'b0;
    r_last_csn_rise_time     = $time;
    r_last_csn_fall_time     = $time;
    r_last_sclk_posedge_time = $time;
    r_last_sclk_negedge_time = $time;

    if (INITIALIZE_MEMORY != 0) begin
      for (i = 0; i < MEMORY_BYTES; i = i + 1) mem_array[i] = INITIAL_MEMORY_VALUE;
    end

    $display("ESP_PSRAM64H[%0d]: %0d-byte model, SPI reset mode, QPI disabled", ID, MEMORY_BYTES);
    if (INJECT_MISSING_DEVICE != 0)
      $display("ESP_PSRAM64H[%0d]: missing-device fault injection enabled", ID);
    else if (INJECT_FAILED_DEVICE != 0)
      $display("ESP_PSRAM64H[%0d]: failed-device fault injection enabled", ID);
  end

endmodule
