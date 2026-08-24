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

module spisd_core #(
    parameter int InputClockHz = 72_000_000,
    parameter int AddrWidth    = 32,
    parameter int DataWidth    = 32,
    parameter int DescCount    = 16,
    parameter int FifoDepth    = 16
) (
    // verilog_format: off -- preserve the reviewed control/status/bus port groups
    input  logic                           clk_i,
    input  logic                           rst_n_i,
    input  logic                           host_enable_i,
    input  logic                           clock_enable_i,
    input  logic                           clock_train_i,
    input  logic [15:0]                    half_period_i,
    input  logic [31:0]                    timeout_cmd_i,
    input  logic [31:0]                    timeout_data_i,
    input  logic [31:0]                    timeout_busy_i,
    input  logic [5:0]                     cmd_index_i,
    input  logic [31:0]                    cmd_arg_i,
    input  spisd_pkg::spisd_resp_type_e    cmd_resp_type_i,
    input  logic                           cmd_stuff_byte_i,
    input  logic                           cmd_data_present_i,
    input  logic                           cmd_auto_stop_i,
    input  logic                           cmd_start_i,
    input  logic [15:0]                    block_size_i,
    input  logic [15:0]                    block_count_i,
    input  logic                           data_direction_i,
    input  logic                           data_dma_enable_i,
    input  logic                           data_multi_block_i,
    input  logic                           data_crc_check_i,
    input  logic                           pio_wvalid_i,
    input  logic [31:0]                    pio_wdata_i,
    input  logic [3:0]                     pio_wstrb_i,
    input  logic [31:0]                    desc_base_i,
    input  logic [15:0]                    desc_count_i,
    input  logic                           dma_start_i,
    input  logic                           dma_abort_i,
    input  logic                           host_abort_i,
    input  logic                           pio_read_consume_i,
    output logic                           pio_write_ready_o,
    output logic [31:0]                    pio_rdata_o,
    output logic                           pio_valid_o,
    output logic [31:0]                    status_o,
    output logic [31:0]                    clock_actual_o,
    output logic [31:0]                    cmd_status_o,
    output logic [39:0]                    response_o,
    output logic [31:0]                    data_status_o,
    output logic [31:0]                    fifo_status_o,
    output logic [31:0]                    dma_status_o,
    output logic [31:0]                    current_desc_o,
    output logic [31:0]                    bytes_done_o,
    output logic [31:0]                    dma_error_addr_o,
    output logic [31:0]                    dma_error_o,
    output logic [31:0]                    error_status_o,
    output logic [5:0]                     last_cmd_o,
    output logic [31:0]                    crc_error_count_o,
    output logic [31:0]                    timeout_count_o,
    output logic [31:0]                    axi_error_count_o,
    output logic [31:0]                    stall_count_o,
    output logic [6:0]                     irq_event_o,
    output logic                           busy_o,
    output logic                           sck_o,
    output logic                           nss_o,
    output logic                           mosi_o,
    input  logic                           miso_i,
    axi4_if.master                         dma_axi4
    // verilog_format: on
);
  localparam int FifoCountWidth = $clog2(FifoDepth);

  typedef enum logic [2:0] {
    Idle,
    Command,
    Data,
    StopCommand,
    Finish,
    Training,
    TrainingFinish
  } transaction_state_e;

  transaction_state_e s_transaction_state_d, s_transaction_state_q;
  logic [2:0] s_transaction_state_bits_q;
  logic s_rise_tick, s_fall_tick, s_clock_running, s_clock_pause;
  logic s_cmd_start, s_cmd_mosi, s_cmd_busy, s_cmd_done, s_cmd_err;
  logic s_cmd_timeout, s_cmd_busy_timeout;
  logic                        [ 7:0] s_cmd_err_code;
  logic                        [39:0] s_cmd_resp;
  logic                        [ 5:0] s_cmd_last_index;
  logic                        [ 5:0] s_active_cmd_index;
  logic                        [31:0] s_active_cmd_arg;
  spisd_pkg::spisd_resp_type_e        s_active_resp_type;
  logic                               s_active_stuff_byte;

  logic s_data_start, s_data_mosi, s_data_pause, s_data_busy, s_data_done;
  logic s_data_err, s_data_timeout, s_data_crc_err, s_data_busy_timeout;
  logic [ 7:0] s_data_err_code;
  logic [15:0] s_blocks_done;
  logic s_data_tx_valid, s_data_tx_ready, s_data_tx_last;
  logic [31:0] s_data_tx_data;
  logic [ 3:0] s_data_tx_strb;
  logic s_data_rx_valid, s_data_rx_ready, s_data_rx_last;
  logic [31:0] s_data_rx_data;
  logic [ 3:0] s_data_rx_strb;

  logic s_dma_start, s_dma_abort, s_dma_busy, s_dma_done, s_dma_err;
  logic [7:0] s_dma_err_code;
  logic [31:0] s_dma_current_desc, s_dma_bytes_done, s_dma_err_addr;
  logic s_dma_descriptor_irq, s_dma_abort_done;
  logic s_dma_data_in_valid, s_dma_data_in_ready, s_dma_data_in_last;
  logic [31:0] s_dma_data_in;
  logic [ 3:0] s_dma_data_in_strb;
  logic s_dma_data_out_valid, s_dma_data_out_ready, s_dma_data_out_last;
  logic [31:0] s_dma_data_out;
  logic [ 3:0] s_dma_data_out_strb;

  logic s_tx_fifo_full, s_tx_fifo_empty, s_tx_fifo_push, s_tx_fifo_pop;
  logic [            35:0] s_tx_fifo_data;
  logic [FifoCountWidth:0] s_tx_fifo_count;
  logic s_rx_fifo_full, s_rx_fifo_empty, s_rx_fifo_push, s_rx_fifo_pop;
  logic [            31:0] s_rx_fifo_data;
  logic [FifoCountWidth:0] s_rx_fifo_count;
  logic                    s_fifo_flush;
  logic [            31:0] s_total_bytes;
  logic [31:0] s_pio_tx_bytes_d, s_pio_tx_bytes_q;
  logic [2:0] s_pio_head_bytes;

  logic       s_cmd_r1_err;
  logic       s_abort_req;
  logic s_cmd_err_event, s_data_err_event, s_dma_err_event;
  logic s_cmd_timeout_event, s_data_timeout_event, s_crc_err_event;
  logic s_abort_event;
  logic [31:0] s_crc_err_count_d, s_crc_err_count_q;
  logic [31:0] s_timeout_count_d, s_timeout_count_q;
  logic [31:0] s_axi_err_count_d, s_axi_err_count_q;
  logic [31:0] s_stall_count_d, s_stall_count_q;
  logic [6:0] s_train_cnt_d, s_train_cnt_q;
  logic s_transaction_start;

  function automatic logic [2:0] count_strobe(input logic [3:0] strb_i);
    logic [2:0] count;
    begin
      count = 3'd0;
      for (int index = 0; index < 4; index++) begin
        if (strb_i[index]) count = count + 1'b1;
      end
      return count;
    end
  endfunction

  function automatic logic [31:0] saturating_increment(input logic [31:0] value_i);
    return (&value_i) ? value_i : value_i + 1'b1;
  endfunction

  assign s_total_bytes = {16'd0, block_size_i} * {16'd0, block_count_i};
  assign s_transaction_start = (cmd_start_i || dma_start_i) && host_enable_i;
  assign s_cmd_start = ((s_transaction_state_q == Idle) && s_transaction_start) ||
                       ((s_transaction_state_q == Data) && s_data_done && !s_data_err &&
                        cmd_auto_stop_i && data_multi_block_i &&
                        (data_direction_i == spisd_pkg::SpisdDataFromCard));
  assign s_data_start = (s_transaction_state_q == Command) && s_cmd_done &&
                        !s_cmd_err && !s_cmd_r1_err && cmd_data_present_i;
  assign s_active_cmd_index = (s_transaction_state_q == Data) ? 6'd12 : cmd_index_i;
  assign s_active_cmd_arg = (s_transaction_state_q == Data) ? 32'd0 : cmd_arg_i;
  assign s_active_resp_type = (s_transaction_state_q == Data)
                                ? spisd_pkg::SpisdRespR1b : cmd_resp_type_i;
  assign s_active_stuff_byte = (s_transaction_state_q == Data) ? 1'b1 : cmd_stuff_byte_i;
  assign s_cmd_r1_err = s_cmd_done && cmd_data_present_i && (s_cmd_resp[7:0] != 8'h00);
  assign s_abort_req = host_abort_i || dma_abort_i || s_cmd_err_event ||
                       s_cmd_r1_err || s_data_err_event || s_dma_err_event;
  assign s_dma_start = (s_transaction_state_q == Idle) && s_transaction_start &&
                       cmd_data_present_i && data_dma_enable_i;
  assign s_dma_abort = s_abort_req;

  assign s_clock_pause = (s_transaction_state_q == Data) && s_data_pause;
  assign nss_o = !host_enable_i || (s_transaction_state_q == Idle) ||
                 (s_transaction_state_q == Training) ||
                 (s_transaction_state_q == TrainingFinish);
  assign mosi_o = ((s_transaction_state_q == Command) ||
                   (s_transaction_state_q == StopCommand)) ? s_cmd_mosi :
                  ((s_transaction_state_q == Data) ? s_data_mosi : 1'b1);

  assign s_tx_fifo_push = pio_wvalid_i && pio_write_ready_o;
  assign s_tx_fifo_pop = !data_dma_enable_i && s_data_tx_valid && s_data_tx_ready;
  assign s_rx_fifo_push = !data_dma_enable_i && s_data_rx_valid && s_data_rx_ready;
  assign s_rx_fifo_pop = pio_read_consume_i && !s_rx_fifo_empty;
  assign s_fifo_flush = host_abort_i;
  assign pio_write_ready_o = !s_tx_fifo_full;
  assign pio_rdata_o = s_rx_fifo_data;
  assign pio_valid_o = !s_rx_fifo_empty;
  assign s_pio_head_bytes = count_strobe(s_tx_fifo_data[35:32]);

  assign s_data_tx_valid = data_dma_enable_i ? s_dma_data_out_valid : !s_tx_fifo_empty;
  assign s_data_tx_data = data_dma_enable_i ? s_dma_data_out : s_tx_fifo_data[31:0];
  assign s_data_tx_strb = data_dma_enable_i ? s_dma_data_out_strb : s_tx_fifo_data[35:32];
  assign s_data_tx_last = data_dma_enable_i ? s_dma_data_out_last :
                          ((s_pio_tx_bytes_q + {29'd0, s_pio_head_bytes}) >= s_total_bytes);
  assign s_dma_data_out_ready = data_dma_enable_i && s_data_tx_ready;
  assign s_dma_data_in_valid = data_dma_enable_i && s_data_rx_valid;
  assign s_dma_data_in = s_data_rx_data;
  assign s_dma_data_in_strb = s_data_rx_strb;
  assign s_dma_data_in_last = s_data_rx_last;
  assign s_data_rx_ready = data_dma_enable_i ? s_dma_data_in_ready : !s_rx_fifo_full;

  assign s_cmd_err_event = s_cmd_done && s_cmd_err;
  assign s_data_err_event = s_data_done && s_data_err;
  assign s_dma_err_event = s_dma_done && s_dma_err;
  assign s_cmd_timeout_event = s_cmd_done && (s_cmd_timeout || s_cmd_busy_timeout);
  assign s_data_timeout_event = s_data_done && (s_data_timeout || s_data_busy_timeout);
  assign s_crc_err_event = s_data_done && s_data_crc_err;
  assign s_abort_event = host_abort_i || dma_abort_i || s_dma_abort_done;

  assign busy_o = (s_transaction_state_q != Idle) || s_dma_busy;
  assign s_transaction_state_q = transaction_state_e'(s_transaction_state_bits_q);
  assign response_o = s_cmd_resp;
  assign last_cmd_o = s_cmd_last_index;
  assign current_desc_o = s_dma_current_desc;
  assign bytes_done_o = s_dma_bytes_done;
  assign dma_error_addr_o = s_dma_err_addr;
  assign dma_error_o = {24'd0, s_dma_err_code};
  assign crc_error_count_o = s_crc_err_count_q;
  assign timeout_count_o = s_timeout_count_q;
  assign axi_error_count_o = s_axi_err_count_q;
  assign stall_count_o = s_stall_count_q;
  assign clock_actual_o = (half_period_i == 16'd0)
                            ? InputClockHz / 2 : InputClockHz / (2 * half_period_i);
  assign status_o = {
    23'd0,
    host_enable_i,
    s_clock_running,
    data_multi_block_i,
    data_dma_enable_i,
    pio_write_ready_o,
    s_dma_busy,
    s_data_busy,
    s_cmd_busy,
    busy_o
  };
  assign cmd_status_o = {
    18'd0,
    s_cmd_err_code,
    2'd0,
    s_cmd_busy_timeout,
    s_cmd_timeout,
    s_cmd_err || s_cmd_r1_err,
    s_cmd_busy
  };
  assign data_status_o = {
    s_blocks_done,
    s_data_err_code,
    3'd0,
    s_data_busy_timeout,
    s_data_crc_err,
    s_data_timeout,
    s_data_err,
    s_data_busy
  };
  assign fifo_status_o = {
    12'd0,
    s_rx_fifo_full,
    s_rx_fifo_empty,
    5'(s_rx_fifo_count),
    6'd0,
    s_tx_fifo_full,
    s_tx_fifo_empty,
    5'(s_tx_fifo_count)
  };
  assign dma_status_o = {21'd0, s_dma_err_code, s_dma_err, s_dma_done, s_dma_busy};
  assign error_status_o = {
    24'd0,
    s_abort_event,
    s_dma_err_event,
    s_data_err_event,
    s_cmd_err_event || s_cmd_r1_err,
    s_data_timeout_event,
    s_cmd_timeout_event,
    s_crc_err_event,
    1'b0
  };
  assign irq_event_o = {
    s_abort_event,
    s_dma_err_event,
    s_data_err_event,
    s_cmd_err_event || s_cmd_r1_err,
    s_dma_done || s_dma_descriptor_irq,
    s_data_done,
    s_cmd_done
  };

  always_comb begin
    s_transaction_state_d = s_transaction_state_q;
    unique case (s_transaction_state_q)
      Idle: begin
        if (clock_train_i && host_enable_i) begin
          s_transaction_state_d = Training;
        end else if (s_transaction_start) begin
          s_transaction_state_d = Command;
        end
      end
      Command: begin
        if (host_abort_i || (s_cmd_done && (s_cmd_err || s_cmd_r1_err))) begin
          s_transaction_state_d = Finish;
        end else if (s_cmd_done) begin
          s_transaction_state_d = cmd_data_present_i ? Data : Finish;
        end
      end
      Data: begin
        if (host_abort_i || (s_data_done && s_data_err)) begin
          s_transaction_state_d = Finish;
        end else if (s_data_done) begin
          if (cmd_auto_stop_i && data_multi_block_i &&
              (data_direction_i == spisd_pkg::SpisdDataFromCard)) begin
            s_transaction_state_d = StopCommand;
          end else begin
            s_transaction_state_d = Finish;
          end
        end
      end
      StopCommand: begin
        if (host_abort_i || s_cmd_done) s_transaction_state_d = Finish;
      end
      Finish: begin
        if (!s_clock_running) s_transaction_state_d = Idle;
      end
      Training: begin
        if (s_rise_tick && (s_train_cnt_q == 7'd79)) begin
          s_transaction_state_d = TrainingFinish;
        end
      end
      TrainingFinish: begin
        if (!s_clock_running) s_transaction_state_d = Idle;
      end
      default: s_transaction_state_d = Finish;
    endcase
  end

  always_comb begin
    s_pio_tx_bytes_d = s_pio_tx_bytes_q;
    if (s_transaction_start && (s_transaction_state_q == Idle)) begin
      s_pio_tx_bytes_d = '0;
    end else if (s_tx_fifo_pop) begin
      s_pio_tx_bytes_d = s_pio_tx_bytes_q + {29'd0, s_pio_head_bytes};
    end
  end

  always_comb begin
    s_crc_err_count_d = s_crc_err_count_q;
    s_timeout_count_d = s_timeout_count_q;
    s_axi_err_count_d = s_axi_err_count_q;
    s_stall_count_d   = s_stall_count_q;
    if (s_crc_err_event) s_crc_err_count_d = saturating_increment(s_crc_err_count_q);
    if (s_cmd_timeout_event || s_data_timeout_event) begin
      s_timeout_count_d = saturating_increment(s_timeout_count_q);
    end
    if (s_dma_err_event) s_axi_err_count_d = saturating_increment(s_axi_err_count_q);
    if ((s_data_tx_valid && !s_data_tx_ready) || (s_data_rx_valid && !s_data_rx_ready)) begin
      s_stall_count_d = saturating_increment(s_stall_count_q);
    end
  end

  always_comb begin
    s_train_cnt_d = s_train_cnt_q;
    if (clock_train_i) begin
      s_train_cnt_d = '0;
    end else if ((s_transaction_state_q == Training) && s_rise_tick) begin
      s_train_cnt_d = s_train_cnt_q + 1'b1;
    end
  end

  dffr #(
      .DATA_WIDTH($bits(transaction_state_e))
  ) u_transaction_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_transaction_state_d),
      .dat_o  (s_transaction_state_bits_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_pio_tx_bytes_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_pio_tx_bytes_d),
      .dat_o  (s_pio_tx_bytes_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_crc_error_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_crc_err_count_d),
      .dat_o  (s_crc_err_count_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_timeout_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_timeout_count_d),
      .dat_o  (s_timeout_count_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_axi_error_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_axi_err_count_d),
      .dat_o  (s_axi_err_count_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_stall_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_stall_count_d),
      .dat_o  (s_stall_count_q)
  );
  dffr #(
      .DATA_WIDTH(7)
  ) u_train_cnt_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_train_cnt_d),
      .dat_o  (s_train_cnt_q)
  );

  fifo #(
      .DATA_WIDTH      (36),
      .BUFFER_DEPTH    (FifoDepth),
      .LOG_BUFFER_DEPTH(FifoCountWidth)
  ) u_tx_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(s_fifo_flush),
      .push_i (s_tx_fifo_push),
      .full_o (s_tx_fifo_full),
      .dat_i  ({pio_wstrb_i, pio_wdata_i}),
      .pop_i  (s_tx_fifo_pop),
      .empty_o(s_tx_fifo_empty),
      .dat_o  (s_tx_fifo_data),
      .cnt_o  (s_tx_fifo_count)
  );

  fifo #(
      .DATA_WIDTH      (32),
      .BUFFER_DEPTH    (FifoDepth),
      .LOG_BUFFER_DEPTH(FifoCountWidth)
  ) u_rx_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(s_fifo_flush),
      .push_i (s_rx_fifo_push),
      .full_o (s_rx_fifo_full),
      .dat_i  (s_data_rx_data),
      .pop_i  (s_rx_fifo_pop),
      .empty_o(s_rx_fifo_empty),
      .dat_o  (s_rx_fifo_data),
      .cnt_o  (s_rx_fifo_count)
  );

  spisd_clock #(
      .CounterWidth(16)
  ) u_spisd_clock (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .enable_i     (host_enable_i && clock_enable_i &&
                     ((s_transaction_state_q == Command) ||
                      (s_transaction_state_q == Data) ||
                      (s_transaction_state_q == StopCommand) ||
                      (s_transaction_state_q == Training))),
      .pause_i(s_clock_pause),
      .half_period_i(half_period_i),
      .sck_o(sck_o),
      .rise_tick_o(s_rise_tick),
      .fall_tick_o(s_fall_tick),
      .running_o(s_clock_running)
  );

  spisd_command #(
      .TimeoutWidth(32)
  ) u_spisd_command (
      .clk_i                (clk_i),
      .rst_n_i              (rst_n_i),
      .rise_tick_i          (s_rise_tick),
      .fall_tick_i          (s_fall_tick),
      .start_i              (s_cmd_start),
      .abort_i              (s_abort_req),
      .cmd_index_i          (s_active_cmd_index),
      .cmd_arg_i            (s_active_cmd_arg),
      .resp_type_i          (s_active_resp_type),
      .stuff_byte_i         (s_active_stuff_byte),
      .timeout_cycles_i     (timeout_cmd_i),
      .busy_timeout_cycles_i(timeout_busy_i),
      .miso_i               (miso_i),
      .mosi_o               (s_cmd_mosi),
      .busy_o               (s_cmd_busy),
      .done_o               (s_cmd_done),
      .error_o              (s_cmd_err),
      .timeout_o            (s_cmd_timeout),
      .busy_timeout_o       (s_cmd_busy_timeout),
      .error_code_o         (s_cmd_err_code),
      .response_o           (s_cmd_resp),
      .last_cmd_index_o     (s_cmd_last_index)
  );

  spisd_data #(
      .TimeoutWidth(32)
  ) u_spisd_data (
      .clk_i                (clk_i),
      .rst_n_i              (rst_n_i),
      .rise_tick_i          (s_rise_tick),
      .fall_tick_i          (s_fall_tick),
      .start_i              (s_data_start),
      .abort_i              (s_abort_req),
      .direction_i          (spisd_pkg::spisd_data_direction_e'(data_direction_i)),
      .multi_block_i        (data_multi_block_i),
      .crc_check_i          (data_crc_check_i),
      .block_size_i         (block_size_i),
      .block_count_i        (block_count_i),
      .timeout_cycles_i     (timeout_data_i),
      .busy_timeout_cycles_i(timeout_busy_i),
      .miso_i               (miso_i),
      .mosi_o               (s_data_mosi),
      .clock_pause_o        (s_data_pause),
      .tx_valid_i           (s_data_tx_valid),
      .tx_ready_o           (s_data_tx_ready),
      .tx_data_i            (s_data_tx_data),
      .tx_strb_i            (s_data_tx_strb),
      .tx_last_i            (s_data_tx_last),
      .rx_valid_o           (s_data_rx_valid),
      .rx_ready_i           (s_data_rx_ready),
      .rx_data_o            (s_data_rx_data),
      .rx_strb_o            (s_data_rx_strb),
      .rx_last_o            (s_data_rx_last),
      .busy_o               (s_data_busy),
      .done_o               (s_data_done),
      .error_o              (s_data_err),
      .timeout_o            (s_data_timeout),
      .crc_error_o          (s_data_crc_err),
      .busy_timeout_o       (s_data_busy_timeout),
      .error_code_o         (s_data_err_code),
      .blocks_done_o        (s_blocks_done)
  );

  sdio_dma #(
      .AddrWidth(AddrWidth),
      .DataWidth(DataWidth),
      .DescCount(DescCount)
  ) u_storage_dma (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .start_i         (s_dma_start),
      .abort_i         (s_dma_abort),
      .direction_i     (data_direction_i),
      .desc_base_i     (desc_base_i),
      .desc_count_i    (desc_count_i),
      .total_bytes_i   (s_total_bytes),
      .data_in_valid_i (s_dma_data_in_valid),
      .data_in_ready_o (s_dma_data_in_ready),
      .data_in_i       (s_dma_data_in),
      .data_in_strb_i  (s_dma_data_in_strb),
      .data_in_last_i  (s_dma_data_in_last),
      .data_out_valid_o(s_dma_data_out_valid),
      .data_out_ready_i(s_dma_data_out_ready),
      .data_out_o      (s_dma_data_out),
      .data_out_strb_o (s_dma_data_out_strb),
      .data_out_last_o (s_dma_data_out_last),
      .busy_o          (s_dma_busy),
      .done_o          (s_dma_done),
      .error_o         (s_dma_err),
      .error_code_o    (s_dma_err_code),
      .current_desc_o  (s_dma_current_desc),
      .bytes_done_o    (s_dma_bytes_done),
      .error_addr_o    (s_dma_err_addr),
      .descriptor_irq_o(s_dma_descriptor_irq),
      .abort_done_o    (s_dma_abort_done),
      .dma_axi4        (dma_axi4)
  );

`ifndef SYNTHESIS
  initial begin
    if ((AddrWidth != 32) || (DataWidth != 32) || (DescCount < 1) ||
        (FifoDepth < 2) || ((FifoDepth & (FifoDepth - 1)) != 0)) begin
      $fatal(1, "spisd_core: unsupported geometry");
    end
  end
`endif
endmodule
