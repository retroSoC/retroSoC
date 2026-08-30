// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module soc_data_plane (
    // verilog_format: off -- preserve the LP/HP and memory-target boundary columns
    input  logic       clk_lp_i,
    input  logic       rst_lp_n_i,
    input  logic       clk_io_i,
    input  logic       rst_io_n_i,
    input  logic       clk_hp_i,
    input  logic       rst_hp_n_i,
    input  logic       block_new_i,
    input  logic [1:0] mem_pad_mode_i,
    axi4_if.slave      hp_icache_axi4,
    axi4_if.slave      hp_dcache_axi4,
    axi4_if.slave      dma_axi4,
    axi4_if.slave      sdio0_axi4,
    axi4_if.slave      sdio1_axi4,
    axi4_if.slave      spisd_axi4,
    axi4_if.slave      usb2_axi4,
    axi4_if.slave      ext_h_axi4,
    axi4_if.master     sram_gateway_axi4,
    axi4_if.master     sdram_gateway_axi4,
    axi4_if.master     qpi_gateway_axi4,
    axi4_if.master     opi_gateway_axi4,
    axi4_if.master     xpi_gateway_axi4,
    output logic       idle_o
    // verilog_format: on
);
  localparam int unsigned NumIoMasters = 5;
  localparam int unsigned NumMemoryTargets = 5;

  logic       s_block_new_hp;
  logic [1:0] s_mem_pad_mode_hp;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (6),
      .USER_WIDTH(1)
  ) u_master_axi4[8] (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (6),
      .USER_WIDTH(1)
  ) u_target_axi4[6] (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (6),
      .USER_WIDTH(1)
  ) u_hp_icache_prefixed_axi4 (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (6),
      .USER_WIDTH(1)
  ) u_hp_dcache_prefixed_axi4 (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_io_lp_axi4[NumIoMasters] (
      .aclk   (clk_io_i),
      .aresetn(rst_io_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_io_hp_axi4[NumIoMasters] (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (3),
      .USER_WIDTH(1)
  ) u_ext_h_hp_axi4 (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(64),
      .ID_WIDTH  (6),
      .USER_WIDTH(1)
  ) u_ext_h_prefixed_axi4 (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_target_hp_axi4[NumMemoryTargets] (
      .aclk   (clk_hp_i),
      .aresetn(rst_hp_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_gateway_lp_axi4[NumMemoryTargets] (
      .aclk   (clk_lp_i),
      .aresetn(rst_lp_n_i)
  );

  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_block_new_sync (
      .clk_i  (clk_hp_i),
      .rst_n_i(rst_hp_n_i),
      .dat_i  (block_new_i),
      .dat_o  (s_block_new_hp)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(2)
  ) u_mem_pad_mode_sync (
      .clk_i  (clk_hp_i),
      .rst_n_i(rst_hp_n_i),
      .dat_i  (mem_pad_mode_i),
      .dat_o  (s_mem_pad_mode_hp)
  );

  axi4_id_prefix #(
      .MasterIndex(3'd0)
  ) u_hp_icache_prefix (
      .source(hp_icache_axi4),
      .sink  (u_hp_icache_prefixed_axi4)
  );
  axi4_connector u_hp_icache_connector (
      .source(u_hp_icache_prefixed_axi4),
      .sink  (u_master_axi4[0])
  );
  axi4_id_prefix #(
      .MasterIndex(3'd1)
  ) u_hp_dcache_prefix (
      .source(hp_dcache_axi4),
      .sink  (u_hp_dcache_prefixed_axi4)
  );
  axi4_connector u_hp_dcache_connector (
      .source(u_hp_dcache_prefixed_axi4),
      .sink  (u_master_axi4[1])
  );

  axi4_connector u_dma_source_connector (
      .source(dma_axi4),
      .sink  (u_io_lp_axi4[0])
  );
  axi4_connector u_sdio0_source_connector (
      .source(sdio0_axi4),
      .sink  (u_io_lp_axi4[1])
  );
  axi4_connector u_sdio1_source_connector (
      .source(sdio1_axi4),
      .sink  (u_io_lp_axi4[2])
  );
  axi4_connector u_spisd_source_connector (
      .source(spisd_axi4),
      .sink  (u_io_lp_axi4[3])
  );
  axi4_connector u_usb2_source_connector (
      .source(usb2_axi4),
      .sink  (u_io_lp_axi4[4])
  );

  for (genvar master = 0; master < NumIoMasters; master++) begin : gen_io_master
    axi4_async_bridge #(
        .DataWidth(32),
        .IdWidth  (1)
    ) u_io_cdc (
        .src_clk_i  (clk_io_i),
        .src_rst_n_i(rst_io_n_i),
        .dst_clk_i  (clk_hp_i),
        .dst_rst_n_i(rst_hp_n_i),
        .src_axi4   (u_io_lp_axi4[master]),
        .dst_axi4   (u_io_hp_axi4[master])
    );
    axi4_upsizer_32to64 #(
        .MasterIndex(3'(master + 2))
    ) u_io_upsizer (
        .clk_i  (clk_hp_i),
        .rst_n_i(rst_hp_n_i),
        .narrow (u_io_hp_axi4[master]),
        .wide   (u_master_axi4[master+2])
    );
  end

  axi4_async_bridge #(
      .DataWidth(64),
      .IdWidth  (3)
  ) u_ext_h_cdc (
      .src_clk_i  (clk_io_i),
      .src_rst_n_i(rst_io_n_i),
      .dst_clk_i  (clk_hp_i),
      .dst_rst_n_i(rst_hp_n_i),
      .src_axi4   (ext_h_axi4),
      .dst_axi4   (u_ext_h_hp_axi4)
  );
  axi4_id_prefix #(
      .MasterIndex(3'd7)
  ) u_ext_h_prefix (
      .source(u_ext_h_hp_axi4),
      .sink  (u_ext_h_prefixed_axi4)
  );
  axi4_connector u_ext_h_connector (
      .source(u_ext_h_prefixed_axi4),
      .sink  (u_master_axi4[7])
  );

  axi4_data_crossbar u_data_crossbar (
      .clk_i         (clk_hp_i),
      .rst_n_i       (rst_hp_n_i),
      .block_new_i   (s_block_new_hp),
      .mem_pad_mode_i(s_mem_pad_mode_hp),
      .masters       (u_master_axi4),
      .targets       (u_target_axi4),
      .idle_o        (idle_o)
  );

  for (genvar target = 0; target < NumMemoryTargets; target++) begin : gen_memory_target
    axi4_downsizer_64to32 #(
        .WideIdWidth(6)
    ) u_target_downsizer (
        .clk_i  (clk_hp_i),
        .rst_n_i(rst_hp_n_i),
        .wide   (u_target_axi4[target]),
        .narrow (u_target_hp_axi4[target])
    );
    axi4_async_bridge #(
        .DataWidth(32),
        .IdWidth  (1)
    ) u_target_cdc (
        .src_clk_i  (clk_hp_i),
        .src_rst_n_i(rst_hp_n_i),
        .dst_clk_i  (clk_lp_i),
        .dst_rst_n_i(rst_lp_n_i),
        .src_axi4   (u_target_hp_axi4[target]),
        .dst_axi4   (u_gateway_lp_axi4[target])
    );
  end

  axi4_error_slave #(
      .Response(2'b11),
      .IdWidth (6)
  ) u_data_error_slave (
      .clk_i  (clk_hp_i),
      .rst_n_i(rst_hp_n_i),
      .axi4   (u_target_axi4[5])
  );

  axi4_connector u_sram_gateway_connector (
      .source(u_gateway_lp_axi4[0]),
      .sink  (sram_gateway_axi4)
  );
  axi4_connector u_sdram_gateway_connector (
      .source(u_gateway_lp_axi4[1]),
      .sink  (sdram_gateway_axi4)
  );
  axi4_connector u_qpi_gateway_connector (
      .source(u_gateway_lp_axi4[2]),
      .sink  (qpi_gateway_axi4)
  );
  axi4_connector u_opi_gateway_connector (
      .source(u_gateway_lp_axi4[3]),
      .sink  (opi_gateway_axi4)
  );
  axi4_connector u_xpi_gateway_connector (
      .source(u_gateway_lp_axi4[4]),
      .sink  (xpi_gateway_axi4)
  );
endmodule
