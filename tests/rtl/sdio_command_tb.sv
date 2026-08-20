`timescale 1ns / 1ps

module sdio_command_tb;
  logic                              clk_i = 1'b0;
  logic                              rst_n_i = 1'b0;
  logic                              clock_enable_i = 1'b0;
  logic                      [ 15:0] half_period_i = 16'd1;
  logic                              launch_tick;
  logic                              sample_tick;
  logic                              sck;
  logic                              running;
  logic                              start_i = 1'b0;
  logic                      [  5:0] cmd_index_i = 6'd0;
  logic                      [ 31:0] cmd_arg_i = '0;
  sdio_pkg::sdio_resp_type_e         resp_type_i = sdio_pkg::SdioRespNone;
  logic                              crc_check_i = 1'b0;
  logic                              index_check_i = 1'b0;
  logic                      [ 31:0] timeout_cycles_i = 32'd1000;
  logic                              cmd_di_i = 1'b1;
  logic                              dat0_i = 1'b1;
  logic                              cmd_oe_o;
  logic                              cmd_do_o;
  logic                              busy_o;
  logic                              done_o;
  logic                              error_o;
  logic                              timeout_o;
  logic                              crc_error_o;
  logic                              index_error_o;
  logic                              busy_timeout_o;
  logic                      [135:0] response_o;
  logic                      [  5:0] last_cmd_index_o;
  integer                            launch_count;
  integer                            captured_bits;
  logic                      [ 47:0] captured_command;

  always #1 clk_i = ~clk_i;

  sdio_clock u_sdio_clock (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .enable_i     (clock_enable_i),
      .half_period_i(half_period_i),
      .sck_o        (sck),
      .launch_tick_o(launch_tick),
      .sample_tick_o(sample_tick),
      .running_o    (running)
  );
  sdio_command u_sdio_command (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .launch_tick_i   (launch_tick),
      .sample_tick_i   (sample_tick),
      .start_i         (start_i),
      .cmd_index_i     (cmd_index_i),
      .cmd_arg_i       (cmd_arg_i),
      .resp_type_i     (resp_type_i),
      .crc_check_i     (crc_check_i),
      .index_check_i   (index_check_i),
      .timeout_cycles_i(timeout_cycles_i),
      .cmd_di_i        (cmd_di_i),
      .dat0_i          (dat0_i),
      .cmd_oe_o        (cmd_oe_o),
      .cmd_do_o        (cmd_do_o),
      .busy_o          (busy_o),
      .done_o          (done_o),
      .error_o         (error_o),
      .timeout_o       (timeout_o),
      .crc_error_o     (crc_error_o),
      .index_error_o   (index_error_o),
      .busy_timeout_o  (busy_timeout_o),
      .response_o      (response_o),
      .last_cmd_index_o(last_cmd_index_o)
  );

  always @(posedge clk_i) begin
    if (launch_tick) launch_count = launch_count + 1;
  end

  always @(posedge sck) begin
    if (cmd_oe_o) begin
      captured_command = {captured_command[46:0], cmd_do_o};
      captured_bits    = captured_bits + 1;
    end
  end

  initial begin
    launch_count     = 0;
    captured_bits    = 0;
    captured_command = '0;
    repeat (2) @(posedge clk_i);
    rst_n_i = 1'b1;
    @(negedge clk_i);
    start_i = 1'b1;
    @(negedge clk_i);
    start_i        = 1'b0;
    clock_enable_i = 1'b1;
    wait (done_o);
    if (error_o || (launch_count != 48) || (captured_bits != 48) ||
        (captured_command[47:46] != 2'b01) || (captured_command[0] != 1'b1) ||
        (captured_command[7:1] != sdio_pkg::sdio_crc7_calc(
            captured_command[47:8]
        )) || (last_cmd_index_o != 6'd0) || cmd_oe_o) begin
      $fatal(1, "no-response command frame failed: err=%b launches=%0d captured=%0d frame=%h oe=%b",
             error_o, launch_count, captured_bits, captured_command, cmd_oe_o);
    end

    @(posedge clk_i);
    resp_type_i      = sdio_pkg::SdioRespR1;
    timeout_cycles_i = 32'd4;
    @(negedge clk_i);
    start_i = 1'b1;
    @(negedge clk_i);
    start_i = 1'b0;
    wait (done_o);
    if (!error_o || !timeout_o) begin
      $fatal(1, "response timeout was not reported");
    end
    $display("SDIO command engine test passed");
    $finish;
  end
endmodule
