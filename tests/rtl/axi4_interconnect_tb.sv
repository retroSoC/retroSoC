`timescale 1ns / 1ps

`include "axi4_define.svh"
`include "rib_defs.svh"

module axi4_interconnect_tb;
  localparam int NumMasters = 5;
  localparam int NumTargets = 9;

  logic        clk_i = 1'b0;
  logic        rst_n_i = 1'b0;
  logic        fault_valid_o;
  logic [31:0] fault_addr_o;
  logic [ 3:0] fault_wstrb_o;
  logic        fault_reserved_o;
  logic        fault_access_o;
  logic [ 2:0] fault_master_o;
  logic [ 2:0] fault_code_o;
  logic        user_bus_idle_o;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) masters[NumMasters] (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) targets[NumTargets] (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

  axi4_interconnect #(
      .NumMasters(NumMasters),
      .NumTargets(NumTargets)
  ) u_dut (
      .clk_i                  (clk_i),
      .rst_n_i                (rst_n_i),
      .masters                (masters),
      .targets                (targets),
      .user_bus_enable_i      (1'b1),
      .user_bus_idle_o        (user_bus_idle_o),
      .perf_enable_i          (1'b0),
      .perf_clear_i           (1'b0),
      .fault_valid_o          (fault_valid_o),
      .fault_addr_o           (fault_addr_o),
      .fault_wstrb_o          (fault_wstrb_o),
      .fault_reserved_o       (fault_reserved_o),
      .fault_access_o         (fault_access_o),
      .fault_master_o         (fault_master_o),
      .fault_code_o           (fault_code_o),
      .perf_mgmt_wait_o       (),
      .perf_user_wait_o       (),
      .perf_dma_wait_o        (),
      .perf_sdio0_wait_o      (),
      .perf_sdio1_wait_o      (),
      .perf_apb4_periph_wait_o(),
      .perf_apb4_system_wait_o(),
      .perf_sdram_wait_o      (),
      .perf_psram_wait_o      (),
      .perf_flash_wait_o      (),
      .perf_opipsram_wait_o   ()
  );

  for (genvar target = 0; target < NumTargets; target++) begin : GEN_TARGETS
    localparam logic [1:0] Response =
        (target == 7) ? `AXI4_RESP_DECODE_ERROR :
        (target == 8) ? `AXI4_RESP_SLAVE_ERROR : `AXI4_RESP_OKAY;
    axi4_error_slave #(
        .Response(Response)
    ) u_target (
        .clk_i  (clk_i),
        .rst_n_i(rst_n_i),
        .axi4   (targets[target])
    );
  end

  `define INIT_MASTER(index)                                      \
  masters[index].awid     = '0;                                \
  masters[index].awaddr   = '0;                                \
  masters[index].awlen    = '0;                                \
  masters[index].awsize   = `AXI4_BURST_SIZE_4BYTES;           \
  masters[index].awburst  = `AXI4_BURST_TYPE_INCR;             \
  masters[index].awlock   = `AXI4_LOCK_NORM;                   \
  masters[index].awcache  = `AXI4_CACHE_NO_BUF;                \
  masters[index].awprot   = `AXI4_PROT_DATA;                   \
  masters[index].awqos    = `AXI4_QOS_NORMAL;                  \
  masters[index].awregion = `AXI4_REGION_NORMAL;               \
  masters[index].awuser   = '0;                                \
  masters[index].awvalid  = 1'b0;                              \
  masters[index].wdata    = '0;                                \
  masters[index].wstrb    = '0;                                \
  masters[index].wlast    = 1'b0;                              \
  masters[index].wuser    = '0;                                \
  masters[index].wvalid   = 1'b0;                              \
  masters[index].bready   = 1'b0;                              \
  masters[index].arid     = '0;                                \
  masters[index].araddr   = '0;                                \
  masters[index].arlen    = '0;                                \
  masters[index].arsize   = `AXI4_BURST_SIZE_4BYTES;           \
  masters[index].arburst  = `AXI4_BURST_TYPE_INCR;             \
  masters[index].arlock   = `AXI4_LOCK_NORM;                   \
  masters[index].arcache  = `AXI4_CACHE_NO_BUF;                \
  masters[index].arprot   = `AXI4_PROT_DATA;                   \
  masters[index].arqos    = `AXI4_QOS_NORMAL;                  \
  masters[index].arregion = `AXI4_REGION_NORMAL;               \
  masters[index].aruser   = '0;                                \
  masters[index].arvalid  = 1'b0;                              \
  masters[index].rready   = 1'b0;

  task automatic issue_mgmt_error_read(input logic [31:0] address, input logic [7:0] length,
                                       input logic [1:0] response, input logic [2:0] fault_code);
    integer beat;
    begin
      @(negedge clk_i);
      masters[0].araddr  = address;
      masters[0].arlen   = length;
      masters[0].arvalid = 1'b1;
      do @(posedge clk_i); while (!masters[0].arready);
      @(negedge clk_i);
      masters[0].arvalid = 1'b0;
      masters[0].rready  = 1'b1;
      beat               = 0;
      while (beat <= length) begin
        @(negedge clk_i);
        if (masters[0].rvalid) begin
          if ((masters[0].rresp != response) || (masters[0].rlast != (beat == int'(length)))) begin
            $fatal(1, "management error response mismatch on beat %0d", beat);
          end
          if ((beat == int'(length)) &&
              (!fault_valid_o || (fault_addr_o != address) || fault_access_o ||
               (fault_master_o != 3'd0) || (fault_code_o != fault_code))) begin
            $fatal(1, "management fault classification mismatch");
          end
          beat = beat + 1;
        end
      end
      @(negedge clk_i);
      masters[0].rready = 1'b0;
    end
  endtask

  task automatic issue_denied_user_write(input logic [31:0] address);
    begin
      @(negedge clk_i);
      masters[1].awaddr  = address;
      masters[1].awlen   = 8'd0;
      masters[1].awvalid = 1'b1;
      do @(posedge clk_i); while (!masters[1].awready);
      @(negedge clk_i);
      masters[1].awvalid = 1'b0;
      masters[1].wdata   = 32'hA5A5_5A5A;
      masters[1].wstrb   = 4'hF;
      masters[1].wlast   = 1'b1;
      masters[1].wvalid  = 1'b1;
      do @(posedge clk_i); while (!masters[1].wready);
      @(negedge clk_i);
      masters[1].wvalid = 1'b0;
      while (!masters[1].bvalid) @(negedge clk_i);
      masters[1].bready = 1'b1;
      #1;
      if ((masters[1].bresp != `AXI4_RESP_SLAVE_ERROR) || !fault_valid_o ||
          !fault_access_o || (fault_addr_o != address) || (fault_wstrb_o != 4'hF) ||
          (fault_master_o != 3'd1) || (fault_code_o != `RIB_RESP_PROTERR)) begin
        $fatal(1, "user access fault classification mismatch");
      end
      @(negedge clk_i);
      masters[1].bready = 1'b0;
    end
  endtask

  task automatic issue_management_with_idle_sdio;
    integer cycles;
    begin
      @(negedge clk_i);
      masters[0].araddr  = 32'h0000_0000;
      masters[0].arlen   = 8'd0;
      masters[0].arvalid = 1'b1;
      do @(posedge clk_i); while (!masters[0].arready);
      @(negedge clk_i);
      masters[0].arvalid = 1'b0;
      masters[0].rready  = 1'b1;
      cycles             = 0;
      while (!masters[0].rvalid && cycles < 100) begin
        if (masters[3].arvalid || masters[3].awvalid || masters[3].wvalid ||
            masters[4].arvalid || masters[4].awvalid || masters[4].wvalid) begin
          $fatal(1, "inactive SDIO master drove a request during management boot traffic");
        end
        @(negedge clk_i);
        cycles = cycles + 1;
      end
      if (cycles >= 100) $fatal(1, "idle SDIO masters blocked management boot traffic");
      if (masters[0].rresp != `AXI4_RESP_OKAY) begin
        $fatal(1, "management boot traffic received an unexpected response");
      end
      @(posedge clk_i);
      @(negedge clk_i);
      masters[0].rready = 1'b0;
    end
  endtask

  task automatic issue_contending_sdio_faults;
    integer cycles;
    begin
      @(negedge clk_i);
      masters[3].araddr  = 32'hA000_1000;
      masters[3].arlen   = 8'd0;
      masters[3].arvalid = 1'b1;
      masters[4].araddr  = 32'hA000_2000;
      masters[4].arlen   = 8'd0;
      masters[4].arvalid = 1'b1;
      do @(posedge clk_i); while (!(masters[3].arready && masters[4].arready));
      @(negedge clk_i);
      masters[3].arvalid = 1'b0;
      masters[4].arvalid = 1'b0;
      cycles             = 0;
      while (!masters[3].rvalid && !masters[4].rvalid && cycles < 100) begin
        @(negedge clk_i);
        cycles = cycles + 1;
      end
      if (cycles >= 100) $fatal(1, "SDIO master contention did not produce a response");
      if (masters[3].rvalid) begin
        masters[3].rready = 1'b1;
        #1;
        if ((masters[3].rresp != `AXI4_RESP_DECODE_ERROR) || !fault_valid_o ||
            (fault_master_o != 3'd3) || (fault_addr_o != 32'hA000_1000) ||
            (fault_code_o != `RIB_RESP_DECERR)) begin
          $fatal(1, "SDIO0 fault attribution mismatch");
        end
        @(posedge clk_i);
        @(negedge clk_i);
        masters[3].rready = 1'b0;
      end else begin
        masters[4].rready = 1'b1;
        #1;
        if ((masters[4].rresp != `AXI4_RESP_DECODE_ERROR) || !fault_valid_o ||
            (fault_master_o != 3'd4) || (fault_addr_o != 32'hA000_2000) ||
            (fault_code_o != `RIB_RESP_DECERR)) begin
          $fatal(1, "SDIO1 fault attribution mismatch");
        end
        @(posedge clk_i);
        @(negedge clk_i);
        masters[4].rready = 1'b0;
      end

      cycles = 0;
      while (!masters[3].rvalid && !masters[4].rvalid && cycles < 100) begin
        @(negedge clk_i);
        cycles = cycles + 1;
      end
      if (cycles >= 100) $fatal(1, "second SDIO master response was lost");
      if (masters[3].rvalid) begin
        masters[3].rready = 1'b1;
        #1;
        if ((masters[3].rresp != `AXI4_RESP_DECODE_ERROR) || !fault_valid_o ||
            (fault_master_o != 3'd3) || (fault_addr_o != 32'hA000_1000) ||
            (fault_code_o != `RIB_RESP_DECERR)) begin
          $fatal(1, "second SDIO0 fault attribution mismatch");
        end
        @(posedge clk_i);
        @(negedge clk_i);
        masters[3].rready = 1'b0;
      end else begin
        masters[4].rready = 1'b1;
        #1;
        if ((masters[4].rresp != `AXI4_RESP_DECODE_ERROR) || !fault_valid_o ||
            (fault_master_o != 3'd4) || (fault_addr_o != 32'hA000_2000) ||
            (fault_code_o != `RIB_RESP_DECERR)) begin
          $fatal(1, "second SDIO1 fault attribution mismatch");
        end
        @(posedge clk_i);
        @(negedge clk_i);
        masters[4].rready = 1'b0;
      end
    end
  endtask

  initial begin
    `INIT_MASTER(0)
    `INIT_MASTER(1)
    `INIT_MASTER(2)
    `INIT_MASTER(3)
    `INIT_MASTER(4)
    repeat (4) @(posedge clk_i);
    rst_n_i = 1'b1;

    issue_management_with_idle_sdio();
    issue_mgmt_error_read(32'hA000_0000, 8'd0, `AXI4_RESP_DECODE_ERROR, `RIB_RESP_DECERR);
    issue_mgmt_error_read(32'h3000_0000, 8'd16, `AXI4_RESP_SLAVE_ERROR, `RIB_RESP_BURSTERR);
    issue_denied_user_write(32'h1000_B000);
    issue_contending_sdio_faults();

    $display("AXI4 interconnect fault classification test passed");
    $finish;
  end

  `undef INIT_MASTER
endmodule
