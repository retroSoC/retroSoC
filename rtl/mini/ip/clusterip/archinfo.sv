// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// archinfo is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef INC_ARCHINFO_DEF_SV
`define INC_ARCHINFO_DEF_SV

/* register mapping
 * ARCHINFO_SYS:
 * BITS:   | 31:20 | 19:8  | 7:0  |
 * FIELDS: | RES   | CLOCK | SRAM |
 * PERMS:  | NONE  | RW    | RW   |
 * -------------------------------------------
 * ARCHINFO_IDL:
 * BITS:   | 31:30 | 29:22  | 21:6    | 5:0  |
 * FIELDS: | TYPE  | VENDOR | PROCESS | CUST |
 * PERMS:  | RW    | RW     | RW      | RW   |
 * -------------------------------------------
 * ARCHINFO_IDH:
 * BITS:   | 31:24 | 23:0 |
 * FIELDS: | RES   | DATE |
 * PERMS:  | NONE  | RW   |
 * -------------------------------------------
*/

// verilog_format: off
`define ARCHINFO_SYS 4'b0000 // BASEADDR + 0x00
`define ARCHINFO_IDL 4'b0001 // BASEADDR + 0x04
`define ARCHINFO_IDH 4'b0010 // BASEADDR + 0x08

`define ARCHINFO_SYS_ADDR {26'b0, `ARCHINFO_SYS, 2'b00}
`define ARCHINFO_IDL_ADDR {26'b0, `ARCHINFO_IDL, 2'b00}
`define ARCHINFO_IDH_ADDR {26'b0, `ARCHINFO_IDH, 2'b00}

`define ARCHINFO_SYS_WIDTH 20
`define ARCHINFO_IDL_WIDTH 32
`define ARCHINFO_IDH_WIDTH 24

`define SYS_VAL 20'hF_1010
`define IDL_VAL 32'hFFFF_2022
`define IDH_VAL 24'hFF_FFFF
// verilog_format: on

`endif


// Copyright (c) 2023-2024 Miao Yuchi <miaoyuchi@ict.ac.cn>
// archinfo is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module apb4_archinfo (
    input         pclk,
    input         presetn,
    input  [31:0] paddr,
    input  [ 2:0] pprot,
    input         psel,
    input         penable,
    input         pwrite,
    input  [31:0] pwdata,
    input  [ 3:0] pstrb,
    output        pready,
    output [31:0] prdata,
    output        pslverr
);

  wire [3:0] s_apb4_addr;
  wire s_apb4_wr_hdshk, s_apb4_rd_hdshk;
  wire [`ARCHINFO_SYS_WIDTH-1:0] s_arch_sys_d, s_arch_sys_q;
  wire s_arch_sys_en;
  wire [`ARCHINFO_IDL_WIDTH-1:0] s_arch_idl_d, s_arch_idl_q;
  wire s_arch_idl_en;
  wire [`ARCHINFO_IDH_WIDTH-1:0] s_arch_idh_d, s_arch_idh_q;
  wire s_arch_idh_en;

  assign s_apb4_addr     = paddr[5:2];
  assign s_apb4_wr_hdshk = psel && penable && pwrite;
  assign s_apb4_rd_hdshk = psel && penable && (~pwrite);
  assign pready          = 1'b1;
  assign pslverr         = 1'b0;

  assign s_arch_sys_en   = s_apb4_wr_hdshk && s_apb4_addr == `ARCHINFO_SYS;
  assign s_arch_sys_d    = pwdata[`ARCHINFO_SYS_WIDTH-1:0];
  dfferc #(`ARCHINFO_SYS_WIDTH, `SYS_VAL) u_arch_sys_dfferc (
      pclk,
      presetn,
      s_arch_sys_en,
      s_arch_sys_d,
      s_arch_sys_q
  );

  assign s_arch_idl_en = s_apb4_wr_hdshk && s_apb4_addr == `ARCHINFO_IDL;
  assign s_arch_idl_d  = pwdata[`ARCHINFO_IDL_WIDTH-1:0];
  dfferc #(`ARCHINFO_IDL_WIDTH, `IDL_VAL) u_arch_idl_dfferc (
      pclk,
      presetn,
      s_arch_idl_en,
      s_arch_idl_d,
      s_arch_idl_q
  );

  assign s_arch_idh_en = s_apb4_wr_hdshk && s_apb4_addr == `ARCHINFO_IDH;
  assign s_arch_idh_d  = pwdata[`ARCHINFO_IDH_WIDTH-1:0];
  dfferc #(`ARCHINFO_IDH_WIDTH, `IDH_VAL) u_arch_idh_dfferc (
      pclk,
      presetn,
      s_arch_idh_en,
      s_arch_idh_d,
      s_arch_idh_q
  );

  assign prdata = ({32{~s_apb4_rd_hdshk}} & 32'h0) |
                  ({32{s_apb4_rd_hdshk}} & (({32{s_apb4_addr == `ARCHINFO_SYS}} & {12'h0, s_arch_sys_q}) |
                  ({32{s_apb4_addr == `ARCHINFO_IDL}} & s_arch_idl_q) |
                  ({32{s_apb4_addr == `ARCHINFO_IDH}} & {8'h0, s_arch_idh_q}) | 32'h0));

endmodule
