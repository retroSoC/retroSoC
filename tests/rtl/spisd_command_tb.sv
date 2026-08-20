`timescale 1ns / 1ps

module spisd_command_tb;
  logic                               clk_i = 1'b0;
  logic                               rst_n_i = 1'b0;
  logic                               clock_enable_i = 1'b0;
  logic                        [15:0] half_period_i = 16'd1;
  logic                               rise_tick;
  logic                               fall_tick;
  logic                               sck;
  logic                               running;
  logic                               start_i = 1'b0;
  logic                               abort_i = 1'b0;
  logic                        [ 5:0] cmd_index_i = 6'd0;
  logic                        [31:0] cmd_arg_i = 32'd0;
  spisd_pkg::spisd_resp_type_e        resp_type_i = spisd_pkg::SpisdRespNone;
  logic                               stuff_byte_i = 1'b0;
  logic                        [31:0] timeout_cycles_i = 32'd1000;
  logic                        [31:0] busy_timeout_cycles_i = 32'd1000;
  logic                               miso_i = 1'b1;
  logic                               mosi_o;
  logic                               busy_o;
  logic                               done_o;
  logic                               error_o;
  logic                               timeout_o;
  logic                               busy_timeout_o;
  logic                        [ 7:0] error_code_o;
  logic                        [39:0] response_o;
  logic                        [ 5:0] last_cmd_index_o;
  logic                        [47:0] s_captured_cmd;
  logic                        [ 7:0] s_model_resp;
  integer                             s_captured_bits;
  integer                             s_resp_bit;
  logic                               s_capture_cmd;
  logic                               s_send_resp;

  always #1 clk_i = ~clk_i;

  spisd_clock u_spisd_clock (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .enable_i     (clock_enable_i),
      .pause_i      (1'b0),
      .half_period_i(half_period_i),
      .sck_o        (sck),
      .rise_tick_o  (rise_tick),
      .fall_tick_o  (fall_tick),
      .running_o    (running)
  );

  spisd_command u_spisd_command (
      .clk_i                (clk_i),
      .rst_n_i              (rst_n_i),
      .rise_tick_i          (rise_tick),
      .fall_tick_i          (fall_tick),
      .start_i              (start_i),
      .abort_i              (abort_i),
      .cmd_index_i          (cmd_index_i),
      .cmd_arg_i            (cmd_arg_i),
      .resp_type_i          (resp_type_i),
      .stuff_byte_i         (stuff_byte_i),
      .timeout_cycles_i     (timeout_cycles_i),
      .busy_timeout_cycles_i(busy_timeout_cycles_i),
      .miso_i               (miso_i),
      .mosi_o               (mosi_o),
      .busy_o               (busy_o),
      .done_o               (done_o),
      .error_o              (error_o),
      .timeout_o            (timeout_o),
      .busy_timeout_o       (busy_timeout_o),
      .error_code_o         (error_code_o),
      .response_o           (response_o),
      .last_cmd_index_o     (last_cmd_index_o)
  );

  always @(posedge sck) begin
    if (s_capture_cmd && (s_captured_bits < 48)) begin
      s_captured_cmd  = {s_captured_cmd[46:0], mosi_o};
      s_captured_bits = s_captured_bits + 1;
    end
  end

  always @(negedge sck) begin
    if (s_send_resp && (s_captured_bits == 48) && (s_resp_bit < 8)) begin
      miso_i <= s_model_resp[7-s_resp_bit];
      s_resp_bit = s_resp_bit + 1;
    end else begin
      miso_i <= 1'b1;
    end
  end

  task automatic start_command;
    begin
      @(negedge clk_i);
      start_i = 1'b1;
      @(negedge clk_i);
      start_i = 1'b0;
    end
  endtask

  task automatic wait_complete;
    begin
      wait (done_o);
      clock_enable_i = 1'b0;
      @(posedge clk_i);
      wait (!done_o);
      wait (!running);
    end
  endtask

  initial begin
    s_captured_cmd  = '0;
    s_captured_bits = 0;
    s_resp_bit      = 0;
    s_capture_cmd   = 1'b1;
    s_send_resp     = 1'b0;
    repeat (2) @(posedge clk_i);
    rst_n_i        = 1'b1;
    clock_enable_i = 1'b1;
    cmd_index_i    = 6'd0;
    cmd_arg_i      = 32'd0;
    resp_type_i    = spisd_pkg::SpisdRespNone;
    start_command();
    wait (done_o);
    if (error_o || (s_captured_bits != 48) ||
        (s_captured_cmd != {2'b01, 6'd0, 32'd0, 7'h4A, 1'b1}) ||
        (last_cmd_index_o != 6'd0)) begin
      $fatal(1, "command frame failed: frame=%h bits=%0d err=%b", s_captured_cmd, s_captured_bits,
             error_o);
    end
    wait_complete();

    s_captured_cmd  = '0;
    s_captured_bits = 0;
    s_resp_bit      = 0;
    s_model_resp    = 8'h01;
    s_send_resp     = 1'b1;
    cmd_index_i     = 6'd8;
    cmd_arg_i       = 32'h0000_01AA;
    resp_type_i     = spisd_pkg::SpisdRespR1;
    start_command();
    clock_enable_i = 1'b1;
    wait (done_o);
    if (error_o || (response_o[7:0] != 8'h01) ||
        (s_captured_cmd != {2'b01, 6'd8, 32'h0000_01AA, 7'h43, 1'b1})) begin
      $fatal(1, "R1 command/response failed: frame=%h response=%h", s_captured_cmd, response_o);
    end
    wait_complete();

    s_captured_bits  = 0;
    s_capture_cmd    = 1'b0;
    s_send_resp      = 1'b0;
    miso_i           = 1'b1;
    timeout_cycles_i = 32'd12;
    cmd_index_i      = 6'd13;
    cmd_arg_i        = 32'd0;
    resp_type_i      = spisd_pkg::SpisdRespR1;
    start_command();
    clock_enable_i = 1'b1;
    wait (done_o);
    if (!error_o || !timeout_o || busy_timeout_o ||
        (error_code_o != spisd_pkg::SpisdErrCmdTimeout)) begin
      $fatal(1, "response timeout classification failed");
    end
    $display("SPISD command frame, R1 response, and timeout test passed");
    $finish;
  end
endmodule
