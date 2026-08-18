// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

`include "sdram_define.svh"

module sdram_core (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic                    clk_i,
    input  logic                    rst_n_i,
    input  logic                    fir_edge_i,
    input  logic                    sec_edge_i,
    input  logic                    sdram_clk_i,
    input  logic                    auto_init_i,
    input  logic                    open_page_i,
    input  logic [1:0]              cas_i,
    input  logic [1:0]              burst_len_i,
    input  logic                    write_burst_i,
    input  logic [7:0]              trp_i,
    input  logic [7:0]              trcd_i,
    input  logic [7:0]              tras_i,
    input  logic [7:0]              trc_i,
    input  logic [7:0]              twr_i,
    input  logic [7:0]              trfc_i,
    input  logic [7:0]              trrd_i,
    input  logic [7:0]              twtr_i,
    input  logic [7:0]              trtp_i,
    input  logic [7:0]              tmrd_i,
    input  logic [7:0]              txsr_i,
    input  logic [15:0]             trefi_i,
    input  logic [3:0]              credit_max_i,
    input  logic [15:0]             powerup_cycles_i,
    input  logic                    init_start_i,
    input  logic                    reinit_start_i,
    input  logic                    precharge_all_i,
    input  logic                    refresh_start_i,
    output logic                    init_busy_o,
    output logic                    phy_busy_o,
    output logic                    ready_o,
    output logic                    init_done_event_o,
    output logic                    perf_row_hit_o,
    output logic                    perf_row_miss_o,
    output logic                    perf_refresh_stall_o,
    output logic                    perf_bank_conflict_o,
    output logic [2:0]              perf_read_bytes_o,
    output logic [2:0]              perf_write_bytes_o,
    input  logic                    rd_cmd_valid_i,
    output logic                    rd_cmd_ready_o,
    input  logic [1:0]              rd_cmd_bank_i,
    input  logic [12:0]             rd_cmd_row_i,
    input  logic [9:0]              rd_cmd_col_i,
    input  logic [3:0]              rd_cmd_len_i,
    output logic                    rd_data_valid_o,
    input  logic                    rd_data_ready_i,
    output logic [31:0]             rd_data_rdata_o,
    output logic                    rd_data_error_o,
    input  logic                    wr_cmd_valid_i,
    output logic                    wr_cmd_ready_o,
    input  logic [1:0]              wr_cmd_bank_i,
    input  logic [12:0]             wr_cmd_row_i,
    input  logic [9:0]              wr_cmd_col_i,
    input  logic [3:0]              wr_cmd_len_i,
    input  logic                    wr_data_valid_i,
    output logic                    wr_data_ready_o,
    input  logic [31:0]             wr_data_wdata_i,
    input  logic [3:0]              wr_data_wstrb_i,
    output logic                    wr_done_valid_o,
    input  logic                    wr_done_ready_i,
    output logic                    wr_done_error_o,
    sdram_if.dut                    sdram
    // verilog_format: on
);

  import sdram_pkg::*;

  typedef enum logic [4:0] {
    StReset    = 5'd0,
    StPowerup  = 5'd1,
    StCke      = 5'd2,
    StInitPre  = 5'd3,
    StInitRef0 = 5'd4,
    StInitRef1 = 5'd5,
    StInitMrs  = 5'd6,
    StIdle     = 5'd7,
    StAct      = 5'd8,
    StReadCmd  = 5'd9,
    StReadLo   = 5'd10,
    StReadHi   = 5'd11,
    StReadHold = 5'd12,
    StWriteGet = 5'd13,
    StWriteCmd = 5'd14,
    StWriteHi  = 5'd15,
    StPre      = 5'd16,
    StPreAll   = 5'd17,
    StRefresh  = 5'd18,
    StWait     = 5'd19
  } sdram_state_e;

  sdram_state_e        s_state_q;
  sdram_state_e        s_state_d;
  sdram_state_e        s_ret_q;
  sdram_state_e        s_ret_d;
  logic         [15:0] s_wait_q;
  logic         [15:0] s_wait_d;
  logic         [ 3:0] s_cmd_q;
  logic         [ 3:0] s_cmd_d;
  logic                s_cke_q;
  logic                s_cke_d;
  logic         [ 1:0] s_ba_q;
  logic         [ 1:0] s_ba_d;
  logic         [12:0] s_addr_q;
  logic         [12:0] s_addr_d;
  logic         [ 1:0] s_dqm_q;
  logic         [ 1:0] s_dqm_d;
  logic         [15:0] s_dq_q;
  logic         [15:0] s_dq_d;
  logic                s_oe_q;
  logic                s_oe_d;
  logic         [31:0] s_rdata_q;
  logic         [31:0] s_rdata_d;
  logic                s_rd_valid_q;
  logic                s_wr_done_q;
  logic                s_ready_q;
  logic                s_ready_d;
  logic                s_init_busy_q;
  logic                s_init_busy_d;
  logic                s_init_done_q;
  logic                s_sel_wr_q;
  logic                s_sel_wr_d;
  logic         [ 1:0] s_bank_q;
  logic         [ 1:0] s_bank_d;
  logic         [12:0] s_row_q;
  logic         [12:0] s_row_d;
  logic         [ 9:0] s_col_q;
  logic         [ 9:0] s_col_d;
  logic         [ 4:0] s_left_q;
  logic         [ 4:0] s_left_d;
  logic         [31:0] s_wdata_q;
  logic         [31:0] s_wdata_d;
  logic         [ 3:0] s_wstrb_q;
  logic         [ 3:0] s_wstrb_d;
  logic         [ 1:0] s_cas_q;
  logic         [ 1:0] s_cas_d;
  logic         [ 3:0] s_bank_open_q;
  logic         [ 3:0] s_bank_open_d;
  logic         [12:0] s_open_row0_q;
  logic         [12:0] s_open_row0_d;
  logic         [12:0] s_open_row1_q;
  logic         [12:0] s_open_row1_d;
  logic         [12:0] s_open_row2_q;
  logic         [12:0] s_open_row2_d;
  logic         [12:0] s_open_row3_q;
  logic         [12:0] s_open_row3_d;
  logic         [15:0] s_refi_q;
  logic         [15:0] s_refi_d;
  logic         [ 3:0] s_credit_q;
  logic         [ 3:0] s_credit_d;
  logic         [15:0] s_tras_left_q;
  logic         [15:0] s_tras_left_d;
  logic         [15:0] s_trc_left_q;
  logic         [15:0] s_trc_left_d;
  logic         [15:0] s_rrd_left_q;
  logic         [15:0] s_rrd_left_d;
  logic                s_last_wr_q;
  logic                s_last_wr_d;
  logic                s_init_req_q;
  logic                s_reinit_req_q;
  logic                s_pre_req_q;
  logic                s_ref_req_q;
  logic                s_hit_q;
  logic                s_miss_q;
  logic                s_conflict_q;
  logic                s_ref_stall_q;
  logic         [ 2:0] s_rd_bytes_q;
  logic         [ 2:0] s_wr_bytes_q;
  logic                s_force_refresh;
  logic                s_oppo_refresh;
  logic                s_resp_hold;
  logic                s_can_accept;
  logic                s_take_wr;
  logic                s_take_rd;
  logic                s_row_hit;
  logic                s_row_conflict;
  logic                s_last_beat;
  logic                s_auto_pre;
  logic         [12:0] s_sel_row;
  logic         [ 1:0] s_sel_bank;
  logic                unused_burst_len;
  logic                unused_trtp;

  function automatic logic [15:0] cyc8(input logic [7:0] value);
    return {8'd0, sdram_min_cycles(value)};
  endfunction

  function automatic logic [15:0] cyc16(input logic [15:0] value);
    return sdram_min_cycles16(value);
  endfunction

  function automatic logic [15:0] max16(input logic [15:0] left, input logic [15:0] right);
    return (left > right) ? left : right;
  endfunction

  function automatic logic [12:0] mrs_word(input logic [1:0] cas_l, input logic write_burst);
    logic [2:0] cas_bits;
    begin
      cas_bits = {1'b0, cas_l};
      mrs_word = {3'b000, ~write_burst, 2'b00, cas_bits, 1'b0, 3'b001};
    end
  endfunction

  function automatic logic [12:0] open_row_of(input logic [1:0] bank);
    unique case (bank)
      2'd1:    open_row_of = s_open_row1_q;
      2'd2:    open_row_of = s_open_row2_q;
      2'd3:    open_row_of = s_open_row3_q;
      default: open_row_of = s_open_row0_q;
    endcase
  endfunction

  function automatic logic [12:0] col_addr(input logic [9:0] column, input logic auto_pre);
    return {2'b00, auto_pre, column};
  endfunction

  assign sdram.clk_o = sdram_clk_i;
  assign sdram.cke_o = s_cke_q;
  assign sdram.cs_n_o = s_cmd_q[3];
  assign sdram.ras_n_o = s_cmd_q[2];
  assign sdram.cas_n_o = s_cmd_q[1];
  assign sdram.we_n_o = s_cmd_q[0];
  assign sdram.ba_o = s_ba_q;
  assign sdram.addr_o = s_addr_q;
  assign sdram.dqm_o = s_dqm_q;
  assign sdram.oe_o = s_oe_q;
  assign sdram.dq_o = s_dq_q;

  assign init_busy_o = s_init_busy_q;
  assign ready_o = s_ready_q;
  assign phy_busy_o = (s_state_q != StIdle) || s_rd_valid_q || s_wr_done_q;
  assign init_done_event_o = s_init_done_q;
  assign rd_data_valid_o = s_rd_valid_q;
  assign rd_data_rdata_o = s_rdata_q;
  assign rd_data_error_o = 1'b0;
  assign wr_done_valid_o = s_wr_done_q;
  assign wr_done_error_o = 1'b0;
  assign perf_row_hit_o = s_hit_q;
  assign perf_row_miss_o = s_miss_q;
  assign perf_refresh_stall_o = s_ref_stall_q;
  assign perf_bank_conflict_o = s_conflict_q;
  assign perf_read_bytes_o = s_rd_bytes_q;
  assign perf_write_bytes_o = s_wr_bytes_q;

  assign s_resp_hold = (s_rd_valid_q && !rd_data_ready_i) || (s_wr_done_q && !wr_done_ready_i);
  assign s_force_refresh = (s_credit_q >= credit_max_i) || s_ref_req_q;
  assign s_oppo_refresh = (s_credit_q != 4'd0) && !rd_cmd_valid_i && !wr_cmd_valid_i;
  assign s_can_accept         = s_ready_q && (s_state_q == StIdle) && sec_edge_i &&
      !s_force_refresh && !s_pre_req_q && !s_resp_hold && !s_init_req_q &&
      !s_reinit_req_q;
  assign wr_cmd_ready_o = s_can_accept;
  assign rd_cmd_ready_o = s_can_accept && !wr_cmd_valid_i;
  assign wr_data_ready_o = (s_state_q == StWriteGet) && sec_edge_i;
  assign s_take_wr = wr_cmd_valid_i && wr_cmd_ready_o;
  assign s_take_rd = rd_cmd_valid_i && rd_cmd_ready_o;
  assign s_sel_bank = s_take_wr ? wr_cmd_bank_i : rd_cmd_bank_i;
  assign s_sel_row = s_take_wr ? wr_cmd_row_i : rd_cmd_row_i;
  assign s_row_hit = s_bank_open_q[s_sel_bank] && (open_row_of(s_sel_bank) == s_sel_row);
  assign s_row_conflict = s_bank_open_q[s_sel_bank] && (open_row_of(s_sel_bank) != s_sel_row);
  assign s_last_beat = (s_left_q == 5'd1);
  assign s_auto_pre = !open_page_i && s_last_beat;
  // MODE.BL8 and tRTP are stored for the ABI / next scheduler step; MRS always
  // programs BL2, and tRTP is not a live command-to-precharge input yet.
  assign unused_burst_len = |burst_len_i;
  assign unused_trtp = |trtp_i;

  always_comb begin
    s_state_d     = s_state_q;
    s_ret_d       = s_ret_q;
    s_wait_d      = s_wait_q;
    s_cmd_d       = SdramCmdNop;
    s_cke_d       = s_cke_q;
    s_ba_d        = s_ba_q;
    s_addr_d      = s_addr_q;
    s_dqm_d       = 2'b11;
    s_dq_d        = s_dq_q;
    s_oe_d        = 1'b0;
    s_rdata_d     = s_rdata_q;
    s_ready_d     = s_ready_q;
    s_init_busy_d = s_init_busy_q;
    s_sel_wr_d    = s_sel_wr_q;
    s_bank_d      = s_bank_q;
    s_row_d       = s_row_q;
    s_col_d       = s_col_q;
    s_left_d      = s_left_q;
    s_wdata_d     = s_wdata_q;
    s_wstrb_d     = s_wstrb_q;
    s_cas_d       = s_cas_q;
    s_bank_open_d = s_bank_open_q;
    s_open_row0_d = s_open_row0_q;
    s_open_row1_d = s_open_row1_q;
    s_open_row2_d = s_open_row2_q;
    s_open_row3_d = s_open_row3_q;
    s_refi_d      = s_refi_q;
    s_credit_d    = s_credit_q;
    s_tras_left_d = (s_tras_left_q != 16'd0) ? (s_tras_left_q - 16'd1) : 16'd0;
    s_trc_left_d  = (s_trc_left_q != 16'd0) ? (s_trc_left_q - 16'd1) : 16'd0;
    s_rrd_left_d  = (s_rrd_left_q != 16'd0) ? (s_rrd_left_q - 16'd1) : 16'd0;
    s_last_wr_d   = s_last_wr_q;

    unique case (s_state_q)
      StReset: begin
        s_cke_d       = 1'b0;
        s_init_busy_d = 1'b1;
        s_ready_d     = 1'b0;
        if (auto_init_i || s_init_req_q) begin
          s_state_d = StPowerup;
          s_wait_d  = cyc16(powerup_cycles_i);
        end
      end
      StPowerup: begin
        s_cke_d  = 1'b0;
        s_wait_d = s_wait_q - 16'd1;
        if (s_wait_q == 16'd1) begin
          s_state_d = StCke;
        end
      end
      StCke: begin
        s_cke_d   = 1'b1;
        s_state_d = StWait;
        s_ret_d   = StInitPre;
        s_wait_d  = cyc8(txsr_i);
      end
      StInitPre: begin
        s_cmd_d       = SdramCmdPre;
        s_addr_d      = 13'h0400;
        s_ba_d        = 2'd0;
        s_bank_open_d = 4'd0;
        s_state_d     = StWait;
        s_ret_d       = StInitRef0;
        s_wait_d      = cyc8(trp_i);
      end
      StInitRef0: begin
        s_cmd_d   = SdramCmdRef;
        s_state_d = StWait;
        s_ret_d   = StInitRef1;
        s_wait_d  = cyc8(trfc_i);
      end
      StInitRef1: begin
        s_cmd_d   = SdramCmdRef;
        s_state_d = StWait;
        s_ret_d   = StInitMrs;
        s_wait_d  = cyc8(trfc_i);
      end
      StInitMrs: begin
        s_cmd_d       = SdramCmdMrs;
        s_addr_d      = mrs_word(cas_i, write_burst_i);
        s_ba_d        = 2'd0;
        s_cas_d       = ((cas_i == 2'd3) ? 2'd3 : 2'd2);
        s_bank_open_d = 4'd0;
        s_state_d     = StWait;
        s_ret_d       = StIdle;
        s_wait_d      = cyc8(tmrd_i);
        s_init_busy_d = 1'b0;
        s_ready_d     = 1'b1;
        s_credit_d    = 4'd0;
        s_refi_d      = cyc16(trefi_i);
        s_last_wr_d   = 1'b0;
      end
      StIdle: begin
        if (s_resp_hold) begin
          s_state_d = StIdle;
        end else if (s_init_req_q) begin
          s_ready_d     = 1'b0;
          s_init_busy_d = 1'b1;
          s_bank_open_d = 4'd0;
          s_state_d     = StPowerup;
          s_wait_d      = cyc16(powerup_cycles_i);
        end else if (s_reinit_req_q) begin
          s_ready_d     = 1'b0;
          s_init_busy_d = 1'b1;
          s_bank_open_d = 4'd0;
          s_state_d     = StInitPre;
        end else if (s_pre_req_q) begin
          if (s_bank_open_q != 4'd0) begin
            if (s_tras_left_q != 16'd0) begin
              s_state_d = StWait;
              s_ret_d   = StPreAll;
              s_wait_d  = s_tras_left_q;
            end else begin
              s_state_d = StPreAll;
            end
          end
        end else if (s_force_refresh || s_oppo_refresh) begin
          if (s_bank_open_q != 4'd0) begin
            if (s_tras_left_q != 16'd0) begin
              s_state_d = StWait;
              s_ret_d   = StPreAll;
              s_wait_d  = s_tras_left_q;
            end else begin
              s_state_d = StPreAll;
            end
          end else begin
            s_state_d = StRefresh;
          end
        end else if (s_take_wr || s_take_rd) begin
          s_sel_wr_d = s_take_wr;
          s_bank_d   = s_sel_bank;
          s_row_d    = s_sel_row;
          s_col_d    = s_take_wr ? wr_cmd_col_i : rd_cmd_col_i;
          s_left_d   = {1'b0, (s_take_wr ? wr_cmd_len_i : rd_cmd_len_i)} + 5'd1;
          if (s_row_hit) begin
            if (!s_take_wr && s_last_wr_q) begin
              s_state_d = StWait;
              s_ret_d   = StReadCmd;
              s_wait_d  = cyc8(twtr_i);
            end else begin
              s_state_d = s_take_wr ? StWriteGet : StReadCmd;
            end
          end else if (s_row_conflict) begin
            if (s_tras_left_q != 16'd0) begin
              s_state_d = StWait;
              s_ret_d   = StPre;
              s_wait_d  = s_tras_left_q;
            end else begin
              s_state_d = StPre;
            end
          end else if ((s_rrd_left_q != 16'd0) || (s_trc_left_q != 16'd0)) begin
            s_state_d = StWait;
            s_ret_d   = StAct;
            s_wait_d  = max16(s_rrd_left_q, s_trc_left_q);
          end else begin
            s_state_d = StAct;
          end
        end
      end
      StAct: begin
        s_cmd_d       = SdramCmdAct;
        s_ba_d        = s_bank_q;
        s_addr_d      = s_row_q;
        s_tras_left_d = cyc8(tras_i);
        s_trc_left_d  = cyc8(trc_i);
        s_rrd_left_d  = cyc8(trrd_i);
        unique case (s_bank_q)
          2'd1:    s_open_row1_d = s_row_q;
          2'd2:    s_open_row2_d = s_row_q;
          2'd3:    s_open_row3_d = s_row_q;
          default: s_open_row0_d = s_row_q;
        endcase
        s_bank_open_d[s_bank_q] = 1'b1;
        s_state_d               = StWait;
        s_ret_d                 = s_sel_wr_q ? StWriteGet : StReadCmd;
        s_wait_d                = cyc8(trcd_i);
      end
      StPre: begin
        s_cmd_d                 = SdramCmdPre;
        s_ba_d                  = s_bank_q;
        s_addr_d                = 13'h0000;
        s_bank_open_d[s_bank_q] = 1'b0;
        s_state_d               = StWait;
        s_ret_d                 = StAct;
        s_wait_d                = cyc8(trp_i);
      end
      StPreAll: begin
        s_cmd_d       = SdramCmdPre;
        s_addr_d      = 13'h0400;
        s_ba_d        = 2'd0;
        s_bank_open_d = 4'd0;
        s_state_d     = StWait;
        s_ret_d       = s_pre_req_q ? StIdle : StRefresh;
        s_wait_d      = cyc8(trp_i);
      end
      StRefresh: begin
        s_cmd_d     = SdramCmdRef;
        s_last_wr_d = 1'b0;
        s_state_d   = StWait;
        s_ret_d     = StIdle;
        s_wait_d    = cyc8(trfc_i);
        if (s_credit_q != 4'd0) begin
          s_credit_d = s_credit_q - 4'd1;
        end
      end
      StReadCmd: begin
        if (!s_resp_hold) begin
          s_cmd_d     = SdramCmdRead;
          s_ba_d      = s_bank_q;
          s_dqm_d     = 2'b00;
          s_addr_d    = col_addr(s_col_q, s_auto_pre);
          s_last_wr_d = 1'b0;
          if (s_auto_pre) begin
            s_bank_open_d[s_bank_q] = 1'b0;
          end
          s_state_d = StWait;
          s_ret_d   = StReadLo;
          s_wait_d  = {14'd0, s_cas_q};
        end
      end
      StReadLo: begin
        s_dqm_d         = 2'b00;
        s_rdata_d[15:0] = sdram.dq_i;
        s_state_d       = StReadHi;
      end
      StReadHi: begin
        s_dqm_d          = 2'b00;
        s_rdata_d[31:16] = sdram.dq_i;
        s_left_d         = s_left_q - 5'd1;
        s_col_d          = s_col_q + 10'd2;
        s_state_d        = StReadHold;
      end
      StReadHold: begin
        if (!s_rd_valid_q || rd_data_ready_i) begin
          if (s_left_q == 5'd0) begin
            if (!open_page_i) begin
              s_state_d = StWait;
              s_ret_d   = StIdle;
              s_wait_d  = max16(cyc8(trp_i), s_tras_left_q);
            end else begin
              s_state_d = StIdle;
            end
          end else begin
            s_state_d = StReadCmd;
          end
        end
      end
      StWriteGet: begin
        if (wr_data_valid_i) begin
          s_wdata_d = wr_data_wdata_i;
          s_wstrb_d = wr_data_wstrb_i;
          s_state_d = StWriteCmd;
        end
      end
      StWriteCmd: begin
        s_cmd_d     = SdramCmdWrite;
        s_ba_d      = s_bank_q;
        s_oe_d      = 1'b1;
        s_dq_d      = s_wdata_q[15:0];
        s_dqm_d     = ~s_wstrb_q[1:0];
        s_addr_d    = col_addr(s_col_q, s_auto_pre);
        s_last_wr_d = 1'b1;
        if (s_auto_pre) begin
          s_bank_open_d[s_bank_q] = 1'b0;
        end
        s_state_d = StWriteHi;
      end
      StWriteHi: begin
        s_oe_d   = 1'b1;
        s_dq_d   = s_wdata_q[31:16];
        s_dqm_d  = ~s_wstrb_q[3:2];
        s_left_d = s_left_q - 5'd1;
        s_col_d  = s_col_q + 10'd2;
        if (s_left_q == 5'd1) begin
          s_state_d = StWait;
          s_ret_d   = StIdle;
          s_wait_d  = open_page_i ? cyc8(twr_i) : max16(cyc8(twr_i) + cyc8(trp_i), s_tras_left_q);
        end else begin
          s_state_d = StWriteGet;
        end
      end
      StWait: begin
        // Keep DQM low across the CAS wait so BL2 beat 1 is not masked.
        if (s_ret_q == StReadLo) begin
          s_dqm_d = 2'b00;
        end
        s_wait_d = s_wait_q - 16'd1;
        if (s_wait_q == 16'd1) begin
          s_state_d = s_ret_q;
        end
      end
      default: s_state_d = StReset;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q      <= StReset;
      s_ret_q        <= StReset;
      s_wait_q       <= '0;
      s_cmd_q        <= SdramCmdNop;
      s_cke_q        <= 1'b0;
      s_ba_q         <= '0;
      s_addr_q       <= '0;
      s_dqm_q        <= 2'b11;
      s_dq_q         <= '0;
      s_oe_q         <= 1'b0;
      s_rdata_q      <= '0;
      s_rd_valid_q   <= 1'b0;
      s_wr_done_q    <= 1'b0;
      s_ready_q      <= 1'b0;
      s_init_busy_q  <= 1'b1;
      s_init_done_q  <= 1'b0;
      s_sel_wr_q     <= 1'b0;
      s_bank_q       <= '0;
      s_row_q        <= '0;
      s_col_q        <= '0;
      s_left_q       <= '0;
      s_wdata_q      <= '0;
      s_wstrb_q      <= '0;
      s_cas_q        <= 2'd2;
      s_bank_open_q  <= '0;
      s_open_row0_q  <= '0;
      s_open_row1_q  <= '0;
      s_open_row2_q  <= '0;
      s_open_row3_q  <= '0;
      s_refi_q       <= 16'd1;
      s_credit_q     <= '0;
      s_tras_left_q  <= '0;
      s_trc_left_q   <= '0;
      s_rrd_left_q   <= '0;
      s_last_wr_q    <= 1'b0;
      s_init_req_q   <= 1'b0;
      s_reinit_req_q <= 1'b0;
      s_pre_req_q    <= 1'b0;
      s_ref_req_q    <= 1'b0;
      s_hit_q        <= 1'b0;
      s_miss_q       <= 1'b0;
      s_conflict_q   <= 1'b0;
      s_ref_stall_q  <= 1'b0;
      s_rd_bytes_q   <= '0;
      s_wr_bytes_q   <= '0;
    end else begin
      if (init_start_i) begin
        s_init_req_q <= 1'b1;
      end else if (sec_edge_i && (s_state_q == StReset || s_state_q == StIdle) &&
          s_init_req_q && !s_resp_hold) begin
        s_init_req_q <= 1'b0;
      end
      if (reinit_start_i) begin
        s_reinit_req_q <= 1'b1;
      end else if (sec_edge_i && (s_state_q == StIdle) && s_reinit_req_q && !s_resp_hold) begin
        s_reinit_req_q <= 1'b0;
      end
      if (precharge_all_i) begin
        s_pre_req_q <= 1'b1;
      end else if (sec_edge_i && (s_state_q == StPreAll)) begin
        s_pre_req_q <= 1'b0;
      end else if (sec_edge_i && (s_state_q == StIdle) && s_pre_req_q &&
          (s_bank_open_q == 4'd0) && !s_resp_hold) begin
        s_pre_req_q <= 1'b0;
      end
      if (refresh_start_i) begin
        s_ref_req_q <= 1'b1;
      end else if (sec_edge_i && (s_state_q == StRefresh)) begin
        s_ref_req_q <= 1'b0;
      end

      if (s_rd_valid_q && rd_data_ready_i && !(fir_edge_i && (s_state_q == StReadHi))) begin
        s_rd_valid_q <= 1'b0;
      end
      if (s_wr_done_q && wr_done_ready_i &&
          !(sec_edge_i && (s_state_q == StWriteHi) && (s_left_q == 5'd1))) begin
        s_wr_done_q <= 1'b0;
      end

      s_init_done_q <= 1'b0;
      s_hit_q       <= 1'b0;
      s_miss_q      <= 1'b0;
      s_conflict_q  <= 1'b0;
      s_ref_stall_q <= 1'b0;
      s_rd_bytes_q  <= '0;
      s_wr_bytes_q  <= '0;

      if (fir_edge_i) begin
        s_rdata_q <= s_rdata_d;
        if (s_state_q == StReadHi) begin
          s_rd_valid_q <= 1'b1;
          s_rd_bytes_q <= 3'd4;
        end
      end

      if (sec_edge_i) begin
        s_state_q     <= s_state_d;
        s_ret_q       <= s_ret_d;
        s_wait_q      <= s_wait_d;
        s_cmd_q       <= s_cmd_d;
        s_cke_q       <= s_cke_d;
        s_ba_q        <= s_ba_d;
        s_addr_q      <= s_addr_d;
        s_dqm_q       <= s_dqm_d;
        s_dq_q        <= s_dq_d;
        s_oe_q        <= s_oe_d;
        s_ready_q     <= s_ready_d;
        s_init_busy_q <= s_init_busy_d;
        s_sel_wr_q    <= s_sel_wr_d;
        s_bank_q      <= s_bank_d;
        s_row_q       <= s_row_d;
        s_col_q       <= s_col_d;
        s_left_q      <= s_left_d;
        s_wdata_q     <= s_wdata_d;
        s_wstrb_q     <= s_wstrb_d;
        s_cas_q       <= s_cas_d;
        s_bank_open_q <= s_bank_open_d;
        s_open_row0_q <= s_open_row0_d;
        s_open_row1_q <= s_open_row1_d;
        s_open_row2_q <= s_open_row2_d;
        s_open_row3_q <= s_open_row3_d;
        s_last_wr_q   <= s_last_wr_d;
        s_tras_left_q <= s_tras_left_d;
        s_trc_left_q  <= s_trc_left_d;
        s_rrd_left_q  <= s_rrd_left_d;
        if (s_state_q == StInitMrs) begin
          s_init_done_q <= 1'b1;
        end
        if ((s_state_q == StIdle) && (s_take_wr || s_take_rd)) begin
          s_hit_q       <= s_row_hit;
          s_miss_q      <= !s_row_hit;
          s_conflict_q  <= s_row_conflict;
          s_ref_stall_q <= s_force_refresh;
        end
        if ((s_state_q == StIdle) && (s_force_refresh || s_oppo_refresh) &&
            (rd_cmd_valid_i || wr_cmd_valid_i)) begin
          s_ref_stall_q <= 1'b1;
        end
        if ((s_state_q == StWriteHi) && (s_left_q == 5'd1)) begin
          s_wr_done_q  <= 1'b1;
          s_wr_bytes_q <= 3'(s_wstrb_q[0] + s_wstrb_q[1] + s_wstrb_q[2] + s_wstrb_q[3]);
        end else if (s_state_q == StWriteHi) begin
          s_wr_bytes_q <= 3'(s_wstrb_q[0] + s_wstrb_q[1] + s_wstrb_q[2] + s_wstrb_q[3]);
        end
        if (s_state_q == StRefresh) begin
          s_credit_q <= s_credit_d;
          s_refi_q   <= s_refi_d;
        end else if (s_ready_q) begin
          if (s_refi_q == 16'd1) begin
            s_refi_q <= cyc16(trefi_i);
            if (s_credit_q < credit_max_i) begin
              s_credit_q <= s_credit_q + 4'd1;
            end
          end else begin
            s_refi_q <= s_refi_q - 16'd1;
          end
        end else begin
          s_refi_q   <= s_refi_d;
          s_credit_q <= s_credit_d;
        end
      end
    end
  end

endmodule
