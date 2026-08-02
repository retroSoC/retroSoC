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
  soc_rib_if mgmt_rib ();
  soc_rib_if user_rib ();
  soc_rib_if dma_rib ();
  rib_if rib ();
  rib_if apb_rib ();

  always #5 clk_i = ~clk_i;

  assign rib.ready = 1'b1;
  assign rib.rdata = 32'hCAFE_BABE;
  assign apb_rib.ready  = 1'b1;
  assign apb_rib.rdata  = 32'h1234_5678;

  bus u_bus (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .mgmt_rib         (mgmt_rib),
      .user_rib         (user_rib),
      .dma_rib          (dma_rib),
      .user_bus_enable_i(1'b1),
      .user_bus_idle_o  (user_bus_idle_o),
      .rib         (rib),
      .apb_rib          (apb_rib),
      .apb_resp_err_i   (1'b0),
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
      mgmt_rib.addr  = address;
      mgmt_rib.wdata = 32'hA5A5_5A5A;
      mgmt_rib.wstrb = write_strobes;
      mgmt_rib.valid = 1'b1;
      while (!fault_valid_o) @(posedge clk_i);
      if (fault_addr_o !== address || fault_wstrb_o !== write_strobes ||
          fault_reserved_o !== reserved || fault_access_o || fault_code_o !== expected_code ||
          rib.valid || apb_rib.valid) begin
        $fatal(1, "unexpected fault response for address %h", address);
      end
      while (!mgmt_rib.ready) @(posedge clk_i);
      if (mgmt_rib.rdata !== 32'd0 || !mgmt_rib.resp_err ||
          mgmt_rib.resp_code !== expected_code) begin
        $fatal(1, "fault response data must be zero");
      end
      @(negedge clk_i);
      mgmt_rib.valid = 1'b0;
      while (fault_valid_o) @(posedge clk_i);
    end
  endtask

  task automatic expect_user_denied(input logic [31:0] address, input logic [3:0] write_strobes);
    begin
      @(negedge clk_i);
      user_rib.addr  = address;
      user_rib.wdata = 32'h5A5A_A5A5;
      user_rib.wstrb = write_strobes;
      user_rib.valid = 1'b1;
      while (!fault_valid_o) @(posedge clk_i);
      if (!fault_access_o || fault_master_o != 2'd1 || rib.valid || apb_rib.valid) begin
        $fatal(1, "user access was not denied locally");
      end
      while (!user_rib.ready) @(posedge clk_i);
      if (user_rib.rdata !== 32'd0 || !user_rib.resp_err ||
          user_rib.resp_code !== `SOC_RIB_RESP_PROTERR) begin
        $fatal(1, "denied user response data must be zero");
      end
      @(negedge clk_i);
      user_rib.valid = 1'b0;
      while (fault_valid_o) @(posedge clk_i);
    end
  endtask

  initial begin
    mgmt_rib.valid = 1'b0;
    mgmt_rib.addr  = '0;
    mgmt_rib.wdata = '0;
    mgmt_rib.wstrb = '0;
    user_rib.valid = 1'b0;
    user_rib.addr  = '0;
    user_rib.wdata = '0;
    user_rib.wstrb = '0;
    dma_rib.valid  = 1'b0;
    dma_rib.addr   = '0;
    dma_rib.wdata  = '0;
    dma_rib.wstrb  = '0;

    repeat (2) @(posedge clk_i);
    rst_n_i = 1'b1;

    expect_fault(32'h1000_F000, 4'hF, 1'b1, `SOC_RIB_RESP_RESERVED);
    expect_fault(32'hA000_0000, 4'h0, 1'b0, `SOC_RIB_RESP_DECERR);
    expect_user_denied(32'h1000_B000, 4'hF);
    $display("bus fault responder test passed");
    $finish;
  end
endmodule
