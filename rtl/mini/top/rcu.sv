// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module rcu (
    input  logic       xtal_clk_i,
    input  logic       ext_clk_i,
    input  logic       aud_clk_i,
    input  logic       clk_bypass_i,
    input  logic       ext_rst_n_i,
`ifdef HAVE_PLL
    input  logic [2:0] pll_cfg_i,
`endif
    output logic       sys_clk_o,
    output logic       sys_rst_n_o,
    output logic       aud_rst_n_o,
    output logic       sys_clkdiv4_o
);
  logic       s_xtal_clk_buf;
  logic       s_ext_clk_buf;
  logic       s_pll_clk;
  logic       s_pll_clk_buf;
  logic       s_sys_clk;
  logic       s_ext_rst_n_sync;
  logic       s_aud_rst_n_sync;
  logic       s_pll_lock;
  logic       s_pll_bp;
  logic [3:0] s_pll_N;
  logic [7:0] s_pll_M;
  logic [1:0] s_pll_OD;
  logic [3:0] s_div_cnt_d, s_div_cnt_q;
  logic s_sys_clkdiv4_d, s_sys_clkdiv4_q;


  tc_clk_buf u_xtal_buf (
      .clk_i(xtal_clk_i),
      .clk_o(s_xtal_clk_buf)
  );
  tc_clk_buf u_ext_clk_buf (
      .clk_i(ext_clk_i),
      .clk_o(s_ext_clk_buf)
  );
  tc_clk_buf u_pll_clk_buf (
      .clk_i(s_pll_clk),
      .clk_o(s_pll_clk_buf)
  );
  tc_clk_mux2 u_sys_mux (
      .clk0_i   (s_pll_clk_buf),
      .clk1_i   (s_ext_clk_buf),
      .clk_sel_i(clk_bypass_i),
      .clk_o    (s_sys_clk)
  );
  tc_clk_buf u_sys_clk_buf (
      .clk_i(s_sys_clk),
      .clk_o(sys_clk_o)
  );

  rst_sync #(
      .STAGE(5)
  ) u_ext_rst_sync (
      .clk_i  (sys_clk_o),
      .rst_n_i(ext_rst_n_i),
      .rst_n_o(s_ext_rst_n_sync)
  );

  rst_sync #(
      .STAGE(5)
  ) u_aud_rst_sync (
      .clk_i  (aud_clk_i),
      .rst_n_i(ext_rst_n_i),
      .rst_n_o(s_aud_rst_n_sync)
  );

  assign sys_rst_n_o   = clk_bypass_i ? s_ext_rst_n_sync : s_pll_lock;
  assign aud_rst_n_o   = s_aud_rst_n_sync;
  assign sys_clkdiv4_o = s_sys_clkdiv4_q;

  assign s_div_cnt_d   = (s_div_cnt_q == 4'd1) ? '0 : s_div_cnt_q + 1'b1;
  dffr #(4) u_div_cnt_dffr (
      sys_clk_o,
      sys_rst_n_o,
      s_div_cnt_d,
      s_div_cnt_q
  );

  assign s_sys_clkdiv4_d = (s_div_cnt_q == 4'd1) ? ~s_sys_clkdiv4_q : s_sys_clkdiv4_q;
  dffr #(1) u_sys_clkdiv4_dffr (
      sys_clk_o,
      sys_rst_n_o,
      s_sys_clkdiv4_d,
      s_sys_clkdiv4_q
  );

  // 24(bypass) 48(ext clk) 72 96
  // 120 144 168 192
  // 2 <= N <= 4
  // 7 <= M 
`ifdef HAVE_PLL
  always_comb begin
    unique case (pll_cfg_i)
      3'b000: begin  //bypass 24MHz
        s_pll_bp = 1'b1;
        s_pll_M  = 8'd20;
        s_pll_N  = 4'd2;
        s_pll_OD = 2'd1;
      end
      3'b001: begin  //bypass 24MHz
        s_pll_bp = 1'b1;
        s_pll_M  = 8'd20;
        s_pll_N  = 4'd2;
        s_pll_OD = 2'd1;
      end
      3'b010: begin  //3*clk 72MHz
        s_pll_bp = 1'b0;
        s_pll_M  = 8'd24;
        s_pll_N  = 4'd2;
        s_pll_OD = 2'd2;
      end
      3'b011: begin  //4*clk 96MHz
        s_pll_bp = 1'b0;
        s_pll_M  = 8'd32;
        s_pll_N  = 4'd2;
        s_pll_OD = 2'd2;
      end
      3'b100: begin  //5*clk 120MHz
        s_pll_bp = 1'b0;
        s_pll_M  = 8'd40;
        s_pll_N  = 4'd2;
        s_pll_OD = 2'd2;
      end
      3'b101: begin  //6*clk 144MHz
        s_pll_bp = 1'b0;
        s_pll_M  = 8'd48;
        s_pll_N  = 4'd2;
        s_pll_OD = 2'd2;
      end
      3'b110: begin  //7*clk 168MHz
        s_pll_bp = 1'b0;
        s_pll_M  = 8'd56;
        s_pll_N  = 4'd2;
        s_pll_OD = 2'd2;
      end
      3'b111: begin  //8*clk 192MHz
        s_pll_bp = 1'b0;
        s_pll_M  = 8'd64;
        s_pll_N  = 4'd4;
        s_pll_OD = 2'd1;
      end
      default: begin  //bypass
        s_pll_bp = 1'b1;
        s_pll_M  = 8'd20;
        s_pll_N  = 4'd2;
        s_pll_OD = 2'd1;
      end
    endcase
  end
`else
  assign s_pll_bp = 1'b1;
  assign s_pll_M  = 8'd20;
  assign s_pll_N  = 4'd2;
  assign s_pll_OD = 2'd1;
`endif
  tc_pll u_tc_pll (
      .fref_i    (s_xtal_clk_buf),
      .rst_n_i   (s_ext_rst_n_sync),
      .refdiv_i  (s_pll_M),
      .fbdiv_i   (),
      .postdiv1_i(s_pll_N),
      .postdiv2_i(s_pll_OD),
      .bp_i      (clk_bypass_i || s_pll_bp),
      .pll_lock_o(s_pll_lock),
      .pll_clk_o (s_pll_clk)
  );

endmodule
