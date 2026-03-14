// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

// NOTE: need to focus on the port dir

`include "gpio_define.svh"
`include "mdd_config.svh"

module retrosoc_asic (
    inout  extclk_i_pad,
    inout  audclk_i_pad,
    inout  ext_rst_n_i_pad,
`ifdef HAVE_PLL
    input  xi_i_pad,
    output xo_o_pad,
    inout  clk_bypass_i_pad,
    inout  pll_cfg_0_i_pad,
    inout  pll_cfg_1_i_pad,
    inout  pll_cfg_2_i_pad,
`endif
`ifdef CORE_MDD
    inout  core_sel_0_i_pad,
    inout  core_sel_1_i_pad,
    inout  core_sel_2_i_pad,
    inout  core_sel_3_i_pad,
    inout  core_sel_4_i_pad,
`endif
`ifdef IP_MDD
    inout  user_gpio_0_io_pad,
    inout  user_gpio_1_io_pad,
    inout  user_gpio_2_io_pad,
    inout  user_gpio_3_io_pad,
    inout  user_gpio_4_io_pad,
    inout  user_gpio_5_io_pad,
    inout  user_gpio_6_io_pad,
    inout  user_gpio_7_io_pad,
    inout  user_gpio_8_io_pad,
    inout  user_gpio_9_io_pad,
    inout  user_gpio_10_io_pad,
    inout  user_gpio_11_io_pad,
    inout  user_gpio_12_io_pad,
    inout  user_gpio_13_io_pad,
    inout  user_gpio_14_io_pad,
    inout  user_gpio_15_io_pad,
`endif
    // gpio
    inout  gpio_0_io_pad,
    inout  gpio_1_io_pad,
    inout  gpio_2_io_pad,
    inout  gpio_3_io_pad,
    inout  gpio_4_io_pad,
    inout  gpio_5_io_pad,
    inout  gpio_6_io_pad,
    inout  gpio_7_io_pad,
    inout  gpio_8_io_pad,
    inout  gpio_9_io_pad,
    inout  gpio_10_io_pad,
    inout  gpio_11_io_pad,
    inout  gpio_12_io_pad,
    inout  gpio_13_io_pad,
    inout  gpio_14_io_pad,
    inout  gpio_15_io_pad,
    inout  gpio_16_io_pad,
    inout  gpio_17_io_pad,
    inout  gpio_18_io_pad,
    inout  gpio_19_io_pad,
    inout  gpio_20_io_pad,
    inout  gpio_21_io_pad,
    inout  gpio_22_io_pad,
    inout  gpio_23_io_pad,
    inout  gpio_24_io_pad,
    inout  gpio_25_io_pad,
    inout  gpio_26_io_pad,
    inout  gpio_27_io_pad,
    inout  gpio_28_io_pad,
    inout  gpio_29_io_pad,
    inout  gpio_30_io_pad,
    inout  gpio_31_io_pad,
    // uart
    output uart0_tx_o_pad,
    inout  uart0_rx_i_pad,
    // xpi
    output qspi_sck_o_pad,
    output qspi_nss0_o_pad,
    output qspi_nss1_o_pad,
    output qspi_nss2_o_pad,
    output qspi_nss3_o_pad,
    inout  qspi_dat0_io_pad,
    inout  qspi_dat1_io_pad,
    inout  qspi_dat2_io_pad,
    inout  qspi_dat3_io_pad,
    // sdram
    output sdram_clk_o_pad,
    output sdram_cke_o_pad,
    output sdram_cs_n_o_pad,
    output sdram_ras_n_o_pad,
    output sdram_cas_n_o_pad,
    output sdram_we_n_o_pad,
    output sdram_ba0_o_pad,
    output sdram_ba1_o_pad,
    output sdram_addr0_o_pad,
    output sdram_addr1_o_pad,
    output sdram_addr2_o_pad,
    output sdram_addr3_o_pad,
    output sdram_addr4_o_pad,
    output sdram_addr5_o_pad,
    output sdram_addr6_o_pad,
    output sdram_addr7_o_pad,
    output sdram_addr8_o_pad,
    output sdram_addr9_o_pad,
    output sdram_addr10_o_pad,
    output sdram_addr11_o_pad,
    output sdram_addr12_o_pad,
    output sdram_dqm0_o_pad,
    output sdram_dqm1_o_pad,
    inout  sdram_dq0_io_pad,
    inout  sdram_dq1_io_pad,
    inout  sdram_dq2_io_pad,
    inout  sdram_dq3_io_pad,
    inout  sdram_dq4_io_pad,
    inout  sdram_dq5_io_pad,
    inout  sdram_dq6_io_pad,
    inout  sdram_dq7_io_pad,
    inout  sdram_dq8_io_pad,
    inout  sdram_dq9_io_pad,
    inout  sdram_dq10_io_pad,
    inout  sdram_dq11_io_pad,
    inout  sdram_dq12_io_pad,
    inout  sdram_dq13_io_pad,
    inout  sdram_dq14_io_pad,
    inout  sdram_dq15_io_pad
);
  // clk&rst
  logic s_ext_clk;
  logic s_aud_clk;
  logic s_sys_clkdiv4;
