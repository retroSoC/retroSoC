`timescale 1ns / 1ps

module pll_ctrl_tb;
  logic        ext_clk_i = 1'b0;
  logic        ref24_clk_i = 1'b0;
  logic        aud_clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        wdg_reset_req_i = 1'b0;
  logic        fault_valid_i = 1'b0;
  logic [31:0] fault_addr_i = '0;
  logic [ 3:0] fault_wstrb_i = '0;
  logic        fault_reserved_i = 1'b0;
  logic        sys_clk_o;
  logic        sys_rst_n_o;
  logic        aon_clk_o;
  logic        aon_rst_n_o;
  logic        hp_clk_o;
  logic        hp_rst_n_o;
  logic        pclk_o;
  logic        pclk_rst_n_o;
  logic        mem_clk_o;
  logic        mem_rst_n_o;
  logic        aud_clk_o;
  logic        aud_rst_n_o;
  logic        sys_clkdiv4_o;
  apb4_if apb4 (
      .pclk   (pclk_o),
      .presetn(pclk_rst_n_o)
  );
  sysctrl_if sysctrl ();
  pll_ctrl_if pll_ctrl ();
  clock_ctrl_if clock_ctrl ();
  logic [31:0] read_data;
  time         edge_start;
  time         edge_end;

  always #7 ext_clk_i = ~ext_clk_i;
  always #21 ref24_clk_i = ~ref24_clk_i;
  always #27 aud_clk_i = ~aud_clk_i;

  rcu u_rcu (
      .ext_clk_i      (ext_clk_i),
      .ref24_clk_i    (ref24_clk_i),
      .aud_clk_i      (aud_clk_i),
      .ext_rst_n_i    (rst_n_i),
      .wdg_reset_req_i(wdg_reset_req_i),
      .hp_idle_i      (1'b1),
      .pclk_idle_i    (1'b1),
      .pll_ctrl       (pll_ctrl),
      .clock_ctrl     (clock_ctrl),
      .aon_clk_o      (aon_clk_o),
      .aon_rst_n_o    (aon_rst_n_o),
      .sys_clk_o      (sys_clk_o),
      .sys_rst_n_o    (sys_rst_n_o),
      .hp_clk_o       (hp_clk_o),
      .hp_rst_n_o     (hp_rst_n_o),
      .pclk_o         (pclk_o),
      .pclk_rst_n_o   (pclk_rst_n_o),
      .mem_clk_o      (mem_clk_o),
      .mem_rst_n_o    (mem_rst_n_o),
      .aud_clk_o      (aud_clk_o),
      .aud_rst_n_o    (aud_rst_n_o),
      .sys_clkdiv4_o  (sys_clkdiv4_o),
      .timebase_tick_o(),
      .hp_block_o     (),
      .pll_fault_o    (),
      .mem_pad_mode_o (),
      .mem_pad_lock_o ()
  );

  apb4_sysctrl u_sysctrl (
      .clk_i           (pclk_o),
      .rst_n_i         (pclk_rst_n_o),
      .fault_valid_i   (fault_valid_i),
      .fault_addr_i    (fault_addr_i),
      .fault_wstrb_i   (fault_wstrb_i),
      .fault_reserved_i(fault_reserved_i),
      .apb4            (apb4),
      .sysctrl         (sysctrl),
      .pll_ctrl        (pll_ctrl),
      .clock_ctrl      (clock_ctrl)
  );

  task automatic read_register(input logic [31:0] address, output logic [31:0] data);
    begin
      @(negedge pclk_o);
      apb4.paddr   = address;
      apb4.pwdata  = '0;
      apb4.pstrb   = '0;
      apb4.pwrite  = 1'b0;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      @(negedge pclk_o);
      apb4.penable = 1'b1;
      while (!apb4.pready) @(negedge pclk_o);
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
      @(negedge pclk_o);
      apb4.paddr   = address;
      apb4.pwdata  = data;
      apb4.pstrb   = 4'hF;
      apb4.pwrite  = 1'b1;
      apb4.psel    = 1'b1;
      apb4.penable = 1'b0;
      @(negedge pclk_o);
      apb4.penable = 1'b1;
      while (!apb4.pready) @(negedge pclk_o);
      if (apb4.pslverr !== 1'b0) begin
        $fatal(1, "write %h error=%b expected=%b", address, apb4.pslverr, 1'b0);
      end
      apb4.psel    = 1'b0;
      apb4.penable = 1'b0;
      apb4.pwrite  = 1'b0;
      apb4.pstrb   = '0;
    end
  endtask

  task automatic wait_for_completion(output logic [31:0] status);
    integer index;
    logic   complete;
    begin
      status   = '0;
      complete = 1'b0;
      for (index = 0; index < 3000; index = index + 1) begin
        if (!complete) begin
          read_register(32'h1000_B01C, status);
          complete = !status[4];
        end
      end
      if (!complete) begin
        $fatal(1, "pll configuration did not complete");
      end
    end
  endtask

  initial begin
    apb4.psel                       = 1'b0;
    apb4.paddr                      = '0;
    apb4.pwdata                     = '0;
    apb4.pstrb                      = '0;
    sysctrl.user_bus_idle_i         = 1'b1;
    sysctrl.fault_access_i          = 1'b0;
    sysctrl.fault_master_i          = '0;
    sysctrl.fault_code_i            = '0;
    sysctrl.perf_mgmt_wait_i        = '0;
    sysctrl.perf_user_wait_i        = '0;
    sysctrl.perf_dma_wait_i         = '0;
    sysctrl.perf_sdio0_wait_i       = '0;
    sysctrl.perf_sdio1_wait_i       = '0;
    sysctrl.perf_usb2_wait_i        = '0;
    sysctrl.perf_apb4_periph_wait_i = '0;
    sysctrl.perf_apb4_system_wait_i = '0;
    sysctrl.perf_sdram_wait_i       = '0;
    sysctrl.perf_psram_wait_i       = '0;
    sysctrl.perf_flash_wait_i       = '0;
    sysctrl.rtc_wake_i              = 1'b0;
    sysctrl.hp_present_i            = 1'b0;
    rst_n_i                         = 1'b1;
    #10;
    rst_n_i = 1'b0;
    #100;
    rst_n_i = 1'b1;
    $display("pll_ctrl_tb: root reset released");
    repeat (2) begin
      @(posedge aud_clk_i);
      #1;
      if (aud_clk_o !== 1'b1) begin
        $fatal(1, "buffered audio clock did not follow a rising edge");
      end
      @(negedge aud_clk_i);
      #1;
      if (aud_clk_o !== 1'b0) begin
        $fatal(1, "buffered audio clock did not follow a falling edge");
      end
    end
    $display("pll_ctrl_tb: audio clock buffer passed");
    wait (aud_rst_n_o);
    $display("pll_ctrl_tb: audio reset released");
    repeat (50) @(posedge ref24_clk_i);
    $display("pll_ctrl_tb: lp_clk=%b lp_rst=%b pclk=%b pclk_rst=%b div=%b valid=%b", sys_clk_o,
             sys_rst_n_o, pclk_o, pclk_rst_n_o,
             u_rcu.u_clock_reset_subsystem.u_pclk_divider.s_div_q,
             u_rcu.u_clock_reset_subsystem.s_pclk_cfg_valid);
    wait (pclk_rst_n_o);
    repeat (12) @(posedge pclk_o);
    $display("pll_ctrl_tb: clock domains released");

    if (!$test$plusargs("pll_lock_fail")) begin
      wdg_reset_req_i = 1'b1;
      #1;
      if (aon_rst_n_o !== 1'b1 || sys_rst_n_o || hp_rst_n_o || pclk_rst_n_o || mem_rst_n_o ||
          aud_rst_n_o) begin
        $fatal(1, "watchdog reset did not preserve AON and reset controlled domains");
      end
      wdg_reset_req_i = 1'b0;
      wait (pclk_rst_n_o && sys_rst_n_o && hp_rst_n_o && mem_rst_n_o && aud_rst_n_o);
      if (!aon_rst_n_o) begin
        $fatal(1, "watchdog reset disturbed AON reset");
      end
      $display("pll_ctrl_tb: watchdog reset recovery passed");
    end

    read_register(32'h1000_B01C, read_data);
`ifdef HAVE_PLL
    if ($test$plusargs("pll_lock_fail")) begin
      if ((read_data !== 32'h0000_0500) && (read_data !== 32'h0000_05A0)) begin
        $fatal(1, "runtime PLL lock fault status mismatch: %h", read_data);
      end
    end else if (read_data !== 32'h0000_0500) begin
      $fatal(1, "pll reset status is not the external safe clock");
    end
`else
    if (read_data !== 32'h0000_0100) begin
      $fatal(1, "unsupported pll reset status is not the external safe clock");
    end
`endif

    write_register(32'h1000_B008, 32'd4);
    write_register(32'h1000_B00C, 32'd1);
    $display("pll_ctrl_tb: PLL request submitted");
    wait_for_completion(read_data);

`ifdef HAVE_PLL
    if ($test$plusargs("pll_lock_fail")) begin
      if (read_data !== 32'h0000_05A0) begin
        $fatal(1, "pll lock timeout did not keep the external safe clock");
      end
      $display("pll controller timeout test passed");
      $finish;
    end

    if (read_data !== 32'h0000_060C) begin
      $fatal(1, "pll configuration did not select the requested frequency");
    end
    repeat (4) @(posedge hp_clk_o);
    @(posedge hp_clk_o);
    edge_start = $time;
    @(posedge hp_clk_o);
    edge_end = $time;
    if ((edge_end - edge_start) > 9) begin
      $fatal(1, "pll behavioral output is slower than 120MHz");
    end

    write_register(32'h1000_B008, 32'd0);
    write_register(32'h1000_B00C, 32'd1);
    wait_for_completion(read_data);
    if (read_data !== 32'h0000_0608) begin
      $fatal(1, "pll did not select the 24MHz profile");
    end
    repeat (4) @(posedge hp_clk_o);
    @(posedge hp_clk_o);
    edge_start = $time;
    @(posedge hp_clk_o);
    edge_end = $time;
    if ((edge_end - edge_start) < 12) begin
      $fatal(1, "pll behavioral output is faster than the 72MHz profile");
    end

    $display("pll controller dynamic configuration test passed");
`else
    if (read_data !== 32'h0000_0160) begin
      $fatal(1, "unsupported pll backend did not report the safe-clock error");
    end
    $display("pll controller capability gate test passed");
`endif
    $finish;
  end
endmodule
