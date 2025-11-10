// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

/*
 * 0. copy this file as `user_ip_design.sv`
 * 1. create a new folder `userip` and simply put `user_ip_design.sv` into `userip` folder
 * 2. put all user custom design files into `userip` folder
 *    - instance top module of user design under `user_ip_design.sv`
 *    - create a filelist named `userip.fl` to include all files needed to be add into the path
 * 3. archive 'userip' as `userip.zip` and upload `userip.zip` to cloud platform
 */
module user_ip_design_template #(
    parameter int ID = 8'd255
) (
    // verilog_format: off
    input logic      clk_i,
    input logic      rst_n_i,
    user_gpio_if.dut gpio,
    apb4_if.slave    apb
    // verilog_format: on
);

  // ========== USER CUSTOM AREA ==========
  // NOTE: define constants by using 'localparam'
  localparam USER_IP_APB_ID = 8'h00;
  localparam USER_IP_APB_XX = 8'h04;
  // wire
  logic s_apb_wr_hdshk, s_apb_rd_hdshk;

  assign s_apb_wr_hdshk = apb.psel && apb.penable && apb.pwrite;
  assign s_apb_rd_hdshk = apb.psel && apb.penable && (~apb.pwrite);
  assign apb.pready     = 1'b1;
  assign apb.pslverr    = 1'b0;

  always_comb begin
    apb.prdata = '0;
    if (s_apb_rd_hdshk) begin
      unique case (apb.paddr[7:0])
        USER_IP_APB_ID: apb.prdata = {24'd0, ID};
        default:        apb.prdata = '0;
      endcase
    end
  end

  assign gpio.gpio_out = '0;
  assign gpio.gpio_oen = '0;

  // ====== INSTANCE USER CUSTOM DESIGN HERE!!!! ======
  // ====== ==================================== ======
  // ====== ==================================== ======

endmodule
