// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0
`include "archinfo_integration_metadata.svh"
`include "archinfo_define.svh"

// The locked ArchInfo V2 has a fixed Mini SOC_ID. This owned adapter changes
// only that read-only identity, retaining the managed ABI and build metadata.
module tiny_archinfo (
    input logic         clk_i,
    input logic         rst_n_i,
          apb4_if.slave apb4
);
  apb4_if u_info_apb4_if (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  assign u_info_apb4_if.paddr = apb4.paddr;
  assign u_info_apb4_if.psel = apb4.psel;
  assign u_info_apb4_if.penable = apb4.penable;
  assign u_info_apb4_if.pwrite = apb4.pwrite;
  assign u_info_apb4_if.pwdata = apb4.pwdata;
  assign u_info_apb4_if.pstrb = apb4.pstrb;
  assign u_info_apb4_if.pprot = apb4.pprot;
  assign apb4.pready = u_info_apb4_if.pready;
  assign apb4.pslverr = u_info_apb4_if.pslverr;
  assign apb4.prdata = (apb4.paddr[11:0] == `ARCHINFO_SOC_ID_OFFSET) ?
      32'h5449_4e59 : u_info_apb4_if.prdata;
  apb4_archinfo #(
      .REFERENCE_CLOCK_HZ(24_000_000),
      .SRAM_BYTES        (131072),
      .TOPOLOGY          (32'h2020_0001),
      .FEATURES0         (32'h0000_7ffe),
      .TECHNOLOGY        (32'h0201_0082),
      .BUILD_ID          (`ARCHINFO_INTEGRATION_BUILD_ID),
      .CONFIG_ID         (`ARCHINFO_INTEGRATION_CONFIG_ID),
      .BUILD_STATUS      (`ARCHINFO_INTEGRATION_BUILD_STATUS)
  ) u_archinfo (
      .device_id_i            (128'd0),
      .device_id_valid_i      (1'b0),
      .device_id_read_enable_i(1'b0),
      .apb4                   (u_info_apb4_if)
  );
endmodule
