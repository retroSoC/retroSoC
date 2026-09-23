`timescale 1ns / 1ps

module sysctrl_tb;
  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        clk_hp_i = 1'b0;
  logic        rst_hp_n_i = 1'b0;
  logic        s_bus_fault_valid;
  logic [31:0] s_bus_fault_addr;
  logic [ 3:0] s_bus_fault_wstrb;
  logic        s_bus_fault_reserved;
  logic        s_bus_fault_access;
  logic [ 3:0] s_bus_fault_master;
  logic [ 2:0] s_bus_fault_code;
  logic        s_data_plane_fault_valid_hp;
  logic [ 3:0] s_data_plane_fault_master_hp;
  logic [ 2:0] s_data_plane_fault_target_hp;
  logic [31:0] s_data_plane_fault_addr_hp;
  logic        s_data_plane_fault_write_hp;
  logic [ 3:0] s_data_plane_fault_reason_hp;
  logic        s_data_plane_fault_ready_hp;
  logic        s_data_plane_fault_valid_pclk;
  logic [ 3:0] s_data_plane_fault_master_pclk;
  logic [ 2:0] s_data_plane_fault_target_pclk;
  logic [31:0] s_data_plane_fault_addr_pclk;
  logic        s_data_plane_fault_write_pclk;
  logic [ 3:0] s_data_plane_fault_reason_pclk;
  logic [ 3:0] s_data_plane_fault_delivery_count;
  logic [ 3:0] s_data_plane_fault_delivery_master[0:2];
  logic [ 2:0] s_data_plane_fault_delivery_target[0:2];
  logic [31:0] s_data_plane_fault_delivery_addr  [0:2];
  logic        s_data_plane_fault_delivery_write [0:2];
  logic [ 3:0] s_data_plane_fault_delivery_reason[0:2];
  logic        fault_valid_i;
  logic [31:0] fault_addr_i;
  logic [ 3:0] fault_wstrb_i;
  logic        fault_reserved_i;
  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  sysctrl_if sysctrl ();
  pll_ctrl_if pll_ctrl ();
  clock_ctrl_if clock_ctrl ();

  always #17 clk_i = ~clk_i;
  always #3 clk_hp_i = ~clk_hp_i;
  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_data_plane_fault_delivery_count <= '0;
    end else if (s_data_plane_fault_valid_pclk) begin
      if (s_data_plane_fault_delivery_count < 4'd3) begin
        s_data_plane_fault_delivery_master[s_data_plane_fault_delivery_count] <=
            s_data_plane_fault_master_pclk;
        s_data_plane_fault_delivery_target[s_data_plane_fault_delivery_count] <=
            s_data_plane_fault_target_pclk;
        s_data_plane_fault_delivery_addr[s_data_plane_fault_delivery_count] <=
            s_data_plane_fault_addr_pclk;
        s_data_plane_fault_delivery_write[s_data_plane_fault_delivery_count] <=
            s_data_plane_fault_write_pclk;
        s_data_plane_fault_delivery_reason[s_data_plane_fault_delivery_count] <=
            s_data_plane_fault_reason_pclk;
      end
      s_data_plane_fault_delivery_count <= s_data_plane_fault_delivery_count + 1'b1;
    end
  end

  data_plane_fault_cdc u_data_plane_fault_cdc (
      .clk_hp_i      (clk_hp_i),
      .rst_hp_n_i    (rst_hp_n_i),
      .fault_valid_i (s_data_plane_fault_valid_hp),
      .fault_master_i(s_data_plane_fault_master_hp),
      .fault_target_i(s_data_plane_fault_target_hp),
      .fault_addr_i  (s_data_plane_fault_addr_hp),
      .fault_write_i (s_data_plane_fault_write_hp),
      .fault_reason_i(s_data_plane_fault_reason_hp),
      .fault_ready_o (s_data_plane_fault_ready_hp),
      .clk_pclk_i    (clk_i),
      .rst_pclk_n_i  (rst_n_i),
      .fault_valid_o (s_data_plane_fault_valid_pclk),
      .fault_master_o(s_data_plane_fault_master_pclk),
      .fault_target_o(s_data_plane_fault_target_pclk),
      .fault_addr_o  (s_data_plane_fault_addr_pclk),
      .fault_write_o (s_data_plane_fault_write_pclk),
      .fault_reason_o(s_data_plane_fault_reason_pclk)
  );

  assign fault_valid_i = s_data_plane_fault_valid_pclk || s_bus_fault_valid;
  assign sysctrl.fault_access_i = s_data_plane_fault_valid_pclk ?
      s_data_plane_fault_write_pclk : s_bus_fault_access;
  assign sysctrl.fault_master_i = s_data_plane_fault_valid_pclk ?
      s_data_plane_fault_master_pclk : s_bus_fault_master;
  assign sysctrl.fault_code_i = s_data_plane_fault_valid_pclk ?
      s_data_plane_fault_reason_pclk[2:0] : s_bus_fault_code;
  assign fault_addr_i = s_data_plane_fault_valid_pclk ?
      s_data_plane_fault_addr_pclk : s_bus_fault_addr;
  assign fault_wstrb_i = s_data_plane_fault_valid_pclk && s_data_plane_fault_write_pclk ?
      4'hF : s_bus_fault_wstrb;
  assign fault_reserved_i = s_data_plane_fault_valid_pclk ? 1'b0 : s_bus_fault_reserved;

  apb4_sysctrl u_sysctrl (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .fault_valid_i   (fault_valid_i),
      .fault_addr_i    (fault_addr_i),
      .fault_wstrb_i   (fault_wstrb_i),
      .fault_reserved_i(fault_reserved_i),
      .apb4            (apb4),
      .sysctrl         (sysctrl),
      .pll_ctrl        (pll_ctrl),
      .clock_ctrl      (clock_ctrl)
  );

  task automatic send_data_plane_fault(input logic [3:0] master, input logic [2:0] target,
                                       input logic [31:0] address, input logic write_access,
                                       input logic [3:0] reason, input logic require_backpressure);
    logic saw_backpressure;
    begin
      saw_backpressure = 1'b0;
      @(negedge clk_hp_i);
      s_data_plane_fault_master_hp = master;
      s_data_plane_fault_target_hp = target;
      s_data_plane_fault_addr_hp   = address;
      s_data_plane_fault_write_hp  = write_access;
      s_data_plane_fault_reason_hp = reason;
      s_data_plane_fault_valid_hp  = 1'b1;
      do begin
        @(posedge clk_hp_i);
        if (!s_data_plane_fault_ready_hp) saw_backpressure = 1'b1;
      end while (!s_data_plane_fault_ready_hp);
      if (require_backpressure && !saw_backpressure) begin
        $fatal(1, "slow PCLK did not backpressure the successive HP fault");
      end
      @(negedge clk_hp_i);
      s_data_plane_fault_valid_hp = 1'b0;
    end
  endtask

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

  task automatic write_register_error(input logic [31:0] address, input logic [31:0] data);
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
      if (apb4.pslverr !== 1'b1) begin
        $fatal(1, "write %h error=%b expected=%b", address, apb4.pslverr, 1'b1);
      end
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
      apb4.pwrite  = 1'b0;
      apb4.pstrb   = '0;
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
    s_bus_fault_valid               = 1'b0;
    s_bus_fault_addr                = '0;
    s_bus_fault_wstrb               = '0;
    s_bus_fault_reserved            = 1'b0;
    s_bus_fault_access              = 1'b0;
    s_bus_fault_master              = '0;
    s_bus_fault_code                = `RIB_RESP_RESERVED;
    s_data_plane_fault_valid_hp     = 1'b0;
    s_data_plane_fault_master_hp    = '0;
    s_data_plane_fault_target_hp    = '0;
    s_data_plane_fault_addr_hp      = '0;
    s_data_plane_fault_write_hp     = 1'b0;
    s_data_plane_fault_reason_hp    = '0;
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
    sysctrl.hp_present_i            = 1'b0;
    sysctrl.hp_actual_released_i    = 1'b0;
    sysctrl.hp_draining_i           = 1'b0;
    sysctrl.hp_forced_fault_i       = 1'b0;
    pll_ctrl.req_ready_i            = 1'b1;
    pll_ctrl.rsp_active_sel_i       = '0;
    pll_ctrl.rsp_active_valid_i     = 1'b0;
    pll_ctrl.rsp_safe_clk_i         = 1'b1;
    pll_ctrl.rsp_pll_lock_i         = 1'b0;
    pll_ctrl.rsp_error_i            = '0;
    pll_ctrl.rsp_valid_i            = 1'b0;
    pll_ctrl.capable_i              = 1'b0;
    clock_ctrl.req_ready_i          = 1'b1;
    clock_ctrl.rsp_data_i           = '0;
    clock_ctrl.rsp_valid_i          = 1'b0;
    clock_ctrl.current_i            = '0;
    clock_ctrl.fault_i              = '0;
    clock_ctrl.memory_i             = 32'h0000_0005;
    repeat (2) @(posedge clk_i);
    rst_n_i    = 1'b1;
    rst_hp_n_i = 1'b1;
    repeat (3) @(posedge clk_hp_i);

    send_data_plane_fault(4'd8, 3'd5, 32'h1001_2000, 1'b1, {1'b0, `RIB_RESP_RESERVED}, 1'b0);
    send_data_plane_fault(4'd4, 3'd2, 32'h1001_2800, 1'b0, {1'b0, `RIB_RESP_DECERR}, 1'b1);
    send_data_plane_fault(4'd1, 3'd4, 32'h1001_2C00, 1'b1, {1'b0, `RIB_RESP_SLVERR}, 1'b1);
    wait (s_data_plane_fault_delivery_count == 4'd3);
    @(posedge clk_i);
    #1;
    if ((s_data_plane_fault_delivery_master[0] != 4'd8) ||
        (s_data_plane_fault_delivery_target[0] != 3'd5) ||
        (s_data_plane_fault_delivery_addr[0] != 32'h1001_2000) ||
        !s_data_plane_fault_delivery_write[0] ||
        (s_data_plane_fault_delivery_reason[0] != {1'b0, `RIB_RESP_RESERVED}) ||
        (s_data_plane_fault_delivery_master[1] != 4'd4) ||
        (s_data_plane_fault_delivery_target[1] != 3'd2) ||
        (s_data_plane_fault_delivery_addr[1] != 32'h1001_2800) ||
        s_data_plane_fault_delivery_write[1] ||
        (s_data_plane_fault_delivery_reason[1] != {1'b0, `RIB_RESP_DECERR}) ||
        (s_data_plane_fault_delivery_master[2] != 4'd1) ||
        (s_data_plane_fault_delivery_target[2] != 3'd4) ||
        (s_data_plane_fault_delivery_addr[2] != 32'h1001_2C00) ||
        !s_data_plane_fault_delivery_write[2] ||
        (s_data_plane_fault_delivery_reason[2] != {1'b0, `RIB_RESP_SLVERR})) begin
      $fatal(1, "successive HP faults were not delivered exactly once and coherently");
    end

    read_register(32'h1000_B010, read_data);
    if (read_data !== 32'h0000_000B) $fatal(1, "fault status was not recorded");
    read_register(32'h1000_B014, read_data);
    if (read_data !== 32'h1001_2000) $fatal(1, "fault address was not recorded");
    read_register(32'h1000_B018, read_data);
    if (read_data !== 32'h0000_0003) $fatal(1, "consecutive data-plane faults were lost");
    read_register(32'h1000_B028, read_data);
    if (read_data !== 32'h0000_0008) $fatal(1, "four-bit fault master was not recorded");
    read_register(32'h1000_B02C, read_data);
    if (read_data !== `RIB_RESP_RESERVED) $fatal(1, "fault detail was not recorded");

    @(negedge clk_i);
    s_bus_fault_master   = 4'd4;
    s_bus_fault_code     = `RIB_RESP_DECERR;
    s_bus_fault_valid    = 1'b1;
    s_bus_fault_addr     = 32'hA000_0000;
    s_bus_fault_wstrb    = 4'h0;
    s_bus_fault_reserved = 1'b0;
    @(negedge clk_i);
    s_bus_fault_valid = 1'b0;
    read_register(32'h1000_B014, read_data);
    if (read_data !== 32'h1001_2000) $fatal(1, "later fault overwrote first fault address");
    read_register(32'h1000_B018, read_data);
    if (read_data !== 32'h0000_0004) $fatal(1, "later fault did not increment count");
    read_register(32'h1000_B02C, read_data);
    if (read_data !== `RIB_RESP_RESERVED) $fatal(1, "later fault overwrote first fault detail");

    write_register(32'h1000_B010, 32'h0000_0001);
    read_register(32'h1000_B010, read_data);
    if (read_data !== 32'h0000_000A) $fatal(1, "fault W1C did not clear pending");

    send_data_plane_fault(4'd8, 3'd2, 32'h1001_3000, 1'b0, {1'b0, `RIB_RESP_RESERVED}, 1'b0);
    wait (s_data_plane_fault_valid_pclk);
    @(negedge clk_i);
    s_bus_fault_master   = 4'd4;
    s_bus_fault_code     = `RIB_RESP_DECERR;
    s_bus_fault_valid    = 1'b1;
    s_bus_fault_addr     = 32'hA000_1000;
    s_bus_fault_wstrb    = 4'h0;
    s_bus_fault_reserved = 1'b0;
    @(negedge clk_i);
    s_bus_fault_valid = 1'b0;
    read_register(32'h1000_B014, read_data);
    if (read_data !== 32'h1001_3000) begin
      $fatal(1, "simultaneous local fault overrode the PCLK-visible data-plane fault");
    end
    read_register(32'h1000_B028, read_data);
    if (read_data !== 32'h0000_0008) begin
      $fatal(1, "fault arbitration lost the data-plane master high bit");
    end
    wait (s_data_plane_fault_delivery_count == 4'd4);
    read_register(32'h1000_B018, read_data);
    if (read_data !== 32'h0000_0005) begin
      $fatal(1, "simultaneous local fault was not deterministically suppressed");
    end

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
    if (read_data !== 32'hFFFF_FFFF) $fatal(1, "retired user cores were not held in reset");
    read_register(32'h1000_B024, read_data);
    if (read_data !== 32'h0000_0200) $fatal(1, "retired user-core status was not idle");
    write_register_error(32'h1000_B000, 32'h0000_0001);
    write_register_error(32'h1000_B004, 32'h0000_0001);
    write_register_error(32'h1000_B020, 32'hFFFF_FFFE);
    write_register_error(32'h1000_B024, 32'h0000_0800);
    read_register(32'h1000_B024, read_data);
    if (read_data !== 32'h0000_0A00) $fatal(1, "retired user-core write fault was not sticky");

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

    read_register(32'h1000_B0A8, read_data);
    if (read_data !== 32'h0000_0000) $fatal(1, "absent HP status was not zero");
    write_register(32'h1000_B0A4, 32'h0000_0001);
    write_register(32'h1000_B0AC, 32'h0000_0001);
    if (sysctrl.hp_release_o || sysctrl.debug_hp_select_o) begin
      $fatal(1, "absent HP accepted lifecycle control");
    end

    sysctrl.hp_present_i = 1'b1;
    read_register(32'h1000_B0A8, read_data);
    if (read_data !== 32'h0000_0005) $fatal(1, "present HP reset status mismatch");
    write_register(32'h1000_B0AC, 32'h0000_0001);
    if (!sysctrl.debug_hp_select_o) $fatal(1, "HP debug selection was not accepted in reset");
    write_register(32'h1000_B0A4, 32'h0000_0001);
    read_register(32'h1000_B0A8, read_data);
    if ((read_data !== 32'h0000_0003) || !sysctrl.hp_release_o) begin
      $fatal(1, "HP release status mismatch");
    end
    write_register(32'h1000_B0AC, 32'h0000_0000);
    if (!sysctrl.debug_hp_select_o) $fatal(1, "running HP allowed JTAG selection change");
    write_register(32'h1000_B0A4, 32'h0000_0000);
    write_register(32'h1000_B0AC, 32'h0000_0000);
    if (sysctrl.hp_release_o || sysctrl.debug_hp_select_o) begin
      $fatal(1, "HP reset/debug return did not complete");
    end

    $display("SystemCtrl register, lifecycle, fault, performance, RTC wake, and HP test passed");
    $finish;
  end
endmodule
