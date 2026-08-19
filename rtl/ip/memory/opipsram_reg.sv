// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

`include "opipsram_define.svh"

module opipsram_reg (
    // verilog_format: off -- preserve reviewed port alignment
    input  logic                    clk_i,
    input  logic                    rst_n_i,
    apb4_if.slave                   apb4,
    input  logic                    busy_i,
    input  logic                    initialized_i,
    input  logic                    ready_i,
    input  logic                    quiesced_i,
    input  logic                    trained_i,
    input  logic                    error_i,
    input  logic                    profile_lock_i,
    input  logic                    profile_hyper_i,
    input  logic [31:0]             profile_status_i,
    input  logic [31:0]             train_status_i,
    input  logic [31:0]             train_window_i,
    input  opipsram_pkg::opipsram_error_e last_error_i,
    input  logic [31:0]             last_error_addr_i,
    input  logic                    init_done_event_i,
    input  logic                    indirect_done_event_i,
    input  logic                    train_done_event_i,
    input  logic                    error_event_i,
    input  logic                    timeout_event_i,
    input  logic [3:0]              perf_read_bytes_event_i,
    input  logic [3:0]              perf_write_bytes_event_i,
    input  logic                    perf_command_event_i,
    input  logic                    perf_cache_hit_event_i,
    input  logic                    perf_stall_event_i,
    input  logic                    perf_error_event_i,
    input  logic [63:0]             indirect_rdata_i,
    output logic                    controller_enable_o,
    output logic                    memory_enable_o,
    output logic                    auto_init_o,
    output logic                    line_buffer_o,
    output logic                    protocol_hyper_o,
    output logic [31:0]             device_size_o,
    output logic [31:0]             opi_read_cmd_o,
    output logic [31:0]             opi_write_cmd_o,
    output logic [31:0]             opi_reg_read_cmd_o,
    output logic [31:0]             opi_reg_write_cmd_o,
    output logic [31:0]             opi_timing_o,
    output logic [31:0]             hyper_timing_o,
    output logic [31:0]             clk_config_o,
    output logic [31:0]             cs_timing_o,
    output logic [31:0]             powerup_cycles_o,
    output logic [31:0]             timeout_cycles_o,
    output logic [7:0]              rx_delay_o,
    output logic                    init_o,
    output logic                    abort_o,
    output logic                    soft_reset_o,
    output logic                    train_o,
    output logic                    indirect_start_o,
    output logic                    indirect_write_o,
    output logic                    indirect_register_o,
    output logic [3:0]              indirect_length_o,
    output logic [31:0]             indirect_addr_o,
    output logic [63:0]             indirect_wdata_o,
    output logic                    irq_o
    // verilog_format: on
);

  import opipsram_pkg::*;

  localparam logic [31:0] CTRL_WRITABLE_MASK = 32'h0000_000F;
  localparam logic [31:0] INDIRECT_WRITABLE_MASK = 32'h0000_01F3;
  localparam logic [31:0] PERF_WRITABLE_MASK = 32'h0000_0007;

  logic        s_req;
  logic        s_write;
  logic [11:0] s_offset;
  logic        s_aligned;
  logic        s_access_err;
  logic [31:0] s_read_data;
  logic        s_ready_d;
  logic        s_ready_q;
  logic        s_resp_err_d;
  logic        s_resp_err_q;
  logic [31:0] s_rdata_d;
  logic [31:0] s_rdata_q;
  logic        s_write_accept;

  logic [31:0] s_ctrl_d;
  logic [31:0] s_ctrl_q;
  logic [31:0] s_protocol_d;
  logic [31:0] s_protocol_q;
  logic [31:0] s_device_size_d;
  logic [31:0] s_device_size_q;
  logic [31:0] s_opi_read_cmd_d;
  logic [31:0] s_opi_read_cmd_q;
  logic [31:0] s_opi_write_cmd_d;
  logic [31:0] s_opi_write_cmd_q;
  logic [31:0] s_opi_reg_read_cmd_d;
  logic [31:0] s_opi_reg_read_cmd_q;
  logic [31:0] s_opi_reg_write_cmd_d;
  logic [31:0] s_opi_reg_write_cmd_q;
  logic [31:0] s_opi_timing_d;
  logic [31:0] s_opi_timing_q;
  logic [31:0] s_hyper_timing_d;
  logic [31:0] s_hyper_timing_q;
  logic [31:0] s_clk_config_d;
  logic [31:0] s_clk_config_q;
  logic [31:0] s_cs_timing_d;
  logic [31:0] s_cs_timing_q;
  logic [31:0] s_powerup_d;
  logic [31:0] s_powerup_q;
  logic [31:0] s_timeout_d;
  logic [31:0] s_timeout_q;
  logic [ 7:0] s_rx_delay_d;
  logic [ 7:0] s_rx_delay_q;
  logic [31:0] s_indirect_ctrl_d;
  logic [31:0] s_indirect_ctrl_q;
  logic [31:0] s_indirect_addr_d;
  logic [31:0] s_indirect_addr_q;
  logic [63:0] s_indirect_wdata_d;
  logic [63:0] s_indirect_wdata_q;
  logic [ 4:0] s_intr_state_q;
  logic [ 4:0] s_intr_en_d;
  logic [ 4:0] s_intr_en_q;
  logic [ 2:0] s_perf_ctrl_d;
  logic [ 2:0] s_perf_ctrl_q;
  logic [31:0] s_perf_read_bytes_d;
  logic [31:0] s_perf_read_bytes_q;
  logic [31:0] s_perf_write_bytes_d;
  logic [31:0] s_perf_write_bytes_q;
  logic [31:0] s_perf_commands_d;
  logic [31:0] s_perf_commands_q;
  logic [31:0] s_perf_cache_hits_d;
  logic [31:0] s_perf_cache_hits_q;
  logic [31:0] s_perf_stall_d;
  logic [31:0] s_perf_stall_q;
  logic [31:0] s_perf_errs_d;
  logic [31:0] s_perf_errs_q;

  logic [31:0] s_ctrl_write_value;
  logic [31:0] s_protocol_write_value;
  logic [31:0] s_device_size_write_value;
  logic [31:0] s_indirect_ctrl_write_value;
  logic [ 2:0] s_perf_ctrl_write_value;
  logic [ 4:0] s_intr_set;
  logic [ 4:0] s_intr_clear;
  logic [ 4:0] s_intr_next;

  function automatic logic [31:0] merge_wstrb(input logic [31:0] current, input logic [31:0] value,
                                              input logic [3:0] strobe);
    logic [31:0] merged;
    begin
      merged = current;
      for (int byte_index = 0; byte_index < 4; byte_index++) begin
        if (strobe[byte_index]) merged[(byte_index*8)+:8] = value[(byte_index*8)+:8];
      end
      return merged;
    end
  endfunction

  function automatic logic is_power_of_two(input logic [31:0] value);
    return (value != 32'd0) && ((value & (value - 32'd1)) == 32'd0);
  endfunction

  function automatic logic [31:0] saturating_add(input logic [31:0] value,
                                                 input logic [3:0] increment);
    logic [32:0] result;
    begin
      result = {1'b0, value} + {29'd0, increment};
      return result[32] ? 32'hFFFF_FFFF : result[31:0];
    end
  endfunction

  function automatic logic [31:0] saturating_increment(input logic [31:0] value);
    return (&value) ? value : (value + 32'd1);
  endfunction

  assign s_req = apb4.psel && apb4.penable && !s_ready_q;
  assign s_write = apb4.pwrite;
  assign s_offset = apb4.paddr[11:0];
  assign s_aligned = apb4.paddr[1:0] == 2'b00;
  assign s_ctrl_write_value = merge_wstrb(s_ctrl_q, apb4.pwdata, apb4.pstrb) & CTRL_WRITABLE_MASK;
  assign s_protocol_write_value = merge_wstrb(
      s_protocol_q, apb4.pwdata, apb4.pstrb
  ) & 32'h0000_0001;
  assign s_device_size_write_value = merge_wstrb(s_device_size_q, apb4.pwdata, apb4.pstrb);
  assign s_indirect_ctrl_write_value = merge_wstrb(
      s_indirect_ctrl_q, apb4.pwdata, apb4.pstrb
  ) & INDIRECT_WRITABLE_MASK;
  assign s_perf_ctrl_write_value = 3'(merge_wstrb(
      {29'd0, s_perf_ctrl_q}, apb4.pwdata, apb4.pstrb
  ) & PERF_WRITABLE_MASK);
  assign s_write_accept = s_req && s_write && !s_access_err;

  assign apb4.pready = s_ready_q;
  assign apb4.prdata = s_rdata_q;
  assign apb4.pslverr = s_resp_err_q;

  assign controller_enable_o = s_ctrl_q[`APB4_OPIPSRAM__CTRL_ENABLE];
  assign memory_enable_o = s_ctrl_q[`APB4_OPIPSRAM__CTRL_MEMORY_ENABLE];
  assign auto_init_o = s_ctrl_q[`APB4_OPIPSRAM__CTRL_AUTO_INIT];
  assign line_buffer_o = s_ctrl_q[`APB4_OPIPSRAM__CTRL_LINE_BUFFER];
  assign protocol_hyper_o = s_protocol_q[`APB4_OPIPSRAM__PROTOCOL_HYPER];
  assign device_size_o = s_device_size_q;
  assign opi_read_cmd_o = s_opi_read_cmd_q;
  assign opi_write_cmd_o = s_opi_write_cmd_q;
  assign opi_reg_read_cmd_o = s_opi_reg_read_cmd_q;
  assign opi_reg_write_cmd_o = s_opi_reg_write_cmd_q;
  assign opi_timing_o = s_opi_timing_q;
  assign hyper_timing_o = s_hyper_timing_q;
  assign clk_config_o = s_clk_config_q;
  assign cs_timing_o = s_cs_timing_q;
  assign powerup_cycles_o = s_powerup_q;
  assign timeout_cycles_o = s_timeout_q;
  assign rx_delay_o = s_rx_delay_q;
  assign init_o = s_write_accept && (s_offset == `APB4_OPIPSRAM__COMMAND) &&
      apb4.pstrb[0] && apb4.pwdata[`APB4_OPIPSRAM__COMMAND_INIT];
  assign abort_o = s_write_accept && (s_offset == `APB4_OPIPSRAM__COMMAND) &&
      apb4.pstrb[0] && apb4.pwdata[`APB4_OPIPSRAM__COMMAND_ABORT];
  assign soft_reset_o = s_write_accept && (s_offset == `APB4_OPIPSRAM__COMMAND) &&
      apb4.pstrb[0] && apb4.pwdata[`APB4_OPIPSRAM__COMMAND_SOFT_RESET];
  assign train_o = s_write_accept && (s_offset == `APB4_OPIPSRAM__COMMAND) &&
      apb4.pstrb[0] && apb4.pwdata[`APB4_OPIPSRAM__COMMAND_TRAIN];
  assign indirect_start_o = s_write_accept && (s_offset == `APB4_OPIPSRAM__INDIRECT_CTRL) &&
      apb4.pstrb[0] && s_indirect_ctrl_write_value[`APB4_OPIPSRAM__INDIRECT_START];
  assign indirect_write_o = indirect_start_o ?
      s_indirect_ctrl_write_value[`APB4_OPIPSRAM__INDIRECT_WRITE] :
      s_indirect_ctrl_q[`APB4_OPIPSRAM__INDIRECT_WRITE];
  assign indirect_register_o = indirect_start_o ?
      s_indirect_ctrl_write_value[`APB4_OPIPSRAM__INDIRECT_REGISTER] :
      s_indirect_ctrl_q[`APB4_OPIPSRAM__INDIRECT_REGISTER];
  assign indirect_length_o = indirect_start_o ?
      ((s_indirect_ctrl_write_value[7:4] == 4'd0) ? 4'd1 :
       s_indirect_ctrl_write_value[7:4]) :
      ((s_indirect_ctrl_q[7:4] == 4'd0) ? 4'd1 : s_indirect_ctrl_q[7:4]);
  assign indirect_addr_o = s_indirect_addr_q;
  assign indirect_wdata_o = s_indirect_wdata_q;
  assign irq_o = |(s_intr_state_q & s_intr_en_q);

  always_comb begin
    s_access_err = !s_aligned;
    s_read_data  = 32'd0;
    if (s_aligned) begin
      unique case (s_offset)
        `APB4_OPIPSRAM__IP_ID: begin
          s_read_data  = `APB4_OPIPSRAM__IP_ID_VALUE;
          s_access_err = s_write;
        end
        `APB4_OPIPSRAM__IP_VERSION: begin
          s_read_data  = `APB4_OPIPSRAM__IP_VERSION_VALUE;
          s_access_err = s_write;
        end
        `APB4_OPIPSRAM__CAPABILITY: begin
          s_read_data  = `APB4_OPIPSRAM__CAPABILITY_VALUE;
          s_access_err = s_write;
        end
        `APB4_OPIPSRAM__CTRL: begin
          s_read_data  = s_ctrl_q;
          s_access_err = s_write && busy_i;
        end
        `APB4_OPIPSRAM__COMMAND: begin
          s_access_err = !s_write || !apb4.pstrb[0] ||
              (apb4.pwdata[3:0] == 4'd0) ||
              (|(apb4.pwdata[3:0] & (apb4.pwdata[3:0] - 4'd1))) ||
              (busy_i && (apb4.pwdata[`APB4_OPIPSRAM__COMMAND_INIT] ||
                          apb4.pwdata[`APB4_OPIPSRAM__COMMAND_TRAIN]));
        end
        `APB4_OPIPSRAM__STATUS: begin
          s_read_data = {
            24'd0,
            profile_hyper_i,
            profile_lock_i,
            error_i,
            trained_i,
            quiesced_i,
            ready_i,
            initialized_i,
            busy_i
          };
          s_access_err = s_write;
        end
        `APB4_OPIPSRAM__PROTOCOL_CFG: begin
          s_read_data  = {30'd0, profile_lock_i, s_protocol_q[0]};
          s_access_err = s_write && (profile_lock_i || busy_i);
        end
        `APB4_OPIPSRAM__DEVICE_SIZE: begin
          s_read_data = s_device_size_q;
          s_access_err = s_write &&
              (profile_lock_i || busy_i || !is_power_of_two(s_device_size_write_value) ||
               (s_device_size_write_value > 32'h0800_0000));
        end
        `APB4_OPIPSRAM__OPI_READ_CMD: begin
          s_read_data  = s_opi_read_cmd_q;
          s_access_err = s_write && (profile_lock_i || busy_i);
        end
        `APB4_OPIPSRAM__OPI_WRITE_CMD: begin
          s_read_data  = s_opi_write_cmd_q;
          s_access_err = s_write && (profile_lock_i || busy_i);
        end
        `APB4_OPIPSRAM__OPI_REG_READ_CMD: begin
          s_read_data  = s_opi_reg_read_cmd_q;
          s_access_err = s_write && (profile_lock_i || busy_i);
        end
        `APB4_OPIPSRAM__OPI_REG_WRITE_CMD: begin
          s_read_data  = s_opi_reg_write_cmd_q;
          s_access_err = s_write && (profile_lock_i || busy_i);
        end
        `APB4_OPIPSRAM__OPI_TIMING: begin
          s_read_data  = s_opi_timing_q;
          s_access_err = s_write && (profile_lock_i || busy_i);
        end
        `APB4_OPIPSRAM__HYPER_TIMING: begin
          s_read_data  = s_hyper_timing_q;
          s_access_err = s_write && (profile_lock_i || busy_i);
        end
        `APB4_OPIPSRAM__CLK_CONFIG: begin
          s_read_data  = s_clk_config_q;
          s_access_err = s_write && (profile_lock_i || busy_i);
        end
        `APB4_OPIPSRAM__CS_TIMING: begin
          s_read_data  = s_cs_timing_q;
          s_access_err = s_write && (profile_lock_i || busy_i);
        end
        `APB4_OPIPSRAM__POWERUP_CYCLES: begin
          s_read_data = s_powerup_q;
          s_access_err = s_write && (profile_lock_i || busy_i ||
                                     (merge_wstrb(s_powerup_q, apb4.pwdata, apb4.pstrb) == 32'd0));
        end
        `APB4_OPIPSRAM__TIMEOUT_CYCLES: begin
          s_read_data = s_timeout_q;
          s_access_err = s_write && (profile_lock_i || busy_i ||
                                     (merge_wstrb(s_timeout_q, apb4.pwdata, apb4.pstrb) == 32'd0));
        end
        `APB4_OPIPSRAM__RX_DELAY: begin
          s_read_data  = {24'd0, s_rx_delay_q};
          s_access_err = s_write && busy_i;
        end
        `APB4_OPIPSRAM__PROFILE_STATUS: begin
          s_read_data  = profile_status_i;
          s_access_err = s_write;
        end
        `APB4_OPIPSRAM__INDIRECT_CTRL: begin
          s_read_data = s_indirect_ctrl_q & 32'h0000_01F3;
          s_access_err = s_write && (busy_i || (s_indirect_ctrl_write_value[7:4] > 4'd8) ||
              (s_indirect_ctrl_write_value[7:4] == 4'd0 && !s_indirect_ctrl_write_value[8]));
          if (s_write && s_indirect_ctrl_write_value[8] && !apb4.pstrb[0]) s_access_err = 1'b1;
        end
        `APB4_OPIPSRAM__INDIRECT_ADDR: begin
          s_read_data  = s_indirect_addr_q;
          s_access_err = s_write && busy_i;
        end
        `APB4_OPIPSRAM__INDIRECT_WDATA_LO: begin
          s_read_data  = s_indirect_wdata_q[31:0];
          s_access_err = s_write && busy_i;
        end
        `APB4_OPIPSRAM__INDIRECT_WDATA_HI: begin
          s_read_data  = s_indirect_wdata_q[63:32];
          s_access_err = s_write && busy_i;
        end
        `APB4_OPIPSRAM__INDIRECT_RDATA_LO: begin
          s_read_data  = indirect_rdata_i[31:0];
          s_access_err = s_write;
        end
        `APB4_OPIPSRAM__INDIRECT_RDATA_HI: begin
          s_read_data  = indirect_rdata_i[63:32];
          s_access_err = s_write;
        end
        `APB4_OPIPSRAM__LAST_ERROR: begin
          s_read_data  = {28'd0, last_error_i};
          s_access_err = s_write;
        end
        `APB4_OPIPSRAM__LAST_ERROR_ADDR: begin
          s_read_data  = last_error_addr_i;
          s_access_err = s_write;
        end
        `APB4_OPIPSRAM__TRAIN_STATUS: begin
          s_read_data  = train_status_i;
          s_access_err = s_write;
        end
        `APB4_OPIPSRAM__TRAIN_WINDOW: begin
          s_read_data  = train_window_i;
          s_access_err = s_write;
        end
        `APB4_OPIPSRAM__INTR_STATE: begin
          s_read_data  = {27'd0, s_intr_state_q};
          s_access_err = s_write && !apb4.pstrb[0];
        end
        `APB4_OPIPSRAM__INTR_ENABLE: begin
          s_read_data = {27'd0, s_intr_en_q};
        end
        `APB4_OPIPSRAM__INTR_STATUS: begin
          s_read_data  = {27'd0, s_intr_state_q & s_intr_en_q};
          s_access_err = s_write;
        end
        `APB4_OPIPSRAM__INTR_TEST: begin
          s_access_err = !s_write || !apb4.pstrb[0];
        end
        `APB4_OPIPSRAM__PERF_CTRL: begin
          s_read_data  = {29'd0, s_perf_ctrl_q};
          s_access_err = s_write && !apb4.pstrb[0] && apb4.pwdata[2];
        end
        `APB4_OPIPSRAM__PERF_READ_BYTES: begin
          s_read_data  = s_perf_read_bytes_q;
          s_access_err = s_write;
        end
        `APB4_OPIPSRAM__PERF_WRITE_BYTES: begin
          s_read_data  = s_perf_write_bytes_q;
          s_access_err = s_write;
        end
        `APB4_OPIPSRAM__PERF_COMMANDS: begin
          s_read_data  = s_perf_commands_q;
          s_access_err = s_write;
        end
        `APB4_OPIPSRAM__PERF_CACHE_HITS: begin
          s_read_data  = s_perf_cache_hits_q;
          s_access_err = s_write;
        end
        `APB4_OPIPSRAM__PERF_STALL_CYCLES: begin
          s_read_data  = s_perf_stall_q;
          s_access_err = s_write;
        end
        `APB4_OPIPSRAM__PERF_ERROR_COUNT: begin
          s_read_data  = s_perf_errs_q;
          s_access_err = s_write;
        end
        default: s_access_err = 1'b1;
      endcase
    end
  end

`ifndef SYNTHESIS
`ifndef SV_ASSRT_DISABLE
  always_ff @(posedge clk_i) begin
    if (rst_n_i && indirect_start_o) begin
      assert (indirect_write_o == s_indirect_ctrl_write_value[`APB4_OPIPSRAM__INDIRECT_WRITE]);
      assert (indirect_register_o == s_indirect_ctrl_write_value[
          `APB4_OPIPSRAM__INDIRECT_REGISTER]);
      assert (indirect_length_o == ((s_indirect_ctrl_write_value[7:4] == 4'd0) ?
          4'd1 : s_indirect_ctrl_write_value[7:4]));
    end
  end
`endif
`endif

  always_comb begin
    s_intr_set = {
      timeout_event_i, error_event_i, train_done_event_i, indirect_done_event_i, init_done_event_i
    };
    s_intr_clear = 5'd0;
    if (s_write_accept && (s_offset == `APB4_OPIPSRAM__INTR_STATE) && apb4.pstrb[0]) begin
      s_intr_clear = apb4.pwdata[4:0];
    end
    if (s_write_accept && (s_offset == `APB4_OPIPSRAM__INTR_TEST) && apb4.pstrb[0]) begin
      s_intr_set = s_intr_set | apb4.pwdata[4:0];
    end
    s_intr_next = (s_intr_state_q & ~s_intr_clear) | s_intr_set;
  end

  always_comb begin
    s_ctrl_d              = s_ctrl_write_value;
    s_protocol_d          = s_protocol_write_value;
    s_device_size_d       = s_device_size_write_value;
    s_opi_read_cmd_d      = merge_wstrb(s_opi_read_cmd_q, apb4.pwdata, apb4.pstrb);
    s_opi_write_cmd_d     = merge_wstrb(s_opi_write_cmd_q, apb4.pwdata, apb4.pstrb);
    s_opi_reg_read_cmd_d  = merge_wstrb(s_opi_reg_read_cmd_q, apb4.pwdata, apb4.pstrb);
    s_opi_reg_write_cmd_d = merge_wstrb(s_opi_reg_write_cmd_q, apb4.pwdata, apb4.pstrb);
    s_opi_timing_d        = merge_wstrb(s_opi_timing_q, apb4.pwdata, apb4.pstrb);
    s_hyper_timing_d      = merge_wstrb(s_hyper_timing_q, apb4.pwdata, apb4.pstrb);
    s_clk_config_d        = merge_wstrb(s_clk_config_q, apb4.pwdata, apb4.pstrb);
    s_cs_timing_d         = merge_wstrb(s_cs_timing_q, apb4.pwdata, apb4.pstrb);
    s_powerup_d           = merge_wstrb(s_powerup_q, apb4.pwdata, apb4.pstrb);
    s_timeout_d           = merge_wstrb(s_timeout_q, apb4.pwdata, apb4.pstrb);
    s_rx_delay_d          = 8'(merge_wstrb({24'd0, s_rx_delay_q}, apb4.pwdata, apb4.pstrb));
    s_indirect_ctrl_d     = s_indirect_ctrl_write_value & ~32'h0000_0100;
    s_indirect_addr_d     = merge_wstrb(s_indirect_addr_q, apb4.pwdata, apb4.pstrb);
    s_indirect_wdata_d    = s_indirect_wdata_q;
    if (s_offset == `APB4_OPIPSRAM__INDIRECT_WDATA_LO) begin
      s_indirect_wdata_d[31:0] = merge_wstrb(s_indirect_wdata_q[31:0], apb4.pwdata, apb4.pstrb);
    end
    if (s_offset == `APB4_OPIPSRAM__INDIRECT_WDATA_HI) begin
      s_indirect_wdata_d[63:32] = merge_wstrb(s_indirect_wdata_q[63:32], apb4.pwdata, apb4.pstrb);
    end
    s_intr_en_d   = 5'(merge_wstrb({27'd0, s_intr_en_q}, apb4.pwdata, apb4.pstrb));
    s_perf_ctrl_d = s_perf_ctrl_write_value;

    if (!(s_write_accept && (s_offset == `APB4_OPIPSRAM__CTRL))) s_ctrl_d = s_ctrl_q;
    if (!(s_write_accept && (s_offset == `APB4_OPIPSRAM__PROTOCOL_CFG)))
      s_protocol_d = s_protocol_q;
    if (!(s_write_accept && (s_offset == `APB4_OPIPSRAM__DEVICE_SIZE)))
      s_device_size_d = s_device_size_q;
    if (!(s_write_accept && (s_offset == `APB4_OPIPSRAM__OPI_READ_CMD)))
      s_opi_read_cmd_d = s_opi_read_cmd_q;
    if (!(s_write_accept && (s_offset == `APB4_OPIPSRAM__OPI_WRITE_CMD)))
      s_opi_write_cmd_d = s_opi_write_cmd_q;
    if (!(s_write_accept && (s_offset == `APB4_OPIPSRAM__OPI_REG_READ_CMD)))
      s_opi_reg_read_cmd_d = s_opi_reg_read_cmd_q;
    if (!(s_write_accept && (s_offset == `APB4_OPIPSRAM__OPI_REG_WRITE_CMD)))
      s_opi_reg_write_cmd_d = s_opi_reg_write_cmd_q;
    if (!(s_write_accept && (s_offset == `APB4_OPIPSRAM__OPI_TIMING)))
      s_opi_timing_d = s_opi_timing_q;
    if (!(s_write_accept && (s_offset == `APB4_OPIPSRAM__HYPER_TIMING)))
      s_hyper_timing_d = s_hyper_timing_q;
    if (!(s_write_accept && (s_offset == `APB4_OPIPSRAM__CLK_CONFIG)))
      s_clk_config_d = s_clk_config_q;
    if (!(s_write_accept && (s_offset == `APB4_OPIPSRAM__CS_TIMING))) s_cs_timing_d = s_cs_timing_q;
    if (!(s_write_accept && (s_offset == `APB4_OPIPSRAM__POWERUP_CYCLES)))
      s_powerup_d = s_powerup_q;
    if (!(s_write_accept && (s_offset == `APB4_OPIPSRAM__TIMEOUT_CYCLES)))
      s_timeout_d = s_timeout_q;
    if (!(s_write_accept && (s_offset == `APB4_OPIPSRAM__RX_DELAY))) s_rx_delay_d = s_rx_delay_q;
    if (!(s_write_accept && (s_offset == `APB4_OPIPSRAM__INDIRECT_CTRL)))
      s_indirect_ctrl_d = s_indirect_ctrl_q;
    if (!(s_write_accept && (s_offset == `APB4_OPIPSRAM__INDIRECT_ADDR)))
      s_indirect_addr_d = s_indirect_addr_q;
    if (!(s_write_accept && ((s_offset == `APB4_OPIPSRAM__INDIRECT_WDATA_LO) ||
                             (s_offset == `APB4_OPIPSRAM__INDIRECT_WDATA_HI)))) begin
      s_indirect_wdata_d = s_indirect_wdata_q;
    end
    if (!(s_write_accept && (s_offset == `APB4_OPIPSRAM__INTR_ENABLE))) s_intr_en_d = s_intr_en_q;
    if (!(s_write_accept && (s_offset == `APB4_OPIPSRAM__PERF_CTRL))) s_perf_ctrl_d = s_perf_ctrl_q;
  end

  always_comb begin
    s_perf_read_bytes_d  = s_perf_read_bytes_q;
    s_perf_write_bytes_d = s_perf_write_bytes_q;
    s_perf_commands_d    = s_perf_commands_q;
    s_perf_cache_hits_d  = s_perf_cache_hits_q;
    s_perf_stall_d       = s_perf_stall_q;
    s_perf_errs_d        = s_perf_errs_q;
    if (s_write_accept && (s_offset == `APB4_OPIPSRAM__PERF_CTRL) &&
        apb4.pstrb[0] && apb4.pwdata[`APB4_OPIPSRAM__PERF_CLEAR]) begin
      s_perf_read_bytes_d  = 32'd0;
      s_perf_write_bytes_d = 32'd0;
      s_perf_commands_d    = 32'd0;
      s_perf_cache_hits_d  = 32'd0;
      s_perf_stall_d       = 32'd0;
      s_perf_errs_d        = 32'd0;
    end else if (s_perf_ctrl_q[`APB4_OPIPSRAM__PERF_ENABLE] &&
                 !s_perf_ctrl_q[`APB4_OPIPSRAM__PERF_FREEZE]) begin
      if (perf_read_bytes_event_i != 4'd0)
        s_perf_read_bytes_d = saturating_add(s_perf_read_bytes_q, perf_read_bytes_event_i);
      if (perf_write_bytes_event_i != 4'd0)
        s_perf_write_bytes_d = saturating_add(s_perf_write_bytes_q, perf_write_bytes_event_i);
      if (perf_command_event_i) s_perf_commands_d = saturating_increment(s_perf_commands_q);
      if (perf_cache_hit_event_i) s_perf_cache_hits_d = saturating_increment(s_perf_cache_hits_q);
      if (perf_stall_event_i) s_perf_stall_d = saturating_increment(s_perf_stall_q);
      if (perf_error_event_i) s_perf_errs_d = saturating_increment(s_perf_errs_q);
    end
  end

  assign s_ready_d    = s_req;
  assign s_resp_err_d = s_access_err;
  assign s_rdata_d    = s_read_data;

  dffr #(
      .DATA_WIDTH(1)
  ) u_ready_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ready_d),
      .dat_o  (s_ready_q)
  );
  dffer #(
      .DATA_WIDTH(1)
  ) u_resp_err_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_req),
      .dat_i  (s_resp_err_d),
      .dat_o  (s_resp_err_q)
  );
  dffer #(
      .DATA_WIDTH(32)
  ) u_rdata_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_req),
      .dat_i  (s_rdata_d),
      .dat_o  (s_rdata_q)
  );
  dfferc #(
      .DATA_WIDTH(32),
      .RESET_VAL (32'd0)
  ) u_ctrl_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_write_accept && (s_offset == `APB4_OPIPSRAM__CTRL)),
      .dat_i  (s_ctrl_d),
      .dat_o  (s_ctrl_q)
  );
  dfferc #(
      .DATA_WIDTH(32),
      .RESET_VAL (32'd0)
  ) u_protocol_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_write_accept && (s_offset == `APB4_OPIPSRAM__PROTOCOL_CFG)),
      .dat_i  (s_protocol_d),
      .dat_o  (s_protocol_q)
  );
  dfferc #(
      .DATA_WIDTH(32),
      .RESET_VAL (`APB4_OPIPSRAM__DEVICE_SIZE_RESET)
  ) u_device_size_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_write_accept && (s_offset == `APB4_OPIPSRAM__DEVICE_SIZE)),
      .dat_i  (s_device_size_d),
      .dat_o  (s_device_size_q)
  );
  dfferc #(
      .DATA_WIDTH(32),
      .RESET_VAL (`APB4_OPIPSRAM__OPI_READ_CMD_RESET)
  ) u_opi_read_cmd_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_write_accept && (s_offset == `APB4_OPIPSRAM__OPI_READ_CMD)),
      .dat_i  (s_opi_read_cmd_d),
      .dat_o  (s_opi_read_cmd_q)
  );
  dfferc #(
      .DATA_WIDTH(32),
      .RESET_VAL (`APB4_OPIPSRAM__OPI_WRITE_CMD_RESET)
  ) u_opi_write_cmd_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_write_accept && (s_offset == `APB4_OPIPSRAM__OPI_WRITE_CMD)),
      .dat_i  (s_opi_write_cmd_d),
      .dat_o  (s_opi_write_cmd_q)
  );
  dfferc #(
      .DATA_WIDTH(32),
      .RESET_VAL (32'd0)
  ) u_opi_reg_read_cmd_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_write_accept && (s_offset == `APB4_OPIPSRAM__OPI_REG_READ_CMD)),
      .dat_i  (s_opi_reg_read_cmd_d),
      .dat_o  (s_opi_reg_read_cmd_q)
  );
  dfferc #(
      .DATA_WIDTH(32),
      .RESET_VAL (32'd0)
  ) u_opi_reg_write_cmd_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_write_accept && (s_offset == `APB4_OPIPSRAM__OPI_REG_WRITE_CMD)),
      .dat_i  (s_opi_reg_write_cmd_d),
      .dat_o  (s_opi_reg_write_cmd_q)
  );
  dfferc #(
      .DATA_WIDTH(32),
      .RESET_VAL (`APB4_OPIPSRAM__OPI_TIMING_RESET)
  ) u_opi_timing_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_write_accept && (s_offset == `APB4_OPIPSRAM__OPI_TIMING)),
      .dat_i  (s_opi_timing_d),
      .dat_o  (s_opi_timing_q)
  );
  dfferc #(
      .DATA_WIDTH(32),
      .RESET_VAL (`APB4_OPIPSRAM__HYPER_TIMING_RESET)
  ) u_hyper_timing_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_write_accept && (s_offset == `APB4_OPIPSRAM__HYPER_TIMING)),
      .dat_i  (s_hyper_timing_d),
      .dat_o  (s_hyper_timing_q)
  );
  dfferc #(
      .DATA_WIDTH(32),
      .RESET_VAL (`APB4_OPIPSRAM__CLK_CONFIG_RESET)
  ) u_clk_config_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_write_accept && (s_offset == `APB4_OPIPSRAM__CLK_CONFIG)),
      .dat_i  (s_clk_config_d),
      .dat_o  (s_clk_config_q)
  );
  dfferc #(
      .DATA_WIDTH(32),
      .RESET_VAL (`APB4_OPIPSRAM__CS_TIMING_RESET)
  ) u_cs_timing_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_write_accept && (s_offset == `APB4_OPIPSRAM__CS_TIMING)),
      .dat_i  (s_cs_timing_d),
      .dat_o  (s_cs_timing_q)
  );
  dfferc #(
      .DATA_WIDTH(32),
      .RESET_VAL (`APB4_OPIPSRAM__POWERUP_RESET)
  ) u_powerup_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_write_accept && (s_offset == `APB4_OPIPSRAM__POWERUP_CYCLES)),
      .dat_i  (s_powerup_d),
      .dat_o  (s_powerup_q)
  );
  dfferc #(
      .DATA_WIDTH(32),
      .RESET_VAL (`APB4_OPIPSRAM__TIMEOUT_RESET)
  ) u_timeout_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_write_accept && (s_offset == `APB4_OPIPSRAM__TIMEOUT_CYCLES)),
      .dat_i  (s_timeout_d),
      .dat_o  (s_timeout_q)
  );
  dfferc #(
      .DATA_WIDTH(8),
      .RESET_VAL (8'd0)
  ) u_rx_delay_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_write_accept && (s_offset == `APB4_OPIPSRAM__RX_DELAY)),
      .dat_i  (s_rx_delay_d),
      .dat_o  (s_rx_delay_q)
  );
  dfferc #(
      .DATA_WIDTH(32),
      .RESET_VAL (32'd0)
  ) u_indirect_ctrl_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_write_accept && (s_offset == `APB4_OPIPSRAM__INDIRECT_CTRL)),
      .dat_i  (s_indirect_ctrl_d),
      .dat_o  (s_indirect_ctrl_q)
  );
  dfferc #(
      .DATA_WIDTH(32),
      .RESET_VAL (32'd0)
  ) u_indirect_addr_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_write_accept && (s_offset == `APB4_OPIPSRAM__INDIRECT_ADDR)),
      .dat_i  (s_indirect_addr_d),
      .dat_o  (s_indirect_addr_q)
  );
  dfferc #(
      .DATA_WIDTH(64),
      .RESET_VAL (64'd0)
  ) u_indirect_wdata_dfferc (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .en_i(s_write_accept && ((s_offset == `APB4_OPIPSRAM__INDIRECT_WDATA_LO) ||
                               (s_offset == `APB4_OPIPSRAM__INDIRECT_WDATA_HI))),
      .dat_i(s_indirect_wdata_d),
      .dat_o(s_indirect_wdata_q)
  );
  dffr #(
      .DATA_WIDTH(5)
  ) u_intr_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_intr_next),
      .dat_o  (s_intr_state_q)
  );
  dfferc #(
      .DATA_WIDTH(5),
      .RESET_VAL (5'd0)
  ) u_intr_enable_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_write_accept && (s_offset == `APB4_OPIPSRAM__INTR_ENABLE)),
      .dat_i  (s_intr_en_d),
      .dat_o  (s_intr_en_q)
  );
  dfferc #(
      .DATA_WIDTH(3),
      .RESET_VAL (3'd0)
  ) u_perf_ctrl_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_write_accept && (s_offset == `APB4_OPIPSRAM__PERF_CTRL)),
      .dat_i  (s_perf_ctrl_d),
      .dat_o  (s_perf_ctrl_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_read_bytes_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_read_bytes_d),
      .dat_o  (s_perf_read_bytes_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_write_bytes_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_write_bytes_d),
      .dat_o  (s_perf_write_bytes_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_commands_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_commands_d),
      .dat_o  (s_perf_commands_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_cache_hits_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_cache_hits_d),
      .dat_o  (s_perf_cache_hits_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_stall_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_stall_d),
      .dat_o  (s_perf_stall_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_errors_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_errs_d),
      .dat_o  (s_perf_errs_q)
  );

endmodule
