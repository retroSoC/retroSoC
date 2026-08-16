/*
 *  mt48lc16m16a2_ctrl - A sdram controller
 *
 *  Copyright (C) 2022  Hirosh Dabui <hirosh@dabui.de>
 *
 *  Permission to use, copy, modify, and/or distribute this software for any
 *  purpose with or without fee is hereby granted, provided that the above
 *  copyright notice and this permission notice appear in all copies.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 *  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 *  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 *  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 *  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 *  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 *  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 */
// -- Adaptable modifications are redistributed under compatible License --
//
// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.


`include "mmap_define.svh"

module sdram_core (
    // verilog_format: off -- preserve reviewed column alignment
    input logic         clk_i,
    input logic         rst_n_i,
    input logic         sdram_clk_i,
    input logic         fir_edge_i,
    input logic         sec_edge_i,
    input  logic        req_valid_i,
    output logic        req_ready_o,
    input  logic [31:0] req_addr_i,
    input  logic [31:0] req_wdata_i,
    input  logic [ 3:0] req_wstrb_i,
    output logic [31:0] req_rdata_o,
    output logic        req_resp_err_o,
    sdram_if.dut        sdram
    // verilog_format: on
);

  // clk_i/rst_n_i control the scheduler; SDRAM commands advance only on the
  // supplied phase edges. The request port accepts one captured request and
  // never reports resp_err; ready is asserted when that response is available.
  localparam int signed ClkFreq = 32'sd36;
  localparam int signed TrpNs = 32'sd20;
  localparam int signed TrcNs = 32'sd66;
  localparam int signed TrcdNs = 32'sd20;
  localparam int signed TchNs = 32'sd2;
  localparam logic [2:0] Cas = 3'd2;

  // ClkFreq * 1/CLK_FREQe6s = 1us
  localparam int signed OneOverMicrosecond = ClkFreq;
  localparam int signed Wait100Us = 32'sd100 * OneOverMicrosecond;
  // Command period: PRE to ACT in ns, e.g. 20 ns.
  localparam int signed Trp = (TrpNs * OneOverMicrosecond / 32'sd1000) + 32'sd1;
  // tRC command period (REF to REF/ACT to ACT) in ns.
  localparam int signed Trc = (TrcNs * OneOverMicrosecond / 32'sd1000) + 32'sd1;
  // tRCD active-command to read/write-command delay in ns.
  localparam int signed Trcd = (TrcdNs * OneOverMicrosecond / 32'sd1000) + 32'sd1;
  // tCH command hold time.
  localparam int signed Tch = (TchNs * OneOverMicrosecond / 32'sd1000) + 32'sd1;
  // 000: 1-burst, 001: 2-burst
  // 010: 4-burst, 011: 8-burst
  localparam logic [2:0] BurstLength = 3'b001;
  // 0: sequential, 1: interleaved
  localparam logic AccessType = 1'b0;
  // 2/3 allowed, tRCD=20 ns -> 3 cycles@128 MHz
  localparam logic [2:0] CasLatency = Cas;
  // Only 00 (standard operation) is allowed.
  localparam logic [1:0] OpMode = 2'b00;
  // 0: write burst enabled, 1: only single-access write.
  localparam logic NoWriteBurst = 1'b0;
  // (CS, RAS, Cas, WE)
  // mode register set
  localparam logic [3:0] CmdMrs = 4'b0000;
  // Bank active.
  localparam logic [3:0] CmdAct = 4'b0011;
  // Read variant with auto-precharge set A10=H.
  localparam logic [3:0] CmdRead = 4'b0101;
  // A10=H selects auto-precharge.
  localparam logic [3:0] CmdWrite = 4'b0100;
  // Burst stop.
  localparam logic [3:0] CmdBst = 4'b0110;
  // Precharge selected bank; A10=H selects both banks.
  localparam logic [3:0] CmdPrer = 4'b0010;
  // Auto refresh (cke=H); self refresh assigns cke=L.
  localparam logic [3:0] CmdRfsh = 4'b0001;
  localparam logic [3:0] CmdNop = 4'b0111;
  // SDRAM mode; this implementation does not configure it dynamically.
  localparam logic [12:0] SdramMode = {
    3'b0, NoWriteBurst, OpMode, CasLatency, AccessType, BurstLength
  };

  typedef enum logic [3:0] {
    Reset               = 4'd0,
    AssertCke           = 4'd1,
    InitSeqPreChargeAll = 4'd2,
    InitSeqAutoRefresh0 = 4'd3,
    InitSeqAutoRefresh1 = 4'd4,
    InitSeqLoadMode     = 4'd5,
    Idle                = 4'd6,
    ColRead             = 4'd7,
    ColReadLow          = 4'd8,
    ColReadHigh         = 4'd9,
    ColWriteLow         = 4'd10,
    ColWriteHigh        = 4'd11,
    AutoRefresh         = 4'd12,
    PreChargeAll        = 4'd13,
    WaitState           = 4'd14,
    LastState           = 4'd15
  } sdram_state_e;


`ifndef SYNTHESIS
  initial begin
    $display("Clk frequence: %6d MHz", ClkFreq);
    $display("Wait100Us:    %6d cycles", Wait100Us);
    $display("Trp:           %6d cycles", Trp);
    $display("Trc:           %6d cycles", Trc);
    $display("Trcd:          %6d cycles", Trcd);
    $display("Tch:           %6d cycles", Tch);
    $display("CasLatency:   %6d cycles", CasLatency);
  end
