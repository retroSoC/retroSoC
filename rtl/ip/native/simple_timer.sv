/* Simple 32-bit counter-timer for ravenna. */

module simple_timer (
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic [ 3:0] reg_val_we,
    input  logic [31:0] reg_val_di,
    output logic [31:0] reg_val_do,
    input  logic        reg_cfg_we,
    input  logic [31:0] reg_cfg_di,
    output logic [31:0] reg_cfg_do,
    input  logic [ 3:0] reg_dat_we,
    input  logic [31:0] reg_dat_di,
    output logic [31:0] reg_dat_do,
    output logic        irq_out
);

  logic [31:0] r_value_cur;
  logic [31:0] r_value_reset;
  // Enable (start) the counter/timer
  // Set r_oneshot (1) mode or continuous (0) mode
  // Count up (1) or down (0)
  // Enable interrupt on timeout
  logic        r_ena;
  logic        r_oneshot;
  logic        r_updown;
  logic        r_irq_ena;

  // Configuration register
  assign reg_cfg_do = {28'd0, r_irq_ena, r_updown, r_oneshot, r_ena};

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (rst_n_i == 1'b0) begin
      r_ena     <= '0;
      r_oneshot <= '0;
      r_updown  <= '0;
      r_irq_ena <= '0;
    end else begin
      if (reg_cfg_we) begin
        r_ena     <= reg_cfg_di[0];
        r_oneshot <= reg_cfg_di[1];
        r_updown  <= reg_cfg_di[2];
        r_irq_ena <= reg_cfg_di[3];
      end
    end
  end

  // Counter/timer reset value register
  assign reg_val_do = r_value_reset;
  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (rst_n_i == 1'b0) begin
      r_value_reset <= '0;
    end else begin
      if (reg_val_we[3]) r_value_reset[31:24] <= reg_val_di[31:24];
      if (reg_val_we[2]) r_value_reset[23:16] <= reg_val_di[23:16];
      if (reg_val_we[1]) r_value_reset[15:8] <= reg_val_di[15:8];
      if (reg_val_we[0]) r_value_reset[7:0] <= reg_val_di[7:0];
    end
  end

  assign reg_dat_do = r_value_cur;

  // Counter/timer current value register and timer implementation
  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (rst_n_i == 1'b0) begin
      r_value_cur <= '0;
      irq_out     <= '0;
    end else begin
      if (reg_dat_we != '0) begin
        if (reg_dat_we[3] == 1'b1) r_value_cur[31:24] <= reg_dat_di[31:24];
        if (reg_dat_we[2] == 1'b1) r_value_cur[23:16] <= reg_dat_di[23:16];
        if (reg_dat_we[1] == 1'b1) r_value_cur[15:8] <= reg_dat_di[15:8];
        if (reg_dat_we[0] == 1'b1) r_value_cur[7:0] <= reg_dat_di[7:0];
      end else if (r_ena == 1'b1) begin
        if (r_updown == 1'b1) begin
          if (r_value_cur == r_value_reset) begin
            if (r_oneshot != 1'b1) begin
              r_value_cur <= '0;
            end
            irq_out <= r_irq_ena;
          end else begin
            r_value_cur <= r_value_cur + 1;  // count up
            irq_out     <= '0;
          end
        end else begin
          if (r_value_cur == '0) begin
            if (r_oneshot != 1'b1) begin
              r_value_cur <= r_value_reset;
            end
            irq_out <= r_irq_ena;
          end else begin
            r_value_cur <= r_value_cur - 1;  // count down
            irq_out     <= '0;
          end
        end
      end else begin
        irq_out <= '0;
      end
    end
  end

endmodule
