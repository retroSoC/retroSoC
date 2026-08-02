`timescale 1ns / 1ps

module pll_ctrl_tb;
  logic        ext_clk_i = 1'b0;
  logic        xtal_clk_i = 1'b0;
  logic        aud_clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        fault_valid_i = 1'b0;
  logic [31:0] fault_addr_i = '0;
  logic [ 3:0] fault_wstrb_i = '0;
  logic        fault_reserved_i = 1'b0;
  rib_if rib ();
  sysctrl_if sysctrl ();
  pll_ctrl_if pll_ctrl ();
  logic        sys_clk_o;
  logic        sys_rst_n_o;
  logic        aud_rst_n_o;
  logic        sys_clkdiv4_o;
  logic [31:0] read_data;
  time         edge_start;
  time         edge_end;

  always #7 ext_clk_i = ~ext_clk_i;
  always #21 xtal_clk_i = ~xtal_clk_i;
  always #27 aud_clk_i = ~aud_clk_i;

  rcu u_rcu (
      .ext_clk_i    (ext_clk_i),
      .aud_clk_i    (aud_clk_i),
      .ext_rst_n_i  (rst_n_i),
`ifdef HAVE_PLL
      .xtal_clk_i   (xtal_clk_i),
`endif
      .pll_ctrl     (pll_ctrl),
      .sys_clk_o    (sys_clk_o),
      .sys_rst_n_o  (sys_rst_n_o),
      .aud_rst_n_o  (aud_rst_n_o),
      .sys_clkdiv4_o(sys_clkdiv4_o)
  );

  rib_sysctrl u_sysctrl (
      .clk_i           (sys_clk_o),
      .rst_n_i         (sys_rst_n_o),
      .fault_valid_i   (fault_valid_i),
      .fault_addr_i    (fault_addr_i),
      .fault_wstrb_i   (fault_wstrb_i),
      .fault_reserved_i(fault_reserved_i),
      .rib             (rib),
      .sysctrl         (sysctrl),
      .pll_ctrl        (pll_ctrl)
  );

  task automatic read_register(input logic [31:0] address, output logic [31:0] data);
    begin
      @(negedge sys_clk_o);
      rib.addr  = address;
      rib.wdata = '0;
      rib.wstrb = '0;
      rib.valid = 1'b1;
      while (!rib.ready) @(posedge sys_clk_o);
      data = rib.rdata;
      @(negedge sys_clk_o);
      rib.valid = 1'b0;
      while (rib.ready) @(posedge sys_clk_o);
    end
  endtask

  task automatic write_register(input logic [31:0] address, input logic [31:0] data);
    begin
      @(negedge sys_clk_o);
      rib.addr  = address;
      rib.wdata = data;
      rib.wstrb = 4'hF;
      rib.valid = 1'b1;
      while (!rib.ready) @(posedge sys_clk_o);
      @(negedge sys_clk_o);
      rib.valid = 1'b0;
      while (rib.ready) @(posedge sys_clk_o);
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
    rib.valid               = 1'b0;
    rib.addr                = '0;
    rib.wdata               = '0;
    rib.wstrb               = '0;
    sysctrl.user_bus_idle_i = 1'b1;
    sysctrl.fault_access_i  = 1'b0;
    sysctrl.fault_master_i  = '0;
    #100;
    rst_n_i = 1'b1;
    repeat (12) @(posedge sys_clk_o);

    read_register(32'h1000_B01C, read_data);
`ifdef HAVE_PLL
    if (read_data !== 32'h0000_0500) begin
      $fatal(1, "pll reset status is not the external safe clock");
    end
`else
    if (read_data !== 32'h0000_0100) begin
      $fatal(1, "unsupported pll reset status is not the external safe clock");
    end
`endif

    write_register(32'h1000_B008, 32'd4);
    write_register(32'h1000_B00C, 32'd1);
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
    repeat (4) @(posedge sys_clk_o);
    @(posedge sys_clk_o);
    edge_start = $time;
    @(posedge sys_clk_o);
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
    repeat (4) @(posedge sys_clk_o);
    @(posedge sys_clk_o);
    edge_start = $time;
    @(posedge sys_clk_o);
    edge_end = $time;
    if ((edge_end - edge_start) < 35) begin
      $fatal(1, "pll behavioral output is faster than the 24MHz profile");
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
