`timescale 1ns / 1ps

module sdram_data_tb;
  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  wire  [15:0] s_dq;
  logic [31:0] s_read_data;
  rib_if rib ();
  sdram_if sdram ();

  always #5 clk_i = ~clk_i;

  assign s_dq       = sdram.oe_o ? sdram.dq_o : 'z;
  assign sdram.dq_i = s_dq;

  rib_sdram u_rib_sdram (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .rib    (rib),
      .sdram  (sdram)
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

  task automatic write_word(input logic [31:0] address, input logic [31:0] data,
                            input logic [3:0] strobe);
    begin
      @(negedge clk_i);
      rib.addr  = address;
      rib.wdata = data;
      rib.wstrb = strobe;
      rib.valid = 1'b1;
      do begin
        @(posedge clk_i);
      end while (!rib.ready);
      @(negedge clk_i);
      rib.valid = 1'b0;
      rib.wstrb = '0;
    end
  endtask

  task automatic read_word(input logic [31:0] address);
    begin
      @(negedge clk_i);
      rib.addr  = address;
      rib.wdata = '0;
      rib.wstrb = '0;
      rib.valid = 1'b1;
      do begin
        @(posedge clk_i);
      end while (!rib.ready);
      s_read_data = rib.rdata;
      @(negedge clk_i);
      rib.valid = 1'b0;
    end
  endtask

  initial begin
    rib.addr  = '0;
    rib.valid = 1'b0;
    rib.wdata = '0;
    rib.wstrb = '0;
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

    $display("sdram data integrity test passed");
    $finish;
  end
endmodule
