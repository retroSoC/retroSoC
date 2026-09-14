// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "ga2d_define.svh"

module ga2d_reg (
    // verilog_format: off -- preserve the APB, lifecycle, and event boundary columns
    input  logic                  clk_i,
    input  logic                  rst_n_i,
    input  logic                  busy_i,
    input  logic                  draining_i,
    input  logic                  quiesced_i,
    input  logic                  data_ready_i,
    input  logic                  recovery_required_i,
    input  logic                  idle_i,
    input  logic                  done_i,
    input  logic                  aborted_i,
    input  logic                  error_i,
    input  logic [2:0]            irq_event_i,
    input  logic                  error_valid_i,
    input  logic [6:0]            error_code_i,
    input  logic [3:0]            error_stage_i,
    input  logic [1:0]            error_axi_response_i,
    input  logic [31:0]           error_address_i,
    input  logic [63:0]           cycles_i,
    input  logic [63:0]           read_bytes_i,
    input  logic [63:0]           write_bytes_i,
    input  logic [63:0]           read_stalls_i,
    input  logic [63:0]           write_stalls_i,
    input  logic [63:0]           pipe_stalls_i,
    input  logic [15:0]           lines_done_i,
    apb4_if.slave                 apb4,
    output ga2d_pkg::ga2d_config_t config_o,
    output logic                  start_o,
    output logic                  soft_reset_o,
    output logic                  abort_o,
    output logic                  snapshot_o,
    output logic                  idle_o,
    output logic                  irq_o
    // verilog_format: on
);
  import ga2d_pkg::ga2d_config_t;
  import ga2d_pkg::ga2d_error_t;

  localparam ga2d_config_t ConfigReset = '{
      timeout_cycles: `APB4_GA2D__TIMEOUT_CYCLES_RESET,
      job_config: '0,
      global_alpha: `APB4_GA2D__GLOBAL_ALPHA_RESET,
      color: '0,
      size: '0,
      fg_address: '0,
      fg_pitch: '0,
      fg_format: '0,
      bg_address: '0,
      bg_pitch: '0,
      bg_format: '0,
      dst_address: '0,
      dst_pitch: '0,
      dst_format: '0
  };

  logic s_apb4_ready_d, s_apb4_ready_q;
  logic s_access_seen_d, s_access_seen_q;
  logic [31:0] s_apb4_rdata_d, s_apb4_rdata_q;
  logic s_apb4_resp_err_d, s_apb4_resp_err_q;
  ga2d_config_t s_config_d, s_config_q;
  ga2d_error_t s_err_d, s_err_q;
  logic [2:0] s_irq_state_d, s_irq_state_q;
  logic [2:0] s_irq_en_d, s_irq_en_q;
  logic [63:0] s_snap_cycles_d, s_snap_cycles_q;
  logic [63:0] s_snap_read_bytes_d, s_snap_read_bytes_q;
  logic [63:0] s_snap_write_bytes_d, s_snap_write_bytes_q;
  logic [63:0] s_snap_read_stalls_d, s_snap_read_stalls_q;
  logic [63:0] s_snap_write_stalls_d, s_snap_write_stalls_q;
  logic [63:0] s_snap_pipe_stalls_d, s_snap_pipe_stalls_q;
  logic [15:0] s_snap_lines_done_d, s_snap_lines_done_q;
  logic        s_req_accept;
  logic        s_write;
  logic [11:0] s_offset;
  logic [31:0] s_write_value;
  logic [31:0] s_read_data;
  logic        s_read_valid;
  logic        s_read_err;
  logic        s_write_err;
  logic [ 2:0] s_irq_clear;
  logic [ 2:0] s_irq_test;
  logic        s_err_clear;
  logic        s_cmd_soft_reset;
  logic        s_cmd_abort;
  logic        s_cmd_start;
  logic        s_cmd_snapshot;

  assign s_req_accept = apb4.psel && apb4.penable && !s_access_seen_q;
  assign s_write = s_req_accept && apb4.pwrite;
  assign s_offset = apb4.paddr[11:0];
  assign s_write_value = apb4.pwdata;
  assign s_cmd_abort   = s_write && (s_offset[1:0] == 2'b00) && (apb4.pstrb == 4'hf) &&
                       (s_offset == `APB4_GA2D__COMMAND) && (s_write_value == 32'h0000_0002);

  assign apb4.pready = s_apb4_ready_q;
  assign apb4.prdata = s_apb4_rdata_q;
  assign apb4.pslverr = s_apb4_resp_err_q;
  assign config_o = s_config_q;
  assign start_o = s_cmd_start;
  assign soft_reset_o = s_cmd_soft_reset;
  assign abort_o = s_cmd_abort;
  assign snapshot_o = s_cmd_snapshot;
  assign idle_o = idle_i;
  assign irq_o = (s_irq_state_q & s_irq_en_q) != 3'd0;

  always_comb begin
    s_read_data  = 32'd0;
    s_read_valid = 1'b1;
    unique case (s_offset)
      `APB4_GA2D__IP_ID: s_read_data = `APB4_GA2D__IP_ID_VALUE;
      `APB4_GA2D__IP_VERSION: s_read_data = `APB4_GA2D__IP_VERSION_VALUE;
      `APB4_GA2D__CAPABILITY: s_read_data = `APB4_GA2D__CAPABILITY_P4;
      `APB4_GA2D__LIMITS: s_read_data = `APB4_GA2D__LIMITS_P4;
      `APB4_GA2D__STATUS:
      s_read_data = {
        24'd0,
        recovery_required_i,
        error_i,
        aborted_i,
        done_i,
        data_ready_i,
        quiesced_i,
        draining_i,
        busy_i
      };
      `APB4_GA2D__IRQ_STATE: s_read_data = {29'd0, s_irq_state_q};
      `APB4_GA2D__IRQ_ENABLE: s_read_data = {29'd0, s_irq_en_q};
      `APB4_GA2D__ERROR_STATUS:
      s_read_data = {18'd0, s_err_q.axi_response, s_err_q.stage, s_err_q.code, s_err_q.valid};
      `APB4_GA2D__ERROR_ADDRESS: s_read_data = s_err_q.address;
      `APB4_GA2D__TIMEOUT_CYCLES: s_read_data = s_config_q.timeout_cycles;
      `APB4_GA2D__JOB_CONFIG: s_read_data = s_config_q.job_config;
      `APB4_GA2D__GLOBAL_ALPHA: s_read_data = s_config_q.global_alpha;
      `APB4_GA2D__COLOR: s_read_data = s_config_q.color;
      `APB4_GA2D__SIZE: s_read_data = s_config_q.size;
      `APB4_GA2D__FG_ADDRESS: s_read_data = s_config_q.fg_address;
      `APB4_GA2D__FG_PITCH: s_read_data = s_config_q.fg_pitch;
      `APB4_GA2D__FG_FORMAT: s_read_data = s_config_q.fg_format;
      `APB4_GA2D__BG_ADDRESS: s_read_data = s_config_q.bg_address;
      `APB4_GA2D__BG_PITCH: s_read_data = s_config_q.bg_pitch;
      `APB4_GA2D__BG_FORMAT: s_read_data = s_config_q.bg_format;
      `APB4_GA2D__DST_ADDRESS: s_read_data = s_config_q.dst_address;
      `APB4_GA2D__DST_PITCH: s_read_data = s_config_q.dst_pitch;
      `APB4_GA2D__DST_FORMAT: s_read_data = s_config_q.dst_format;
      `APB4_GA2D__FORMAT_CAPABILITY: s_read_data = `APB4_GA2D__FORMAT_CAPABILITY_P4;
      `APB4_GA2D__SNAP_CYCLES_LO: s_read_data = s_snap_cycles_q[31:0];
      `APB4_GA2D__SNAP_CYCLES_HI: s_read_data = s_snap_cycles_q[63:32];
      `APB4_GA2D__SNAP_READ_BYTES_LO: s_read_data = s_snap_read_bytes_q[31:0];
      `APB4_GA2D__SNAP_READ_BYTES_HI: s_read_data = s_snap_read_bytes_q[63:32];
      `APB4_GA2D__SNAP_WRITE_BYTES_LO: s_read_data = s_snap_write_bytes_q[31:0];
      `APB4_GA2D__SNAP_WRITE_BYTES_HI: s_read_data = s_snap_write_bytes_q[63:32];
      `APB4_GA2D__SNAP_READ_STALL_LO: s_read_data = s_snap_read_stalls_q[31:0];
      `APB4_GA2D__SNAP_READ_STALL_HI: s_read_data = s_snap_read_stalls_q[63:32];
      `APB4_GA2D__SNAP_WRITE_STALL_LO: s_read_data = s_snap_write_stalls_q[31:0];
      `APB4_GA2D__SNAP_WRITE_STALL_HI: s_read_data = s_snap_write_stalls_q[63:32];
      `APB4_GA2D__SNAP_PIPE_STALL_LO: s_read_data = s_snap_pipe_stalls_q[31:0];
      `APB4_GA2D__SNAP_PIPE_STALL_HI: s_read_data = s_snap_pipe_stalls_q[63:32];
      `APB4_GA2D__SNAP_LINES_DONE: s_read_data = {16'd0, s_snap_lines_done_q};
      `APB4_GA2D__COMMAND, `APB4_GA2D__IRQ_TEST, `APB4_GA2D__PERF_SNAPSHOT: begin
      end
      default: s_read_valid = 1'b0;
    endcase
  end

  always_comb begin
    s_read_err = (s_offset[1:0] != 2'b00) || !s_read_valid;
  end

  always_comb begin
    s_write_err      = 1'b0;
    s_irq_clear      = 3'd0;
    s_irq_test       = 3'd0;
    s_err_clear      = 1'b0;
    s_cmd_soft_reset = 1'b0;
    s_cmd_start      = 1'b0;
    s_cmd_snapshot   = 1'b0;
    if (s_write) begin
      if ((s_offset[1:0] != 2'b00) || (apb4.pstrb != 4'hf)) begin
        s_write_err = 1'b1;
      end else begin
        unique case (s_offset)
          `APB4_GA2D__COMMAND: begin
            unique case (s_write_value)
              32'd0: begin
              end
              32'h0000_0001: begin
                if (busy_i || draining_i || recovery_required_i || !idle_i || !data_ready_i ||
                    (s_config_q.job_config[1:0] > `APB4_GA2D__OP_COPY)) begin
                  s_write_err = 1'b1;
                end else begin
                  s_cmd_start = 1'b1;
                end
              end
              32'h0000_0002: begin
              end
              32'h0000_0004: begin
                if (busy_i || draining_i || recovery_required_i || !idle_i || !data_ready_i) begin
                  s_write_err = 1'b1;
                end else begin
                  s_cmd_soft_reset = 1'b1;
                end
              end
              default: s_write_err = 1'b1;
            endcase
          end
          `APB4_GA2D__IRQ_STATE: begin
            if (s_write_value[31:3] != '0) begin
              s_write_err = 1'b1;
            end else begin
              s_irq_clear = s_write_value[2:0];
            end
          end
          `APB4_GA2D__IRQ_ENABLE: begin
            if (s_write_value[31:3] != '0) begin
              s_write_err = 1'b1;
            end
          end
          `APB4_GA2D__IRQ_TEST: begin
            if (s_write_value[31:3] != '0) begin
              s_write_err = 1'b1;
            end else begin
              s_irq_test = s_write_value[2:0];
            end
          end
          `APB4_GA2D__ERROR_STATUS: begin
            if (busy_i || recovery_required_i ||
                ((s_write_value != 32'd0) && (s_write_value != 32'd1))) begin
              s_write_err = 1'b1;
            end else if (s_write_value == 32'd1) begin
              s_err_clear = 1'b1;
            end
          end
          `APB4_GA2D__TIMEOUT_CYCLES: begin
            if (busy_i || (s_write_value == 32'd0)) begin
              s_write_err = 1'b1;
            end
          end
          `APB4_GA2D__JOB_CONFIG: begin
            if (busy_i || (s_write_value[31:2] != '0)) begin
              s_write_err = 1'b1;
            end
          end
          `APB4_GA2D__GLOBAL_ALPHA: begin
            if (busy_i || (s_write_value[31:8] != '0)) begin
              s_write_err = 1'b1;
            end
          end
          `APB4_GA2D__COLOR,
          `APB4_GA2D__SIZE,
          `APB4_GA2D__FG_ADDRESS,
          `APB4_GA2D__FG_PITCH,
          `APB4_GA2D__BG_ADDRESS,
          `APB4_GA2D__BG_PITCH,
          `APB4_GA2D__DST_ADDRESS,
          `APB4_GA2D__DST_PITCH: begin
            if (busy_i) begin
              s_write_err = 1'b1;
            end
          end
          `APB4_GA2D__FG_FORMAT, `APB4_GA2D__BG_FORMAT, `APB4_GA2D__DST_FORMAT: begin
            if (busy_i || (s_write_value[31:3] != '0)) begin
              s_write_err = 1'b1;
            end
          end
          `APB4_GA2D__PERF_SNAPSHOT: begin
            if (s_write_value != 32'h0000_0001) begin
              s_write_err = 1'b1;
            end else begin
              s_cmd_snapshot = 1'b1;
            end
          end
          default: s_write_err = 1'b1;
        endcase
      end
    end
  end

  always_comb begin
    s_apb4_ready_d  = s_req_accept;
    s_access_seen_d = s_access_seen_q;
    if (!apb4.psel || !apb4.penable) begin
      s_access_seen_d = 1'b0;
    end else if (s_req_accept) begin
      s_access_seen_d = 1'b1;
    end
    s_apb4_rdata_d    = s_apb4_rdata_q;
    s_apb4_resp_err_d = s_req_accept && (s_write ? s_write_err : s_read_err);
    if (s_req_accept) begin
      s_apb4_rdata_d = (!s_write && !s_read_err) ? s_read_data : 32'd0;
    end

    s_config_d            = s_config_q;
    s_irq_state_d         = (s_irq_state_q & ~s_irq_clear) | irq_event_i | s_irq_test;
    s_irq_en_d            = s_irq_en_q;
    s_err_d               = s_err_q;
    s_snap_cycles_d       = s_snap_cycles_q;
    s_snap_read_bytes_d   = s_snap_read_bytes_q;
    s_snap_write_bytes_d  = s_snap_write_bytes_q;
    s_snap_read_stalls_d  = s_snap_read_stalls_q;
    s_snap_write_stalls_d = s_snap_write_stalls_q;
    s_snap_pipe_stalls_d  = s_snap_pipe_stalls_q;
    s_snap_lines_done_d   = s_snap_lines_done_q;

    if (s_err_clear) begin
      s_err_d = '0;
    end
    if (error_valid_i && !s_err_q.valid) begin
      s_err_d = '{
          valid: 1'b1,
          code: error_code_i,
          stage: error_stage_i,
          axi_response: error_axi_response_i,
          address: error_address_i
      };
    end

    if (s_cmd_soft_reset) begin
      s_config_d            = ConfigReset;
      s_irq_state_d         = '0;
      s_irq_en_d            = '0;
      s_err_d               = '0;
      s_snap_cycles_d       = '0;
      s_snap_read_bytes_d   = '0;
      s_snap_write_bytes_d  = '0;
      s_snap_read_stalls_d  = '0;
      s_snap_write_stalls_d = '0;
      s_snap_pipe_stalls_d  = '0;
      s_snap_lines_done_d   = '0;
    end else if (s_cmd_snapshot) begin
      s_snap_cycles_d       = cycles_i;
      s_snap_read_bytes_d   = read_bytes_i;
      s_snap_write_bytes_d  = write_bytes_i;
      s_snap_read_stalls_d  = read_stalls_i;
      s_snap_write_stalls_d = write_stalls_i;
      s_snap_pipe_stalls_d  = pipe_stalls_i;
      s_snap_lines_done_d   = lines_done_i;
    end else if (s_write && !s_write_err) begin
      unique case (s_offset)
        `APB4_GA2D__IRQ_ENABLE:     s_irq_en_d = s_write_value[2:0];
        `APB4_GA2D__TIMEOUT_CYCLES: s_config_d.timeout_cycles = s_write_value;
        `APB4_GA2D__JOB_CONFIG:     s_config_d.job_config = s_write_value;
        `APB4_GA2D__GLOBAL_ALPHA:   s_config_d.global_alpha = s_write_value;
        `APB4_GA2D__COLOR:          s_config_d.color = s_write_value;
        `APB4_GA2D__SIZE:           s_config_d.size = s_write_value;
        `APB4_GA2D__FG_ADDRESS:     s_config_d.fg_address = s_write_value;
        `APB4_GA2D__FG_PITCH:       s_config_d.fg_pitch = s_write_value;
        `APB4_GA2D__FG_FORMAT:      s_config_d.fg_format = s_write_value;
        `APB4_GA2D__BG_ADDRESS:     s_config_d.bg_address = s_write_value;
        `APB4_GA2D__BG_PITCH:       s_config_d.bg_pitch = s_write_value;
        `APB4_GA2D__BG_FORMAT:      s_config_d.bg_format = s_write_value;
        `APB4_GA2D__DST_ADDRESS:    s_config_d.dst_address = s_write_value;
        `APB4_GA2D__DST_PITCH:      s_config_d.dst_pitch = s_write_value;
        `APB4_GA2D__DST_FORMAT:     s_config_d.dst_format = s_write_value;
        default: begin
        end
      endcase
    end
  end

  dffr #(
      .DATA_WIDTH(1)
  ) u_apb4_ready (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_apb4_ready_d),
      .dat_o  (s_apb4_ready_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_access_seen (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_access_seen_d),
      .dat_o  (s_access_seen_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_apb4_rdata (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_apb4_rdata_d),
      .dat_o  (s_apb4_rdata_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_apb4_resp_err (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_apb4_resp_err_d),
      .dat_o  (s_apb4_resp_err_q)
  );
  dffrc #(
      .DATA_WIDTH($bits(ga2d_config_t)),
      .RESET_VAL (ConfigReset)
  ) u_config (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_config_d),
      .dat_o  (s_config_q)
  );
  dffr #(
      .DATA_WIDTH($bits(ga2d_error_t))
  ) u_error (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_d),
      .dat_o  (s_err_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_irq_state (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_irq_state_d),
      .dat_o  (s_irq_state_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_irq_enable (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_irq_en_d),
      .dat_o  (s_irq_en_q)
  );
  dffr #(
      .DATA_WIDTH(64)
  ) u_snap_cycles (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_snap_cycles_d),
      .dat_o  (s_snap_cycles_q)
  );
  dffr #(
      .DATA_WIDTH(64)
  ) u_snap_read_bytes (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_snap_read_bytes_d),
      .dat_o  (s_snap_read_bytes_q)
  );
  dffr #(
      .DATA_WIDTH(64)
  ) u_snap_write_bytes (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_snap_write_bytes_d),
      .dat_o  (s_snap_write_bytes_q)
  );
  dffr #(
      .DATA_WIDTH(64)
  ) u_snap_read_stalls (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_snap_read_stalls_d),
      .dat_o  (s_snap_read_stalls_q)
  );
  dffr #(
      .DATA_WIDTH(64)
  ) u_snap_write_stalls (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_snap_write_stalls_d),
      .dat_o  (s_snap_write_stalls_q)
  );
  dffr #(
      .DATA_WIDTH(64)
  ) u_snap_pipe_stalls (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_snap_pipe_stalls_d),
      .dat_o  (s_snap_pipe_stalls_q)
  );
  dffr #(
      .DATA_WIDTH(16)
  ) u_snap_lines_done (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_snap_lines_done_d),
      .dat_o  (s_snap_lines_done_q)
  );
endmodule
