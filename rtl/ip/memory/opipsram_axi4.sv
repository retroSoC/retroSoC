// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

`include "axi4_define.svh"

module opipsram_axi4 (
    // verilog_format: off -- preserve reviewed port alignment
    input  logic          clk_i,
    input  logic          rst_n_i,
    input  logic          accept_enable_i,
    input  logic [31:0]   device_size_i,
    input  logic          memory_available_i,
    axi4_if.slave         axi4,
    output logic          core_req_valid_o,
    input  logic          core_req_ready_i,
    output logic          core_req_write_o,
    output logic [31:0]   core_req_addr_o,
    output logic [3:0]    core_req_len_o,
    output logic [31:0]   core_req_wdata_o,
    output logic [3:0]    core_req_wstrb_o,
    input  logic          core_rsp_valid_i,
    output logic          core_rsp_ready_o,
    input  logic          core_rsp_error_i,
    input  logic [31:0]   core_rsp_rdata_i,
    output logic          busy_o,
    output logic          stall_event_o,
    output logic [3:0]    read_bytes_event_o,
    output logic [3:0]    write_bytes_event_o,
    output logic          error_event_o
    // verilog_format: on
);

  localparam logic [31:0] APERTURE_BASE = 32'h4800_0000;
  localparam logic [31:0] APERTURE_LAST = 32'h4FFF_FFFF;

  typedef enum logic [3:0] {
    AxiIdle       = 4'd0,
    AxiWriteData  = 4'd1,
    AxiWriteIssue = 4'd2,
    AxiWriteWait  = 4'd3,
    AxiWriteDrain = 4'd4,
    AxiWriteResp  = 4'd5,
    AxiReadIssue  = 4'd6,
    AxiReadWait   = 4'd7,
    AxiReadResp   = 4'd8
  } opipsram_axi_state_e;

  logic [3:0] s_state_bits_q;
  opipsram_axi_state_e s_state_d, s_state_q;
  logic [31:0] s_addr_d, s_addr_q;
  logic [7:0] s_len_d, s_len_q;
  logic [7:0] s_beat_d, s_beat_q;
  logic [2:0] s_size_d, s_size_q;
  logic [0:0] s_id_d, s_id_q;
  logic [31:0] s_wdata_d, s_wdata_q;
  logic [3:0] s_lane_mask_d, s_lane_mask_q;
  logic [1:0] s_lane_d, s_lane_q;
  logic [1:0] s_resp_d, s_resp_q;
  logic [31:0] s_rdata_d, s_rdata_q;
  logic s_read_invalid_d, s_read_invalid_q;
  logic s_stall_d, s_stall_q;
  logic [3:0] s_read_bytes_d, s_read_bytes_q;
  logic [3:0] s_write_bytes_d, s_write_bytes_q;
  logic s_err_evt_d, s_err_evt_q;

  logic [32:0] s_write_last_addr;
  logic [32:0] s_read_last_addr;
  logic [32:0] s_device_last;
  logic        s_legal_read;
  logic        s_legal_write;
  logic        s_w_accept;
  logic        s_r_accept;
  logic        s_core_accept;
  logic        s_core_rsp_accept;

  assign s_state_q = opipsram_axi_state_e'(s_state_bits_q);

  function automatic logic [32:0] burst_last_addr(input logic [31:0] addr, input logic [7:0] length,
                                                  input logic [2:0] size);
    logic [32:0] bytes;
    begin
      bytes = ({25'd0, length} + 33'd1) << size;
      return {1'b0, addr} + bytes - 33'd1;
    end
  endfunction

  function automatic logic [3:0] beat_mask(input logic [2:0] size, input logic [1:0] addr);
    unique case (size)
      3'd0:    return 4'b0001 << addr;
      3'd1:    return 4'b0011 << addr;
      3'd2:    return 4'b1111;
      default: return 4'd0;
    endcase
  endfunction

  function automatic logic [1:0] first_lane(input logic [3:0] mask);
    if (mask[0]) return 2'd0;
    if (mask[1]) return 2'd1;
    if (mask[2]) return 2'd2;
    if (mask[3]) return 2'd3;
    return 2'd0;
  endfunction

  assign s_write_last_addr = burst_last_addr(axi4.awaddr, axi4.awlen, axi4.awsize);
  assign s_device_last = {1'b0, APERTURE_BASE} + {1'b0, device_size_i} - 33'd1;
  assign s_legal_write = (axi4.awlen <= 8'd15) &&
      (axi4.awburst == `AXI4_BURST_TYPE_INCR) && !axi4.awlock &&
      (axi4.awsize <= `AXI4_BURST_SIZE_4BYTES) &&
      ((axi4.awaddr & ((32'd1 << axi4.awsize) - 32'd1)) == 32'd0) &&
      !s_write_last_addr[32] && (axi4.awaddr[31:12] == s_write_last_addr[31:12]) &&
      (axi4.awaddr >= APERTURE_BASE) && (s_write_last_addr[31:0] <= APERTURE_LAST) &&
      (s_write_last_addr <= s_device_last);
  assign s_read_last_addr = burst_last_addr(axi4.araddr, axi4.arlen, axi4.arsize);
  assign s_legal_read = (axi4.arlen <= 8'd15) &&
      (axi4.arburst == `AXI4_BURST_TYPE_INCR) && !axi4.arlock &&
      (axi4.arsize <= `AXI4_BURST_SIZE_4BYTES) &&
      ((axi4.araddr & ((32'd1 << axi4.arsize) - 32'd1)) == 32'd0) &&
      !s_read_last_addr[32] && (axi4.araddr[31:12] == s_read_last_addr[31:12]) &&
      (axi4.araddr >= APERTURE_BASE) && (s_read_last_addr[31:0] <= APERTURE_LAST) &&
      (s_read_last_addr <= s_device_last);

  assign s_w_accept = axi4.wvalid && axi4.wready;
  assign s_r_accept = axi4.rvalid && axi4.rready;
  assign s_core_accept = core_req_valid_o && core_req_ready_i;
  assign s_core_rsp_accept = core_rsp_valid_i && core_rsp_ready_o;

  assign axi4.awready = (s_state_q == AxiIdle) && accept_enable_i && !axi4.arvalid;
  assign axi4.arready = (s_state_q == AxiIdle) && accept_enable_i;
  assign axi4.wready = (s_state_q == AxiWriteData) || (s_state_q == AxiWriteDrain);
  assign axi4.bid = s_id_q;
  assign axi4.bresp = s_resp_q;
  assign axi4.buser = '0;
  assign axi4.bvalid = s_state_q == AxiWriteResp;
  assign axi4.rid = s_id_q;
  always_comb begin
    axi4.rdata       = '0;
    axi4.rdata[31:0] = s_rdata_q;
  end
  assign axi4.rresp = s_resp_q;
  assign axi4.ruser = '0;
  assign axi4.rvalid = s_state_q == AxiReadResp;
  assign axi4.rlast = s_beat_q == s_len_q;

  assign core_req_valid_o = (s_state_q == AxiWriteIssue) || (s_state_q == AxiReadIssue);
  assign core_req_write_o = s_state_q == AxiWriteIssue;
  assign core_req_addr_o = (s_state_q == AxiWriteIssue) ? (s_addr_q + {30'd0, s_lane_q}) : s_addr_q;
  assign core_req_len_o = (s_state_q == AxiWriteIssue) ? 4'd1 : (4'd1 << s_size_q);
  assign core_req_wdata_o = s_wdata_q >> (s_lane_q * 8);
  assign core_req_wstrb_o = (s_state_q == AxiWriteIssue) ? 4'b0001 : 4'd0;
  assign core_rsp_ready_o = (s_state_q == AxiWriteWait) || (s_state_q == AxiReadWait);
  assign busy_o = s_state_q != AxiIdle;
  assign stall_event_o = s_stall_q;
  assign read_bytes_event_o = s_read_bytes_q;
  assign write_bytes_event_o = s_write_bytes_q;
  assign error_event_o = s_err_evt_q;

  always_comb begin
    s_state_d        = s_state_q;
    s_addr_d         = s_addr_q;
    s_len_d          = s_len_q;
    s_beat_d         = s_beat_q;
    s_size_d         = s_size_q;
    s_id_d           = s_id_q;
    s_wdata_d        = s_wdata_q;
    s_lane_mask_d    = s_lane_mask_q;
    s_lane_d         = s_lane_q;
    s_resp_d         = s_resp_q;
    s_rdata_d        = s_rdata_q;
    s_read_invalid_d = s_read_invalid_q;
    s_stall_d        = 1'b0;
    s_read_bytes_d   = 4'd0;
    s_write_bytes_d  = 4'd0;
    s_err_evt_d      = 1'b0;

    if ((axi4.awvalid && !axi4.awready) || (axi4.arvalid && !axi4.arready) ||
        (axi4.wvalid && !axi4.wready) || (axi4.rvalid && !axi4.rready) ||
        (axi4.bvalid && !axi4.bready)) begin
      s_stall_d = 1'b1;
    end

    unique case (s_state_q)
      AxiIdle: begin
        s_beat_d         = 8'd0;
        s_resp_d         = `AXI4_RESP_OKAY;
        s_read_invalid_d = 1'b0;
        if (axi4.arvalid && axi4.arready) begin
          s_addr_d  = axi4.araddr;
          s_len_d   = axi4.arlen;
          s_size_d  = axi4.arsize;
          s_id_d    = axi4.arid[0];
          s_rdata_d = 32'd0;
          if (!s_legal_read || !memory_available_i) begin
            s_read_invalid_d = 1'b1;
            s_resp_d         = `AXI4_RESP_SLAVE_ERROR;
            s_state_d        = AxiReadResp;
            s_err_evt_d      = 1'b1;
          end else begin
            s_state_d = AxiReadIssue;
          end
        end else if (axi4.awvalid && axi4.awready) begin
          s_addr_d  = axi4.awaddr;
          s_len_d   = axi4.awlen;
          s_size_d  = axi4.awsize;
          s_id_d    = axi4.awid[0];
          s_state_d = AxiWriteData;
          if (!s_legal_write || !memory_available_i) begin
            s_resp_d    = `AXI4_RESP_SLAVE_ERROR;
            s_err_evt_d = 1'b1;
            s_beat_d    = 8'd0;
            s_state_d   = AxiWriteDrain;
          end
        end
      end

      AxiWriteData: begin
        if (s_w_accept) begin
          s_wdata_d     = axi4.wdata[31:0];
          s_lane_mask_d = axi4.wstrb[3:0] & beat_mask(s_size_q, s_addr_q[1:0]);
          s_lane_d      = first_lane(axi4.wstrb[3:0] & beat_mask(s_size_q, s_addr_q[1:0]));
          if ((axi4.wlast != (s_beat_q == s_len_q)) || (axi4.wstrb[3:0] & ~beat_mask(
                  s_size_q, s_addr_q[1:0]
              )) != 4'd0) begin
            s_resp_d    = `AXI4_RESP_SLAVE_ERROR;
            s_err_evt_d = 1'b1;
            if (s_beat_q == s_len_q) begin
              s_state_d = AxiWriteResp;
            end else begin
              s_beat_d  = s_beat_q + 8'd1;
              s_state_d = AxiWriteDrain;
            end
          end else if ((axi4.wstrb[3:0] & beat_mask(s_size_q, s_addr_q[1:0])) == 4'd0) begin
            if (s_beat_q == s_len_q) begin
              s_state_d = AxiWriteResp;
            end else begin
              s_addr_d = s_addr_q + (32'd1 << s_size_q);
              s_beat_d = s_beat_q + 8'd1;
            end
          end else begin
            s_state_d = AxiWriteIssue;
          end
        end
      end

      AxiWriteIssue: begin
        if (s_core_accept) s_state_d = AxiWriteWait;
      end

      AxiWriteWait: begin
        if (s_core_rsp_accept) begin
          if (core_rsp_error_i) begin
            s_resp_d    = `AXI4_RESP_SLAVE_ERROR;
            s_err_evt_d = 1'b1;
            if (s_beat_q == s_len_q) begin
              s_state_d = AxiWriteResp;
            end else begin
              s_beat_d  = s_beat_q + 8'd1;
              s_state_d = AxiWriteDrain;
            end
          end else if ((s_lane_mask_q & ~(4'b0001 << s_lane_q)) != 4'd0) begin
            s_lane_mask_d   = s_lane_mask_q & ~(4'b0001 << s_lane_q);
            s_lane_d        = first_lane(s_lane_mask_q & ~(4'b0001 << s_lane_q));
            s_write_bytes_d = 4'd1;
            s_state_d       = AxiWriteIssue;
          end else if (s_beat_q == s_len_q) begin
            s_write_bytes_d = 4'd1;
            s_state_d       = AxiWriteResp;
          end else begin
            s_write_bytes_d = 4'd1;
            s_addr_d        = s_addr_q + (32'd1 << s_size_q);
            s_beat_d        = s_beat_q + 8'd1;
            s_state_d       = AxiWriteData;
          end
        end
      end

      AxiWriteDrain: begin
        if (s_w_accept) begin
          if (s_beat_q == s_len_q) begin
            s_state_d = AxiWriteResp;
          end else begin
            s_beat_d = s_beat_q + 8'd1;
          end
        end
      end

      AxiWriteResp: begin
        if (axi4.bvalid && axi4.bready) s_state_d = AxiIdle;
      end

      AxiReadIssue: begin
        if (s_core_accept) s_state_d = AxiReadWait;
      end

      AxiReadWait: begin
        if (s_core_rsp_accept) begin
          s_rdata_d = core_rsp_rdata_i << (s_addr_q[1:0] * 8);
          if (core_rsp_error_i) begin
            s_resp_d         = `AXI4_RESP_SLAVE_ERROR;
            s_read_invalid_d = 1'b1;
            s_err_evt_d      = 1'b1;
          end else begin
            s_read_bytes_d = 4'd1 << s_size_q;
          end
          s_state_d = AxiReadResp;
        end
      end

      AxiReadResp: begin
        if (s_r_accept) begin
          if (s_beat_q == s_len_q) begin
            s_state_d = AxiIdle;
          end else begin
            s_addr_d  = s_addr_q + (32'd1 << s_size_q);
            s_beat_d  = s_beat_q + 8'd1;
            s_rdata_d = 32'd0;
            s_resp_d  = s_read_invalid_q ? `AXI4_RESP_SLAVE_ERROR : `AXI4_RESP_OKAY;
            s_state_d = s_read_invalid_q ? AxiReadResp : AxiReadIssue;
          end
        end
      end

      default: s_state_d = AxiIdle;
    endcase
  end

  dffrc #(
      .DATA_WIDTH(4),
      .RESET_VAL (AxiIdle)
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
      .DATA_WIDTH(1)
  ) u_id_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_id_d),
      .dat_o  (s_id_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_wdata_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_wdata_d),
      .dat_o  (s_wdata_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_lane_mask_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_lane_mask_d),
      .dat_o  (s_lane_mask_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_lane_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_lane_d),
      .dat_o  (s_lane_q)
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
  ) u_read_invalid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_invalid_d),
      .dat_o  (s_read_invalid_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_stall_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_stall_d),
      .dat_o  (s_stall_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_read_bytes_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_read_bytes_d),
      .dat_o  (s_read_bytes_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_write_bytes_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_write_bytes_d),
      .dat_o  (s_write_bytes_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_error_event_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_evt_d),
      .dat_o  (s_err_evt_q)
  );

endmodule
