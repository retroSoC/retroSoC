`timescale 1ns / 1ps

module sdram_data_tb;
  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  wire  [15:0] s_dq;
  logic [31:0] s_read_data;
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  ribp_if cfg_ribp ();
  sdram_if sdram ();

  always #5 clk_i = ~clk_i;

  assign s_dq       = sdram.oe_o ? sdram.dq_o : 'z;
  assign sdram.dq_i = s_dq;

  axi4_sdram u_axi4_sdram (
      .clk_i   (clk_i),
      .rst_n_i (rst_n_i),
      .axi4    (axi4),
      .cfg_ribp(cfg_ribp),
      .sdram   (sdram)
  );

`ifdef SDRAM_TIMING_MODEL
  sdr u_sdr (
      .Clk  (sdram.clk_o),
      .Cke  (sdram.cke_o),
      .Cs_n (sdram.cs_n_o),
      .Ras_n(sdram.ras_n_o),
      .Cas_n(sdram.cas_n_o),
      .We_n (sdram.we_n_o),
      .Addr (sdram.addr_o),
      .Ba   (sdram.ba_o),
      .Dq   (s_dq),
      .Dqm  (sdram.dqm_o)
  );
`else
  sdram_verilator_model u_sdram_verilator_model (
      .clk_i  (sdram.clk_o),
      .cke_i  (sdram.cke_o),
      .cs_n_i (sdram.cs_n_o),
      .ras_n_i(sdram.ras_n_o),
      .cas_n_i(sdram.cas_n_o),
      .we_n_i (sdram.we_n_o),
      .ba_i   (sdram.ba_o),
      .addr_i (sdram.addr_o),
      .dqm_i  (sdram.dqm_o),
      .dq_io  (s_dq)
  );
`endif

  task automatic init_axi4;
    begin
      axi4.awid      = '0;
      axi4.awaddr    = '0;
      axi4.awlen     = '0;
      axi4.awsize    = `AXI4_BURST_SIZE_4BYTES;
      axi4.awburst   = `AXI4_BURST_TYPE_INCR;
      axi4.awlock    = `AXI4_LOCK_NORM;
      axi4.awcache   = `AXI4_CACHE_NO_BUF;
      axi4.awprot    = `AXI4_PROT_DATA;
      axi4.awqos     = `AXI4_QOS_NORMAL;
      axi4.awregion  = `AXI4_REGION_NORMAL;
      axi4.awuser    = '0;
      axi4.awvalid   = 1'b0;
      axi4.wdata     = '0;
      axi4.wstrb     = '0;
      axi4.wlast     = 1'b0;
      axi4.wuser     = '0;
      axi4.wvalid    = 1'b0;
      axi4.bready    = 1'b0;
      axi4.arid      = '0;
      axi4.araddr    = '0;
      axi4.arlen     = '0;
      axi4.arsize    = `AXI4_BURST_SIZE_4BYTES;
      axi4.arburst   = `AXI4_BURST_TYPE_INCR;
      axi4.arlock    = `AXI4_LOCK_NORM;
      axi4.arcache   = `AXI4_CACHE_NO_BUF;
      axi4.arprot    = `AXI4_PROT_DATA;
      axi4.arqos     = `AXI4_QOS_NORMAL;
      axi4.arregion  = `AXI4_REGION_NORMAL;
      axi4.aruser    = '0;
      axi4.arvalid   = 1'b0;
      axi4.rready    = 1'b0;
      cfg_ribp.valid = 1'b0;
      cfg_ribp.addr  = '0;
      cfg_ribp.wdata = '0;
      cfg_ribp.wstrb = '0;
    end
  endtask

  task automatic write_word(input logic [31:0] address, input logic [31:0] data,
                            input logic [3:0] strobe);
    begin
      @(negedge clk_i);
      axi4.awaddr  = address;
      axi4.awlen   = 8'd0;
      axi4.awvalid = 1'b1;
      do @(posedge clk_i); while (!axi4.awready);
      @(negedge clk_i);
      axi4.awvalid = 1'b0;
      axi4.wdata   = data;
      axi4.wstrb   = strobe;
      axi4.wlast   = 1'b1;
      axi4.wvalid  = 1'b1;
      do @(posedge clk_i); while (!axi4.wready);
      @(negedge clk_i);
      axi4.wvalid = 1'b0;
      axi4.wlast  = 1'b0;
      axi4.bready = 1'b1;
      do @(posedge clk_i); while (!axi4.bvalid);
      if (axi4.bresp != `AXI4_RESP_OKAY) begin
        $fatal(1, "AXI4 SDRAM write failed at %08x", address);
      end
      @(negedge clk_i);
      axi4.bready = 1'b0;
    end
  endtask

  task automatic read_word(input logic [31:0] address);
    begin
      @(negedge clk_i);
      axi4.araddr  = address;
      axi4.arlen   = 8'd0;
      axi4.arvalid = 1'b1;
      do @(posedge clk_i); while (!axi4.arready);
      @(negedge clk_i);
      axi4.arvalid = 1'b0;
      axi4.rready  = 1'b1;
      do @(posedge clk_i); while (!axi4.rvalid);
      s_read_data = axi4.rdata;
      if (axi4.rresp != `AXI4_RESP_OKAY || !axi4.rlast) begin
        $fatal(1, "AXI4 SDRAM read failed at %08x", address);
      end
      @(negedge clk_i);
      axi4.rready = 1'b0;
    end
  endtask

  initial begin
    init_axi4();
    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;

    // The controller waits 100 us after reset before accepting a request.
    repeat (8000) @(posedge clk_i);

    write_word(`SOC_ADDR_SDRAM_BASE, 32'h1234_5678, 4'b1111);
    read_word(`SOC_ADDR_SDRAM_BASE);
    if (s_read_data !== 32'h1234_5678) begin
      $fatal(1, "full-word SDRAM readback was %08x", s_read_data);
    end

    write_word(`SOC_ADDR_SDRAM_BASE, 32'hA5A5_0000, 4'b1100);
    read_word(`SOC_ADDR_SDRAM_BASE);
    if (s_read_data !== 32'hA5A5_5678) begin
      $fatal(1, "masked SDRAM readback was %08x", s_read_data);
    end

    write_word(`SOC_ADDR_SDRAM_BASE + 32'h03FF_FFFC, 32'hCAFE_BABE, 4'b1111);
    read_word(`SOC_ADDR_SDRAM_BASE + 32'h03FF_FFFC);
    if (s_read_data !== 32'hCAFE_BABE) begin
      $fatal(1, "high-address SDRAM readback was %08x", s_read_data);
    end

    $display("sdram data integrity test passed");
    $finish;
  end
endmodule
