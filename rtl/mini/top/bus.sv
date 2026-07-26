// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "mmap_define.svh"

module bus (
    // verilog_format: off
    input  logic  clk_i,
    input  logic  rst_n_i,
`ifdef HAVE_SRAM_IF
    ram_if.master ram,
`endif
    nmi_if.slave  mgmt_nmi,
    nmi_if.slave  user_nmi,
    nmi_if.slave  dma_nmi,
    input  logic  user_bus_enable_i,
    output logic  user_bus_idle_o,
    nmi_if.master natv_nmi,
    nmi_if.master apb_nmi,
    output logic  fault_valid_o,
    output logic [31:0] fault_addr_o,
    output logic [3:0]  fault_wstrb_o,
    output logic        fault_reserved_o,
    output logic        fault_access_o,
    output logic [1:0]  fault_master_o
    // verilog_format: on
);

  localparam logic [1:0] MSTR_MGMT = 2'd0;
  localparam logic [1:0] MSTR_USER = 2'd1;
  localparam logic [1:0] MSTR_DMA = 2'd2;

  logic s_natv_sel, s_apb_sel, s_ram_sel, s_fault_sel, s_access_denied;
  logic s_ram_valid, s_ram_ready;
  logic s_mstr_lock_d, s_mstr_lock_q;
  logic [1:0] s_mstr_id_d, s_mstr_id_q;
  logic [1:0] s_mstr_rr_d, s_mstr_rr_q;
  logic s_user_request;
  logic s_user_access_allowed;
  nmi_if u_mstr_nmi_if ();
  nmi_if u_mstr_rgsl_nmi_if ();

  assign s_user_request  = user_bus_enable_i && user_nmi.valid;
  assign user_bus_idle_o = ~s_mstr_lock_q || s_mstr_id_q != MSTR_USER;

  always_comb begin
    s_mstr_lock_d = s_mstr_lock_q;
    s_mstr_id_d   = s_mstr_id_q;
    s_mstr_rr_d   = s_mstr_rr_q;
    if (~s_mstr_lock_q) begin
      unique case (s_mstr_rr_q)
        MSTR_MGMT: begin
          if (mgmt_nmi.valid) begin
            s_mstr_lock_d = 1'b1;
            s_mstr_id_d   = MSTR_MGMT;
          end else if (s_user_request) begin
            s_mstr_lock_d = 1'b1;
            s_mstr_id_d   = MSTR_USER;
          end else if (dma_nmi.valid) begin
            s_mstr_lock_d = 1'b1;
            s_mstr_id_d   = MSTR_DMA;
          end
        end
        MSTR_USER: begin
          if (s_user_request) begin
            s_mstr_lock_d = 1'b1;
            s_mstr_id_d   = MSTR_USER;
          end else if (dma_nmi.valid) begin
            s_mstr_lock_d = 1'b1;
            s_mstr_id_d   = MSTR_DMA;
          end else if (mgmt_nmi.valid) begin
            s_mstr_lock_d = 1'b1;
            s_mstr_id_d   = MSTR_MGMT;
          end
        end
        default: begin
          if (dma_nmi.valid) begin
            s_mstr_lock_d = 1'b1;
            s_mstr_id_d   = MSTR_DMA;
          end else if (mgmt_nmi.valid) begin
            s_mstr_lock_d = 1'b1;
            s_mstr_id_d   = MSTR_MGMT;
          end else if (s_user_request) begin
            s_mstr_lock_d = 1'b1;
            s_mstr_id_d   = MSTR_USER;
          end
        end
      endcase
    end else if (u_mstr_nmi_if.ready) begin
      s_mstr_lock_d = 1'b0;
      unique case (s_mstr_id_q)
        MSTR_MGMT: s_mstr_rr_d = MSTR_USER;
        MSTR_USER: s_mstr_rr_d = MSTR_DMA;
        default:   s_mstr_rr_d = MSTR_MGMT;
      endcase
    end
  end
  dffr #(1) u_mstr_lock_dffr (
      clk_i,
      rst_n_i,
      s_mstr_lock_d,
      s_mstr_lock_q
  );
  dffr #(2) u_mstr_id_dffr (
      clk_i,
      rst_n_i,
      s_mstr_id_d,
      s_mstr_id_q
  );
  dffr #(2) u_mstr_rr_dffr (
      clk_i,
      rst_n_i,
      s_mstr_rr_d,
      s_mstr_rr_q
  );

  // The owner is locked from request acceptance through its response.
  // verilog_format: off
  assign u_mstr_nmi_if.valid = s_mstr_lock_q && (s_mstr_id_q == MSTR_MGMT ? mgmt_nmi.valid :
                                                  s_mstr_id_q == MSTR_USER ? user_nmi.valid :
                                                                               dma_nmi.valid);
  assign u_mstr_nmi_if.addr  = s_mstr_id_q == MSTR_MGMT ? mgmt_nmi.addr :
                              s_mstr_id_q == MSTR_USER ? user_nmi.addr : dma_nmi.addr;
  assign u_mstr_nmi_if.wdata = s_mstr_id_q == MSTR_MGMT ? mgmt_nmi.wdata :
                              s_mstr_id_q == MSTR_USER ? user_nmi.wdata : dma_nmi.wdata;
  assign u_mstr_nmi_if.wstrb = s_mstr_id_q == MSTR_MGMT ? mgmt_nmi.wstrb :
                              s_mstr_id_q == MSTR_USER ? user_nmi.wstrb : dma_nmi.wstrb;

  assign mgmt_nmi.ready      = s_mstr_lock_q && s_mstr_id_q == MSTR_MGMT ? u_mstr_nmi_if.ready : '0;
  assign mgmt_nmi.rdata      = s_mstr_lock_q && s_mstr_id_q == MSTR_MGMT ? u_mstr_nmi_if.rdata : '0;
  assign user_nmi.ready      = s_mstr_lock_q && s_mstr_id_q == MSTR_USER ? u_mstr_nmi_if.ready : '0;
  assign user_nmi.rdata      = s_mstr_lock_q && s_mstr_id_q == MSTR_USER ? u_mstr_nmi_if.rdata : '0;
  assign dma_nmi.ready       = s_mstr_lock_q && s_mstr_id_q == MSTR_DMA ? u_mstr_nmi_if.ready : '0;
  assign dma_nmi.rdata       = s_mstr_lock_q && s_mstr_id_q == MSTR_DMA ? u_mstr_nmi_if.rdata : '0;
  // verilog_format: on

  nmi_regslice u_nmi_regslice (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi_slv(u_mstr_nmi_if),
      .nmi_mst(u_mstr_rgsl_nmi_if)
  );

  assign s_user_access_allowed = |u_mstr_rgsl_nmi_if.wstrb ?
      `SOC_USER_ADDR_WRITABLE(u_mstr_rgsl_nmi_if.addr) :
      `SOC_USER_ADDR_READABLE(u_mstr_rgsl_nmi_if.addr);
  assign s_access_denied = u_mstr_rgsl_nmi_if.valid && s_mstr_id_q == MSTR_USER &&
                           ~s_user_access_allowed;

  // Address ownership comes from the generated address map. User requests are
  // filtered before any target observes valid.
  // verilog_format: off
  assign s_natv_sel      = `SOC_ADDR_IS_NATIVE(u_mstr_rgsl_nmi_if.addr) && ~s_access_denied;
  assign natv_nmi.valid  = u_mstr_rgsl_nmi_if.valid && s_natv_sel;
  assign natv_nmi.addr   = u_mstr_rgsl_nmi_if.addr;
  assign natv_nmi.wdata  = u_mstr_rgsl_nmi_if.wdata;
  assign natv_nmi.wstrb  = u_mstr_rgsl_nmi_if.wstrb;

  assign s_apb_sel       = `SOC_ADDR_IS_APB(u_mstr_rgsl_nmi_if.addr) && ~s_access_denied;
  assign apb_nmi.valid   = u_mstr_rgsl_nmi_if.valid && s_apb_sel;
  assign apb_nmi.addr    = u_mstr_rgsl_nmi_if.addr;
  assign apb_nmi.wdata   = u_mstr_rgsl_nmi_if.wdata;
  assign apb_nmi.wstrb   = u_mstr_rgsl_nmi_if.wstrb;