`ifdef HAVE_PLL
  logic       s_xtal_io;
  logic       s_clk_bypass;
  logic [2:0] s_pll_cfg;
`endif
  logic s_sys_clk;
  logic s_ext_rst_n;
  logic s_sys_rst_n;
  logic s_aud_rst_n;
  logic s_tmr_capch;

`ifdef CORE_MDD
  logic [`USER_CORESEL_WIDTH-1:0] s_core_sel;
`endif

`ifdef IP_MDD
  gpio_if #(`USER_GPIO_NUM) u_user_gpio_if ();
`endif

`ifdef HAVE_SRAM_IF
  ram_if u_ram_if ();
`endif

  // verilog_format: off
  gpio_if     u_gpio_if  ();
  uart_if     u_uart0_if ();
  xpi_if      u_xpi_if   ();
  sdram_if    u_sdram_if ();


  tc_io_tri_pad         u_extclk_i_pad          (.pad(extclk_i_pad),          .c2p(1'b0),                       .c2p_en(1'b0),                      .p2c(s_ext_clk));
  tc_io_tri_pad         u_audclk_i_pad          (.pad(audclk_i_pad),          .c2p(1'b0),                       .c2p_en(1'b0),                      .p2c(s_aud_clk));
  tc_io_tri_schmitt_pad u_ext_rst_n_i_pad       (.pad(ext_rst_n_i_pad),       .c2p(1'b0),                       .c2p_en(1'b0),                      .p2c(s_ext_rst_n));
`ifdef HAVE_PLL
  tc_io_xtl_pad         u_xtal_io_pad           (.xi_pad(xi_i_pad),           .xo_pad(xo_o_pad),                .en(1'b1),                          .clk(s_xtal_io));
  tc_io_tri_pad         u_clk_bypass_i_pad      (.pad(clk_bypass_i_pad),      .c2p(1'b0),                       .c2p_en(1'b0),                      .p2c(s_clk_bypass));
  tc_io_tri_pad         u_pll_cfg_0_i_pad       (.pad(pll_cfg_0_i_pad),       .c2p(1'b0),                       .c2p_en(1'b0),                      .p2c(s_pll_cfg[0]));
  tc_io_tri_pad         u_pll_cfg_1_i_pad       (.pad(pll_cfg_1_i_pad),       .c2p(1'b0),                       .c2p_en(1'b0),                      .p2c(s_pll_cfg[1]));
  tc_io_tri_pad         u_pll_cfg_2_i_pad       (.pad(pll_cfg_2_i_pad),       .c2p(1'b0),                       .c2p_en(1'b0),                      .p2c(s_pll_cfg[2]));
`endif
`ifdef CORE_MDD
  tc_io_tri_pad         u_core_sel_0_i_pad      (.pad(core_sel_0_i_pad),      .c2p(1'b0),                       .c2p_en(1'b0),                      .p2c(s_core_sel[0]));
  tc_io_tri_pad         u_core_sel_1_i_pad      (.pad(core_sel_1_i_pad),      .c2p(1'b0),                       .c2p_en(1'b0),                      .p2c(s_core_sel[1]));
  tc_io_tri_pad         u_core_sel_2_i_pad      (.pad(core_sel_2_i_pad),      .c2p(1'b0),                       .c2p_en(1'b0),                      .p2c(s_core_sel[2]));
  tc_io_tri_pad         u_core_sel_3_i_pad      (.pad(core_sel_3_i_pad),      .c2p(1'b0),                       .c2p_en(1'b0),                      .p2c(s_core_sel[3]));
  tc_io_tri_pad         u_core_sel_4_i_pad      (.pad(core_sel_4_i_pad),      .c2p(1'b0),                       .c2p_en(1'b0),                      .p2c(s_core_sel[4]));
`endif
`ifdef IP_MDD
  tc_io_tri_full_pad    u_user_gpio_0_io_pad    (.pad(user_gpio_0_io_pad),    .c2p(u_user_gpio_if.do_o[0]),  .c2p_en(u_user_gpio_if.oe_o[0]),  .p2c(u_user_gpio_if.di_i[0]),  .cs(u_user_gpio_if.cs_o[0]),  .pu(u_user_gpio_if.pu_o[0]),  .pd(u_user_gpio_if.pd_o[0]));
  tc_io_tri_full_pad    u_user_gpio_1_io_pad    (.pad(user_gpio_1_io_pad),    .c2p(u_user_gpio_if.do_o[1]),  .c2p_en(u_user_gpio_if.oe_o[1]),  .p2c(u_user_gpio_if.di_i[1]),  .cs(u_user_gpio_if.cs_o[1]),  .pu(u_user_gpio_if.pu_o[1]),  .pd(u_user_gpio_if.pd_o[1]));
  tc_io_tri_full_pad    u_user_gpio_2_io_pad    (.pad(user_gpio_2_io_pad),    .c2p(u_user_gpio_if.do_o[2]),  .c2p_en(u_user_gpio_if.oe_o[2]),  .p2c(u_user_gpio_if.di_i[2]),  .cs(u_user_gpio_if.cs_o[2]),  .pu(u_user_gpio_if.pu_o[2]),  .pd(u_user_gpio_if.pd_o[2]));
  tc_io_tri_full_pad    u_user_gpio_3_io_pad    (.pad(user_gpio_3_io_pad),    .c2p(u_user_gpio_if.do_o[3]),  .c2p_en(u_user_gpio_if.oe_o[3]),  .p2c(u_user_gpio_if.di_i[3]),  .cs(u_user_gpio_if.cs_o[3]),  .pu(u_user_gpio_if.pu_o[3]),  .pd(u_user_gpio_if.pd_o[3]));
  tc_io_tri_full_pad    u_user_gpio_4_io_pad    (.pad(user_gpio_4_io_pad),    .c2p(u_user_gpio_if.do_o[4]),  .c2p_en(u_user_gpio_if.oe_o[4]),  .p2c(u_user_gpio_if.di_i[4]),  .cs(u_user_gpio_if.cs_o[4]),  .pu(u_user_gpio_if.pu_o[4]),  .pd(u_user_gpio_if.pd_o[4]));
  tc_io_tri_full_pad    u_user_gpio_5_io_pad    (.pad(user_gpio_5_io_pad),    .c2p(u_user_gpio_if.do_o[5]),  .c2p_en(u_user_gpio_if.oe_o[5]),  .p2c(u_user_gpio_if.di_i[5]),  .cs(u_user_gpio_if.cs_o[5]),  .pu(u_user_gpio_if.pu_o[5]),  .pd(u_user_gpio_if.pd_o[5]));
  tc_io_tri_full_pad    u_user_gpio_6_io_pad    (.pad(user_gpio_6_io_pad),    .c2p(u_user_gpio_if.do_o[6]),  .c2p_en(u_user_gpio_if.oe_o[6]),  .p2c(u_user_gpio_if.di_i[6]),  .cs(u_user_gpio_if.cs_o[6]),  .pu(u_user_gpio_if.pu_o[6]),  .pd(u_user_gpio_if.pd_o[6]));
  tc_io_tri_full_pad    u_user_gpio_7_io_pad    (.pad(user_gpio_7_io_pad),    .c2p(u_user_gpio_if.do_o[7]),  .c2p_en(u_user_gpio_if.oe_o[7]),  .p2c(u_user_gpio_if.di_i[7]),  .cs(u_user_gpio_if.cs_o[7]),  .pu(u_user_gpio_if.pu_o[7]),  .pd(u_user_gpio_if.pd_o[7]));
  tc_io_tri_full_pad    u_user_gpio_8_io_pad    (.pad(user_gpio_8_io_pad),    .c2p(u_user_gpio_if.do_o[8]),  .c2p_en(u_user_gpio_if.oe_o[8]),  .p2c(u_user_gpio_if.di_i[8]),  .cs(u_user_gpio_if.cs_o[8]),  .pu(u_user_gpio_if.pu_o[8]),  .pd(u_user_gpio_if.pd_o[8]));
  tc_io_tri_full_pad    u_user_gpio_9_io_pad    (.pad(user_gpio_9_io_pad),    .c2p(u_user_gpio_if.do_o[9]),  .c2p_en(u_user_gpio_if.oe_o[9]),  .p2c(u_user_gpio_if.di_i[9]),  .cs(u_user_gpio_if.cs_o[9]),  .pu(u_user_gpio_if.pu_o[9]),  .pd(u_user_gpio_if.pd_o[9]));
  tc_io_tri_full_pad    u_user_gpio_10_io_pad   (.pad(user_gpio_10_io_pad),   .c2p(u_user_gpio_if.do_o[10]), .c2p_en(u_user_gpio_if.oe_o[10]), .p2c(u_user_gpio_if.di_i[10]), .cs(u_user_gpio_if.cs_o[10]), .pu(u_user_gpio_if.pu_o[10]), .pd(u_user_gpio_if.pd_o[10]));
  tc_io_tri_full_pad    u_user_gpio_11_io_pad   (.pad(user_gpio_11_io_pad),   .c2p(u_user_gpio_if.do_o[11]), .c2p_en(u_user_gpio_if.oe_o[11]), .p2c(u_user_gpio_if.di_i[11]), .cs(u_user_gpio_if.cs_o[11]), .pu(u_user_gpio_if.pu_o[11]), .pd(u_user_gpio_if.pd_o[11]));
  tc_io_tri_full_pad    u_user_gpio_12_io_pad   (.pad(user_gpio_12_io_pad),   .c2p(u_user_gpio_if.do_o[12]), .c2p_en(u_user_gpio_if.oe_o[12]), .p2c(u_user_gpio_if.di_i[12]), .cs(u_user_gpio_if.cs_o[12]), .pu(u_user_gpio_if.pu_o[12]), .pd(u_user_gpio_if.pd_o[12]));
  tc_io_tri_full_pad    u_user_gpio_13_io_pad   (.pad(user_gpio_13_io_pad),   .c2p(u_user_gpio_if.do_o[13]), .c2p_en(u_user_gpio_if.oe_o[13]), .p2c(u_user_gpio_if.di_i[13]), .cs(u_user_gpio_if.cs_o[13]), .pu(u_user_gpio_if.pu_o[13]), .pd(u_user_gpio_if.pd_o[13]));
  tc_io_tri_full_pad    u_user_gpio_14_io_pad   (.pad(user_gpio_14_io_pad),   .c2p(u_user_gpio_if.do_o[14]), .c2p_en(u_user_gpio_if.oe_o[14]), .p2c(u_user_gpio_if.di_i[14]), .cs(u_user_gpio_if.cs_o[14]), .pu(u_user_gpio_if.pu_o[14]), .pd(u_user_gpio_if.pd_o[14]));
  tc_io_tri_full_pad    u_user_gpio_15_io_pad   (.pad(user_gpio_15_io_pad),   .c2p(u_user_gpio_if.do_o[15]), .c2p_en(u_user_gpio_if.oe_o[15]), .p2c(u_user_gpio_if.di_i[15]), .cs(u_user_gpio_if.cs_o[15]), .pu(u_user_gpio_if.pu_o[15]), .pd(u_user_gpio_if.pd_o[15]));
`endif
  // gpio
  tc_io_tri_full_pad    u_gpio_0_io_pad          (.pad(gpio_0_io_pad),          .c2p(u_gpio_if.do_o[0]),       .c2p_en(u_gpio_if.oe_o[0]),       .p2c(u_gpio_if.di_i[0]),  .cs(u_gpio_if.cs_o[0]),   .pu(u_gpio_if.pu_o[0]),   .pd(u_gpio_if.pd_o[0]));
  tc_io_tri_full_pad    u_gpio_1_io_pad          (.pad(gpio_1_io_pad),          .c2p(u_gpio_if.do_o[1]),       .c2p_en(u_gpio_if.oe_o[1]),       .p2c(u_gpio_if.di_i[1]),  .cs(u_gpio_if.cs_o[1]),   .pu(u_gpio_if.pu_o[1]),   .pd(u_gpio_if.pd_o[1]));
  tc_io_tri_full_pad    u_gpio_2_io_pad          (.pad(gpio_2_io_pad),          .c2p(u_gpio_if.do_o[2]),       .c2p_en(u_gpio_if.oe_o[2]),       .p2c(u_gpio_if.di_i[2]),  .cs(u_gpio_if.cs_o[2]),   .pu(u_gpio_if.pu_o[2]),   .pd(u_gpio_if.pd_o[2]));
  tc_io_tri_full_pad    u_gpio_3_io_pad          (.pad(gpio_3_io_pad),          .c2p(u_gpio_if.do_o[3]),       .c2p_en(u_gpio_if.oe_o[3]),       .p2c(u_gpio_if.di_i[3]),  .cs(u_gpio_if.cs_o[3]),   .pu(u_gpio_if.pu_o[3]),   .pd(u_gpio_if.pd_o[3]));
  tc_io_tri_full_pad    u_gpio_4_io_pad          (.pad(gpio_4_io_pad),          .c2p(u_gpio_if.do_o[4]),       .c2p_en(u_gpio_if.oe_o[4]),       .p2c(u_gpio_if.di_i[4]),  .cs(u_gpio_if.cs_o[4]),   .pu(u_gpio_if.pu_o[4]),   .pd(u_gpio_if.pd_o[4]));
  tc_io_tri_full_pad    u_gpio_5_io_pad          (.pad(gpio_5_io_pad),          .c2p(u_gpio_if.do_o[5]),       .c2p_en(u_gpio_if.oe_o[5]),       .p2c(u_gpio_if.di_i[5]),  .cs(u_gpio_if.cs_o[5]),   .pu(u_gpio_if.pu_o[5]),   .pd(u_gpio_if.pd_o[5]));
  tc_io_tri_full_pad    u_gpio_6_io_pad          (.pad(gpio_6_io_pad),          .c2p(u_gpio_if.do_o[6]),       .c2p_en(u_gpio_if.oe_o[6]),       .p2c(u_gpio_if.di_i[6]),  .cs(u_gpio_if.cs_o[6]),   .pu(u_gpio_if.pu_o[6]),   .pd(u_gpio_if.pd_o[6]));
  tc_io_tri_full_pad    u_gpio_7_io_pad          (.pad(gpio_7_io_pad),          .c2p(u_gpio_if.do_o[7]),       .c2p_en(u_gpio_if.oe_o[7]),       .p2c(u_gpio_if.di_i[7]),  .cs(u_gpio_if.cs_o[7]),   .pu(u_gpio_if.pu_o[7]),   .pd(u_gpio_if.pd_o[7]));
  tc_io_tri_full_pad    u_gpio_8_io_pad          (.pad(gpio_8_io_pad),          .c2p(u_gpio_if.do_o[8]),       .c2p_en(u_gpio_if.oe_o[8]),       .p2c(u_gpio_if.di_i[8]),  .cs(u_gpio_if.cs_o[8]),   .pu(u_gpio_if.pu_o[8]),   .pd(u_gpio_if.pd_o[8]));
  tc_io_tri_full_pad    u_gpio_9_io_pad          (.pad(gpio_9_io_pad),          .c2p(u_gpio_if.do_o[9]),       .c2p_en(u_gpio_if.oe_o[9]),       .p2c(u_gpio_if.di_i[9]),  .cs(u_gpio_if.cs_o[9]),   .pu(u_gpio_if.pu_o[9]),   .pd(u_gpio_if.pd_o[9]));
  tc_io_tri_full_pad    u_gpio_10_io_pad         (.pad(gpio_10_io_pad),         .c2p(u_gpio_if.do_o[10]),      .c2p_en(u_gpio_if.oe_o[10]),      .p2c(u_gpio_if.di_i[10]), .cs(u_gpio_if.cs_o[10]),  .pu(u_gpio_if.pu_o[10]),  .pd(u_gpio_if.pd_o[10]));
  tc_io_tri_full_pad    u_gpio_11_io_pad         (.pad(gpio_11_io_pad),         .c2p(u_gpio_if.do_o[11]),      .c2p_en(u_gpio_if.oe_o[11]),      .p2c(u_gpio_if.di_i[11]), .cs(u_gpio_if.cs_o[11]),  .pu(u_gpio_if.pu_o[11]),  .pd(u_gpio_if.pd_o[11]));
  tc_io_tri_full_pad    u_gpio_12_io_pad         (.pad(gpio_12_io_pad),         .c2p(u_gpio_if.do_o[12]),      .c2p_en(u_gpio_if.oe_o[12]),      .p2c(u_gpio_if.di_i[12]), .cs(u_gpio_if.cs_o[12]),  .pu(u_gpio_if.pu_o[12]),  .pd(u_gpio_if.pd_o[12]));
  tc_io_tri_full_pad    u_gpio_13_io_pad         (.pad(gpio_13_io_pad),         .c2p(u_gpio_if.do_o[13]),      .c2p_en(u_gpio_if.oe_o[13]),      .p2c(u_gpio_if.di_i[13]), .cs(u_gpio_if.cs_o[13]),  .pu(u_gpio_if.pu_o[13]),  .pd(u_gpio_if.pd_o[13]));
  tc_io_tri_full_pad    u_gpio_14_io_pad         (.pad(gpio_14_io_pad),         .c2p(u_gpio_if.do_o[14]),      .c2p_en(u_gpio_if.oe_o[14]),      .p2c(u_gpio_if.di_i[14]), .cs(u_gpio_if.cs_o[14]),  .pu(u_gpio_if.pu_o[14]),  .pd(u_gpio_if.pd_o[14]));
  tc_io_tri_full_pad    u_gpio_15_io_pad         (.pad(gpio_15_io_pad),         .c2p(u_gpio_if.do_o[15]),      .c2p_en(u_gpio_if.oe_o[15]),      .p2c(u_gpio_if.di_i[15]), .cs(u_gpio_if.cs_o[15]),  .pu(u_gpio_if.pu_o[15]),  .pd(u_gpio_if.pd_o[15]));
  tc_io_tri_full_pad    u_gpio_16_io_pad         (.pad(gpio_16_io_pad),         .c2p(u_gpio_if.do_o[16]),      .c2p_en(u_gpio_if.oe_o[16]),      .p2c(u_gpio_if.di_i[16]), .cs(u_gpio_if.cs_o[16]),  .pu(u_gpio_if.pu_o[16]),  .pd(u_gpio_if.pd_o[16]));
  tc_io_tri_full_pad    u_gpio_17_io_pad         (.pad(gpio_17_io_pad),         .c2p(u_gpio_if.do_o[17]),      .c2p_en(u_gpio_if.oe_o[17]),      .p2c(u_gpio_if.di_i[17]), .cs(u_gpio_if.cs_o[17]),  .pu(u_gpio_if.pu_o[17]),  .pd(u_gpio_if.pd_o[17]));
  tc_io_tri_full_pad    u_gpio_18_io_pad         (.pad(gpio_18_io_pad),         .c2p(u_gpio_if.do_o[18]),      .c2p_en(u_gpio_if.oe_o[18]),      .p2c(u_gpio_if.di_i[18]), .cs(u_gpio_if.cs_o[18]),  .pu(u_gpio_if.pu_o[18]),  .pd(u_gpio_if.pd_o[18]));
  tc_io_tri_full_pad    u_gpio_19_io_pad         (.pad(gpio_19_io_pad),         .c2p(u_gpio_if.do_o[19]),      .c2p_en(u_gpio_if.oe_o[19]),      .p2c(u_gpio_if.di_i[19]), .cs(u_gpio_if.cs_o[19]),  .pu(u_gpio_if.pu_o[19]),  .pd(u_gpio_if.pd_o[19]));
  tc_io_tri_full_pad    u_gpio_20_io_pad         (.pad(gpio_20_io_pad),         .c2p(u_gpio_if.do_o[20]),      .c2p_en(u_gpio_if.oe_o[20]),      .p2c(u_gpio_if.di_i[20]), .cs(u_gpio_if.cs_o[20]),  .pu(u_gpio_if.pu_o[20]),  .pd(u_gpio_if.pd_o[20]));
  tc_io_tri_full_pad    u_gpio_21_io_pad         (.pad(gpio_21_io_pad),         .c2p(u_gpio_if.do_o[21]),      .c2p_en(u_gpio_if.oe_o[21]),      .p2c(u_gpio_if.di_i[21]), .cs(u_gpio_if.cs_o[21]),  .pu(u_gpio_if.pu_o[21]),  .pd(u_gpio_if.pd_o[21]));
  tc_io_tri_full_pad    u_gpio_22_io_pad         (.pad(gpio_22_io_pad),         .c2p(u_gpio_if.do_o[22]),      .c2p_en(u_gpio_if.oe_o[22]),      .p2c(u_gpio_if.di_i[22]), .cs(u_gpio_if.cs_o[22]),  .pu(u_gpio_if.pu_o[22]),  .pd(u_gpio_if.pd_o[22]));
  tc_io_tri_full_pad    u_gpio_23_io_pad         (.pad(gpio_23_io_pad),         .c2p(u_gpio_if.do_o[23]),      .c2p_en(u_gpio_if.oe_o[23]),      .p2c(u_gpio_if.di_i[23]), .cs(u_gpio_if.cs_o[23]),  .pu(u_gpio_if.pu_o[23]),  .pd(u_gpio_if.pd_o[23]));
  tc_io_tri_full_pad    u_gpio_24_io_pad         (.pad(gpio_24_io_pad),         .c2p(u_gpio_if.do_o[24]),      .c2p_en(u_gpio_if.oe_o[24]),      .p2c(u_gpio_if.di_i[24]), .cs(u_gpio_if.cs_o[24]),  .pu(u_gpio_if.pu_o[24]),  .pd(u_gpio_if.pd_o[24]));
  tc_io_tri_full_pad    u_gpio_25_io_pad         (.pad(gpio_25_io_pad),         .c2p(u_gpio_if.do_o[25]),      .c2p_en(u_gpio_if.oe_o[25]),      .p2c(u_gpio_if.di_i[25]), .cs(u_gpio_if.cs_o[25]),  .pu(u_gpio_if.pu_o[25]),  .pd(u_gpio_if.pd_o[25]));
  tc_io_tri_full_pad    u_gpio_26_io_pad         (.pad(gpio_26_io_pad),         .c2p(u_gpio_if.do_o[26]),      .c2p_en(u_gpio_if.oe_o[26]),      .p2c(u_gpio_if.di_i[26]), .cs(u_gpio_if.cs_o[26]),  .pu(u_gpio_if.pu_o[26]),  .pd(u_gpio_if.pd_o[26]));
  tc_io_tri_full_pad    u_gpio_27_io_pad         (.pad(gpio_27_io_pad),         .c2p(u_gpio_if.do_o[27]),      .c2p_en(u_gpio_if.oe_o[27]),      .p2c(u_gpio_if.di_i[27]), .cs(u_gpio_if.cs_o[27]),  .pu(u_gpio_if.pu_o[27]),  .pd(u_gpio_if.pd_o[27]));
  tc_io_tri_full_pad    u_gpio_28_io_pad         (.pad(gpio_28_io_pad),         .c2p(u_gpio_if.do_o[28]),      .c2p_en(u_gpio_if.oe_o[28]),      .p2c(u_gpio_if.di_i[28]), .cs(u_gpio_if.cs_o[28]),  .pu(u_gpio_if.pu_o[28]),  .pd(u_gpio_if.pd_o[28]));
  tc_io_tri_full_pad    u_gpio_29_io_pad         (.pad(gpio_29_io_pad),         .c2p(u_gpio_if.do_o[29]),      .c2p_en(u_gpio_if.oe_o[29]),      .p2c(u_gpio_if.di_i[29]), .cs(u_gpio_if.cs_o[29]),  .pu(u_gpio_if.pu_o[29]),  .pd(u_gpio_if.pd_o[29]));
  tc_io_tri_full_pad    u_gpio_30_io_pad         (.pad(gpio_30_io_pad),         .c2p(u_gpio_if.do_o[30]),      .c2p_en(u_gpio_if.oe_o[30]),      .p2c(u_gpio_if.di_i[30]), .cs(u_gpio_if.cs_o[30]),  .pu(u_gpio_if.pu_o[30]),  .pd(u_gpio_if.pd_o[30]));
  tc_io_tri_full_pad    u_gpio_31_io_pad         (.pad(gpio_31_io_pad),         .c2p(u_gpio_if.do_o[31]),      .c2p_en(u_gpio_if.oe_o[31]),      .p2c(u_gpio_if.di_i[31]), .cs(u_gpio_if.cs_o[31]),  .pu(u_gpio_if.pu_o[31]),  .pd(u_gpio_if.pd_o[31]));

  // uart0
  tc_io_tri_pad         u_uart0_tx_o_pad        (.pad(uart0_tx_o_pad),        .c2p(u_uart0_if.uart_tx_o),       .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_uart0_rx_i_pad        (.pad(uart0_rx_i_pad),        .c2p(1'b0),                       .c2p_en(1'b0),                      .p2c(u_uart0_if.uart_rx_i));
  // xpi
  tc_io_tri_pad         u_qspi_sck_o_pad       (.pad(qspi_sck_o_pad),         .c2p(u_xpi_if.spi_sck_o),        .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_qspi_nss0_o_pad      (.pad(qspi_nss0_o_pad),        .c2p(u_xpi_if.spi_nss_o[0]),     .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_qspi_nss1_o_pad      (.pad(qspi_nss1_o_pad),        .c2p(u_xpi_if.spi_nss_o[1]),     .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_qspi_nss2_o_pad      (.pad(qspi_nss2_o_pad),        .c2p(u_xpi_if.spi_nss_o[2]),     .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_qspi_nss3_o_pad      (.pad(qspi_nss3_o_pad),        .c2p(u_xpi_if.spi_nss_o[3]),     .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_qspi_dat0_io_pad     (.pad(qspi_dat0_io_pad),       .c2p(u_xpi_if.spi_io_out_o[0]),  .c2p_en(u_xpi_if.spi_io_en_o[0]),  .p2c(u_xpi_if.spi_io_in_i[0]));
  tc_io_tri_pad         u_qspi_dat1_io_pad     (.pad(qspi_dat1_io_pad),       .c2p(u_xpi_if.spi_io_out_o[1]),  .c2p_en(u_xpi_if.spi_io_en_o[1]),  .p2c(u_xpi_if.spi_io_in_i[1]));
  tc_io_tri_pad         u_qspi_dat2_io_pad     (.pad(qspi_dat2_io_pad),       .c2p(u_xpi_if.spi_io_out_o[2]),  .c2p_en(u_xpi_if.spi_io_en_o[2]),  .p2c(u_xpi_if.spi_io_in_i[2]));
  tc_io_tri_pad         u_qspi_dat3_io_pad     (.pad(qspi_dat3_io_pad),       .c2p(u_xpi_if.spi_io_out_o[3]),  .c2p_en(u_xpi_if.spi_io_en_o[3]),  .p2c(u_xpi_if.spi_io_in_i[3]));
  // sdram
  tc_io_tri_pad         u_sdram_clk_o_pad       (.pad(sdram_clk_o_pad),       .c2p(u_sdram_if.clk_o),           .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_sdram_cke_o_pad       (.pad(sdram_cke_o_pad),       .c2p(u_sdram_if.cke_o),           .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_sdram_cs_n_o_pad      (.pad(sdram_cs_n_o_pad),      .c2p(u_sdram_if.cs_n_o),          .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_sdram_ras_n_o_pad     (.pad(sdram_ras_n_o_pad),     .c2p(u_sdram_if.ras_n_o),         .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_sdram_cas_n_o_pad     (.pad(sdram_cas_n_o_pad),     .c2p(u_sdram_if.cas_n_o),         .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_sdram_we_n_o_pad      (.pad(sdram_we_n_o_pad),      .c2p(u_sdram_if.we_n_o),          .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_sdram_ba0_o_pad       (.pad(sdram_ba0_o_pad),       .c2p(u_sdram_if.ba_o[0]),         .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_sdram_ba1_o_pad       (.pad(sdram_ba1_o_pad),       .c2p(u_sdram_if.ba_o[1]),         .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_sdram_addr0_o_pad     (.pad(sdram_addr0_o_pad),     .c2p(u_sdram_if.addr_o[0]),       .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_sdram_addr1_o_pad     (.pad(sdram_addr1_o_pad),     .c2p(u_sdram_if.addr_o[1]),       .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_sdram_addr2_o_pad     (.pad(sdram_addr2_o_pad),     .c2p(u_sdram_if.addr_o[2]),       .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_sdram_addr3_o_pad     (.pad(sdram_addr3_o_pad),     .c2p(u_sdram_if.addr_o[3]),       .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_sdram_addr4_o_pad     (.pad(sdram_addr4_o_pad),     .c2p(u_sdram_if.addr_o[4]),       .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_sdram_addr5_o_pad     (.pad(sdram_addr5_o_pad),     .c2p(u_sdram_if.addr_o[5]),       .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_sdram_addr6_o_pad     (.pad(sdram_addr6_o_pad),     .c2p(u_sdram_if.addr_o[6]),       .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_sdram_addr7_o_pad     (.pad(sdram_addr7_o_pad),     .c2p(u_sdram_if.addr_o[7]),       .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_sdram_addr8_o_pad     (.pad(sdram_addr8_o_pad),     .c2p(u_sdram_if.addr_o[8]),       .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_sdram_addr9_o_pad     (.pad(sdram_addr9_o_pad),     .c2p(u_sdram_if.addr_o[9]),       .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_sdram_addr10_o_pad    (.pad(sdram_addr10_o_pad),    .c2p(u_sdram_if.addr_o[10]),      .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_sdram_addr11_o_pad    (.pad(sdram_addr11_o_pad),    .c2p(u_sdram_if.addr_o[11]),      .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_sdram_addr12_o_pad    (.pad(sdram_addr12_o_pad),    .c2p(u_sdram_if.addr_o[12]),      .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_sdram_dqm0_o_pad      (.pad(sdram_dqm0_o_pad),      .c2p(u_sdram_if.dqm_o[0]),        .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_sdram_dqm1_o_pad      (.pad(sdram_dqm1_o_pad),      .c2p(u_sdram_if.dqm_o[1]),        .c2p_en(1'b1),                      .p2c());
  tc_io_tri_pad         u_sdram_dq0_io_pad      (.pad(sdram_dq0_io_pad),      .c2p(u_sdram_if.dq_o[0]),         .c2p_en(u_sdram_if.oe_o),           .p2c(u_sdram_if.dq_i[0]));
  tc_io_tri_pad         u_sdram_dq1_io_pad      (.pad(sdram_dq1_io_pad),      .c2p(u_sdram_if.dq_o[1]),         .c2p_en(u_sdram_if.oe_o),           .p2c(u_sdram_if.dq_i[1]));
  tc_io_tri_pad         u_sdram_dq2_io_pad      (.pad(sdram_dq2_io_pad),      .c2p(u_sdram_if.dq_o[2]),         .c2p_en(u_sdram_if.oe_o),           .p2c(u_sdram_if.dq_i[2]));
  tc_io_tri_pad         u_sdram_dq3_io_pad      (.pad(sdram_dq3_io_pad),      .c2p(u_sdram_if.dq_o[3]),         .c2p_en(u_sdram_if.oe_o),           .p2c(u_sdram_if.dq_i[3]));
  tc_io_tri_pad         u_sdram_dq4_io_pad      (.pad(sdram_dq4_io_pad),      .c2p(u_sdram_if.dq_o[4]),         .c2p_en(u_sdram_if.oe_o),           .p2c(u_sdram_if.dq_i[4]));
  tc_io_tri_pad         u_sdram_dq5_io_pad      (.pad(sdram_dq5_io_pad),      .c2p(u_sdram_if.dq_o[5]),         .c2p_en(u_sdram_if.oe_o),           .p2c(u_sdram_if.dq_i[5]));
  tc_io_tri_pad         u_sdram_dq6_io_pad      (.pad(sdram_dq6_io_pad),      .c2p(u_sdram_if.dq_o[6]),         .c2p_en(u_sdram_if.oe_o),           .p2c(u_sdram_if.dq_i[6]));
  tc_io_tri_pad         u_sdram_dq7_io_pad      (.pad(sdram_dq7_io_pad),      .c2p(u_sdram_if.dq_o[7]),         .c2p_en(u_sdram_if.oe_o),           .p2c(u_sdram_if.dq_i[7]));
  tc_io_tri_pad         u_sdram_dq8_io_pad      (.pad(sdram_dq8_io_pad),      .c2p(u_sdram_if.dq_o[8]),         .c2p_en(u_sdram_if.oe_o),           .p2c(u_sdram_if.dq_i[8]));
  tc_io_tri_pad         u_sdram_dq9_io_pad      (.pad(sdram_dq9_io_pad),      .c2p(u_sdram_if.dq_o[9]),         .c2p_en(u_sdram_if.oe_o),           .p2c(u_sdram_if.dq_i[9]));
  tc_io_tri_pad         u_sdram_dq10_io_pad     (.pad(sdram_dq10_io_pad),     .c2p(u_sdram_if.dq_o[10]),        .c2p_en(u_sdram_if.oe_o),           .p2c(u_sdram_if.dq_i[10]));
  tc_io_tri_pad         u_sdram_dq11_io_pad     (.pad(sdram_dq11_io_pad),     .c2p(u_sdram_if.dq_o[11]),        .c2p_en(u_sdram_if.oe_o),           .p2c(u_sdram_if.dq_i[11]));
  tc_io_tri_pad         u_sdram_dq12_io_pad     (.pad(sdram_dq12_io_pad),     .c2p(u_sdram_if.dq_o[12]),        .c2p_en(u_sdram_if.oe_o),           .p2c(u_sdram_if.dq_i[12]));
  tc_io_tri_pad         u_sdram_dq13_io_pad     (.pad(sdram_dq13_io_pad),     .c2p(u_sdram_if.dq_o[13]),        .c2p_en(u_sdram_if.oe_o),           .p2c(u_sdram_if.dq_i[13]));
  tc_io_tri_pad         u_sdram_dq14_io_pad     (.pad(sdram_dq14_io_pad),     .c2p(u_sdram_if.dq_o[14]),        .c2p_en(u_sdram_if.oe_o),           .p2c(u_sdram_if.dq_i[14]));
  tc_io_tri_pad         u_sdram_dq15_io_pad     (.pad(sdram_dq15_io_pad),     .c2p(u_sdram_if.dq_o[15]),        .c2p_en(u_sdram_if.oe_o),           .p2c(u_sdram_if.dq_i[15]));
  // verilog_format: on


  // clk buffer & mux
  rcu u_rcu (
      .ext_clk_i    (s_ext_clk),
      .aud_clk_i    (s_aud_clk),
      .ext_rst_n_i  (s_ext_rst_n),
`ifdef HAVE_PLL
      .xtal_clk_i   (s_xtal_io),
      .clk_bypass_i (s_clk_bypass),
      .pll_cfg_i    (s_pll_cfg),
`endif
      .sys_clk_o    (s_sys_clk),
      .sys_rst_n_o  (s_sys_rst_n),
      .aud_rst_n_o  (s_aud_rst_n),
      .sys_clkdiv4_o(s_sys_clkdiv4)
  );

`ifdef HAVE_SRAM_IF
  onchip_ram u_onchip_ram (
      .clk_i(s_sys_clk),
      .ram  (u_ram_if)
  );
`endif

  retrosoc u_retrosoc (
      .clk_i      (s_sys_clk),
      .rst_n_i    (s_sys_rst_n),
      .clk_aud_i  (s_aud_clk),
      .rst_aud_n_i(s_aud_rst_n),
      .clkdiv4_i  (s_sys_clkdiv4),
`ifdef CORE_MDD
      .core_sel_i (s_core_sel),
`endif
`ifdef IP_MDD
      .user_gpio  (u_user_gpio_if),
`endif
`ifdef HAVE_SRAM_IF
      .ram        (u_ram_if),
`endif
      .gpio       (u_gpio_if),
      .uart0      (u_uart0_if),
      .xpi        (u_xpi_if),
      .sdram      (u_sdram_if)
  );

endmodule
