`timescale 1ns / 1ps

module bus_fault_tb;
  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        fault_valid_o;
  logic [31:0] fault_addr_o;
  logic [ 3:0] fault_wstrb_o;
  logic        fault_reserved_o;
  nmi_if core_nmi ();
  nmi_if dma_nmi ();
  nmi_if natv_nmi ();
  nmi_if apb_nmi ();

  always #5 clk_i = ~clk_i;

  assign natv_nmi.ready = 1'b1;
  assign natv_nmi.rdata = 32'hCAFE_BABE;
  assign apb_nmi.ready  = 1'b1;
  assign apb_nmi.rdata  = 32'h1234_5678;

  bus u_bus (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .core_nmi        (core_nmi),
      .dma_nmi         (dma_nmi),
      .natv_nmi        (natv_nmi),
      .apb_nmi         (apb_nmi),
      .fault_valid_o   (fault_valid_o),
      .fault_addr_o    (fault_addr_o),
      .fault_wstrb_o   (fault_wstrb_o),
      .fault_reserved_o(fault_reserved_o)
  );

  task automatic expect_fault(input logic [31:0] address, input logic [3:0] write_strobes,
                              input logic reserved);
    begin
      @(negedge clk_i);
      core_nmi.addr  = address;
      core_nmi.wdata = 32'hA5A5_5A5A;
      core_nmi.wstrb = write_strobes;
      core_nmi.valid = 1'b1;

      while (!fault_valid_o) @(posedge clk_i);
      if (fault_addr_o !== address || fault_wstrb_o !== write_strobes ||
          fault_reserved_o !== reserved || natv_nmi.valid || apb_nmi.valid) begin
        $fatal(1, "unexpected fault response for address %h", address);
      end
      while (!core_nmi.ready) @(posedge clk_i);
      if (core_nmi.rdata !== 32'd0) begin
        $fatal(1, "fault response data must be zero");
      end
      @(negedge clk_i);
      core_nmi.valid = 1'b0;
      while (fault_valid_o) @(posedge clk_i);
    end
  endtask

  initial begin
    core_nmi.valid = 1'b0;
    core_nmi.addr  = '0;
    core_nmi.wdata = '0;
    core_nmi.wstrb = '0;
    dma_nmi.valid  = 1'b0;
    dma_nmi.addr   = '0;
    dma_nmi.wdata  = '0;
    dma_nmi.wstrb  = '0;

    repeat (2) @(posedge clk_i);
    rst_n_i = 1'b1;

    expect_fault(32'h1000_F000, 4'hF, 1'b1);
    expect_fault(32'hA000_0000, 4'h0, 1'b0);
    $display("bus fault responder test passed");
    $finish;
  end
endmodule
