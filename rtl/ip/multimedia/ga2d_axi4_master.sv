// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module ga2d_axi4_master (
    input  logic                 clk_i,
    input  logic                 rst_n_i,
    input  logic                 clear_i,
    input  logic                 read_request_valid_i,
    output logic                 read_request_ready_o,
    input  logic          [31:0] read_address_i,
    input  logic          [ 2:0] read_size_i,
    input  logic          [ 4:0] read_beats_i,
    input  logic                 read_stop_i,
    output logic                 read_request_accept_o,
    output logic                 read_address_presented_o,
    output logic                 read_request_cancel_o,
    output logic                 read_response_valid_o,
    input  logic                 read_response_ready_i,
    output logic          [63:0] read_data_o,
    output logic          [ 1:0] read_response_o,
    output logic                 read_protocol_error_o,
    output logic                 read_response_terminal_o,
    output logic          [31:0] read_response_address_o,
    input  logic                 write_request_valid_i,
    output logic                 write_request_ready_o,
    input  logic          [31:0] write_address_i,
    input  logic          [ 4:0] write_beats_i,
    input  logic                 write_stop_i,
    output logic                 write_request_accept_o,
    output logic                 write_address_presented_o,
    output logic                 write_request_cancel_o,
    input  logic                 write_payload_valid_i,
    input  logic          [63:0] write_data_i,
    input  logic          [ 7:0] write_strobe_i,
    output logic                 write_payload_accept_o,
    output logic                 write_response_valid_o,
    input  logic                 write_response_ready_i,
    output logic          [ 1:0] write_response_o,
    output logic                 write_protocol_error_o,
    output logic          [31:0] write_response_address_o,
    output logic                 read_busy_o,
    output logic                 write_busy_o,
    output logic                 idle_o,
    output logic                 read_stall_o,
    output logic                 write_stall_o,
           axi4_if.master        axi4
);
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

  read_state_e         s_read_state_q;
  write_state_e        s_write_state_q;
  logic         [31:0] s_read_addr_q;
  logic         [ 2:0] s_read_size_q;
  logic         [ 4:0] s_read_beats_q;
  logic         [ 4:0] s_read_beats_left_q;
  logic                s_rd_ar_presented_q;
  logic                s_read_resp_seen_q;
  logic         [31:0] s_write_addr_q;
  logic         [ 4:0] s_write_beats_q;
  logic         [ 4:0] s_write_beats_left_q;
  logic                s_wr_aw_presented_q;
  logic                s_write_resp_seen_q;
  logic                s_read_rsp_accept;
  logic                s_write_rsp_accept;
  logic                s_read_last_expected;
  logic                s_read_rsp_terminal;
  logic                s_read_protocol_fault_q;
  logic                s_write_protocol_fault_q;

  assign read_request_ready_o = (s_read_state_q == ReadIdle) && !clear_i;
  assign write_request_ready_o = (s_write_state_q == WriteIdle) && !clear_i;
  assign read_request_accept_o = read_request_valid_i && read_request_ready_o && !read_stop_i &&
                                 (read_beats_i != 5'd0) && (read_beats_i <= 5'd16);
  assign read_address_presented_o = s_rd_ar_presented_q ||
                                    ((s_read_state_q == ReadAddress) && axi4.arvalid);
  assign read_request_cancel_o = (s_read_state_q == ReadAddress) && read_stop_i &&
                                 !s_rd_ar_presented_q;
  assign write_request_accept_o = write_request_valid_i && write_request_ready_o && !write_stop_i &&
                                  (write_beats_i != 5'd0) && (write_beats_i <= 5'd16);
  assign write_address_presented_o = s_wr_aw_presented_q ||
                                     ((s_write_state_q == WriteAddress) && axi4.awvalid);
  assign write_request_cancel_o = (s_write_state_q == WriteAddress) && write_stop_i &&
                                  !s_wr_aw_presented_q;

  assign read_response_valid_o = (s_read_state_q == ReadData) &&
                                 s_read_resp_seen_q && axi4.rvalid && !clear_i;
  assign read_data_o = axi4.rdata;
  assign read_response_o = axi4.rresp;
  assign s_read_last_expected = s_read_beats_left_q == 5'd1;
  assign read_protocol_error_o = (axi4.rid != '0) || (axi4.rlast != s_read_last_expected);
  // A malformed response cannot safely retire local ID 0: only a matching
  // final beat resolves the owner, and a prior protocol fault requires clear_i.
  assign s_read_rsp_terminal = !s_read_protocol_fault_q && !read_protocol_error_o &&
                               axi4.rlast && s_read_last_expected;
  assign read_response_terminal_o = read_response_valid_o && s_read_rsp_terminal;
  assign read_response_address_o = s_read_addr_q +
                                   ({27'd0, s_read_beats_q - s_read_beats_left_q} <<
                                    s_read_size_q);
  assign s_read_rsp_accept = read_response_valid_o && read_response_ready_i;

  assign write_response_valid_o = (s_write_state_q == WriteResponse) &&
                                  s_write_resp_seen_q && axi4.bvalid && !clear_i;
  assign write_response_o = axi4.bresp;
  assign write_protocol_error_o = axi4.bid != '0;
  assign write_response_address_o = s_write_addr_q;
  assign s_write_rsp_accept = write_response_valid_o && write_response_ready_i;

  assign read_busy_o = s_read_state_q != ReadIdle;
  assign write_busy_o = s_write_state_q != WriteIdle;
  assign idle_o = !read_busy_o && !write_busy_o;
  assign read_stall_o = (axi4.arvalid && !axi4.arready) || (axi4.rvalid && !axi4.rready);
  assign write_stall_o = (axi4.awvalid && !axi4.awready) || (axi4.wvalid && !axi4.wready) ||
                         (axi4.bvalid && !axi4.bready);

  assign axi4.awid = '0;
  assign axi4.awaddr = s_write_addr_q;
  assign axi4.awlen = {3'd0, s_write_beats_q} - 1'b1;
  assign axi4.awsize = 3'd3;
  assign axi4.awburst = 2'b01;
  assign axi4.awlock = 1'b0;
  assign axi4.awcache = 4'd0;
  assign axi4.awprot = 3'd0;
  assign axi4.awqos = 4'd0;
  assign axi4.awregion = 4'd0;
  assign axi4.awuser = '0;
  assign axi4.awvalid = (s_write_state_q == WriteAddress) && !clear_i &&
                        (!write_stop_i || s_wr_aw_presented_q);
  assign axi4.wdata = write_data_i;
  assign axi4.wstrb = write_strobe_i;
  assign axi4.wlast = s_write_beats_left_q == 5'd1;
  assign axi4.wuser = '0;
  assign axi4.wvalid = (s_write_state_q == WriteData) && write_payload_valid_i && !clear_i;
  assign write_payload_accept_o = axi4.wvalid && axi4.wready;
  assign axi4.bready = (s_write_state_q == WriteResponse) && write_response_ready_i &&
                       s_write_resp_seen_q && !s_write_protocol_fault_q && !clear_i;

  assign axi4.arid = '0;
  assign axi4.araddr = s_read_addr_q;
  assign axi4.arlen = {3'd0, s_read_beats_q} - 1'b1;
  assign axi4.arsize = s_read_size_q;
  assign axi4.arburst = 2'b01;
  assign axi4.arlock = 1'b0;
  assign axi4.arcache = 4'd0;
  assign axi4.arprot = 3'd0;
  assign axi4.arqos = 4'd0;
  assign axi4.arregion = 4'd0;
  assign axi4.aruser = '0;
  assign axi4.arvalid = (s_read_state_q == ReadAddress) && !clear_i &&
                        (!read_stop_i || s_rd_ar_presented_q);
  assign axi4.rready = (s_read_state_q == ReadData) && read_response_ready_i &&
                       s_read_resp_seen_q && !s_read_protocol_fault_q && !clear_i;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_read_state_q           <= ReadIdle;
      s_read_addr_q            <= '0;
      s_read_size_q            <= '0;
      s_read_beats_q           <= '0;
      s_read_beats_left_q      <= '0;
      s_rd_ar_presented_q      <= 1'b0;
      s_read_resp_seen_q       <= 1'b0;
      s_read_protocol_fault_q  <= 1'b0;
      s_write_state_q          <= WriteIdle;
      s_write_addr_q           <= '0;
      s_write_beats_q          <= '0;
      s_write_beats_left_q     <= '0;
      s_wr_aw_presented_q      <= 1'b0;
      s_write_resp_seen_q      <= 1'b0;
      s_write_protocol_fault_q <= 1'b0;
    end else if (clear_i) begin
      s_read_state_q           <= ReadIdle;
      s_write_state_q          <= WriteIdle;
      s_rd_ar_presented_q      <= 1'b0;
      s_wr_aw_presented_q      <= 1'b0;
      s_read_resp_seen_q       <= 1'b0;
      s_write_resp_seen_q      <= 1'b0;
      s_read_protocol_fault_q  <= 1'b0;
      s_write_protocol_fault_q <= 1'b0;
    end else begin
      unique case (s_read_state_q)
        ReadIdle: begin
          if (read_request_accept_o) begin
            // A stop-qualified acceptance commits an AR presentation for the next AXI cycle.
            s_read_addr_q           <= read_address_i;
            s_read_size_q           <= read_size_i;
            s_read_beats_q          <= read_beats_i;
            s_read_beats_left_q     <= read_beats_i;
            s_rd_ar_presented_q     <= 1'b1;
            s_read_resp_seen_q      <= 1'b0;
            s_read_protocol_fault_q <= 1'b0;
            s_read_state_q          <= ReadAddress;
          end
        end
        ReadAddress: begin
          if (read_request_cancel_o) begin
            s_read_state_q <= ReadIdle;
          end else begin
            s_rd_ar_presented_q <= 1'b1;
          end
          if (axi4.arvalid && axi4.arready) begin
            s_read_state_q <= ReadData;
          end
        end
        ReadData: begin
          if (axi4.rvalid) begin
            s_read_resp_seen_q <= 1'b1;
          end
          if (s_read_rsp_accept) begin
            if (read_protocol_error_o) begin
              s_read_protocol_fault_q <= 1'b1;
            end else if (s_read_rsp_terminal) begin
              s_read_state_q      <= ReadIdle;
              s_rd_ar_presented_q <= 1'b0;
              s_read_resp_seen_q  <= 1'b0;
            end else begin
              s_read_beats_left_q <= s_read_beats_left_q - 1'b1;
            end
          end
        end
        default: s_read_state_q <= ReadIdle;
      endcase

      unique case (s_write_state_q)
        WriteIdle: begin
          if (write_request_accept_o) begin
            // A stop-qualified acceptance commits an AW presentation for the next AXI cycle.
            s_write_addr_q           <= write_address_i;
            s_write_beats_q          <= write_beats_i;
            s_write_beats_left_q     <= write_beats_i;
            s_wr_aw_presented_q      <= 1'b1;
            s_write_resp_seen_q      <= 1'b0;
            s_write_protocol_fault_q <= 1'b0;
            s_write_state_q          <= WriteAddress;
          end
        end
        WriteAddress: begin
          if (write_request_cancel_o) begin
            s_write_state_q <= WriteIdle;
          end else begin
            s_wr_aw_presented_q <= 1'b1;
          end
          if (axi4.awvalid && axi4.awready) begin
            s_write_state_q <= WriteData;
          end
        end
        WriteData: begin
          if (write_payload_accept_o) begin
            if (s_write_beats_left_q == 5'd1) begin
              s_write_state_q <= WriteResponse;
            end else begin
              s_write_beats_left_q <= s_write_beats_left_q - 1'b1;
            end
          end
        end
        WriteResponse: begin
          if (axi4.bvalid) begin
            s_write_resp_seen_q <= 1'b1;
          end
          if (s_write_rsp_accept) begin
            if (write_protocol_error_o) begin
              s_write_protocol_fault_q <= 1'b1;
            end else begin
              s_write_state_q     <= WriteIdle;
              s_wr_aw_presented_q <= 1'b0;
              s_write_resp_seen_q <= 1'b0;
            end
          end
        end
        default: s_write_state_q <= WriteIdle;
      endcase
    end
  end
endmodule