`endif

  sdram_state_e s_state_d, s_state_q;
  sdram_state_e s_ret_state_d, s_ret_state_q;
  logic [15:0] s_wait_cnt_d, s_wait_cnt_q;
  logic [3:0] s_cmd_d, s_cmd_q;
  logic s_ready_d, s_ready_q;
  logic [31:0] s_rdata_d, s_rdata_q;
  // sdram
  logic [1:0] s_dqm_d, s_dqm_q;
  logic [15:0] s_dq_d, s_dq_q;
  logic [1:0] s_ba_q, s_ba_d;
  logic s_oe_q, s_oe_d;
  logic s_cke_q, s_cke_d;
  logic [12:0] s_addr_d, s_addr_q;
  logic s_upd_ready_d, s_upd_ready_q;
  // Registered RIB inputs (captured at Idle-to-ACT)
  logic [31:0] s_apb4_addr_d, s_apb4_addr_q;
  logic [25:0] s_mem_addr;
  logic [31:0] s_req_addr_rel;
  logic [31:0] s_apb4_wdata_d, s_apb4_wdata_q;
  logic [3:0] s_apb4_wstrb_d, s_apb4_wstrb_q;


  // apb4
  assign req_ready_o = s_ready_q;
  assign req_resp_err_o = 1'b0;
  assign req_rdata_o = s_rdata_q;
  // sdram
  assign sdram.clk_o = sdram_clk_i;
  assign sdram.cke_o = s_cke_q;
  assign sdram.addr_o = s_addr_q;
  assign sdram.dqm_o = s_dqm_q;
  assign {sdram.cs_n_o, sdram.ras_n_o, sdram.cas_n_o, sdram.we_n_o} = s_cmd_q;
  assign sdram.ba_o = s_ba_q;
  assign sdram.dq_o = s_dq_q;
  assign sdram.oe_o = s_oe_q;
  assign s_mem_addr = s_apb4_addr_q - `SOC_ADDR_SDRAM_BASE;
  assign s_req_addr_rel = req_addr_i - `SOC_ADDR_SDRAM_BASE;



  always_comb begin
    s_state_d      = s_state_q;
    s_ret_state_d  = s_ret_state_q;
    s_wait_cnt_d   = s_wait_cnt_q;
    s_cmd_d        = s_cmd_q;
    s_ready_d      = s_ready_q;
    s_rdata_d      = s_rdata_q;
    // sdram
    s_dqm_d        = s_dqm_q;
    s_dq_d         = s_dq_q;
    s_ba_d         = s_ba_q;
    s_oe_d         = s_oe_q;
    s_cke_d        = s_cke_q;
    s_addr_d       = s_addr_q;
    s_upd_ready_d  = s_upd_ready_q;
    s_apb4_addr_d  = s_apb4_addr_q;
    s_apb4_wdata_d = s_apb4_wdata_q;
    s_apb4_wstrb_d = s_apb4_wstrb_q;
    case (s_state_q)
      Reset: begin
        s_cke_d       = 1'b0;
        s_state_d     = WaitState;
        s_ret_state_d = AssertCke;
        s_wait_cnt_d  = 16'(Wait100Us);
      end
      AssertCke: begin
        s_cke_d       = 1'b1;
        s_state_d     = WaitState;
        s_ret_state_d = InitSeqPreChargeAll;
        s_wait_cnt_d  = 16'd2;
      end
      InitSeqPreChargeAll: begin
        s_cke_d       = 1'b1;
        s_cmd_d       = CmdPrer;
        s_addr_d[10]  = 1'b1;
        s_state_d     = WaitState;
        s_ret_state_d = InitSeqAutoRefresh0;
        s_wait_cnt_d  = 16'(Trp);
      end
      InitSeqAutoRefresh0: begin
        s_cmd_d       = CmdRfsh;
        s_state_d     = WaitState;
        s_ret_state_d = InitSeqAutoRefresh1;
        s_wait_cnt_d  = 16'(Trc);
      end
      InitSeqAutoRefresh1: begin
        s_cmd_d       = CmdRfsh;
        s_state_d     = WaitState;
        s_ret_state_d = InitSeqLoadMode;
        s_wait_cnt_d  = 16'(Trc);
      end
      InitSeqLoadMode: begin
        s_cmd_d       = CmdMrs;
        s_addr_d      = SdramMode;
        s_state_d     = WaitState;
        s_ret_state_d = Idle;
        s_wait_cnt_d  = 16'(Tch);
      end
      Idle: begin
        s_oe_d    = 1'b0;
        s_dqm_d   = 2'b11;
        s_ready_d = 1'b0;
        if (req_valid_i && !s_ready_q) begin
          // Capture RIB inputs into holding registers
          s_apb4_addr_d  = req_addr_i;
          s_apb4_wdata_d = req_wdata_i;
          s_apb4_wstrb_d = req_wstrb_i;
          s_cmd_d        = CmdAct;
          s_ba_d         = s_req_addr_rel[25:24];
          s_addr_d       = s_req_addr_rel[23:11];
          s_state_d      = WaitState;
          s_ret_state_d  = |req_wstrb_i ? ColWriteLow : ColRead;
          s_wait_cnt_d   = 16'(Trcd);
          s_upd_ready_d  = 1'b1;
        end else begin
          // autorefresh
          s_cmd_d       = CmdRfsh;
          s_addr_d      = '0;
          s_ba_d        = '0;
          // Trc
          s_state_d     = WaitState;
          s_ret_state_d = Idle;
          s_wait_cnt_d  = 16'(Trc);
          s_upd_ready_d = 1'b0;
        end
      end
      ColRead: begin
        s_cmd_d       = CmdRead;
        s_dqm_d       = 2'b00;
        // autoprecharge and column (use registered addr)
        s_ba_d        = s_mem_addr[25:24];
        s_addr_d      = {3'b001, s_mem_addr[10:2], 1'b0};
        // $display("rd col addr: %0x", s_addr_d);
        s_state_d     = WaitState;
        s_ret_state_d = ColReadLow;
        s_wait_cnt_d  = 16'(CasLatency);
      end
      ColReadLow: begin
        s_cmd_d         = CmdNop;
        s_dqm_d         = 2'b00;
        s_rdata_d[15:0] = sdram.dq_i;
        s_state_d       = ColReadHigh;
      end
      ColReadHigh: begin
        s_cmd_d          = CmdNop;
        s_dqm_d          = 2'b00;
        s_rdata_d[31:16] = sdram.dq_i;
        s_state_d        = WaitState;
        s_ret_state_d    = Idle;
        s_wait_cnt_d     = 16'(Trp);
      end
      ColWriteLow: begin
        s_cmd_d   = CmdWrite;
        s_dqm_d   = ~s_apb4_wstrb_q[1:0];
        // autoprecharge and column (use registered addr)
        s_ba_d    = s_mem_addr[25:24];
        s_addr_d  = {3'b001, s_mem_addr[10:2], 1'b0};
        s_dq_d    = s_apb4_wdata_q[15:0];
        s_oe_d    = 1'b1;
        s_state_d = ColWriteHigh;
      end
      ColWriteHigh: begin
        s_cmd_d       = CmdNop;
        s_dqm_d       = ~s_apb4_wstrb_q[3:2];
        // autoprecharge and column (use registered wdata)
        s_dq_d        = s_apb4_wdata_q[31:16];
        s_oe_d        = 1'b1;
        s_state_d     = WaitState;
        s_ret_state_d = Idle;
        s_wait_cnt_d  = 16'(Trp);
      end
      // NOTE: notused
      // PreChargeAll: begin
      //   s_cmd_d     = CmdPrer;
      //   // select all banks
      //   s_addr_d[10]   = 1'b1;
      //   s_ba_d          = 0;
      //   s_state_d       = WaitState;
      //   s_ret_state_d   = Idle;
      //   s_wait_cnt_d = Trp;
      // end
      WaitState: begin
        s_cmd_d      = CmdNop;
        s_wait_cnt_d = s_wait_cnt_q - 1'b1;
        if (s_wait_cnt_q == 16'd1) begin
          s_state_d = s_ret_state_q;
          if (s_ret_state_q == Idle && s_upd_ready_q) begin
            s_upd_ready_d = 1'b0;
            s_ready_d     = 1'b1;
          end
        end
      end
      default: begin
        // Preserve the legacy illegal-state hold rather than adding recovery.
        s_state_d = s_state_q;
      end
    endcase
  end

  // The fir/sec edge-qualified state updates share reset and update priority.
  // Retain this process to preserve the SDRAM cycle schedule exactly.
  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (~rst_n_i) begin
      s_state_q      <= Reset;
      s_ret_state_q  <= Reset;
      s_wait_cnt_q   <= '0;
      s_cmd_q        <= CmdNop;
      s_ready_q      <= '0;
      s_rdata_q      <= '0;
      // sdram
      s_dqm_q        <= '1;
      s_dq_q         <= '0;
      s_ba_q         <= '1;
      s_oe_q         <= '0;
      s_cke_q        <= '0;
      s_addr_q       <= '0;
      s_upd_ready_q  <= '0;
      s_apb4_addr_q  <= '0;
      s_apb4_wdata_q <= '0;
      s_apb4_wstrb_q <= '0;
    end else begin
      s_ready_q <= s_ready_d;
      if (fir_edge_i) begin
        s_rdata_q <= s_rdata_d;
      end
      if (sec_edge_i) begin
        s_state_q      <= s_state_d;
        s_ret_state_q  <= s_ret_state_d;
        s_wait_cnt_q   <= s_wait_cnt_d;
        s_cmd_q        <= s_cmd_d;
        // sdram
        s_dqm_q        <= s_dqm_d;
        s_dq_q         <= s_dq_d;
        s_ba_q         <= s_ba_d;
        s_oe_q         <= s_oe_d;
        s_cke_q        <= s_cke_d;
        s_addr_q       <= s_addr_d;
        s_upd_ready_q  <= s_upd_ready_d;
        s_apb4_addr_q  <= s_apb4_addr_d;
        s_apb4_wdata_q <= s_apb4_wdata_d;
        s_apb4_wstrb_q <= s_apb4_wstrb_d;
      end
    end
  end

endmodule
