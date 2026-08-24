// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "axi4_define.svh"
`include "mmap_define.svh"

module onchip_ram #(
    parameter bit          Present     = 1'b1,
    parameter int unsigned CapacityKiB = 128
) (
    // verilog_format: off -- preserve the AXI, APB, and performance grouping
    input logic          clk_i,
    input logic          rst_n_i,
    input logic          perf_enable_i,
    input logic          perf_clear_i,
    axi4_if.slave        mem_axi4,
    apb4_if.slave        cfg_apb4
    // verilog_format: on
);
  localparam int unsigned NumBanks = CapacityKiB / 4;
  localparam int unsigned BankIndexWidth = (NumBanks > 1) ? $clog2(NumBanks) : 1;
  localparam logic [31:0] MemoryEnd = `SOC_ADDR_SRAM_BASE + 32'(CapacityKiB * 1024) - 1'b1;

  typedef enum logic [2:0] {
    Idle,
    ReadData,
    ReadError,
    WriteData,
    WriteDrain,
    WriteResponse
  } state_e;

  state_e       s_state_d;
  state_e       s_state_q;
  logic   [2:0] s_state_bits_q;
  logic s_id_d, s_id_q;
  logic [7:0] s_len_d, s_len_q;
  logic [7:0] s_beat_d, s_beat_q;
  logic [2:0] s_size_d, s_size_q;
  logic [1:0] s_burst_d, s_burst_q;
  logic [31:0] s_addr_d, s_addr_q;
  logic [1:0] s_write_resp_d, s_write_resp_q;
  logic s_read_pending_d, s_read_pending_q;
  logic [7:0] s_read_rsp_beat_d, s_read_rsp_beat_q;
  logic s_read_rsp_last_d, s_read_rsp_last_q;
  logic [1:0] s_read_rsp_d, s_read_rsp_q;
  logic s_read_issue_valid_d, s_read_issue_valid_q;
  logic [31:0] s_read_issue_addr_d, s_read_issue_addr_q;
  logic [7:0] s_read_issue_beat_d, s_read_issue_beat_q;

  logic [31:0] s_perf_read_requests_d, s_perf_read_requests_q;
  logic [31:0] s_perf_write_requests_d, s_perf_write_requests_q;
  logic [31:0] s_perf_read_beats_d, s_perf_read_beats_q;
  logic [31:0] s_perf_write_beats_d, s_perf_write_beats_q;
  logic [31:0] s_perf_stall_cycles_d, s_perf_stall_cycles_q;
  logic [31:0] s_perf_err_resps_d, s_perf_err_resps_q;

  logic [32:0] s_ar_last_addr;
  logic [32:0] s_aw_last_addr;
  logic [31:0] s_ar_next_addr;
  logic [31:0] s_read_next_addr;
  logic [31:0] s_write_next_addr;
  logic        s_ar_protocol_legal;
  logic        s_aw_protocol_legal;
  logic        s_ar_bounds_legal;
  logic        s_aw_bounds_legal;
  logic [ 1:0] s_ar_response;
  logic [ 1:0] s_aw_response;
  logic        s_ar_accept;
  logic        s_aw_accept;
  logic        s_w_accept;
  logic        s_read_accept;
  logic        s_b_accept;
  logic        s_read_issue;
  logic        s_read_can_issue;
  logic        s_expected_wlast;
  logic [ 3:0] s_write_lane_mask;
  logic        s_write_strobe_legal;
  logic        s_write_beat_legal;
  logic        s_write_terminal;
  logic        s_err_resp_event;
  logic        s_stall_event;

  logic        s_mem_read;
  logic        s_mem_write;
  logic [14:0] s_mem_word_addr;
  logic [31:0] s_mem_wdata;
  logic [ 3:0] s_mem_wstrb;
  logic [31:0] s_mem_rdata;

  function automatic logic wrap_length_legal(input logic [7:0] length_i);
    return (length_i == 8'd1) || (length_i == 8'd3) || (length_i == 8'd7) || (length_i == 8'd15);
  endfunction

  function automatic logic [32:0] burst_last_addr(
      input logic [31:0] addr_i, input logic [7:0] length_i, input logic [2:0] size_i,
      input logic [1:0] burst_i);
    logic [32:0] beat_bytes;
    logic [32:0] burst_bytes;
    logic [32:0] wrap_base;
    begin
      beat_bytes  = 33'd1 << size_i;
      burst_bytes = beat_bytes * ({25'd0, length_i} + 1'b1);
      wrap_base   = {1'b0, addr_i} & ~(burst_bytes - 1'b1);
      unique case (burst_i)
        `AXI4_BURST_TYPE_FIXED: burst_last_addr = {1'b0, addr_i} + beat_bytes - 1'b1;
        `AXI4_BURST_TYPE_WRAP:  burst_last_addr = wrap_base + burst_bytes - 1'b1;
        default:                burst_last_addr = {1'b0, addr_i} + burst_bytes - 1'b1;
      endcase
    end
  endfunction

  function automatic logic [3:0] transfer_lane_mask(input logic [2:0] size_i,
                                                    input logic [1:0] address_i);
    unique case (size_i)
      3'd0:    return 4'b0001 << address_i;
      3'd1:    return 4'b0011 << address_i;
      default: return 4'b1111;
    endcase
  endfunction

  function automatic logic [31:0] saturating_increment(input logic [31:0] value_i);
    return (&value_i) ? value_i : value_i + 1'b1;
  endfunction

  assign s_state_q = state_e'(s_state_bits_q);

  assign s_ar_last_addr = burst_last_addr(
      mem_axi4.araddr, mem_axi4.arlen, mem_axi4.arsize, mem_axi4.arburst
  );
  assign s_aw_last_addr = burst_last_addr(
      mem_axi4.awaddr, mem_axi4.awlen, mem_axi4.awsize, mem_axi4.awburst
  );
  assign s_ar_protocol_legal =
      (mem_axi4.arlen <= 8'd15) &&
      ((mem_axi4.arburst == `AXI4_BURST_TYPE_FIXED) ||
       (mem_axi4.arburst == `AXI4_BURST_TYPE_INCR) ||
       ((mem_axi4.arburst == `AXI4_BURST_TYPE_WRAP) && wrap_length_legal(
      mem_axi4.arlen
  ))) && !mem_axi4.arlock && (mem_axi4.arsize <= `AXI4_BURST_SIZE_4BYTES) &&
      ((mem_axi4.araddr & ((32'd1 << mem_axi4.arsize) - 1'b1)) == 32'd0) && !s_ar_last_addr[32] &&
      (mem_axi4.araddr[31:12] == s_ar_last_addr[31:12]);
  assign s_aw_protocol_legal =
      (mem_axi4.awlen <= 8'd15) &&
      ((mem_axi4.awburst == `AXI4_BURST_TYPE_FIXED) ||
       (mem_axi4.awburst == `AXI4_BURST_TYPE_INCR) ||
       ((mem_axi4.awburst == `AXI4_BURST_TYPE_WRAP) && wrap_length_legal(
      mem_axi4.awlen
  ))) && !mem_axi4.awlock && (mem_axi4.awsize <= `AXI4_BURST_SIZE_4BYTES) &&
      ((mem_axi4.awaddr & ((32'd1 << mem_axi4.awsize) - 1'b1)) == 32'd0) && !s_aw_last_addr[32] &&
      (mem_axi4.awaddr[31:12] == s_aw_last_addr[31:12]);
  assign s_ar_bounds_legal = Present && (mem_axi4.araddr >= `SOC_ADDR_SRAM_BASE) &&
                             (s_ar_last_addr[31:0] <= MemoryEnd);
  assign s_aw_bounds_legal = Present && (mem_axi4.awaddr >= `SOC_ADDR_SRAM_BASE) &&
                             (s_aw_last_addr[31:0] <= MemoryEnd);
  assign s_ar_response = !s_ar_protocol_legal ? `AXI4_RESP_SLAVE_ERROR :
                         !s_ar_bounds_legal ? `AXI4_RESP_DECODE_ERROR : `AXI4_RESP_OKAY;
  assign s_aw_response = !s_aw_protocol_legal ? `AXI4_RESP_SLAVE_ERROR :
                         !s_aw_bounds_legal ? `AXI4_RESP_DECODE_ERROR : `AXI4_RESP_OKAY;

  assign mem_axi4.arready = s_state_q == Idle;
  assign mem_axi4.awready = (s_state_q == Idle) && !mem_axi4.arvalid;
  assign mem_axi4.wready = (s_state_q == WriteData) || (s_state_q == WriteDrain);
  assign mem_axi4.rid = s_id_q;
  assign mem_axi4.rdata = (s_read_rsp_q == `AXI4_RESP_OKAY) ? s_mem_rdata : 32'd0;
  assign mem_axi4.rresp = s_read_rsp_q;
  assign mem_axi4.rlast = s_read_rsp_last_q;
  assign mem_axi4.ruser = '0;
  assign mem_axi4.rvalid = s_read_pending_q;
  assign mem_axi4.bid = s_id_q;
  assign mem_axi4.bresp = s_write_resp_q;
  assign mem_axi4.buser = '0;
  assign mem_axi4.bvalid = s_state_q == WriteResponse;

  assign s_ar_accept = mem_axi4.arvalid && mem_axi4.arready;
  assign s_aw_accept = mem_axi4.awvalid && mem_axi4.awready;
  assign s_w_accept = mem_axi4.wvalid && mem_axi4.wready;
  assign s_read_accept = mem_axi4.rvalid && mem_axi4.rready;
  assign s_b_accept = mem_axi4.bvalid && mem_axi4.bready;
  assign s_read_can_issue = !s_read_pending_q || mem_axi4.rready;
  assign s_read_issue = (s_state_q == ReadData) && s_read_issue_valid_q && s_read_can_issue;
  assign s_expected_wlast = s_beat_q == s_len_q;
  assign s_write_lane_mask = transfer_lane_mask(s_size_q, s_addr_q[1:0]);
  assign s_write_strobe_legal = (mem_axi4.wstrb & ~s_write_lane_mask) == 4'd0;
  assign s_write_beat_legal = s_write_strobe_legal && (mem_axi4.wlast == s_expected_wlast);
  assign s_write_terminal = s_expected_wlast || mem_axi4.wlast;

  assign s_mem_read = (s_ar_accept && (s_ar_response == `AXI4_RESP_OKAY)) || s_read_issue;
  assign s_mem_write = (s_state_q == WriteData) && s_w_accept && s_write_beat_legal &&
                       (|mem_axi4.wstrb);
  assign s_mem_word_addr =
      (s_ar_accept && (s_ar_response == `AXI4_RESP_OKAY)) ? mem_axi4.araddr[16:2] :
      s_read_issue ? s_read_issue_addr_q[16:2] : s_addr_q[16:2];
  assign s_mem_wdata = mem_axi4.wdata;
  assign s_mem_wstrb = s_mem_write ? mem_axi4.wstrb : 4'd0;

  assign s_err_resp_event =
      (s_b_accept && (mem_axi4.bresp != `AXI4_RESP_OKAY)) ||
      (s_read_accept && mem_axi4.rlast && (mem_axi4.rresp != `AXI4_RESP_OKAY));
  assign s_stall_event = (mem_axi4.arvalid && !mem_axi4.arready) ||
                         (mem_axi4.awvalid && !mem_axi4.awready) ||
                         (mem_axi4.wvalid && !mem_axi4.wready) ||
                         (mem_axi4.rvalid && !mem_axi4.rready) ||
                         (mem_axi4.bvalid && !mem_axi4.bready);

  axi4_addr_gen #(
      .ADDR_WIDTH(32)
  ) u_ar_addr_gen (
      .alen_i  (mem_axi4.arlen),
      .asize_i (mem_axi4.arsize),
      .aburst_i(mem_axi4.arburst),
      .addr_i  (mem_axi4.araddr),
      .addr_o  (s_ar_next_addr)
  );

  axi4_addr_gen #(
      .ADDR_WIDTH(32)
  ) u_read_addr_gen (
      .alen_i  (s_len_q),
      .asize_i (s_size_q),
      .aburst_i(s_burst_q),
      .addr_i  (s_read_issue_addr_q),
      .addr_o  (s_read_next_addr)
  );

  axi4_addr_gen #(
      .ADDR_WIDTH(32)
  ) u_write_addr_gen (
      .alen_i  (s_len_q),
      .asize_i (s_size_q),
      .aburst_i(s_burst_q),
      .addr_i  (s_addr_q),
      .addr_o  (s_write_next_addr)
  );

  always_comb begin
    s_state_d            = s_state_q;
    s_id_d               = s_id_q;
    s_len_d              = s_len_q;
    s_beat_d             = s_beat_q;
    s_size_d             = s_size_q;
    s_burst_d            = s_burst_q;
    s_addr_d             = s_addr_q;
    s_write_resp_d       = s_write_resp_q;
    s_read_pending_d     = s_read_pending_q;
    s_read_rsp_beat_d    = s_read_rsp_beat_q;
    s_read_rsp_last_d    = s_read_rsp_last_q;
    s_read_rsp_d         = s_read_rsp_q;
    s_read_issue_valid_d = s_read_issue_valid_q;
    s_read_issue_addr_d  = s_read_issue_addr_q;
    s_read_issue_beat_d  = s_read_issue_beat_q;

    if (s_read_accept) begin
      s_read_pending_d = 1'b0;
      if (s_read_rsp_last_q) begin
        s_state_d = Idle;
      end
    end

    if (s_ar_accept) begin
      s_state_d            = (s_ar_response == `AXI4_RESP_OKAY) ? ReadData : ReadError;
      s_id_d               = mem_axi4.arid;
      s_len_d              = s_ar_protocol_legal ? mem_axi4.arlen : 8'd0;
      s_size_d             = mem_axi4.arsize;
      s_burst_d            = mem_axi4.arburst;
      s_read_pending_d     = 1'b1;
      s_read_rsp_beat_d    = 8'd0;
      s_read_rsp_last_d    = !s_ar_protocol_legal || (mem_axi4.arlen == 8'd0);
      s_read_rsp_d         = s_ar_response;
      s_read_issue_valid_d = (s_ar_response == `AXI4_RESP_OKAY) && (mem_axi4.arlen != 8'd0);
      s_read_issue_addr_d  = s_ar_next_addr;
      s_read_issue_beat_d  = 8'd1;
    end else if (s_aw_accept) begin
      s_state_d      = (s_aw_response == `AXI4_RESP_OKAY) ? WriteData : WriteDrain;
      s_id_d         = mem_axi4.awid;
      s_len_d        = s_aw_protocol_legal ? mem_axi4.awlen : 8'd0;
      s_beat_d       = 8'd0;
      s_size_d       = mem_axi4.awsize;
      s_burst_d      = mem_axi4.awburst;
      s_addr_d       = mem_axi4.awaddr;
      s_write_resp_d = s_aw_response;
    end

    if (s_read_issue) begin
      s_read_pending_d  = 1'b1;
      s_read_rsp_beat_d = s_read_issue_beat_q;
      s_read_rsp_last_d = s_read_issue_beat_q == s_len_q;
      s_read_rsp_d      = `AXI4_RESP_OKAY;
      if (s_read_issue_beat_q == s_len_q) begin
        s_read_issue_valid_d = 1'b0;
      end else begin
        s_read_issue_addr_d = s_read_next_addr;
        s_read_issue_beat_d = s_read_issue_beat_q + 1'b1;
      end
    end

    if ((s_state_q == ReadError) && s_read_accept && !s_read_rsp_last_q) begin
      s_read_pending_d  = 1'b1;
      s_read_rsp_beat_d = s_read_rsp_beat_q + 1'b1;
      s_read_rsp_last_d = (s_read_rsp_beat_q + 1'b1) == s_len_q;
    end

    if (s_w_accept) begin
      if ((s_state_q == WriteData) && !s_write_beat_legal) begin
        s_write_resp_d = `AXI4_RESP_SLAVE_ERROR;
      end
      if (s_write_terminal) begin
        s_state_d = WriteResponse;
      end else begin
        s_beat_d = s_beat_q + 1'b1;
        s_addr_d = s_write_next_addr;
      end
    end

    if (s_b_accept) begin
      s_state_d = Idle;
    end
  end

  always_comb begin
    s_perf_read_requests_d  = s_perf_read_requests_q;
    s_perf_write_requests_d = s_perf_write_requests_q;
    s_perf_read_beats_d     = s_perf_read_beats_q;
    s_perf_write_beats_d    = s_perf_write_beats_q;
    s_perf_stall_cycles_d   = s_perf_stall_cycles_q;
    s_perf_err_resps_d      = s_perf_err_resps_q;
    if (perf_clear_i) begin
      s_perf_read_requests_d  = '0;
      s_perf_write_requests_d = '0;
      s_perf_read_beats_d     = '0;
      s_perf_write_beats_d    = '0;
      s_perf_stall_cycles_d   = '0;
      s_perf_err_resps_d      = '0;
    end else if (perf_enable_i) begin
      if (s_ar_accept) begin
        s_perf_read_requests_d = saturating_increment(s_perf_read_requests_q);
      end
      if (s_aw_accept) begin
        s_perf_write_requests_d = saturating_increment(s_perf_write_requests_q);
      end
      if (s_read_accept) begin
        s_perf_read_beats_d = saturating_increment(s_perf_read_beats_q);
      end
      if (s_w_accept) begin
        s_perf_write_beats_d = saturating_increment(s_perf_write_beats_q);
      end
      if (s_stall_event) begin
        s_perf_stall_cycles_d = saturating_increment(s_perf_stall_cycles_q);
      end
      if (s_err_resp_event) begin
        s_perf_err_resps_d = saturating_increment(s_perf_err_resps_q);
      end
    end
  end

  if (Present) begin : gen_memory
    logic [      NumBanks-1:0] s_bank_cs;
    logic [              31:0] s_bank_rdata  [NumBanks];
    logic [BankIndexWidth-1:0] s_read_bank_q;

    for (genvar bank = 0; bank < NumBanks; bank++) begin : gen_bank
      assign s_bank_cs[bank] = (s_mem_read || s_mem_write) && (s_mem_word_addr[14:10] == 5'(bank));
      tc_sram_1024x32 u_ram (
          .clk_i (clk_i),
          .cs_i  (s_bank_cs[bank]),
          .addr_i(s_mem_word_addr[9:0]),
          .data_i(s_mem_wdata),
          .mask_i(s_mem_wstrb),
          .wren_i(s_mem_write),
          .data_o(s_bank_rdata[bank])
      );
    end

    dffer #(
        .DATA_WIDTH(BankIndexWidth)
    ) u_read_bank_dffer (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .en_i   (s_mem_read),
        .dat_i  (s_mem_word_addr[BankIndexWidth+9:10]),
        .dat_o  (s_read_bank_q)
    );

    assign s_mem_rdata = s_bank_rdata[s_read_bank_q];

`ifdef HAVE_SVA
    assert property (@(posedge clk_i) disable iff (!rst_n_i) $onehot0(s_bank_cs));
`endif
  end else begin : gen_no_memory
    assign s_mem_rdata = {32{1'b0 & ^{s_mem_read, s_mem_write, s_mem_word_addr,
                                      s_mem_wdata, s_mem_wstrb}}};
  end

  onchip_ram_reg #(
      .Present    (Present),
      .CapacityKiB(CapacityKiB)
  ) u_reg (
      .clk_i                 (clk_i),
      .rst_n_i               (rst_n_i),
      .apb4                  (cfg_apb4),
      .perf_read_requests_i  (s_perf_read_requests_q),
      .perf_write_requests_i (s_perf_write_requests_q),
      .perf_read_beats_i     (s_perf_read_beats_q),
      .perf_write_beats_i    (s_perf_write_beats_q),
      .perf_stall_cycles_i   (s_perf_stall_cycles_q),
      .perf_error_responses_i(s_perf_err_resps_q)
  );

  dffr #(
      .DATA_WIDTH(3)
  ) u_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
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
      .DATA_WIDTH(32)
  ) u_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_addr_d),
      .dat_o  (s_addr_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_write_resp_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_resp_d),
      .dat_o  (s_write_resp_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_read_pending_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_pending_d),
      .dat_o  (s_read_pending_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_read_rsp_beat_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_rsp_beat_d),
      .dat_o  (s_read_rsp_beat_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_read_rsp_last_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_rsp_last_d),
      .dat_o  (s_read_rsp_last_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_read_rsp_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_rsp_d),
      .dat_o  (s_read_rsp_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_read_issue_valid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_issue_valid_d),
      .dat_o  (s_read_issue_valid_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_read_issue_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_issue_addr_d),
      .dat_o  (s_read_issue_addr_q)
  );
  dffr #(
      .DATA_WIDTH(8)
  ) u_read_issue_beat_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_issue_beat_d),
      .dat_o  (s_read_issue_beat_q)
  );

  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_read_requests_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_read_requests_d),
      .dat_o  (s_perf_read_requests_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_write_requests_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_write_requests_d),
      .dat_o  (s_perf_write_requests_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_read_beats_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_read_beats_d),
      .dat_o  (s_perf_read_beats_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_write_beats_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_write_beats_d),
      .dat_o  (s_perf_write_beats_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_stall_cycles_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_stall_cycles_d),
      .dat_o  (s_perf_stall_cycles_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_perf_err_resps_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_perf_err_resps_d),
      .dat_o  (s_perf_err_resps_q)
  );

`ifdef HAVE_SVA
  assert property (@(posedge clk_i) disable iff (!rst_n_i)
      mem_axi4.rvalid && !mem_axi4.rready |=>
      $stable(
      {mem_axi4.rid, mem_axi4.rdata, mem_axi4.rresp, mem_axi4.rlast}
  ));
  assert property (@(posedge clk_i) disable iff (!rst_n_i)
      mem_axi4.bvalid && !mem_axi4.bready |=>
      $stable(
      {mem_axi4.bid, mem_axi4.bresp}
  ));
  assert property (@(posedge clk_i) disable iff (!rst_n_i) !(s_mem_read && s_mem_write));
`endif

`ifndef SYNTHESIS
  initial begin
    if ((CapacityKiB != 4) && (CapacityKiB != 16) && (CapacityKiB != 32) &&
        (CapacityKiB != 64) && (CapacityKiB != 128)) begin
      $fatal(1, "onchip_ram: CapacityKiB must be 4, 16, 32, 64, or 128");
    end
  end
`endif
endmodule
