// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "axi4_define.svh"

module dma_axi4_master #(
    parameter int AddrWidth     = 32,
    parameter int DataWidth     = 32,
    parameter int MaxBurstBeats = 16
) (
    // verilog_format: off -- AXI command/data ports are aligned with their response groups.
    input  logic                 clk_i,
    input  logic                 rst_n_i,
    input  logic                 read_start_valid_i,
    output logic                 read_start_ready_o,
    input  logic [AddrWidth-1:0] read_addr_i,
    input  logic [          4:0] read_beats_i,
    input  logic                 read_fixed_i,
    output logic                 read_busy_o,
    output logic                 read_beat_valid_o,
    input  logic                 read_beat_ready_i,
    output logic [DataWidth-1:0] read_data_o,
    output logic [          1:0] read_resp_o,
    output logic                 read_last_o,
    output logic                 read_expected_last_o,
    output logic                 read_id_error_o,
    output logic                 read_done_o,
    input  logic                 write_start_valid_i,
    output logic                 write_start_ready_o,
    input  logic [AddrWidth-1:0] write_addr_i,
    input  logic [          4:0] write_beats_i,
    input  logic                 write_fixed_i,
    output logic                 write_busy_o,
    input  logic                 write_data_valid_i,
    output logic                 write_data_ready_o,
    input  logic [DataWidth-1:0] write_data_i,
    input  logic [DataWidth/8-1:0] write_strb_i,
    output logic                 write_done_o,
    output logic [          1:0] write_resp_o,
    output logic                 write_id_error_o,
    axi4_if.master               axi4
    // verilog_format: on
);
  localparam int BeatBytes = DataWidth / 8;
  localparam logic [2:0] AxSize = 3'($clog2(BeatBytes));

  typedef enum logic [1:0] {
    ReadIdle,
    ReadAddress,
    ReadData
  } read_state_e;
  typedef enum logic [1:0] {
    WriteIdle,
    WriteAddress,
    WriteData,
    WriteResponse
  } write_state_e;

  read_state_e                  s_read_state_q;
  write_state_e                 s_write_state_q;
  logic         [AddrWidth-1:0] s_read_addr_q;
  logic         [AddrWidth-1:0] s_write_addr_q;
  logic         [          4:0] s_read_beats_q;
  logic         [          4:0] s_write_beats_q;
  logic         [          4:0] s_read_beat_q;
  logic         [          4:0] s_write_beat_q;
  logic                         s_read_fixed_q;
  logic                         s_write_fixed_q;

