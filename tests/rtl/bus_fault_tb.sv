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
  soc_nmi_if mgmt_nmi ();
  soc_nmi_if user_nmi ();
  soc_nmi_if dma_nmi ();
  nmi_if natv_nmi ();
  nmi_if apb_nmi ();

  always #5 clk_i = ~clk_i;

  assign natv_nmi.ready = 1'b1;
  assign natv_nmi.rdata = 32'hCAFE_BABE;
  assign apb_nmi.ready  = 1'b1;
  assign apb_nmi.rdata  = 32'h1234_5678;

  bus u_bus (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .mgmt_nmi         (mgmt_nmi),
      .user_nmi         (user_nmi),
      .dma_nmi          (dma_nmi),
      .user_bus_enable_i(1'b1),
      .user_bus_idle_o  (user_bus_idle_o),
      .natv_nmi         (natv_nmi),
      .apb_nmi          (apb_nmi),
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
      mgmt_nmi.addr  = address;
      mgmt_nmi.wdata = 32'hA5A5_5A5A;
      mgmt_nmi.wstrb = write_strobes;
      mgmt_nmi.valid = 1'b1;
      while (!fault_valid_o) @(posedge clk_i);
      if (fault_addr_o !== address || fault_wstrb_o !== write_strobes ||
          fault_reserved_o !== reserved || fault_access_o || fault_code_o !== expected_code ||
          natv_nmi.valid || apb_nmi.valid) begin
        $fatal(1, "unexpected fault response for address %h", address);
      end
      while (!mgmt_nmi.ready) @(posedge clk_i);
      if (mgmt_nmi.rdata !== 32'd0 || !mgmt_nmi.resp_err ||
          mgmt_nmi.resp_code !== expected_code) begin
        $fatal(1, "fault response data must be zero");
      end
      @(negedge clk_i);
      mgmt_nmi.valid = 1'b0;
      while (fault_valid_o) @(posedge clk_i);
    end
  endtask

  task automatic expect_user_denied(input logic [31:0] address, input logic [3:0] write_strobes);
    begin
      @(negedge clk_i);
      user_nmi.addr  = address;
      user_nmi.wdata = 32'h5A5A_A5A5;
      user_nmi.wstrb = write_strobes;
      user_nmi.valid = 1'b1;
      while (!fault_valid_o) @(posedge clk_i);
      if (!fault_access_o || fault_master_o != 2'd1 || natv_nmi.valid || apb_nmi.valid) begin
        $fatal(1, "user access was not denied locally");
      end
      while (!user_nmi.ready) @(posedge clk_i);
      if (user_nmi.rdata !== 32'd0 || !user_nmi.resp_err ||
          user_nmi.resp_code !== `SOC_NMI_RESP_PROTERR) begin
        $fatal(1, "denied user response data must be zero");
      end
      @(negedge clk_i);
      user_nmi.valid = 1'b0;
      while (fault_valid_o) @(posedge clk_i);
    end
  endtask

  initial begin
    mgmt_nmi.valid = 1'b0;
    mgmt_nmi.addr  = '0;
    mgmt_nmi.wdata = '0;
    mgmt_nmi.wstrb = '0;
    user_nmi.valid = 1'b0;
    user_nmi.addr  = '0;
    user_nmi.wdata = '0;
    user_nmi.wstrb = '0;
    dma_nmi.valid  = 1'b0;
    dma_nmi.addr   = '0;
    dma_nmi.wdata  = '0;
    dma_nmi.wstrb  = '0;

    repeat (2) @(posedge clk_i);
    rst_n_i = 1'b1;

    expect_fault(32'h1000_F000, 4'hF, 1'b1, `SOC_NMI_RESP_RESERVED);
    expect_fault(32'hA000_0000, 4'h0, 1'b0, `SOC_NMI_RESP_DECERR);
    expect_user_denied(32'h1000_B000, 4'hF);
    $display("bus fault responder test passed");
    $finish;
  end
endmodule
