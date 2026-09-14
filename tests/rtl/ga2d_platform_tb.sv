// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`timescale 1ns / 1ps

module ga2d_platform_idle_target (
    axi4_if.slave axi4
);
  assign axi4.awready = 1'b1;
  assign axi4.wready  = 1'b1;
  assign axi4.bid     = '0;
  assign axi4.bresp   = 2'b00;
  assign axi4.buser   = '0;
  assign axi4.bvalid  = 1'b0;
  assign axi4.arready = 1'b1;
  assign axi4.rid     = '0;
  assign axi4.rdata   = '0;
  assign axi4.rresp   = 2'b00;
  assign axi4.rlast   = 1'b1;
  assign axi4.ruser   = '0;
  assign axi4.rvalid  = 1'b0;
endmodule

module ga2d_platform_sram_target (
    input  logic               clk_i,
    input  logic               rst_n_i,
    input  logic               hold_ar_i,
    input  logic               hold_response_i,
    output logic         [6:0] last_arid_o,
    output logic               saw_ga2d_o,
    output logic               saw_legacy_o,
    output logic               saw_ga2d_write_o,
           axi4_if.slave       axi4
);
  logic       read_pending_q;
  logic [6:0] read_id_q;
  logic       read_valid_q;
  logic       write_address_pending_q;
  logic       write_data_pending_q;
  logic [6:0] write_id_q;
  logic       write_valid_q;

  assign axi4.awready = !write_address_pending_q && !write_valid_q;
  assign axi4.wready  = write_address_pending_q && !write_data_pending_q && !write_valid_q;
  assign axi4.bid     = write_id_q;
  assign axi4.bresp   = 2'b00;
  assign axi4.buser   = '0;
  assign axi4.bvalid  = write_valid_q;
  assign axi4.arready = !hold_ar_i && !read_pending_q;
  assign axi4.rid     = read_id_q;
  assign axi4.rdata   = 64'hA5A5_0000_0000_0000 | read_id_q;
  assign axi4.rresp   = 2'b00;
  assign axi4.rlast   = 1'b1;
  assign axi4.ruser   = '0;
  assign axi4.rvalid  = read_valid_q;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      read_pending_q          <= 1'b0;
      read_id_q               <= '0;
      read_valid_q            <= 1'b0;
      write_address_pending_q <= 1'b0;
      write_data_pending_q    <= 1'b0;
      write_id_q              <= '0;
      write_valid_q           <= 1'b0;
      last_arid_o             <= '0;
      saw_ga2d_o              <= 1'b0;
      saw_legacy_o            <= 1'b0;
      saw_ga2d_write_o        <= 1'b0;
    end else begin
      if (axi4.awvalid && axi4.awready) begin
        write_address_pending_q <= 1'b1;
        write_id_q              <= axi4.awid;
        if (axi4.awid == 7'h40) saw_ga2d_write_o <= 1'b1;
      end
      if (axi4.wvalid && axi4.wready) begin
        write_data_pending_q <= 1'b1;
      end
      if (write_address_pending_q && (write_data_pending_q || (axi4.wvalid && axi4.wready))) begin
        write_valid_q <= 1'b1;
      end
      if (write_valid_q && axi4.bready) begin
        write_address_pending_q <= 1'b0;
        write_data_pending_q    <= 1'b0;
        write_valid_q           <= 1'b0;
      end
      if (axi4.arvalid && axi4.arready) begin
        read_pending_q <= 1'b1;
        read_id_q      <= axi4.arid;
        last_arid_o    <= axi4.arid;
        if (axi4.arid == 7'h40) saw_ga2d_o <= 1'b1;
        if (axi4.arid == 7'h08) saw_legacy_o <= 1'b1;
      end
      if (read_pending_q && !hold_response_i) begin
        read_valid_q <= 1'b1;
        if (read_valid_q && axi4.rready) begin
          read_pending_q <= 1'b0;
          read_valid_q   <= 1'b0;
        end
      end
    end
  end
endmodule

module ga2d_platform_tb;
  logic        clk_lp_i = 1'b0;
  logic        clk_io_i = 1'b0;
  logic        clk_hp_i = 1'b0;
  logic        clk_mem_i = 1'b0;
  logic        rst_lp_n_i = 1'b0;
  logic        rst_io_n_i = 1'b0;
  logic        rst_hp_n_i = 1'b0;
  logic        rst_mem_n_i = 1'b0;
  logic        block_new_i = 1'b0;
  logic        recovery_i = 1'b0;
  logic        flush_i = 1'b0;
  logic [ 8:0] resource_block_i = '0;
  logic [ 1:0] mem_pad_mode_i = 2'd1;
  logic        ga2d_core_safe_idle_i = 1'b1;
  logic        ext_h_block_i = 1'b0;
  logic        sram_hold_ar_i = 1'b0;
  logic        sram_hold_response_i = 1'b0;
  logic [ 6:0] sram_last_arid;
  logic        sram_saw_ga2d;
  logic        sram_saw_legacy;
  logic        sram_saw_ga2d_write;
  logic        idle_o;
  logic        flush_busy_o;
  logic        ext_h_idle_o;
  logic [ 7:0] apu_bridge_epoch_o;
  logic        ga2d_source_stop_o;
  logic        ga2d_source_safe_idle_o;
  logic        ga2d_bridge_clear_busy_o;
  logic [ 7:0] ga2d_bridge_epoch_o;
  logic        ga2d_data_ready_o;
  logic [ 8:0] resource_idle_o;
  logic [ 8:0] resource_block_ack_o;
  logic [ 7:0] outstanding_read_o;
  logic [ 7:0] outstanding_write_o;
  logic        fault_valid_o;
  logic [ 3:0] fault_master_o;
  logic [ 2:0] fault_target_o;
  logic [31:0] fault_addr_o;
  logic        fault_write_o;
  logic [ 3:0] fault_reason_o;
  logic [ 7:0] epoch_before;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) hp_icache_axi4 (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) hp_dcache_axi4 (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) dma_axi4 (
      .aclk   (clk_io_i),
      .aresetn(rst_io_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) sdio0_axi4 (
      .aclk   (clk_io_i),
      .aresetn(rst_io_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) sdio1_axi4 (
      .aclk   (clk_io_i),
      .aresetn(rst_io_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) spisd_axi4 (
      .aclk   (clk_io_i),
      .aresetn(rst_io_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) usb2_axi4 (
      .aclk   (clk_io_i),
      .aresetn(rst_io_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) apu_axi4 (
      .aclk   (clk_io_i),
      .aresetn(rst_io_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) jpeg_axi4 (
      .aclk   (clk_io_i),
      .aresetn(rst_io_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) ga2d_axi4 (
      .aclk   (clk_io_i),
      .aresetn(rst_io_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) lp_data_axi4 (
      .aclk   (clk_lp_i),
      .aresetn(rst_lp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) ext_h_axi4 (
      .aclk   (clk_io_i),
      .aresetn(rst_io_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (7),
      .USER_WIDTH(1)
  ) sram_gateway_axi4 (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) sdram_gateway_axi4 (
      .aclk   (clk_mem_i),
      .aresetn(rst_mem_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) qpi_gateway_axi4 (
      .aclk   (clk_mem_i),
      .aresetn(rst_mem_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) opi_gateway_axi4 (
      .aclk   (clk_mem_i),
      .aresetn(rst_mem_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) xpi_gateway_axi4 (
      .aclk   (clk_mem_i),
      .aresetn(rst_mem_n_i)
  );
  apb4_if fabric_monitor_apb4 (
      .pclk   (clk_hp_i),
      .presetn(rst_hp_n_i)
  );

  always #5 clk_lp_i = ~clk_lp_i;
  always #7 clk_io_i = ~clk_io_i;
  always #11 clk_hp_i = ~clk_hp_i;
  always #13 clk_mem_i = ~clk_mem_i;

  axi4_master_idle u_hp_icache_idle (.axi4(hp_icache_axi4));
  axi4_master_idle u_dma_idle (.axi4(dma_axi4));
  axi4_master_idle u_sdio0_idle (.axi4(sdio0_axi4));
  axi4_master_idle u_sdio1_idle (.axi4(sdio1_axi4));
  axi4_master_idle u_spisd_idle (.axi4(spisd_axi4));
  axi4_master_idle u_usb2_idle (.axi4(usb2_axi4));
  axi4_master_idle u_apu_idle (.axi4(apu_axi4));
  axi4_master_idle u_jpeg_idle (.axi4(jpeg_axi4));
  axi4_master_idle u_ext_h_idle (.axi4(ext_h_axi4));
  ga2d_platform_sram_target u_sram_target (
      .clk_i           (clk_hp_i),
      .rst_n_i         (rst_hp_n_i),
      .hold_ar_i       (sram_hold_ar_i),
      .hold_response_i (sram_hold_response_i),
      .last_arid_o     (sram_last_arid),
      .saw_ga2d_o      (sram_saw_ga2d),
      .saw_legacy_o    (sram_saw_legacy),
      .saw_ga2d_write_o(sram_saw_ga2d_write),
      .axi4            (sram_gateway_axi4)
  );
  ga2d_platform_idle_target u_sdram_target (.axi4(sdram_gateway_axi4));
  ga2d_platform_idle_target u_qpi_target (.axi4(qpi_gateway_axi4));
  ga2d_platform_idle_target u_opi_target (.axi4(opi_gateway_axi4));
  ga2d_platform_idle_target u_xpi_target (.axi4(xpi_gateway_axi4));

  soc_data_plane u_dut (
      .clk_lp_i                (clk_lp_i),
      .rst_lp_n_i              (rst_lp_n_i),
      .clk_io_i                (clk_io_i),
      .rst_io_n_i              (rst_io_n_i),
      .clk_hp_i                (clk_hp_i),
      .rst_hp_n_i              (rst_hp_n_i),
      .clk_mem_i               (clk_mem_i),
      .rst_mem_n_i             (rst_mem_n_i),
      .block_new_i             (block_new_i),
      .recovery_i              (recovery_i),
      .flush_i                 (flush_i),
      .resource_block_i        (resource_block_i),
      .mem_pad_mode_i          (mem_pad_mode_i),
      .ga2d_core_safe_idle_i   (ga2d_core_safe_idle_i),
      .ext_h_block_i           (ext_h_block_i),
      .ext_h_read_base_i       (32'h3000_0000),
      .ext_h_read_limit_i      (32'h4FFF_FFFF),
      .ext_h_write_base_i      (32'h3000_0000),
      .ext_h_write_limit_i     (32'h4FFF_FFFF),
      .hp_icache_axi4          (hp_icache_axi4),
      .hp_dcache_axi4          (hp_dcache_axi4),
      .dma_axi4                (dma_axi4),
      .sdio0_axi4              (sdio0_axi4),
      .sdio1_axi4              (sdio1_axi4),
      .spisd_axi4              (spisd_axi4),
      .usb2_axi4               (usb2_axi4),
      .apu_axi4                (apu_axi4),
      .jpeg_axi4               (jpeg_axi4),
      .ga2d_axi4               (ga2d_axi4),
      .lp_data_axi4            (lp_data_axi4),
      .ext_h_axi4              (ext_h_axi4),
      .sram_gateway_axi4       (sram_gateway_axi4),
      .sdram_gateway_axi4      (sdram_gateway_axi4),
      .qpi_gateway_axi4        (qpi_gateway_axi4),
      .opi_gateway_axi4        (opi_gateway_axi4),
      .xpi_gateway_axi4        (xpi_gateway_axi4),
      .fabric_monitor_apb4     (fabric_monitor_apb4),
      .idle_o                  (idle_o),
      .flush_busy_o            (flush_busy_o),
      .ext_h_idle_o            (ext_h_idle_o),
      .apu_bridge_epoch_o      (apu_bridge_epoch_o),
      .ga2d_source_stop_o      (ga2d_source_stop_o),
      .ga2d_source_safe_idle_o (ga2d_source_safe_idle_o),
      .ga2d_bridge_clear_busy_o(ga2d_bridge_clear_busy_o),
      .ga2d_bridge_epoch_o     (ga2d_bridge_epoch_o),
      .ga2d_data_ready_o       (ga2d_data_ready_o),
      .resource_idle_o         (resource_idle_o),
      .resource_block_ack_o    (resource_block_ack_o),
      .outstanding_read_o      (outstanding_read_o),
      .outstanding_write_o     (outstanding_write_o),
      .fault_valid_o           (fault_valid_o),
      .fault_ready_i           (1'b1),
      .fault_master_o          (fault_master_o),
      .fault_target_o          (fault_target_o),
      .fault_addr_o            (fault_addr_o),
      .fault_write_o           (fault_write_o),
      .fault_reason_o          (fault_reason_o)
  );

  task automatic issue_ga2d_read(input logic [2:0] id, input logic [31:0] address);
    begin
      @(negedge clk_io_i);
      ga2d_axi4.arid     = id;
      ga2d_axi4.araddr   = address;
      ga2d_axi4.arlen    = '0;
      ga2d_axi4.arsize   = 3'd3;
      ga2d_axi4.arburst  = 2'b01;
      ga2d_axi4.arlock   = 1'b0;
      ga2d_axi4.arcache  = '0;
      ga2d_axi4.arprot   = '0;
      ga2d_axi4.arqos    = 4'hF;
      ga2d_axi4.arregion = '0;
      ga2d_axi4.aruser   = '0;
      ga2d_axi4.arvalid  = 1'b1;
      do @(posedge clk_io_i); while (!ga2d_axi4.arready);
      @(negedge clk_io_i);
      ga2d_axi4.arvalid = 1'b0;
    end
  endtask

  task automatic expect_ga2d_read(input logic [2:0] id);
    begin
      wait (ga2d_axi4.rvalid);
      if ((ga2d_axi4.rid != id) || (ga2d_axi4.rresp != 2'b00)) begin
        $fatal(1, "GA2D response did not preserve the local source ID");
      end
    end
  endtask

  task automatic issue_ga2d_write(input logic [2:0] id, input logic [31:0] address,
                                  input logic [63:0] data);
    begin
      @(negedge clk_io_i);
      ga2d_axi4.awid     = id;
      ga2d_axi4.awaddr   = address;
      ga2d_axi4.awlen    = '0;
      ga2d_axi4.awsize   = 3'd3;
      ga2d_axi4.awburst  = 2'b01;
      ga2d_axi4.awlock   = 1'b0;
      ga2d_axi4.awcache  = '0;
      ga2d_axi4.awprot   = '0;
      ga2d_axi4.awqos    = 4'hF;
      ga2d_axi4.awregion = '0;
      ga2d_axi4.awuser   = '0;
      ga2d_axi4.awvalid  = 1'b1;
      do @(posedge clk_io_i); while (!ga2d_axi4.awready);
      @(negedge clk_io_i);
      ga2d_axi4.awvalid = 1'b0;
      ga2d_axi4.wdata   = data;
      ga2d_axi4.wstrb   = '1;
      ga2d_axi4.wlast   = 1'b1;
      ga2d_axi4.wuser   = '0;
      ga2d_axi4.wvalid  = 1'b1;
      do @(posedge clk_io_i); while (!ga2d_axi4.wready);
      @(negedge clk_io_i);
      ga2d_axi4.wvalid = 1'b0;
    end
  endtask

  task automatic expect_ga2d_write(input logic [2:0] id);
    begin
      wait (ga2d_axi4.bvalid);
      if ((ga2d_axi4.bid != id) || (ga2d_axi4.bresp != 2'b00)) begin
        $fatal(1, "GA2D write response did not preserve the local source ID");
      end
    end
  endtask

  task automatic issue_legacy_read(input logic [2:0] id, input logic [31:0] address);
    begin
      @(negedge clk_hp_i);
      hp_dcache_axi4.arid     = id;
      hp_dcache_axi4.araddr   = address;
      hp_dcache_axi4.arlen    = '0;
      hp_dcache_axi4.arsize   = 3'd3;
      hp_dcache_axi4.arburst  = 2'b01;
      hp_dcache_axi4.arlock   = 1'b0;
      hp_dcache_axi4.arcache  = '0;
      hp_dcache_axi4.arprot   = '0;
      hp_dcache_axi4.arqos    = '0;
      hp_dcache_axi4.arregion = '0;
      hp_dcache_axi4.aruser   = '0;
      hp_dcache_axi4.arvalid  = 1'b1;
      do @(posedge clk_hp_i); while (!hp_dcache_axi4.arready);
      @(negedge clk_hp_i);
      hp_dcache_axi4.arvalid = 1'b0;
    end
  endtask

  task automatic expect_legacy_read(input logic [2:0] id);
    begin
      wait (hp_dcache_axi4.rvalid);
      if ((hp_dcache_axi4.rid != id) || (hp_dcache_axi4.rresp != 2'b00)) begin
        $fatal(1, "legacy response did not preserve its source ID");
      end
    end
  endtask

  task automatic issue_lp_read(input logic id, input logic [31:0] address);
    begin
      @(negedge clk_lp_i);
      lp_data_axi4.arid     = id;
      lp_data_axi4.araddr   = address;
      lp_data_axi4.arlen    = '0;
      lp_data_axi4.arsize   = 3'd2;
      lp_data_axi4.arburst  = 2'b01;
      lp_data_axi4.arlock   = 1'b0;
      lp_data_axi4.arcache  = '0;
      lp_data_axi4.arprot   = '0;
      lp_data_axi4.arqos    = '0;
      lp_data_axi4.arregion = '0;
      lp_data_axi4.aruser   = '0;
      lp_data_axi4.arvalid  = 1'b1;
      do @(posedge clk_lp_i); while (!lp_data_axi4.arready);
      @(negedge clk_lp_i);
      lp_data_axi4.arvalid = 1'b0;
    end
  endtask

  task automatic expect_lp_read(input logic id);
    begin
      wait (lp_data_axi4.rvalid);
      if ((lp_data_axi4.rid != id) || (lp_data_axi4.rresp != 2'b00)) begin
        $fatal(1, "LP response did not survive the HP lifecycle flush");
      end
    end
  endtask

  task automatic wait_for_data_ready;
    begin
      wait (ga2d_data_ready_o && !ga2d_source_stop_o);
    end
  endtask

  initial begin
    lp_data_axi4.awid           = '0;
    lp_data_axi4.awaddr         = '0;
    lp_data_axi4.awlen          = '0;
    lp_data_axi4.awsize         = 3'd2;
    lp_data_axi4.awburst        = 2'b01;
    lp_data_axi4.awlock         = 1'b0;
    lp_data_axi4.awcache        = '0;
    lp_data_axi4.awprot         = '0;
    lp_data_axi4.awqos          = '0;
    lp_data_axi4.awregion       = '0;
    lp_data_axi4.awuser         = '0;
    lp_data_axi4.awvalid        = 1'b0;
    lp_data_axi4.wdata          = '0;
    lp_data_axi4.wstrb          = '0;
    lp_data_axi4.wlast          = 1'b1;
    lp_data_axi4.wuser          = '0;
    lp_data_axi4.wvalid         = 1'b0;
    lp_data_axi4.bready         = 1'b1;
    lp_data_axi4.arid           = '0;
    lp_data_axi4.araddr         = '0;
    lp_data_axi4.arlen          = '0;
    lp_data_axi4.arsize         = 3'd2;
    lp_data_axi4.arburst        = 2'b01;
    lp_data_axi4.arlock         = 1'b0;
    lp_data_axi4.arcache        = '0;
    lp_data_axi4.arprot         = '0;
    lp_data_axi4.arqos          = '0;
    lp_data_axi4.arregion       = '0;
    lp_data_axi4.aruser         = '0;
    lp_data_axi4.arvalid        = 1'b0;
    lp_data_axi4.rready         = 1'b1;

    ga2d_axi4.awid              = '0;
    ga2d_axi4.awaddr            = '0;
    ga2d_axi4.awlen             = '0;
    ga2d_axi4.awsize            = 3'd3;
    ga2d_axi4.awburst           = 2'b01;
    ga2d_axi4.awlock            = 1'b0;
    ga2d_axi4.awcache           = '0;
    ga2d_axi4.awprot            = '0;
    ga2d_axi4.awqos             = '0;
    ga2d_axi4.awregion          = '0;
    ga2d_axi4.awuser            = '0;
    ga2d_axi4.awvalid           = 1'b0;
    ga2d_axi4.wdata             = '0;
    ga2d_axi4.wstrb             = '0;
    ga2d_axi4.wlast             = 1'b1;
    ga2d_axi4.wuser             = '0;
    ga2d_axi4.wvalid            = 1'b0;
    ga2d_axi4.bready            = 1'b1;
    ga2d_axi4.arid              = '0;
    ga2d_axi4.araddr            = '0;
    ga2d_axi4.arlen             = '0;
    ga2d_axi4.arsize            = 3'd3;
    ga2d_axi4.arburst           = 2'b01;
    ga2d_axi4.arlock            = 1'b0;
    ga2d_axi4.arcache           = '0;
    ga2d_axi4.arprot            = '0;
    ga2d_axi4.arqos             = '0;
    ga2d_axi4.arregion          = '0;
    ga2d_axi4.aruser            = '0;
    ga2d_axi4.arvalid           = 1'b0;
    ga2d_axi4.rready            = 1'b1;

    hp_dcache_axi4.awid         = '0;
    hp_dcache_axi4.awaddr       = '0;
    hp_dcache_axi4.awlen        = '0;
    hp_dcache_axi4.awsize       = 3'd3;
    hp_dcache_axi4.awburst      = 2'b01;
    hp_dcache_axi4.awlock       = 1'b0;
    hp_dcache_axi4.awcache      = '0;
    hp_dcache_axi4.awprot       = '0;
    hp_dcache_axi4.awqos        = '0;
    hp_dcache_axi4.awregion     = '0;
    hp_dcache_axi4.awuser       = '0;
    hp_dcache_axi4.awvalid      = 1'b0;
    hp_dcache_axi4.wdata        = '0;
    hp_dcache_axi4.wstrb        = '0;
    hp_dcache_axi4.wlast        = 1'b1;
    hp_dcache_axi4.wuser        = '0;
    hp_dcache_axi4.wvalid       = 1'b0;
    hp_dcache_axi4.bready       = 1'b1;
    hp_dcache_axi4.arid         = '0;
    hp_dcache_axi4.araddr       = '0;
    hp_dcache_axi4.arlen        = '0;
    hp_dcache_axi4.arsize       = 3'd3;
    hp_dcache_axi4.arburst      = 2'b01;
    hp_dcache_axi4.arlock       = 1'b0;
    hp_dcache_axi4.arcache      = '0;
    hp_dcache_axi4.arprot       = '0;
    hp_dcache_axi4.arqos        = '0;
    hp_dcache_axi4.arregion     = '0;
    hp_dcache_axi4.aruser       = '0;
    hp_dcache_axi4.arvalid      = 1'b0;
    hp_dcache_axi4.rready       = 1'b1;

    fabric_monitor_apb4.paddr   = '0;
    fabric_monitor_apb4.pprot   = '0;
    fabric_monitor_apb4.psel    = 1'b0;
    fabric_monitor_apb4.penable = 1'b0;
    fabric_monitor_apb4.pwrite  = 1'b0;
    fabric_monitor_apb4.pwdata  = '0;
    fabric_monitor_apb4.pstrb   = '0;

    repeat (3) @(posedge clk_io_i);
    rst_lp_n_i  = 1'b1;
    rst_io_n_i  = 1'b1;
    rst_hp_n_i  = 1'b1;
    rst_mem_n_i = 1'b1;
    wait_for_data_ready();

    // A core that has not established a known-safe idle state cannot hand the
    // resource to HP even when the address gate itself is empty.
    @(negedge clk_io_i);
    ga2d_core_safe_idle_i = 1'b0;
    resource_block_i[8]   = 1'b1;
    repeat (5) @(posedge clk_hp_i);
    if (ga2d_source_safe_idle_o || resource_block_ack_o[8] || resource_idle_o[8]) begin
      $fatal(1, "unsafe GA2D core idle state allowed resource-8 handoff");
    end
    @(negedge clk_io_i);
    ga2d_core_safe_idle_i = 1'b1;
    wait (resource_block_ack_o[8]);
    @(negedge clk_io_i);
    resource_block_i[8] = 1'b0;
    wait_for_data_ready();

    fork
      issue_ga2d_read(3'd0, 32'h3000_0040);
      expect_ga2d_read(3'd0);
      issue_legacy_read(3'd0, 32'h3000_0080);
      expect_legacy_read(3'd0);
    join
    if (!sram_saw_ga2d || !sram_saw_legacy) begin
      $fatal(1, "mixed legacy and GA2D IDs did not reach distinct global IDs");
    end

    fork
      issue_ga2d_write(3'd0, 32'h3000_00C0, 64'h0123_4567_89AB_CDEF);
      expect_ga2d_write(3'd0);
    join
    if (!sram_saw_ga2d_write) begin
      $fatal(1, "GA2D write did not preserve global ID 7'h40");
    end

    wait (!flush_busy_o);
    block_new_i = 1'b1;
    repeat (2) @(posedge clk_hp_i);
    issue_lp_read(1'b0, 32'h3000_0180);
    repeat (2) @(posedge clk_hp_i);
    @(negedge clk_hp_i);
    flush_i = 1'b1;
    repeat (4) @(posedge clk_lp_i);
    repeat (4) @(posedge clk_hp_i);
    @(negedge clk_hp_i);
    flush_i = 1'b0;
    wait (!flush_busy_o);
    block_new_i = 1'b0;
    expect_lp_read(1'b0);
    if (sram_last_arid != 7'h28) begin
      $fatal(1, "HP lifecycle flush discarded the queued LP request");
    end

    wait (ga2d_source_safe_idle_o);
    @(negedge clk_io_i);
    resource_block_i[8] = 1'b1;
    ga2d_axi4.wdata     = 64'hCAFE_BABE_0123_4567;
    ga2d_axi4.wstrb     = '1;
    ga2d_axi4.wlast     = 1'b1;
    ga2d_axi4.wuser     = '0;
    ga2d_axi4.wvalid    = 1'b1;
    repeat (2) @(posedge clk_io_i);
    #1;
    if (ga2d_source_stop_o || ga2d_source_safe_idle_o || resource_block_ack_o[8] ||
        ga2d_axi4.wready) begin
      $fatal(1, "resource block accepted or acknowledged W-before-AW traffic");
    end
    @(negedge clk_io_i);
    ga2d_axi4.awid     = 3'd3;
    ga2d_axi4.awaddr   = 32'h3000_0120;
    ga2d_axi4.awlen    = '0;
    ga2d_axi4.awsize   = 3'd3;
    ga2d_axi4.awburst  = 2'b01;
    ga2d_axi4.awlock   = 1'b0;
    ga2d_axi4.awcache  = '0;
    ga2d_axi4.awprot   = '0;
    ga2d_axi4.awqos    = '0;
    ga2d_axi4.awregion = '0;
    ga2d_axi4.awuser   = '0;
    ga2d_axi4.awvalid  = 1'b1;
    do @(posedge clk_io_i); while (!ga2d_axi4.awready);
    #1;
    if (!ga2d_source_stop_o) begin
      $fatal(1, "resource block did not close after the W-before-AW address handshake");
    end
    if (!ga2d_axi4.wready) begin
      $fatal(1, "W-before-AW write data was not accepted with its address");
    end
    @(negedge clk_io_i);
    ga2d_axi4.awvalid = 1'b0;
    ga2d_axi4.wvalid  = 1'b0;
    if (resource_block_ack_o[8]) begin
      $fatal(1, "resource block acknowledged before the W-before-AW response drained");
    end
    expect_ga2d_write(3'd3);
    wait (resource_block_ack_o[8]);
    if (!ga2d_source_safe_idle_o || !resource_idle_o[8] || ga2d_data_ready_o) begin
      $fatal(1, "W-before-AW resource stop did not reach qualified idle");
    end
    @(negedge clk_io_i);
    resource_block_i[8] = 1'b0;
    wait_for_data_ready();

    sram_hold_ar_i = 1'b1;
    @(negedge clk_io_i);
    resource_block_i[8] = 1'b1;
    ga2d_axi4.arid      = 3'd1;
    ga2d_axi4.araddr    = 32'h3000_0100;
    ga2d_axi4.arlen     = '0;
    ga2d_axi4.arsize    = 3'd3;
    ga2d_axi4.arburst   = 2'b01;
    ga2d_axi4.arlock    = 1'b0;
    ga2d_axi4.arcache   = '0;
    ga2d_axi4.arprot    = '0;
    ga2d_axi4.arqos     = '0;
    ga2d_axi4.arregion  = '0;
    ga2d_axi4.aruser    = '0;
    ga2d_axi4.arvalid   = 1'b1;
    do @(posedge clk_io_i); while (!ga2d_axi4.arready);
    #1;
    if (!ga2d_source_stop_o) begin
      $fatal(1, "resource stop did not close after the presented address entered transport");
    end
    @(negedge clk_io_i);
    ga2d_axi4.arvalid = 1'b0;
    wait (ga2d_source_stop_o);
    if (ga2d_source_safe_idle_o || resource_block_ack_o[8]) begin
      $fatal(1, "resource block acknowledged before the accepted read drained");
    end
    sram_hold_ar_i = 1'b0;
    fork
      expect_ga2d_read(3'd1);
      wait (resource_block_ack_o[8]);
    join
    if (!ga2d_source_safe_idle_o || !resource_idle_o[8] || ga2d_data_ready_o) begin
      $fatal(1, "GA2D resource stop did not reach qualified idle");
    end
    @(negedge clk_io_i);
    resource_block_i[8] = 1'b0;
    wait_for_data_ready();

    sram_hold_response_i = 1'b1;
    issue_ga2d_read(3'd2, 32'h3000_0140);
    wait (sram_last_arid == 7'h42);
    epoch_before = ga2d_bridge_epoch_o;
    @(negedge clk_hp_i);
    flush_i              = 1'b1;
    sram_hold_response_i = 1'b0;
    repeat (4) @(posedge clk_io_i);
    if (ga2d_data_ready_o) begin
      $fatal(1, "GA2D data-ready remained asserted during a warm flush");
    end
    repeat (4) @(posedge clk_hp_i);
    @(negedge clk_hp_i);
    flush_i = 1'b0;
    wait (ga2d_bridge_epoch_o != epoch_before);
    repeat (4) @(posedge clk_io_i);
    if (ga2d_axi4.rvalid) begin
      $fatal(1, "late pre-flush response reached the GA2D source");
    end
    wait_for_data_ready();
    wait (!flush_busy_o);

    epoch_before = ga2d_bridge_epoch_o;
    @(negedge clk_hp_i);
    rst_hp_n_i = 1'b0;
    repeat (3) @(posedge clk_hp_i);
    if (ga2d_data_ready_o) begin
      $fatal(1, "GA2D data-ready remained asserted while HP reset was active");
    end
    @(negedge clk_hp_i);
    rst_hp_n_i = 1'b1;
    wait (ga2d_bridge_epoch_o != epoch_before);
    wait_for_data_ready();

    @(negedge clk_io_i);
    rst_io_n_i = 1'b0;
    repeat (3) @(posedge clk_io_i);
    if (ga2d_data_ready_o || !ga2d_source_stop_o) begin
      $fatal(1, "PCLK reset did not close the GA2D source path");
    end
    @(negedge clk_io_i);
    rst_io_n_i = 1'b1;
    wait_for_data_ready();

    $display("GA2D P2 bridge, ID7, lifecycle, flush, LP retention, and reset test passed");
    $finish;
  end

  initial begin
    #50000;
    $fatal(1, "GA2D platform test timed out");
  end
endmodule