`ifndef SYNTHESIS
  initial begin
    if ((AddrWidth < 1) || (DataWidth < 8) || ((DataWidth % 8) != 0) ||
        ((DataWidth & (DataWidth - 1)) != 0) || (MaxBurstBeats < 1) ||
        (MaxBurstBeats > 16)) begin
      $fatal(1, "dma_axi4_master: unsupported AXI geometry");
    end
  end
`endif

  assign read_start_ready_o   = s_read_state_q == ReadIdle;
  assign read_busy_o          = s_read_state_q != ReadIdle;
  assign read_beat_valid_o    = (s_read_state_q == ReadData) && axi4.rvalid;
  assign read_data_o          = axi4.rdata;
  assign read_resp_o          = axi4.rresp;
  assign read_last_o          = axi4.rlast;
  assign read_expected_last_o = (s_read_beat_q + 1'b1) == s_read_beats_q;
  assign read_id_error_o      = axi4.rid != '0;
  assign read_done_o          = read_beat_valid_o && read_beat_ready_i && axi4.rlast;

  assign write_start_ready_o  = s_write_state_q == WriteIdle;
  assign write_busy_o         = s_write_state_q != WriteIdle;
  assign write_data_ready_o   = (s_write_state_q == WriteData) && axi4.wready;
  assign write_done_o         = (s_write_state_q == WriteResponse) && axi4.bvalid;
  assign write_resp_o         = axi4.bresp;
  assign write_id_error_o     = axi4.bid != '0;

  assign axi4.awid            = '0;
  assign axi4.awaddr          = s_write_addr_q;
  assign axi4.awlen           = {3'd0, s_write_beats_q - 1'b1};
  assign axi4.awsize          = AxSize;
  assign axi4.awburst         = s_write_fixed_q ? `AXI4_BURST_TYPE_FIXED : `AXI4_BURST_TYPE_INCR;
  assign axi4.awlock          = `AXI4_LOCK_NORM;
  assign axi4.awcache         = `AXI4_CACHE_NO_BUF;
  assign axi4.awprot          = `AXI4_PROT_DATA;
  assign axi4.awqos           = `AXI4_QOS_NORMAL;
  assign axi4.awregion        = `AXI4_REGION_NORMAL;
  assign axi4.awuser          = '0;
  assign axi4.awvalid         = s_write_state_q == WriteAddress;
  assign axi4.wdata           = write_data_i;
  assign axi4.wstrb           = write_strb_i;
  assign axi4.wlast           = (s_write_beat_q + 1'b1) == s_write_beats_q;
  assign axi4.wuser           = '0;
  assign axi4.wvalid          = (s_write_state_q == WriteData) && write_data_valid_i;
  assign axi4.bready          = s_write_state_q == WriteResponse;

  assign axi4.arid            = '0;
  assign axi4.araddr          = s_read_addr_q;
  assign axi4.arlen           = {3'd0, s_read_beats_q - 1'b1};
  assign axi4.arsize          = AxSize;
  assign axi4.arburst         = s_read_fixed_q ? `AXI4_BURST_TYPE_FIXED : `AXI4_BURST_TYPE_INCR;
  assign axi4.arlock          = `AXI4_LOCK_NORM;
  assign axi4.arcache         = `AXI4_CACHE_NO_BUF;
  assign axi4.arprot          = `AXI4_PROT_DATA;
  assign axi4.arqos           = `AXI4_QOS_NORMAL;
  assign axi4.arregion        = `AXI4_REGION_NORMAL;
  assign axi4.aruser          = '0;
  assign axi4.arvalid         = s_read_state_q == ReadAddress;
  assign axi4.rready          = (s_read_state_q == ReadData) && read_beat_ready_i;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_read_state_q <= ReadIdle;
      s_read_addr_q  <= '0;
      s_read_beats_q <= 5'd1;
      s_read_beat_q  <= '0;
      s_read_fixed_q <= 1'b0;
    end else begin
      unique case (s_read_state_q)
        ReadIdle: begin
          if (read_start_valid_i && read_start_ready_o) begin
            s_read_addr_q  <= read_addr_i;
            s_read_beats_q <= read_beats_i;
            s_read_beat_q  <= '0;
            s_read_fixed_q <= read_fixed_i;
            s_read_state_q <= ReadAddress;
          end
        end
        ReadAddress: begin
          if (axi4.arvalid && axi4.arready) begin
            s_read_state_q <= ReadData;
          end
        end
        ReadData: begin
          if (read_beat_valid_o && read_beat_ready_i) begin
            if (axi4.rlast) begin
              s_read_state_q <= ReadIdle;
            end else begin
              s_read_beat_q <= s_read_beat_q + 1'b1;
            end
          end
        end
        default: s_read_state_q <= ReadIdle;
      endcase
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_write_state_q <= WriteIdle;
      s_write_addr_q  <= '0;
      s_write_beats_q <= 5'd1;
      s_write_beat_q  <= '0;
      s_write_fixed_q <= 1'b0;
    end else begin
      unique case (s_write_state_q)
        WriteIdle: begin
          if (write_start_valid_i && write_start_ready_o) begin
            s_write_addr_q  <= write_addr_i;
            s_write_beats_q <= write_beats_i;
            s_write_beat_q  <= '0;
            s_write_fixed_q <= write_fixed_i;
            s_write_state_q <= WriteAddress;
          end
        end
        WriteAddress: begin
          if (axi4.awvalid && axi4.awready) begin
            s_write_state_q <= WriteData;
          end
        end
        WriteData: begin
          if (axi4.wvalid && axi4.wready) begin
            if (axi4.wlast) begin
              s_write_state_q <= WriteResponse;
            end else begin
              s_write_beat_q <= s_write_beat_q + 1'b1;
            end
          end
        end
        WriteResponse: begin
          if (axi4.bvalid && axi4.bready) begin
            s_write_state_q <= WriteIdle;
          end
        end
        default: s_write_state_q <= WriteIdle;
      endcase
    end
  end
endmodule
