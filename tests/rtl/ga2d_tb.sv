`timescale 1ns / 1ps

`include "ga2d_define.svh"

module ga2d_tb;
  logic               clk_i = 1'b0;
  logic               rst_n_i = 1'b0;
  logic               busy_i = 1'b0;
  logic               draining_i = 1'b0;
  logic               quiesced_i = 1'b0;
  logic               data_ready_i = 1'b1;
  logic               recovery_required_i = 1'b0;
  logic               idle_i = 1'b1;
  logic               done_i = 1'b0;
  logic               aborted_i = 1'b0;
  logic               error_i = 1'b0;
  logic        [ 2:0] irq_event_i = 3'd0;
  logic               error_valid_i = 1'b0;
  logic        [ 6:0] error_code_i = 7'd0;
  logic        [ 3:0] error_stage_i = 4'd0;
  logic        [ 1:0] error_axi_response_i = 2'd0;
  logic        [31:0] error_address_i = 32'd0;
  logic               soft_reset_o;
  logic               abort_o;
  logic               start_o;
  logic               snapshot_o;
  logic               idle_o;
  logic               irq_o;
  logic        [63:0] cycles_i = 64'd0;
  logic        [63:0] read_bytes_i = 64'd0;
  logic        [63:0] write_bytes_i = 64'd0;
  logic        [63:0] read_stalls_i = 64'd0;
  logic        [63:0] write_stalls_i = 64'd0;
  logic        [63:0] pipe_stalls_i = 64'd0;
  logic        [15:0] lines_done_i = 16'd0;
  logic        [31:0] read_data;
  int unsigned        soft_reset_count;
  int unsigned        start_count;
  int unsigned        snapshot_count;

  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

  always @(posedge clk_i) begin
    if (soft_reset_o) begin
      soft_reset_count++;
    end
    if (start_o) begin
      start_count++;
    end
    if (snapshot_o) begin
      snapshot_count++;
    end
  end

  ga2d_reg u_dut (
      .clk_i               (clk_i),
      .rst_n_i             (rst_n_i),
      .busy_i              (busy_i),
      .draining_i          (draining_i),
      .quiesced_i          (quiesced_i),
      .data_ready_i        (data_ready_i),
      .recovery_required_i (recovery_required_i),
      .idle_i              (idle_i),
      .done_i              (done_i),
      .aborted_i           (aborted_i),
      .error_i             (error_i),
      .irq_event_i         (irq_event_i),
      .error_valid_i       (error_valid_i),
      .error_code_i        (error_code_i),
      .error_stage_i       (error_stage_i),
      .error_axi_response_i(error_axi_response_i),
      .error_address_i     (error_address_i),
      .cycles_i            (cycles_i),
      .read_bytes_i        (read_bytes_i),
      .write_bytes_i       (write_bytes_i),
      .read_stalls_i       (read_stalls_i),
      .write_stalls_i      (write_stalls_i),
      .pipe_stalls_i       (pipe_stalls_i),
      .lines_done_i        (lines_done_i),
      .apb4                (apb4),
      .config_o            (),
      .start_o             (start_o),
      .soft_reset_o        (soft_reset_o),
      .abort_o             (abort_o),
      .snapshot_o          (snapshot_o),
      .idle_o              (idle_o),
      .irq_o               (irq_o)
  );

  task automatic apb_write(input logic [11:0] offset_i, input logic [31:0] value_i,
                           input logic [3:0] strb_i, input logic expected_error_i);
    begin
      @(negedge clk_i);
      apb4.paddr   = {20'd0, offset_i};
      apb4.pwrite  = 1'b1;
      apb4.pwdata  = value_i;
      apb4.pstrb   = strb_i;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b1;
      @(posedge clk_i);
      #1;
      if (!apb4.pready || (apb4.pslverr != expected_error_i)) begin
        $fatal(1, "GA2D APB write response mismatch at %h", offset_i);
      end
      @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
      apb4.pwrite  = 1'b0;
      apb4.pstrb   = '0;
    end
  endtask

  task automatic apb_read(input logic [11:0] offset_i, input logic expected_error_i,
                          output logic [31:0] value_o);
    begin
      @(negedge clk_i);
      apb4.paddr   = {20'd0, offset_i};
      apb4.pwrite  = 1'b0;
      apb4.pstrb   = '0;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b1;
      @(posedge clk_i);
      #1;
      if (!apb4.pready || (apb4.pslverr != expected_error_i)) begin
        $fatal(1, "GA2D APB read response mismatch at %h", offset_i);
      end
      value_o = apb4.prdata;
      @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  task automatic held_soft_reset;
    begin
      @(negedge clk_i);
      apb4.paddr   = {20'd0, `APB4_GA2D__COMMAND};
      apb4.pwrite  = 1'b1;
      apb4.pwdata  = 32'h0000_0004;
      apb4.pstrb   = 4'hf;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b1;
      @(posedge clk_i);
      #1;
      if (!apb4.pready || apb4.pslverr) begin
        $fatal(1, "GA2D soft reset response mismatch");
      end
      repeat (3) begin
        @(posedge clk_i);
        #1;
        if (apb4.pready) begin
          $fatal(1, "held GA2D APB access produced a second response");
        end
      end
      if (soft_reset_count != 1) begin
        $fatal(1, "held GA2D APB access repeated SOFT_RESET");
      end
      @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
      apb4.pwrite  = 1'b0;
      apb4.pstrb   = '0;
    end
  endtask

  initial begin
    apb4.paddr       = '0;
    apb4.pprot       = '0;
    apb4.psel        = 1'b0;
    apb4.penable     = 1'b0;
    apb4.pwrite      = 1'b0;
    apb4.pwdata      = '0;
    apb4.pstrb       = '0;
    soft_reset_count = 0;
    start_count      = 0;
    snapshot_count   = 0;

    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;

    apb_read(`APB4_GA2D__IP_ID, 1'b0, read_data);
    if (read_data != 32'h4741_3244) $fatal(1, "GA2D IP_ID mismatch");
    apb_read(`APB4_GA2D__IP_VERSION, 1'b0, read_data);
    if (read_data != 32'h0001_0000) $fatal(1, "GA2D IP_VERSION mismatch");
    apb_read(`APB4_GA2D__CAPABILITY, 1'b0, read_data);
    if (read_data != 32'h0000_03e3) $fatal(1, "GA2D P4 capability mismatch");
    apb_read(`APB4_GA2D__LIMITS, 1'b0, read_data);
    if (read_data != 32'h0820_2010) $fatal(1, "GA2D P4 limits mismatch");
    apb_read(`APB4_GA2D__FORMAT_CAPABILITY, 1'b0, read_data);
    if (read_data != 32'h000f_000f) $fatal(1, "GA2D P4 format capability mismatch");
    apb_read(`APB4_GA2D__TIMEOUT_CYCLES, 1'b0, read_data);
    if (read_data != 32'h0010_0000) $fatal(1, "GA2D timeout reset mismatch");
    apb_read(`APB4_GA2D__GLOBAL_ALPHA, 1'b0, read_data);
    if (read_data != 32'h0000_00ff) $fatal(1, "GA2D alpha reset mismatch");

    apb_write(`APB4_GA2D__TIMEOUT_CYCLES, 32'd0, 4'hf, 1'b1);
    apb_write(`APB4_GA2D__TIMEOUT_CYCLES, 32'h1122_3344, 4'h7, 1'b1);
    apb_write(`APB4_GA2D__GLOBAL_ALPHA, 32'h0000_0055, 4'hf, 1'b0);
    apb_write(`APB4_GA2D__FG_FORMAT, 32'h0000_0005, 4'hf, 1'b0);
    apb_write(`APB4_GA2D__JOB_CONFIG, 32'h0000_0004, 4'hf, 1'b1);
    apb_write(`APB4_GA2D__IP_ID, 32'h0000_0000, 4'hf, 1'b1);
    apb_read(`APB4_GA2D__GLOBAL_ALPHA, 1'b0, read_data);
    if (read_data != 32'h0000_0055) $fatal(1, "GA2D alpha write mismatch");
    apb_read(`APB4_GA2D__FG_FORMAT, 1'b0, read_data);
    if (read_data != 32'h0000_0005) $fatal(1, "GA2D format shadow mismatch");
    apb_read(12'h06c, 1'b1, read_data);
    apb_read(12'h003, 1'b1, read_data);

    apb_write(`APB4_GA2D__COMMAND, 32'h0000_0001, 4'hf, 1'b0);
    if (start_count != 1) $fatal(1, "GA2D P4 START did not execute exactly once");
    cycles_i      = 64'h1122_3344_5566_7788;
    read_bytes_i  = 64'h0102_0304_0506_0708;
    write_bytes_i = 64'h8877_6655_4433_2211;
    lines_done_i  = 16'h0023;
    apb_write(`APB4_GA2D__PERF_SNAPSHOT, 32'h0000_0001, 4'hf, 1'b0);
    if (snapshot_count != 1) $fatal(1, "GA2D P4 snapshot did not execute exactly once");
    apb_read(`APB4_GA2D__SNAP_CYCLES_LO, 1'b0, read_data);
    if (read_data != 32'h5566_7788) $fatal(1, "GA2D P4 snapshot cycle mismatch");
    apb_read(`APB4_GA2D__SNAP_READ_BYTES_HI, 1'b0, read_data);
    if (read_data != 32'h0102_0304) $fatal(1, "GA2D P4 snapshot read mismatch");
    apb_read(`APB4_GA2D__SNAP_LINES_DONE, 1'b0, read_data);
    if (read_data != 32'h0000_0023) $fatal(1, "GA2D P4 snapshot line mismatch");

    @(negedge clk_i);
    irq_event_i = `APB4_GA2D__IRQ_ALL;
    @(posedge clk_i);
    #1;
    irq_event_i = '0;
    apb_write(`APB4_GA2D__IRQ_ENABLE, `APB4_GA2D__IRQ_ALL, 4'hf, 1'b0);
    if (!irq_o) $fatal(1, "GA2D raw IRQ did not assert");
    irq_event_i = 3'b001;
    apb_write(`APB4_GA2D__IRQ_STATE, 32'h0000_0007, 4'hf, 1'b0);
    irq_event_i = '0;
    apb_read(`APB4_GA2D__IRQ_STATE, 1'b0, read_data);
    if (read_data != 32'h0000_0001) $fatal(1, "GA2D IRQ set did not dominate W1C");
    apb_write(`APB4_GA2D__IRQ_STATE, 32'h0000_0001, 4'hf, 1'b0);
    apb_read(`APB4_GA2D__IRQ_STATE, 1'b0, read_data);
    if (read_data != 32'd0 || irq_o) $fatal(1, "GA2D IRQ clear mismatch");
    apb_write(`APB4_GA2D__IRQ_ENABLE, 32'h0000_0008, 4'hf, 1'b1);

    @(negedge clk_i);
    error_valid_i        = 1'b1;
    error_code_i         = 7'd11;
    error_stage_i        = 4'd5;
    error_axi_response_i = 2'd2;
    error_address_i      = 32'h3000_0040;
    @(posedge clk_i);
    #1;
    error_valid_i = 1'b0;
    apb_read(`APB4_GA2D__ERROR_STATUS, 1'b0, read_data);
    if (read_data != 32'h0000_2517) $fatal(1, "GA2D first error status mismatch");
    apb_read(`APB4_GA2D__ERROR_ADDRESS, 1'b0, read_data);
    if (read_data != 32'h3000_0040) $fatal(1, "GA2D first error address mismatch");
    apb_write(`APB4_GA2D__ERROR_STATUS, 32'h0000_0001, 4'hf, 1'b0);
    apb_read(`APB4_GA2D__ERROR_STATUS, 1'b0, read_data);
    if (read_data != 32'd0) $fatal(1, "GA2D error W1C mismatch");

    held_soft_reset();
    apb_read(`APB4_GA2D__GLOBAL_ALPHA, 1'b0, read_data);
    if (read_data != 32'h0000_00ff) $fatal(1, "GA2D soft reset did not restore alpha");
    apb_read(`APB4_GA2D__IRQ_ENABLE, 1'b0, read_data);
    if (read_data != 32'd0) $fatal(1, "GA2D soft reset did not clear IRQ enable");

    data_ready_i = 1'b0;
    apb_write(`APB4_GA2D__COMMAND, 32'h0000_0004, 4'hf, 1'b1);
    data_ready_i = 1'b1;
    busy_i       = 1'b1;
    apb_write(`APB4_GA2D__COLOR, 32'h1122_3344, 4'hf, 1'b1);
    busy_i              = 1'b0;

    busy_i              = 1'b1;
    draining_i          = 1'b1;
    quiesced_i          = 1'b1;
    data_ready_i        = 1'b0;
    done_i              = 1'b1;
    aborted_i           = 1'b1;
    recovery_required_i = 1'b1;
    apb_read(`APB4_GA2D__STATUS, 1'b0, read_data);
    if (read_data != 32'h0000_00b7) $fatal(1, "GA2D live status mismatch");

    $display("GA2D P4 APB shell test passed");
    $finish;
  end

  initial begin
    repeat (400) @(posedge clk_i);
    $fatal(1, "GA2D P4 APB shell test timed out");
  end
endmodule
