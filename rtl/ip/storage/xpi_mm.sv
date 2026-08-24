// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "axi4_define.svh"
`include "xpi_define.svh"

module xpi_mm (
    // verilog_format: off -- preserve reviewed port alignment
    input  logic                    clk_i,
    input  logic                    rst_n_i,
    input  logic                    accept_enable_i,
    input  logic                    controller_enable_i,
    input  logic [             31:0] slot_ctrl_i [0:3],
    input  logic [             31:0] slot_size_i [0:3],
    input  logic [             31:0] slot_seq_i  [0:3],
    input  logic [             31:0] slot_boundary_i [0:3],
    axi4_if.slave                    axi4,
    output logic                    busy_o,
    output logic                    core_req_valid_o,
    input  logic                    core_req_ready_i,
    output logic [              1:0] core_req_slot_o,
    output logic [              3:0] core_req_seq_o,
    output logic [             31:0] core_req_addr_o,
    output logic [             15:0] core_req_len_o,
    output logic                    core_tx_valid_o,
    input  logic                    core_tx_ready_i,
    output logic [              7:0] core_tx_data_o,
    input  logic                    core_rx_valid_i,
    output logic                    core_rx_ready_o,
    input  logic [              7:0] core_rx_data_i,
    input  logic                    core_done_i,
    input  logic                    core_error_i,
    input  xpi_pkg::xpi_error_e     core_error_code_i,
    input  logic [              2:0] core_error_pc_i,
    output logic                    axi_error_event_o,
    output xpi_pkg::xpi_error_e     error_code_o,
    output logic [             31:0] error_addr_o,
    output logic [              1:0] error_slot_o,
    output logic [              2:0] error_pc_o,
    output logic                    perf_read_byte_event_o,
    output logic                    perf_write_byte_event_o,
    output logic                    perf_command_event_o,
    output logic                    perf_split_event_o,
    output logic                    perf_stall_event_o
    // verilog_format: on
);

  import xpi_pkg::*;

  typedef enum logic [3:0] {
    Idle,
    ReadRequest,
    ReadData,
    ReadFrameWait,
    ReadFinish,
    ReadErrorResponse,
    WriteCollect,
    WriteScan,
    WriteRequest,
    WriteStream,
    WriteWait,
    WriteDrain,
    WriteResponse
  } xpi_mm_state_e;

  logic [3:0] s_state_bits_q;
  xpi_mm_state_e s_state_d, s_state_q;
  logic [31:0] s_addr_d, s_addr_q;
  logic [31:0] s_start_addr_d, s_start_addr_q;
  logic [7:0] s_len_d, s_len_q;
  logic [7:0] s_beat_d, s_beat_q;
  logic [2:0] s_size_d, s_size_q;
  logic [1:0] s_burst_d, s_burst_q;
  logic s_id_d, s_id_q;
  logic [1:0] s_slot_d, s_slot_q;
  logic [1:0] s_resp_d, s_resp_q;
  logic [31:0] s_rdata_d, s_rdata_q;
  logic s_rvalid_d, s_rvalid_q;
  logic [2:0] s_byte_idx_d, s_byte_idx_q;
  logic [6:0] s_cursor_d, s_cursor_q;
  logic [6:0] s_run_end_d, s_run_end_q;
  logic s_coalesce_d, s_coalesce_q;
  logic s_frame_done_d, s_frame_done_q;
  logic s_transaction_err_d, s_transaction_err_q;
  logic [1:0] s_cmd_count_d, s_cmd_count_q;
  logic [3:0] s_err_code_bits_q;
  xpi_error_e s_err_code_d, s_err_code_q;
  logic [31:0] s_err_addr_d, s_err_addr_q;
  logic [1:0] s_err_slot_d, s_err_slot_q;
  logic [2:0] s_err_pc_d, s_err_pc_q;

  logic [35:0] s_write_buffer_d      [0:15];
  logic [35:0] s_write_buffer_q      [0:15];
  logic [15:0] s_write_buffer_en;

  logic [31:0] s_next_addr;
  logic [32:0] s_write_last_addr;
  logic [32:0] s_read_last_addr;
  logic        s_legal_write;
  logic        s_legal_read;
  logic [ 1:0] s_incoming_write_slot;
  logic [ 1:0] s_incoming_read_slot;
  logic [ 3:0] s_write_lane_mask;
  logic [ 6:0] s_total_bytes;
  logic [ 6:0] s_scan_limit;
  logic        s_scan_found;
  logic        s_scan_closed;
  logic [ 6:0] s_scan_start;
  logic [ 6:0] s_scan_len;
  logic        s_scan_active;
  logic [ 3:0] s_scan_beat;
  logic [ 1:0] s_scan_lane;
  logic [ 3:0] s_tx_beat;
  logic [ 1:0] s_tx_lane;
  logic [ 2:0] s_read_lane;
  logic        s_write_boundary_ok;
  logic        s_read_boundary_ok;

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

  function automatic logic address_supported(input logic [31:0] addr);
    return (addr < XPI_BOOT_SIZE) ||
           ((addr >= XPI_WINDOW_BASE) && (addr < (XPI_WINDOW_BASE + XPI_WINDOW_SIZE)));
  endfunction

  function automatic logic [1:0] address_slot(input logic [31:0] addr);
    if (addr < XPI_BOOT_SIZE) return 2'd0;
    return addr[27:26];
  endfunction

  function automatic logic [31:0] device_address(input logic [31:0] addr);
    if (addr < XPI_BOOT_SIZE) return addr;
    return {6'd0, addr[25:0]};
  endfunction

  function automatic logic burst_type_legal(input logic [1:0] burst, input logic [7:0] length);
    return (burst == `AXI4_BURST_TYPE_FIXED) || (burst == `AXI4_BURST_TYPE_INCR) ||
           ((burst == `AXI4_BURST_TYPE_WRAP) && wrap_length_legal(length));
  endfunction

  assign s_state_q = xpi_mm_state_e'(s_state_bits_q);
  assign s_write_last_addr = burst_last_addr(axi4.awaddr, axi4.awlen, axi4.awsize, axi4.awburst);
  assign s_read_last_addr = burst_last_addr(axi4.araddr, axi4.arlen, axi4.arsize, axi4.arburst);
  assign s_incoming_write_slot = address_slot(axi4.awaddr);
  assign s_incoming_read_slot = address_slot(axi4.araddr);
  assign s_write_boundary_ok = (slot_boundary_i[s_incoming_write_slot] == 32'd0) ||
      ((device_address(
      axi4.awaddr
  ) & ~(slot_boundary_i[s_incoming_write_slot] - 1'b1)) == (device_address(
      s_write_last_addr[31:0]
  ) & ~(slot_boundary_i[s_incoming_write_slot] - 1'b1)));
  assign s_read_boundary_ok = (slot_boundary_i[s_incoming_read_slot] == 32'd0) || ((device_address(
      axi4.araddr
  ) & ~(slot_boundary_i[s_incoming_read_slot] - 1'b1)) == (device_address(
      s_read_last_addr[31:0]
  ) & ~(slot_boundary_i[s_incoming_read_slot] - 1'b1)));

  assign s_legal_write = address_supported(
      axi4.awaddr
  ) && controller_enable_i && address_supported(
      s_write_last_addr[31:0]
  ) && !s_write_last_addr[32] && (axi4.awaddr >= XPI_WINDOW_BASE) && (address_slot(
      axi4.awaddr
  ) == address_slot(
      s_write_last_addr[31:0]
  )) && (device_address(
      s_write_last_addr[31:0]
  ) < slot_size_i[s_incoming_write_slot]) &&
      slot_ctrl_i[s_incoming_write_slot][`XPI_SLOT_CTRL_ENABLE] &&
      slot_ctrl_i[s_incoming_write_slot][`XPI_SLOT_CTRL_MM_WRITE_ENABLE] && (axi4.awlen <= 8'd15) &&
      burst_type_legal(
      axi4.awburst, axi4.awlen
  ) && !axi4.awlock && (axi4.awsize <= `AXI4_BURST_SIZE_4BYTES) &&
      ((axi4.awaddr & ((32'd1 << axi4.awsize) - 1'b1)) == 32'd0) &&
      (axi4.awaddr[31:12] == s_write_last_addr[31:12]);

  assign s_legal_read = address_supported(
      axi4.araddr
  ) && controller_enable_i && address_supported(
      s_read_last_addr[31:0]
  ) && !s_read_last_addr[32] && (address_slot(
      axi4.araddr
  ) == address_slot(
      s_read_last_addr[31:0]
  )) && (device_address(
      s_read_last_addr[31:0]
  ) < slot_size_i[s_incoming_read_slot]) && slot_ctrl_i[s_incoming_read_slot][
      `XPI_SLOT_CTRL_ENABLE] && slot_ctrl_i[s_incoming_read_slot][`XPI_SLOT_CTRL_MM_READ_ENABLE] &&
      (axi4.arlen <= 8'd15) && burst_type_legal(
      axi4.arburst, axi4.arlen
  ) && !axi4.arlock && (axi4.arsize <= `AXI4_BURST_SIZE_4BYTES) &&
      ((axi4.araddr & ((32'd1 << axi4.arsize) - 1'b1)) == 32'd0) &&
      (axi4.araddr[31:12] == s_read_last_addr[31:12]);

  assign axi4.awready = (s_state_q == Idle) && accept_enable_i && !axi4.arvalid;
  assign axi4.arready = (s_state_q == Idle) && accept_enable_i;
  assign axi4.wready = (s_state_q == WriteCollect) || (s_state_q == WriteDrain);
  assign axi4.bid = s_id_q;
  assign axi4.bresp = s_resp_q;
  assign axi4.buser = '0;
  assign axi4.bvalid = s_state_q == WriteResponse;
  assign axi4.rid = s_id_q;
  assign axi4.rdata = s_rdata_q;
  assign axi4.rresp = s_resp_q;
  assign axi4.rlast = s_beat_q == s_len_q;
  assign axi4.ruser = '0;
  assign axi4.rvalid = s_rvalid_q || (s_state_q == ReadErrorResponse);

  assign busy_o = s_state_q != Idle;
  assign core_req_valid_o = (s_state_q == ReadRequest) || (s_state_q == WriteRequest);
  assign core_req_slot_o = s_slot_q;
  assign core_req_seq_o = (s_state_q == ReadRequest) ? slot_seq_i[s_slot_q][3:0] :
                                                       slot_seq_i[s_slot_q][7:4];
  assign core_req_addr_o = (s_state_q == WriteRequest) ? (device_address(
      s_addr_q
  ) + {25'd0, s_scan_start}) : device_address(
      s_addr_q
  );
  assign core_req_len_o = (s_state_q == WriteRequest) ? {9'd0, s_scan_len} :
                          (s_coalesce_q ? {9'd0, s_total_bytes} :
                           (16'd1 << s_size_q));

  assign core_tx_valid_o = s_state_q == WriteStream;
  assign core_rx_ready_o = (s_state_q == ReadData) && !s_rvalid_q;
  assign core_tx_data_o = s_write_buffer_q[s_tx_beat][(s_tx_lane*8)+:8];

  assign s_err_code_q = xpi_error_e'(s_err_code_bits_q);
  assign error_code_o = s_err_code_q;
  assign error_addr_o = s_err_addr_q;
  assign error_slot_o = s_err_slot_q;
  assign error_pc_o = s_err_pc_q;
  assign perf_stall_event_o = (axi4.awvalid && !axi4.awready) ||
                              (axi4.wvalid && !axi4.wready) ||
                              (axi4.arvalid && !axi4.arready) ||
                              (axi4.rvalid && !axi4.rready) ||
                              (axi4.bvalid && !axi4.bready);

  assign s_total_bytes = 7'((14'({6'd0, s_len_q}) + 14'd1) << s_size_q);
  assign s_scan_limit = s_coalesce_q ? s_total_bytes : (7'd1 << s_size_q);

  always_comb begin
    s_scan_found  = 1'b0;
    s_scan_closed = 1'b0;
    s_scan_start  = s_cursor_q;
    s_scan_len    = '0;
    s_scan_active = 1'b0;
    s_scan_beat   = '0;
    s_scan_lane   = '0;
    for (int scan_index = 0; scan_index < 64; scan_index++) begin
      if ((scan_index >= s_cursor_q) && (scan_index < s_scan_limit)) begin
        if (s_coalesce_q) begin
          s_scan_beat = 4'(scan_index >> s_size_q);
          s_scan_lane = 2'((s_start_addr_q + 32'(scan_index)) & 32'd3);
        end else begin
          s_scan_beat = s_beat_q[3:0];
          s_scan_lane = 2'((s_addr_q + 32'(scan_index)) & 32'd3);
        end
        s_scan_active = s_write_buffer_q[s_scan_beat][6'd32+{4'd0, s_scan_lane}];
        if (!s_scan_found && s_scan_active && !s_scan_closed) begin
          s_scan_found = 1'b1;
          s_scan_start = 7'(scan_index);
          s_scan_len   = 7'd1;
        end else if (s_scan_found && s_scan_active && !s_scan_closed) begin
          s_scan_len = s_scan_len + 1'b1;
        end else if (s_scan_found && !s_scan_active) begin
          s_scan_closed = 1'b1;
        end
      end
    end
  end

  always_comb begin
    if (s_coalesce_q) begin
      s_tx_beat = 4'({25'd0, s_cursor_q} >> s_size_q);
      s_tx_lane = 2'((s_start_addr_q + {25'd0, s_cursor_q}) & 32'd3);
    end else begin
      s_tx_beat = s_beat_q[3:0];
      s_tx_lane = 2'((s_addr_q + {25'd0, s_cursor_q}) & 32'd3);
    end
  end

  always_comb begin
    s_write_lane_mask = (4'd1 << s_size_q) - 1'b1;
    s_read_lane       = {1'b0, s_addr_q[1:0]} + s_byte_idx_q;
  end

  for (genvar write_index = 0; write_index < 16; write_index++) begin : write_buffer_block
    assign s_write_buffer_en[write_index] = (s_state_q == WriteCollect) &&
                                             axi4.wvalid && axi4.wready &&
                                             (s_beat_q == 8'(write_index));
    assign s_write_buffer_d[write_index] = {axi4.wstrb, axi4.wdata};
    dffer #(
        .DATA_WIDTH(36)
    ) u_write_buffer_dffer (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .en_i   (s_write_buffer_en[write_index]),
        .dat_i  (s_write_buffer_d[write_index]),
        .dat_o  (s_write_buffer_q[write_index])
    );
  end

  always_comb begin
    s_state_d               = s_state_q;
    s_addr_d                = s_addr_q;
    s_start_addr_d          = s_start_addr_q;
    s_len_d                 = s_len_q;
    s_beat_d                = s_beat_q;
    s_size_d                = s_size_q;
    s_burst_d               = s_burst_q;
    s_id_d                  = s_id_q;
    s_slot_d                = s_slot_q;
    s_resp_d                = s_resp_q;
    s_rdata_d               = s_rdata_q;
    s_rvalid_d              = s_rvalid_q;
    s_byte_idx_d            = s_byte_idx_q;
    s_cursor_d              = s_cursor_q;
    s_run_end_d             = s_run_end_q;
    s_coalesce_d            = s_coalesce_q;
    s_frame_done_d          = s_frame_done_q;
    s_transaction_err_d     = s_transaction_err_q;
    s_cmd_count_d           = s_cmd_count_q;
    s_err_code_d            = s_err_code_q;
    s_err_addr_d            = s_err_addr_q;
    s_err_slot_d            = s_err_slot_q;
    s_err_pc_d              = s_err_pc_q;
    axi_error_event_o       = 1'b0;
    perf_read_byte_event_o  = 1'b0;
    perf_write_byte_event_o = 1'b0;
    perf_command_event_o    = 1'b0;
    perf_split_event_o      = 1'b0;

    unique case (s_state_q)
      Idle: begin
        s_beat_d            = '0;
        s_resp_d            = `AXI4_RESP_OKAY;
        s_rdata_d           = '0;
        s_rvalid_d          = 1'b0;
        s_byte_idx_d        = '0;
        s_cursor_d          = '0;
        s_frame_done_d      = 1'b0;
        s_transaction_err_d = 1'b0;
        s_cmd_count_d       = '0;
        if (axi4.arvalid && axi4.arready) begin
          s_addr_d       = axi4.araddr;
          s_start_addr_d = axi4.araddr;
          s_len_d        = axi4.arlen;
          s_size_d       = axi4.arsize;
          s_burst_d      = axi4.arburst;
          s_id_d         = axi4.arid;
          s_slot_d       = s_incoming_read_slot;
          s_coalesce_d   = (axi4.arburst == `AXI4_BURST_TYPE_INCR) && s_read_boundary_ok;
          if (s_legal_read) begin
            s_state_d = ReadRequest;
          end else begin
            s_resp_d          = `AXI4_RESP_SLAVE_ERROR;
            s_err_code_d      = XpiErrorRange;
            s_err_addr_d      = axi4.araddr;
            s_err_slot_d      = s_incoming_read_slot;
            axi_error_event_o = 1'b1;
            s_state_d         = ReadErrorResponse;
          end
        end else if (axi4.awvalid && axi4.awready) begin
          s_addr_d       = axi4.awaddr;
          s_start_addr_d = axi4.awaddr;
          s_len_d        = axi4.awlen;
          s_size_d       = axi4.awsize;
          s_burst_d      = axi4.awburst;
          s_id_d         = axi4.awid;
          s_slot_d       = s_incoming_write_slot;
          s_coalesce_d   = (axi4.awburst == `AXI4_BURST_TYPE_INCR) && s_write_boundary_ok;
          if (s_legal_write) begin
            s_state_d = WriteCollect;
          end else begin
            s_resp_d          = `AXI4_RESP_SLAVE_ERROR;
            s_err_code_d      = XpiErrorRange;
            s_err_addr_d      = axi4.awaddr;
            s_err_slot_d      = s_incoming_write_slot;
            axi_error_event_o = 1'b1;
            s_state_d         = WriteDrain;
          end
        end
      end

      ReadRequest: begin
        if (core_req_valid_o && core_req_ready_i) begin
          s_frame_done_d       = 1'b0;
          s_cmd_count_d        = s_cmd_count_q + 1'b1;
          perf_command_event_o = 1'b1;
          if (s_cmd_count_q != 2'd0) perf_split_event_o = 1'b1;
          s_state_d = ReadData;
        end
      end

      ReadData: begin
        if (core_rx_valid_i && core_rx_ready_o) begin
          s_rdata_d[(s_read_lane*8)+:8] = core_rx_data_i;
          perf_read_byte_event_o        = 1'b1;
          if (s_byte_idx_q == ((3'd1 << s_size_q) - 1'b1)) begin
            s_byte_idx_d = '0;
            s_rvalid_d   = 1'b1;
          end else begin
            s_byte_idx_d = s_byte_idx_q + 1'b1;
          end
        end
        if (core_done_i) begin
          s_frame_done_d = 1'b1;
          if (core_error_i) begin
            s_resp_d            = `AXI4_RESP_SLAVE_ERROR;
            s_transaction_err_d = 1'b1;
            s_err_code_d        = core_error_code_i;
            s_err_addr_d        = s_addr_q;
            s_err_slot_d        = s_slot_q;
            s_err_pc_d          = core_error_pc_i;
            axi_error_event_o   = 1'b1;
            if (!s_rvalid_q) begin
              s_rdata_d  = '0;
              s_rvalid_d = 1'b1;
            end
          end
        end
        if (s_rvalid_q && axi4.rready) begin
          s_rvalid_d = 1'b0;
          s_rdata_d  = '0;
          if (s_beat_q == s_len_q) begin
            s_state_d = (s_frame_done_q || core_done_i) ? Idle : ReadFinish;
          end else begin
            s_addr_d = s_next_addr;
            s_beat_d = s_beat_q + 1'b1;
            if (s_transaction_err_q || core_error_i) begin
              s_state_d = ReadErrorResponse;
            end else if (s_coalesce_q) begin
              s_state_d = ReadData;
            end else begin
              s_state_d = (s_frame_done_q || core_done_i) ? ReadRequest : ReadFrameWait;
            end
          end
        end
      end

      ReadFrameWait: begin
        if (core_done_i) begin
          if (core_error_i) begin
            s_resp_d          = `AXI4_RESP_SLAVE_ERROR;
            s_err_code_d      = core_error_code_i;
            s_err_addr_d      = s_addr_q;
            s_err_slot_d      = s_slot_q;
            s_err_pc_d        = core_error_pc_i;
            axi_error_event_o = 1'b1;
            s_state_d         = ReadErrorResponse;
          end else begin
            s_state_d = ReadRequest;
          end
        end
      end

      ReadFinish: begin
        if (core_done_i) begin
          if (core_error_i) begin
            s_err_code_d      = core_error_code_i;
            s_err_addr_d      = s_addr_q;
            s_err_slot_d      = s_slot_q;
            s_err_pc_d        = core_error_pc_i;
            axi_error_event_o = 1'b1;
          end
          s_state_d = Idle;
        end
      end

      ReadErrorResponse: begin
        s_rdata_d  = '0;
        s_rvalid_d = 1'b0;
        if (axi4.rvalid && axi4.rready) begin
          if (s_beat_q == s_len_q) begin
            s_state_d = Idle;
          end else begin
            s_beat_d = s_beat_q + 1'b1;
          end
        end
      end

      WriteCollect: begin
        if (axi4.wvalid && axi4.wready) begin
          if ((axi4.wlast != (s_beat_q == s_len_q)) ||
              (|(axi4.wstrb & ~(s_write_lane_mask << s_addr_q[1:0])))) begin
            s_resp_d          = `AXI4_RESP_SLAVE_ERROR;
            s_err_code_d      = XpiErrorIllegal;
            s_err_addr_d      = s_addr_q;
            s_err_slot_d      = s_slot_q;
            axi_error_event_o = 1'b1;
            s_state_d         = axi4.wlast ? WriteResponse : WriteDrain;
          end else if (s_beat_q == s_len_q) begin
            s_beat_d   = '0;
            s_cursor_d = '0;
            s_state_d  = WriteScan;
          end else begin
            s_beat_d = s_beat_q + 1'b1;
          end
        end
      end

      WriteScan: begin
        if (s_scan_found) begin
          s_cursor_d  = s_scan_start;
          s_run_end_d = s_scan_start + s_scan_len;
          s_state_d   = WriteRequest;
        end else if (!s_coalesce_q && (s_beat_q != s_len_q)) begin
          s_addr_d   = s_next_addr;
          s_beat_d   = s_beat_q + 1'b1;
          s_cursor_d = '0;
        end else begin
          s_state_d = WriteResponse;
        end
      end

      WriteRequest: begin
        if (core_req_valid_o && core_req_ready_i) begin
          s_cmd_count_d        = s_cmd_count_q + 1'b1;
          perf_command_event_o = 1'b1;
          if (s_cmd_count_q != 2'd0) perf_split_event_o = 1'b1;
          s_state_d = WriteStream;
        end
      end

      WriteStream: begin
        if (core_tx_valid_o && core_tx_ready_i) begin
          perf_write_byte_event_o = 1'b1;
          s_cursor_d              = s_cursor_q + 1'b1;
          if ((s_cursor_q + 1'b1) >= s_run_end_q) begin
            s_state_d = WriteWait;
          end
        end
      end

      WriteWait: begin
        if (core_done_i) begin
          if (core_error_i) begin
            s_resp_d          = `AXI4_RESP_SLAVE_ERROR;
            s_err_code_d      = core_error_code_i;
            s_err_addr_d      = s_addr_q;
            s_err_slot_d      = s_slot_q;
            s_err_pc_d        = core_error_pc_i;
            axi_error_event_o = 1'b1;
            s_state_d         = WriteResponse;
          end else begin
            s_state_d = WriteScan;
          end
        end
      end

      WriteDrain: begin
        if (axi4.wvalid && axi4.wready && axi4.wlast) begin
          s_state_d = WriteResponse;
        end
      end

      WriteResponse: begin
        if (axi4.bvalid && axi4.bready) begin
          s_state_d = Idle;
        end
      end

      default: s_state_d = Idle;
    endcase
  end

  axi4_addr_gen #(
      .ADDR_WIDTH(32)
  ) u_addr_gen (
      .alen_i  (s_len_q),
      .asize_i (s_size_q),
      .aburst_i(s_burst_q),
      .addr_i  (s_addr_q),
      .addr_o  (s_next_addr)
  );

  dffrc #(
      .DATA_WIDTH(4),
      .RESET_VAL (Idle)
  ) u_state_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_addr_d),
      .dat_o  (s_addr_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_start_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_start_addr_d),
      .dat_o  (s_start_addr_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_len_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_len_d),
      .dat_o  (s_len_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_beat_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_beat_d),
      .dat_o  (s_beat_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_size_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_size_d),
      .dat_o  (s_size_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_burst_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_burst_d),
      .dat_o  (s_burst_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_id_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_id_d),
      .dat_o  (s_id_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_slot_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_slot_d),
      .dat_o  (s_slot_q)
  );
  dffrc #(
      .DATA_WIDTH(2),
      .RESET_VAL (`AXI4_RESP_OKAY)
  ) u_resp_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_resp_d),
      .dat_o  (s_resp_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_rdata_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rdata_d),
      .dat_o  (s_rdata_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_rvalid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rvalid_d),
      .dat_o  (s_rvalid_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_byte_idx_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_byte_idx_d),
      .dat_o  (s_byte_idx_q)
  );
  dffr #(
      .DATA_WIDTH(7)
  ) u_cursor_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_cursor_d),
      .dat_o  (s_cursor_q)
  );
  dffr #(
      .DATA_WIDTH(7)
  ) u_run_end_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_run_end_d),
      .dat_o  (s_run_end_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_coalesce_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_coalesce_d),
      .dat_o  (s_coalesce_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_frame_done_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_frame_done_d),
      .dat_o  (s_frame_done_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_transaction_error_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_transaction_err_d),
      .dat_o  (s_transaction_err_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_command_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_cmd_count_d),
      .dat_o  (s_cmd_count_q)
  );
  dffrc #(
      .DATA_WIDTH(4),
      .RESET_VAL (XpiErrorNone)
  ) u_error_code_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_code_d),
      .dat_o  (s_err_code_bits_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_error_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_addr_d),
      .dat_o  (s_err_addr_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_error_slot_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_slot_d),
      .dat_o  (s_err_slot_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_error_pc_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_pc_d),
      .dat_o  (s_err_pc_q)
  );

`ifndef SV_ASSRT_DISABLE
`ifndef SYNTHESIS
  a_xpi_axi_exclusive_accept :
  assert property (@(posedge clk_i) disable iff (!rst_n_i)
      !((axi4.awvalid && axi4.awready) && (axi4.arvalid && axi4.arready)));
  a_xpi_r_stable :
  assert property (@(posedge clk_i) disable iff (!rst_n_i) axi4.rvalid && !axi4.rready |=> $stable(
      {axi4.rvalid, axi4.rdata, axi4.rresp, axi4.rlast}
  ));
  a_xpi_b_stable :
  assert property (@(posedge clk_i) disable iff (!rst_n_i) axi4.bvalid && !axi4.bready |=> $stable(
      {axi4.bvalid, axi4.bresp}
  ));
`endif
`endif

endmodule
