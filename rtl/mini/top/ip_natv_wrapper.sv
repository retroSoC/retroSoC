// Copyright (c) 2023-2025 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module ip_natv_wrapper (
    input  logic        clk_i,
    input  logic        rst_n_i,
    // natv if
    input  logic        natv_valid_i,
    input  logic [31:0] natv_addr_i,
    input  logic [31:0] natv_wdata_i,
    input  logic [ 3:0] natv_wstrb_i,
    output logic [31:0] natv_rdata_o,
    output logic        natv_ready_o,
    // gpio
    output logic [ 7:0] gpio_out_o,
    input  logic [ 7:0] gpio_in_i,
    output logic [ 7:0] gpio_pun_o,
    output logic [ 7:0] gpio_pdn_o,
    output logic [ 7:0] gpio_oen_o,
    // uart
    input  logic        uart_rx_i,
    output logic        uart_tx_o,
    // psram if
    output logic        psram_cfg_wait_wr_en_o,
    input  logic [ 4:0] psram_cfg_wait_i,
    output logic [ 4:0] psram_cfg_wait_o,
    output logic        psram_cfg_chd_wr_en_o,
    input  logic [ 2:0] psram_cfg_chd_i,
    output logic [ 2:0] psram_cfg_chd_o,
    // spisd if
    output logic [ 1:0] spisd_cfg_clkdiv_o,
    // irq
    output logic [ 2:0] irq_o
);

  logic s_natv_ready_d, s_natv_ready_q;
  logic [ 4:0] r_psram_cfg_wait;
  logic [ 2:0] r_psram_cfg_chd;
  logic [ 1:0] r_spisd_cfg_clkdiv;
  logic [31:0] r_mmap_rdata;
  // gpio
  logic [15:0] r_gpio;
  logic [15:0] r_gpio_pun;
  logic [15:0] r_gpio_pdn;
  logic [15:0] r_gpio_oen;
  // uart
  logic        s_uart_div_reg_sel;
  logic        s_uart_dat_reg_sel;
  logic [31:0] s_uart_div_reg_dout;
  logic [31:0] s_uart_dat_reg_dout;
  logic        s_uart_dat_reg_wait;
  // tim0
  logic        s_tim0_cfg_reg_sel;
  logic        s_tim0_val_reg_sel;
  logic        s_tim0_dat_reg_sel;
  logic [31:0] s_tim0_cfg_reg_dout;
  logic [31:0] s_tim0_val_reg_dout;
  logic [31:0] s_tim0_dat_reg_dout;
  // tim1
  logic        s_tim1_cfg_reg_sel;
  logic        s_tim1_val_reg_sel;
  logic        s_tim1_dat_reg_sel;
  logic [31:0] s_tim1_cfg_reg_dout;
  logic [31:0] s_tim1_val_reg_dout;
  logic [31:0] s_tim1_dat_reg_dout;
  // psram
  logic        s_psram_wait_reg_sel;
  logic        s_psram_chd_reg_sel;
  // spisd
  logic        s_spisd_clkdiv_reg_sel;

  assign natv_rdata_o           = r_mmap_rdata;
  assign natv_ready_o           = s_natv_ready_q;
  // gpio
  assign gpio_out_o             = r_gpio;
  assign gpio_oen_o             = {8{~rst_n_i}} | r_gpio_oen;
  assign gpio_pun_o             = r_gpio_pun;
  assign gpio_pdn_o             = r_gpio_pdn;

  assign s_uart_div_reg_sel     = natv_valid_i && (natv_addr_i[15:0] == 16'h1000);
  assign s_uart_dat_reg_sel     = natv_valid_i && (natv_addr_i[15:0] == 16'h1004);
  assign s_tim0_cfg_reg_sel     = natv_valid_i && (natv_addr_i[15:0] == 16'h2000);
  assign s_tim0_val_reg_sel     = natv_valid_i && (natv_addr_i[15:0] == 16'h2004);
  assign s_tim0_dat_reg_sel     = natv_valid_i && (natv_addr_i[15:0] == 16'h2008);
  assign s_tim1_cfg_reg_sel     = natv_valid_i && (natv_addr_i[15:0] == 16'h3000);
  assign s_tim1_val_reg_sel     = natv_valid_i && (natv_addr_i[15:0] == 16'h3004);
  assign s_tim1_dat_reg_sel     = natv_valid_i && (natv_addr_i[15:0] == 16'h3008);
  assign s_psram_wait_reg_sel   = natv_valid_i && (natv_addr_i[15:0] == 16'h4000);
  assign s_psram_chd_reg_sel    = natv_valid_i && (natv_addr_i[15:0] == 16'h4004);
  assign s_spisd_clkdiv_reg_sel = natv_valid_i && (natv_addr_i[15:0] == 16'h5000);

  assign psram_cfg_wait_wr_en_o = s_psram_wait_reg_sel ? natv_wstrb_i[0] : 1'b0;
  assign psram_cfg_chd_wr_en_o  = s_psram_chd_reg_sel ? natv_wstrb_i[0] : 1'b0;
  assign psram_cfg_wait_o       = r_psram_cfg_wait;
  assign psram_cfg_chd_o        = r_psram_cfg_chd;
  assign spisd_cfg_clkdiv_o     = r_spisd_cfg_clkdiv;


  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (~rst_n_i) begin
      r_gpio             <= '0;
      r_gpio_pun         <= '0;
      r_gpio_pdn         <= '0;
      r_gpio_oen         <= '1;
      r_mmap_rdata       <= '0;
      r_psram_cfg_wait   <= '0;
      r_psram_cfg_chd    <= '0;
      r_spisd_cfg_clkdiv <= '0;

    end else begin
      if (natv_valid_i && !s_natv_ready_q) begin
        case (natv_addr_i[15:0])
          16'h0000: begin
            r_mmap_rdata <= {gpio_out_o, gpio_in_i};
            if (natv_wstrb_i[0]) r_gpio[7:0] <= natv_wdata_i[7:0];
          end
          16'h0004: begin
            r_mmap_rdata <= {16'd0, r_gpio_oen};
            if (natv_wstrb_i[0]) r_gpio_oen[7:0] <= natv_wdata_i[7:0];
          end
          16'h0008: begin
            r_mmap_rdata <= {16'd0, r_gpio_pun};
            if (natv_wstrb_i[0]) r_gpio_pun[7:0] <= natv_wdata_i[7:0];
          end
          16'h000C: begin
            r_mmap_rdata <= {16'd0, r_gpio_pun};
            if (natv_wstrb_i[0]) r_gpio_pdn[7:0] <= natv_wdata_i[7:0];
          end
          16'h1000: r_mmap_rdata <= s_uart_div_reg_dout;
          16'h1004: r_mmap_rdata <= s_uart_dat_reg_dout;
          16'h2000: r_mmap_rdata <= s_tim0_cfg_reg_dout;
          16'h2004: r_mmap_rdata <= s_tim0_val_reg_dout;
          16'h2008: r_mmap_rdata <= s_tim0_dat_reg_dout;
          16'h3000: r_mmap_rdata <= s_tim1_cfg_reg_dout;
          16'h3004: r_mmap_rdata <= s_tim1_val_reg_dout;
          16'h3008: r_mmap_rdata <= s_tim1_dat_reg_dout;
          16'h4000: begin
            r_mmap_rdata <= {27'd0, psram_cfg_wait_i};
            if (natv_wstrb_i[0]) r_psram_cfg_wait <= natv_wdata_i[4:0];
          end
          16'h4004: begin
            r_mmap_rdata <= {29'd0, psram_cfg_chd_i};
            if (natv_wstrb_i[0]) r_psram_cfg_chd <= natv_wdata_i[2:0];
          end
          16'h5000: begin
            r_mmap_rdata <= {30'd0, r_spisd_cfg_clkdiv};
            if (natv_wstrb_i[0]) r_spisd_cfg_clkdiv <= natv_wdata_i[1:0];
          end
        endcase
      end
    end
  end

  assign s_natv_ready_d = (natv_valid_i && !s_natv_ready_q) ? 
                          (natv_addr_i[15:0] == 16'h1004 ? ~s_uart_dat_reg_wait : 1'b1) : 1'b0;
  dffr #(1) u_natv_ready_dffr (
      clk_i,
      rst_n_i,
      s_natv_ready_d,
      s_natv_ready_q
  );

  simple_uart u_simple_uart (
      .clk_i       (clk_i),
      .rst_n_i     (rst_n_i),
      .ser_tx      (uart_tx_o),
      .ser_rx      (uart_rx_i),
      .reg_div_we  (s_uart_div_reg_sel ? natv_wstrb_i : 4'b0000),
      .reg_div_di  (natv_wdata_i),
      .reg_div_do  (s_uart_div_reg_dout),
      .reg_dat_we  (s_uart_dat_reg_sel ? natv_wstrb_i[0] : 1'b0),
      .reg_dat_re  (s_uart_dat_reg_sel && !natv_wstrb_i),
      .reg_dat_di  (natv_wdata_i),
      .reg_dat_do  (s_uart_dat_reg_dout),
      .reg_dat_wait(s_uart_dat_reg_wait),
      .irq_out     (irq_o[0])
  );

  simple_timer u_simple_timer0 (
      .clk_i     (clk_i),
      .rst_n_i   (rst_n_i),
      .reg_val_we(s_tim0_val_reg_sel ? natv_wstrb_i : 4'h0),
      .reg_val_di(natv_wdata_i),
      .reg_val_do(s_tim0_val_reg_dout),
      .reg_cfg_we(s_tim0_cfg_reg_sel ? natv_wstrb_i[0] : 1'b0),
      .reg_cfg_di(natv_wdata_i),
      .reg_cfg_do(s_tim0_cfg_reg_dout),
      .reg_dat_we(s_tim0_dat_reg_sel ? natv_wstrb_i : 4'h0),
      .reg_dat_di(natv_wdata_i),
      .reg_dat_do(s_tim0_dat_reg_dout),
      .irq_out   (irq_o[1])
  );

  simple_timer u_simple_timer1 (
      .clk_i     (clk_i),
      .rst_n_i   (rst_n_i),
      .reg_val_we(s_tim1_val_reg_sel ? natv_wstrb_i : 4'h0),
      .reg_val_di(natv_wdata_i),
      .reg_val_do(s_tim1_val_reg_dout),
      .reg_cfg_we(s_tim1_cfg_reg_sel ? natv_wstrb_i[0] : 1'b0),
      .reg_cfg_di(natv_wdata_i),
      .reg_cfg_do(s_tim1_cfg_reg_dout),
      .reg_dat_we(s_tim1_dat_reg_sel ? natv_wstrb_i : 4'h0),
      .reg_dat_di(natv_wdata_i),
      .reg_dat_do(s_tim1_dat_reg_dout),
      .irq_out   (irq_o[2])
  );
endmodule
