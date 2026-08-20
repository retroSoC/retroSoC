// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING, BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`timescale 1ns / 1ps

module sdio_core #(
    parameter int InputClockHz = 72_000_000,
    parameter int AddrWidth    = 32,
    parameter int DataWidth    = 32,
    parameter int DescCount    = 16
) (
    // verilog_format: off -- preserve the host, status, and external bus groups
    input  logic                          clk_i,
    input  logic                          rst_n_i,
    input  logic                          host_enable_i,
    input  logic                          host_irq_enable_i,
    input  logic                          clock_enable_i,
    input  logic [15:0]                   half_period_i,
    input  logic [1:0]                    bus_width_i,
    input  logic [31:0]                   timeout_cmd_i,
    input  logic [31:0]                   timeout_data_i,
    input  logic [31:0]                   timeout_busy_i,
    input  logic [5:0]                    cmd_index_i,
    input  logic [31:0]                   cmd_arg_i,
    input  sdio_pkg::sdio_resp_type_e     cmd_resp_type_i,
    input  logic                          cmd_crc_check_i,
    input  logic                          cmd_index_check_i,
    input  logic                          cmd_start_i,
    input  logic [15:0]                   block_size_i,
    input  logic [15:0]                   block_count_i,
    input  logic                          data_direction_i,
    input  logic                          data_dma_enable_i,
    input  logic                          data_block_mode_i,
    input  logic                          data_fixed_addr_i,
    input  logic                          data_start_i,
    input  logic                          pio_wvalid_i,
    input  logic [31:0]                   pio_wdata_i,
    input  logic [3:0]                    pio_wstrb_i,
    input  logic [31:0]                   desc_base_i,
    input  logic [15:0]                   desc_count_i,
    input  logic                          dma_start_i,
    input  logic                          dma_abort_i,
    input  logic                          host_abort_i,
    input  logic                          irq_dat1_enable_i,
    output logic [31:0]                   status_o,
    output logic [31:0]                   clock_actual_o,
    output logic [31:0]                   cmd_status_o,
    output logic [135:0]                  response_o,
    output logic [31:0]                   data_status_o,
    output logic [31:0]                   fifo_status_o,
    output logic [31:0]                   dma_status_o,
    output logic [31:0]                   current_desc_o,
    output logic [31:0]                   bytes_done_o,
    output logic [31:0]                   dma_error_addr_o,
    output logic [31:0]                   dma_error_o,
    output logic [31:0]                   error_status_o,
    output logic [5:0]                    last_cmd_o,
    output logic [31:0]                   crc_error_count_o,
    output logic [31:0]                   timeout_count_o,
    output logic [31:0]                   axi_error_count_o,
    output logic [31:0]                   stall_count_o,
    output logic [7:0]                    irq_event_o,
    output logic [31:0]                   pio_rdata_o,
    output logic                          pio_valid_o,
    output logic                          pio_ready_o,
    input  logic                          pio_read_consume_i,
    output logic                          busy_o,
    sdio_if.core                          sdio,
    axi4_if.master                        dma_axi4
    // verilog_format: on
);
  logic         s_launch_tick;
  logic         s_sample_tick;
  logic         s_clock_sck;
  logic         s_clock_running;
  logic         s_clock_en;
  logic         s_cmd_oe;
  logic         s_cmd_do;
  logic         s_cmd_busy;
  logic         s_cmd_done;
  logic         s_cmd_err;
  logic         s_cmd_timeout;
  logic         s_cmd_crc_err;
  logic         s_cmd_index_err;
  logic         s_cmd_busy_timeout;
  logic [135:0] s_cmd_response;
  logic [  5:0] s_last_cmd;
  logic [  3:0] s_data_oe;
  logic [  3:0] s_data_do;
  logic         s_data_tx_valid;
  logic         s_data_tx_ready;
  logic         s_data_tx_wait;
  logic [ 31:0] s_data_tx_data;
  logic [  3:0] s_data_tx_strb;
  logic         s_data_tx_last;
  logic         s_data_rx_valid;
  logic         s_data_rx_ready;
  logic         s_data_rx_stall_q;
  logic [ 31:0] s_data_rx_data;
  logic [  3:0] s_data_rx_strb;
  logic         s_data_rx_last;
  logic         s_data_busy;
  logic         s_data_done;
  logic         s_data_err;
  logic         s_data_timeout;
  logic         s_data_crc_err;
  logic         s_data_busy_timeout;
  logic         s_dma_start;
  logic         s_dma_direction;
  logic         s_dma_data_in_valid;
  logic         s_dma_data_in_ready;
  logic [ 31:0] s_dma_data_in;
  logic [  3:0] s_dma_data_in_strb;
  logic         s_dma_data_in_last;
  logic         s_dma_data_out_valid;
  logic         s_dma_data_out_ready;
  logic [ 31:0] s_dma_data_out;
  logic [  3:0] s_dma_data_out_strb;
  logic         s_dma_data_out_last;
  logic         s_dma_busy;
  logic         s_dma_done;
  logic         s_dma_err;
  logic [  7:0] s_dma_err_code;
  logic [ 31:0] s_dma_current_desc;
  logic [ 31:0] s_dma_bytes_done;
  logic [ 31:0] s_dma_err_addr;
  logic         s_dma_descriptor_irq;
  logic         s_dma_abort_done;
  logic s_dat1_meta_q, s_dat1_sync_q, s_dat1_seen_d, s_dat1_seen_q;
  logic [31:0] s_pio_rdata_q;
  logic        s_pio_valid_q;
  logic [31:0] s_pio_tx_data_q[0:3];
  logic [ 3:0] s_pio_tx_strb_q[0:3];
  logic [1:0] s_pio_tx_rd_q, s_pio_tx_wr_q;
  logic [ 2:0] s_pio_tx_count_q;
  logic [31:0] s_crc_err_count_q;
  logic [31:0] s_timeout_count_q;
  logic [31:0] s_axi_err_count_q;
  logic [31:0] s_stall_count_q;
  logic [ 7:0] s_irq_event;
  logic [31:0] s_err_stat;
  logic [31:0] s_total_bytes;
  logic        s_core_busy;
  logic [31:0] s_cmd_timeout_cfg;
  logic        s_dat1_qualify;
  logic        s_abort_request;
  logic        s_abort_pending_q;
  logic        s_abort_event;
  logic s_pio_tx_push, s_pio_tx_pop, s_pio_tx_full;
  logic [ 2:0] s_pio_tx_head_bytes;
  logic [31:0] s_pio_tx_bytes_q;
  logic s_cmd_err_event, s_data_err_event, s_dma_err_event;
  logic s_cmd_crc_event, s_data_crc_event;
  logic s_cmd_timeout_event, s_data_timeout_event, s_busy_timeout_event;

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

  assign s_clock_en = host_enable_i && clock_enable_i &&
                          (s_cmd_busy || s_data_busy || s_dma_busy || cmd_start_i ||
                           data_start_i) &&
                          !s_data_rx_stall_q &&
                          !(s_data_busy && s_data_tx_wait && (s_data_oe == 4'b0000));
  assign s_total_bytes = {16'd0, block_size_i} * {16'd0, block_count_i};
  assign s_abort_request = host_abort_i || dma_abort_i ||
                           (s_dma_done && s_dma_err) ||
                           (s_data_done && s_data_err);
  assign s_dma_start = dma_start_i || (data_start_i && data_dma_enable_i);
  assign s_dma_direction = data_direction_i;
  assign s_cmd_timeout_cfg = timeout_cmd_i;
  assign s_dat1_qualify = host_irq_enable_i && irq_dat1_enable_i && !s_data_busy &&
                          (!host_enable_i || !s_data_oe[1]) && !s_dat1_sync_q;
  assign s_pio_tx_full = s_pio_tx_count_q == 3'd4;
  assign s_pio_tx_head_bytes = count_strobe(s_pio_tx_strb_q[s_pio_tx_rd_q]);
  assign s_pio_tx_push = pio_wvalid_i && pio_ready_o;
  assign s_data_tx_valid = data_dma_enable_i ? s_dma_data_out_valid : (s_pio_tx_count_q != 3'd0);
  assign s_data_tx_data = data_dma_enable_i ? s_dma_data_out : s_pio_tx_data_q[s_pio_tx_rd_q];
  assign s_data_tx_strb = data_dma_enable_i ? s_dma_data_out_strb : s_pio_tx_strb_q[s_pio_tx_rd_q];
  assign s_data_tx_last = data_dma_enable_i ? s_dma_data_out_last :
                          ((s_pio_tx_bytes_q + {29'd0, s_pio_tx_head_bytes}) >=
                           s_total_bytes);
  assign s_dma_data_out_ready = data_dma_enable_i && s_data_tx_ready;
  assign s_dma_data_in_valid = data_dma_enable_i && s_data_rx_valid;
  assign s_dma_data_in = s_data_rx_data;
  assign s_dma_data_in_strb = s_data_rx_strb;
  assign s_dma_data_in_last = s_data_rx_last;
  assign s_data_rx_ready = data_dma_enable_i ? s_dma_data_in_ready : !s_pio_valid_q;
  assign s_core_busy = s_cmd_busy || s_data_busy || s_dma_busy;
  assign busy_o = s_core_busy;
  assign s_pio_tx_pop = !data_dma_enable_i && s_data_tx_valid && s_data_tx_ready;
  assign s_abort_event = s_abort_pending_q && !s_core_busy;
  assign s_cmd_err_event = s_cmd_done && s_cmd_err;
  assign s_data_err_event = s_data_done && s_data_err;
  assign s_dma_err_event = s_dma_done && s_dma_err;
  assign s_cmd_crc_event = s_cmd_done && s_cmd_crc_err;
  assign s_data_crc_event = s_data_done && s_data_crc_err;
  assign s_cmd_timeout_event = s_cmd_done && (s_cmd_timeout || s_cmd_busy_timeout);
  assign s_data_timeout_event = s_data_done && s_data_timeout;
  assign s_busy_timeout_event = s_data_done && s_data_busy_timeout;

  assign sdio.sck_o = s_clock_sck;
  assign sdio.cmd_oe_o = s_cmd_oe && host_enable_i;
  assign sdio.cmd_do_o = s_cmd_do;
  assign sdio.dat_oe_o = host_enable_i ? s_data_oe : 4'b0000;
  assign sdio.dat_do_o = s_data_do;

  assign pio_rdata_o = s_pio_rdata_q;
  assign pio_valid_o = s_pio_valid_q;
  assign pio_ready_o = s_data_busy && !data_dma_enable_i && !s_pio_tx_full &&
                       (data_direction_i == sdio_pkg::SdioDataToCard);
  assign response_o = s_cmd_response;
  assign last_cmd_o = s_last_cmd;
  assign crc_error_count_o = s_crc_err_count_q;
  assign timeout_count_o = s_timeout_count_q;
  assign axi_error_count_o = s_axi_err_count_q;
  assign stall_count_o = s_stall_count_q;
  assign current_desc_o = s_dma_current_desc;
  assign bytes_done_o = s_dma_bytes_done;
  assign dma_error_addr_o = s_dma_err_addr;
  assign dma_error_o = {24'd0, s_dma_err_code};
  assign clock_actual_o = (half_period_i == 16'd0) ? 32'd0 : InputClockHz / (2 * half_period_i);
  assign status_o = {
    23'd0,
    s_clock_running,
    s_dat1_sync_q,
    data_block_mode_i,
    data_fixed_addr_i,
    pio_ready_o,
    s_dma_busy,
    s_data_busy,
    s_cmd_busy,
    s_core_busy
  };
  assign cmd_status_o = {
    27'd0, s_cmd_index_err, s_cmd_crc_err, s_cmd_timeout, s_cmd_err, s_cmd_busy
  };
  assign data_status_o = {
    27'd0, s_data_busy_timeout, s_data_crc_err, s_data_timeout, s_data_err, s_data_busy
  };
  assign fifo_status_o = {28'd0, s_pio_tx_count_q, s_pio_valid_q};
  assign dma_status_o = {21'd0, s_dma_err_code, s_dma_err, s_dma_done, s_dma_busy};
  assign error_status_o = s_err_stat;

  assign s_err_stat = {
    24'd0,
    s_abort_event || s_dma_abort_done,
    s_dma_err_event,
    s_data_err_event,
    s_cmd_err_event,
    s_data_timeout_event || s_busy_timeout_event,
    s_cmd_timeout_event,
    s_data_crc_event,
    s_cmd_crc_event
  };
  assign s_irq_event = {
    s_abort_event || s_dma_abort_done,
    s_dat1_seen_d && !s_dat1_seen_q,
    s_dma_err_event,
    s_data_err_event,
    s_cmd_err_event,
    s_dma_done || s_dma_descriptor_irq,
    s_data_done,
    s_cmd_done
  };
  assign irq_event_o = s_irq_event;

  sdio_clock #(
      .CounterWidth(16)
  ) u_sdio_clock (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .enable_i     (s_clock_en),
      .half_period_i(half_period_i),
      .sck_o        (s_clock_sck),
      .launch_tick_o(s_launch_tick),
      .sample_tick_o(s_sample_tick),
      .running_o    (s_clock_running)
  );

  sdio_command #(
      .TimeoutWidth(32)
  ) u_sdio_command (
      .clk_i                (clk_i),
      .rst_n_i              (rst_n_i),
      .launch_tick_i        (s_launch_tick),
      .sample_tick_i        (s_sample_tick),
      .start_i              (cmd_start_i),
      .abort_i              (s_abort_request),
      .cmd_index_i          (cmd_index_i),
      .cmd_arg_i            (cmd_arg_i),
      .resp_type_i          (cmd_resp_type_i),
      .crc_check_i          (cmd_crc_check_i),
      .index_check_i        (cmd_index_check_i),
      .timeout_cycles_i     (s_cmd_timeout_cfg),
      .busy_timeout_cycles_i(timeout_busy_i),
      .cmd_di_i             (sdio.cmd_di_i),
      .dat0_i               (sdio.dat_di_i[0]),
      .cmd_oe_o             (s_cmd_oe),
      .cmd_do_o             (s_cmd_do),
      .busy_o               (s_cmd_busy),
      .done_o               (s_cmd_done),
      .error_o              (s_cmd_err),
      .timeout_o            (s_cmd_timeout),
      .crc_error_o          (s_cmd_crc_err),
      .index_error_o        (s_cmd_index_err),
      .busy_timeout_o       (s_cmd_busy_timeout),
      .response_o           (s_cmd_response),
      .last_cmd_index_o     (s_last_cmd)
  );

  sdio_data #(
      .TimeoutWidth(32)
  ) u_sdio_data (
      .clk_i                (clk_i),
      .rst_n_i              (rst_n_i),
      .launch_tick_i        (s_launch_tick),
      .sample_tick_i        (s_sample_tick),
      .start_i              (data_start_i),
      .abort_i              (s_abort_request),
      .direction_i          (sdio_pkg::sdio_data_direction_e'(data_direction_i)),
      .bus_width_i          (bus_width_i),
      .block_size_i         (block_size_i),
      .block_count_i        (block_count_i),
      .timeout_cycles_i     (timeout_data_i),
      .busy_timeout_cycles_i(timeout_busy_i),
      .dat_di_i             (sdio.dat_di_i),
      .dat0_i               (sdio.dat_di_i[0]),
      .dat_oe_o             (s_data_oe),
      .dat_do_o             (s_data_do),
      .tx_valid_i           (s_data_tx_valid),
      .tx_ready_o           (s_data_tx_ready),
      .tx_wait_o            (s_data_tx_wait),
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
      .busy_timeout_o       (s_data_busy_timeout)
  );

  sdio_dma #(
      .AddrWidth(AddrWidth),
      .DataWidth(DataWidth),
      .DescCount(DescCount)
  ) u_sdio_dma (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .start_i         (s_dma_start),
      .abort_i         (s_abort_request),
      .direction_i     (s_dma_direction),
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

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_dat1_meta_q     <= 1'b1;
      s_dat1_sync_q     <= 1'b1;
      s_dat1_seen_q     <= 1'b0;
      s_data_rx_stall_q <= 1'b0;
      s_pio_rdata_q     <= '0;
      s_pio_valid_q     <= 1'b0;
      s_pio_tx_rd_q     <= '0;
      s_pio_tx_wr_q     <= '0;
      s_pio_tx_count_q  <= '0;
      s_pio_tx_bytes_q  <= '0;
      s_crc_err_count_q <= '0;
      s_timeout_count_q <= '0;
      s_axi_err_count_q <= '0;
      s_stall_count_q   <= '0;
      s_abort_pending_q <= 1'b0;
      for (int index = 0; index < 4; index++) begin
        s_pio_tx_data_q[index] <= '0;
        s_pio_tx_strb_q[index] <= '0;
      end
    end else begin
      s_dat1_meta_q     <= sdio.dat_di_i[1];
      s_dat1_sync_q     <= s_dat1_meta_q;
      s_dat1_seen_q     <= s_dat1_seen_d;
      s_data_rx_stall_q <= s_data_rx_valid && !s_data_rx_ready;

      if (data_start_i) begin
        s_pio_tx_rd_q    <= '0;
        s_pio_tx_wr_q    <= '0;
        s_pio_tx_count_q <= '0;
        s_pio_tx_bytes_q <= '0;
      end else begin
        if (s_pio_tx_push) begin
          s_pio_tx_data_q[s_pio_tx_wr_q] <= pio_wdata_i;
          s_pio_tx_strb_q[s_pio_tx_wr_q] <= pio_wstrb_i;
          s_pio_tx_wr_q                  <= s_pio_tx_wr_q + 1'b1;
        end
        if (s_pio_tx_pop) begin
          s_pio_tx_rd_q    <= s_pio_tx_rd_q + 1'b1;
          s_pio_tx_bytes_q <= s_pio_tx_bytes_q + {29'd0, s_pio_tx_head_bytes};
        end
        unique case ({
          s_pio_tx_push, s_pio_tx_pop
        })
          2'b10: s_pio_tx_count_q <= s_pio_tx_count_q + 1'b1;
          2'b01: s_pio_tx_count_q <= s_pio_tx_count_q - 1'b1;
          default: begin
          end
        endcase
      end

      if (s_data_rx_valid && s_data_rx_ready && !data_dma_enable_i) begin
        s_pio_rdata_q <= s_data_rx_data;
        s_pio_valid_q <= 1'b1;
      end
      if (pio_read_consume_i) begin
        s_pio_valid_q <= 1'b0;
      end
      unique case ({
        s_cmd_crc_event, s_data_crc_event
      })
        2'b10, 2'b01: s_crc_err_count_q <= s_crc_err_count_q + 1'b1;
        2'b11:        s_crc_err_count_q <= s_crc_err_count_q + 32'd2;
        default: begin
        end
      endcase
      if (s_cmd_timeout_event || s_data_timeout_event || s_busy_timeout_event) begin
        s_timeout_count_q <= s_timeout_count_q + 1'b1;
      end
      if (s_dma_err_event) begin
        s_axi_err_count_q <= s_axi_err_count_q + 1'b1;
      end
      if ((s_data_tx_valid && !s_data_tx_ready) || (s_data_rx_valid && !s_data_rx_ready)) begin
        s_stall_count_q <= s_stall_count_q + 1'b1;
      end

      if (s_abort_request && s_core_busy) begin
        s_abort_pending_q <= 1'b1;
      end else if (s_abort_pending_q && !s_core_busy) begin
        s_abort_pending_q <= 1'b0;
      end
    end
  end

  always_comb begin
    s_dat1_seen_d = s_dat1_seen_q;
    if (s_dat1_sync_q) begin
      s_dat1_seen_d = 1'b0;
    end else if (s_dat1_qualify) begin
      s_dat1_seen_d = 1'b1;
    end
  end

`ifndef SYNTHESIS
  initial begin
    if ((AddrWidth < 4) || (DataWidth != 32) || (DescCount < 1)) begin
      $fatal(1, "sdio_core: unsupported geometry");
    end
  end
`endif
endmodule
