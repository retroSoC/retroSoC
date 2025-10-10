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

module mem2apb (
    // verilog_format: off
    input  logic       clk_i,
    input  logic       rst_n_i,
    nmi_if.slave       nmi,
`ifdef IP_MDD
    apb4_pure_if.master user_ip,
`endif
    apb4_pure_if.master archinfo,
    apb4_pure_if.master rng,
    apb4_pure_if.master uart,
    apb4_pure_if.master pwm,
    apb4_pure_if.master ps2,
    apb4_pure_if.master i2c,
    apb4_pure_if.master qspi,
    apb4_pure_if.master spfs
    // verilog_format: on
);

  localparam FSM_IDLE = 2'd0;
  localparam FSM_SETUP = 2'd1;
  localparam FSM_ENABLE = 2'd2;

  logic [31:0] s_rd_data;
  logic s_xfer_valid, s_xfer_ready;
  logic s_mem_valid_re;
  logic [1:0] s_fsm_d, s_fsm_q;


  // verilog_format: off
  assign archinfo.paddr   = nmi.addr;
  assign rng.paddr        = nmi.addr;
  assign uart.paddr       = nmi.addr;
  assign pwm.paddr        = nmi.addr;
  assign ps2.paddr        = nmi.addr;
  assign i2c.paddr        = nmi.addr;
  assign qspi.paddr       = nmi.addr;
  assign spfs.paddr       = nmi.addr;

  assign archinfo.pprot   = '0;
  assign rng.pprot        = '0;
  assign uart.pprot       = '0;
  assign pwm.pprot        = '0;
  assign ps2.pprot        = '0;
  assign i2c.pprot        = '0;
  assign qspi.pprot       = '0;
  assign spfs.pprot       = '0;

  assign archinfo.psel    = s_xfer_valid && (nmi.addr[31:24] == `APB_IP_START && nmi.addr[15:8] == 8'h10);
  assign rng.psel         = s_xfer_valid && (nmi.addr[31:24] == `APB_IP_START && nmi.addr[15:8] == 8'h20);
  assign uart.psel        = s_xfer_valid && (nmi.addr[31:24] == `APB_IP_START && nmi.addr[15:8] == 8'h30);
  assign pwm.psel         = s_xfer_valid && (nmi.addr[31:24] == `APB_IP_START && nmi.addr[15:8] == 8'h40);
  assign ps2.psel         = s_xfer_valid && (nmi.addr[31:24] == `APB_IP_START && nmi.addr[15:8] == 8'h50);
  assign i2c.psel         = s_xfer_valid && (nmi.addr[31:24] == `APB_IP_START && nmi.addr[15:8] == 8'h60);
  assign qspi.psel        = s_xfer_valid && (nmi.addr[31:24] == `APB_IP_START && nmi.addr[15:8] == 8'h70);
  assign spfs.psel        = s_xfer_valid && (nmi.addr[31:24] == `FLASH_START);

  assign archinfo.penable = s_fsm_q == FSM_ENABLE;
  assign rng.penable      = s_fsm_q == FSM_ENABLE;
  assign uart.penable     = s_fsm_q == FSM_ENABLE;
  assign pwm.penable      = s_fsm_q == FSM_ENABLE;
  assign ps2.penable      = s_fsm_q == FSM_ENABLE;
  assign i2c.penable      = s_fsm_q == FSM_ENABLE;
  assign qspi.penable     = s_fsm_q == FSM_ENABLE;
  assign spfs.penable     = s_fsm_q == FSM_ENABLE;

  assign archinfo.pwrite  = |nmi.wstrb;
  assign rng.pwrite       = |nmi.wstrb;
  assign uart.pwrite      = |nmi.wstrb;
  assign pwm.pwrite       = |nmi.wstrb;
  assign ps2.pwrite       = |nmi.wstrb;
  assign i2c.pwrite       = |nmi.wstrb;
  assign qspi.pwrite      = |nmi.wstrb;
  assign spfs.pwrite      = |nmi.wstrb;

  assign archinfo.pwdata  = nmi.wdata;
  assign rng.pwdata       = nmi.wdata;
  assign uart.pwdata      = nmi.wdata;
  assign pwm.pwdata       = nmi.wdata;
  assign ps2.pwdata       = nmi.wdata;
  assign i2c.pwdata       = nmi.wdata;
  assign qspi.pwdata      = nmi.wdata;
  assign spfs.pwdata      = nmi.wdata;

  assign archinfo.pstrb   = nmi.wstrb;
  assign rng.pstrb        = nmi.wstrb;
  assign uart.pstrb       = nmi.wstrb;
  assign pwm.pstrb        = nmi.wstrb;
  assign ps2.pstrb        = nmi.wstrb;
  assign i2c.pstrb        = nmi.wstrb;
  assign qspi.pstrb       = nmi.wstrb;
  assign spfs.pstrb       = nmi.wstrb;

`ifdef IP_MDD
  assign user_ip.paddr    = nmi.addr;
  assign user_ip.pprot    = '0;
  assign user_ip.psel     = s_xfer_valid && (nmi.addr[31:24] == `APB_IP_START && nmi.addr[15:8] == 8'hF0);
  assign user_ip.penable  = s_fsm_q == FSM_ENABLE;
  assign user_ip.pwrite   = |nmi.wstrb;
  assign user_ip.pwdata   = nmi.wdata;
  assign user_ip.pstrb    = nmi.wstrb;
`endif
  // verilog_format: on

  edge_det_sync_re #(1) u_mem_valid_edge_det_sync_re (
      clk_i,
      rst_n_i,
      nmi.valid,
      s_mem_valid_re
  );

  assign s_xfer_valid = ((s_fsm_q == FSM_IDLE) && s_mem_valid_re) ||
                         (s_fsm_q == FSM_SETUP) || (s_fsm_q == FSM_ENABLE);

  always_comb begin
    s_fsm_d = s_fsm_q;
    unique case (s_fsm_q)
      FSM_IDLE: begin
        if (s_mem_valid_re) s_fsm_d = FSM_SETUP;
      end
      FSM_SETUP: s_fsm_d = FSM_ENABLE;
      FSM_ENABLE: begin
        if (s_xfer_ready) s_fsm_d = FSM_IDLE;
      end
      default:   s_fsm_d = s_fsm_q;
    endcase
  end
  dffr #(2) u_fsm_dffr (
      clk_i,
      rst_n_i,
      s_fsm_d,
      s_fsm_q
  );

  assign nmi.ready   = nmi.valid && (s_fsm_q == FSM_ENABLE) && s_xfer_ready;
  assign nmi.rdata   = {32{nmi.ready}} & s_rd_data;

  // verilog_format: off
  assign s_rd_data = ({32{archinfo.psel}} & archinfo.prdata) |
                     ({32{rng.psel}} & rng.prdata) |
                     ({32{uart.psel}} & uart.prdata) |
                     ({32{pwm.psel}} & pwm.prdata) |
                     ({32{ps2.psel}} & ps2.prdata) |
                     ({32{i2c.psel}} & i2c.prdata) |
                     ({32{qspi.psel}} & qspi.prdata) |
`ifdef IP_MDD
                     ({32{spfs.psel}} & spfs.prdata) |
                     ({32{user_ip.psel}} & user_ip.prdata);
`else
                     ({32{spfs.psel}} & spfs.prdata);
`endif

  assign s_xfer_ready = (archinfo.psel & archinfo.pready) |
                        (rng.psel & rng.pready) |
                        (uart.psel & uart.pready) |
                        (pwm.psel & pwm.pready) |
                        (ps2.psel & ps2.pready) |
                        (i2c.psel & i2c.pready) |
                        (qspi.psel & qspi.pready) |
`ifdef IP_MDD
                        (spfs.psel & spfs.pready) |
                        (user_ip.psel & user_ip.pready);
`else
                        (spfs.psel & spfs.pready);
`endif
  // verilog_format: on

endmodule