`ifdef HAVE_SRAM_IF
  assign s_ram_sel     = `SOC_ADDR_IS_RAM(u_mstr_rgsl_nmi_if.addr) && ~s_access_denied;
  assign s_ram_valid   = u_mstr_rgsl_nmi_if.valid && s_ram_sel;
  assign ram.addr      = u_mstr_rgsl_nmi_if.addr[16:2];
  assign ram.wdata     = u_mstr_rgsl_nmi_if.wdata;
  assign ram.wstrb     = s_ram_valid ? u_mstr_rgsl_nmi_if.wstrb : '0;
`else
  assign s_ram_sel     = 1'b0;
`endif

  assign s_fault_sel      = u_mstr_rgsl_nmi_if.valid &&
                            (s_access_denied || ~(s_natv_sel || s_apb_sel || s_ram_sel));
  assign fault_valid_o    = s_fault_sel;
  assign fault_addr_o     = u_mstr_rgsl_nmi_if.addr;
  assign fault_wstrb_o    = u_mstr_rgsl_nmi_if.wstrb;
  assign fault_reserved_o = `SOC_ADDR_IS_RESERVED(u_mstr_rgsl_nmi_if.addr);
  assign fault_access_o   = s_access_denied;
  assign fault_master_o   = s_mstr_id_q;
  // verilog_format: on

`ifdef HAVE_SRAM_MACRO
  dffr #(1) u_ram_ready_dffr (
      clk_i,
      rst_n_i,
      s_ram_valid,
      s_ram_ready
  );
`endif

  // verilog_format: off
`ifdef HAVE_SRAM_IF
  assign u_mstr_rgsl_nmi_if.ready = s_access_denied || (natv_nmi.valid && natv_nmi.ready) ||
                                    (apb_nmi.valid && apb_nmi.ready) || s_ram_ready || s_fault_sel;
`else
  assign u_mstr_rgsl_nmi_if.ready = s_access_denied || (natv_nmi.valid && natv_nmi.ready) ||
                                    (apb_nmi.valid && apb_nmi.ready) || s_fault_sel;
`endif

`ifdef HAVE_SRAM_IF
  assign u_mstr_rgsl_nmi_if.rdata = s_access_denied ? '0 :
                                    (natv_nmi.valid && natv_nmi.ready) ? natv_nmi.rdata :
                                    (apb_nmi.valid && apb_nmi.ready) ? apb_nmi.rdata :
                                    s_ram_ready ? ram.rdata : '0;
`else
  assign u_mstr_rgsl_nmi_if.rdata = s_access_denied ? '0 :
                                    (natv_nmi.valid && natv_nmi.ready) ? natv_nmi.rdata :
                                    (apb_nmi.valid && apb_nmi.ready) ? apb_nmi.rdata : '0;
`endif
  // verilog_format: on

endmodule
