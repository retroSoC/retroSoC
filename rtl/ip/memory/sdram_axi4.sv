// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

`include "axi4_define.svh"
`include "mmap_define.svh"
`include "sdram_define.svh"

module sdram_axi4 (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic                    clk_i,
    input  logic                    rst_n_i,
    input  logic                    accept_enable_i,
    input  logic                    core_ready_i,
    output logic                    busy_o,
    output logic                    stall_event_o,
    axi4_if.slave                   axi4,
    output logic                    rd_cmd_valid_o,
    input  logic                    rd_cmd_ready_i,
    output logic [1:0]              rd_cmd_bank_o,
    output logic [12:0]             rd_cmd_row_o,
    output logic [9:0]              rd_cmd_col_o,
    output logic [3:0]              rd_cmd_len_o,
    input  logic                    rd_data_valid_i,
    output logic                    rd_data_ready_o,
    input  logic [31:0]             rd_data_rdata_i,
    input  logic                    rd_data_error_i,
    output logic                    wr_cmd_valid_o,
    input  logic                    wr_cmd_ready_i,
    output logic [1:0]              wr_cmd_bank_o,
    output logic [12:0]             wr_cmd_row_o,
    output logic [9:0]              wr_cmd_col_o,
    output logic [3:0]              wr_cmd_len_o,
    output logic                    wr_data_valid_o,
    input  logic                    wr_data_ready_i,
    output logic [31:0]             wr_data_wdata_o,
    output logic [3:0]              wr_data_wstrb_o,
    input  logic                    wr_done_valid_i,
    output logic                    wr_done_ready_o,
    input  logic                    wr_done_error_i,
    output logic                    error_event_o,
    output sdram_pkg::sdram_error_e error_code_o,
    output logic [31:0]             error_addr_o
    // verilog_format: on
);

  import sdram_pkg::*;

  localparam int unsigned CmdWidth = 47;
  localparam int unsigned WdWidth = 37;
  localparam int unsigned RdWidth = 36;
  localparam int unsigned BdWidth = 3;

  // verilog_format: off -- preserve reviewed column alignment
  typedef enum logic [2:0] {
    RdIdle = 3'd0,
    RdCmd  = 3'd1,
    RdData = 3'd2,
    RdErr  = 3'd3
  } sdram_rd_state_e;

  typedef enum logic [2:0] {
    WrIdle     = 3'd0,
    WrCmd      = 3'd1,
    WrData     = 3'd2,
    WrDone     = 3'd3,
    WrErrDrain = 3'd4,
    WrErrResp  = 3'd5
  } sdram_wr_state_e;
  // verilog_format: on

  logic                           s_ar_full;
  logic                           s_ar_empty;
  logic            [CmdWidth-1:0] s_ar_data;
  logic                           s_aw_full;
  logic                           s_aw_empty;
  logic            [CmdWidth-1:0] s_aw_data;
  logic                           s_w_full;
  logic                           s_w_empty;
  logic            [ WdWidth-1:0] s_w_data;
  logic                           s_r_full;
  logic                           s_r_empty;
  logic            [ RdWidth-1:0] s_r_push_data;
  logic            [ RdWidth-1:0] s_r_data;
  logic                           s_b_full;
  logic                           s_b_empty;
  logic            [ BdWidth-1:0] s_b_push_data;
  logic            [ BdWidth-1:0] s_b_data;

  logic                           s_ar_pop;
  logic                           s_aw_pop;
  logic                           s_w_pop;
  logic                           s_r_push;
  logic                           s_b_push;

  logic            [        31:0] s_ar_addr;
  logic            [         7:0] s_ar_len;
  logic            [         2:0] s_ar_size;
  logic            [         1:0] s_ar_burst;
  logic                           s_ar_id;
  logic                           s_ar_lock;
  logic            [        31:0] s_aw_addr;
  logic            [         7:0] s_aw_len;
  logic            [         2:0] s_aw_size;
  logic            [         1:0] s_aw_burst;
  logic                           s_aw_id;
  logic                           s_aw_lock;

  sdram_rd_state_e                s_rd_state_q;
  sdram_rd_state_e                s_rd_state_d;
  logic            [        31:0] s_rd_addr_q;
  logic            [        31:0] s_rd_addr_d;
  logic            [         7:0] s_rd_left_q;
  logic            [         7:0] s_rd_left_d;
  logic            [         3:0] s_rd_frag_q;
  logic            [         3:0] s_rd_frag_d;
  logic            [         2:0] s_rd_size_q;
  logic            [         2:0] s_rd_size_d;
  logic            [         1:0] s_rd_burst_q;
  logic            [         1:0] s_rd_burst_d;
  logic                           s_rd_id_q;
  logic                           s_rd_id_d;
  logic            [         1:0] s_rd_resp_q;
  logic            [         1:0] s_rd_resp_d;

  sdram_wr_state_e                s_wr_state_q;
  sdram_wr_state_e                s_wr_state_d;
  logic            [        31:0] s_wr_addr_q;
  logic            [        31:0] s_wr_addr_d;
  logic            [         7:0] s_wr_left_q;
  logic            [         7:0] s_wr_left_d;
  logic            [         3:0] s_wr_frag_q;
  logic            [         3:0] s_wr_frag_d;
  logic            [         2:0] s_wr_size_q;
  logic            [         2:0] s_wr_size_d;
  logic            [         1:0] s_wr_burst_q;
  logic            [         1:0] s_wr_burst_d;
  logic                           s_wr_id_q;
  logic                           s_wr_id_d;
  logic            [         1:0] s_wr_resp_q;
  logic            [         1:0] s_wr_resp_d;

  logic                           s_rd_err_event_d;
  logic                           s_wr_err_event_d;
  logic                           s_err_event_q;
  sdram_error_e                   s_rd_err_code_d;
  sdram_error_e                   s_wr_err_code_d;
  sdram_error_e                   s_err_code_q;
  logic            [        31:0] s_rd_err_addr_d;
  logic            [        31:0] s_wr_err_addr_d;
  logic            [        31:0] s_err_addr_q;

  function automatic logic [32:0] burst_last_addr(input logic [31:0] addr, input logic [7:0] length,
                                                  input logic [2:0] size, input logic [1:0] burst);
    logic [32:0] beat_bytes;
    logic [32:0] burst_bytes;
    logic [32:0] wrap_base;
    begin
      beat_bytes  = 33'd1 << size;
      burst_bytes = beat_bytes * ({25'd0, length} + 1'b1);
      wrap_base   = {1'b0, addr} & ~(burst_bytes - 1'b1);
      unique case (burst)
        `AXI4_BURST_TYPE_FIXED: burst_last_addr = {1'b0, addr} + beat_bytes - 1'b1;
        `AXI4_BURST_TYPE_WRAP:  burst_last_addr = wrap_base + burst_bytes - 1'b1;
        default:                burst_last_addr = {1'b0, addr} + burst_bytes - 1'b1;
      endcase
    end
  endfunction

  function automatic logic wrap_length_legal(input logic [7:0] length);
    return (length == 8'd1) || (length == 8'd3) || (length == 8'd7) || (length == 8'd15);
  endfunction

  function automatic logic axi_legal(input logic [31:0] addr, input logic [7:0] length,
                                     input logic [2:0] size, input logic [1:0] burst,
                                     input logic lock);
    logic [32:0] last_addr;
    begin
      last_addr = burst_last_addr(addr, length, size, burst);
      axi_legal = (length <= 8'd15) &&
          ((burst == `AXI4_BURST_TYPE_FIXED) || (burst == `AXI4_BURST_TYPE_INCR) ||
           ((burst == `AXI4_BURST_TYPE_WRAP) && wrap_length_legal(length))) && !lock &&
          (size <= `AXI4_BURST_SIZE_4BYTES) && ((addr & ((32'd1 << size) - 1'b1)) == '0) &&
          !last_addr[32] && (addr[31:12] == last_addr[31:12]);
    end
  endfunction

  function automatic logic addr_in_window(input logic [31:0] addr);
    return (addr >= `SOC_ADDR_SDRAM_BASE) && (addr <= `SOC_ADDR_SDRAM_END);
  endfunction

  function automatic logic [25:0] rel_addr(input logic [31:0] addr);
    return addr - `SOC_ADDR_SDRAM_BASE;
  endfunction

  function automatic logic [1:0] req_bank(input logic [31:0] addr);
    logic [25:0] relative;
    begin
      relative = rel_addr(addr);
      req_bank = relative[25:24];
    end
  endfunction

  function automatic logic [12:0] req_row(input logic [31:0] addr);
    logic [25:0] relative;
    begin
      relative = rel_addr(addr);
      req_row  = relative[23:11];
    end
  endfunction

  function automatic logic [9:0] req_col(input logic [31:0] addr);
    logic [25:0] relative;
    begin
      relative = rel_addr(addr);
      req_col  = {relative[10:2], 1'b0};
    end
  endfunction

  function automatic logic [7:0] beats_to_row_end(input logic [31:0] addr);
    logic [25:0] relative;
    logic [11:0] rem_bytes;
    begin
      relative         = rel_addr(addr);
      rem_bytes        = 12'h800 - {1'b0, relative[10:0]};
      beats_to_row_end = rem_bytes[11:2];
    end
  endfunction

  function automatic logic [7:0] beats_to_wrap(input logic [31:0] addr, input logic [7:0] length,
                                               input logic [2:0] size, input logic [1:0] burst);
    logic [32:0] beat_bytes;
    logic [32:0] burst_bytes;
    logic [32:0] wrap_end;
    begin
      if (burst != `AXI4_BURST_TYPE_WRAP) begin
        return 8'd16;
      end
      beat_bytes    = 33'd1 << size;
      burst_bytes   = beat_bytes * ({25'd0, length} + 1'b1);
      wrap_end      = ({1'b0, addr} & ~(burst_bytes - 1'b1)) + burst_bytes;
      beats_to_wrap = 8'((wrap_end - {1'b0, addr}) >> size);
    end
  endfunction

  function automatic logic [3:0] fragment_beats(input logic [31:0] addr, input logic [7:0] left,
                                                input logic [7:0] alen, input logic [2:0] size,
                                                input logic [1:0] burst);
    logic [7:0] row_beats;
    logic [7:0] wrap_beats;
    logic [7:0] limited;
    begin
      if (burst == `AXI4_BURST_TYPE_FIXED) begin
        return 4'd0;
      end
      row_beats  = beats_to_row_end(addr);
      wrap_beats = beats_to_wrap(addr, alen, size, burst);
      limited    = left;
      if (row_beats < limited) limited = row_beats;
      if (wrap_beats < limited) limited = wrap_beats;
      if (limited == 8'd0) limited = 8'd1;
      if (limited > 8'd16) limited = 8'd16;
      fragment_beats = 4'(limited - 1'b1);
    end
  endfunction

  assign {s_ar_addr, s_ar_len, s_ar_size, s_ar_burst, s_ar_id, s_ar_lock} = s_ar_data;
  assign {s_aw_addr, s_aw_len, s_aw_size, s_aw_burst, s_aw_id, s_aw_lock} = s_aw_data;

  assign axi4.awready = !s_aw_full;
  assign axi4.wready = !s_w_full;
  assign axi4.arready = !s_ar_full;
  assign axi4.bvalid = !s_b_empty;
  assign axi4.bid = s_b_data[0];
  assign axi4.bresp = s_b_data[2:1];
  assign axi4.buser = '0;
  assign axi4.rvalid = !s_r_empty;
  assign axi4.rid = s_r_data[0];
  assign axi4.rresp = s_r_data[2:1];
  assign axi4.rlast = s_r_data[3];
  assign axi4.rdata = s_r_data[35:4];
  assign axi4.ruser = '0;

  assign busy_o = (s_rd_state_q != RdIdle) || (s_wr_state_q != WrIdle) || !s_ar_empty ||
      !s_aw_empty || !s_w_empty || !s_r_empty || !s_b_empty;
  assign stall_event_o = ((s_rd_state_q == RdData) && rd_data_valid_i && !rd_data_ready_o) ||
      ((s_wr_state_q == WrData) && wr_data_valid_o && !wr_data_ready_i);

  assign rd_cmd_bank_o = req_bank(s_rd_addr_q);
  assign rd_cmd_row_o = req_row(s_rd_addr_q);
  assign rd_cmd_col_o = req_col(s_rd_addr_q);
  assign rd_cmd_len_o = s_rd_frag_q;
  assign wr_cmd_bank_o = req_bank(s_wr_addr_q);
  assign wr_cmd_row_o = req_row(s_wr_addr_q);
  assign wr_cmd_col_o = req_col(s_wr_addr_q);
  assign wr_cmd_len_o = s_wr_frag_q;
  assign wr_data_wdata_o = s_w_data[36:5];
  assign wr_data_wstrb_o = s_w_data[4:1];

  assign error_event_o = s_err_event_q;
  assign error_code_o = s_err_code_q;
  assign error_addr_o = s_err_addr_q;

  fifo #(
      .DATA_WIDTH  (CmdWidth),
      .BUFFER_DEPTH(2)
  ) u_ar_fifo (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(1'b0),
      .push_i(axi4.arvalid && axi4.arready),
      .full_o(s_ar_full),
      .dat_i({axi4.araddr, axi4.arlen, axi4.arsize, axi4.arburst, axi4.arid[0], axi4.arlock}),
      .pop_i(s_ar_pop),
      .empty_o(s_ar_empty),
      .dat_o(s_ar_data),
      .cnt_o()  // occupancy is not part of the AXI handshake
  );
  fifo #(
      .DATA_WIDTH  (CmdWidth),
      .BUFFER_DEPTH(2)
  ) u_aw_fifo (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(1'b0),
      .push_i(axi4.awvalid && axi4.awready),
      .full_o(s_aw_full),
      .dat_i({axi4.awaddr, axi4.awlen, axi4.awsize, axi4.awburst, axi4.awid[0], axi4.awlock}),
      .pop_i(s_aw_pop),
      .empty_o(s_aw_empty),
      .dat_o(s_aw_data),
      .cnt_o()  // occupancy is not part of the AXI handshake
  );
  fifo #(
      .DATA_WIDTH  (WdWidth),
      .BUFFER_DEPTH(8)
  ) u_w_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(1'b0),
      .push_i (axi4.wvalid && axi4.wready),
      .full_o (s_w_full),
      .dat_i  ({axi4.wdata, axi4.wstrb, axi4.wlast}),
      .pop_i  (s_w_pop),
      .empty_o(s_w_empty),
      .dat_o  (s_w_data),
      .cnt_o  ()                                       // occupancy is not part of the AXI handshake
  );
  fifo #(
      .DATA_WIDTH  (RdWidth),
      .BUFFER_DEPTH(8)
  ) u_r_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(1'b0),
      .push_i (s_r_push),
      .full_o (s_r_full),
      .dat_i  (s_r_push_data),
      .pop_i  (axi4.rvalid && axi4.rready),
      .empty_o(s_r_empty),
      .dat_o  (s_r_data),
      .cnt_o  ()                             // occupancy is not part of the AXI handshake
  );
  fifo #(
      .DATA_WIDTH  (BdWidth),
      .BUFFER_DEPTH(2)
  ) u_b_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(1'b0),
      .push_i (s_b_push),
      .full_o (s_b_full),
      .dat_i  (s_b_push_data),
      .pop_i  (axi4.bvalid && axi4.bready),
      .empty_o(s_b_empty),
      .dat_o  (s_b_data),
      .cnt_o  ()                             // occupancy is not part of the AXI handshake
  );

  always_comb begin
    logic [31:0] next_rd_addr;
    logic [ 3:0] rd_frag;
    logic        rd_legal;
    logic        rd_window;
    logic [32:0] rd_last;

    s_rd_state_d     = s_rd_state_q;
    s_rd_addr_d      = s_rd_addr_q;
    s_rd_left_d      = s_rd_left_q;
    s_rd_frag_d      = s_rd_frag_q;
    s_rd_size_d      = s_rd_size_q;
    s_rd_burst_d     = s_rd_burst_q;
    s_rd_id_d        = s_rd_id_q;
    s_rd_resp_d      = s_rd_resp_q;
    s_ar_pop         = 1'b0;
    s_r_push         = 1'b0;
    s_r_push_data    = '0;
    rd_cmd_valid_o   = 1'b0;
    rd_data_ready_o  = 1'b0;
    s_rd_err_event_d = 1'b0;
    s_rd_err_code_d  = SdramErrNone;
    s_rd_err_addr_d  = s_err_addr_q;
    next_rd_addr     = s_rd_addr_q;
    rd_frag          = '0;
    rd_legal         = 1'b0;
    rd_window        = 1'b0;
    rd_last          = '0;

    unique case (s_rd_state_q)
      RdIdle: begin
        if (!s_ar_empty) begin
          rd_last   = burst_last_addr(s_ar_addr, s_ar_len, s_ar_size, s_ar_burst);
          rd_legal  = axi_legal(s_ar_addr, s_ar_len, s_ar_size, s_ar_burst, s_ar_lock);
          rd_window = addr_in_window(s_ar_addr) && !rd_last[32] && addr_in_window(rd_last[31:0]);
          if (!rd_legal || !rd_window || !accept_enable_i) begin
            s_ar_pop         = 1'b1;
            s_rd_addr_d      = s_ar_addr;
            s_rd_left_d      = s_ar_len + 8'd1;
            s_rd_size_d      = s_ar_size;
            s_rd_burst_d     = s_ar_burst;
            s_rd_id_d        = s_ar_id;
            s_rd_resp_d      = `AXI4_RESP_SLAVE_ERROR;
            s_rd_state_d     = RdErr;
            s_rd_err_event_d = 1'b1;
            s_rd_err_code_d  = rd_window ? SdramErrAxiIllegal : SdramErrAxiDecode;
            s_rd_err_addr_d  = s_ar_addr;
          end else if (core_ready_i) begin
            s_ar_pop = 1'b1;
            s_rd_addr_d = s_ar_addr;
            s_rd_left_d = s_ar_len + 8'd1;
            s_rd_size_d = s_ar_size;
            s_rd_burst_d = s_ar_burst;
            s_rd_id_d = s_ar_id;
            rd_frag = fragment_beats(s_ar_addr, s_ar_len + 8'd1, s_ar_len, s_ar_size, s_ar_burst);
            s_rd_frag_d = rd_frag;
            s_rd_resp_d = `AXI4_RESP_OKAY;
            s_rd_state_d = RdCmd;
          end
        end
      end
      RdCmd: begin
        rd_cmd_valid_o = 1'b1;
        if (rd_cmd_ready_i) begin
          s_rd_state_d = RdData;
        end
      end
      RdData: begin
        rd_data_ready_o = !s_r_full;
        if (rd_data_valid_i && rd_data_ready_o) begin
          if (rd_data_error_i) begin
            s_rd_resp_d      = `AXI4_RESP_SLAVE_ERROR;
            s_rd_err_event_d = 1'b1;
            s_rd_err_code_d  = SdramErrAxiDecode;
            s_rd_err_addr_d  = s_rd_addr_q;
          end
          s_r_push      = 1'b1;
          s_r_push_data = {rd_data_rdata_i, (s_rd_left_q == 8'd1), s_rd_resp_d, s_rd_id_q};
          if (s_rd_burst_q == `AXI4_BURST_TYPE_FIXED) begin
            next_rd_addr = s_rd_addr_q;
          end else begin
            next_rd_addr = s_rd_addr_q + (32'd1 << s_rd_size_q);
            if ((s_rd_burst_q == `AXI4_BURST_TYPE_WRAP) && (beats_to_wrap(
                    s_rd_addr_q, s_rd_left_q - 8'd1, s_rd_size_q, s_rd_burst_q
                ) == 8'd1)) begin
              next_rd_addr = s_rd_addr_q & ~((32'd1 << s_rd_size_q) - 1'b1);
              next_rd_addr = next_rd_addr - (((32'(s_rd_left_q) - 32'd1) << s_rd_size_q));
            end
          end
          s_rd_addr_d = next_rd_addr;
          s_rd_left_d = s_rd_left_q - 8'd1;
          if (s_rd_frag_q != 4'd0) begin
            s_rd_frag_d = s_rd_frag_q - 4'd1;
          end else if (s_rd_left_q == 8'd1) begin
            s_rd_state_d = RdIdle;
          end else begin
            rd_frag = fragment_beats(next_rd_addr, s_rd_left_q - 8'd1, s_rd_left_q - 8'd1,
                                     s_rd_size_q, s_rd_burst_q);
            s_rd_frag_d = rd_frag;
            s_rd_state_d = RdCmd;
          end
        end
      end
      RdErr: begin
        if (!s_r_full) begin
          s_r_push      = 1'b1;
          s_r_push_data = {32'd0, (s_rd_left_q == 8'd1), s_rd_resp_q, s_rd_id_q};
          s_rd_left_d   = s_rd_left_q - 8'd1;
          if (s_rd_left_q == 8'd1) begin
            s_rd_state_d = RdIdle;
          end
        end
      end
      default: s_rd_state_d = RdIdle;
    endcase
  end

  always_comb begin
    logic [ 3:0] wr_frag;
    logic        wr_legal;
    logic        wr_window;
    logic [32:0] wr_last;

    s_wr_state_d     = s_wr_state_q;
    s_wr_addr_d      = s_wr_addr_q;
    s_wr_left_d      = s_wr_left_q;
    s_wr_frag_d      = s_wr_frag_q;
    s_wr_size_d      = s_wr_size_q;
    s_wr_burst_d     = s_wr_burst_q;
    s_wr_id_d        = s_wr_id_q;
    s_wr_resp_d      = s_wr_resp_q;
    s_aw_pop         = 1'b0;
    s_w_pop          = 1'b0;
    s_b_push         = 1'b0;
    s_b_push_data    = '0;
    wr_cmd_valid_o   = 1'b0;
    wr_data_valid_o  = 1'b0;
    wr_done_ready_o  = 1'b0;
    s_wr_err_event_d = 1'b0;
    s_wr_err_code_d  = SdramErrNone;
    s_wr_err_addr_d  = s_err_addr_q;
    wr_frag          = '0;
    wr_legal         = 1'b0;
    wr_window        = 1'b0;
    wr_last          = '0;

    unique case (s_wr_state_q)
      WrIdle: begin
        if (!s_aw_empty) begin
          wr_last   = burst_last_addr(s_aw_addr, s_aw_len, s_aw_size, s_aw_burst);
          wr_legal  = axi_legal(s_aw_addr, s_aw_len, s_aw_size, s_aw_burst, s_aw_lock);
          wr_window = addr_in_window(s_aw_addr) && !wr_last[32] && addr_in_window(wr_last[31:0]);
          if (!wr_legal || !wr_window || !accept_enable_i) begin
            s_aw_pop         = 1'b1;
            s_wr_addr_d      = s_aw_addr;
            s_wr_left_d      = s_aw_len + 8'd1;
            s_wr_size_d      = s_aw_size;
            s_wr_burst_d     = s_aw_burst;
            s_wr_id_d        = s_aw_id;
            s_wr_resp_d      = `AXI4_RESP_SLAVE_ERROR;
            s_wr_state_d     = WrErrDrain;
            s_wr_err_event_d = 1'b1;
            s_wr_err_code_d  = wr_window ? SdramErrAxiIllegal : SdramErrAxiDecode;
            s_wr_err_addr_d  = s_aw_addr;
          end else if (core_ready_i) begin
            s_aw_pop = 1'b1;
            s_wr_addr_d = s_aw_addr;
            s_wr_left_d = s_aw_len + 8'd1;
            s_wr_size_d = s_aw_size;
            s_wr_burst_d = s_aw_burst;
            s_wr_id_d = s_aw_id;
            wr_frag = fragment_beats(s_aw_addr, s_aw_len + 8'd1, s_aw_len, s_aw_size, s_aw_burst);
            s_wr_frag_d = wr_frag;
            s_wr_resp_d = `AXI4_RESP_OKAY;
            s_wr_state_d = WrCmd;
          end
        end
      end
      WrCmd: begin
        wr_cmd_valid_o = 1'b1;
        if (wr_cmd_ready_i) begin
          s_wr_state_d = WrData;
        end
      end
      WrData: begin
        wr_data_valid_o = !s_w_empty;
        if (!s_w_empty && wr_data_ready_i) begin
          s_w_pop = 1'b1;
          if (s_w_data[0] != (s_wr_left_q == 8'd1)) begin
            s_wr_resp_d = `AXI4_RESP_SLAVE_ERROR;
          end
          if (s_wr_burst_q != `AXI4_BURST_TYPE_FIXED) begin
            s_wr_addr_d = s_wr_addr_q + (32'd1 << s_wr_size_q);
          end
          s_wr_left_d = s_wr_left_q - 8'd1;
          if (s_wr_frag_q != 4'd0) begin
            s_wr_frag_d = s_wr_frag_q - 4'd1;
          end else begin
            s_wr_state_d = WrDone;
          end
        end
      end
      WrDone: begin
        wr_done_ready_o = 1'b1;
        if (wr_done_valid_i) begin
          if (wr_done_error_i) begin
            s_wr_resp_d = `AXI4_RESP_SLAVE_ERROR;
          end
          if (s_wr_left_q == 8'd0) begin
            if (!s_b_full) begin
              s_b_push      = 1'b1;
              s_b_push_data = {s_wr_resp_d, s_wr_id_q};
              s_wr_state_d  = WrIdle;
            end
          end else begin
            wr_frag =
                fragment_beats(s_wr_addr_q, s_wr_left_q, s_wr_left_q, s_wr_size_q, s_wr_burst_q);
            s_wr_frag_d = wr_frag;
            s_wr_state_d = WrCmd;
          end
        end
      end
      WrErrDrain: begin
        if (!s_w_empty) begin
          s_w_pop = 1'b1;
          if (s_w_data[0]) begin
            s_wr_state_d = WrErrResp;
          end
        end
      end
      WrErrResp: begin
        if (!s_b_full) begin
          s_b_push      = 1'b1;
          s_b_push_data = {s_wr_resp_q, s_wr_id_q};
          s_wr_state_d  = WrIdle;
        end
      end
      default: s_wr_state_d = WrIdle;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_rd_state_q  <= RdIdle;
      s_rd_addr_q   <= '0;
      s_rd_left_q   <= '0;
      s_rd_frag_q   <= '0;
      s_rd_size_q   <= '0;
      s_rd_burst_q  <= '0;
      s_rd_id_q     <= '0;
      s_rd_resp_q   <= `AXI4_RESP_OKAY;
      s_wr_state_q  <= WrIdle;
      s_wr_addr_q   <= '0;
      s_wr_left_q   <= '0;
      s_wr_frag_q   <= '0;
      s_wr_size_q   <= '0;
      s_wr_burst_q  <= '0;
      s_wr_id_q     <= '0;
      s_wr_resp_q   <= `AXI4_RESP_OKAY;
      s_err_event_q <= 1'b0;
      s_err_code_q  <= SdramErrNone;
      s_err_addr_q  <= '0;
    end else begin
      s_rd_state_q <= s_rd_state_d;
      s_rd_addr_q <= s_rd_addr_d;
      s_rd_left_q <= s_rd_left_d;
      s_rd_frag_q <= s_rd_frag_d;
      s_rd_size_q <= s_rd_size_d;
      s_rd_burst_q <= s_rd_burst_d;
      s_rd_id_q <= s_rd_id_d;
      s_rd_resp_q <= s_rd_resp_d;
      s_wr_state_q <= s_wr_state_d;
      s_wr_addr_q <= s_wr_addr_d;
      s_wr_left_q <= s_wr_left_d;
      s_wr_frag_q <= s_wr_frag_d;
      s_wr_size_q <= s_wr_size_d;
      s_wr_burst_q <= s_wr_burst_d;
      s_wr_id_q <= s_wr_id_d;
      s_wr_resp_q <= s_wr_resp_d;
      s_err_event_q <= s_rd_err_event_d || s_wr_err_event_d;
      s_err_code_q  <= s_wr_err_event_d ? s_wr_err_code_d :
          (s_rd_err_event_d ? s_rd_err_code_d : s_err_code_q);
      s_err_addr_q  <= s_wr_err_event_d ? s_wr_err_addr_d :
          (s_rd_err_event_d ? s_rd_err_addr_d : s_err_addr_q);
    end
  end

endmodule
