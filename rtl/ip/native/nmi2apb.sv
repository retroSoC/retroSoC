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

module nmi2apb (
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
    apb4_pure_if.master rtc,
    apb4_pure_if.master wdg,
    apb4_pure_if.master crc,
    apb4_pure_if.master tmr,
    apb4_pure_if.master spfs
    // verilog_format: on
);

  localparam FSM_IDLE = 2'd0;
  localparam FSM_SETP = 2'd1;
  localparam FSM_ENAB = 2'd2;

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
  assign rtc.paddr        = nmi.addr;
  assign wdg.paddr        = nmi.addr;
  assign crc.paddr        = nmi.addr;
  assign tmr.paddr        = nmi.addr;
  assign spfs.paddr       = nmi.addr;

  assign archinfo.pprot   = '0;
  assign rng.pprot        = '0;
  assign uart.pprot       = '0;
  assign pwm.pprot        = '0;
  assign ps2.pprot        = '0;
  assign rtc.pprot        = '0;
  assign wdg.pprot        = '0;
  assign crc.pprot        = '0;
  assign tmr.pprot        = '0;
  assign spfs.pprot       = '0;

  assign archinfo.psel    = s_xfer_valid && (nmi.addr[31:28] == `APB_IP_START && nmi.addr[15:8] == `APB_ARCHINFO_START);
  assign rng.psel         = s_xfer_valid && (nmi.addr[31:28] == `APB_IP_START && nmi.addr[15:8] == `APB_RNG_START);
  assign uart.psel        = s_xfer_valid && (nmi.addr[31:28] == `APB_IP_START && nmi.addr[15:8] == `APB_UART_START);
  assign pwm.psel         = s_xfer_valid && (nmi.addr[31:28] == `APB_IP_START && nmi.addr[15:8] == `APB_PWM_START);
  assign ps2.psel         = s_xfer_valid && (nmi.addr[31:28] == `APB_IP_START && nmi.addr[15:8] == `APB_PS2_START);
  assign rtc.psel         = s_xfer_valid && (nmi.addr[31:28] == `APB_IP_START && nmi.addr[15:8] == `APB_RTC_START);
  assign wdg.psel         = s_xfer_valid && (nmi.addr[31:28] == `APB_IP_START && nmi.addr[15:8] == `APB_WDG_START);
  assign crc.psel         = s_xfer_valid && (nmi.addr[31:28] == `APB_IP_START && nmi.addr[15:8] == `APB_CRC_START);
  assign tmr.psel         = s_xfer_valid && (nmi.addr[31:28] == `APB_IP_START && nmi.addr[15:8] == `APB_TMR_START);
  assign spfs.psel        = s_xfer_valid && (nmi.addr[31:28] == `FLASH_START);

  assign archinfo.penable = s_fsm_q == FSM_ENAB;
  assign rng.penable      = s_fsm_q == FSM_ENAB;
  assign uart.penable     = s_fsm_q == FSM_ENAB;
  assign pwm.penable      = s_fsm_q == FSM_ENAB;
  assign ps2.penable      = s_fsm_q == FSM_ENAB;
  assign rtc.penable      = s_fsm_q == FSM_ENAB;
  assign wdg.penable      = s_fsm_q == FSM_ENAB;
  assign crc.penable      = s_fsm_q == FSM_ENAB;
  assign tmr.penable      = s_fsm_q == FSM_ENAB;
  assign spfs.penable     = s_fsm_q == FSM_ENAB;

  assign archinfo.pwrite  = |nmi.wstrb;
  assign rng.pwrite       = |nmi.wstrb;
  assign uart.pwrite      = |nmi.wstrb;
  assign pwm.pwrite       = |nmi.wstrb;
  assign ps2.pwrite       = |nmi.wstrb;
  assign rtc.pwrite       = |nmi.wstrb;
  assign wdg.pwrite       = |nmi.wstrb;
  assign crc.pwrite       = |nmi.wstrb;
  assign tmr.pwrite       = |nmi.wstrb;
  assign spfs.pwrite      = |nmi.wstrb;

  assign archinfo.pwdata  = nmi.wdata;
  assign rng.pwdata       = nmi.wdata;
  assign uart.pwdata      = nmi.wdata;
  assign pwm.pwdata       = nmi.wdata;
  assign ps2.pwdata       = nmi.wdata;
  assign rtc.pwdata       = nmi.wdata;
  assign wdg.pwdata       = nmi.wdata;
  assign crc.pwdata       = nmi.wdata;
  assign tmr.pwdata       = nmi.wdata;
  assign spfs.pwdata      = nmi.wdata;

  assign archinfo.pstrb   = nmi.wstrb;
  assign rng.pstrb        = nmi.wstrb;
  assign uart.pstrb       = nmi.wstrb;
  assign pwm.pstrb        = nmi.wstrb;
  assign ps2.pstrb        = nmi.wstrb;
  assign rtc.pstrb        = nmi.wstrb;
  assign wdg.pstrb        = nmi.wstrb;
  assign crc.pstrb        = nmi.wstrb;
  assign tmr.pstrb        = nmi.wstrb;
  assign spfs.pstrb       = nmi.wstrb;

`ifdef IP_MDD
  assign user_ip.paddr    = nmi.addr;
  assign user_ip.pprot    = '0;
  assign user_ip.psel     = s_xfer_valid && (nmi.addr[31:28] == `APB_IP_START && nmi.addr[15:8] == `APB_USR_START);
  assign user_ip.penable  = s_fsm_q == FSM_ENAB;
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
                         (s_fsm_q == FSM_SETP) || (s_fsm_q == FSM_ENAB);

  always_comb begin
    s_fsm_d = s_fsm_q;
    unique case (s_fsm_q)
      FSM_IDLE: if (s_mem_valid_re) s_fsm_d = FSM_SETP;
      FSM_SETP: s_fsm_d = FSM_ENAB;
      FSM_ENAB:  if (s_xfer_ready) s_fsm_d = FSM_IDLE;
      default:   s_fsm_d = s_fsm_q;
    endcase
  end
  dffr #(2) u_fsm_dffr (
      clk_i,
      rst_n_i,
      s_fsm_d,
      s_fsm_q
  );

  assign nmi.ready   = nmi.valid && (s_fsm_q == FSM_ENAB) && s_xfer_ready;
  assign nmi.rdata   = {32{nmi.ready}} & s_rd_data;

  // verilog_format: off
  assign s_rd_data = ({32{archinfo.psel}} & archinfo.prdata) |
                     ({32{rng.psel}}      & rng.prdata)      |
                     ({32{uart.psel}}     & uart.prdata)     |
                     ({32{pwm.psel}}      & pwm.prdata)      |
                     ({32{ps2.psel}}      & ps2.prdata)      |
                     ({32{rtc.psel}}      & rtc.prdata)      |
                     ({32{wdg.psel}}      & wdg.prdata)      |
                     ({32{crc.psel}}      & crc.prdata)      |
                     ({32{tmr.psel}}      & tmr.prdata)      |
`ifdef IP_MDD
                     ({32{user_ip.psel}}  & user_ip.prdata)  |
`endif
                     ({32{spfs.psel}}     & spfs.prdata);

  assign s_xfer_ready = (archinfo.psel & archinfo.pready) |
                        (rng.psel      & rng.pready)      |
                        (uart.psel     & uart.pready)     |
                        (pwm.psel      & pwm.pready)      |
                        (ps2.psel      & ps2.pready)      |
                        (rtc.psel      & rtc.pready)      |
                        (wdg.psel      & wdg.pready)      |
                        (crc.psel      & crc.pready)      |
                        (tmr.psel      & tmr.pready)      |
`ifdef IP_MDD
                        (user_ip.psel  & user_ip.pready)  |
`endif
                        (spfs.psel     & spfs.pready);
  // verilog_format: on

endmodule
