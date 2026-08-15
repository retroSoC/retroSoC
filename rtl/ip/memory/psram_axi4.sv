// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

`include "axi4_define.svh"
`include "mmap_define.svh"

module psram_axi4 (
    // verilog_format: off -- preserve reviewed port alignment
    input  logic          clk_i,
    input  logic          rst_n_i,
    input  logic          accept_enable_i,
    output logic          busy_o,
    output logic          stall_event_o,
    output logic          split_event_o,
    axi4_if.slave         axi4,
    output logic          mem_req_valid_o,
    input  logic          mem_req_ready_i,
    output logic          mem_req_write_o,
    output logic [1:0]    mem_req_chip_o,
    output logic [22:0]   mem_req_addr_o,
    output logic [2:0]    mem_req_len_o,
    output logic [31:0]   mem_req_wdata_o,
    input  logic          mem_rsp_valid_i,
    output logic          mem_rsp_ready_o,
    input  logic          mem_rsp_error_i,
    input  logic [31:0]   mem_rsp_rdata_i
    // verilog_format: on
);

  typedef enum logic [3:0] {
    AxiIdle          = 4'd0,
    AxiWriteData     = 4'd1,
    AxiWriteRequest  = 4'd2,
    AxiWriteWait     = 4'd3,
    AxiWriteDrain    = 4'd4,
    AxiWriteResponse = 4'd5,
    AxiReadRequest   = 4'd6,
    AxiReadWait      = 4'd7,
    AxiReadResponse  = 4'd8
  } psram_axi_state_e;

  psram_axi_state_e        s_state_q;
  logic             [31:0] s_addr_q;
  logic             [31:0] s_next_addr;
  logic             [ 7:0] s_len_q;
  logic             [ 7:0] s_beat_q;
  logic             [ 2:0] s_size_q;
  logic             [ 1:0] s_burst_q;
  logic                    s_id_q;
  logic             [31:0] s_wdata_q;
  logic             [ 3:0] s_wstrb_q;
  logic                    s_wlast_q;
  logic             [ 1:0] s_resp_q;
  logic             [31:0] s_rdata_q;
  logic             [ 2:0] s_byte_count_q;
  logic                    s_read_invalid_q;

  logic             [32:0] s_write_last_addr;
  logic             [32:0] s_read_last_addr;
  logic                    s_legal_write;
  logic                    s_legal_read;
  logic             [ 3:0] s_write_lane_mask;
  logic             [ 1:0] s_active_lane;
  logic             [ 2:0] s_active_run_len;
  logic             [ 3:0] s_active_run_mask;

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

  function automatic logic [3:0] transfer_lane_mask(input logic [2:0] size,
                                                    input logic [1:0] address);
    begin
      unique case (size)
        3'd0:    return 4'b0001 << address;
        3'd1:    return 4'b0011 << address;
        default: return 4'b1111;
      endcase
    end
  endfunction

  function automatic logic [2:0] active_run_length(input logic [3:0] strobe,
                                                   input logic [1:0] lane);
    begin
      if (!strobe[lane]) return 3'd0;
      unique case (lane)
        2'd0: begin
          if (!strobe[1]) return 3'd1;
          if (!strobe[2]) return 3'd2;
          if (!strobe[3]) return 3'd3;
          return 3'd4;
        end
        2'd1: begin
          if (!strobe[2]) return 3'd1;
          if (!strobe[3]) return 3'd2;
          return 3'd3;
        end
        2'd2:    return strobe[3] ? 3'd2 : 3'd1;
        default: return 3'd1;
      endcase
    end
  endfunction

  function automatic logic [3:0] active_run_mask(input logic [2:0] run_len, input logic [1:0] lane);
    logic [3:0] ones;
    begin
      ones = (4'd1 << run_len) - 1'b1;
      return ones << lane;
    end
  endfunction

  always_comb begin
    unique casez (s_wstrb_q)
      4'b???1: s_active_lane = 2'd0;
      4'b??10: s_active_lane = 2'd1;
      4'b?100: s_active_lane = 2'd2;
      default: s_active_lane = 2'd3;
    endcase
  end

  assign s_active_run_len = active_run_length(s_wstrb_q, s_active_lane);
  assign s_active_run_mask = active_run_mask(s_active_run_len, s_active_lane);

  assign s_write_last_addr = burst_last_addr(axi4.awaddr, axi4.awlen, axi4.awsize, axi4.awburst);
  assign s_read_last_addr = burst_last_addr(axi4.araddr, axi4.arlen, axi4.arsize, axi4.arburst);

  assign s_legal_write =
      (axi4.awlen <= 8'd15) &&
      ((axi4.awburst == `AXI4_BURST_TYPE_FIXED) ||
       (axi4.awburst == `AXI4_BURST_TYPE_INCR) ||
       ((axi4.awburst == `AXI4_BURST_TYPE_WRAP) && wrap_length_legal(
          axi4.awlen
      ))) && !axi4.awlock && (axi4.awsize <= `AXI4_BURST_SIZE_4BYTES) &&
          ((axi4.awaddr & ((32'd1 << axi4.awsize) - 1'b1)) == 32'd0) && !s_write_last_addr[32] &&
          (axi4.awaddr[31:12] == s_write_last_addr[31:12]) &&
      `SOC_ADDR_IS_PSRAM(axi4.awaddr)
      &&
      `SOC_ADDR_IS_PSRAM(s_write_last_addr[31:0]);

  assign s_legal_read =
      (axi4.arlen <= 8'd15) &&
      ((axi4.arburst == `AXI4_BURST_TYPE_FIXED) ||
       (axi4.arburst == `AXI4_BURST_TYPE_INCR) ||
       ((axi4.arburst == `AXI4_BURST_TYPE_WRAP) && wrap_length_legal(
          axi4.arlen
      ))) && !axi4.arlock && (axi4.arsize <= `AXI4_BURST_SIZE_4BYTES) &&
          ((axi4.araddr & ((32'd1 << axi4.arsize) - 1'b1)) == 32'd0) && !s_read_last_addr[32] &&
          (axi4.araddr[31:12] == s_read_last_addr[31:12]) &&
      `SOC_ADDR_IS_PSRAM(axi4.araddr)
      &&
      `SOC_ADDR_IS_PSRAM(s_read_last_addr[31:0]);

  assign s_write_lane_mask = transfer_lane_mask(s_size_q, s_addr_q[1:0]);

  assign axi4.awready = (s_state_q == AxiIdle) && accept_enable_i && !axi4.arvalid;
  assign axi4.arready = (s_state_q == AxiIdle) && accept_enable_i;
  assign axi4.wready = (s_state_q == AxiWriteData) || (s_state_q == AxiWriteDrain);
  assign axi4.bid = s_id_q;
  assign axi4.bresp = s_resp_q;
  assign axi4.buser = '0;
  assign axi4.bvalid = s_state_q == AxiWriteResponse;
  assign axi4.rid = s_id_q;
  assign axi4.rdata = s_rdata_q;
  assign axi4.rresp = s_resp_q;
  assign axi4.rlast = s_beat_q == s_len_q;
  assign axi4.ruser = '0;
  assign axi4.rvalid = s_state_q == AxiReadResponse;

  assign busy_o = s_state_q != AxiIdle;
  assign stall_event_o = (axi4.awvalid && !axi4.awready) ||
                         (axi4.wvalid && !axi4.wready) ||
                         (axi4.arvalid && !axi4.arready) ||
                         (axi4.rvalid && !axi4.rready) ||
                         (axi4.bvalid && !axi4.bready);

  assign mem_req_valid_o = (s_state_q == AxiWriteRequest) || (s_state_q == AxiReadRequest);
  assign mem_req_write_o = s_state_q == AxiWriteRequest;
  assign mem_req_chip_o = s_addr_q[24:23];
  assign mem_req_addr_o = (s_state_q == AxiWriteRequest) ?
                          ({s_addr_q[22:2], 2'b00} + {21'd0, s_active_lane}) :
                          s_addr_q[22:0];
  assign mem_req_len_o = (s_state_q == AxiWriteRequest) ? s_active_run_len : s_byte_count_q;
  assign mem_req_wdata_o = s_wdata_q >> (s_active_lane * 8);
  assign mem_rsp_ready_o = (s_state_q == AxiWriteWait) || (s_state_q == AxiReadWait);

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_state_q        <= AxiIdle;
      s_addr_q         <= '0;
      s_len_q          <= '0;
      s_beat_q         <= '0;
      s_size_q         <= '0;
      s_burst_q        <= '0;
      s_id_q           <= '0;
      s_wdata_q        <= '0;
      s_wstrb_q        <= '0;
      s_wlast_q        <= 1'b0;
      s_resp_q         <= `AXI4_RESP_OKAY;
      s_rdata_q        <= '0;
      s_byte_count_q   <= '0;
      s_read_invalid_q <= 1'b0;
      split_event_o    <= 1'b0;
    end else begin
      split_event_o <= 1'b0;
      unique case (s_state_q)
        AxiIdle: begin
          s_beat_q         <= '0;
          s_resp_q         <= `AXI4_RESP_OKAY;
          s_read_invalid_q <= 1'b0;
          if (axi4.arvalid && axi4.arready) begin
            s_addr_q       <= axi4.araddr;
            s_len_q        <= axi4.arlen;
            s_size_q       <= axi4.arsize;
            s_burst_q      <= axi4.arburst;
            s_id_q         <= axi4.arid;
            s_rdata_q      <= '0;
            s_byte_count_q <= 3'(3'd1 << axi4.arsize);
            if (s_legal_read) begin
              s_state_q <= AxiReadRequest;
            end else begin
              s_resp_q         <= `AXI4_RESP_SLAVE_ERROR;
              s_read_invalid_q <= 1'b1;
              s_state_q        <= AxiReadResponse;
            end
          end else if (axi4.awvalid && axi4.awready) begin
            s_addr_q  <= axi4.awaddr;
            s_len_q   <= axi4.awlen;
            s_size_q  <= axi4.awsize;
            s_burst_q <= axi4.awburst;
            s_id_q    <= axi4.awid;
            if (s_legal_write) begin
              s_state_q <= AxiWriteData;
            end else begin
              s_resp_q  <= `AXI4_RESP_SLAVE_ERROR;
              s_state_q <= AxiWriteDrain;
            end
          end
        end

        AxiWriteData: begin
          if (axi4.wvalid && axi4.wready) begin
            s_wdata_q <= axi4.wdata;
            s_wstrb_q <= axi4.wstrb;
            s_wlast_q <= axi4.wlast;
            if ((axi4.wlast != (s_beat_q == s_len_q)) || (|(axi4.wstrb & ~s_write_lane_mask))) begin
              s_resp_q <= `AXI4_RESP_SLAVE_ERROR;
              if (axi4.wlast) s_state_q <= AxiWriteResponse;
              else s_state_q <= AxiWriteDrain;
            end else if (axi4.wstrb == 4'd0) begin
              if (s_beat_q == s_len_q) begin
                s_state_q <= AxiWriteResponse;
              end else begin
                if ((s_addr_q[22:0] == 23'h0003FF) || (s_addr_q[22:0] == 23'h7FFFFF)) begin
                  split_event_o <= 1'b1;
                end
                s_addr_q  <= s_next_addr;
                s_beat_q  <= s_beat_q + 1'b1;
                s_state_q <= AxiWriteData;
              end
            end else begin
              s_state_q <= AxiWriteRequest;
            end
          end
        end

        AxiWriteRequest: begin
          if (mem_req_valid_o && mem_req_ready_i) begin
            s_wstrb_q <= s_wstrb_q & ~s_active_run_mask;
            s_state_q <= AxiWriteWait;
          end
        end

        AxiWriteWait: begin
          if (mem_rsp_valid_i && mem_rsp_ready_o) begin
            if (mem_rsp_error_i) begin
              s_resp_q <= `AXI4_RESP_SLAVE_ERROR;
              if (s_wlast_q) s_state_q <= AxiWriteResponse;
              else s_state_q <= AxiWriteDrain;
            end else if (s_wstrb_q != 4'd0) begin
              s_state_q <= AxiWriteRequest;
            end else if (s_beat_q == s_len_q) begin
              s_state_q <= AxiWriteResponse;
            end else begin
              if ((s_addr_q[22:0] == 23'h0003FF) || (s_addr_q[22:0] == 23'h7FFFFF)) begin
                split_event_o <= 1'b1;
              end
              s_addr_q  <= s_next_addr;
              s_beat_q  <= s_beat_q + 1'b1;
              s_state_q <= AxiWriteData;
            end
          end
        end

        AxiWriteDrain: begin
          if (axi4.wvalid && axi4.wready && axi4.wlast) begin
            s_state_q <= AxiWriteResponse;
          end
        end

        AxiWriteResponse: begin
          if (axi4.bvalid && axi4.bready) begin
            s_state_q <= AxiIdle;
          end
        end

        AxiReadRequest: begin
          if (mem_req_valid_o && mem_req_ready_i) begin
            s_state_q <= AxiReadWait;
          end
        end

        AxiReadWait: begin
          if (mem_rsp_valid_i && mem_rsp_ready_o) begin
            if (mem_rsp_error_i) begin
              s_resp_q  <= `AXI4_RESP_SLAVE_ERROR;
              s_state_q <= AxiReadResponse;
            end else begin
              s_rdata_q <= mem_rsp_rdata_i << (s_addr_q[1:0] * 8);
              s_state_q <= AxiReadResponse;
            end
          end
        end

        AxiReadResponse: begin
          if (axi4.rvalid && axi4.rready) begin
            if (s_beat_q == s_len_q) begin
              s_state_q <= AxiIdle;
            end else begin
              if ((s_addr_q[22:0] == 23'h0003FF) || (s_addr_q[22:0] == 23'h7FFFFF)) begin
                split_event_o <= 1'b1;
              end
              s_addr_q  <= s_next_addr;
              s_beat_q  <= s_beat_q + 1'b1;
              s_rdata_q <= '0;
              s_resp_q  <= s_read_invalid_q ? `AXI4_RESP_SLAVE_ERROR : `AXI4_RESP_OKAY;
              s_state_q <= s_read_invalid_q ? AxiReadResponse : AxiReadRequest;
            end
          end
        end

        default: s_state_q <= AxiIdle;
      endcase
    end
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

endmodule
