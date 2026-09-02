`timescale 1ns / 1ps

`include "axi4_define.svh"
`include "mmap_define.svh"
`include "onchip_ram_define.svh"

module onchip_ram_tb #(
    parameter int unsigned CapacityKiB = 128
);
  localparam logic [31:0] SramBase = `SOC_ADDR_SRAM_BASE;
  localparam logic [31:0] SramEnd = `SOC_ADDR_SRAM_END;

  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        perf_enable_i = 1'b0;
  logic        perf_clear_i = 1'b0;
  logic [31:0] s_apb_read_data;
  logic [31:0] s_expected;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) mem_axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  apb4_if cfg_apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

  onchip_ram #(
      .Present    (1'b1),
      .CapacityKiB(CapacityKiB)
  ) u_dut (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .perf_enable_i(perf_enable_i),
      .perf_clear_i (perf_clear_i),
      .mem_axi4     (mem_axi4),
      .cfg_apb4     (cfg_apb4)
  );

  task automatic init_interfaces;
    begin
      mem_axi4.awid     = '0;
      mem_axi4.awaddr   = '0;
      mem_axi4.awlen    = '0;
      mem_axi4.awsize   = `AXI4_BURST_SIZE_4BYTES;
      mem_axi4.awburst  = `AXI4_BURST_TYPE_INCR;
      mem_axi4.awlock   = `AXI4_LOCK_NORM;
      mem_axi4.awcache  = `AXI4_CACHE_NO_BUF;
      mem_axi4.awprot   = `AXI4_PROT_DATA;
      mem_axi4.awqos    = `AXI4_QOS_NORMAL;
      mem_axi4.awregion = `AXI4_REGION_NORMAL;
      mem_axi4.awuser   = '0;
      mem_axi4.awvalid  = 1'b0;
      mem_axi4.wdata    = '0;
      mem_axi4.wstrb    = '0;
      mem_axi4.wlast    = 1'b0;
      mem_axi4.wuser    = '0;
      mem_axi4.wvalid   = 1'b0;
      mem_axi4.bready   = 1'b0;
      mem_axi4.arid     = '0;
      mem_axi4.araddr   = '0;
      mem_axi4.arlen    = '0;
      mem_axi4.arsize   = `AXI4_BURST_SIZE_4BYTES;
      mem_axi4.arburst  = `AXI4_BURST_TYPE_INCR;
      mem_axi4.arlock   = `AXI4_LOCK_NORM;
      mem_axi4.arcache  = `AXI4_CACHE_NO_BUF;
      mem_axi4.arprot   = `AXI4_PROT_DATA;
      mem_axi4.arqos    = `AXI4_QOS_NORMAL;
      mem_axi4.arregion = `AXI4_REGION_NORMAL;
      mem_axi4.aruser   = '0;
      mem_axi4.arvalid  = 1'b0;
      mem_axi4.rready   = 1'b0;
      cfg_apb4.paddr    = '0;
      cfg_apb4.pprot    = '0;
      cfg_apb4.psel     = 1'b0;
      cfg_apb4.penable  = 1'b0;
      cfg_apb4.pwrite   = 1'b0;
      cfg_apb4.pwdata   = '0;
      cfg_apb4.pstrb    = '0;
    end
  endtask

  task automatic write_burst(input logic [31:0] address, input logic [7:0] length,
                             input logic [2:0] size, input logic [1:0] burst,
                             input logic [31:0] seed, input logic [1:0] response);
    integer previous_cycle;
    integer cycle_count;
    begin
      @(negedge clk_i);
      mem_axi4.awaddr  = address;
      mem_axi4.awlen   = length;
      mem_axi4.awsize  = size;
      mem_axi4.awburst = burst;
      mem_axi4.awvalid = 1'b1;
      do @(posedge clk_i); while (!mem_axi4.awready);
      @(negedge clk_i);
      mem_axi4.awvalid = 1'b0;
      previous_cycle   = -1;
      cycle_count      = 0;
      for (int beat = 0; beat <= int'(length); beat++) begin
        mem_axi4.wdata  = seed + beat;
        mem_axi4.wstrb  = 4'hF;
        mem_axi4.wlast  = beat == int'(length);
        mem_axi4.wvalid = 1'b1;
        do begin
          @(posedge clk_i);
          cycle_count = cycle_count + 1;
        end while (!mem_axi4.wready);
        if ((previous_cycle >= 0) && (cycle_count != previous_cycle + 1)) begin
          $fatal(1, "write burst inserted a bubble at beat %0d", beat);
        end
        previous_cycle = cycle_count;
        @(negedge clk_i);
      end
      mem_axi4.wvalid = 1'b0;
      mem_axi4.wlast  = 1'b0;
      mem_axi4.bready = 1'b1;
      do @(posedge clk_i); while (!mem_axi4.bvalid);
      if (mem_axi4.bresp != response) begin
        $fatal(1, "write response=%0d expected=%0d", mem_axi4.bresp, response);
      end
      @(negedge clk_i);
      mem_axi4.bready = 1'b0;
    end
  endtask

  task automatic read_burst(input logic [31:0] address, input logic [7:0] length,
                            input logic [2:0] size, input logic [1:0] burst,
                            input logic [31:0] seed, input logic [1:0] response,
                            input logic check_data, input logic add_backpressure);
    logic   [31:0] held_data;
    logic   [ 1:0] held_resp;
    logic          held_last;
    integer        previous_cycle;
    integer        cycle_count;
    begin
      @(negedge clk_i);
      mem_axi4.araddr  = address;
      mem_axi4.arlen   = length;
      mem_axi4.arsize  = size;
      mem_axi4.arburst = burst;
      mem_axi4.arvalid = 1'b1;
      do @(posedge clk_i); while (!mem_axi4.arready);
      @(negedge clk_i);
      mem_axi4.arvalid = 1'b0;
      mem_axi4.rready  = 1'b1;
      previous_cycle   = -1;
      cycle_count      = 0;
      for (int beat = 0; beat <= int'(length); beat++) begin
        if (add_backpressure && (beat == 1)) begin
          @(negedge clk_i);
          mem_axi4.rready = 1'b0;
          while (!mem_axi4.rvalid) @(negedge clk_i);
          held_data = mem_axi4.rdata;
          held_resp = mem_axi4.rresp;
          held_last = mem_axi4.rlast;
          repeat (3) begin
            @(negedge clk_i);
            if (!mem_axi4.rvalid || (mem_axi4.rdata !== held_data) ||
                (mem_axi4.rresp !== held_resp) || (mem_axi4.rlast !== held_last)) begin
              $fatal(1, "read response changed under backpressure");
            end
          end
          mem_axi4.rready = 1'b1;
          previous_cycle  = -1;
        end
        do begin
          @(posedge clk_i);
          cycle_count = cycle_count + 1;
        end while (!mem_axi4.rvalid);
        if (mem_axi4.rresp != response || mem_axi4.rlast != (beat == int'(length))) begin
          $fatal(1, "read response mismatch at beat %0d", beat);
        end
        s_expected = seed + beat;
        if (check_data && (mem_axi4.rdata !== s_expected)) begin
          $fatal(1, "read data=%08x expected=%08x at beat %0d", mem_axi4.rdata, s_expected, beat);
        end
        if ((previous_cycle >= 0) && (cycle_count != previous_cycle + 1)) begin
          $fatal(1, "read burst inserted a bubble at beat %0d", beat);
        end
        previous_cycle = cycle_count;
      end
      @(negedge clk_i);
      mem_axi4.rready = 1'b0;
    end
  endtask

  task automatic write_single(input logic [31:0] address, input logic [2:0] size,
                              input logic [31:0] data, input logic [3:0] strobe,
                              input logic [1:0] response);
    begin
      @(negedge clk_i);
      mem_axi4.awaddr  = address;
      mem_axi4.awlen   = 8'd0;
      mem_axi4.awsize  = size;
      mem_axi4.awburst = `AXI4_BURST_TYPE_INCR;
      mem_axi4.awvalid = 1'b1;
      do @(posedge clk_i); while (!mem_axi4.awready);
      @(negedge clk_i);
      mem_axi4.awvalid = 1'b0;
      mem_axi4.wdata   = data;
      mem_axi4.wstrb   = strobe;
      mem_axi4.wlast   = 1'b1;
      mem_axi4.wvalid  = 1'b1;
      do @(posedge clk_i); while (!mem_axi4.wready);
      @(negedge clk_i);
      mem_axi4.wvalid = 1'b0;
      mem_axi4.wlast  = 1'b0;
      mem_axi4.bready = 1'b1;
      do @(posedge clk_i); while (!mem_axi4.bvalid);
      if (mem_axi4.bresp != response) begin
        $fatal(1, "single write response=%0d expected=%0d", mem_axi4.bresp, response);
      end
      @(negedge clk_i);
      mem_axi4.bready = 1'b0;
    end
  endtask

  task automatic write_missing_last(input logic [31:0] address, input logic [31:0] data);
    begin
      @(negedge clk_i);
      mem_axi4.awaddr  = address;
      mem_axi4.awlen   = 8'd0;
      mem_axi4.awsize  = `AXI4_BURST_SIZE_4BYTES;
      mem_axi4.awburst = `AXI4_BURST_TYPE_INCR;
      mem_axi4.awvalid = 1'b1;
      do @(posedge clk_i); while (!mem_axi4.awready);
      @(negedge clk_i);
      mem_axi4.awvalid = 1'b0;
      mem_axi4.wdata   = data;
      mem_axi4.wstrb   = 4'hF;
      mem_axi4.wlast   = 1'b0;
      mem_axi4.wvalid  = 1'b1;
      do @(posedge clk_i); while (!mem_axi4.wready);
      @(negedge clk_i);
      mem_axi4.wvalid = 1'b0;
      mem_axi4.bready = 1'b1;
      do @(posedge clk_i); while (!mem_axi4.bvalid);
      if (mem_axi4.bresp != `AXI4_RESP_SLAVE_ERROR) begin
        $fatal(1, "missing WLAST did not return SLVERR");
      end
      @(negedge clk_i);
      mem_axi4.bready = 1'b0;
    end
  endtask

  task automatic read_single(input logic [31:0] address, input logic [2:0] size,
                             input logic [31:0] expected, input logic [1:0] response);
    begin
      read_burst(address, 8'd0, size, `AXI4_BURST_TYPE_INCR, expected, response,
                 response == `AXI4_RESP_OKAY, 1'b0);
    end
  endtask

  task automatic apb_read(input logic [11:0] offset, input logic [31:0] expected);
    begin
      @(negedge clk_i);
      cfg_apb4.paddr   = {20'd0, offset};
      cfg_apb4.psel    = 1'b1;
      cfg_apb4.penable = 1'b0;
      @(negedge clk_i);
      cfg_apb4.penable = 1'b1;
      do @(posedge clk_i); while (!cfg_apb4.pready);
      s_apb_read_data = cfg_apb4.prdata;
      if (cfg_apb4.pslverr || (s_apb_read_data !== expected)) begin
        $fatal(1, "APB offset=%03x data=%08x expected=%08x error=%0b", offset, s_apb_read_data,
               expected, cfg_apb4.pslverr);
      end
      @(negedge clk_i);
      cfg_apb4.psel    = 1'b0;
      cfg_apb4.penable = 1'b0;
    end
  endtask

  task automatic apb_error(input logic [11:0] offset, input logic write_access);
    begin
      @(negedge clk_i);
      cfg_apb4.paddr   = {20'd0, offset};
      cfg_apb4.psel    = 1'b1;
      cfg_apb4.penable = 1'b0;
      cfg_apb4.pwrite  = write_access;
      cfg_apb4.pwdata  = 32'hFFFF_FFFF;
      cfg_apb4.pstrb   = 4'hF;
      @(negedge clk_i);
      cfg_apb4.penable = 1'b1;
      do @(posedge clk_i); while (!cfg_apb4.pready);
      if (!cfg_apb4.pslverr) begin
        $fatal(1, "APB illegal access offset=%03x write=%0b did not return PSLVERR", offset,
               write_access);
      end
      @(negedge clk_i);
      cfg_apb4.psel    = 1'b0;
      cfg_apb4.penable = 1'b0;
      cfg_apb4.pwrite  = 1'b0;
      cfg_apb4.pwdata  = '0;
      cfg_apb4.pstrb   = '0;
    end
  endtask

  initial begin
    init_interfaces();
    repeat (3) @(posedge clk_i);
    @(negedge clk_i);
    rst_n_i       = 1'b1;
    perf_enable_i = 1'b1;

    apb_read(`APB4_ONCHIP_RAM__IP_ID, 32'h5352_414D);
    apb_read(`APB4_ONCHIP_RAM__IP_VERSION, 32'h0001_0000);
    apb_read(`APB4_ONCHIP_RAM__MEMORY_BYTES, 32'(CapacityKiB * 1024));
    apb_read(`APB4_ONCHIP_RAM__BANK_COUNT, 32'(CapacityKiB / 4));
    apb_read(`APB4_ONCHIP_RAM__BANK_BYTES, 32'd4096);
    apb_error(`APB4_ONCHIP_RAM__IP_ID, 1'b1);
    apb_error(12'h018, 1'b0);
    apb_error(12'h001, 1'b0);

    write_burst(SramEnd - 32'd63, 8'd15, `AXI4_BURST_SIZE_4BYTES, `AXI4_BURST_TYPE_INCR,
                32'hA500_0000, `AXI4_RESP_OKAY);
    read_burst(SramEnd - 32'd63, 8'd15, `AXI4_BURST_SIZE_4BYTES, `AXI4_BURST_TYPE_INCR,
               32'hA500_0000, `AXI4_RESP_OKAY, 1'b1, 1'b1);

    for (int bank = 0; bank < (CapacityKiB / 4); bank++) begin
      write_single(SramBase + 32'(bank * 4096), `AXI4_BURST_SIZE_4BYTES, 32'hB000_0000 + bank, 4'hF,
                   `AXI4_RESP_OKAY);
      read_single(SramBase + 32'(bank * 4096), `AXI4_BURST_SIZE_4BYTES, 32'hB000_0000 + bank,
                  `AXI4_RESP_OKAY);
    end

    write_single(SramBase + 32'h100, `AXI4_BURST_SIZE_4BYTES, 32'h1122_3344, 4'hF, `AXI4_RESP_OKAY);
    write_single(SramBase + 32'h101, `AXI4_BURST_SIZE_1BYTE, 32'h0000_AA00, 4'b0010,
                 `AXI4_RESP_OKAY);
    write_single(SramBase + 32'h102, `AXI4_BURST_SIZE_2BYTES, 32'hBEEF_0000, 4'b1100,
                 `AXI4_RESP_OKAY);
    read_single(SramBase + 32'h100, `AXI4_BURST_SIZE_4BYTES, 32'hBEEF_AA44, `AXI4_RESP_OKAY);

    write_burst(SramBase + 32'h200, 8'd3, `AXI4_BURST_SIZE_4BYTES, `AXI4_BURST_TYPE_FIXED,
                32'hCAFE_0000, `AXI4_RESP_OKAY);
    read_single(SramBase + 32'h200, `AXI4_BURST_SIZE_4BYTES, 32'hCAFE_0003, `AXI4_RESP_OKAY);

    write_burst(SramBase + 32'h248, 8'd3, `AXI4_BURST_SIZE_4BYTES, `AXI4_BURST_TYPE_WRAP,
                32'hFACE_0000, `AXI4_RESP_OKAY);
    read_burst(SramBase + 32'h248, 8'd3, `AXI4_BURST_SIZE_4BYTES, `AXI4_BURST_TYPE_WRAP,
               32'hFACE_0000, `AXI4_RESP_OKAY, 1'b1, 1'b0);

    read_single(SramEnd + 1'b1, `AXI4_BURST_SIZE_4BYTES, 32'd0, `AXI4_RESP_DECODE_ERROR);
    read_single(SramBase + 32'd2, `AXI4_BURST_SIZE_4BYTES, 32'd0, `AXI4_RESP_SLAVE_ERROR);
    write_single(SramBase + 32'h100, `AXI4_BURST_SIZE_4BYTES, 32'hFFFF_FFFF, 4'b0000,
                 `AXI4_RESP_OKAY);
    write_missing_last(SramBase + 32'h100, 32'hDEAD_BEEF);
    write_single(SramBase + 32'h100, `AXI4_BURST_SIZE_1BYTE, 32'h0000_5500, 4'b0010,
                 `AXI4_RESP_SLAVE_ERROR);
    read_single(SramBase + 32'h100, `AXI4_BURST_SIZE_4BYTES, 32'hBEEF_AA44, `AXI4_RESP_OKAY);

    @(negedge clk_i);
    mem_axi4.araddr  = SramBase;
    mem_axi4.awaddr  = SramBase + 32'd4;
    mem_axi4.arvalid = 1'b1;
    mem_axi4.awvalid = 1'b1;
    @(posedge clk_i);
    if (!mem_axi4.arready || mem_axi4.awready) begin
      $fatal(1, "simultaneous AR/AW did not select the read channel");
    end
    @(negedge clk_i);
    mem_axi4.arvalid = 1'b0;
    mem_axi4.awvalid = 1'b0;
    mem_axi4.rready  = 1'b1;
    do @(posedge clk_i); while (!mem_axi4.rvalid);
    @(negedge clk_i);
    mem_axi4.rready = 1'b0;

    apb_read(`APB4_ONCHIP_RAM__PERF_READ_REQUESTS, 32'(CapacityKiB / 4 + 8));
    if (u_dut.s_perf_write_requests_q == 32'd0 || u_dut.s_perf_read_beats_q == 32'd0 ||
        u_dut.s_perf_write_beats_q == 32'd0 || u_dut.s_perf_err_resps_q != 32'd4) begin
      $fatal(1, "performance counters did not record the directed traffic");
    end

    $display("on-chip SRAM AXI4 test passed capacity_kib=%0d", CapacityKiB);
    $finish;
  end
endmodule
