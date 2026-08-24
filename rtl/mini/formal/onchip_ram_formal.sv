// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module onchip_ram_formal_design (
    // verilog_format: off -- preserve AXI channel grouping
    input  logic        clk_i,
    output logic        rst_n_i,
    output logic        f_past_valid,
    output logic        awvalid,
    output logic        awready,
    output logic [31:0] awaddr,
    output logic [7:0]  awlen,
    output logic [2:0]  awsize,
    output logic [1:0]  awburst,
    output logic        wvalid,
    output logic        wready,
    output logic [31:0] wdata,
    output logic [3:0]  wstrb,
    output logic        wlast,
    output logic        bvalid,
    output logic        bready,
    output logic [1:0]  bresp,
    output logic        arvalid,
    output logic        arready,
    output logic [31:0] araddr,
    output logic [7:0]  arlen,
    output logic [2:0]  arsize,
    output logic [1:0]  arburst,
    output logic        rvalid,
    output logic        rready,
    output logic [31:0] rdata,
    output logic [1:0]  rresp,
    output logic        rlast,
    output logic        memory_read,
    output logic        memory_write,
    output logic [14:0] memory_word_addr,
    output logic [3:0]  memory_write_strobe
    // verilog_format: on
);
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) mem_axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  apb4_if cfg_apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );

  (* anyseq *)logic        f_awvalid;
  (* anyseq *)logic [31:0] f_awaddr;
  (* anyseq *)logic [ 7:0] f_awlen;
  (* anyseq *)logic [ 2:0] f_awsize;
  (* anyseq *)logic [ 1:0] f_awburst;
  (* anyseq *)logic        f_awlock;
  (* anyseq *)logic        f_wvalid;
  (* anyseq *)logic [31:0] f_wdata;
  (* anyseq *)logic [ 3:0] f_wstrb;
  (* anyseq *)logic        f_wlast;
  (* anyseq *)logic        f_bready;
  (* anyseq *)logic        f_arvalid;
  (* anyseq *)logic [31:0] f_araddr;
  (* anyseq *)logic [ 7:0] f_arlen;
  (* anyseq *)logic [ 2:0] f_arsize;
  (* anyseq *)logic [ 1:0] f_arburst;
  (* anyseq *)logic        f_arlock;
  (* anyseq *)logic        f_rready;

  assign mem_axi4.awid     = 1'b0;
  assign mem_axi4.awaddr   = f_awaddr;
  assign mem_axi4.awlen    = f_awlen;
  assign mem_axi4.awsize   = f_awsize;
  assign mem_axi4.awburst  = f_awburst;
  assign mem_axi4.awlock   = f_awlock;
  assign mem_axi4.awcache  = '0;
  assign mem_axi4.awprot   = '0;
  assign mem_axi4.awqos    = '0;
  assign mem_axi4.awregion = '0;
  assign mem_axi4.awuser   = '0;
  assign mem_axi4.awvalid  = f_awvalid;
  assign mem_axi4.wdata    = f_wdata;
  assign mem_axi4.wstrb    = f_wstrb;
  assign mem_axi4.wlast    = f_wlast;
  assign mem_axi4.wuser    = '0;
  assign mem_axi4.wvalid   = f_wvalid;
  assign mem_axi4.bready   = f_bready;
  assign mem_axi4.arid     = 1'b0;
  assign mem_axi4.araddr   = f_araddr;
  assign mem_axi4.arlen    = f_arlen;
  assign mem_axi4.arsize   = f_arsize;
  assign mem_axi4.arburst  = f_arburst;
  assign mem_axi4.arlock   = f_arlock;
  assign mem_axi4.arcache  = '0;
  assign mem_axi4.arprot   = '0;
  assign mem_axi4.arqos    = '0;
  assign mem_axi4.arregion = '0;
  assign mem_axi4.aruser   = '0;
  assign mem_axi4.arvalid  = f_arvalid;
  assign mem_axi4.rready   = f_rready;

  assign cfg_apb4.paddr    = '0;
  assign cfg_apb4.pprot    = '0;
  assign cfg_apb4.psel     = 1'b0;
  assign cfg_apb4.penable  = 1'b0;
  assign cfg_apb4.pwrite   = 1'b0;
  assign cfg_apb4.pwdata   = '0;
  assign cfg_apb4.pstrb    = '0;

  assign awvalid           = mem_axi4.awvalid;
  assign awready           = mem_axi4.awready;
  assign awaddr            = mem_axi4.awaddr;
  assign awlen             = mem_axi4.awlen;
  assign awsize            = mem_axi4.awsize;
  assign awburst           = mem_axi4.awburst;
  assign wvalid            = mem_axi4.wvalid;
  assign wready            = mem_axi4.wready;
  assign wdata             = mem_axi4.wdata;
  assign wstrb             = mem_axi4.wstrb;
  assign wlast             = mem_axi4.wlast;
  assign bvalid            = mem_axi4.bvalid;
  assign bready            = mem_axi4.bready;
  assign bresp             = mem_axi4.bresp;
  assign arvalid           = mem_axi4.arvalid;
  assign arready           = mem_axi4.arready;
  assign araddr            = mem_axi4.araddr;
  assign arlen             = mem_axi4.arlen;
  assign arsize            = mem_axi4.arsize;
  assign arburst           = mem_axi4.arburst;
  assign rvalid            = mem_axi4.rvalid;
  assign rready            = mem_axi4.rready;
  assign rdata             = mem_axi4.rdata;
  assign rresp             = mem_axi4.rresp;
  assign rlast             = mem_axi4.rlast;

  onchip_ram #(
      .Present    (1'b1),
      .CapacityKiB(4)
  ) u_dut (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .perf_enable_i(1'b1),
      .perf_clear_i (1'b0),
      .mem_axi4     (mem_axi4),
      .cfg_apb4     (cfg_apb4)
  );

  assign memory_read         = u_dut.s_mem_read;
  assign memory_write        = u_dut.s_mem_write;
  assign memory_word_addr    = u_dut.s_mem_word_addr;
  assign memory_write_strobe = u_dut.s_mem_wstrb;

  initial begin
    rst_n_i      = 1'b0;
    f_past_valid = 1'b0;
  end

  always_ff @(posedge clk_i) begin
    rst_n_i      <= 1'b1;
    f_past_valid <= 1'b1;
  end
endmodule
