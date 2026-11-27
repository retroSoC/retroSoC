`timescale 1ns / 1ps
`include "gpio_define.svh"
`include "piolite_define.svh"

module piolite_p3_gpio_tb;
  localparam logic [31:0] GpioAdminBase = 32'h1001_4000;
  localparam logic [31:0] Pin31 = 32'h8000_0000;

  logic          clk_i = 1'b0;
  logic          pio_rst_n_i = 1'b0;
  logic          gpio_rst_n_i = 1'b0;
  logic          gpio_ready_i = 1'b1;
  logic   [31:0] external_input = 32'd0;
  logic   [31:0] user_select;
  logic   [31:0] user_handoff;
  logic   [31:0] filter_enable;
  logic   [31:0] alt_enable;
  logic   [31:0] alt_select;
  logic   [31:0] output_enable;
  logic   [31:0] open_drain;
  logic   [31:0] pio_value;
  logic   [31:0] pio_oe;
  logic   [31:0] rx_data = 32'd0;
  logic          rx_valid;
  logic   [ 3:0] rx_keep;
  logic   [ 3:0] rx_strb;
  logic          rx_last;
  logic          rx_id;
  logic          rx_dest;
  logic          rx_user;
  logic          tx_ready;
  logic          tx_admit;
  logic          rx_admit;
  logic   [ 7:0] tx_channel_admit;
  logic   [ 7:0] rx_channel_admit;
  logic          lifecycle_idle;
  logic          irq;
  logic          dma_tx_job = 1'b0;
  logic          dma_rx_job = 1'b0;
  logic   [ 7:0] dma_tx_channel_job = 8'd0;
  logic   [ 7:0] dma_rx_channel_job = 8'd0;
  logic   [ 7:0] dma_channel_busy = 8'd0;
  logic   [ 7:0] dma_start_pending = 8'd0;
  logic          handoff_seen = 1'b0;
  integer        rx_count = 0;
  logic   [31:0] value;

  apb4_if pio_apb (
      .pclk   (clk_i),
      .presetn(pio_rst_n_i)
  );
  apb4_if gpio_apb (
      .pclk   (clk_i),
      .presetn(gpio_rst_n_i)
  );
  gpio_if gpio ();
  user_gpio_if user_gpio ();

  always #5 clk_i = ~clk_i;

  assign gpio.di_i      = (gpio.oe_o & gpio.do_o) | (~gpio.oe_o & external_input);
  assign user_gpio.do_o = pio_value;
  assign user_gpio.oe_o = pio_oe;

  apb4_gpio u_gpio (
      .clk_i          (clk_i),
      .rst_n_i        (gpio_rst_n_i),
      .apb4           (gpio_apb),
      .gpio           (gpio),
      .user_gpio      (user_gpio),
      .user_select_o  (user_select),
      .user_handoff_o (user_handoff),
      .alt_enable_o   (alt_enable),
      .alt_select_o   (alt_select),
      .output_enable_o(output_enable),
      .open_drain_o   (open_drain),
      .filter_enable_o(filter_enable)
  );

  apb4_piolite #(
      .DmaChannelCount(8)
  ) u_pio (
      .clk_i                 (clk_i),
      .rst_n_i               (pio_rst_n_i),
      .clock_hz_i            (32'd24000000),
      .user_select_i         (user_select),
      .user_status_i         (user_select & ~user_handoff),
      .filter_enable_i       (filter_enable),
      .gpio_ready_i          (gpio_rst_n_i && gpio_ready_i),
      .gpio_input_i          (user_gpio.di_i),
      .gpio_value_o          (pio_value),
      .gpio_oe_o             (pio_oe),
      .dma_tx_job_i          (dma_tx_job),
      .dma_rx_job_i          (dma_rx_job),
      .dma_tx_channel_job_i  (dma_tx_channel_job),
      .dma_rx_channel_job_i  (dma_rx_channel_job),
      .dma_channel_busy_i    (dma_channel_busy),
      .dma_start_pending_i   (dma_start_pending),
      .dma_tx_valid_i        (1'b0),
      .dma_tx_ready_o        (tx_ready),
      .dma_tx_data_i         (32'd0),
      .dma_tx_keep_i         (4'hf),
      .dma_tx_strb_i         (4'hf),
      .dma_tx_id_i           (1'b0),
      .dma_tx_dest_i         (1'b0),
      .dma_tx_user_i         (1'b0),
      .dma_tx_last_i         (1'b0),
      .dma_rx_valid_o        (rx_valid),
      .dma_rx_ready_i        (1'b1),
      .dma_rx_data_o         (rx_data),
      .dma_rx_keep_o         (rx_keep),
      .dma_rx_strb_o         (rx_strb),
      .dma_rx_last_o         (rx_last),
      .dma_rx_id_o           (rx_id),
      .dma_rx_dest_o         (rx_dest),
      .dma_rx_user_o         (rx_user),
      .dma_tx_admit_o        (tx_admit),
      .dma_rx_admit_o        (rx_admit),
      .dma_tx_channel_admit_o(tx_channel_admit),
      .dma_rx_channel_admit_o(rx_channel_admit),
      .lifecycle_idle_o      (lifecycle_idle),
      .irq_o                 (irq),
      .apb4                  (pio_apb)
  );

  always @(posedge clk_i) begin
    if (!gpio_rst_n_i) begin
      handoff_seen <= 1'b0;
    end else begin
      if (|user_handoff) begin
        handoff_seen <= 1'b1;
        if (|(gpio.oe_o & user_handoff)) $fatal(1, "GPIO handoff did not clamp OE");
      end
      if (|(pio_oe & ~(user_select & ~user_handoff & ~filter_enable))) begin
        $fatal(1, "PIO output escaped its ownership guard");
      end
      if (!gpio_ready_i && (pio_oe != 32'd0)) $fatal(1, "PIO output escaped readiness clamp");
    end
    if (!pio_rst_n_i) begin
      rx_count <= 0;
    end else if (rx_valid) begin
      rx_count <= rx_count + 1;
    end
  end

  task automatic pio_access(input logic write_access, input logic [11:0] offset,
                            input logic [31:0] data, input logic error_expected,
                            output logic [31:0] result);
    begin
      @(negedge clk_i);
      pio_apb.psel    = 1'b1;
      pio_apb.penable = 1'b0;
      pio_apb.pwrite  = write_access;
      pio_apb.paddr   = {20'd0, offset};
      pio_apb.pwdata  = data;
      pio_apb.pstrb   = write_access ? 4'hf : 4'd0;
      pio_apb.pprot   = 3'd0;
      @(negedge clk_i);
      pio_apb.penable = 1'b1;
      for (integer timeout = 0; !pio_apb.pready; timeout++) begin
        if (timeout == 4) $fatal(1, "PIO APB timeout offset=%h", offset);
        @(negedge clk_i);
      end
      if (pio_apb.pslverr !== error_expected) begin
        $fatal(
            1,
            "PIO APB offset=%h data=%h error=%b expected=%b writable=%b sm=%b/%h state=%0d cfg=%h",
            offset, data, pio_apb.pslverr, error_expected, u_pio.u_reg.s_cfg_writable,
            u_pio.u_reg.s_sm_access, u_pio.u_reg.s_sm_offset, u_pio.u_ctrl.runtime[1].state,
            u_pio.u_ctrl.cfg[1]);
      end
      result = pio_apb.prdata;
      @(negedge clk_i);
      pio_apb.psel    = 1'b0;
      pio_apb.penable = 1'b0;
    end
  endtask

  task automatic pio_wr(input logic [11:0] offset, input logic [31:0] data, input logic err);
    logic [31:0] unused;
    begin
      pio_access(1'b1, offset, data, err, unused);
    end
  endtask

  task automatic pio_rd(input logic [11:0] offset, output logic [31:0] data);
    begin
      pio_access(1'b0, offset, 32'd0, 1'b0, data);
    end
  endtask

  task automatic pio_check(input logic [11:0] offset, input logic [31:0] expected);
    logic [31:0] observed;
    begin
      pio_rd(offset, observed);
      if (observed !== expected) begin
        $fatal(1, "PIO register %h got=%h expected=%h", offset, observed, expected);
      end
    end
  endtask

  task automatic gpio_access(input logic write_access, input logic [11:0] offset,
                             input logic [31:0] data, input logic error_expected,
                             output logic [31:0] result);
    begin
      @(negedge clk_i);
      gpio_apb.psel    = 1'b1;
      gpio_apb.penable = 1'b0;
      gpio_apb.pwrite  = write_access;
      gpio_apb.paddr   = GpioAdminBase + {20'd0, offset};
      gpio_apb.pwdata  = data;
      gpio_apb.pstrb   = write_access ? 4'hf : 4'd0;
      gpio_apb.pprot   = 3'd0;
      @(negedge clk_i);
      gpio_apb.penable = 1'b1;
      for (integer timeout = 0; !gpio_apb.pready; timeout++) begin
        if (timeout == 4) $fatal(1, "GPIO APB timeout offset=%h", offset);
        @(negedge clk_i);
      end
      if (gpio_apb.pslverr !== error_expected) begin
        $fatal(1, "GPIO APB offset=%h error=%b expected=%b", offset, gpio_apb.pslverr,
               error_expected);
      end
      result = gpio_apb.prdata;
      @(negedge clk_i);
      gpio_apb.psel    = 1'b0;
      gpio_apb.penable = 1'b0;
    end
  endtask

  task automatic gpio_wr(input logic [11:0] offset, input logic [31:0] data, input logic err);
    logic [31:0] unused;
    begin
      gpio_access(1'b1, offset, data, err, unused);
    end
  endtask

  task automatic gpio_rd(input logic [11:0] offset, output logic [31:0] data);
    begin
      gpio_access(1'b0, offset, 32'd0, 1'b0, data);
    end
  endtask

  task automatic wait_sm(input integer sm, input logic [2:0] expected);
    logic [31:0] status;
    begin
      status = 32'hffff_ffff;
      for (integer timeout = 0; (status[2:0] != expected) && (timeout < 20); timeout++) begin
        pio_rd(12'h200 + (sm * 12'h80), status);
      end
      if (status[2:0] != expected) begin
        $fatal(1, "SM%0d state=%0d expected=%0d", sm, status[2:0], expected);
      end
    end
  endtask

  task automatic configure_sm(input integer sm, input logic [31:0] claim,
                              input logic [31:0] outputs);
    logic [11:0] base;
    begin
      base = 12'h200 + (sm * 12'h80);
      pio_wr(base + 12'h004, 32'd0, 1'b0);
      pio_wr(base + 12'h008, 32'd1, 1'b0);
      pio_wr(base + 12'h014, 32'd0, 1'b0);
      pio_wr(base + 12'h018, 32'd0, 1'b0);
      pio_wr(base + 12'h01c, 32'd0, 1'b0);
      pio_wr(base + 12'h020, claim, 1'b0);
      pio_wr(base + 12'h024, outputs, 1'b0);
      pio_wr(base + 12'h028, 32'd0, 1'b0);
      pio_wr(base + 12'h02c, 32'd0, 1'b0);
      pio_wr(base + 12'h030, 32'd0, 1'b0);
      pio_wr(base + 12'h034, 32'h0000_2020, 1'b0);
      pio_wr(base + 12'h038, 32'd0, 1'b0);
      pio_wr(base + 12'h03c, 32'h0000_0100, 1'b0);
    end
  endtask

  task automatic configure_program(input integer sm, input logic [4:0] base,
                                   input logic [5:0] length, input logic [4:0] top);
    logic [11:0] sm_base;
    begin
      sm_base = 12'h200 + (sm * 12'h80);
      pio_wr(sm_base + 12'h00c, (32'(length) << 8) | (32'(base) << 16) | 32'(base), 1'b0);
      pio_wr(sm_base + 12'h010, (32'(top) << 8) | 32'(base), 1'b0);
    end
  endtask

  task automatic quiesce;
    begin
      dma_tx_job         = 1'b0;
      dma_rx_job         = 1'b0;
      dma_tx_channel_job = 8'd0;
      dma_rx_channel_job = 8'd0;
      dma_channel_busy   = 8'd0;
      dma_start_pending  = 8'd0;
      pio_wr(12'h050, 32'd3, 1'b0);
      pio_wr(12'h054, 32'd3, 1'b0);
      configure_sm(0, 32'd0, 32'd0);
      configure_sm(1, 32'd0, 32'd0);
    end
  endtask

  task automatic reset_all;
    begin
      pio_rst_n_i      = 1'b0;
      gpio_rst_n_i     = 1'b0;
      gpio_ready_i     = 1'b1;
      external_input   = 32'd0;
      pio_apb.psel     = 1'b0;
      pio_apb.penable  = 1'b0;
      pio_apb.pwrite   = 1'b0;
      pio_apb.paddr    = 32'd0;
      pio_apb.pwdata   = 32'd0;
      pio_apb.pstrb    = 4'd0;
      pio_apb.pprot    = 3'd0;
      gpio_apb.psel    = 1'b0;
      gpio_apb.penable = 1'b0;
      gpio_apb.pwrite  = 1'b0;
      gpio_apb.paddr   = 32'd0;
      gpio_apb.pwdata  = 32'd0;
      gpio_apb.pstrb   = 4'd0;
      gpio_apb.pprot   = 3'd0;
      gpio.alt0_do_i   = 32'd0;
      gpio.alt0_oe_i   = 32'd0;
      gpio.alt1_do_i   = 32'd0;
      gpio.alt1_oe_i   = 32'd0;
      repeat (4) @(negedge clk_i);
      pio_rst_n_i  = 1'b1;
      gpio_rst_n_i = 1'b1;
      repeat (4) @(negedge clk_i);
    end
  endtask

  initial begin
    reset_all();
    configure_sm(0, 32'hffff_ffff, 32'hffff_ffff);
    configure_sm(1, 32'hffff_ffff, 32'd0);
    pio_wr(12'h100, 32'h0000_0020, 1'b0);
    pio_wr(12'h104, 32'h0000_4000, 1'b0);
    pio_wr(12'h108, 32'h0000_70c0, 1'b0);
    pio_wr(12'h10c, 32'h0000_0020, 1'b0);
    configure_program(0, 0, 1, 0);
    configure_program(1, 1, 3, 3);
    pio_wr(12'h218, 32'd0, 1'b0);
    pio_wr(12'h228, 32'ha55a_3cc3, 1'b0);
    pio_wr(12'h22c, 32'hffff_ffff, 1'b0);
    pio_wr(12'h294, 32'h0000_2000, 1'b0);
    gpio_wr(`APB4_GPIO_ADMIN_OE_SET, 32'd1, 1'b0);
    gpio_wr(`APB4_GPIO_ADMIN_ALT_SELECT, 32'h5555_aaaa, 1'b0);
    pio_wr(12'h040, 32'd1, 1'b1);
    gpio_wr(`APB4_GPIO_ADMIN_USER_SELECT, 32'hffff_ffff, 1'b0);
    gpio_rd(`APB4_GPIO_ADMIN_USER_STATUS, value);
    if ((value != 32'hffff_ffff) || !handoff_seen) $fatal(1, "GPIO acquisition did not finish");
    if (alt_select != 32'h5555_aaaa) $fatal(1, "GPIO ALT select changed during acquisition");
    pio_check(12'h03c, 32'hffff_ffff);
    pio_wr(12'h040, 32'd1, 1'b0);
    wait_sm(0, 3);
    repeat (4) @(negedge clk_i);
    if ((gpio.oe_o != 32'hffff_ffff) || (gpio.do_o != 32'ha55a_3cc3)) begin
      $fatal(1, "32-bit GPIO output mismatch oe=%h data=%h", gpio.oe_o, gpio.do_o);
    end
    pio_wr(12'h030, 32'h8000_0201, 1'b0);
    pio_wr(12'h040, 32'd2, 1'b0);
    wait_sm(1, 3);
    if ((rx_count != 1) || (rx_data != 32'ha55a_3cc3)) begin
      $fatal(1, "32-bit shared input mismatch count=%0d data=%h", rx_count, rx_data);
    end
    $display("P3_GPIO_CASE all32_shared_input");

    quiesce();
    configure_sm(0, 32'd1, 32'd1);
    configure_sm(1, 32'd1, 32'd1);
    pio_wr(12'h100, 32'h0000_0020, 1'b0);
    pio_wr(12'h104, 32'h0000_0020, 1'b0);
    configure_program(0, 0, 1, 0);
    configure_program(1, 1, 1, 1);
    pio_wr(12'h040, 32'd3, 1'b1);
    pio_check(12'h200, 32'd0);
    pio_check(12'h280, 32'd0);
    $display("P3_GPIO_CASE output_overlap_rejected");

    quiesce();
    configure_sm(0, Pin31, Pin31);
    pio_wr(12'h21c, (32'd1 << 8) | 32'd31, 1'b0);
    pio_wr(12'h22c, Pin31, 1'b0);
    pio_wr(12'h100, 32'h0000_1001, 1'b0);
    pio_wr(12'h104, 32'h0000_0020, 1'b0);
    configure_program(0, 0, 2, 1);
    pio_wr(12'h040, 32'd1, 1'b0);
    wait_sm(0, 3);
    if (!gpio.oe_o[31] || !gpio.do_o[31]) $fatal(1, "GPIO31 SET window failed");
    quiesce();
    configure_sm(1, Pin31, 32'd0);
    pio_wr(12'h294, (32'd1 << 8) | 32'd31, 1'b0);
    pio_wr(12'h104, 32'h0000_4001, 1'b0);
    pio_wr(12'h108, 32'h0000_70c0, 1'b0);
    pio_wr(12'h10c, 32'h0000_0020, 1'b0);
    configure_program(1, 1, 3, 3);
    external_input = Pin31;
    pio_wr(12'h030, 32'h8000_0201, 1'b0);
    pio_wr(12'h040, 32'd2, 1'b0);
    wait_sm(1, 3);
    if (rx_data != 32'd1) $fatal(1, "GPIO31 IN window captured %h", rx_data);
    $display("P3_GPIO_CASE gpio31_windows");

    quiesce();
    configure_sm(1, Pin31, 32'd0);
    pio_wr(12'h104, 32'h0000_807e, 1'b0);
    pio_wr(12'h108, 32'h0000_0020, 1'b0);
    configure_program(1, 1, 2, 2);
    external_input = 32'd0;
    pio_wr(12'h040, 32'd2, 1'b0);
    repeat (5) @(negedge clk_i);
    pio_rd(12'h280, value);
    if ((value[2:0] != 1) || (value[6:4] != 1)) $fatal(1, "WAIT31 did not stall on pin");
    external_input = Pin31;
    wait_sm(1, 3);
    quiesce();
    configure_sm(1, 32'd0, 32'd0);
    pio_wr(12'h104, 32'h0000_807e, 1'b0);
    pio_wr(12'h108, 32'h0000_0020, 1'b0);
    configure_program(1, 1, 2, 2);
    pio_wr(12'h040, 32'd2, 1'b0);
    wait_sm(1, 4);
    pio_check(12'h2d4, 32'h0000_0105);
    quiesce();
    configure_sm(1, 32'd0, 32'd0);
    pio_wr(12'h284, 32'h0000_0010, 1'b0);
    pio_wr(12'h2b8, 32'd31, 1'b0);
    pio_wr(12'h104, 32'h0000_0020, 1'b0);
    configure_program(1, 1, 1, 1);
    pio_wr(12'h040, 32'd2, 1'b1);
    $display("P3_GPIO_CASE wait_and_test_authorization");

    quiesce();
    configure_sm(0, 32'd1, 32'd1);
    configure_sm(1, 32'd2, 32'd0);
    pio_wr(12'h228, 32'd1, 1'b0);
    pio_wr(12'h22c, 32'd1, 1'b0);
    pio_wr(12'h100, 32'h0000_0020, 1'b0);
    pio_wr(12'h104, 32'h0000_0020, 1'b0);
    configure_program(0, 0, 1, 0);
    configure_program(1, 1, 1, 1);
    pio_wr(12'h040, 32'd3, 1'b0);
    wait_sm(0, 3);
    wait_sm(1, 3);
    gpio_wr(`APB4_GPIO_ADMIN_FILTER_COUNT, 32'd1, 1'b0);
    gpio_wr(`APB4_GPIO_ADMIN_FILTER_ENABLE, 32'd1, 1'b0);
    wait_sm(0, 4);
    pio_check(12'h254, 32'h0000_0006);
    pio_check(12'h280, 32'h0000_0003);
    if (gpio.oe_o[0]) $fatal(1, "filter loss left GPIO driven");
    gpio_wr(`APB4_GPIO_ADMIN_FILTER_ENABLE, 32'd0, 1'b0);
    pio_wr(12'h054, 32'd1, 1'b0);
    pio_wr(12'h040, 32'd1, 1'b0);
    wait_sm(0, 3);
    pio_wr(12'h050, 32'd1, 1'b0);
    pio_wr(12'h054, 32'd1, 1'b0);
    pio_wr(12'h040, 32'd1, 1'b0);
    wait_sm(0, 3);
    gpio_wr(`APB4_GPIO_ADMIN_USER_SELECT, 32'hffff_fffe, 1'b0);
    wait_sm(0, 4);
    pio_check(12'h254, 32'h0000_0006);
    if (pio_oe[0]) $fatal(1, "ownership loss left PIO USER OE asserted");
    pio_wr(12'h054, 32'd1, 1'b0);
    gpio_wr(`APB4_GPIO_ADMIN_USER_SELECT, 32'hffff_ffff, 1'b0);
    pio_wr(12'h040, 32'd1, 1'b0);
    wait_sm(0, 3);
    pio_wr(12'h050, 32'd1, 1'b0);
    pio_wr(12'h054, 32'd1, 1'b0);
    pio_wr(12'h040, 32'd1, 1'b0);
    wait_sm(0, 3);
    gpio_ready_i = 1'b0;
    wait_sm(0, 4);
    pio_check(12'h254, 32'h0000_0007);
    gpio_ready_i = 1'b1;
    pio_wr(12'h054, 32'd1, 1'b0);
    pio_wr(12'h040, 32'd1, 1'b0);
    wait_sm(0, 3);
    $display("P3_GPIO_CASE guard_loss_and_rearm");

    pio_wr(12'h050, 32'd1, 1'b0);
    pio_wr(12'h054, 32'd1, 1'b0);
    pio_wr(12'h040, 32'd1, 1'b0);
    wait_sm(0, 3);
    gpio_rst_n_i = 1'b0;
    repeat (3) @(negedge clk_i);
    gpio_rst_n_i = 1'b1;
    wait_sm(0, 4);
    pio_wr(12'h054, 32'd1, 1'b0);
    pio_wr(12'h040, 32'd1, 1'b1);
    gpio_wr(`APB4_GPIO_ADMIN_USER_SELECT, 32'hffff_ffff, 1'b0);
    pio_wr(12'h040, 32'd1, 1'b0);
    wait_sm(0, 3);
    $display("P3_GPIO_CASE unexpected_reset_requires_reacquire");

    quiesce();
    configure_sm(0, 32'd1, 32'd0);
    configure_sm(1, 32'd2, 32'd0);
    pio_wr(12'h100, 32'h0000_0020, 1'b0);
    pio_wr(12'h104, 32'h0000_0020, 1'b0);
    configure_program(0, 0, 1, 0);
    configure_program(1, 1, 1, 1);
    pio_wr(12'h02c, 32'h8000_0300, 1'b0);
    pio_wr(12'h030, 32'h8000_0301, 1'b1);
    pio_wr(12'h030, 32'h8000_0201, 1'b0);
    if ((tx_channel_admit != 8'h08) || (rx_channel_admit != 8'h04)) begin
      $fatal(1, "PIO binding admission is not one-hot tx=%h rx=%h", tx_channel_admit,
             rx_channel_admit);
    end
    dma_tx_job         = 1'b1;
    dma_tx_channel_job = 8'h08;
    dma_start_pending  = 8'h08;
    pio_wr(12'h02c, 32'd0, 1'b1);
    pio_check(12'h02c, 32'h8000_0300);
    pio_wr(12'h054, 32'd1, 1'b1);
    dma_tx_job         = 1'b0;
    dma_tx_channel_job = 8'd0;
    dma_start_pending  = 8'd0;
    pio_wr(12'h02c, 32'd0, 1'b0);
    pio_wr(12'h054, 32'd2, 1'b0);
    pio_check(12'h030, 32'd0);
    $display("P3_GPIO_CASE binding_and_reset_races");

    $display("SIM_TEST_PASS PIOLITE_P3_GPIO all32=1 gpio31=1 guards=1 reset_rearm=1 bind_race=1");
    $finish;
  end

  initial begin
    #2000000;
    $fatal(1, "SIM_TEST_TIMEOUT piolite_p3_gpio_tb");
  end
endmodule
