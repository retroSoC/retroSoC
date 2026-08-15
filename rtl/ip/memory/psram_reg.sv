// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

`include "psram_define.svh"

module psram_reg (
    // verilog_format: off -- preserve reviewed port alignment
    input  logic                     clk_i,
    input  logic                     rst_n_i,
    ribp_if.slave                    ribp,
    input  logic                     init_busy_i,
    input  logic                     axi_busy_i,
    input  logic                     indirect_busy_i,
    input  logic                     phy_busy_i,
    input  logic                     quiesced_i,
    input  logic                     global_ready_i,
    input  logic [3:0]               chip_present_i,
    input  logic [3:0]               chip_ready_i,
    input  logic [3:0]               chip_qpi_i,
    input  logic [3:0]               chip_wrap32_i,
    input  logic [3:0]               chip_error_i,
    input  logic [47:0]              chip0_id_i,
    input  logic [47:0]              chip1_id_i,
    input  logic [47:0]              chip2_id_i,
    input  logic [47:0]              chip3_id_i,
    input  psram_pkg::psram_error_e  last_error_i,
    input  logic [1:0]               last_error_chip_i,
    input  logic [31:0]              last_error_addr_i,
    input  logic [63:0]              indirect_rdata_i,
    input  logic                     init_done_event_i,
    input  logic                     indirect_done_event_i,
    input  logic                     error_event_i,
    input  logic                     timeout_event_i,
    input  logic [2:0]               perf_read_byte_event_i,
    input  logic [2:0]               perf_write_byte_event_i,
    input  logic                     perf_command_event_i,
    input  logic                     perf_split_event_i,
    input  logic                     perf_stall_event_i,
    input  logic                     perf_error_event_i,
    output logic                     controller_enable_o,
    output logic                     memory_enable_o,
    output logic                     auto_init_o,
    output logic                     wrap32_o,
    output logic [3:0]               chip_enable_o,
    output logic [15:0]              half_period_o,
    output logic                     above_84mhz_o,
    output logic [31:0]              powerup_cycles_o,
    output logic [15:0]              cs_setup_cycles_o,
    output logic [15:0]              cs_high_cycles_o,
    output logic [15:0]              cs_hold_cycles_o,
    output logic [31:0]              cs_max_low_cycles_o,
    output logic [31:0]              access_timeout_cycles_o,
    output logic                     init_start_o,
    output logic                     recover_start_o,
    output logic [1:0]               recover_chip_o,
    output logic                     abort_o,
    output logic [3:0]               chip_error_clear_o,
    output logic                     indirect_start_o,
    output psram_pkg::psram_cmd_e    indirect_command_o,
    output logic [1:0]               indirect_chip_o,
    output logic [22:0]              indirect_addr_o,
    output logic [3:0]               indirect_length_o,
    output logic [63:0]              indirect_wdata_o,
    output logic                     irq_o
    // verilog_format: on
);

  import psram_pkg::*;

  localparam logic [31:0] CTRL_WRITABLE_MASK = 32'h0000_000F;
  localparam logic [31:0] CLK_WRITABLE_MASK = 32'h0001_FFFF;
  localparam logic [31:0] INDIRECT_WRITABLE_MASK = 32'h8007_030F;
  localparam logic [31:0] PERF_WRITABLE_MASK = 32'h0000_0003;

  logic        s_req;
  logic        s_write;
  logic [11:0] s_offset;
  logic        s_aligned;
  logic        s_access_err;
  logic [31:0] s_read_data;
  logic        s_ready_q;
  logic        s_resp_err_q;
  logic [31:0] s_rdata_q;

  logic [31:0] s_ctrl_q;
  logic [ 3:0] s_chip_en_q;
  logic [31:0] s_clk_config_q;
  logic [31:0] s_powerup_cycles_q;
  logic [15:0] s_cs_setup_q;
  logic [15:0] s_cs_high_q;
  logic [15:0] s_cs_hold_q;
  logic [31:0] s_cs_max_low_q;
  logic [31:0] s_access_timeout_q;
  logic [31:0] s_indirect_ctrl_q;
  logic [22:0] s_indirect_addr_q;
  logic [63:0] s_indirect_wdata_q;
  logic [ 3:0] s_intr_state_q;
  logic [ 3:0] s_intr_en_q;
  logic [ 1:0] s_perf_ctrl_q;
  logic [31:0] s_perf_read_bytes_q;
  logic [31:0] s_perf_write_bytes_q;
  logic [31:0] s_perf_commands_q;
  logic [31:0] s_perf_splits_q;
  logic [31:0] s_perf_stall_cycles_q;
  logic [31:0] s_perf_err_count_q;
  logic [ 3:0] s_intr_clear;
  logic [ 3:0] s_intr_set;
  logic [ 3:0] s_intr_next;

  logic [31:0] s_ctrl_write_value;
  logic [ 3:0] s_chip_en_write_value;
  logic [31:0] s_clk_write_value;
  logic [15:0] s_cs_setup_write_value;
  logic [15:0] s_cs_high_write_value;
  logic [15:0] s_cs_hold_write_value;
  logic [31:0] s_indirect_write_value;
  logic [22:0] s_indirect_addr_write_value;
  logic [ 3:0] s_intr_en_write_value;
  logic [ 1:0] s_perf_write_value;
  logic        s_busy;
  logic        s_timing_valid;

  function automatic logic [31:0] merge_wstrb(input logic [31:0] current, input logic [31:0] value,
                                              input logic [3:0] strobe);
    logic [31:0] merged;
    begin
      merged = current;
      for (int byte_index = 0; byte_index < 4; byte_index++) begin
        if (strobe[byte_index]) begin
          merged[(byte_index*8)+:8] = value[(byte_index*8)+:8];
        end
      end
      return merged;
    end
  endfunction

  function automatic logic [31:0] saturating_increment(input logic [31:0] value);
    return (&value) ? value : value + 1'b1;
  endfunction

  function automatic logic [31:0] saturating_add(input logic [31:0] value,
                                                 input logic [2:0] increment);
    logic [32:0] result;
    begin
      result = {1'b0, value} + {30'd0, increment};
      return result[32] ? 32'hFFFF_FFFF : result[31:0];
    end
  endfunction

  assign s_req = ribp.valid && !s_ready_q;
  assign s_write = |ribp.wstrb;
  assign s_offset = ribp.addr[11:0];
  assign s_aligned = ribp.addr[1:0] == 2'b00;
  assign s_busy = init_busy_i || axi_busy_i || indirect_busy_i || phy_busy_i;
  assign s_timing_valid = (s_clk_config_q[15:0] != 16'd0) &&
                          (s_cs_max_low_q != 32'd0) &&
                          (s_access_timeout_q != 32'd0);

  assign s_ctrl_write_value = merge_wstrb(s_ctrl_q, ribp.wdata, ribp.wstrb) & CTRL_WRITABLE_MASK;
  assign s_chip_en_write_value = 4'(merge_wstrb({28'd0, s_chip_en_q}, ribp.wdata, ribp.wstrb));
  assign s_clk_write_value = merge_wstrb(
      s_clk_config_q, ribp.wdata, ribp.wstrb
  ) & CLK_WRITABLE_MASK;
  assign s_cs_setup_write_value = 16'(merge_wstrb({16'd0, s_cs_setup_q}, ribp.wdata, ribp.wstrb));
  assign s_cs_high_write_value = 16'(merge_wstrb({16'd0, s_cs_high_q}, ribp.wdata, ribp.wstrb));
  assign s_cs_hold_write_value = 16'(merge_wstrb({16'd0, s_cs_hold_q}, ribp.wdata, ribp.wstrb));
  assign s_indirect_write_value = merge_wstrb(
      s_indirect_ctrl_q, ribp.wdata, ribp.wstrb
  ) & INDIRECT_WRITABLE_MASK;
  assign s_indirect_addr_write_value = 23'(merge_wstrb(
      {9'd0, s_indirect_addr_q}, ribp.wdata, ribp.wstrb
  ));
  assign s_intr_en_write_value = 4'(merge_wstrb({28'd0, s_intr_en_q}, ribp.wdata, ribp.wstrb));
  assign s_perf_write_value = 2'(merge_wstrb(
      {30'd0, s_perf_ctrl_q}, ribp.wdata, ribp.wstrb
  ) & PERF_WRITABLE_MASK);

  assign ribp.ready = s_ready_q;
  assign ribp.resp_err = s_resp_err_q;
  assign ribp.rdata = s_rdata_q;

  always_comb begin
    s_access_err = !s_aligned;
    s_read_data  = '0;
    if (s_aligned) begin
      unique case (s_offset)
        `RIBP_PSRAM_CTRL: begin
          s_read_data  = s_ctrl_q;
          s_access_err = s_write && s_busy && (s_ctrl_write_value != s_ctrl_q);
        end
        `RIBP_PSRAM_COMMAND: begin
          s_access_err = !s_write || !ribp.wstrb[0] ||
                           ((ribp.wdata[2:0] == 3'd0) ||
                            (|(ribp.wdata[2:0] & (ribp.wdata[2:0] - 1'b1)))) ||
                           (ribp.wdata[`PSRAM_COMMAND_RECOVER] &&
                            !s_chip_en_q[ribp.wdata[9:8]]);
        end
        `RIBP_PSRAM_STATUS: begin
          s_read_data = {
            26'd0, global_ready_i, quiesced_i, phy_busy_i, indirect_busy_i, axi_busy_i, init_busy_i
          };
          s_access_err = s_write;
        end
        `RIBP_PSRAM_CHIP_ENABLE: begin
          s_read_data  = {28'd0, s_chip_en_q};
          s_access_err = s_write && s_busy;
        end
        `RIBP_PSRAM_CHIP_PRESENT: begin
          s_read_data  = {28'd0, chip_present_i};
          s_access_err = s_write;
        end
        `RIBP_PSRAM_CHIP_READY: begin
          s_read_data  = {28'd0, chip_ready_i};
          s_access_err = s_write;
        end
        `RIBP_PSRAM_CHIP_MODE: begin
          s_read_data  = {24'd0, chip_wrap32_i, chip_qpi_i};
          s_access_err = s_write;
        end
        `RIBP_PSRAM_CHIP_ERROR:        s_read_data = {28'd0, chip_error_i};
        `RIBP_PSRAM_CLK_CONFIG: begin
          s_read_data  = s_clk_config_q;
          s_access_err = s_write && s_busy;
          if (s_write && (s_clk_write_value[15:0] == 16'd0)) begin
            s_access_err = 1'b1;
          end
        end
        `RIBP_PSRAM_POWERUP_CYCLES: begin
          s_read_data  = s_powerup_cycles_q;
          s_access_err = s_write && s_busy;
        end
        `RIBP_PSRAM_CS_SETUP_CYCLES: begin
          s_read_data  = {16'd0, s_cs_setup_q};
          s_access_err = s_write && s_busy;
        end
        `RIBP_PSRAM_CS_HIGH_CYCLES: begin
          s_read_data  = {16'd0, s_cs_high_q};
          s_access_err = s_write && s_busy;
        end
        `RIBP_PSRAM_CS_HOLD_CYCLES: begin
          s_read_data  = {16'd0, s_cs_hold_q};
          s_access_err = s_write && s_busy;
        end
        `RIBP_PSRAM_CS_MAX_LOW_CYCLES: begin
          s_read_data  = s_cs_max_low_q;
          s_access_err = s_write && (s_busy || (ribp.wdata == 32'd0));
        end
        `RIBP_PSRAM_ACCESS_TIMEOUT_CYCLES: begin
          s_read_data  = s_access_timeout_q;
          s_access_err = s_write && (s_busy || (ribp.wdata == 32'd0));
        end
        `RIBP_PSRAM_TIMING_STATUS: begin
          s_read_data  = {14'd0, s_clk_config_q[16], s_timing_valid, s_clk_config_q[15:0]};
          s_access_err = s_write;
        end
        `RIBP_PSRAM_INDIRECT_CTRL: begin
          s_read_data = s_indirect_ctrl_q & 32'h7FFF_FFFF;
          if (s_write && s_indirect_write_value[`PSRAM_INDIRECT_START]) begin
            s_access_err =
                indirect_busy_i ||
                (s_indirect_write_value[3:0] > PsramCmdReadId) ||
                !s_chip_en_q[s_indirect_write_value[9:8]];
          end
        end
        `RIBP_PSRAM_INDIRECT_ADDR:     s_read_data = {9'd0, s_indirect_addr_q};
        `RIBP_PSRAM_INDIRECT_WDATA_LO: s_read_data = s_indirect_wdata_q[31:0];
        `RIBP_PSRAM_INDIRECT_WDATA_HI: s_read_data = s_indirect_wdata_q[63:32];
        `RIBP_PSRAM_INDIRECT_RDATA_LO: begin
          s_read_data  = indirect_rdata_i[31:0];
          s_access_err = s_write;
        end
        `RIBP_PSRAM_INDIRECT_RDATA_HI: begin
          s_read_data  = indirect_rdata_i[63:32];
          s_access_err = s_write;
        end
        `RIBP_PSRAM_LAST_ERROR: begin
          s_read_data  = {24'd0, last_error_chip_i, 2'd0, last_error_i};
          s_access_err = s_write;
        end
        `RIBP_PSRAM_LAST_ERROR_ADDR: begin
          s_read_data  = last_error_addr_i;
          s_access_err = s_write;
        end
        `RIBP_PSRAM_CHIP0_ID_LO: begin
          s_read_data  = chip0_id_i[31:0];
          s_access_err = s_write;
        end
        `RIBP_PSRAM_CHIP0_ID_HI: begin
          s_read_data  = {16'd0, chip0_id_i[47:32]};
          s_access_err = s_write;
        end
        `RIBP_PSRAM_CHIP1_ID_LO: begin
          s_read_data  = chip1_id_i[31:0];
          s_access_err = s_write;
        end
        `RIBP_PSRAM_CHIP1_ID_HI: begin
          s_read_data  = {16'd0, chip1_id_i[47:32]};
          s_access_err = s_write;
        end
        `RIBP_PSRAM_CHIP2_ID_LO: begin
          s_read_data  = chip2_id_i[31:0];
          s_access_err = s_write;
        end
        `RIBP_PSRAM_CHIP2_ID_HI: begin
          s_read_data  = {16'd0, chip2_id_i[47:32]};
          s_access_err = s_write;
        end
        `RIBP_PSRAM_CHIP3_ID_LO: begin
          s_read_data  = chip3_id_i[31:0];
          s_access_err = s_write;
        end
        `RIBP_PSRAM_CHIP3_ID_HI: begin
          s_read_data  = {16'd0, chip3_id_i[47:32]};
          s_access_err = s_write;
        end
        `RIBP_PSRAM_INTR_STATE:        s_read_data = {28'd0, s_intr_state_q};
        `RIBP_PSRAM_INTR_ENABLE:       s_read_data = {28'd0, s_intr_en_q};
        `RIBP_PSRAM_INTR_STATUS: begin
          s_read_data  = {28'd0, s_intr_state_q & s_intr_en_q};
          s_access_err = s_write;
        end
        `RIBP_PSRAM_INTR_TEST:         s_access_err = !s_write || !ribp.wstrb[0];
        `RIBP_PSRAM_PERF_CTRL:         s_read_data = {30'd0, s_perf_ctrl_q};
        `RIBP_PSRAM_PERF_READ_BYTES: begin
          s_read_data  = s_perf_read_bytes_q;
          s_access_err = s_write;
        end
        `RIBP_PSRAM_PERF_WRITE_BYTES: begin
          s_read_data  = s_perf_write_bytes_q;
          s_access_err = s_write;
        end
        `RIBP_PSRAM_PERF_COMMANDS: begin
          s_read_data  = s_perf_commands_q;
          s_access_err = s_write;
        end
        `RIBP_PSRAM_PERF_SPLITS: begin
          s_read_data  = s_perf_splits_q;
          s_access_err = s_write;
        end
        `RIBP_PSRAM_PERF_STALL_CYCLES: begin
          s_read_data  = s_perf_stall_cycles_q;
          s_access_err = s_write;
        end
        `RIBP_PSRAM_PERF_ERROR_COUNT: begin
          s_read_data  = s_perf_err_count_q;
          s_access_err = s_write;
        end
        `RIBP_PSRAM_IP_VERSION: begin
          s_read_data  = `PSRAM_IP_VERSION_VALUE;
          s_access_err = s_write;
        end
        `RIBP_PSRAM_CAPABILITY: begin
          s_read_data  = `PSRAM_CAPABILITY_VALUE;
          s_access_err = s_write;
        end
        default:                       s_access_err = 1'b1;
      endcase
    end
  end

  always_comb begin
    s_intr_clear = '0;
    s_intr_set   = {timeout_event_i, error_event_i, indirect_done_event_i, init_done_event_i};
    if (s_req && s_write && !s_access_err &&
        (s_offset == `RIBP_PSRAM_INTR_STATE) && ribp.wstrb[0]) begin
      s_intr_clear = ribp.wdata[3:0];
    end
    if (s_req && s_write && !s_access_err &&
        (s_offset == `RIBP_PSRAM_INTR_TEST) && ribp.wstrb[0]) begin
      s_intr_set = s_intr_set | ribp.wdata[3:0];
    end
    s_intr_next = (s_intr_state_q & ~s_intr_clear) | s_intr_set;
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_ready_q             <= 1'b0;
      s_resp_err_q          <= 1'b0;
      s_rdata_q             <= '0;
      s_ctrl_q              <= 32'h0000_0003;
      s_chip_en_q           <= 4'hF;
      s_clk_config_q        <= 32'h0000_0001;
      s_powerup_cycles_q    <= 32'd10_800;
      s_cs_setup_q          <= 16'd1;
      s_cs_high_q           <= 16'd4;
      s_cs_hold_q           <= 16'd3;
      s_cs_max_low_q        <= 32'd576;
      s_access_timeout_q    <= 32'd100_000;
      s_indirect_ctrl_q     <= 32'h0000_0000;
      s_indirect_addr_q     <= '0;
      s_indirect_wdata_q    <= '0;
      s_intr_state_q        <= '0;
      s_intr_en_q           <= '0;
      s_perf_ctrl_q         <= '0;
      s_perf_read_bytes_q   <= '0;
      s_perf_write_bytes_q  <= '0;
      s_perf_commands_q     <= '0;
      s_perf_splits_q       <= '0;
      s_perf_stall_cycles_q <= '0;
      s_perf_err_count_q    <= '0;
      init_start_o          <= 1'b0;
      recover_start_o       <= 1'b0;
      recover_chip_o        <= '0;
      abort_o               <= 1'b0;
      chip_error_clear_o    <= '0;
      indirect_start_o      <= 1'b0;
    end else begin
      s_ready_q          <= s_req;
      init_start_o       <= 1'b0;
      recover_start_o    <= 1'b0;
      abort_o            <= 1'b0;
      chip_error_clear_o <= '0;
      indirect_start_o   <= 1'b0;

      if (s_req) begin
        s_resp_err_q <= s_access_err;
        s_rdata_q    <= s_read_data;
      end

      if (s_req && s_write && !s_access_err) begin
        unique case (s_offset)
          `RIBP_PSRAM_CTRL: s_ctrl_q <= s_ctrl_write_value;
          `RIBP_PSRAM_COMMAND: begin
            init_start_o    <= ribp.wdata[`PSRAM_COMMAND_INIT];
            recover_start_o <= ribp.wdata[`PSRAM_COMMAND_RECOVER];
            abort_o         <= ribp.wdata[`PSRAM_COMMAND_ABORT];
            recover_chip_o  <= ribp.wdata[9:8];
          end
          `RIBP_PSRAM_CHIP_ENABLE: s_chip_en_q <= s_chip_en_write_value;
          `RIBP_PSRAM_CHIP_ERROR: begin
            if (ribp.wstrb[0]) chip_error_clear_o <= ribp.wdata[3:0];
          end
          `RIBP_PSRAM_CLK_CONFIG: s_clk_config_q <= s_clk_write_value;
          `RIBP_PSRAM_POWERUP_CYCLES:
          s_powerup_cycles_q <= merge_wstrb(s_powerup_cycles_q, ribp.wdata, ribp.wstrb);
          `RIBP_PSRAM_CS_SETUP_CYCLES: s_cs_setup_q <= s_cs_setup_write_value;
          `RIBP_PSRAM_CS_HIGH_CYCLES: s_cs_high_q <= s_cs_high_write_value;
          `RIBP_PSRAM_CS_HOLD_CYCLES: s_cs_hold_q <= s_cs_hold_write_value;
          `RIBP_PSRAM_CS_MAX_LOW_CYCLES:
          s_cs_max_low_q <= merge_wstrb(s_cs_max_low_q, ribp.wdata, ribp.wstrb);
          `RIBP_PSRAM_ACCESS_TIMEOUT_CYCLES:
          s_access_timeout_q <= merge_wstrb(s_access_timeout_q, ribp.wdata, ribp.wstrb);
          `RIBP_PSRAM_INDIRECT_CTRL: begin
            s_indirect_ctrl_q <= s_indirect_write_value & 32'h7FFF_FFFF;
            indirect_start_o  <= s_indirect_write_value[`PSRAM_INDIRECT_START];
          end
          `RIBP_PSRAM_INDIRECT_ADDR: s_indirect_addr_q <= s_indirect_addr_write_value;
          `RIBP_PSRAM_INDIRECT_WDATA_LO:
          s_indirect_wdata_q[31:0] <= merge_wstrb(s_indirect_wdata_q[31:0], ribp.wdata, ribp.wstrb);
          `RIBP_PSRAM_INDIRECT_WDATA_HI:
          s_indirect_wdata_q[63:32] <= merge_wstrb(
              s_indirect_wdata_q[63:32], ribp.wdata, ribp.wstrb
          );
          `RIBP_PSRAM_INTR_ENABLE: s_intr_en_q <= s_intr_en_write_value;
          `RIBP_PSRAM_PERF_CTRL: s_perf_ctrl_q <= s_perf_write_value[1:0];
          default: begin
          end
        endcase
      end

      s_intr_state_q <= s_intr_next;

      if (s_req && s_write && !s_access_err &&
          (s_offset == `RIBP_PSRAM_PERF_CTRL) &&
          ribp.wdata[`PSRAM_PERF_CLEAR]) begin
        s_perf_read_bytes_q   <= '0;
        s_perf_write_bytes_q  <= '0;
        s_perf_commands_q     <= '0;
        s_perf_splits_q       <= '0;
        s_perf_stall_cycles_q <= '0;
        s_perf_err_count_q    <= '0;
      end else if (s_perf_ctrl_q[`PSRAM_PERF_ENABLE] && !s_perf_ctrl_q[`PSRAM_PERF_FREEZE]) begin
        if (|perf_read_byte_event_i)
          s_perf_read_bytes_q <= saturating_add(s_perf_read_bytes_q, perf_read_byte_event_i);
        if (|perf_write_byte_event_i)
          s_perf_write_bytes_q <= saturating_add(s_perf_write_bytes_q, perf_write_byte_event_i);
        if (perf_command_event_i) s_perf_commands_q <= saturating_increment(s_perf_commands_q);
        if (perf_split_event_i) s_perf_splits_q <= saturating_increment(s_perf_splits_q);
        if (perf_stall_event_i)
          s_perf_stall_cycles_q <= saturating_increment(s_perf_stall_cycles_q);
        if (perf_error_event_i) s_perf_err_count_q <= saturating_increment(s_perf_err_count_q);
      end
    end
  end

  assign controller_enable_o     = s_ctrl_q[`PSRAM_CTRL_ENABLE];
  assign memory_enable_o         = s_ctrl_q[`PSRAM_CTRL_MEMORY_ENABLE];
  assign auto_init_o             = s_ctrl_q[`PSRAM_CTRL_AUTO_INIT];
  assign wrap32_o                = s_ctrl_q[`PSRAM_CTRL_WRAP32];
  assign chip_enable_o           = s_chip_en_q;
  assign half_period_o           = s_clk_config_q[15:0];
  assign above_84mhz_o           = s_clk_config_q[`PSRAM_CLK_ABOVE_84MHZ];
  assign powerup_cycles_o        = s_powerup_cycles_q;
  assign cs_setup_cycles_o       = s_cs_setup_q;
  assign cs_high_cycles_o        = s_cs_high_q;
  assign cs_hold_cycles_o        = s_cs_hold_q;
  assign cs_max_low_cycles_o     = s_cs_max_low_q;
  assign access_timeout_cycles_o = s_access_timeout_q;
  assign indirect_command_o      = psram_cmd_e'(s_indirect_ctrl_q[3:0]);
  assign indirect_chip_o         = s_indirect_ctrl_q[9:8];
  assign indirect_length_o       = {1'b0, s_indirect_ctrl_q[18:16]} + 1'b1;
  assign indirect_addr_o         = s_indirect_addr_q;
  assign indirect_wdata_o        = s_indirect_wdata_q;
  assign irq_o                   = |(s_intr_state_q & s_intr_en_q);

endmodule
