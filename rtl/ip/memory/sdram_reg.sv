// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "sdram_define.svh"

module sdram_reg (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic                    clk_i,
    input  logic                    rst_n_i,
    apb4_if.slave                   apb4,
    input  logic                    init_busy_i,
    input  logic                    axi_busy_i,
    input  logic                    phy_busy_i,
    input  logic                    ready_i,
    input  sdram_pkg::sdram_error_e last_error_i,
    input  logic [31:0]             last_error_addr_i,
    input  logic                    init_done_event_i,
    input  logic                    error_event_i,
    input  logic [2:0]              perf_read_byte_event_i,
    input  logic [2:0]              perf_write_byte_event_i,
    input  logic                    perf_row_hit_event_i,
    input  logic                    perf_row_miss_event_i,
    input  logic                    perf_refresh_stall_event_i,
    input  logic                    perf_bank_conflict_event_i,
    output logic [1:0]              clkdiv_o,
    output logic                    controller_enable_o,
    output logic                    memory_enable_o,
    output logic                    auto_init_o,
    output logic                    open_page_o,
    output logic [1:0]              cas_o,
    output logic [1:0]              burst_len_o,
    output logic                    write_burst_o,
    output logic                    burst_type_o,
    output logic [7:0]              trp_o,
    output logic [7:0]              trcd_o,
    output logic [7:0]              tras_o,
    output logic [7:0]              trc_o,
    output logic [7:0]              twr_o,
    output logic [7:0]              trfc_o,
    output logic [7:0]              trrd_o,
    output logic [7:0]              twtr_o,
    output logic [7:0]              trtp_o,
    output logic [7:0]              tmrd_o,
    output logic [7:0]              txsr_o,
    output logic [15:0]             trefi_o,
    output logic [3:0]              credit_max_o,
    output logic [15:0]             powerup_cycles_o,
    output logic                    init_start_o,
    output logic                    reinit_start_o,
    output logic                    precharge_all_o,
    output logic                    refresh_start_o
    // verilog_format: on
);

  import sdram_pkg::*;

  localparam logic [31:0] CTRL_WRITABLE_MASK = 32'h0000_000F;
  localparam logic [31:0] MODE_WRITABLE_MASK = 32'h0000_003F;
  localparam logic [31:0] REFRESH_WRITABLE_MASK = 32'h000F_FFFF;
  localparam logic [31:0] PERF_WRITABLE_MASK = 32'h0000_0003;
  localparam logic [31:0] CLKDIV_WRITABLE_MASK = 32'h0000_0003;

  logic        s_req;
  logic        s_write;
  logic [11:0] s_offset;
  logic        s_aligned;
  logic        s_busy;
  logic        s_access_err;
  logic [31:0] s_read_data;
  logic        s_ready_q;
  logic        s_resp_err_d;
  logic        s_resp_err_q;
  logic [31:0] s_rdata_d;
  logic [31:0] s_rdata_q;

  logic [31:0] s_ctrl_d;
  logic [31:0] s_ctrl_q;
  logic [ 1:0] s_clkdiv_d;
  logic [ 1:0] s_clkdiv_q;
  logic [31:0] s_mode_d;
  logic [31:0] s_mode_q;
  logic [31:0] s_timing0_d;
  logic [31:0] s_timing0_q;
  logic [31:0] s_timing1_d;
  logic [31:0] s_timing1_q;
  logic [31:0] s_timing2_d;
  logic [31:0] s_timing2_q;
  logic [31:0] s_refresh_d;
  logic [31:0] s_refresh_q;
  logic [31:0] s_powerup_d;
  logic [31:0] s_powerup_q;
  logic [ 1:0] s_intr_state_q;
  logic [ 1:0] s_intr_en_d;
  logic [ 1:0] s_intr_en_q;
  logic [ 1:0] s_perf_ctrl_d;
  logic [ 1:0] s_perf_ctrl_q;
  logic [31:0] s_perf_read_bytes_d;
  logic [31:0] s_perf_read_bytes_q;
  logic [31:0] s_perf_write_bytes_d;
  logic [31:0] s_perf_write_bytes_q;
  logic [31:0] s_perf_row_hit_d;
  logic [31:0] s_perf_row_hit_q;
  logic [31:0] s_perf_row_miss_d;
  logic [31:0] s_perf_row_miss_q;
  logic [31:0] s_perf_refresh_stall_d;
  logic [31:0] s_perf_refresh_stall_q;
  logic [31:0] s_perf_bank_conflict_d;
  logic [31:0] s_perf_bank_conflict_q;

  logic        s_ctrl_en;
  logic        s_clkdiv_en;
  logic        s_mode_en;
  logic        s_timing0_en;
  logic        s_timing1_en;
  logic        s_timing2_en;
  logic        s_refresh_en;
  logic        s_powerup_en;
  logic        s_intr_en_en;
  logic        s_perf_ctrl_en;
  logic [ 1:0] s_intr_clear;
  logic [ 1:0] s_intr_set;
  logic [ 1:0] s_intr_next;
  logic        s_init_start_d;
  logic        s_reinit_start_d;
  logic        s_precharge_all_d;
  logic        s_refresh_start_d;
  logic        s_init_start_q;
  logic        s_reinit_start_q;
  logic        s_precharge_all_q;
  logic        s_refresh_start_q;

  logic [31:0] s_ctrl_write_value;
  logic [31:0] s_mode_write_value;
  logic [31:0] s_refresh_write_value;
  logic [ 1:0] s_mode_cas;
  logic [ 1:0] s_mode_bl;
  logic        s_mode_legal;

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
    return (&value) ? value : (value + 1'b1);
  endfunction

  function automatic logic [31:0] saturating_add(input logic [31:0] value,
                                                 input logic [2:0] increment);
    logic [32:0] result;
    begin
      result = {1'b0, value} + {30'd0, increment};
      return result[32] ? 32'hFFFF_FFFF : result[31:0];
    end
  endfunction

  assign s_req = apb4.psel && apb4.penable && !s_ready_q;
  assign s_write = apb4.pwrite;
  assign s_offset = apb4.paddr[11:0];
  assign s_aligned = apb4.paddr[1:0] == 2'b00;
  assign s_busy = init_busy_i || axi_busy_i || phy_busy_i;

  assign s_ctrl_write_value = merge_wstrb(s_ctrl_q, apb4.pwdata, apb4.pstrb) & CTRL_WRITABLE_MASK;
  assign s_mode_write_value = merge_wstrb(s_mode_q, apb4.pwdata, apb4.pstrb) & MODE_WRITABLE_MASK;
  assign s_refresh_write_value = merge_wstrb(
      s_refresh_q, apb4.pwdata, apb4.pstrb
  ) & REFRESH_WRITABLE_MASK;
  assign s_mode_cas = s_mode_write_value[1:0];
  assign s_mode_bl = s_mode_write_value[3:2];
  assign s_mode_legal          = ((s_mode_cas == 2'd2) || (s_mode_cas == 2'd3)) &&
      ((s_mode_bl == `APB4_SDRAM__MODE_BL_2) || (s_mode_bl == `APB4_SDRAM__MODE_BL_8)) &&
      !s_mode_write_value[`APB4_SDRAM__MODE_BURST_TYPE];

  assign apb4.pready = s_ready_q;
  assign apb4.pslverr = s_resp_err_q;
  assign apb4.prdata = s_rdata_q;

  assign clkdiv_o = s_clkdiv_q;
  assign controller_enable_o = s_ctrl_q[`APB4_SDRAM__CTRL_ENABLE];
  assign memory_enable_o = s_ctrl_q[`APB4_SDRAM__CTRL_MEMORY_ENABLE];
  assign auto_init_o = s_ctrl_q[`APB4_SDRAM__CTRL_AUTO_INIT];
  assign open_page_o = s_ctrl_q[`APB4_SDRAM__CTRL_OPEN_PAGE];
  assign cas_o = s_mode_q[1:0];
  assign burst_len_o = s_mode_q[3:2];
  assign write_burst_o = s_mode_q[`APB4_SDRAM__MODE_WR_BURST];
  assign burst_type_o = s_mode_q[`APB4_SDRAM__MODE_BURST_TYPE];
  assign trp_o = s_timing0_q[7:0];
  assign trcd_o = s_timing0_q[15:8];
  assign tras_o = s_timing0_q[23:16];
  assign trc_o = s_timing0_q[31:24];
  assign twr_o = s_timing1_q[7:0];
  assign trfc_o = s_timing1_q[15:8];
  assign trrd_o = s_timing1_q[23:16];
  assign twtr_o = s_timing1_q[31:24];
  assign trtp_o = s_timing2_q[7:0];
  assign tmrd_o = s_timing2_q[15:8];
  assign txsr_o = s_timing2_q[23:16];
  assign trefi_o = s_refresh_q[15:0];
  assign credit_max_o = s_refresh_q[19:16];
  assign powerup_cycles_o = s_powerup_q[15:0];
  assign init_start_o = s_init_start_q;
  assign reinit_start_o = s_reinit_start_q;
  assign precharge_all_o = s_precharge_all_q;
  assign refresh_start_o = s_refresh_start_q;

  always_comb begin
    s_access_err = !s_aligned;
    s_read_data  = '0;
    if (s_aligned) begin
      unique case (s_offset)
        `APB4_SDRAM__CLKDIV: begin
          s_read_data  = {30'd0, s_clkdiv_q};
          s_access_err = 1'b0;
        end
        `APB4_SDRAM__CTRL: begin
          s_read_data  = s_ctrl_q;
          s_access_err = s_write && init_busy_i && (s_ctrl_write_value != s_ctrl_q);
        end
        `APB4_SDRAM__COMMAND: begin
          s_access_err = !s_write || !apb4.pstrb[0] || (apb4.pwdata[3:0] == 4'd0) ||
              (|(apb4.pwdata[3:0] & (apb4.pwdata[3:0] - 1'b1))) ||
              (s_busy && (apb4.pwdata[`APB4_SDRAM__COMMAND_INIT] ||
                          apb4.pwdata[`APB4_SDRAM__COMMAND_REINIT]));
        end
        `APB4_SDRAM__STATUS: begin
          s_read_data = {
            27'd0, (last_error_i != SdramErrNone), ready_i, phy_busy_i, axi_busy_i, init_busy_i
          };
          s_access_err = s_write;
        end
        `APB4_SDRAM__MODE: begin
          s_read_data  = s_mode_q;
          s_access_err = s_write && (!s_mode_legal || s_busy);
        end
        `APB4_SDRAM__TIMING0: begin
          s_read_data  = s_timing0_q;
          s_access_err = s_write && s_busy;
        end
        `APB4_SDRAM__TIMING1: begin
          s_read_data  = s_timing1_q;
          s_access_err = s_write && s_busy;
        end
        `APB4_SDRAM__TIMING2: begin
          s_read_data  = s_timing2_q;
          s_access_err = s_write && s_busy;
        end
        `APB4_SDRAM__REFRESH: begin
          s_read_data = s_refresh_q;
          s_access_err = s_write && (s_busy || (s_refresh_write_value[15:0] == 16'd0) ||
                          (s_refresh_write_value[19:16] == 4'd0));
        end
        `APB4_SDRAM__POWERUP: begin
          s_read_data  = s_powerup_q;
          s_access_err = s_write && (s_busy || (apb4.pwdata[15:0] == 16'd0));
        end
        `APB4_SDRAM__LAST_ERROR: begin
          s_read_data  = {28'd0, last_error_i};
          s_access_err = s_write;
        end
        `APB4_SDRAM__LAST_ERROR_ADDR: begin
          s_read_data  = last_error_addr_i;
          s_access_err = s_write;
        end
        `APB4_SDRAM__INTR_STATE:  s_read_data = {30'd0, s_intr_state_q};
        `APB4_SDRAM__INTR_ENABLE: s_read_data = {30'd0, s_intr_en_q};
        `APB4_SDRAM__INTR_STATUS: begin
          s_read_data  = {30'd0, s_intr_state_q & s_intr_en_q};
          s_access_err = s_write;
        end
        `APB4_SDRAM__INTR_TEST:   s_access_err = !s_write || !apb4.pstrb[0];
        `APB4_SDRAM__PERF_CTRL:   s_read_data = {30'd0, s_perf_ctrl_q};
        `APB4_SDRAM__PERF_READ_BYTES: begin
          s_read_data  = s_perf_read_bytes_q;
          s_access_err = s_write;
        end
        `APB4_SDRAM__PERF_WRITE_BYTES: begin
          s_read_data  = s_perf_write_bytes_q;
          s_access_err = s_write;
        end
        `APB4_SDRAM__PERF_ROW_HIT: begin
          s_read_data  = s_perf_row_hit_q;
          s_access_err = s_write;
        end
        `APB4_SDRAM__PERF_ROW_MISS: begin
          s_read_data  = s_perf_row_miss_q;
          s_access_err = s_write;
        end
        `APB4_SDRAM__PERF_REFRESH_STALL: begin
          s_read_data  = s_perf_refresh_stall_q;
          s_access_err = s_write;
        end
        `APB4_SDRAM__PERF_BANK_CONFLICT: begin
          s_read_data  = s_perf_bank_conflict_q;
          s_access_err = s_write;
        end
        `APB4_SDRAM__IP_VERSION: begin
          s_read_data  = `APB4_SDRAM__IP_VERSION_VALUE;
          s_access_err = s_write;
        end
        `APB4_SDRAM__CAPABILITY: begin
          s_read_data  = `APB4_SDRAM__CAPABILITY_VALUE;
          s_access_err = s_write;
        end
        default:                  s_access_err = 1'b1;
      endcase
    end
  end

  always_comb begin
    s_intr_clear = '0;
    s_intr_set   = {error_event_i, init_done_event_i};
    if (s_req && s_write && !s_access_err && (s_offset == `APB4_SDRAM__INTR_STATE) &&
        apb4.pstrb[0]) begin
      s_intr_clear = apb4.pwdata[1:0];
    end
    if (s_req && s_write && !s_access_err && (s_offset == `APB4_SDRAM__INTR_TEST) &&
        apb4.pstrb[0]) begin
      s_intr_set = s_intr_set | apb4.pwdata[1:0];
    end
    s_intr_next = (s_intr_state_q & ~s_intr_clear) | s_intr_set;
  end

  always_comb begin
    s_ctrl_en = 1'b0;
    s_clkdiv_en = 1'b0;
    s_mode_en = 1'b0;
    s_timing0_en = 1'b0;
    s_timing1_en = 1'b0;
    s_timing2_en = 1'b0;
    s_refresh_en = 1'b0;
    s_powerup_en = 1'b0;
    s_intr_en_en = 1'b0;
    s_perf_ctrl_en = 1'b0;
    s_ctrl_d = s_ctrl_write_value;
    s_clkdiv_d =
        2'(merge_wstrb({30'd0, s_clkdiv_q}, apb4.pwdata, apb4.pstrb) & CLKDIV_WRITABLE_MASK);
    s_mode_d = s_mode_write_value;
    s_timing0_d = merge_wstrb(s_timing0_q, apb4.pwdata, apb4.pstrb);
    s_timing1_d = merge_wstrb(s_timing1_q, apb4.pwdata, apb4.pstrb);
    s_timing2_d = merge_wstrb(s_timing2_q, apb4.pwdata, apb4.pstrb);
    s_refresh_d = s_refresh_write_value;
    s_powerup_d = merge_wstrb(s_powerup_q, apb4.pwdata, apb4.pstrb);
    s_intr_en_d = 2'(merge_wstrb({30'd0, s_intr_en_q}, apb4.pwdata, apb4.pstrb));
    s_perf_ctrl_d =
        2'(merge_wstrb({30'd0, s_perf_ctrl_q}, apb4.pwdata, apb4.pstrb) & PERF_WRITABLE_MASK);
    s_init_start_d = 1'b0;
    s_reinit_start_d = 1'b0;
    s_precharge_all_d = 1'b0;
    s_refresh_start_d = 1'b0;
    if (s_req && s_write && !s_access_err) begin
      unique case (s_offset)
        `APB4_SDRAM__CLKDIV:      s_clkdiv_en = 1'b1;
        `APB4_SDRAM__CTRL:        s_ctrl_en = 1'b1;
        `APB4_SDRAM__COMMAND: begin
          s_init_start_d    = apb4.pwdata[`APB4_SDRAM__COMMAND_INIT];
          s_reinit_start_d  = apb4.pwdata[`APB4_SDRAM__COMMAND_REINIT];
          s_precharge_all_d = apb4.pwdata[`APB4_SDRAM__COMMAND_PRECHARGE_ALL];
          s_refresh_start_d = apb4.pwdata[`APB4_SDRAM__COMMAND_REFRESH];
        end
        `APB4_SDRAM__MODE:        s_mode_en = 1'b1;
        `APB4_SDRAM__TIMING0:     s_timing0_en = 1'b1;
        `APB4_SDRAM__TIMING1:     s_timing1_en = 1'b1;
        `APB4_SDRAM__TIMING2:     s_timing2_en = 1'b1;
        `APB4_SDRAM__REFRESH:     s_refresh_en = 1'b1;
        `APB4_SDRAM__POWERUP:     s_powerup_en = 1'b1;
        `APB4_SDRAM__INTR_ENABLE: s_intr_en_en = 1'b1;
        `APB4_SDRAM__PERF_CTRL:   s_perf_ctrl_en = 1'b1;
        default:                  ;
      endcase
    end
  end

  always_comb begin
    s_perf_read_bytes_d    = s_perf_read_bytes_q;
    s_perf_write_bytes_d   = s_perf_write_bytes_q;
    s_perf_row_hit_d       = s_perf_row_hit_q;
    s_perf_row_miss_d      = s_perf_row_miss_q;
    s_perf_refresh_stall_d = s_perf_refresh_stall_q;
    s_perf_bank_conflict_d = s_perf_bank_conflict_q;
    if (s_req && s_write && !s_access_err && (s_offset == `APB4_SDRAM__PERF_CTRL) &&
        apb4.pwdata[`APB4_SDRAM__PERF_CLEAR]) begin
      s_perf_read_bytes_d    = '0;
      s_perf_write_bytes_d   = '0;
      s_perf_row_hit_d       = '0;
      s_perf_row_miss_d      = '0;
      s_perf_refresh_stall_d = '0;
      s_perf_bank_conflict_d = '0;
    end else if (s_perf_ctrl_q[`APB4_SDRAM__PERF_ENABLE] &&
        !s_perf_ctrl_q[`APB4_SDRAM__PERF_FREEZE]) begin
      if (|perf_read_byte_event_i) begin
        s_perf_read_bytes_d = saturating_add(s_perf_read_bytes_q, perf_read_byte_event_i);
      end
      if (|perf_write_byte_event_i) begin
        s_perf_write_bytes_d = saturating_add(s_perf_write_bytes_q, perf_write_byte_event_i);
      end
      if (perf_row_hit_event_i) begin
        s_perf_row_hit_d = saturating_increment(s_perf_row_hit_q);
      end
      if (perf_row_miss_event_i) begin
        s_perf_row_miss_d = saturating_increment(s_perf_row_miss_q);
      end
      if (perf_refresh_stall_event_i) begin
        s_perf_refresh_stall_d = saturating_increment(s_perf_refresh_stall_q);
      end
      if (perf_bank_conflict_event_i) begin
        s_perf_bank_conflict_d = saturating_increment(s_perf_bank_conflict_q);
      end
    end
  end

  assign s_resp_err_d = s_access_err;
  assign s_rdata_d    = s_read_data;

  dffr #(
      .DATA_WIDTH(1)
  ) u_ready_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_req),
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
      .RESET_VAL (`APB4_SDRAM__CTRL_RESET)
  ) u_ctrl_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_ctrl_en),
      .dat_i  (s_ctrl_d),
      .dat_o  (s_ctrl_q)
  );
  dffer #(
      .DATA_WIDTH(2)
  ) u_clkdiv_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_clkdiv_en),
      .dat_i  (s_clkdiv_d),
      .dat_o  (s_clkdiv_q)
  );
  dfferc #(
      .DATA_WIDTH(32),
      .RESET_VAL (`APB4_SDRAM__MODE_RESET)
  ) u_mode_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_mode_en),
      .dat_i  (s_mode_d),
      .dat_o  (s_mode_q)
  );
  dfferc #(
      .DATA_WIDTH(32),
      .RESET_VAL (`APB4_SDRAM__TIMING0_RESET)
  ) u_timing0_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_timing0_en),
      .dat_i  (s_timing0_d),
      .dat_o  (s_timing0_q)
  );
  dfferc #(
      .DATA_WIDTH(32),
      .RESET_VAL (`APB4_SDRAM__TIMING1_RESET)
  ) u_timing1_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_timing1_en),
      .dat_i  (s_timing1_d),
      .dat_o  (s_timing1_q)
  );
  dfferc #(
      .DATA_WIDTH(32),
      .RESET_VAL (`APB4_SDRAM__TIMING2_RESET)
  ) u_timing2_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_timing2_en),
      .dat_i  (s_timing2_d),
      .dat_o  (s_timing2_q)
  );
  dfferc #(
      .DATA_WIDTH(32),
      .RESET_VAL (`APB4_SDRAM__REFRESH_RESET)
  ) u_refresh_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_refresh_en),
      .dat_i  (s_refresh_d),
      .dat_o  (s_refresh_q)
  );
  dfferc #(
      .DATA_WIDTH(32),
      .RESET_VAL (`APB4_SDRAM__POWERUP_RESET)
  ) u_powerup_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_powerup_en),
      .dat_i  (s_powerup_d),
      .dat_o  (s_powerup_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_intr_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_intr_next),
      .dat_o  (s_intr_state_q)
  );
  dffer #(
      .DATA_WIDTH(2)
  ) u_intr_en_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_intr_en_en),
      .dat_i  (s_intr_en_d),
      .dat_o  (s_intr_en_q)
  );
  dffer #(
      .DATA_WIDTH(2)
  ) u_perf_ctrl_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_perf_ctrl_en),
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
  ) u_perf_row_hit_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_row_hit_d),
      .dat_o  (s_perf_row_hit_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_row_miss_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_row_miss_d),
      .dat_o  (s_perf_row_miss_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_refresh_stall_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_refresh_stall_d),
      .dat_o  (s_perf_refresh_stall_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_bank_conflict_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_bank_conflict_d),
      .dat_o  (s_perf_bank_conflict_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_init_start_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_init_start_d),
      .dat_o  (s_init_start_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_reinit_start_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_reinit_start_d),
      .dat_o  (s_reinit_start_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_precharge_all_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_precharge_all_d),
      .dat_o  (s_precharge_all_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_refresh_start_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_refresh_start_d),
      .dat_o  (s_refresh_start_q)
  );

endmodule
