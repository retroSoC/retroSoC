module natv_ip_wrapper (
    input             clk_i,
    input             rst_n_i,
    // natv if
    input             natv_valid_i,
    input      [31:0] natv_addr_i,
    input      [31:0] natv_wdata_i,
    input      [ 3:0] natv_wstrb_i,
    output     [31:0] natv_rdata_o,
    output            natv_ready_o,
    // gpio
    output     [15:0] gpio_out_o,
    input      [15:0] gpio_in_i,
    output     [15:0] gpio_pub_o,
    output     [15:0] gpio_pdb_o,
    output     [15:0] gpio_oeb_o,
    // uart
    input             uart_rx_i,
    output            uart_tx_o,
    // psram if
    output            psram_cfg_wait_wr_en_o,
    input      [ 4:0] psram_cfg_wait_i,
    output reg [ 4:0] psram_cfg_wait_o,
    output            psram_cfg_chd_wr_en_o,
    input      [ 2:0] psram_cfg_chd_i,
    output reg [ 2:0] psram_cfg_chd_o,
    output     [ 2:0] irq_o
);

  wire        s_natv_ready_d;
  wire        s_natv_ready_q;
  reg  [31:0] r_mmap_rdata;
  // gpio
  reg  [15:0] r_gpio;
  reg  [15:0] r_gpio_pub;
  reg  [15:0] r_gpio_pdb;
  reg  [15:0] r_gpio_oeb;
  // uart
  wire        s_uart_div_reg_sel;
  wire        s_uart_dat_reg_sel;
  wire [31:0] s_uart_div_reg_dout;
  wire [31:0] s_uart_dat_reg_dout;
  wire        s_uart_dat_reg_wait;
  // tim0
  wire        s_tim0_cfg_reg_sel;
  wire        s_tim0_val_reg_sel;
  wire        s_tim0_dat_reg_sel;
  wire [31:0] s_tim0_cfg_reg_dout;
  wire [31:0] s_tim0_val_reg_dout;
  wire [31:0] s_tim0_dat_reg_dout;
  // tim1
  wire        s_tim1_cfg_reg_sel;
  wire        s_tim1_val_reg_sel;
  wire        s_tim1_dat_reg_sel;
  wire [31:0] s_tim1_cfg_reg_dout;
  wire [31:0] s_tim1_val_reg_dout;
  wire [31:0] s_tim1_dat_reg_dout;
  // psram
  wire        s_psram_wait_reg_sel;
  wire        s_psram_chd_reg_sel;

  assign natv_rdata_o           = r_mmap_rdata;
  assign natv_ready_o           = s_natv_ready_q;
  // gpio
  assign gpio_out_o             = r_gpio;
  assign gpio_oeb_o             = {16{~rst_n_i}} | r_gpio_oeb;
  assign gpio_pub_o             = r_gpio_pub;
  assign gpio_pdb_o             = r_gpio_pdb;

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

  assign psram_cfg_wait_wr_en_o = s_psram_wait_reg_sel ? natv_wstrb_i[0] : 1'b0;
  assign psram_cfg_chd_wr_en_o  = s_psram_chd_reg_sel ? natv_wstrb_i[0] : 1'b0;

  always @(posedge clk_i, negedge rst_n_i) begin
    if (!rst_n_i) begin
      r_gpio       <= 16'd0;
      r_gpio_pub   <= 16'd0;
      r_gpio_pdb   <= 16'd0;
      r_gpio_oeb   <= 16'hFFFF;
      r_mmap_rdata <= 32'd0;
    end else begin
      if (natv_valid_i && !s_natv_ready_q) begin
        case (natv_addr_i[15:0])
          16'h0000: begin
            r_mmap_rdata <= {gpio_out_o, gpio_in_i};
            if (natv_wstrb_i[0]) r_gpio[7:0] <= natv_wdata_i[7:0];
            if (natv_wstrb_i[1]) r_gpio[15:8] <= natv_wdata_i[15:8];
          end
          16'h0004: begin
            r_mmap_rdata <= {16'd0, r_gpio_oeb};
            if (natv_wstrb_i[0]) r_gpio_oeb[7:0] <= natv_wdata_i[7:0];
            if (natv_wstrb_i[1]) r_gpio_oeb[15:8] <= natv_wdata_i[15:8];
          end
          16'h0008: begin
            r_mmap_rdata <= {16'd0, r_gpio_pub};
            if (natv_wstrb_i[0]) r_gpio_pub[7:0] <= natv_wdata_i[7:0];
            if (natv_wstrb_i[1]) r_gpio_pub[15:8] <= natv_wdata_i[15:8];
          end
          16'h000C: begin
            r_mmap_rdata <= {16'd0, r_gpio_pub};
            if (natv_wstrb_i[0]) r_gpio_pdb[7:0] <= natv_wdata_i[7:0];
            if (natv_wstrb_i[1]) r_gpio_pdb[15:8] <= natv_wdata_i[15:8];
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
            if (natv_wstrb_i[0]) psram_cfg_wait_o <= natv_wdata_i[4:0];
          end
          16'h4004: begin
            r_mmap_rdata <= {29'd0, psram_cfg_chd_i};
            if (natv_wstrb_i[0]) psram_cfg_chd_o <= natv_wdata_i[2:0];
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

  simpleuart u_simpleuart (
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

  counter_timer u_counter_timer0 (
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

  counter_timer u_counter_timer1 (
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
