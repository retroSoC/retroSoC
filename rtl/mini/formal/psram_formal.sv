// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module psram_formal_design (
    // verilog_format: off -- preserve reviewed port alignment
    input  logic          clk_i,
    output logic          rst_n_i,
    output logic          f_past_valid,
    output logic          awvalid,
    output logic          awready,
    output logic [31:0]   awaddr,
    output logic [7:0]    awlen,
    output logic [2:0]    awsize,
    output logic [1:0]    awburst,
    output logic          wvalid,
    output logic          wready,
    output logic [31:0]   wdata,
    output logic [3:0]    wstrb,
    output logic          wlast,
    output logic          bvalid,
    output logic          bready,
    output logic [1:0]    bresp,
    output logic          arvalid,
    output logic          arready,
    output logic [31:0]   araddr,
    output logic [7:0]    arlen,
    output logic [2:0]    arsize,
    output logic [1:0]    arburst,
    output logic          rvalid,
    output logic          rready,
    output logic [31:0]   rdata,
    output logic [1:0]    rresp,
    output logic          rlast,
    output logic          mem_req_valid,
    output logic          mem_req_ready,
    output logic          mem_req_write,
    output logic [1:0]    mem_req_chip,
    output logic [22:0]   mem_req_addr,
    output logic [2:0]    mem_req_len,
    output logic [31:0]   mem_req_wdata,
    output logic          phy_abort,
    output logic          phy_req_valid,
    output logic          phy_req_ready,
    output logic [3:0]    phy_req_cmd,
    output logic [1:0]    phy_req_chip,
    output logic          phy_req_qpi,
    output logic [22:0]   phy_req_addr,
    output logic [5:0]    phy_req_len,
    output logic [63:0]   phy_req_wdata,
    output logic          phy_busy,
    output logic          phy_done,
    output logic          phy_error,
    output logic          phy_sclk,
    output logic [3:0]    phy_nss,
    output logic [3:0]    phy_io_oe,
    output logic [3:0]    phy_io_do
    // verilog_format: on
);

  import psram_pkg::*;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  (* anyseq *)logic              f_awvalid;
  (* anyseq *)logic       [31:0] f_awaddr;
  (* anyseq *)logic       [ 7:0] f_awlen;
  (* anyseq *)logic       [ 2:0] f_awsize;
  (* anyseq *)logic       [ 1:0] f_awburst;
  (* anyseq *)logic              f_awlock;
  (* anyseq *)logic              f_wvalid;
  (* anyseq *)logic       [31:0] f_wdata;
  (* anyseq *)logic       [ 3:0] f_wstrb;
  (* anyseq *)logic              f_wlast;
  (* anyseq *)logic              f_bready;
  (* anyseq *)logic              f_arvalid;
  (* anyseq *)logic       [31:0] f_araddr;
  (* anyseq *)logic       [ 7:0] f_arlen;
  (* anyseq *)logic       [ 2:0] f_arsize;
  (* anyseq *)logic       [ 1:0] f_arburst;
  (* anyseq *)logic              f_arlock;
  (* anyseq *)logic              f_rready;
  (* anyseq *)logic              f_mem_rsp_error;
  (* anyseq *)logic       [31:0] f_mem_rsp_rdata;
  (* anyseq *)logic              f_phy_abort;
  (* anyseq *)logic              f_phy_req_valid;
  (* anyseq *)psram_cmd_e        f_phy_req_cmd;
  (* anyseq *)logic       [ 1:0] f_phy_req_chip;
  (* anyseq *)logic              f_phy_req_qpi;
  (* anyseq *)logic       [22:0] f_phy_req_addr;
  (* anyseq *)logic       [ 5:0] f_phy_req_len;
  (* anyseq *)logic       [63:0] f_phy_req_wdata;
  (* anyseq *)logic       [ 3:0] f_phy_io_di;

  logic              f_mem_rsp_valid_q;
  logic              mem_rsp_ready;

  assign axi4.awid     = 1'b0;
  assign axi4.awaddr   = f_awaddr;
  assign axi4.awlen    = f_awlen;
  assign axi4.awsize   = f_awsize;
  assign axi4.awburst  = f_awburst;
  assign axi4.awlock   = f_awlock;
  assign axi4.awcache  = '0;
  assign axi4.awprot   = '0;
  assign axi4.awqos    = '0;
  assign axi4.awregion = '0;
  assign axi4.awuser   = '0;
  assign axi4.awvalid  = f_awvalid;
  assign axi4.wdata    = f_wdata;
  assign axi4.wstrb    = f_wstrb;
  assign axi4.wlast    = f_wlast;
  assign axi4.wuser    = '0;
  assign axi4.wvalid   = f_wvalid;
  assign axi4.bready   = f_bready;
  assign axi4.arid     = 1'b0;
  assign axi4.araddr   = f_araddr;
  assign axi4.arlen    = f_arlen;
  assign axi4.arsize   = f_arsize;
  assign axi4.arburst  = f_arburst;
  assign axi4.arlock   = f_arlock;
  assign axi4.arcache  = '0;
  assign axi4.arprot   = '0;
  assign axi4.arqos    = '0;
  assign axi4.arregion = '0;
  assign axi4.aruser   = '0;
  assign axi4.arvalid  = f_arvalid;
  assign axi4.rready   = f_rready;

  assign awvalid       = axi4.awvalid;
  assign awready       = axi4.awready;
  assign awaddr        = axi4.awaddr;
  assign awlen         = axi4.awlen;
  assign awsize        = axi4.awsize;
  assign awburst       = axi4.awburst;
  assign wvalid        = axi4.wvalid;
  assign wready        = axi4.wready;
  assign wdata         = axi4.wdata;
  assign wstrb         = axi4.wstrb;
  assign wlast         = axi4.wlast;
  assign bvalid        = axi4.bvalid;
  assign bready        = axi4.bready;
  assign bresp         = axi4.bresp;
  assign arvalid       = axi4.arvalid;
  assign arready       = axi4.arready;
  assign araddr        = axi4.araddr;
  assign arlen         = axi4.arlen;
  assign arsize        = axi4.arsize;
  assign arburst       = axi4.arburst;
  assign rvalid        = axi4.rvalid;
  assign rready        = axi4.rready;
  assign rdata         = axi4.rdata;
  assign rresp         = axi4.rresp;
  assign rlast         = axi4.rlast;
  assign mem_req_ready = 1'b1;

  psram_axi4 u_axi4 (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .accept_enable_i(1'b1),
      .busy_o         (),
      .stall_event_o  (),
      .split_event_o  (),
      .axi4           (axi4),
      .mem_req_valid_o(mem_req_valid),
      .mem_req_ready_i(mem_req_ready),
      .mem_req_write_o(mem_req_write),
      .mem_req_chip_o (mem_req_chip),
      .mem_req_addr_o (mem_req_addr),
      .mem_req_len_o  (mem_req_len),
      .mem_req_wdata_o(mem_req_wdata),
      .mem_rsp_valid_i(f_mem_rsp_valid_q),
      .mem_rsp_ready_o(mem_rsp_ready),
      .mem_rsp_error_i(f_mem_rsp_error),
      .mem_rsp_rdata_i(f_mem_rsp_rdata)
  );

  assign phy_abort     = f_phy_abort;
  assign phy_req_valid = f_phy_req_valid;
  assign phy_req_cmd   = f_phy_req_cmd;
  assign phy_req_chip  = f_phy_req_chip;
  assign phy_req_qpi   = f_phy_req_qpi;
  assign phy_req_addr  = f_phy_req_addr;
  assign phy_req_len   = f_phy_req_len;
  assign phy_req_wdata = f_phy_req_wdata;
  psram_phy u_phy (
      .clk_i               (clk_i),
      .rst_n_i             (rst_n_i),
      .abort_i             (f_phy_abort),
      .req_valid_i         (f_phy_req_valid),
      .req_ready_o         (phy_req_ready),
      .req_command_i       (f_phy_req_cmd),
      .req_chip_i          (f_phy_req_chip),
      .req_qpi_i           (f_phy_req_qpi),
      .req_addr_i          (f_phy_req_addr),
      .req_length_i        (f_phy_req_len),
      .req_wdata_i         (f_phy_req_wdata),
      .busy_o              (phy_busy),
      .done_o              (phy_done),
      .error_o             (phy_error),
      .rdata_o             (),
      .cfg_half_period_i   (16'd1),
      .cfg_cs_setup_i      (16'd1),
      .cfg_cs_high_i       (16'd2),
      .cfg_cs_hold_i       (16'd2),
      .cfg_cs_max_low_i    (32'd200),
      .cfg_access_timeout_i(32'd200),
      .psram_sclk_o        (phy_sclk),
      .psram_nss_o         (phy_nss),
      .psram_io_oe_o       (phy_io_oe),
      .psram_io_di_i       (f_phy_io_di),
      .psram_io_do_o       (phy_io_do)
  );

  initial begin
    rst_n_i           = 1'b0;
    f_past_valid      = 1'b0;
    f_mem_rsp_valid_q = 1'b0;
  end

  always_ff @(posedge clk_i) begin
    rst_n_i      <= 1'b1;
    f_past_valid <= 1'b1;
    if (!rst_n_i) begin
      f_mem_rsp_valid_q <= 1'b0;
    end else begin
      if (mem_req_valid && mem_req_ready) f_mem_rsp_valid_q <= 1'b1;
      else if (f_mem_rsp_valid_q && mem_rsp_ready) f_mem_rsp_valid_q <= 1'b0;
    end
  end

endmodule
