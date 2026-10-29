`timescale 1ns / 1ps
module piolite_exhaustive_tb;
  logic                              clk_i = 1'b0;
  logic                              rst_n_i = 1'b0;
  piolite_pkg::sm_config_t           cfg;
  logic                              start_i = 1'b0;
  logic                     [   5:0] event_clear_i = 6'd0;
  logic                              guard_fault_i = 1'b0;
  logic                     [   7:0] guard_fault_code_i = 8'd0;
  logic                              stream_fault_i = 1'b0;
  logic                     [  15:0] instruction_i = 16'd0;
  logic                              instruction_valid_i = 1'b1;
  logic                     [   4:0] instruction_addr_o;
  logic                     [  31:0] flags_i = 32'd1;
  logic                     [  31:0] pin_inputs_i = 32'd1;
  logic                     [   3:0] flag_set_o;
  logic                     [   3:0] flag_clear_o;
  logic                              tx_empty_i = 1'b0;
  logic                     [  31:0] tx_data_i = 32'hd31a5a69;
  logic                              tx_pop_o;
  logic                              rx_full_i = 1'b0;
  logic                              rx_push_o;
  logic                     [  31:0] rx_data_o;
  piolite_pkg::sm_runtime_t          runtime;
  logic                     [  31:0] vector_mem                 [0:1507327];
  logic                     [   3:0] observed_set;
  logic                     [   3:0] observed_clear;
  logic                              observed_tx_pop;
  logic                              observed_rx_push;
  logic                              counter_load = 1'b0;
  logic                     [  31:0] observed_rx_data;
  integer                            legal_count = 0;
  integer                            rejected_count = 0;
  reg                       [4095:0] vector_path;
  always #1 clk_i = ~clk_i;

  piolite_sm u_dut (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .cfg_i              (cfg),
      .start_i            (start_i),
      .pause_i            (1'b0),
      .resume_i           (1'b0),
      .disable_i          (1'b0),
      .abort_i            (1'b0),
      .sm_reset_i         (1'b0),
      .block_reset_i      (1'b0),
`ifdef PIOLITE_EXHAUSTIVE_DV
      .counter_load_i     (counter_load),
