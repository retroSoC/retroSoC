// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.


`timescale 1ns / 10ps

// 1-4-4
module QSPIFlash (
    input logic clk,
    input logic cs,
    inout wire  io0,
    inout wire  io1,
    inout wire  io2,
    inout wire  io3
);

  typedef enum logic [2:0] {
    cmd_t,
    addr_t,
    dumm_t,
    data_t,
    err_t
  } state_t;

  logic [2:0] r_state;
  logic [7:0] r_cnt, r_cmd;
  logic [31:0] r_addr, r_data;
  logic s_reset, s_rd_en;
  logic [31:0] s_rdata, s_raddr;
  logic s_out_en;

  assign s_reset  = cs;
  assign io0      = s_out_en ? r_data[28] : 1'bz;
  assign io1      = s_out_en ? r_data[29] : 1'bz;
  assign io2      = s_out_en ? r_data[30] : 1'bz;
  assign io3      = s_out_en ? r_data[31] : 1'bz;
  assign s_rd_en  = (r_state == addr_t) && (r_cnt == 8'd24);
  assign s_out_en = r_state == data_t;
  assign s_raddr  = r_addr;

  flash_read_binder #(32) u_flash_read_binder (
      .clk_i  (clk),
      .rd_en_i(s_rd_en),
      .addr_i ({8'd0, s_raddr[23:0]}),
      .data_o (s_rdata)
  );

  always @(posedge clk or posedge s_reset) begin
    if (s_reset) r_state <= cmd_t;
    else begin
      case (r_state)
        cmd_t:   r_state <= r_cnt == 8'd07 ? addr_t : r_state;
        addr_t:  r_state <= r_cmd != 8'hEB ? err_t : (r_cnt == 8'd28) ? dumm_t : r_state;
        dumm_t:  r_state <= r_cnt == 8'd03 ? data_t : r_state;
        data_t:  r_state <= r_state;
        err_t: begin
          r_state <= r_state;
          $error("Assertion failed: only support `EBh` read command\n");
          $fatal;
        end
        default: r_state <= r_state;
      endcase
    end
  end

  always @(posedge clk or posedge s_reset) begin
    if (s_reset) r_cnt <= 8'd0;
    else begin
      case (r_state)
        cmd_t:   r_cnt <= r_cnt == 8'd7 ? 8'd0 : r_cnt + 8'd1;
        addr_t:  r_cnt <= r_cnt == 8'd28 ? 8'd0 : r_cnt + 8'd4;
        dumm_t:  r_cnt <= r_cnt == 8'd3 ? 8'd0 : r_cnt + 8'd1;
        default: r_cnt <= r_cnt + 8'd4;
      endcase
    end
  end

  always @(posedge clk or posedge s_reset) begin
    if (s_reset) r_cmd <= 8'd0;
    else if (r_state == cmd_t) r_cmd <= {r_cmd[6:0], io0};
  end

  always @(posedge clk or posedge s_reset) begin
    if (s_reset) r_addr <= 32'd0;
    else if (r_state == addr_t && r_cnt < 8'd24) r_addr <= {r_addr[27:0], io3, io2, io1, io0};
  end

  always @(posedge clk or posedge s_reset) begin
    if (s_reset) r_data <= 32'd0;
    else if (r_state == addr_t && r_cnt == 8'd28)
      r_data <= {s_rdata[7:0], s_rdata[15:8], s_rdata[23:16], s_rdata[31:24]};
    else if (r_state == data_t) r_data <= {r_data[27:0], r_data[31:28]};
  end

endmodule

