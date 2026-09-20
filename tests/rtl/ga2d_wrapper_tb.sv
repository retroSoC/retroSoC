`timescale 1ns / 1ps

`include "ga2d_define.svh"

module ga2d_wrapper_tb;
  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        resource_quiesce_i = 1'b0;
  logic        resource_reset_i = 1'b0;
  logic        source_stop_i = 1'b0;
  logic        source_safe_idle_i = 1'b1;
  logic        block_ack_i = 1'b0;
  logic        bridge_clear_busy_i = 1'b0;
  logic [ 7:0] bridge_epoch_i = 8'd0;
  logic        data_ready_i = 1'b1;
  logic [ 1:0] mem_pad_mode_i = 2'd0;
  logic        idle_o;
  logic        irq_o;
  logic [31:0] read_data;

  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) ga2d_axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

  assign ga2d_axi4.awready = 1'b1;
  assign ga2d_axi4.wready  = 1'b1;
  assign ga2d_axi4.bid     = '0;
  assign ga2d_axi4.bresp   = 2'd0;
  assign ga2d_axi4.buser   = '0;
  assign ga2d_axi4.bvalid  = 1'b0;
  assign ga2d_axi4.arready = 1'b1;
  assign ga2d_axi4.rid     = '0;
  assign ga2d_axi4.rdata   = '0;
  assign ga2d_axi4.rresp   = 2'd0;
  assign ga2d_axi4.rlast   = 1'b1;
  assign ga2d_axi4.ruser   = '0;
  assign ga2d_axi4.rvalid  = 1'b0;

  apb4_ga2d u_dut (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .resource_quiesce_i (resource_quiesce_i),
      .resource_reset_i   (resource_reset_i),
      .source_stop_i      (source_stop_i),
      .source_safe_idle_i (source_safe_idle_i),
      .block_ack_i        (block_ack_i),
      .bridge_clear_busy_i(bridge_clear_busy_i),
      .bridge_epoch_i     (bridge_epoch_i),
      .data_ready_i       (data_ready_i),
      .mem_pad_mode_i     (mem_pad_mode_i),
      .apb4               (apb4),
      .ga2d_axi4          (ga2d_axi4),
      .idle_o             (idle_o),
      .irq_o              (irq_o)
  );

  task automatic apb_write(input logic [11:0] offset_i, input logic [31:0] value_i,
                           input logic expected_error_i);
    begin
      @(negedge clk_i);
      apb4.paddr   = {20'd0, offset_i};
      apb4.pwrite  = 1'b1;
      apb4.pwdata  = value_i;
      apb4.pstrb   = 4'hf;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b1;
      @(posedge clk_i);
      #1;
      if (!apb4.pready || (apb4.pslverr != expected_error_i)) begin
        $fatal(1, "GA2D wrapper APB write response mismatch at %h", offset_i);
      end
      @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
      apb4.pwrite  = 1'b0;
      apb4.pstrb   = '0;
    end
  endtask

  task automatic apb_read(input logic [11:0] offset_i, output logic [31:0] value_o);
    begin
      @(negedge clk_i);
      apb4.paddr   = {20'd0, offset_i};
      apb4.pwrite  = 1'b0;
      apb4.pstrb   = '0;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b1;
      @(posedge clk_i);
      #1;
      if (!apb4.pready || apb4.pslverr) begin
        $fatal(1, "GA2D wrapper APB read response mismatch at %h", offset_i);
      end
      value_o = apb4.prdata;
      @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  task automatic apb_lifecycle_soft_reset(input logic reset_request_i);
    begin
      @(negedge clk_i);
      resource_quiesce_i = !reset_request_i;
      resource_reset_i   = reset_request_i;
      apb4.paddr         = {20'd0, `APB4_GA2D__COMMAND};
      apb4.pwrite        = 1'b1;
      apb4.pwdata        = 32'h0000_0004;
      apb4.pstrb         = 4'hf;
      apb4.psel          = 1'b1;
      apb4.penable       = 1'b1;
      @(posedge clk_i);
      #1;
      if (!apb4.pready || !apb4.pslverr) begin
        $fatal(1, "GA2D lifecycle request allowed unsafe soft reset");
      end
      @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
      apb4.pwrite  = 1'b0;
      apb4.pstrb   = '0;
    end
  endtask

  initial begin
    apb4.paddr   = '0;
    apb4.pprot   = '0;
    apb4.psel    = 1'b0;
    apb4.penable = 1'b0;
    apb4.pwrite  = 1'b0;
    apb4.pwdata  = '0;
    apb4.pstrb   = '0;

    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;

    if (!idle_o) $fatal(1, "GA2D wrapper did not expose source-safe idle");
    apb_write(`APB4_GA2D__GLOBAL_ALPHA, 32'h0000_0055, 1'b0);
    apb_write(`APB4_GA2D__IRQ_ENABLE, 32'h0000_0001, 1'b0);
    apb_write(`APB4_GA2D__IRQ_TEST, 32'h0000_0001, 1'b0);
    if (!irq_o) $fatal(1, "GA2D wrapper IRQ_TEST did not assert raw IRQ");

    apb_lifecycle_soft_reset(1'b0);
    apb_read(`APB4_GA2D__STATUS, read_data);
    if (read_data[`APB4_GA2D__STATUS_DATA_READY]) begin
      $fatal(1, "GA2D resource quiesce left data ready asserted");
    end
    apb_read(`APB4_GA2D__GLOBAL_ALPHA, read_data);
    if (read_data != 32'h0000_0055) begin
      $fatal(1, "GA2D resource quiesce allowed unsafe soft reset");
    end
    apb_read(`APB4_GA2D__IRQ_STATE, read_data);
    if (read_data != 32'h0000_0001 || !irq_o) begin
      $fatal(1, "GA2D resource quiesce cleared retained diagnostics");
    end
    resource_quiesce_i = 1'b0;
    apb_write(`APB4_GA2D__COMMAND, 32'h0000_0004, 1'b0);
    apb_read(`APB4_GA2D__GLOBAL_ALPHA, read_data);
    if (read_data != 32'h0000_00ff) begin
      $fatal(1, "GA2D post-quiesce soft reset did not clear configuration");
    end
    apb_read(`APB4_GA2D__IRQ_STATE, read_data);
    if (read_data != 32'd0 || irq_o) begin
      $fatal(1, "GA2D post-quiesce soft reset did not clear diagnostics");
    end

    apb_write(`APB4_GA2D__GLOBAL_ALPHA, 32'h0000_0055, 1'b0);
    apb_write(`APB4_GA2D__IRQ_ENABLE, 32'h0000_0001, 1'b0);
    apb_write(`APB4_GA2D__IRQ_TEST, 32'h0000_0001, 1'b0);
    apb_lifecycle_soft_reset(1'b1);
    apb_read(`APB4_GA2D__STATUS, read_data);
    if (read_data[`APB4_GA2D__STATUS_DATA_READY]) begin
      $fatal(1, "GA2D resource reset left data ready asserted");
    end
    apb_read(`APB4_GA2D__GLOBAL_ALPHA, read_data);
    if (read_data != 32'h0000_0055) begin
      $fatal(1, "GA2D resource reset allowed unsafe soft reset");
    end
    apb_read(`APB4_GA2D__IRQ_STATE, read_data);
    if (read_data != 32'h0000_0001 || !irq_o) begin
      $fatal(1, "GA2D resource reset cleared retained diagnostics");
    end
    resource_reset_i = 1'b0;
    apb_write(`APB4_GA2D__COMMAND, 32'h0000_0004, 1'b0);
    apb_read(`APB4_GA2D__GLOBAL_ALPHA, read_data);
    if (read_data != 32'h0000_00ff) begin
      $fatal(1, "GA2D post-reset soft reset did not clear configuration");
    end
    apb_read(`APB4_GA2D__IRQ_STATE, read_data);
    if (read_data != 32'd0 || irq_o) begin
      $fatal(1, "GA2D post-reset soft reset did not clear diagnostics");
    end

    apb_write(`APB4_GA2D__GLOBAL_ALPHA, 32'h0000_0055, 1'b0);
    apb_write(`APB4_GA2D__IRQ_ENABLE, 32'h0000_0001, 1'b0);
    apb_write(`APB4_GA2D__IRQ_TEST, 32'h0000_0001, 1'b0);
    resource_reset_i   = 1'b1;
    source_stop_i      = 1'b1;
    source_safe_idle_i = 1'b0;
    apb_read(`APB4_GA2D__STATUS, read_data);
    if (read_data[`APB4_GA2D__STATUS_QUIESCED]) begin
      $fatal(1, "GA2D resource reset quiesced before source drain");
    end
    if (!irq_o) $fatal(1, "GA2D resource reset cleared local IRQ state");

    source_safe_idle_i = 1'b1;
    apb_read(`APB4_GA2D__STATUS, read_data);
    if (read_data[`APB4_GA2D__STATUS_QUIESCED]) begin
      $fatal(1, "GA2D resource reset quiesced before HP block acknowledgement");
    end
    if (!idle_o) $fatal(1, "GA2D wrapper did not reassert idle after source drain");

    block_ack_i = 1'b1;
    apb_read(`APB4_GA2D__STATUS, read_data);
    if (!read_data[`APB4_GA2D__STATUS_QUIESCED]) begin
      $fatal(1, "GA2D resource reset did not report drain-and-hold quiesce");
    end
    apb_read(`APB4_GA2D__GLOBAL_ALPHA, read_data);
    if (read_data != 32'h0000_0055) begin
      $fatal(1, "GA2D resource reset cleared local configuration");
    end
    apb_read(`APB4_GA2D__IRQ_STATE, read_data);
    if (read_data != 32'h0000_0001 || !irq_o) begin
      $fatal(1, "GA2D resource reset cleared local diagnostic state");
    end

    bridge_clear_busy_i = 1'b1;
    apb_read(`APB4_GA2D__STATUS, read_data);
    if (!read_data[`APB4_GA2D__STATUS_RECOVERY_REQUIRED]) begin
      $fatal(1, "GA2D wrapper missed bridge clear-busy recovery state");
    end
    bridge_clear_busy_i = 1'b0;
    data_ready_i        = 1'b0;
    apb_read(`APB4_GA2D__STATUS, read_data);
    if (!read_data[`APB4_GA2D__STATUS_RECOVERY_REQUIRED] ||
        read_data[`APB4_GA2D__STATUS_DATA_READY]) begin
      $fatal(1, "GA2D wrapper missed data-ready recovery state");
    end
    data_ready_i   = 1'b1;
    bridge_epoch_i = 8'd1;
    #1;
    if (!u_dut.s_epoch_changed) begin
      $fatal(1, "GA2D wrapper missed bridge epoch change");
    end
    data_ready_i = 1'b0;
    apb_read(`APB4_GA2D__STATUS, read_data);
    if (!read_data[`APB4_GA2D__STATUS_RECOVERY_REQUIRED] ||
        read_data[`APB4_GA2D__STATUS_DATA_READY]) begin
      $fatal(1, "GA2D wrapper missed bridge epoch recovery state");
    end
    data_ready_i     = 1'b1;

    resource_reset_i = 1'b0;
    source_stop_i    = 1'b0;
    block_ack_i      = 1'b0;
    apb_write(`APB4_GA2D__COMMAND, 32'h0000_0004, 1'b0);
    apb_read(`APB4_GA2D__GLOBAL_ALPHA, read_data);
    if (read_data != 32'h0000_00ff) begin
      $fatal(1, "GA2D soft reset did not clear retained configuration");
    end
    apb_read(`APB4_GA2D__IRQ_STATE, read_data);
    if (read_data != 32'd0 || irq_o) begin
      $fatal(1, "GA2D soft reset did not clear retained diagnostic state");
    end

    apb_write(`APB4_GA2D__IRQ_ENABLE, 32'h0000_0002, 1'b0);
    apb_write(`APB4_GA2D__SIZE, 32'h0003_0000, 1'b0);
    apb_write(`APB4_GA2D__COMMAND, 32'h0000_0001, 1'b0);
    apb_read(`APB4_GA2D__STATUS, read_data);
    if (!read_data[`APB4_GA2D__STATUS_ERROR] || read_data[`APB4_GA2D__STATUS_DONE] ||
        read_data[`APB4_GA2D__STATUS_BUSY] || read_data[`APB4_GA2D__STATUS_DRAINING]) begin
      $fatal(1, "GA2D validation error did not report a terminal error state");
    end
    apb_read(`APB4_GA2D__IRQ_STATE, read_data);
    if (read_data != 32'h0000_0002 || !irq_o) begin
      $fatal(1, "GA2D validation error did not raise the enabled raw IRQ");
    end
    apb_read(`APB4_GA2D__ERROR_STATUS, read_data);
    if (read_data != 32'h0000_0103) begin
      $fatal(1, "GA2D validation error first-error record mismatch: %h", read_data);
    end
    apb_write(`APB4_GA2D__IRQ_ENABLE, 32'h0000_0000, 1'b0);
    if (irq_o) $fatal(1, "GA2D IRQ mask did not deassert the raw level");
    apb_read(`APB4_GA2D__IRQ_STATE, read_data);
    if (read_data != 32'h0000_0002) begin
      $fatal(1, "GA2D IRQ mask cleared retained state");
    end
    apb_write(`APB4_GA2D__IRQ_ENABLE, 32'h0000_0002, 1'b0);
    if (!irq_o) $fatal(1, "GA2D IRQ unmask did not reassert the raw level");
    apb_write(`APB4_GA2D__IRQ_STATE, 32'h0000_0002, 1'b0);
    if (irq_o) $fatal(1, "GA2D IRQ W1C did not clear the raw level");
    apb_read(`APB4_GA2D__ERROR_STATUS, read_data);
    if (read_data != 32'h0000_0103) begin
      $fatal(1, "GA2D first-error record changed before explicit clear");
    end
    apb_write(`APB4_GA2D__ERROR_STATUS, 32'h0000_0001, 1'b0);
    apb_read(`APB4_GA2D__ERROR_STATUS, read_data);
    if (read_data != 32'd0) begin
      $fatal(1, "GA2D first-error record did not clear on explicit W1C");
    end
    apb_write(`APB4_GA2D__COMMAND, 32'h0000_0004, 1'b0);
    apb_read(`APB4_GA2D__STATUS, read_data);
    if (read_data[`APB4_GA2D__STATUS_ERROR] || read_data[`APB4_GA2D__STATUS_DONE] || irq_o) begin
      $fatal(1, "GA2D soft reset did not clear the validation error state");
    end

    $display("GA2D P5 wrapper lifecycle test passed");
    $finish;
  end

  initial begin
    repeat (400) @(posedge clk_i);
    $fatal(1, "GA2D P5 wrapper lifecycle test timed out");
  end
endmodule
