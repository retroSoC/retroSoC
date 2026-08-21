`timescale 1ns / 1ps

module bus_fault_tb;
  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        fault_valid_o;
  logic [31:0] fault_addr_o;
  logic [ 3:0] fault_wstrb_o;
  logic        fault_reserved_o;
  logic        fault_access_o;
  logic [ 1:0] fault_master_o;
  logic [ 2:0] fault_code_o;
  logic        user_bus_idle_o;
  rib_if mgmt_rib ();
  rib_if user_rib ();
  rib_if dma_rib ();
  rib_if rib ();
  rib_if apb_rib ();

  always #5 clk_i = ~clk_i;

  assign rib.cmd_ready     = 1'b1;
  assign rib.w_ready       = 1'b1;
  assign rib.rsp_valid     = 1'b0;
  assign rib.rdata         = 32'hCAFE_BABE;
  assign rib.resp_err      = 1'b0;
  assign rib.resp_code     = `RIB_RESP_OK;
  assign rib.rsp_beat      = '0;
  assign rib.rsp_last      = 1'b0;
  assign apb_rib.cmd_ready = 1'b1;
  assign apb_rib.w_ready   = 1'b1;
  assign apb_rib.rsp_valid = 1'b0;
  assign apb_rib.rdata     = 32'h1234_5678;
  assign apb_rib.resp_err  = 1'b0;
  assign apb_rib.resp_code = `RIB_RESP_OK;
  assign apb_rib.rsp_beat  = '0;
  assign apb_rib.rsp_last  = 1'b1;

  rib_bus u_bus (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .mgmt_rib         (mgmt_rib),
      .user_rib         (user_rib),
      .dma_rib          (dma_rib),
      .user_bus_enable_i(1'b1),
      .user_bus_idle_o  (user_bus_idle_o),
      .rib              (rib),
      .apb_rib          (apb_rib),
      .perf_enable_i    (1'b0),
      .perf_clear_i     (1'b0),
      .fault_valid_o    (fault_valid_o),
      .fault_addr_o     (fault_addr_o),
      .fault_wstrb_o    (fault_wstrb_o),
      .fault_reserved_o (fault_reserved_o),
      .fault_access_o   (fault_access_o),
      .fault_master_o   (fault_master_o),
      .fault_code_o     (fault_code_o)
  );

  task automatic expect_fault(input logic [31:0] address, input logic [3:0] write_strobes,
                              input logic reserved, input logic [2:0] expected_code);
    begin
      @(negedge clk_i);
      mgmt_rib.cmd_addr  = address;
      mgmt_rib.cmd_write = |write_strobes;
      mgmt_rib.cmd_len   = `RIB_LEN_INCR1;
      mgmt_rib.cmd_valid = 1'b1;
      while (!mgmt_rib.cmd_ready) @(posedge clk_i);
      @(negedge clk_i);
      mgmt_rib.cmd_valid = 1'b0;
      if (|write_strobes) begin
        mgmt_rib.wdata   = 32'hA5A5_5A5A;
        mgmt_rib.wstrb   = write_strobes;
        mgmt_rib.wlast   = 1'b1;
        mgmt_rib.w_valid = 1'b1;
        while (!mgmt_rib.w_ready) @(posedge clk_i);
        @(negedge clk_i);
        mgmt_rib.w_valid = 1'b0;
      end
      while (!fault_valid_o) @(posedge clk_i);
      if (fault_addr_o !== address || fault_wstrb_o !== write_strobes ||
          fault_reserved_o !== reserved || fault_access_o || fault_code_o !== expected_code ||
          rib.cmd_valid || apb_rib.cmd_valid) begin
        $fatal(1, "unexpected fault response for address %h", address);
      end
      while (!mgmt_rib.rsp_valid) @(posedge clk_i);
      if (mgmt_rib.rdata !== 32'd0 || !mgmt_rib.resp_err) begin
        $fatal(1, "fault response data must be zero");
      end
      while (fault_valid_o) @(posedge clk_i);
    end
  endtask

  task automatic expect_user_denied(input logic [31:0] address, input logic [3:0] write_strobes);
    begin
      @(negedge clk_i);
      user_rib.cmd_addr  = address;
      user_rib.cmd_write = |write_strobes;
      user_rib.cmd_len   = `RIB_LEN_INCR1;
      user_rib.cmd_valid = 1'b1;
      while (!user_rib.cmd_ready) @(posedge clk_i);
      @(negedge clk_i);
      user_rib.cmd_valid = 1'b0;
      if (|write_strobes) begin
        user_rib.wdata   = 32'h5A5A_A5A5;
        user_rib.wstrb   = write_strobes;
        user_rib.wlast   = 1'b1;
        user_rib.w_valid = 1'b1;
        while (!user_rib.w_ready) @(posedge clk_i);
        @(negedge clk_i);
        user_rib.w_valid = 1'b0;
      end
      while (!fault_valid_o) @(posedge clk_i);
      if (!fault_access_o || fault_master_o != 2'd1 || rib.cmd_valid || apb_rib.cmd_valid) begin
        $fatal(1, "user access was not denied locally");
      end
      if (user_rib.rdata !== 32'd0 || !user_rib.resp_err || !user_rib.rsp_last ||
          user_rib.resp_code !== `RIB_RESP_PROTERR) begin
        $fatal(1, "denied user response data must be zero");
      end
      while (fault_valid_o) @(posedge clk_i);
    end
  endtask

  initial begin
    mgmt_rib.cmd_valid = 1'b0;
    mgmt_rib.cmd_addr  = '0;
    mgmt_rib.cmd_write = 1'b0;
    mgmt_rib.cmd_len   = `RIB_LEN_INCR1;
    mgmt_rib.w_valid   = 1'b0;
    mgmt_rib.wdata     = '0;
    mgmt_rib.wstrb     = '0;
    mgmt_rib.wlast     = 1'b0;
    mgmt_rib.rsp_ready = 1'b1;
    user_rib.cmd_valid = 1'b0;
    user_rib.cmd_addr  = '0;
    user_rib.cmd_write = 1'b0;
    user_rib.cmd_len   = `RIB_LEN_INCR1;
    user_rib.w_valid   = 1'b0;
    user_rib.wdata     = '0;
    user_rib.wstrb     = '0;
    user_rib.wlast     = 1'b0;
    user_rib.rsp_ready = 1'b1;
    dma_rib.cmd_valid  = 1'b0;
    dma_rib.cmd_addr   = '0;
    dma_rib.cmd_write  = 1'b0;
    dma_rib.cmd_len    = `RIB_LEN_INCR1;
    dma_rib.w_valid    = 1'b0;
    dma_rib.wdata      = '0;
    dma_rib.wstrb      = '0;
    dma_rib.wlast      = 1'b0;
    dma_rib.rsp_ready  = 1'b1;

    repeat (2) @(posedge clk_i);
    rst_n_i = 1'b1;

    expect_fault(32'h1001_2000, 4'hF, 1'b1, `RIB_RESP_RESERVED);
    expect_fault(32'hA000_0000, 4'h0, 1'b0, `RIB_RESP_DECERR);
    expect_user_denied(32'h1000_B000, 4'hF);
    $display("bus fault responder test passed");
    $finish;
  end
endmodule
