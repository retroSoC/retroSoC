// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module bus_formal_design (
    input  logic        clk_i,
    output logic        rst_n_i,
    output logic        f_past_valid,
    output logic        core_valid,
    output logic [31:0] core_addr,
    output logic [31:0] core_wdata,
    output logic [ 3:0] core_wstrb,
    output logic        core_ready,
    output logic        dma_valid,
    output logic [31:0] dma_addr,
    output logic [31:0] dma_wdata,
    output logic [ 3:0] dma_wstrb,
    output logic        dma_ready,
    output logic        natv_valid,
    output logic        apb_valid,
    output logic        fault_valid,
    output logic        fault_reserved,
    output logic        fault_sel,
    output logic        arb_locked,
    output logic        arb_dma_owner
);

  nmi_if core_nmi ();
  nmi_if dma_nmi ();
  nmi_if natv_nmi ();
  nmi_if apb_nmi ();

  (* anyseq *)logic        f_core_valid;
  (* anyseq *)logic [31:0] f_core_addr;
  (* anyseq *)logic [31:0] f_core_wdata;
  (* anyseq *)logic [ 3:0] f_core_wstrb;
  (* anyseq *)logic        f_dma_valid;
  (* anyseq *)logic [31:0] f_dma_addr;
  (* anyseq *)logic [31:0] f_dma_wdata;
  (* anyseq *)logic [ 3:0] f_dma_wstrb;
  (* anyseq *)logic        f_natv_ready;
  (* anyseq *)logic [31:0] f_natv_rdata;
  (* anyseq *)logic        f_apb_ready;
  (* anyseq *)logic [31:0] f_apb_rdata;
  logic [31:0] fault_addr;
  logic [ 3:0] fault_wstrb;

  assign core_nmi.valid = f_core_valid;
  assign core_nmi.addr  = f_core_addr;
  assign core_nmi.wdata = f_core_wdata;
  assign core_nmi.wstrb = f_core_wstrb;
  assign dma_nmi.valid  = f_dma_valid;
  assign dma_nmi.addr   = f_dma_addr;
  assign dma_nmi.wdata  = f_dma_wdata;
  assign dma_nmi.wstrb  = f_dma_wstrb;
  assign natv_nmi.ready = f_natv_ready;
  assign natv_nmi.rdata = f_natv_rdata;
  assign apb_nmi.ready  = f_apb_ready;
  assign apb_nmi.rdata  = f_apb_rdata;

  assign core_valid     = core_nmi.valid;
  assign core_addr      = core_nmi.addr;
  assign core_wdata     = core_nmi.wdata;
  assign core_wstrb     = core_nmi.wstrb;
  assign core_ready     = core_nmi.ready;
  assign dma_valid      = dma_nmi.valid;
  assign dma_addr       = dma_nmi.addr;
  assign dma_wdata      = dma_nmi.wdata;
  assign dma_wstrb      = dma_nmi.wstrb;
  assign dma_ready      = dma_nmi.ready;
  assign natv_valid     = natv_nmi.valid;
  assign apb_valid      = apb_nmi.valid;

  bus u_dut (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .core_nmi        (core_nmi),
      .dma_nmi         (dma_nmi),
      .natv_nmi        (natv_nmi),
      .apb_nmi         (apb_nmi),
      .fault_valid_o   (fault_valid),
      .fault_addr_o    (fault_addr),
      .fault_wstrb_o   (fault_wstrb),
      .fault_reserved_o(fault_reserved)
  );

  assign fault_sel     = u_dut.s_fault_sel;
  assign arb_locked    = u_dut.s_mstr_lock_q;
  assign arb_dma_owner = u_dut.s_mstr_id_q;

  initial begin
    rst_n_i      = 1'b0;
    f_past_valid = 1'b0;
  end

  always_ff @(posedge clk_i) begin
    rst_n_i      <= 1'b1;
    f_past_valid <= 1'b1;
  end

endmodule
