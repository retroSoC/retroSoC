`timescale 1ns / 1ps

module sysctrl_fault_tb;
  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        fault_valid_i = 1'b0;
  logic [31:0] fault_addr_i = '0;
  logic [ 3:0] fault_wstrb_i = '0;
  logic        fault_reserved_i = 1'b0;
  nmi_if nmi ();
  sysctrl_if sysctrl ();
  pll_ctrl_if pll_ctrl ();

  always #5 clk_i = ~clk_i;

  nmi_sysctrl u_sysctrl (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .fault_valid_i   (fault_valid_i),
      .fault_addr_i    (fault_addr_i),
      .fault_wstrb_i   (fault_wstrb_i),
      .fault_reserved_i(fault_reserved_i),
      .nmi             (nmi),
      .sysctrl         (sysctrl),
      .pll_ctrl        (pll_ctrl)
  );

  task automatic read_register(input logic [31:0] address, output logic [31:0] data);
    begin
      @(negedge clk_i);
      nmi.addr  = address;
      nmi.wdata = '0;
      nmi.wstrb = '0;
      nmi.valid = 1'b1;
      while (!nmi.ready) @(posedge clk_i);
      data = nmi.rdata;
      @(negedge clk_i);
      nmi.valid = 1'b0;
      while (nmi.ready) @(posedge clk_i);
    end
  endtask

  task automatic write_register(input logic [31:0] address, input logic [31:0] data);
    begin
      @(negedge clk_i);
      nmi.addr  = address;
      nmi.wdata = data;
      nmi.wstrb = 4'hF;
      nmi.valid = 1'b1;
      while (!nmi.ready) @(posedge clk_i);
      @(negedge clk_i);
      nmi.valid = 1'b0;
      while (nmi.ready) @(posedge clk_i);
    end
  endtask

  logic [31:0] read_data;
  initial begin
    nmi.valid                   = 1'b0;
    nmi.addr                    = '0;
    nmi.wdata                   = '0;
    nmi.wstrb                   = '0;
    sysctrl.core_sel_i          = '0;
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
    write_register(32'h1000_B010, 32'h0000_0001);
    read_register(32'h1000_B010, read_data);
    if (read_data !== 32'h0000_000A) $fatal(1, "fault W1C did not clear pending");

    $display("sysctrl fault registers test passed");
    $finish;
  end
endmodule
