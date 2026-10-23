// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0
// verilog_syntax: parse-as-module-body
// Verification owner is used only before DMA admission and after DMA drain.
// Every memory access, including guards/readback, crosses the real serial pins.
apb4_if xpi_apb (
    clk,
    rst_n
);
axi4_if #(
    .DATA_WIDTH(32)
) xpi_bus (
    clk,
    rst_n
);
xpi_if xpi_pins ();
tri1 [3:0] psram_data;
logic test_owner = 1, test_awvalid = 0, test_wvalid = 0, test_arvalid = 0;
logic [31:0] test_address = 0, test_data = 0;
logic xpi_idle, xpi_irq, xpi_tx_stall, xpi_rx_stall;
logic [31:0] xpi_value;
for (genvar lane = 0; lane < 4; lane++) begin : gen_psram_pins
  assign psram_data[lane] = xpi_pins.io_oe_o[lane] ? xpi_pins.io_do_o[lane] : 1'bz;
end
assign xpi_pins.io_di_i = psram_data;
apb4_xpi u_xpi (
    .clk_i           (clk),
    .rst_n_i         (rst_n),
    .dma_xfer_done_i (dma_done),
    .lifecycle_idle_o(xpi_idle),
    .dma_tx_stall_o  (xpi_tx_stall),
    .dma_rx_stall_o  (xpi_rx_stall),
    .irq_o           (xpi_irq),
    .apb4            (xpi_apb),
    .mem_axi4        (xpi_bus),
    .xpi             (xpi_pins)
);
ESP_PSRAM64H #(
    .POWER_UP_CHECK        (1),
    .TIMING_VIOLATION_FATAL(1)
) u_psram (
    .sclk(xpi_pins.sck_o),
    .csn (xpi_pins.nss_o[1]),
    .sio (psram_data)
);
assign xpi_bus.awid = test_owner ? 0 : bus.awid;
assign xpi_bus.awaddr = test_owner ? test_address : bus.awaddr;
assign xpi_bus.awlen = test_owner ? 0 : bus.awlen;
assign xpi_bus.awsize = 2;
assign xpi_bus.awburst = 1;
assign {xpi_bus.awlock, xpi_bus.awcache, xpi_bus.awprot, xpi_bus.awqos,
        xpi_bus.awregion, xpi_bus.awuser} = '0;
assign xpi_bus.awvalid = test_owner ? test_awvalid : bus.awvalid;
assign xpi_bus.wdata = test_owner ? test_data : bus.wdata;
assign xpi_bus.wstrb = test_owner ? 4'hf : bus.wstrb;
assign xpi_bus.wlast = test_owner ? 1'b1 : bus.wlast;
assign xpi_bus.wuser = 0;
assign xpi_bus.wvalid = test_owner ? test_wvalid : bus.wvalid;
assign xpi_bus.bready = test_owner || (bus.bready && (written_words < FrameWords || release_response));
assign bus.awready = !test_owner && xpi_bus.awready;
assign bus.wready = !test_owner && xpi_bus.wready;
assign bus.bvalid = !test_owner && xpi_bus.bvalid && (written_words < FrameWords || release_response);
assign bus.bid = xpi_bus.bid;
assign bus.bresp = xpi_bus.bresp;
assign bus.buser = xpi_bus.buser;
assign xpi_bus.arid = 0;
assign xpi_bus.araddr = test_address;
assign xpi_bus.arlen = 0;
assign xpi_bus.arsize = 2;
assign xpi_bus.arburst = 1;
assign {xpi_bus.arlock, xpi_bus.arcache, xpi_bus.arprot, xpi_bus.arqos,
        xpi_bus.arregion, xpi_bus.aruser} = '0;
assign xpi_bus.arvalid = test_owner && test_arvalid;
assign xpi_bus.rready = test_owner;
assign bus.arready = 0;
assign {bus.rvalid, bus.rlast, bus.rdata, bus.rid, bus.rresp, bus.ruser} = '0;

task automatic xpi_access(input bit write, input logic [11:0] address, input logic [31:0] data,
                          output logic [31:0] result);
  @(negedge clk);
  xpi_apb.paddr   = {20'd0, address};
  xpi_apb.pwdata  = data;
  xpi_apb.pwrite  = write;
  xpi_apb.pstrb   = write ? 4'hf : 0;
  xpi_apb.psel    = 1;
  xpi_apb.penable = 0;
  @(negedge clk);
  xpi_apb.penable = 1;
  do @(posedge clk); while (!xpi_apb.pready);
  if (xpi_apb.pslverr) $fatal(1, "P9 XPI APB error %h", address);
  result = xpi_apb.prdata;
  @(negedge clk);
  xpi_apb.psel    = 0;
  xpi_apb.penable = 0;
endtask
task automatic xpi_write(input logic [11:0] address, input logic [31:0] data);
  logic [31:0] ignored;
  xpi_access(1, address, data, ignored);
endtask
task automatic xpi_wait_idle;
  do xpi_access(0, 12'h010, 0, xpi_value); while ((xpi_value & 32'he) != 0);