`endif
      .event_clear_i      (event_clear_i),
      .guard_fault_i      (guard_fault_i),
      .guard_fault_code_i (guard_fault_code_i),
      .stream_fault_i     (stream_fault_i),
      .instruction_i      (instruction_i),
      .instruction_valid_i(instruction_valid_i),
      .instruction_addr_o (instruction_addr_o),
      .flags_i            (flags_i),
      .pin_inputs_i       (pin_inputs_i),
      .flag_set_o         (flag_set_o),
      .flag_clear_o       (flag_clear_o),
      .tx_empty_i         (tx_empty_i),
      .tx_data_i          (tx_data_i),
      .tx_pop_o           (tx_pop_o),
      .rx_full_i          (rx_full_i),
      .rx_push_o          (rx_push_o),
      .rx_data_o          (rx_data_o),
      .runtime_o          (runtime)
  );

  always @(posedge clk_i) begin
    observed_set     = flag_set_o;
    observed_clear   = flag_clear_o;
    observed_tx_pop  = tx_pop_o;
    observed_rx_push = rx_push_o;
    observed_rx_data = rx_data_o;
  end

  task automatic check_field(input integer word, input integer field, input logic [31:0] actual,
                             input logic [31:0] expected);
    if (actual !== expected)
      $fatal(
          1,
          "PIOLITE exhaustive word=%h field=%0d got=%h expected=%h",
          word,
          field,
          actual,
          expected
      );
  endtask

  task automatic run_word(input integer word);
    integer base;
    base          = word * 23;
    instruction_i = vector_mem[base][15:0];
    rst_n_i       = 1'b0;
    start_i       = 1'b0;
    repeat (2) @(negedge clk_i);
    rst_n_i = 1'b1;
    @(negedge clk_i);
    start_i = 1'b1;
    @(negedge clk_i);
    start_i = 1'b0;
    @(negedge clk_i);
    check_field(word, 2, {23'd0, runtime.last_fifo_failed, 1'b0, runtime.stall, 1'b0, runtime.state
                }, vector_mem[base+2]);
    check_field(word, 3, {19'd0, runtime.fault_pc, runtime.fault_code}, vector_mem[base+3]);
    check_field(word, 4, {27'd0, runtime.pc}, vector_mem[base+4]);
    check_field(word, 5, runtime.isr, vector_mem[base+5]);
    check_field(word, 6, runtime.osr, vector_mem[base+6]);
    check_field(word, 7, {runtime.y, runtime.x}, vector_mem[base+7]);
    check_field(word, 8, {18'd0, runtime.osr_count, 2'd0, runtime.isr_count}, vector_mem[base+8]);
    check_field(word, 9, runtime.tick_count, vector_mem[base+9]);
    check_field(word, 10, runtime.tx_stall_count, vector_mem[base+10]);
    check_field(word, 11, runtime.rx_stall_count, vector_mem[base+11]);
    check_field(word, 12, runtime.retired_count, vector_mem[base+12]);
    check_field(word, 13, {12'd0, runtime.delay_remaining, runtime.divider_remaining},
                vector_mem[base+13]);
    check_field(word, 14, {26'd0, runtime.events}, vector_mem[base+14]);
    check_field(word, 15, runtime.output_value, vector_mem[base+15]);
    check_field(word, 16, runtime.output_oe, vector_mem[base+16]);
    check_field(word, 17, (flags_i & ~{28'd0, observed_clear}) | {28'd0, observed_set},
                vector_mem[base+17]);
    check_field(word, 18, {28'd0, observed_set}, vector_mem[base+18]);
    check_field(word, 19, {28'd0, observed_clear}, vector_mem[base+19]);
    check_field(word, 20, {31'd0, observed_tx_pop}, vector_mem[base+20]);
    check_field(word, 21, {31'd0, observed_rx_push}, vector_mem[base+21]);
    check_field(word, 22, observed_rx_data, vector_mem[base+22]);
    if (vector_mem[base+1] == 32'd1) legal_count++;
    else if (vector_mem[base+1] == 32'd0) rejected_count++;
    else $fatal(1, "PIOLITE exhaustive legality class is invalid");
    if ((word & 4095) == 4095) $display("PIOLITE_P2_EXHAUSTIVE_PROGRESS words=%0d", word + 1);
  endtask

  task automatic raw_start(input logic [15:0] word);
    instruction_i = word;
    rst_n_i       = 1'b0;
    start_i       = 1'b0;
    repeat (2) @(negedge clk_i);
    rst_n_i = 1'b1;
    @(negedge clk_i);
    start_i = 1'b1;
    @(negedge clk_i);
    start_i = 1'b0;
  endtask

  task automatic first_fault_priority;
    raw_start(16'hb000);
    guard_fault_i      = 1'b1;
    guard_fault_code_i = 8'd6;
    stream_fault_i     = 1'b1;
    @(negedge clk_i);
    if ((runtime.fault_code != 8'd6) || (runtime.state != piolite_pkg::Closing))
      $fatal(1, "PIOLITE guard/stream/execution first-fault priority");
    guard_fault_code_i = 8'd7;
    @(negedge clk_i);
    if ((runtime.fault_code != 8'd6) || (runtime.fault_pc != 5'd0))
      $fatal(1, "PIOLITE first fault was overwritten");
    guard_fault_i  = 1'b0;
    stream_fault_i = 1'b0;
    $display("PIOLITE_P2_COVER PL-V08 first-fault-priority-and-retention");
  endtask

  task automatic saturating_counters;
    raw_start(16'h0000);
    counter_load = 1'b1;
    @(negedge clk_i);
    counter_load = 1'b0;
    if ((runtime.tick_count != 32'hffff_ffff) ||
        (runtime.retired_count != 32'hffff_ffff) ||
        (runtime.tx_stall_count != 32'hffff_ffff) ||
        (runtime.rx_stall_count != 32'hffff_ffff))
      $fatal(1, "PIOLITE commit counters wrapped");
    instruction_i = 16'h7040;
    tx_empty_i    = 1'b1;
    @(negedge clk_i);
    if (runtime.tx_stall_count != 32'hffff_ffff) $fatal(1, "PIOLITE stall counter wrapped");
    tx_empty_i = 1'b0;
    $display("PIOLITE_P2_COVER PL-V08 saturating-tick-stall-retired-counters");
  endtask

  initial begin
    cfg                = '0;
    cfg.options        = 5'h1f;
    cfg.divider        = 16'd1;
    cfg.base           = 5'd0;
    cfg.length         = 6'd1;
    cfg.entry          = 5'd0;
    cfg.wrap_bottom    = 5'd0;
    cfg.wrap_top       = 5'd0;
    cfg.in_pins.base   = 5'd0;
    cfg.in_pins.width  = 6'd32;
    cfg.out_pins.base  = 5'd0;
    cfg.out_pins.width = 6'd32;
    cfg.set_pins.base  = 5'd0;
    cfg.set_pins.width = 6'd8;
    cfg.claim_mask     = 32'hffff_ffff;
    cfg.output_mask    = 32'hffff_ffff;
    cfg.initial_value  = 32'd0;
    cfg.initial_oe     = 32'd0;
    cfg.initial_x      = 16'd1;
    cfg.initial_y      = 16'd0;
    cfg.tx_bits        = 6'd32;
    cfg.rx_bits        = 6'd8;
    cfg.test_pin       = 5'd0;
    cfg.test_flag      = 2'd0;
    cfg.tx_low         = 4'd0;
    cfg.rx_high        = 4'd1;
    if (!$value$plusargs("PIOLITE_EXHAUSTIVE=%s", vector_path))
      $fatal(1, "PIOLITE exhaustive vector path is required");
    $readmemh(vector_path, vector_mem);
    for (integer word = 0; word < 65536; word++) run_word(word);
    if ((legal_count != 22257) || (rejected_count != 43279))
      $fatal(1, "PIOLITE exhaustive counts legal=%0d rejected=%0d", legal_count, rejected_count);
    $display("PIOLITE_P2_EXHAUSTIVE legal=%0d rejected=%0d total=65536", legal_count,
             rejected_count);
    first_fault_priority();
    saturating_counters();
    $display("PIOLITE_P2_COVER PL-V01 exhaustive-legal-and-reserved-semantics");
    $display("PIOLITE_P2_PASS piolite_exhaustive_tb");
    $finish;
  end

  initial begin
    #10000000;
    $fatal(1, "SIM_TEST_TIMEOUT PIOLITE exhaustive");
  end
endmodule
