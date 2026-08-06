`timescale 1ns / 1ps

module sysctrl_fault_tb;
  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        fault_valid_i = 1'b0;
  logic [31:0] fault_addr_i = '0;
  logic [ 3:0] fault_wstrb_i = '0;
  logic        fault_reserved_i = 1'b0;
  ribp_if rib ();
  sysctrl_if sysctrl ();
  pll_ctrl_if pll_ctrl ();

  always #5 clk_i = ~clk_i;

  ribp_sysctrl u_sysctrl (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .fault_valid_i   (fault_valid_i),
      .fault_addr_i    (fault_addr_i),
      .fault_wstrb_i   (fault_wstrb_i),
      .fault_reserved_i(fault_reserved_i),
      .ribp            (rib),
      .sysctrl         (sysctrl),
      .pll_ctrl        (pll_ctrl)
  );

  task automatic read_register(input logic [31:0] address, output logic [31:0] data);
    begin
      @(negedge clk_i);
      rib.addr  = address;
      rib.wdata = '0;
      rib.wstrb = '0;
      rib.valid = 1'b1;
      while (!rib.ready) @(posedge clk_i);
      data = rib.rdata;
      @(negedge clk_i);
      rib.valid = 1'b0;
      while (rib.ready) @(posedge clk_i);
    end
  endtask

  task automatic write_register(input logic [31:0] address, input logic [31:0] data);
    begin
      @(negedge clk_i);
      rib.addr  = address;
      rib.wdata = data;
      rib.wstrb = 4'hF;
      rib.valid = 1'b1;
      while (!rib.ready) @(posedge clk_i);
      @(negedge clk_i);
      rib.valid = 1'b0;
      while (rib.ready) @(posedge clk_i);
    end
  endtask

  logic [31:0] read_data;
  initial begin
    rib.valid                   = 1'b0;
    rib.addr                    = '0;
    rib.wdata                   = '0;
    rib.wstrb                   = '0;
    sysctrl.user_bus_idle_i     = 1'b1;
    sysctrl.fault_access_i      = 1'b0;
    sysctrl.fault_master_i      = '0;
    sysctrl.fault_code_i        = `RIB_RESP_RESERVED;
    sysctrl.perf_mgmt_wait_i    = 64'd11;
    sysctrl.perf_user_wait_i    = 64'd12;
    sysctrl.perf_dma_wait_i     = 64'd13;
    sysctrl.perf_ribp_wait_i    = 64'd14;
    sysctrl.perf_apb_wait_i     = 64'd15;
    sysctrl.perf_sdram_wait_i   = 64'd16;
    sysctrl.perf_psram_wait_i   = 64'd17;
    sysctrl.perf_flash_wait_i   = 64'd18;
    pll_ctrl.req_ready_i        = 1'b1;
    pll_ctrl.rsp_active_sel_i   = '0;
    pll_ctrl.rsp_active_valid_i = 1'b0;
    pll_ctrl.rsp_safe_clk_i     = 1'b1;
    pll_ctrl.rsp_pll_lock_i     = 1'b0;
    pll_ctrl.rsp_error_i        = '0;
    pll_ctrl.rsp_valid_i        = 1'b0;
    pll_ctrl.capable_i          = 1'b0;
    repeat (2) @(posedge clk_i);
    rst_n_i = 1'b1;

    @(negedge clk_i);
    fault_valid_i    = 1'b1;
    fault_addr_i     = 32'h1000_F000;
    fault_wstrb_i    = 4'hF;
    fault_reserved_i = 1'b1;
    @(negedge clk_i);
    fault_valid_i = 1'b0;

    read_register(32'h1000_B010, read_data);
    if (read_data !== 32'h0000_000B) $fatal(1, "fault status was not recorded");
    read_register(32'h1000_B014, read_data);
    if (read_data !== 32'h1000_F000) $fatal(1, "fault address was not recorded");
    read_register(32'h1000_B018, read_data);
    if (read_data !== 32'h0000_0001) $fatal(1, "fault count was not incremented");
    read_register(32'h1000_B02C, read_data);
    if (read_data !== `RIB_RESP_RESERVED) $fatal(1, "fault detail was not recorded");

    @(negedge clk_i);
    sysctrl.fault_code_i = `RIB_RESP_DECERR;
    fault_valid_i        = 1'b1;
    fault_addr_i         = 32'hA000_0000;
    fault_wstrb_i        = 4'h0;
    fault_reserved_i     = 1'b0;
    @(negedge clk_i);
    fault_valid_i = 1'b0;
    read_register(32'h1000_B014, read_data);
    if (read_data !== 32'h1000_F000) $fatal(1, "later fault overwrote first fault address");
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

    read_register(32'h1000_B020, read_data);
    if (read_data !== 32'h0000_003F) $fatal(1, "user cores were not held in reset");
    write_register(32'h1000_B000, 32'h0000_0006);
    read_register(32'h1000_B024, read_data);
    if ((read_data & 32'h0000_083F) !== 32'h0000_0800) begin
      $fatal(1, "out-of-range user core selection was accepted");
    end
    write_register(32'h1000_B024, 32'h0000_0800);
    write_register(32'h1000_B000, 32'h0000_0001);
    write_register(32'h1000_B020, 32'h0000_003D);
    read_register(32'h1000_B024, read_data);
    if ((read_data & 32'h0000_0300) !== 32'h0000_0300 || (read_data & 32'h1F) != 1) begin
      $fatal(1, "user core start state was not recorded");
    end
    write_register(32'h1000_B020, 32'h0000_003F);
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

    $display("sysctrl fault and user core control test passed");
    $finish;
  end
endmodule
