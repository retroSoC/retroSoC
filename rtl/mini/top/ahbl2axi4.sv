// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// See LICENSE for the complete license text.

`include "axi4_define.svh"

module ahbl2axi4 (
           ahbl_if.slave  ahbl,
           axi4_if.master axi4,
    output logic          idle_o
);
  localparam logic [1:0] AHBL_TRANS_NSEQ = 2'b10;
  localparam logic [2:0] AHBL_SIZE_BYTE = 3'b000;
  localparam logic [2:0] AHBL_SIZE_HWRD = 3'b001;
  localparam logic AHBL_RESP_OKAY = 1'b0;
  localparam logic AHBL_RESP_ERROR = 1'b1;

  localparam logic [2:0] FSM_IDLE = 3'd0;
  localparam logic [2:0] FSM_WRITE = 3'd1;
  localparam logic [2:0] FSM_WRITE_RESP = 3'd2;
  localparam logic [2:0] FSM_READ = 3'd3;
  localparam logic [2:0] FSM_READ_RESP = 3'd4;

  logic [2:0] s_fsm_d, s_fsm_q;
  logic [31:0] s_addr_d, s_addr_q;
  logic s_write_d, s_write_q;
  logic [2:0] s_size_d, s_size_q;
  logic s_aw_done_d, s_aw_done_q;
  logic s_w_done_d, s_w_done_q;
  logic [ 3:0] s_wstrb;
  logic [31:0] s_wdata;
  logic        s_terminal;

  assign idle_o = s_fsm_q == FSM_IDLE;
  assign s_terminal = ((s_fsm_q == FSM_WRITE_RESP) && axi4.bvalid) ||
                      ((s_fsm_q == FSM_READ_RESP) && axi4.rvalid);
  assign ahbl.hready = (s_fsm_q == FSM_IDLE) || s_terminal;
  assign ahbl.hresp = s_terminal &&
                      (((s_fsm_q == FSM_WRITE_RESP) && (axi4.bresp != `AXI4_RESP_OKAY)) ||
                       ((s_fsm_q == FSM_READ_RESP) && (axi4.rresp != `AXI4_RESP_OKAY))) ?
                          AHBL_RESP_ERROR : AHBL_RESP_OKAY;
  assign ahbl.hrdata = axi4.rdata;

  always_comb begin
    s_wstrb = '0;
    s_wdata = '0;
    if (s_write_q) begin
      unique case (s_size_q)
        AHBL_SIZE_BYTE: begin
          unique case (s_addr_q[1:0])
            2'd0: begin
              s_wstrb = 4'b0001;
              s_wdata = {24'd0, ahbl.hwdata[7:0]};
            end
            2'd1: begin
              s_wstrb = 4'b0010;
              s_wdata = {16'd0, ahbl.hwdata[7:0], 8'd0};
            end
            2'd2: begin
              s_wstrb = 4'b0100;
              s_wdata = {8'd0, ahbl.hwdata[7:0], 16'd0};
            end
            default: begin
              s_wstrb = 4'b1000;
              s_wdata = {ahbl.hwdata[7:0], 24'd0};
            end
          endcase
        end
        AHBL_SIZE_HWRD: begin
          if (s_addr_q[1]) begin
            s_wstrb = 4'b1100;
            s_wdata = {ahbl.hwdata[15:0], 16'd0};
          end else begin
            s_wstrb = 4'b0011;
            s_wdata = {16'd0, ahbl.hwdata[15:0]};
          end
        end
        default: begin
          s_wstrb = 4'b1111;
          s_wdata = ahbl.hwdata;
        end
      endcase
    end
  end

  assign axi4.awid     = '0;
  assign axi4.awaddr   = {s_addr_q[31:2], 2'b00};
  assign axi4.awlen    = 8'd0;
  assign axi4.awsize   = `AXI4_BURST_SIZE_4BYTES;
  assign axi4.awburst  = `AXI4_BURST_TYPE_INCR;
  assign axi4.awlock   = `AXI4_LOCK_NORM;
  assign axi4.awcache  = `AXI4_CACHE_NO_BUF;
  assign axi4.awprot   = `AXI4_PROT_PRIVILEGED | `AXI4_PROT_DATA;
  assign axi4.awqos    = `AXI4_QOS_NORMAL;
  assign axi4.awregion = `AXI4_REGION_NORMAL;
  assign axi4.awuser   = '0;
  assign axi4.awvalid  = (s_fsm_q == FSM_WRITE) && !s_aw_done_q;
  assign axi4.wdata    = s_wdata;
  assign axi4.wstrb    = s_wstrb;
  assign axi4.wlast    = 1'b1;
  assign axi4.wuser    = '0;
  assign axi4.wvalid   = (s_fsm_q == FSM_WRITE) && !s_w_done_q;
  assign axi4.bready   = (s_fsm_q == FSM_WRITE_RESP);

  assign axi4.arid     = '0;
  assign axi4.araddr   = {s_addr_q[31:2], 2'b00};
  assign axi4.arlen    = 8'd0;
  assign axi4.arsize   = `AXI4_BURST_SIZE_4BYTES;
  assign axi4.arburst  = `AXI4_BURST_TYPE_INCR;
  assign axi4.arlock   = `AXI4_LOCK_NORM;
  assign axi4.arcache  = `AXI4_CACHE_NO_BUF;
  assign axi4.arprot   = `AXI4_PROT_PRIVILEGED | `AXI4_PROT_DATA;
  assign axi4.arqos    = `AXI4_QOS_NORMAL;
  assign axi4.arregion = `AXI4_REGION_NORMAL;
  assign axi4.aruser   = '0;
  assign axi4.arvalid  = (s_fsm_q == FSM_READ);
  assign axi4.rready   = (s_fsm_q == FSM_READ_RESP);

  always_comb begin
    s_fsm_d     = s_fsm_q;
    s_addr_d    = s_addr_q;
    s_write_d   = s_write_q;
    s_size_d    = s_size_q;
    s_aw_done_d = s_aw_done_q;
    s_w_done_d  = s_w_done_q;

    if (s_fsm_q == FSM_IDLE || s_terminal) begin
      s_aw_done_d = 1'b0;
      s_w_done_d  = 1'b0;
      if (ahbl.htrans == AHBL_TRANS_NSEQ) begin
        s_addr_d  = ahbl.haddr;
        s_write_d = ahbl.hwrite;
        s_size_d  = ahbl.hsize;
        s_fsm_d   = ahbl.hwrite ? FSM_WRITE : FSM_READ;
      end else begin
        s_fsm_d = FSM_IDLE;
      end
    end else begin
      unique case (s_fsm_q)
        FSM_WRITE: begin
          if (axi4.awvalid && axi4.awready) s_aw_done_d = 1'b1;
          if (axi4.wvalid && axi4.wready) s_w_done_d = 1'b1;
          if ((s_aw_done_q || (axi4.awvalid && axi4.awready)) &&
              (s_w_done_q || (axi4.wvalid && axi4.wready))) begin
            s_fsm_d = FSM_WRITE_RESP;
          end
        end
        FSM_READ: begin
          if (axi4.arvalid && axi4.arready) s_fsm_d = FSM_READ_RESP;
        end
        default: begin
        end
      endcase
    end
  end

  dffr #(
      .DATA_WIDTH(3)
  ) u_fsm_dffr (
      .clk_i  (ahbl.hclk),
      .rst_n_i(ahbl.hresetn),
      .dat_i  (s_fsm_d),
      .dat_o  (s_fsm_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_addr_dffr (
      .clk_i  (ahbl.hclk),
      .rst_n_i(ahbl.hresetn),
      .dat_i  (s_addr_d),
      .dat_o  (s_addr_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_write_dffr (
      .clk_i  (ahbl.hclk),
      .rst_n_i(ahbl.hresetn),
      .dat_i  (s_write_d),
      .dat_o  (s_write_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_size_dffr (
      .clk_i  (ahbl.hclk),
      .rst_n_i(ahbl.hresetn),
      .dat_i  (s_size_d),
      .dat_o  (s_size_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_aw_done_dffr (
      .clk_i  (ahbl.hclk),
      .rst_n_i(ahbl.hresetn),
      .dat_i  (s_aw_done_d),
      .dat_o  (s_aw_done_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_w_done_dffr (
      .clk_i  (ahbl.hclk),
      .rst_n_i(ahbl.hresetn),
      .dat_i  (s_w_done_d),
      .dat_o  (s_w_done_q)
  );
endmodule
