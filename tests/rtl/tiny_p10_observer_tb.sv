module tiny_p10_observer_tb;
  logic clk = 0;
  always #5 clk = !clk;
  logic reset_n = 0, enable = 0;
  logic [2:0] ar = 0, r = 0, aw = 0, b = 0, errors = 0;
  logic [2:0][7:0] read_bytes = 0, write_bytes = 0;
  logic [2:0][4:0] stalled = 0;
  tiny_p10_observer u_observer (
      .clk_i             (clk),
      .rst_n_i           (reset_n),
      .enable_i          (enable),
      .read_accept_i     (ar),
      .read_done_i       (r),
      .write_accept_i    (aw),
      .write_done_i      (b),
      .error_i           (errors),
      .read_bytes_i      (read_bytes),
      .write_bytes_i     (write_bytes),
      .stalled_i         (stalled),
      .active_targets_i  (6'd3),
      .bank_issues_i     (4'b0101),
      .dma_beat_overlap_i(read_bytes[1] != 0 && write_bytes[1] != 0)
  );
  initial begin
    repeat (2) @(negedge clk);
    reset_n = 1;
    ar[0]   = 1;
    @(negedge clk);
    ar             = 0;
    enable         = 1;
    aw[1]          = 1;
    write_bytes[1] = 4;
    stalled[0][0]  = 1;
    @(negedge clk);
    aw            = 0;
    write_bytes   = 0;
    r[0]          = 1;
    read_bytes[0] = 4;
    @(negedge clk);
    r          = 0;
    read_bytes = 0;
    stalled    = 0;
    b[1]       = 1;
    @(negedge clk);
    b      = 0;
    enable = 0;
    @(negedge clk);
    if ($test$plusargs("orphan")) begin
      r[2] = 1;
      @(negedge clk);
    end
    enable = 1;
    ar[2]  = 1;
    @(negedge clk);
    ar     = 0;
    enable = 0;
    @(negedge clk);
    r[2] = 1;
    @(negedge clk);
    $display("SIM_TEST_PASS Tiny cycles=9");
    $finish;
  end
endmodule
