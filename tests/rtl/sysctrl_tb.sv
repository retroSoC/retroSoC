`timescale 1ns / 1ps

module sysctrl_tb;
  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        fault_valid_i = 1'b0;
  logic [31:0] fault_addr_i = '0;
  logic [ 3:0] fault_wstrb_i = '0;
  logic        fault_reserved_i = 1'b0;
  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  sysctrl_if sysctrl ();
  pll_ctrl_if pll_ctrl ();

  always #5 clk_i = ~clk_i;

  apb4_sysctrl u_sysctrl (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .fault_valid_i   (fault_valid_i),
      .fault_addr_i    (fault_addr_i),
      .fault_wstrb_i   (fault_wstrb_i),
      .fault_reserved_i(fault_reserved_i),
      .apb4            (apb4),
      .sysctrl         (sysctrl),
      .pll_ctrl        (pll_ctrl)
  );

  task automatic read_register(input logic [31:0] address, output logic [31:0] data);
    begin
      @(negedge clk_i);
      apb4.paddr   = address;
      apb4.pwdata  = '0;
      apb4.pstrb   = '0;
      apb4.pwrite  = 1'b0;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      @(negedge clk_i);
      apb4.penable = 1'b1;
      while (!apb4.pready) @(negedge clk_i);
      if (apb4.pslverr !== 1'b0) begin
        $fatal(1, "read %h error=%b expected=%b", address, apb4.pslverr, 1'b0);
      end
      data         = apb4.prdata;
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
    end
  endtask

  task automatic write_register(input logic [31:0] address, input logic [31:0] data);
    begin
      @(negedge clk_i);
      apb4.paddr   = address;
      apb4.pwdata  = data;
      apb4.pstrb   = 4'hF;
      apb4.pwrite  = 1'b1;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      @(negedge clk_i);
      apb4.penable = 1'b1;
      while (!apb4.pready) @(negedge clk_i);
      if (apb4.pslverr !== 1'b0) begin
        $fatal(1, "write %h error=%b expected=%b", address, apb4.pslverr, 1'b0);
      end
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
      apb4.pwrite  = 1'b0;
      apb4.pstrb   = '0;
    end
  endtask

  logic [31:0] read_data;
  initial begin
    apb4.psel                       = 1'b0;
    apb4.paddr                      = '0;
    apb4.pwdata                     = '0;
    apb4.pstrb                      = '0;
    sysctrl.user_bus_idle_i         = 1'b1;
    sysctrl.fault_access_i          = 1'b0;
    sysctrl.fault_master_i          = '0;
    sysctrl.fault_code_i            = `RIB_RESP_RESERVED;
    sysctrl.perf_mgmt_wait_i        = 64'd11;
    sysctrl.perf_user_wait_i        = 64'd12;
    sysctrl.perf_dma_wait_i         = 64'd13;
    sysctrl.perf_sdio0_wait_i       = 64'd131;
    sysctrl.perf_sdio1_wait_i       = 64'd141;
    sysctrl.perf_usb2_wait_i        = 64'd151;
    sysctrl.perf_apb4_periph_wait_i = 64'd14;
    sysctrl.perf_apb4_system_wait_i = 64'd15;
    sysctrl.perf_sdram_wait_i       = 64'd16;
    sysctrl.perf_psram_wait_i       = 64'd17;
    sysctrl.perf_flash_wait_i       = 64'd18;
    sysctrl.rtc_wake_i              = 1'b0;
    pll_ctrl.req_ready_i            = 1'b1;
    pll_ctrl.rsp_active_sel_i       = '0;
    pll_ctrl.rsp_active_valid_i     = 1'b0;
    pll_ctrl.rsp_safe_clk_i         = 1'b1;
    pll_ctrl.rsp_pll_lock_i         = 1'b0;
    pll_ctrl.rsp_error_i            = '0;
    pll_ctrl.rsp_valid_i            = 1'b0;
    pll_ctrl.capable_i              = 1'b0;
    repeat (2) @(posedge clk_i);
    rst_n_i = 1'b1;

    @(negedge clk_i);
    sysctrl.fault_master_i = 3'd3;
    fault_valid_i          = 1'b1;
    fault_addr_i           = 32'h1001_2000;
    fault_wstrb_i          = 4'hF;
    fault_reserved_i       = 1'b1;
    @(negedge clk_i);
    fault_valid_i = 1'b0;

    read_register(32'h1000_B010, read_data);
    if (read_data !== 32'h0000_000B) $fatal(1, "fault status was not recorded");
    read_register(32'h1000_B014, read_data);
    if (read_data !== 32'h1001_2000) $fatal(1, "fault address was not recorded");
    read_register(32'h1000_B018, read_data);
    if (read_data !== 32'h0000_0001) $fatal(1, "fault count was not incremented");
    read_register(32'h1000_B028, read_data);
    if (read_data !== 32'h0000_0003) $fatal(1, "three-bit fault master was not recorded");
    read_register(32'h1000_B02C, read_data);
    if (read_data !== `RIB_RESP_RESERVED) $fatal(1, "fault detail was not recorded");

    @(negedge clk_i);
    sysctrl.fault_master_i = 3'd4;
    sysctrl.fault_code_i   = `RIB_RESP_DECERR;
    fault_valid_i          = 1'b1;
    fault_addr_i           = 32'hA000_0000;
    fault_wstrb_i          = 4'h0;
    fault_reserved_i       = 1'b0;
    @(negedge clk_i);
    fault_valid_i = 1'b0;
    read_register(32'h1000_B014, read_data);
    if (read_data !== 32'h1001_2000) $fatal(1, "later fault overwrote first fault address");
    read_register(32'h1000_B018, read_data);
    if (read_data !== 32'h0000_0002) $fatal(1, "later fault did not increment count");
    read_register(32'h1000_B02C, read_data);
    if (read_data !== `RIB_RESP_RESERVED) $fatal(1, "later fault overwrote first fault detail");

    write_register(32'h1000_B010, 32'h0000_0001);
    read_register(32'h1000_B010, read_data);
    if (read_data !== 32'h0000_000A) $fatal(1, "fault W1C did not clear pending");

    write_register(32'h1000_B040, 32'h0000_0005);
    read_register(32'h1000_B044, read_data);
    if (read_data !== 32'd11) $fatal(1, "performance snapshot was not recorded");
    read_register(32'h1000_B08C, read_data);
    if (read_data !== 32'd131) $fatal(1, "SDIO0 performance snapshot was not recorded");
    read_register(32'h1000_B094, read_data);
    if (read_data !== 32'd141) $fatal(1, "SDIO1 performance snapshot was not recorded");
    read_register(32'h1000_B09C, read_data);
    if (read_data !== 32'd151) $fatal(1, "USB2 performance snapshot was not recorded");

    read_register(32'h1000_B020, read_data);
    if (read_data !== 32'h0000_000F) $fatal(1, "user cores were not held in reset");
    write_register(32'h1000_B000, 32'h0000_0004);
    read_register(32'h1000_B024, read_data);
    if ((read_data & 32'h0000_083F) !== 32'h0000_0800) begin
      $fatal(1, "out-of-range user core selection was accepted");
    end
    write_register(32'h1000_B024, 32'h0000_0800);
    write_register(32'h1000_B000, 32'h0000_0001);
    write_register(32'h1000_B020, 32'h0000_000D);
    read_register(32'h1000_B024, read_data);
    if ((read_data & 32'h0000_0300) !== 32'h0000_0300 || (read_data & 32'h1F) != 1) begin
      $fatal(1, "user core start state was not recorded");
    end
    write_register(32'h1000_B020, 32'h0000_000F);
    read_register(32'h1000_B024, read_data);
    if ((read_data & 32'h0000_0300) !== 32'h0000_0200) begin
      $fatal(1, "user core stop state was not recorded");
    end

    read_register(32'h1000_B084, read_data);
    if (read_data !== 32'h0000_0000) begin
      $fatal(1, "test status did not reset");
    end
    write_register(32'h1000_B084, 32'h0000_5A01);
    read_register(32'h1000_B084, read_data);
    if (read_data !== 32'h0000_0000) begin
      $fatal(1, "invalid test status write was accepted");
    end
    write_register(32'h1000_B084, 32'h8000_5A01);
    read_register(32'h1000_B084, read_data);
    if (read_data !== 32'h8000_5A01) begin
      $fatal(1, "test pass status was not recorded");
    end
    write_register(32'h1000_B084, 32'h8000_0B00);
    read_register(32'h1000_B084, read_data);
    if (read_data !== 32'h8000_5A01) begin
      $fatal(1, "terminal test status was overwritten");
    end

    read_register(32'h1000_B088, read_data);
    if (read_data !== 32'h0000_0000) begin
      $fatal(1, "RTC wake status did not reset");
    end
    sysctrl.rtc_wake_i = 1'b1;
    repeat (4) @(posedge clk_i);
    read_register(32'h1000_B088, read_data);
    if (read_data !== 32'h0000_0003) begin
      $fatal(1, "RTC wake live and sticky status was not recorded");
    end
    sysctrl.rtc_wake_i = 1'b0;
    repeat (4) @(posedge clk_i);
    read_register(32'h1000_B088, read_data);
    if (read_data !== 32'h0000_0002) begin
      $fatal(1, "RTC wake sticky status was not retained");
    end
    write_register(32'h1000_B088, 32'h0000_0002);
    read_register(32'h1000_B088, read_data);
    if (read_data !== 32'h0000_0000) begin
      $fatal(1, "RTC wake sticky status W1C failed");
    end

    $display("SystemCtrl register, lifecycle, fault, performance, and RTC wake test passed");
    $finish;
  end
endmodule
