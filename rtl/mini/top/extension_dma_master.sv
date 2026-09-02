// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "axi4_define.svh"

module extension_dma_master (
    // verilog_format: off -- preserve the extension command/status columns
    input  logic          clk_i,
    input  logic          rst_n_i,
    input  logic          start_i,
    input  logic          abort_i,
    input  logic          quiesce_i,
    input  logic [31:0]   src_addr_i,
    input  logic [31:0]   dst_addr_i,
    input  logic [31:0]   len_i,
    input  logic [31:0]   timeout_i,
    output logic          busy_o,
    output logic          done_o,
    output logic          err_o,
    output logic [31:0]   fault_addr_o,
    axi4_if.master        axi4
    // verilog_format: on
);
  typedef enum logic [2:0] {
    Idle,
    ReadAddr,
    ReadData,
    WriteAddr,
    WriteData,
    WriteResp
  } state_e;

  state_e s_state_d, s_state_q;
  logic [31:0] s_src_addr_d, s_src_addr_q;
  logic [31:0] s_dst_addr_d, s_dst_addr_q;
  logic [31:0] s_remaining_d, s_remaining_q;
  logic [63:0] s_data_d, s_data_q;
  logic [31:0] s_timeout_cnt_d, s_timeout_cnt_q;
  logic s_done_d, s_done_q;
  logic s_err_d, s_err_q;
  logic [31:0] s_fault_addr_d, s_fault_addr_q;
  logic [7:0] s_tail_strobe;
  logic       s_progress;

  always_comb begin
    if (s_remaining_q >= 32'd8) begin
      s_tail_strobe = 8'hFF;
    end else begin
      s_tail_strobe = 8'((9'd1 << s_remaining_q[3:0]) - 1'b1);
    end
  end

  assign axi4.awid = 3'd0;
  assign axi4.awaddr = s_dst_addr_q;
  assign axi4.awlen = 8'd0;
  assign axi4.awsize = 3'd3;
  assign axi4.awburst = `AXI4_BURST_TYPE_INCR;
  assign axi4.awlock = 1'b0;
  assign axi4.awcache = 4'd0;
  assign axi4.awprot = 3'd0;
  assign axi4.awqos = 4'd8;
  assign axi4.awregion = 4'd0;
  assign axi4.awuser = 1'b0;
  assign axi4.awvalid = s_state_q == WriteAddr;
  assign axi4.wdata = s_data_q;
  assign axi4.wstrb = s_tail_strobe;
  assign axi4.wlast = 1'b1;
  assign axi4.wuser = 1'b0;
  assign axi4.wvalid = s_state_q == WriteData;
  assign axi4.bready = s_state_q == WriteResp;
  assign axi4.arid = 3'd0;
  assign axi4.araddr = s_src_addr_q;
  assign axi4.arlen = 8'd0;
  assign axi4.arsize = 3'd3;
  assign axi4.arburst = `AXI4_BURST_TYPE_INCR;
  assign axi4.arlock = 1'b0;
  assign axi4.arcache = 4'd0;
  assign axi4.arprot = 3'd0;
  assign axi4.arqos = 4'd8;
  assign axi4.arregion = 4'd0;
  assign axi4.aruser = 1'b0;
  assign axi4.arvalid = s_state_q == ReadAddr;
  assign axi4.rready = s_state_q == ReadData;
  assign busy_o = s_state_q != Idle;
  assign done_o = s_done_q;
  assign err_o = s_err_q;
  assign fault_addr_o = s_fault_addr_q;

  assign s_progress = (axi4.arvalid && axi4.arready) ||
                      (axi4.rvalid && axi4.rready) ||
                      (axi4.awvalid && axi4.awready) ||
                      (axi4.wvalid && axi4.wready) ||
                      (axi4.bvalid && axi4.bready);

  always_comb begin
    s_state_d       = s_state_q;
    s_src_addr_d    = s_src_addr_q;
    s_dst_addr_d    = s_dst_addr_q;
    s_remaining_d   = s_remaining_q;
    s_data_d        = s_data_q;
    s_timeout_cnt_d = s_timeout_cnt_q;
    s_done_d        = 1'b0;
    s_err_d         = 1'b0;
    s_fault_addr_d  = s_fault_addr_q;

    if (s_state_q == Idle) begin
      s_timeout_cnt_d = '0;
      if (start_i && !quiesce_i) begin
        if ((len_i == 32'd0) || (src_addr_i[2:0] != 3'd0) || (dst_addr_i[2:0] != 3'd0)) begin
          s_done_d       = 1'b1;
          s_err_d        = 1'b1;
          s_fault_addr_d = (src_addr_i[2:0] != 3'd0) ? src_addr_i : dst_addr_i;
        end else begin
          s_src_addr_d  = src_addr_i;
          s_dst_addr_d  = dst_addr_i;
          s_remaining_d = len_i;
          s_state_d     = ReadAddr;
        end
      end
    end else if (abort_i) begin
      s_state_d = Idle;
      s_done_d = 1'b1;
      s_err_d = 1'b1;
      s_fault_addr_d = (s_state_q == ReadAddr || s_state_q == ReadData) ?
          s_src_addr_q : s_dst_addr_q;
    end else if (!s_progress && (timeout_i != 32'd0) && (s_timeout_cnt_q == timeout_i - 1'b1)) begin
      s_state_d = Idle;
      s_done_d = 1'b1;
      s_err_d = 1'b1;
      s_fault_addr_d = (s_state_q == ReadAddr || s_state_q == ReadData) ?
          s_src_addr_q : s_dst_addr_q;
      s_timeout_cnt_d = '0;
    end else begin
      s_timeout_cnt_d = s_progress ? 32'd0 : s_timeout_cnt_q + 1'b1;
      unique case (s_state_q)
        ReadAddr:  if (axi4.arvalid && axi4.arready) s_state_d = ReadData;
        ReadData: begin
          if (axi4.rvalid && axi4.rready) begin
            if ((axi4.rresp != `AXI4_RESP_OKAY) || !axi4.rlast) begin
              s_state_d      = Idle;
              s_done_d       = 1'b1;
              s_err_d        = 1'b1;
              s_fault_addr_d = s_src_addr_q;
            end else begin
              s_data_d  = axi4.rdata;
              s_state_d = WriteAddr;
            end
          end
        end
        WriteAddr: if (axi4.awvalid && axi4.awready) s_state_d = WriteData;
        WriteData: if (axi4.wvalid && axi4.wready) s_state_d = WriteResp;
        WriteResp: begin
          if (axi4.bvalid && axi4.bready) begin
            if (axi4.bresp != `AXI4_RESP_OKAY) begin
              s_state_d      = Idle;
              s_done_d       = 1'b1;
              s_err_d        = 1'b1;
              s_fault_addr_d = s_dst_addr_q;
            end else if (s_remaining_q <= 32'd8) begin
              s_state_d = Idle;
              s_done_d  = 1'b1;
            end else begin
              s_src_addr_d  = s_src_addr_q + 32'd8;
              s_dst_addr_d  = s_dst_addr_q + 32'd8;
              s_remaining_d = s_remaining_q - 32'd8;
              s_state_d     = ReadAddr;
            end
          end
        end
        default:   s_state_d = Idle;
      endcase
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q       <= Idle;
      s_src_addr_q    <= '0;
      s_dst_addr_q    <= '0;
      s_remaining_q   <= '0;
      s_data_q        <= '0;
      s_timeout_cnt_q <= '0;
      s_done_q        <= 1'b0;
      s_err_q         <= 1'b0;
      s_fault_addr_q  <= '0;
    end else begin
      s_state_q       <= s_state_d;
      s_src_addr_q    <= s_src_addr_d;
      s_dst_addr_q    <= s_dst_addr_d;
      s_remaining_q   <= s_remaining_d;
      s_data_q        <= s_data_d;
      s_timeout_cnt_q <= s_timeout_cnt_d;
      s_done_q        <= s_done_d;
      s_err_q         <= s_err_d;
      s_fault_addr_q  <= s_fault_addr_d;
    end
  end
endmodule
