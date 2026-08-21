// Shared APB4 master helpers for unit tests.
// The including module must provide clk_i and an apb4_if instance.
`ifndef APB4_BFM_IF
`define APB4_BFM_IF apb4
`endif

task automatic apb4_idle();
  begin
    `APB4_BFM_IF.psel    = 1'b0;
    `APB4_BFM_IF.penable = 1'b0;
    `APB4_BFM_IF.pwrite  = 1'b0;
    `APB4_BFM_IF.paddr   = '0;
    `APB4_BFM_IF.pwdata  = '0;
    `APB4_BFM_IF.pstrb   = '0;
    `APB4_BFM_IF.pprot   = '0;
  end
endtask

task automatic apb4_xfer(input logic [31:0] address, input logic write, input logic [31:0] wdata,
                         input logic [3:0] strobe, input logic expected_error,
                         output logic [31:0] rdata);
  begin
    @(negedge clk_i);
    `APB4_BFM_IF.paddr   = address;
    `APB4_BFM_IF.pwdata  = wdata;
    `APB4_BFM_IF.pstrb   = write ? strobe : 4'h0;
    `APB4_BFM_IF.pwrite  = write;
    `APB4_BFM_IF.pprot   = '0;
    `APB4_BFM_IF.psel    = 1'b1;
    `APB4_BFM_IF.penable = 1'b0;
    @(negedge clk_i);
    `APB4_BFM_IF.penable = 1'b1;
    while (!`APB4_BFM_IF.pready) begin
      @(negedge clk_i);
    end
    if (`APB4_BFM_IF.pslverr !== expected_error) begin
      $fatal(1, "APB4 %s %h error=%b expected=%b", write ? "write" : "read", address,
             `APB4_BFM_IF.pslverr, expected_error);
    end
    rdata                = `APB4_BFM_IF.prdata;
    `APB4_BFM_IF.psel    = 1'b0;
    `APB4_BFM_IF.penable = 1'b0;
    `APB4_BFM_IF.pwrite  = 1'b0;
    `APB4_BFM_IF.pstrb   = '0;
  end
endtask

task automatic apb4_write(input logic [31:0] address, input logic [31:0] data,
                          input logic [3:0] strobe, input logic expected_error);
  logic [31:0] unused_rdata;
  begin
    apb4_xfer(address, 1'b1, data, strobe, expected_error, unused_rdata);
  end
endtask

task automatic apb4_read(input logic [31:0] address, input logic expected_error,
                         output logic [31:0] data);
  begin
    apb4_xfer(address, 1'b0, 32'd0, 4'h0, expected_error, data);
  end
endtask
