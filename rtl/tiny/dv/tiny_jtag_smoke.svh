// Pin-level JTAG/DTM/DMI acceptance, opt-in and independent of UART output.
logic s_jtag_checks_done = 1'b0;

task automatic jtag_tick(input bit tms, input bit tdi, output logic tdo);
  s_jtag_tms_driver = tms;
  s_jtag_tdi_driver = tdi;
  #50;
  tdo               = s_jtag_tdo;
  s_jtag_tck_driver = 1'b1;
  #50;
  s_jtag_tck_driver = 1'b0;
endtask

task automatic jtag_idle(input integer count);
  bit ignored;
  repeat (count) jtag_tick(0, 0, ignored);
endtask

task automatic jtag_ir(input logic [4:0] instruction);
  bit ignored;
  jtag_tick(1, 0, ignored);
  jtag_tick(1, 0, ignored);
  jtag_tick(0, 0, ignored);
  jtag_tick(0, 0, ignored);
  for (int i = 0; i < 5; i++) jtag_tick(i == 4, instruction[i], ignored);
  jtag_tick(1, 0, ignored);
  jtag_tick(0, 0, ignored);
endtask

task automatic jtag_dr(input integer width, input logic [40:0] data, output logic [40:0] result);
  logic sampled;
  result = '0;
  jtag_tick(1, 0, sampled);
  jtag_tick(0, 0, sampled);
  jtag_tick(0, 0, sampled);
  for (int i = 0; i < width; i++) begin
    jtag_tick(i == width - 1, data[i], sampled);
    if (sampled !== 1'b0 && sampled !== 1'b1) $fatal(1, "SIM_TEST_FAIL unknown shifted JTAG TDO");
    result[i] = sampled;
  end
  jtag_tick(1, 0, sampled);
  jtag_tick(0, 0, sampled);
endtask

task automatic jtag_dmi(input bit write_access, input logic [6:0] address, input logic [31:0] data,
                        output logic [31:0] result);
  logic [40:0] response;
  jtag_dr(41, {address, data, (write_access ? 2'd2 : 2'd1)}, response);
  jtag_idle(16);
  jtag_dr(41, 41'd0, response);
  if (response[1:0] != 0) $fatal(1, "SIM_TEST_FAIL DMI status %0d", response[1:0]);
  result = response[33:2];
endtask

initial begin : jtag_smoke
  bit            ignored;
  logic   [40:0] response;
  logic   [31:0] status;
  integer        attempts;
  if ($test$plusargs("tiny_jtag_smoke")) begin
    // Exercise reset with a live TCK before releasing the external reset.
    // Four-state models must observe an asserted reset, not X -> 1.
    repeat (6) jtag_tick(1, 0, ignored);
    wait (s_rst_n);
    // Five-edge JTAG reset release plus TAP reset; SYS remains independent.
    repeat (12) jtag_tick(1, 0, ignored);
    jtag_idle(1);
    jtag_ir(5'h01);
    jtag_dr(32, 41'd0, response);
    if (response[31:0] != 32'(`SOC_JTAG_IDCODE))
      $fatal(1, "SIM_TEST_FAIL JTAG IDCODE %h", response[31:0]);
    jtag_ir(5'h10);
    jtag_dr(32, 41'd0, response);
    if (response[3:0] != 1 || response[9:4] != 7)
      $fatal(1, "SIM_TEST_FAIL DTMCS %h", response[31:0]);
    jtag_ir(5'h11);
    jtag_dmi(1, 7'h10, 32'h00000001, status);
    jtag_dmi(1, 7'h10, 32'h80000001, status);
    attempts = 0;
    status   = 0;
    while (!status[9] && attempts < 256) begin
      jtag_dmi(0, 7'h11, 32'd0, status);
      attempts++;
    end
    if (!status[9]) $fatal(1, "SIM_TEST_FAIL JTAG halt timeout");
    jtag_dmi(1, 7'h10, 32'h40000001, status);
    attempts = 0;
    status   = 0;
    while (!status[11] && attempts < 256) begin
      jtag_dmi(0, 7'h11, 32'd0, status);
      attempts++;
    end
    if (!status[11]) $fatal(1, "SIM_TEST_FAIL JTAG resume timeout");
    jtag_dmi(1, 7'h10, 32'h00000001, status);
    $display("SIM_TEST_PASS Tiny JTAG transport halt/resume");
  end
  s_jtag_checks_done = 1'b1;
end
