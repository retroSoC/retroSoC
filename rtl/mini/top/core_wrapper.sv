// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "mmap_define.svh"
`include "mdd_config.svh"

module core_wrapper (
    // verilog_format: off
    input logic                           clk_i,
    input logic                           rst_n_i,
    input logic [31:0]                    irq_i,
`ifdef CORE_MDD
    input logic [`USER_CORESEL_WIDTH-1:0] core_sel_i,
`endif
    nmi_if.master                         nmi
    // verilog_format: on
);

`ifdef CORE_PICORV32
  picorv32 #(
      .BARREL_SHIFTER (1),
      .COMPRESSED_ISA (1),
      .ENABLE_MUL     (1),
      .ENABLE_FAST_MUL(1),
      .ENABLE_DIV     (1),
      .ENABLE_IRQ     (0),
      .PROGADDR_RESET (`FLASH_START_ADDR),
      .PROGADDR_IRQ   (`IRQ_HANDLER_START_ADDR)
  ) u_picorv32 (
      .clk         (clk_i),
      .resetn      (rst_n_i),
      .trap        (),
      .mem_valid   (nmi.valid),
      .mem_instr   (),
      .mem_addr    (nmi.addr),
      .mem_wdata   (nmi.wdata),
      .mem_wstrb   (nmi.wstrb),
      .mem_rdata   (nmi.rdata),
      .mem_ready   (nmi.ready),
      .mem_la_read (),
      .mem_la_write(),
      .mem_la_addr (),
      .mem_la_wdata(),
      .mem_la_wstrb(),
      .pcpi_valid  (),
      .pcpi_insn   (),
      .pcpi_rs1    (),
      .pcpi_rs2    (),
      .pcpi_wr     (),
      .pcpi_rd     (),
      .pcpi_wait   (),
      .pcpi_ready  (),
      .irq         (irq_i),
      .eoi         (),
      .trace_valid (),
      .trace_data  ()
  );
// `elsif CORE_KIANV
//   kianv_harris_mc_edition #(
//       .RESET_ADDR(`FLASH_START_ADDR),
//       .RV32E     (0)
//   ) u_kianv_harris_mc_edition (
//       .clk      (clk_i),
//       .resetn   (rst_n_i),
//       .mem_valid(nmi.valid),
//       .mem_ready(nmi.ready),
//       .mem_wstrb(nmi.wstrb),
//       .mem_addr (nmi.addr),
//       .mem_wdata(nmi.wdata),
//       .mem_rdata(nmi.rdata)
//   );

// `elsif CORE_MINIRV
//   logic [31:0] s_awaddr;
//   logic        s_awvalid;
//   logic        s_awready;
//   logic [31:0] s_wdata;
//   logic [ 3:0] s_wstrb;
//   logic        s_wvalid;
//   logic        s_wready;
//   logic [ 1:0] s_bresp;
//   logic        s_bvalid;
//   logic        s_bready;
//   logic [31:0] s_araddr;
//   logic        s_arvalid;
//   logic        s_arready;
//   logic [31:0] s_rdata;
//   logic [ 1:0] s_rresp;
//   logic        s_rvalid;
//   logic        s_rready;

//   logic [31:0] s_remap_awaddr;
//   logic [31:0] s_remap_araddr;

//   // 0x20000 * 5
//   logic [18:0] s_delay_rst_cnt_d;
//   logic [18:0] s_delay_rst_cnt_q;
//   logic        s_delay_rst_n;

//   assign s_delay_rst_n     = s_delay_rst_cnt_q == '1;
//   assign s_delay_rst_cnt_d = s_delay_rst_cnt_q + 1'b1;
//   dffer #(19) u_delay_rst_cnt_dffer (
//       clk_i,
//       rst_n_i,
//       ~s_delay_rst_n,
//       s_delay_rst_cnt_d,
//       s_delay_rst_cnt_q
//   );


//   minirv u_minirv (
//       .clock            (clk_i),
//       .reset            (~s_delay_rst_n),
//       .io_master_awready(s_awready),
//       .io_master_awvalid(s_awvalid),
//       .io_master_awaddr (s_awaddr),
//       .io_master_awsize (),
//       .io_master_awid   (),
//       .io_master_awlen  (),
//       .io_master_awburst(),
//       .io_master_wready (s_wready),
//       .io_master_wvalid (s_wvalid),
//       .io_master_wdata  (s_wdata),
//       .io_master_wstrb  (s_wstrb),
//       .io_master_wlast  (),
//       .io_master_bready (s_bready),
//       .io_master_bvalid (s_bvalid),
//       .io_master_bresp  (s_bresp),
//       .io_master_bid    (),
//       .io_master_arready(s_arready),
//       .io_master_arvalid(s_arvalid),
//       .io_master_araddr (s_araddr),
//       .io_master_arsize (),
//       .io_master_arid   (),
//       .io_master_arlen  (),
//       .io_master_arburst(),
//       .io_master_rready (s_rready),
//       .io_master_rvalid (s_rvalid),
//       .io_master_rresp  (s_rresp),
//       .io_master_rdata  (s_rdata),
//       .io_master_rlast  (),
//       .io_master_rid    (),
//       .io_interrupt     (|irq_i)
//   );

//   axi4l2nmi u_axi4l2nmi (
//       .aclk_i     (clk_i),
//       .aresetn_i  (s_delay_rst_n),
//       .awaddr_i   (s_remap_awaddr),
//       .awvalid_i  (s_awvalid),
//       .awready_o  (s_awready),
//       .wdata_i    (s_wdata),
//       .wstrb_i    (s_wstrb),
//       .wvalid_i   (s_wvalid),
//       .wready_o   (s_wready),
//       .bresp_o    (s_bresp),
//       .bvalid_o   (s_bvalid),
//       .bready_i   (s_bready),
//       .araddr_i   (s_remap_araddr),
//       .arvalid_i  (s_arvalid),
//       .arready_o  (s_arready),
//       .rdata_o    (s_rdata),
//       .rresp_o    (s_rresp),
//       .rvalid_o   (s_rvalid),
//       .rready_i   (s_rready),
//       .mem_valid_o(nmi.valid),
//       .mem_instr_o(),
//       .mem_addr_o (nmi.addr),
//       .mem_wdata_o(nmi.wdata),
//       .mem_wstrb_o(nmi.wstrb),
//       .mem_ready_i(nmi.ready),
//       .mem_rdata_i(nmi.rdata)
//   );

//   always_comb begin
//     s_remap_awaddr = s_awaddr;
//     if (s_awaddr[31:24] == 8'h30) begin
//       s_remap_awaddr = {8'h00, s_awaddr[23:0]};
//     end else if (s_awaddr[31:24] == 8'ha0) begin
//       s_remap_awaddr = {8'h40, s_awaddr[23:0]};
//     end
//   end

//   always_comb begin
//     s_remap_araddr = s_araddr;
//     if (s_araddr[31:24] == 8'h30) begin
//       s_remap_araddr = {8'h00, s_araddr[23:0]};
//     end else if (s_araddr[31:24] == 8'ha0) begin
//       s_remap_araddr = {8'h40, s_araddr[23:0]};
//     end
//   end

`elsif CORE_MDD
  user_core_wrapper u_user_core_wrapper (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .sel_i       (core_sel_i),
      .core_valid_o(nmi.valid),
      .core_addr_o (nmi.addr),
      .core_wdata_o(nmi.wdata),
      .core_wstrb_o(nmi.wstrb),
      .core_rdata_i(nmi.rdata),
      .core_ready_i(nmi.ready),
      .irq_i       (irq_i)
  );

`endif

endmodule
