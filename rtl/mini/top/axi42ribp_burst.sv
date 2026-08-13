// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// See LICENSE for the complete license text.

`include "axi4_define.svh"

module axi42ribp_burst (
    input logic          clk_i,
    input logic          rst_n_i,
          axi4_if.slave  axi4,
          ribp_if.master ribp
);
  localparam logic [3:0] FSM_IDLE = 4'd0;
  localparam logic [3:0] FSM_WR_DATA = 4'd1;
  localparam logic [3:0] FSM_WR_REQ = 4'd2;
  localparam logic [3:0] FSM_WR_RESP = 4'd3;
  localparam logic [3:0] FSM_RD_REQ = 4'd4;
  localparam logic [3:0] FSM_RD_RESP = 4'd5;
  localparam logic [3:0] FSM_ERR_WR_DRAIN = 4'd6;
  localparam logic [3:0] FSM_ERR_WR_RESP = 4'd7;
  localparam logic [3:0] FSM_ERR_RD_RESP = 4'd8;

  logic [3:0] s_fsm_d, s_fsm_q;
  logic [31:0] s_addr_d, s_addr_q;
  logic [31:0] s_wdata_d, s_wdata_q;
  logic [3:0] s_wstrb_d, s_wstrb_q;
  logic [7:0] s_len_d, s_len_q;
  logic [7:0] s_beat_d, s_beat_q;
  logic [2:0] s_size_d, s_size_q;
  logic [1:0] s_burst_d, s_burst_q;
  logic s_id_d, s_id_q;
  logic [31:0] s_rdata_d, s_rdata_q;
  logic [1:0] s_resp_d, s_resp_q;
  logic s_legal_write, s_legal_read;
  logic [32:0] s_write_last_addr, s_read_last_addr;
  logic [31:0] s_next_addr;

  function automatic logic [32:0] burst_last_addr(input logic [31:0] addr, input logic [7:0] len,
                                                  input logic [2:0] size, input logic [1:0] burst);
    logic [32:0] beat_bytes;
    logic [32:0] burst_bytes;
    logic [32:0] wrap_base;
    begin
      beat_bytes  = 33'd1 << size;
      burst_bytes = beat_bytes * (33'(len) + 1'b1);
      wrap_base   = {1'b0, addr} & ~(burst_bytes - 1'b1);
      case (burst)
        `AXI4_BURST_TYPE_FIXED: burst_last_addr = {1'b0, addr} + beat_bytes - 1'b1;
        `AXI4_BURST_TYPE_WRAP:  burst_last_addr = wrap_base + burst_bytes - 1'b1;
        default:                burst_last_addr = {1'b0, addr} + burst_bytes - 1'b1;
      endcase
    end
  endfunction

  assign s_write_last_addr = burst_last_addr(axi4.awaddr, axi4.awlen, axi4.awsize, axi4.awburst);
  assign s_read_last_addr = burst_last_addr(axi4.araddr, axi4.arlen, axi4.arsize, axi4.arburst);
  assign s_legal_write = (axi4.awlen <= 8'd15) &&
                         ((axi4.awburst == `AXI4_BURST_TYPE_FIXED) ||
                          (axi4.awburst == `AXI4_BURST_TYPE_INCR) ||
                          ((axi4.awburst == `AXI4_BURST_TYPE_WRAP) &&
                           ((axi4.awlen == 8'd1) || (axi4.awlen == 8'd3) ||
                            (axi4.awlen == 8'd7) || (axi4.awlen == 8'd15)))) &&
                         !axi4.awlock &&
                         (axi4.awsize <= `AXI4_BURST_SIZE_4BYTES) &&
                         ((axi4.awaddr & ((32'd1 << axi4.awsize) - 1'b1)) == '0) &&
                         !s_write_last_addr[32] &&
                         (axi4.awaddr[31:12] == s_write_last_addr[31:12]);
  assign s_legal_read = (axi4.arlen <= 8'd15) &&
                        ((axi4.arburst == `AXI4_BURST_TYPE_FIXED) ||
                         (axi4.arburst == `AXI4_BURST_TYPE_INCR) ||
                         ((axi4.arburst == `AXI4_BURST_TYPE_WRAP) &&
                          ((axi4.arlen == 8'd1) || (axi4.arlen == 8'd3) ||
                           (axi4.arlen == 8'd7) || (axi4.arlen == 8'd15)))) &&
                        !axi4.arlock &&
                        (axi4.arsize <= `AXI4_BURST_SIZE_4BYTES) &&
                        ((axi4.araddr & ((32'd1 << axi4.arsize) - 1'b1)) == '0) &&
                        !s_read_last_addr[32] &&
                        (axi4.araddr[31:12] == s_read_last_addr[31:12]);

  assign axi4.awready = (s_fsm_q == FSM_IDLE) && !axi4.arvalid;
  assign axi4.arready = s_fsm_q == FSM_IDLE;
  assign axi4.wready = (s_fsm_q == FSM_WR_DATA) || (s_fsm_q == FSM_ERR_WR_DRAIN);
  assign axi4.bid = s_id_q;
  assign axi4.bresp = s_resp_q;
  assign axi4.buser = '0;
  assign axi4.bvalid = (s_fsm_q == FSM_WR_RESP) || (s_fsm_q == FSM_ERR_WR_RESP);
  assign axi4.rid = s_id_q;
  assign axi4.rdata = s_rdata_q;
  assign axi4.rresp = s_resp_q;
  assign axi4.rlast = s_beat_q == s_len_q;
  assign axi4.ruser = '0;
  assign axi4.rvalid = (s_fsm_q == FSM_RD_RESP) || (s_fsm_q == FSM_ERR_RD_RESP);

  assign ribp.valid = (s_fsm_q == FSM_WR_REQ) || (s_fsm_q == FSM_RD_REQ);
  assign ribp.addr = s_addr_q;
  assign ribp.wdata = s_wdata_q;
  assign ribp.wstrb = (s_fsm_q == FSM_WR_REQ) ? s_wstrb_q : '0;

  always_comb begin
    s_fsm_d   = s_fsm_q;
    s_addr_d  = s_addr_q;
    s_wdata_d = s_wdata_q;
    s_wstrb_d = s_wstrb_q;
    s_len_d   = s_len_q;
    s_beat_d  = s_beat_q;
    s_size_d  = s_size_q;
    s_burst_d = s_burst_q;
    s_id_d    = s_id_q;
    s_rdata_d = s_rdata_q;
    s_resp_d  = s_resp_q;

    unique case (s_fsm_q)
      FSM_IDLE: begin
        s_beat_d = '0;
        s_resp_d = `AXI4_RESP_OKAY;
        if (axi4.arvalid && axi4.arready) begin
          s_addr_d  = axi4.araddr;
          s_len_d   = axi4.arlen;
          s_size_d  = axi4.arsize;
          s_burst_d = axi4.arburst;
          s_id_d    = axi4.arid;
          s_fsm_d   = s_legal_read ? FSM_RD_REQ : FSM_ERR_RD_RESP;
          if (!s_legal_read) s_resp_d = `AXI4_RESP_SLAVE_ERROR;
        end else if (axi4.awvalid && axi4.awready) begin
          s_addr_d  = axi4.awaddr;
          s_len_d   = axi4.awlen;
          s_size_d  = axi4.awsize;
          s_burst_d = axi4.awburst;
          s_id_d    = axi4.awid;
          s_fsm_d   = s_legal_write ? FSM_WR_DATA : FSM_ERR_WR_DRAIN;
          if (!s_legal_write) s_resp_d = `AXI4_RESP_SLAVE_ERROR;
        end
      end
      FSM_WR_DATA: begin
        if (axi4.wvalid && axi4.wready) begin
          s_wdata_d = axi4.wdata;
          s_wstrb_d = axi4.wstrb;
          s_fsm_d   = FSM_WR_REQ;
          if (axi4.wlast != (s_beat_q == s_len_q)) s_resp_d = `AXI4_RESP_SLAVE_ERROR;
        end
      end
      FSM_WR_REQ: begin
        if (ribp.ready) begin
          if (ribp.resp_err) s_resp_d = `AXI4_RESP_SLAVE_ERROR;
          if ((s_beat_q == s_len_q) || (s_resp_q != `AXI4_RESP_OKAY)) begin
            s_fsm_d = FSM_WR_RESP;
          end else begin
            s_addr_d = s_next_addr;
            s_beat_d = s_beat_q + 1'b1;
            s_fsm_d  = FSM_WR_DATA;
          end
        end
      end
      FSM_WR_RESP: begin
        if (axi4.bvalid && axi4.bready) s_fsm_d = FSM_IDLE;
      end
      FSM_RD_REQ: begin
        if (ribp.ready) begin
          s_rdata_d = ribp.rdata;
          if (ribp.resp_err) s_resp_d = `AXI4_RESP_SLAVE_ERROR;
          s_fsm_d = FSM_RD_RESP;
        end
      end
      FSM_RD_RESP: begin
        if (axi4.rvalid && axi4.rready) begin
          if (s_beat_q == s_len_q) begin
            s_fsm_d = FSM_IDLE;
          end else begin
            s_addr_d = s_next_addr;
            s_beat_d = s_beat_q + 1'b1;
            s_fsm_d  = FSM_RD_REQ;
          end
        end
      end
      FSM_ERR_WR_DRAIN: begin
        if (axi4.wvalid && axi4.wready && axi4.wlast) s_fsm_d = FSM_ERR_WR_RESP;
      end
      FSM_ERR_WR_RESP: begin
        if (axi4.bvalid && axi4.bready) s_fsm_d = FSM_IDLE;
      end
      FSM_ERR_RD_RESP: begin
        if (axi4.rvalid && axi4.rready) begin
          if (s_beat_q == s_len_q) begin
            s_fsm_d = FSM_IDLE;
          end else begin
            s_beat_d = s_beat_q + 1'b1;
          end
        end
      end
      default: s_fsm_d = FSM_IDLE;
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

  dffr #(
      .DATA_WIDTH(4)
  ) u_fsm_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fsm_d),
      .dat_o  (s_fsm_q)
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
  ) u_wdata_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_wdata_d),
      .dat_o  (s_wdata_q)
  );
  dffr #(
      .DATA_WIDTH(4)
  ) u_wstrb_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_wstrb_d),
      .dat_o  (s_wstrb_q)
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
      .DATA_WIDTH(32)
  ) u_rdata_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rdata_d),
      .dat_o  (s_rdata_q)
  );
  dffr #(
      .DATA_WIDTH(2)
  ) u_resp_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_resp_d),
      .dat_o  (s_resp_q)
  );
endmodule
