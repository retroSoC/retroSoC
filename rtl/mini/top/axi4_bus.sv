// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module axi4_bus (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic        clk_i,
    input  logic        rst_n_i,
    axi4_if.slave       mgmt_axi4,
    axi4_if.slave       user_axi4,
    axi4_if.slave       dma_axi4,
    axi4_if.slave       sdio0_axi4,
    axi4_if.slave       sdio1_axi4,
    axi4_if.slave       usb2_axi4,
    axi4_if.slave       spisd_axi4,
    axi4_if.slave       hp_axi4,
    axi4_if.master      cfg_axi4,
    axi4_if.master      system_axi4,
    axi4_if.master      sram_axi4,
    axi4_if.master      sdram_axi4,
    axi4_if.master      psram_axi4,
    axi4_if.master      xpi_axi4,
    axi4_if.master      opipsram_axi4,
    input  logic        user_bus_enable_i,
    output logic        user_bus_idle_o,
    input  logic [1:0]  mem_pad_mode_i,
    input  logic        perf_enable_i,
    input  logic        perf_clear_i,
    output logic        fault_valid_o,
    output logic [31:0] fault_addr_o,
    output logic [3:0]  fault_wstrb_o,
    output logic        fault_reserved_o,
    output logic        fault_access_o,
    output logic [2:0]  fault_master_o,
    output logic [2:0]  fault_code_o,
    output logic [63:0] perf_mgmt_wait_o,
    output logic [63:0] perf_user_wait_o,
    output logic [63:0] perf_dma_wait_o,
    output logic [63:0] perf_sdio0_wait_o,
    output logic [63:0] perf_sdio1_wait_o,
    output logic [63:0] perf_usb2_wait_o,
    output logic [63:0] perf_apb4_periph_wait_o,
    output logic [63:0] perf_apb4_system_wait_o,
    output logic [63:0] perf_sdram_wait_o,
    output logic [63:0] perf_psram_wait_o,
    output logic [63:0] perf_flash_wait_o,
    output logic [63:0] perf_opipsram_wait_o
    // verilog_format: on
);
  localparam int NumMasters = 8;
  localparam int NumTargets = 10;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_master_axi4_if[NumMasters] (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_target_axi4_if[NumTargets] (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  axi4_connector u_mgmt_connector (
      .source(mgmt_axi4),
      .sink  (u_master_axi4_if[0])
  );

  axi4_connector u_user_connector (
      .source(user_axi4),
      .sink  (u_master_axi4_if[1])
  );

  axi4_connector u_dma_connector (
      .source(dma_axi4),
      .sink  (u_master_axi4_if[2])
  );

  axi4_connector u_sdio0_connector (
      .source(sdio0_axi4),
      .sink  (u_master_axi4_if[3])
  );

  axi4_connector u_sdio1_connector (
      .source(sdio1_axi4),
      .sink  (u_master_axi4_if[4])
  );

  axi4_connector u_spisd_connector (
      .source(spisd_axi4),
      .sink  (u_master_axi4_if[5])
  );

  axi4_connector u_usb2_connector (
      .source(usb2_axi4),
      .sink  (u_master_axi4_if[6])
  );

  axi4_connector u_hp_connector (
      .source(hp_axi4),
      .sink  (u_master_axi4_if[7])
  );

  axi4_connector u_cfg_connector (
      .source(u_target_axi4_if[0]),
      .sink  (cfg_axi4)
  );

  axi4_connector u_apb_connector (
      .source(u_target_axi4_if[1]),
      .sink  (system_axi4)
  );

  axi4_connector u_ram_connector (
      .source(u_target_axi4_if[2]),
      .sink  (sram_axi4)
  );

  axi4_connector u_sdram_connector (
      .source(u_target_axi4_if[3]),
      .sink  (sdram_axi4)
  );

  axi4_connector u_psram_connector (
      .source(u_target_axi4_if[4]),
      .sink  (psram_axi4)
  );

  axi4_connector u_xpi_connector (
      .source(u_target_axi4_if[5]),
      .sink  (xpi_axi4)
  );

  axi4_connector u_opipsram_connector (
      .source(u_target_axi4_if[9]),
      .sink  (opipsram_axi4)
  );

  axi4_interconnect #(
      .NumMasters(NumMasters),
      .NumTargets(NumTargets)
  ) u_axi4_interconnect (
      .clk_i                  (clk_i),
      .rst_n_i                (rst_n_i),
      .masters                (u_master_axi4_if),
      .targets                (u_target_axi4_if),
      .user_bus_enable_i      (user_bus_enable_i),
      .user_bus_idle_o        (user_bus_idle_o),
      .mem_pad_mode_i         (mem_pad_mode_i),
      .perf_enable_i          (perf_enable_i),
      .perf_clear_i           (perf_clear_i),
      .fault_valid_o          (fault_valid_o),
      .fault_addr_o           (fault_addr_o),
      .fault_wstrb_o          (fault_wstrb_o),
      .fault_reserved_o       (fault_reserved_o),
      .fault_access_o         (fault_access_o),
      .fault_master_o         (fault_master_o),
      .fault_code_o           (fault_code_o),
      .perf_mgmt_wait_o       (perf_mgmt_wait_o),
      .perf_user_wait_o       (perf_user_wait_o),
      .perf_dma_wait_o        (perf_dma_wait_o),
      .perf_sdio0_wait_o      (perf_sdio0_wait_o),
      .perf_sdio1_wait_o      (perf_sdio1_wait_o),
      .perf_usb2_wait_o       (perf_usb2_wait_o),
      .perf_apb4_periph_wait_o(perf_apb4_periph_wait_o),
      .perf_apb4_system_wait_o(perf_apb4_system_wait_o),
      .perf_sdram_wait_o      (perf_sdram_wait_o),
      .perf_psram_wait_o      (perf_psram_wait_o),
      .perf_flash_wait_o      (perf_flash_wait_o),
      .perf_opipsram_wait_o   (perf_opipsram_wait_o)
  );

  axi4_error_slave #(
      .Response(2'b11)
  ) u_decode_error_slave (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .axi4   (u_target_axi4_if[7])
  );

  axi4_error_slave #(
      .Response(2'b11)
  ) u_retired_spisd_error_slave (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .axi4   (u_target_axi4_if[6])
  );

  axi4_error_slave #(
      .Response(2'b10)
  ) u_slave_error_slave (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .axi4   (u_target_axi4_if[8])
  );
endmodule
