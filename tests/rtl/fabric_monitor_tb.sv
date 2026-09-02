`timescale 1ns / 1ps

module fabric_monitor_tb;
  logic             clk_i = 1'b0;
  logic             rst_n_i = 1'b0;
  logic [ 7:0]      master_read_accept_i = '0;
  logic [ 7:0]      master_write_accept_i = '0;
  logic [ 7:0]      master_read_beat_i = '0;
  logic [ 7:0]      master_write_beat_i = '0;
  logic [ 7:0]      master_wait_i = '0;
  logic [ 7:0]      master_promotion_i = '0;
  logic [ 7:0][2:0] master_read_outstanding_i = '0;
  logic [ 7:0][2:0] master_write_outstanding_i = '0;
  logic [ 5:0]      target_read_accept_i = '0;
  logic [ 5:0]      target_write_accept_i = '0;
  logic [ 5:0]      target_read_beat_i = '0;
  logic [ 5:0]      target_write_beat_i = '0;
  logic [ 5:0]      target_wait_i = '0;
  logic [ 5:0]      target_timeout_i = '0;
  logic [ 5:0]      target_isolated_i = '0;
  logic [ 5:0][2:0] target_read_outstanding_i = '0;
  logic [ 5:0][2:0] target_write_outstanding_i = '0;
  logic             fault_valid_i = 1'b0;
  logic [31:0]      read_data;

  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

  fabric_monitor u_dut (
      .clk_i                     (clk_i),
      .rst_n_i                   (rst_n_i),
      .idle_i                    (1'b0),
      .recovery_i                (1'b1),
      .flush_busy_i              (1'b0),
      .flush_i                   (target_timeout_i[5]),
      .outstanding_read_i        (8'd2),
      .outstanding_write_i       (8'd1),
      .fault_valid_i             (fault_valid_i),
      .fault_master_i            (3'd5),
      .fault_target_i            (3'd2),
      .fault_addr_i              (32'h4000_0040),
      .fault_write_i             (1'b1),
      .fault_reason_i            (4'd5),
      .master_read_accept_i      (master_read_accept_i),
      .master_write_accept_i     (master_write_accept_i),
      .master_read_beat_i        (master_read_beat_i),
      .master_write_beat_i       (master_write_beat_i),
      .master_wait_i             (master_wait_i),
      .master_promotion_i        (master_promotion_i),
      .master_read_outstanding_i (master_read_outstanding_i),
      .master_write_outstanding_i(master_write_outstanding_i),
      .target_read_accept_i      (target_read_accept_i),
      .target_write_accept_i     (target_write_accept_i),
      .target_read_beat_i        (target_read_beat_i),
      .target_write_beat_i       (target_write_beat_i),
      .target_wait_i             (target_wait_i),
      .target_timeout_i          (target_timeout_i),
      .target_isolated_i         (target_isolated_i),
      .target_read_outstanding_i (target_read_outstanding_i),
      .target_write_outstanding_i(target_write_outstanding_i),
      .apb4                      (apb4)
  );

  task automatic apb_write(input logic [11:0] offset, input logic [31:0] data);
    begin
      @(negedge clk_i);
      apb4.paddr   = {20'd0, offset};
      apb4.pwrite  = 1'b1;
      apb4.pwdata  = data;
      apb4.pstrb   = 4'hF;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b1;
      do @(posedge clk_i); while (!apb4.pready);
      if (apb4.pslverr) $fatal(1, "fabric monitor write failed at %h", offset);
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
      if (apb4.pslverr) $fatal(1, "fabric monitor read failed at %h", offset);
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

    apb_write(12'h00C, 32'h0000_0001);
    @(negedge clk_i);
    master_read_accept_i[0]      = 1'b1;
    master_read_beat_i[0]        = 1'b1;
    master_promotion_i[0]        = 1'b1;
    master_read_outstanding_i[0] = 3'd3;
    target_read_accept_i[2]      = 1'b1;
    target_read_beat_i[2]        = 1'b1;
    target_read_outstanding_i[2] = 3'd2;
    @(negedge clk_i);
    master_read_accept_i = '0;
    master_read_beat_i   = '0;
    master_promotion_i   = '0;
    target_read_accept_i = '0;
    target_read_beat_i   = '0;
    repeat (3) begin
      master_wait_i[0] = 1'b1;
      target_wait_i[2] = 1'b1;
      @(negedge clk_i);
    end
    master_wait_i        = '0;
    target_wait_i        = '0;
    target_timeout_i[2]  = 1'b1;
    target_isolated_i[2] = 1'b1;
    fault_valid_i        = 1'b1;
    @(negedge clk_i);
    target_timeout_i[2] = 1'b0;
    fault_valid_i       = 1'b0;
    target_timeout_i[5] = 1'b1;
    @(negedge clk_i);
    target_timeout_i[5] = 1'b0;

    apb_write(12'h00C, 32'h0000_0009);
    apb_read(12'h100, read_data);
    if (read_data != 32'd1) $fatal(1, "master read request count mismatch");
    apb_read(12'h110, read_data);
    if (read_data != 32'd3) $fatal(1, "master wait count mismatch");
    apb_read(12'h114, read_data);
    if (read_data != 32'd3) $fatal(1, "master max wait mismatch");
    apb_read(12'h118, read_data);
    if (read_data != 32'd1) $fatal(1, "master promotion count mismatch");
    apb_read(12'h11C, read_data);
    if (read_data[2:0] != 3'd3) $fatal(1, "master high-water mismatch");
    apb_read(12'h340, read_data);
    if (read_data != 32'd1) $fatal(1, "target read request count mismatch");
    apb_read(12'h350, read_data);
    if (read_data != 32'd3) $fatal(1, "target wait count mismatch");
    apb_read(12'h354, read_data);
    if (read_data != 32'd1) $fatal(1, "target timeout count mismatch");
    apb_read(12'h358, read_data);
    if (read_data != 32'd1) $fatal(1, "target isolation mismatch");
    apb_read(12'h01C, read_data);
    if (read_data != 32'd1) $fatal(1, "flush count mismatch");
    apb_read(12'h018, read_data);
    if (read_data != 32'h4000_0040) $fatal(1, "fault address mismatch");
    apb_read(12'h014, read_data);
    if (read_data != 32'h0000_0557) $fatal(1, "sticky fault attribution mismatch");
    apb_read(12'h020, read_data);
    if (read_data != 32'd1) $fatal(1, "fault count mismatch");

    apb_write(12'h00C, 32'h0000_0005);
    apb_read(12'h100, read_data);
    if (read_data != 32'd0) $fatal(1, "snapshot did not clear");
    apb_read(12'h014, read_data);
    if (read_data != 32'd0) $fatal(1, "sticky fault did not clear");

    $display("Fabric Monitor counter, snapshot, and clear test passed");
    $finish;
  end

  initial begin
    repeat (400) @(posedge clk_i);
    $fatal(1, "Fabric Monitor test timed out");
  end
endmodule
