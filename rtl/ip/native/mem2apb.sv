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

module mem2apb #(
`ifdef IP_MDD
    parameter APB_SLAVES_NUM = 9
`else
    parameter APB_SLAVES_NUM = 8
`endif
) (
    input  logic                      clk_i,
    input  logic                      rst_n_i,
    // mem if
    input  logic                      mem_valid_i,
    input  logic [              31:0] mem_addr_i,
    input  logic [              31:0] mem_wdata_i,
    input  logic [               3:0] mem_wstrb_i,
    output logic [              31:0] mem_rdata_o,
    output logic                      mem_ready_o,
    // apb if
    output logic [              31:0] apb_paddr_o,
    output logic [               2:0] apb_pprot_o,
    output logic [APB_SLAVES_NUM-1:0] apb_psel_o,
    output logic                      apb_penable_o,
    output logic                      apb_pwrite_o,
    output logic [              31:0] apb_pwdata_o,
    output logic [               3:0] apb_pstrb_o,
    input  logic [APB_SLAVES_NUM-1:0] apb_pready_i,
    input  logic [              31:0] apb_prdata0_i,
    input  logic [              31:0] apb_prdata1_i,
    input  logic [              31:0] apb_prdata2_i,
    input  logic [              31:0] apb_prdata3_i,
    input  logic [              31:0] apb_prdata4_i,
    input  logic [              31:0] apb_prdata5_i,
    input  logic [              31:0] apb_prdata6_i,
    input  logic [              31:0] apb_prdata7_i,
`ifdef IP_MDD
    input  logic [              31:0] apb_prdata8_i,
`endif
    input  logic [APB_SLAVES_NUM-1:0] apb_pslverr_i
);

  localparam FSM_IDLE = 2'd0;
  localparam FSM_SETUP = 2'd1;
  localparam FSM_ENABLE = 2'd2;

  logic [31:0] s_rd_data;
  logic s_xfer_valid, s_xfer_ready;
  logic s_mem_valid_re;
  logic [1:0] s_fsm_d, s_fsm_q;

  assign apb_psel_o[0] = s_xfer_valid && (mem_addr_i[31:24] == `CUST_IP_START && mem_addr_i[15:8] == 8'h10);
  assign apb_psel_o[1] = s_xfer_valid && (mem_addr_i[31:24] == `CUST_IP_START && mem_addr_i[15:8] == 8'h20);
  assign apb_psel_o[2] = s_xfer_valid && (mem_addr_i[31:24] == `CUST_IP_START && mem_addr_i[15:8] == 8'h30);
  assign apb_psel_o[3] = s_xfer_valid && (mem_addr_i[31:24] == `CUST_IP_START && mem_addr_i[15:8] == 8'h40);
  assign apb_psel_o[4] = s_xfer_valid && (mem_addr_i[31:24] == `CUST_IP_START && mem_addr_i[15:8] == 8'h50);
  assign apb_psel_o[5] = s_xfer_valid && (mem_addr_i[31:24] == `CUST_IP_START && mem_addr_i[15:8] == 8'h60);
  assign apb_psel_o[6] = s_xfer_valid && (mem_addr_i[31:24] == `CUST_IP_START && mem_addr_i[15:8] == 8'h70);
  assign apb_psel_o[7] = s_xfer_valid && (mem_addr_i[31:24] == `FLASH_START);
`ifdef IP_MDD
  assign apb_psel_o[8] = s_xfer_valid && (mem_addr_i[31:24] == `CUST_IP_START && mem_addr_i[15:8] == 8'hF0);
`endif
  assign apb_paddr_o   = mem_addr_i;
  assign apb_pwrite_o  = |mem_wstrb_i;
  assign apb_pwdata_o  = mem_wdata_i;
  assign apb_pstrb_o   = mem_wstrb_i;
  assign apb_pprot_o   = 3'd0;
  assign apb_penable_o = s_fsm_q == FSM_ENABLE;

  edge_det_sync_re #(1) u_mem_valid_edge_det_sync_re (
      clk_i,
      rst_n_i,
      mem_valid_i,
      s_mem_valid_re
  );

  assign s_xfer_valid = ((s_fsm_q == FSM_IDLE) && s_mem_valid_re) ||
                        (s_fsm_q == FSM_SETUP) || (s_fsm_q == FSM_ENABLE);

  always_comb begin
    s_fsm_d = s_fsm_q;
    unique case (s_fsm_q)
      FSM_IDLE: begin
        if (s_mem_valid_re) begin
          s_fsm_d = FSM_SETUP;
        end
      end
      FSM_SETUP: begin
        s_fsm_d = FSM_ENABLE;
      end
      FSM_ENABLE: begin
        if (s_xfer_ready) begin
          s_fsm_d = FSM_IDLE;
        end
      end
      default: begin
        s_fsm_d = s_fsm_q;
      end
    endcase
  end
  dffr #(2) u_fsm_dffr (
      clk_i,
      rst_n_i,
      s_fsm_d,
      s_fsm_q
  );

  assign mem_ready_o   = mem_valid_i && apb_penable_o && s_xfer_ready;
  assign mem_rdata_o   = {32{mem_ready_o}} & s_rd_data;

  // verilog_format: off
  assign s_rd_data = ({32{apb_psel_o[0]}} & apb_prdata0_i) |
                     ({32{apb_psel_o[1]}} & apb_prdata1_i) |
                     ({32{apb_psel_o[2]}} & apb_prdata2_i) |
                     ({32{apb_psel_o[3]}} & apb_prdata3_i) |
                     ({32{apb_psel_o[4]}} & apb_prdata4_i) |
                     ({32{apb_psel_o[5]}} & apb_prdata5_i) |
                     ({32{apb_psel_o[6]}} & apb_prdata6_i) |
`ifdef IP_MDD
                     ({32{apb_psel_o[8]}} & apb_prdata8_i) |
`endif
                     ({32{apb_psel_o[7]}} & apb_prdata7_i);

  assign s_xfer_ready = (apb_psel_o[0] & apb_pready_i[0]) |
                        (apb_psel_o[1] & apb_pready_i[1]) |
                        (apb_psel_o[2] & apb_pready_i[2]) |
                        (apb_psel_o[3] & apb_pready_i[3]) |
                        (apb_psel_o[4] & apb_pready_i[4]) |
                        (apb_psel_o[5] & apb_pready_i[5]) |
                        (apb_psel_o[6] & apb_pready_i[6]) |
`ifdef IP_MDD
                        (apb_psel_o[8] & apb_pready_i[8]) |
`endif
                        (apb_psel_o[7] & apb_pready_i[7]);
  // verilog_format: on

endmodule
