`timescale 1ns / 1ps

module hp_lifecycle_controller_tb;
  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  logic release_req_i = 1'b0;
  logic hp_idle_i = 1'b0;
  logic flush_busy_i = 1'b0;
  logic cache_clean_i = 1'b0;
  logic hp_release_o;
  logic block_new_o;
  logic flush_o;
  logic cache_request_o;
  logic draining_o;
  logic forced_fault_o;

  always #5 clk_i = ~clk_i;

  hp_lifecycle_controller u_dut (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .release_req_i  (release_req_i),
      .hp_idle_i      (hp_idle_i),
      .flush_busy_i   (flush_busy_i),
      .cache_clean_i  (cache_clean_i),
      .timeout_i      (16'd4),
      .hp_release_o   (hp_release_o),
      .block_new_o    (block_new_o),
      .flush_o        (flush_o),
      .cache_request_o(cache_request_o),
      .draining_o     (draining_o),
      .forced_fault_o (forced_fault_o)
  );

  task automatic complete_flush;
    begin
      wait (flush_o);
      @(negedge clk_i);
      flush_busy_i = 1'b1;
      wait (!flush_o);
      repeat (2) @(negedge clk_i);
      flush_busy_i = 1'b0;
      wait (!hp_release_o);
    end
  endtask

  initial begin
    repeat (2) @(posedge clk_i);
    rst_n_i = 1'b1;
    @(negedge clk_i);
    release_req_i = 1'b1;
    wait (hp_release_o);
    if (block_new_o || draining_o) $fatal(1, "released HP was unexpectedly blocked");

    @(negedge clk_i);
    release_req_i = 1'b0;
    wait (cache_request_o);
    if (block_new_o || !hp_release_o) begin
      $fatal(1, "cache-maintenance phase blocked HP before acknowledgement");
    end
    cache_clean_i = 1'b1;
    @(posedge clk_i);
    @(negedge clk_i);
    cache_clean_i = 1'b0;
    repeat (2) @(negedge clk_i);
    if (!block_new_o || !draining_o || !hp_release_o) begin
      $fatal(1, "normal shutdown did not enter drain while HP remained released");
    end
    hp_idle_i = 1'b1;
    complete_flush();
    if (forced_fault_o || block_new_o) $fatal(1, "normal shutdown reported a forced fault");

    @(negedge clk_i);
    hp_idle_i     = 1'b0;
    release_req_i = 1'b1;
    wait (hp_release_o);
    @(negedge clk_i);
    release_req_i = 1'b0;
    wait (flush_o);
    if (!forced_fault_o) $fatal(1, "quiesce timeout did not record a forced fault");
    complete_flush();

    $display("HP lifecycle drain, flush, and forced reset test passed");
    $finish;
  end
endmodule
