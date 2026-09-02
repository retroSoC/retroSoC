`timescale 1ns / 1ps

module resource_controller_tb;
  logic             clk_i = 1'b0;
  logic             rst_n_i = 1'b0;
  logic [ 5:0]      idle_i = '0;
  logic [ 5:0]      block_ack_i = '0;
  logic [ 5:0]      irq_i = '0;
  logic             cache_request_i = 1'b0;
  logic             cache_clean_o;
  logic [ 5:0][1:0] owner_o;
  logic [ 5:0]      quiesce_o;
  logic [ 5:0]      reset_o;
  logic [ 5:0]      irq_lp_o;
  logic [ 5:0]      irq_hp_o;
  logic             fault_irq_o;
  logic [31:0]      read_data;

  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

  resource_controller u_dut (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .idle_i         (idle_i),
      .block_ack_i    (block_ack_i),
      .irq_i          (irq_i),
      .cache_request_i(cache_request_i),
      .cache_clean_o  (cache_clean_o),
      .owner_o        (owner_o),
      .quiesce_o      (quiesce_o),
      .reset_o        (reset_o),
      .irq_lp_o       (irq_lp_o),
      .irq_hp_o       (irq_hp_o),
      .fault_irq_o    (fault_irq_o),
      .apb4           (apb4)
  );

  task automatic apb_write(input logic [11:0] offset, input logic [31:0] data,
                           input logic expected_error);
    begin
      @(negedge clk_i);
      apb4.paddr   = {20'd0, offset};
      apb4.pwrite  = 1'b1;
      apb4.pwdata  = data;
      apb4.pstrb   = 4'hF;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b1;
      do @(posedge clk_i); while (!apb4.pready);
      if (apb4.pslverr != expected_error) begin
        $fatal(1, "resource controller write error mismatch at %h", offset);
      end
      @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
      apb4.pwrite  = 1'b0;
      apb4.pstrb   = '0;
    end
  endtask

  task automatic apb_read(input logic [11:0] offset, output logic [31:0] data);
    begin
      @(negedge clk_i);
      apb4.paddr   = {20'd0, offset};
      apb4.pwrite  = 1'b0;
      apb4.pstrb   = '0;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b1;
      do @(posedge clk_i); while (!apb4.pready);
      if (apb4.pslverr) $fatal(1, "resource controller read failed at %h", offset);
      data = apb4.prdata;
      @(negedge clk_i);
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
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
    idle_i  = 6'h3F;

    apb_read(12'h000, read_data);
    if (read_data != 32'h5253_4354) $fatal(1, "resource controller ID mismatch");

    irq_i[1] = 1'b1;
    #1;
    if (!irq_lp_o[1] || irq_hp_o[1]) $fatal(1, "default LP IRQ ownership mismatch");

    idle_i[0]      = 1'b0;
    block_ack_i[0] = 1'b1;
    apb_write(12'h104, 32'h0000_0001, 1'b0);
    apb_write(12'h100, 32'h0000_0001, 1'b1);
    if (!fault_irq_o || (owner_o[0] != 2'd0)) begin
      $fatal(1, "busy resource handoff did not fail closed");
    end
    apb_write(12'h10C, 32'h0000_0001, 1'b0);
    if (fault_irq_o) $fatal(1, "resource fault did not clear");

    idle_i[0] = 1'b1;
    irq_i[0]  = 1'b1;
    apb_write(12'h100, 32'h0000_0001, 1'b0);
    if ((owner_o[0] != 2'd1) || irq_lp_o[0] || !irq_hp_o[0]) begin
      $fatal(1, "HP resource ownership or IRQ routing mismatch");
    end
    apb_read(12'h110, read_data);
    if (read_data != 32'd1) $fatal(1, "resource handoff counter mismatch");

    apb_write(12'h100, 32'h0000_0101, 1'b0);
    apb_write(12'h100, 32'h0000_0000, 1'b1);
    if (owner_o[0] != 2'd1) $fatal(1, "locked resource owner changed");

    cache_request_i = 1'b1;
    apb_write(12'h010, 32'h0000_0001, 1'b0);
    if (!cache_clean_o) $fatal(1, "cache maintenance acknowledgement was not retained");
    cache_request_i = 1'b0;
    @(posedge clk_i);
    #1;
    if (cache_clean_o) $fatal(1, "cache acknowledgement did not clear with request");

    apb_write(12'h124, 32'h0000_0003, 1'b0);
    if (!quiesce_o[1] || !reset_o[1]) begin
      $fatal(1, "resource lifecycle controls did not update");
    end

    $display("Resource Controller ownership, IRQ, and cache handshake test passed");
    $finish;
  end

  initial begin
    repeat (300) @(posedge clk_i);
    $fatal(1, "Resource Controller test timed out");
  end
endmodule
