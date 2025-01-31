/* Simple 32-bit counter-timer for ravenna. */

module counter_timer (
    input             resetn,
    input             clkin,
    input      [ 3:0] reg_val_we,
    input      [31:0] reg_val_di,
    output     [31:0] reg_val_do,
    input             reg_cfg_we,
    input      [31:0] reg_cfg_di,
    output     [31:0] reg_cfg_do,
    input      [ 3:0] reg_dat_we,
    input      [31:0] reg_dat_di,
    output     [31:0] reg_dat_do,
    output reg        irq_out
);

  reg [31:0] value_cur;
  reg [31:0] value_reset;
  reg        enable;  // Enable (start) the counter/timer
  reg        oneshot;  // Set oneshot (1) mode or continuous (0) mode
  reg        updown;  // Count up (1) or down (0)
  reg        irq_ena;  // Enable interrupt on timeout

  // Configuration register
  assign reg_cfg_do = {28'd0, irq_ena, updown, oneshot, enable};

  always @(posedge clkin or negedge resetn) begin
    if (resetn == 1'b0) begin
      enable  <= 1'b0;
      oneshot <= 1'b0;
      updown  <= 1'b0;
      irq_ena <= 1'b0;
    end else begin
      if (reg_cfg_we) begin
        enable  <= reg_cfg_di[0];
        oneshot <= reg_cfg_di[1];
        updown  <= reg_cfg_di[2];
        irq_ena <= reg_cfg_di[3];
      end
    end
  end

  // Counter/timer reset value register

  assign reg_val_do = value_reset;
  always @(posedge clkin or negedge resetn) begin
    if (resetn == 1'b0) begin
      value_reset <= 32'd0;
    end else begin
      if (reg_val_we[3]) value_reset[31:24] <= reg_val_di[31:24];
      if (reg_val_we[2]) value_reset[23:16] <= reg_val_di[23:16];
      if (reg_val_we[1]) value_reset[15:8] <= reg_val_di[15:8];
      if (reg_val_we[0]) value_reset[7:0] <= reg_val_di[7:0];
    end
  end

  assign reg_dat_do = value_cur;

  // Counter/timer current value register and timer implementation
  always @(posedge clkin or negedge resetn) begin
    if (resetn == 1'b0) begin
      value_cur <= 32'd0;
      irq_out   <= 1'b0;
    end else begin
      if (reg_dat_we != 4'b0000) begin
        if (reg_dat_we[3] == 1'b1) value_cur[31:24] <= reg_dat_di[31:24];
        if (reg_dat_we[2] == 1'b1) value_cur[23:16] <= reg_dat_di[23:16];
        if (reg_dat_we[1] == 1'b1) value_cur[15:8] <= reg_dat_di[15:8];
        if (reg_dat_we[0] == 1'b1) value_cur[7:0] <= reg_dat_di[7:0];
      end else if (enable == 1'b1) begin
        if (updown == 1'b1) begin
          if (value_cur == value_reset) begin
            if (oneshot != 1'b1) begin
              value_cur <= 32'd0;
            end
            irq_out <= irq_ena;
          end else begin
            value_cur <= value_cur + 1;  // count up
            irq_out   <= 1'b0;
          end
        end else begin
          if (value_cur == 32'd0) begin
            if (oneshot != 1'b1) begin
              value_cur <= value_reset;
            end
            irq_out <= irq_ena;
          end else begin
            value_cur <= value_cur - 1;  // count down
            irq_out   <= 1'b0;
          end
        end
      end else begin
        irq_out <= 1'b0;
      end
    end
  end

endmodule