endtask
task automatic xpi_command(input logic [7:0] opcode);
  xpi_wait_idle();
  xpi_write(12'h00c, 0);
  xpi_write(12'h230, {16'd0, 8'h10, opcode});
  xpi_write(12'h234, 0);
  xpi_write(12'h00c, 1);
  xpi_write(12'h024, 255);
  xpi_write(12'h048, 0);
  xpi_write(12'h04c, 0);
  xpi_write(12'h050, 32'h31);
  xpi_write(12'h014, 1);
  xpi_wait_idle();
endtask
task automatic memory_word(input bit write, input logic [31:0] address, input logic [31:0] data,
                           output logic [31:0] result);
  @(negedge clk);
  test_address = address;
  test_data    = data;
  if (write) begin
    test_awvalid = 1;
    do @(posedge clk); while (!xpi_bus.awready);
    @(negedge clk);
    test_awvalid = 0;
    test_wvalid  = 1;
    do @(posedge clk); while (!xpi_bus.wready);
    @(negedge clk);
    test_wvalid = 0;
    do @(posedge clk); while (!xpi_bus.bvalid);
    if (xpi_bus.bresp !== 0) $fatal(1, "P9 XPI guard write response");
    result = 0;
  end else begin
    test_arvalid = 1;
    do @(posedge clk); while (!xpi_bus.arready);
    @(negedge clk);
    test_arvalid = 0;
    do @(posedge clk); while (!xpi_bus.rvalid);
    if (xpi_bus.rresp !== 0 || xpi_bus.rlast !== 1'b1) $fatal(1, "P9 XPI readback response");
    result = xpi_bus.rdata;
  end
  @(negedge clk);
endtask
task automatic initialize_psram;
  xpi_apb.psel    = 0;
  xpi_apb.penable = 0;
  xpi_apb.pwrite  = 0;
  xpi_apb.paddr   = 0;
  xpi_apb.pwdata  = 0;
  xpi_apb.pstrb   = 0;
  xpi_apb.pprot   = 0;
  #150000;
  xpi_write(12'h00c, 0);
  xpi_write(12'h120, 1);
  xpi_write(12'h124, 32'h800000);
  xpi_write(12'h128, 32'h21);
  xpi_write(12'h12c, 32'h02010100);
  xpi_write(12'h130, 192);
  xpi_write(12'h134, 1024);
  xpi_write(12'h210, 32'h281818eb);
  xpi_write(12'h214, 32'h68004006);
  xpi_write(12'h220, 32'h28181838);
  xpi_write(12'h224, 32'h00005800);
  xpi_write(12'h240, 32'h2018109f);
  xpi_write(12'h244, 32'h00006000);
  xpi_write(12'h00c, 1);
  xpi_command(8'h66);
  xpi_command(8'h99);
  #100;
  xpi_write(12'h024, 255);
  xpi_write(12'h048, 0);
  xpi_write(12'h04c, 6);
  xpi_write(12'h050, 32'h41);
  xpi_write(12'h014, 1);
  xpi_wait_idle();
  xpi_access(0, 12'h044, 0, xpi_value);
  if (xpi_value[23:0] !== 24'h265d0d) $fatal(1, "P9 PSRAM identity mismatch %h", xpi_value);
  xpi_access(0, 12'h044, 0, xpi_value);
  xpi_command(8'h35);
  xpi_write(12'h00c, 0);
  xpi_write(12'h120, 7);
  xpi_write(12'h00c, 1);
  for (int word_index = 0; word_index < FrameWords + 2; word_index++)
    memory_word(1, Destination - 4 + 32'(word_index * 4), 32'hcafebabe, xpi_value);
  test_owner = 0;
endtask
task automatic verify_psram;
  if (!dma_idle || response_pending) $fatal(1, "P9 XPI verification before DMA drain");
  test_owner = 1;
  for (int word_index = 0; word_index < FrameWords + 2; word_index++) begin
    memory_word(0, Destination - 4 + 32'(word_index * 4), 0, xpi_value);
    memory[word_index] = xpi_value;
  end
  xpi_wait_idle();
  xpi_access(0, 12'h024, 0, xpi_value);
  if ((xpi_value & 32'h60) != 0) $fatal(1, "P9 XPI error after DMA capture");
  $display("P9_XPI_READBACK bytes=256 guards=2 pixel_hz=1000000");
endtask
